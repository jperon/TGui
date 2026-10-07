-- Summary: HTTP edge for TGui (index/static assets + GraphQL POST endpoint).
-- Responsibilities:
-- - Serve SPA shell (`/`) and static frontend files (`/.*`).
-- - Decode GraphQL JSON requests and delegate execution to graphql.executor.
-- - Build auth context from Bearer token before resolver execution.
-- Key Flows:
-- - POST /graphql -> extract token -> core.auth.validate_session -> graphql.execute.
-- - GET / -> index.render ; GET /assets -> filesystem lookup under FRONTEND_DIR.
-- Depends on:
-- - http.server, graphql.executor, core.auth, core.config, index.
-- Used by:
-- - backend/init.moon runtime bootstrap (`http_server.start`).

http = require 'http.server'
fiber = require 'fiber'
json = require 'json'
fio = require 'fio'
log = require 'log'

graphql = require 'graphql.executor'
index  = require 'index'
{ :FRONTEND_DIR } = require 'core.config'

mime_types = {
  txt:  'text/plain'
  html: 'text/html'
  css:  'text/css'
  js:   'application/javascript'
  json: 'application/json'
  yaml: 'application/x-yaml'
  ico:  'image/x-icon'
  png:  'image/png'
  svg:  'image/svg+xml'
  zst:  'application/zstd'
}

ext_of = (path) ->
  path\match('[^.]+$') or ''

read_file = (path) ->
  f = fio.open path, {'O_RDONLY'}
  return nil unless f
  content = f\read!
  f\close!
  content

-- Refuse anything that is not a plain URL path rooted under FRONTEND_DIR.
-- Plan Task 3 / spec §7: no `..`, no `//`, no NUL byte, no percent-encoded
-- traversal (`%2e%2e`), no absolute path (URI form, drive letter, UNC) and no
-- relative path. Pure function (no filesystem access): returns the disk path
-- under FRONTEND_DIR, or nil when the request must be refused.
safe_static_path = (url_path) ->
  return nil unless type(url_path) == 'string'
  return nil if url_path == ''
  -- URL paths are rooted (`/src/app.js`); a bare drive/URI/UNC path or a
  -- relative path never is.
  return nil unless url_path\sub(1, 1) == '/'
  return nil if url_path\find '\0', 1, true
  return nil if url_path\find '\\', 1, true
  return nil if url_path\find ':', 1, true
  return nil if url_path\find '..', 1, true
  return nil if url_path\find '//', 1, true
  lowered = url_path\lower!
  return nil if lowered\find '%2e', 1, true
  return nil if lowered\find '%2f', 1, true
  return nil if lowered\find '%5c', 1, true
  disk_path = FRONTEND_DIR .. url_path
  prefix = FRONTEND_DIR .. '/'
  return nil unless disk_path\sub(1, #prefix) == prefix
  disk_path

serve_static = (req) ->
  -- Requests to / are handled by serve_index; this path serves only assets.
  disk_path = safe_static_path req.path
  unless disk_path
    return { status: 404, headers: {}, body: 'Not found' }
  content = read_file disk_path
  unless content
    return { status: 404, headers: {}, body: 'Not found' }

  ext = ext_of disk_path
  mime = mime_types[ext] or 'application/octet-stream'
  { status: 200, headers: { 'content-type': mime }, body: content }

auth_mod = require 'core.auth'
-- Admin check shared with the GraphQL resolvers (group membership).
{ :require_admin } = require 'resolvers.utils'

-- Extract bearer token from Authorization header
extract_token = (req) ->
  auth_header = req.headers and req.headers['authorization']
  return nil unless auth_header
  tok = auth_header\match '^[Bb]earer%s+(.+)$'
  tok

handle_graphql = (req) ->
  ok, body = pcall -> json.decode req\read_cached!
  unless ok
    return req\render { status: 400, json: { errors: { {message: 'Invalid JSON'} } } }

  query     = body.query or ''
  variables = body.variables or {}
  op_name   = body.operationName
  op_name   = nil unless type(op_name) == 'string'

  -- Build context with authenticated user (if any)
  ctx = {}
  token = extract_token req
  if token
    session = auth_mod.validate_session token
    if session
      ctx.token   = token
      ctx.user_id = session.user_id

  result = graphql.execute { query, variables, op_name, context: ctx }
  req\render { status: 200, json: result }

serve_index = (req) ->
  -- `index` (require 'index') retourne directement la fonction de rendu.
  { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' }, body: index! }

-- Analyse la query string de /export (une seule petite fonction pure) :
-- seules les valeurs littérales 'true' comptent, les paramètres inconnus
-- ou malformés sont ignorés.
parse_export_query = (query) ->
  params = { compress: false, include_data: false }
  return params unless type(query) == 'string'
  for pair in query\gmatch '[^&]+'
    key, value = pair\match '^([^=]+)=(.*)$'
    if key == 'compress'
      params.compress = value == 'true'
    elseif key == 'includeData'
      params.include_data = value == 'true'
  params

-- Handle snapshot export (spec §7 : admin = appartenance au groupe, via
-- resolvers.utils.require_admin — plus de test sur le nom d'utilisateur).
handle_export = (req) ->
  params = parse_export_query req.query
  include_data = params.include_data
  compress = params.compress

  -- Check authentication
  token = extract_token req
  unless token
    return { status: 401, headers: {}, body: 'Unauthorized' }

  session = auth_mod.validate_session token
  unless session
    return { status: 401, headers: {}, body: 'Invalid token' }

  -- Check admin permissions (group membership, not username)
  ok_admin, err_admin = pcall require_admin, { user_id: session.user_id }
  unless ok_admin
    if tostring(err_admin)\match 'Forbidden'
      return { status: 403, headers: {}, body: 'Admin access required' }
    return { status: 401, headers: {}, body: 'Unauthorized' }

  -- Build snapshot
  export_resolvers = require 'resolvers.export_resolvers'
  snap = export_resolvers.build_snapshot include_data
  yaml_str = require('yaml').encode snap

  if compress
    -- Use ZSTD-FFI compression
    ZstdWrapper = require 'zstd_wrapper'
    compressed, err = ZstdWrapper.compress_zstd yaml_str, {level: 1}
    if err
      return { status: 500, headers: {}, body: "Compression failed: #{err}" }

    -- Set filename based on content
    filename = if include_data then 'backup.tdb.yaml.zst' else 'schema.tdb.yaml.zst'

    return {
      status: 200
      headers: {
        'content-type': 'application/zstd'
        'content-disposition': "attachment; filename=\"#{filename}\""
        'content-length': #compressed
      }
      body: compressed
    }
  else
    -- Serve as plain YAML
    filename = if include_data then 'backup.tdb.yaml' else 'schema.tdb.yaml'

    return {
      status: 200
      headers: {
        'content-type': 'text/yaml; charset=utf-8'
        'content-disposition': "attachment; filename=\"#{filename}\""
        'content-length': #yaml_str
      }
      body: yaml_str
    }

start = (opts = {}) ->
  host = opts.host or '0.0.0.0'
  port = opts.port or 8080

  server = http.new host, port, { log_requests: true }

  server\route { path: '/graphql', method: 'POST' }, handle_graphql
  server\route { path: '/export', method: 'GET' }, handle_export
  server\route { path: '/' },    serve_index
  server\route { path: '/.*' },  serve_static

  server\start!
  log.info "tdb HTTP server listening on #{host}:#{port}"

{ :start, :safe_static_path, :serve_static, :handle_export, :parse_export_query }
