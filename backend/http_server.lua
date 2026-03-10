local http = require('http.server')
local fiber = require('fiber')
local json = require('json')
local fio = require('fio')
local log = require('log')
local graphql = require('graphql.executor')
local index = require('index')
local FRONTEND_DIR
FRONTEND_DIR = require('core.config').FRONTEND_DIR
local mime_types = {
  html = 'text/html; charset=utf-8',
  css = 'text/css; charset=utf-8',
  js = 'application/javascript; charset=utf-8',
  json = 'application/json; charset=utf-8',
  ico = 'image/x-icon',
  png = 'image/png',
  svg = 'image/svg+xml'
}
local ext_of
ext_of = function(path)
  return path:match('[^.]+$') or ''
end
local read_file
read_file = function(path)
  local f = fio.open(path, {
    'O_RDONLY'
  })
  if not (f) then
    return nil
  end
  local content = f:read()
  f:close()
  return content
end
local serve_static
serve_static = function(req)
  local url_path = req.path
  local disk_path = FRONTEND_DIR .. url_path
  local content = read_file(disk_path)
  if not (content) then
    return {
      status = 404,
      headers = { },
      body = 'Not found'
    }
  end
  local ext = ext_of(disk_path)
  local mime = mime_types[ext] or 'application/octet-stream'
  return {
    status = 200,
    headers = {
      ['content-type'] = mime
    },
    body = content
  }
end
local auth_mod = require('core.auth')
local extract_token
extract_token = function(req)
  local auth_header = req.headers and req.headers['authorization']
  if not (auth_header) then
    return nil
  end
  local tok = auth_header:match('^[Bb]earer%s+(.+)$')
  return tok
end
local handle_graphql
handle_graphql = function(req)
  local ok, body = pcall(function()
    return json.decode(req:read_cached())
  end)
  if not (ok) then
    return req:render({
      status = 400,
      json = {
        errors = {
          {
            message = 'Invalid JSON'
          }
        }
      }
    })
  end
  local query = body.query or ''
  local variables = body.variables or { }
  local op_name = body.operationName
  if not (type(op_name) == 'string') then
    op_name = nil
  end
  local ctx = { }
  local token = extract_token(req)
  if token then
    local session = auth_mod.validate_session(token)
    if session then
      ctx.token = token
      ctx.user_id = session.user_id
    end
  end
  local result = graphql.execute({
    query,
    variables,
    op_name,
    context = ctx
  })
  return req:render({
    status = 200,
    json = result
  })
end
local serve_index
serve_index = function(req)
  return {
    status = 200,
    headers = {
      ['content-type'] = 'text/html; charset=utf-8'
    },
    body = index.render()
  }
end
local start
start = function(opts)
  if opts == nil then
    opts = { }
  end
  local host = opts.host or '0.0.0.0'
  local port = opts.port or 8080
  local server = http.new(host, port, {
    log_requests = true
  })
  server:route({
    path = '/graphql',
    method = 'POST'
  }, handle_graphql)
  server:route({
    path = '/'
  }, serve_index)
  server:route({
    path = '/.*'
  }, serve_static)
  server:start()
  return log.info("tdb HTTP server listening on " .. tostring(host) .. ":" .. tostring(port))
end
return {
  start = start
}
