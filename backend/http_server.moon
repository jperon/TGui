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

mime_types =
  html: 'text/html; charset=utf-8'
  css:  'text/css; charset=utf-8'
  js:   'application/javascript; charset=utf-8'
  json: 'application/json; charset=utf-8'
  ico:  'image/x-icon'
  png:  'image/png'
  svg:  'image/svg+xml'
  gz:   'application/gzip'

ext_of = (path) ->
  path\match('[^.]+$') or ''

read_file = (path) ->
  f = fio.open path, {'O_RDONLY'}
  return nil unless f
  content = f\read!
  f\close!
  content

serve_static = (req) ->
  url_path = req.path
  -- Requests to / are handled by serve_index; this path serves only assets.
  disk_path = FRONTEND_DIR .. url_path
  content = read_file disk_path
  unless content
    return { status: 404, headers: {}, body: 'Not found' }

  ext = ext_of disk_path
  mime = mime_types[ext] or 'application/octet-stream'
  { status: 200, headers: { 'content-type': mime }, body: content }

auth_mod = require 'core.auth'

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
  { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' }, body: index.render! }

-- Handle compressed snapshot export
handle_export = (req) ->
  -- Parse query parameters - the Tarantool HTTP server doesn't include query params in req.path
  -- We need to access them differently

  query_params = {
    compress: 'false'
    includeData: 'false'
  }

  -- Try to get the full URL from various sources
  full_url = nil

  -- Check if there's a way to get the original request URL
  -- The issue is that req.path only contains "/export" without query params
  -- We need to find where the query parameters are stored

  -- For now, let's use a simple approach: check the request object more thoroughly
  -- Log what we have access to for debugging
  log.info "Export request: path=#{req.path}, method=#{req.method}, headers available=#{req.headers and 'yes' or 'no'}"

  -- Try to get query parameters from headers or other request properties
  -- This is a limitation of the current Tarantool HTTP server implementation

  -- As a temporary solution, we'll use the fact that we can detect the presence
  query_params = { compress: 'false', includeData: 'false' }

  if req.query and type(req.query) == 'string'
    log.info "Export request: query=#{req.query}"
    -- Parse key=value pairs
    for pair in req.query\gmatch('[^&]+')
      key, value = pair\match('([^=]+)=([^=]*)')
      if key and value
        query_params[key] = value
        log.info "Export request: parsed #{key}=#{value}"

  log.info "Export request: using compress=#{query_params.compress}, includeData=#{query_params.includeData}"

  include_data = query_params.includeData == 'true'
  compress = query_params.compress == 'true'

  -- Check authentication
  token = extract_token req
  unless token
    return { status: 401, headers: {}, body: 'Unauthorized' }

  session = auth_mod.validate_session token
  unless session
    return { status: 401, headers: {}, body: 'Invalid token' }

  -- Check admin permissions
  user = auth_mod.get_user_by_id session.user_id
  unless user and user.username == 'admin'
    return { status: 403, headers: {}, body: 'Admin access required' }

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

{ :start }
