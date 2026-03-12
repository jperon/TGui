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

start = (opts = {}) ->
  host = opts.host or '0.0.0.0'
  port = opts.port or 8080

  server = http.new host, port, { log_requests: true }

  server\route { path: '/graphql', method: 'POST' }, handle_graphql
  server\route { path: '/' },    serve_index
  server\route { path: '/.*' },  serve_static

  server\start!
  log.info "tdb HTTP server listening on #{host}:#{port}"

{ :start }
