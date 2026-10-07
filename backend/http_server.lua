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
  txt = 'text/plain',
  html = 'text/html',
  css = 'text/css',
  js = 'application/javascript',
  json = 'application/json',
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
    body = index()
  }
end
local handle_export
handle_export = function(req)
  local query_params = {
    compress = 'false',
    includeData = 'false'
  }
  local full_url = nil
  log.info("Export request: path=" .. tostring(req.path) .. ", method=" .. tostring(req.method) .. ", headers available=" .. tostring(req.headers and 'yes' or 'no'))
  query_params = {
    compress = 'false',
    includeData = 'false'
  }
  if req.query and type(req.query) == 'string' then
    log.info("Export request: query=" .. tostring(req.query))
    for pair in req.query:gmatch('[^&]+') do
      local key, value = pair:match('([^=]+)=([^=]*)')
      if key and value then
        query_params[key] = value
        log.info("Export request: parsed " .. tostring(key) .. "=" .. tostring(value))
      end
    end
  end
  log.info("Export request: using compress=" .. tostring(query_params.compress) .. ", includeData=" .. tostring(query_params.includeData))
  local include_data = query_params.includeData == 'true'
  local compress = query_params.compress == 'true'
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
  local user = auth_mod.get_user_by_id(session.user_id)
  if not (user and user.username == 'admin') then
    return {
      status = 403,
      headers = { },
      body = 'Admin access required'
    }
  end
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
  serve_static = serve_static
}
