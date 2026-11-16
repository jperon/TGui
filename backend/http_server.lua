local http = require('http.server')
local fiber = require('fiber')
local json = require('json')
local fio = require('fio')
local log = require('log')
local graphql = require('graphql.executor')
local index = require('index')
local FRONTEND_DIR, set_request_slice
do
  local _obj_0 = require('core.config')
  FRONTEND_DIR, set_request_slice = _obj_0.FRONTEND_DIR, _obj_0.set_request_slice
end
local mime_types = {
  txt = 'text/plain',
  html = 'text/html',
  css = 'text/css',
  js = 'application/javascript',
  json = 'application/json',
  wasm = 'application/wasm',
  yaml = 'application/x-yaml',
  ico = 'image/x-icon',
  png = 'image/png',
  svg = 'image/svg+xml',
  zst = 'application/zstd'
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
local safe_static_path
safe_static_path = function(url_path)
  if not (type(url_path) == 'string') then
    return nil
  end
  if url_path == '' then
    return nil
  end
  if not (url_path:sub(1, 1) == '/') then
    return nil
  end
  if url_path:find('\0', 1, true) then
    return nil
  end
  if url_path:find('\\', 1, true) then
    return nil
  end
  if url_path:find(':', 1, true) then
    return nil
  end
  if url_path:find('..', 1, true) then
    return nil
  end
  if url_path:find('//', 1, true) then
    return nil
  end
  local lowered = url_path:lower()
  if lowered:find('%2e', 1, true) then
    return nil
  end
  if lowered:find('%2f', 1, true) then
    return nil
  end
  if lowered:find('%5c', 1, true) then
    return nil
  end
  local disk_path = FRONTEND_DIR .. url_path
  local prefix = FRONTEND_DIR .. '/'
  if not (disk_path:sub(1, #prefix) == prefix) then
    return nil
  end
  return disk_path
end
local serve_static
serve_static = function(req)
  local disk_path = safe_static_path(req.path)
  if not (disk_path) then
    return {
      status = 404,
      headers = { },
      body = 'Not found'
    }
  end
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
local require_admin
require_admin = require('resolvers.utils').require_admin
local extract_token
extract_token = function(req)
  local auth_header = req.headers and req.headers['authorization']
  if not (auth_header) then
    return nil
  end
  local tok = auth_header:match('^[Bb]earer%s+(.+)$')
  return tok
end
local has_widget_header
has_widget_header = function(req)
  local headers = req and req.headers
  if not (type(headers) == 'table') then
    return false
  end
  for name, value in pairs(headers) do
    if type(name) == 'string' and string.lower(name) == 'x-tdb-widget' then
      return value == '1' or value == true
    end
  end
  return false
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
  if req.peer and req.peer.host then
    ctx.client_addr = req.peer.host
  end
  local token = extract_token(req)
  if token then
    local session = auth_mod.validate_session(token)
    if session then
      ctx.token = token
      ctx.user_id = session.user_id
      local user = auth_mod.get_user_by_id(session.user_id)
      ctx.must_change_password = user and user.must_change_password or false
    end
  end
  if has_widget_header(req) then
    ctx.widget = true
  end
  set_request_slice()
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
    body = index()
  }
end
local parse_export_query
parse_export_query = function(query)
  local params = {
    compress = false,
    include_data = false
  }
  if not (type(query) == 'string') then
    return params
  end
  for pair in query:gmatch('[^&]+') do
    local key, value = pair:match('^([^=]+)=(.*)$')
    if key == 'compress' then
      params.compress = value == 'true'
    elseif key == 'includeData' then
      params.include_data = value == 'true'
    end
  end
  return params
end
local handle_export
handle_export = function(req)
  local params = parse_export_query(req.query)
  local include_data = params.include_data
  local compress = params.compress
  local token = extract_token(req)
  if not (token) then
    return {
      status = 401,
      headers = { },
      body = 'Unauthorized'
    }
  end
  local session = auth_mod.validate_session(token)
  if not (session) then
    return {
      status = 401,
      headers = { },
      body = 'Invalid token'
    }
  end
  local exp_user = auth_mod.get_user_by_id(session.user_id)
  local export_ctx = {
    user_id = session.user_id,
    must_change_password = exp_user and exp_user.must_change_password or false
  }
  local ok_admin, err_admin = pcall(require_admin, export_ctx)
  if not (ok_admin) then
    if tostring(err_admin):match('PASSWORD_CHANGE_REQUIRED') then
      return {
        status = 403,
        headers = { },
        body = 'Password change required'
      }
    end
    if tostring(err_admin):match('Forbidden') then
      return {
        status = 403,
        headers = { },
        body = 'Admin access required'
      }
    end
    return {
      status = 401,
      headers = { },
      body = 'Unauthorized'
    }
  end
  set_request_slice()
  local export_resolvers = require('resolvers.export_resolvers')
  local snap = export_resolvers.build_snapshot(include_data)
  local yaml_str = require('yaml').encode(snap)
  if compress then
    local ZstdWrapper = require('zstd_wrapper')
    local compressed, err = ZstdWrapper.compress_zstd(yaml_str, {
      level = 1
    })
    if err then
      return {
        status = 500,
        headers = { },
        body = "Compression failed: " .. tostring(err)
      }
    end
    local filename
    if include_data then
      filename = 'backup.tdb.yaml.zst'
    else
      filename = 'schema.tdb.yaml.zst'
    end
    return {
      status = 200,
      headers = {
        ['content-type'] = 'application/zstd',
        ['content-disposition'] = "attachment; filename=\"" .. tostring(filename) .. "\"",
        ['content-length'] = #compressed
      },
      body = compressed
    }
  else
    local filename
    if include_data then
      filename = 'backup.tdb.yaml'
    else
      filename = 'schema.tdb.yaml'
    end
    return {
      status = 200,
      headers = {
        ['content-type'] = 'text/yaml; charset=utf-8',
        ['content-disposition'] = "attachment; filename=\"" .. tostring(filename) .. "\"",
        ['content-length'] = #yaml_str
      },
      body = yaml_str
    }
  end
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
    path = '/export',
    method = 'GET'
  }, handle_export)
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
  start = start,
  safe_static_path = safe_static_path,
  serve_static = serve_static,
  handle_export = handle_export,
  parse_export_query = parse_export_query,
  has_widget_header = has_widget_header,
  handle_graphql = handle_graphql
}
