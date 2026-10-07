local R = require('tests.runner')
local http_server = require('http_server')
local auth = require('core.auth')
local perms = require('core.permissions')
local FRONTEND_DIR
FRONTEND_DIR = require('core.config').FRONTEND_DIR
local SFX = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
local mk_req
mk_req = function(path)
  return {
    path = path,
    method = 'GET',
    headers = { }
  }
end
local mk_export_req
mk_export_req = function(opts)
  opts = opts or { }
  local headers = { }
  if opts.token then
    headers['authorization'] = "Bearer " .. tostring(opts.token)
  end
  return {
    path = '/export',
    method = 'GET',
    query = opts.query,
    headers = headers
  }
end
local admin_group_id
admin_group_id = function()
  local _list_0 = perms.list_groups()
  for _index_0 = 1, #_list_0 do
    local g = _list_0[_index_0]
    if g.name == 'admin' then
      return g.id
    end
  end
  return nil
end
R.describe("safe_static_path — assets frontend acceptés", function()
  R.it("accepte /src/app.js", function()
    return R.eq(http_server.safe_static_path('/src/app.js'), tostring(FRONTEND_DIR) .. "/src/app.js")
  end)
  R.it("accepte /css/app.css", function()
    return R.eq(http_server.safe_static_path('/css/app.css'), tostring(FRONTEND_DIR) .. "/css/app.css")
  end)
  return R.it("accepte /vendor/tui-grid.bundle.js", function()
    return R.eq(http_server.safe_static_path('/vendor/tui-grid.bundle.js'), tostring(FRONTEND_DIR) .. "/vendor/tui-grid.bundle.js")
  end)
end)
R.describe("safe_static_path — traversal refusé", function()
  R.it("refuse /../backend/init.lua", function()
    return R.is_nil(http_server.safe_static_path('/../backend/init.lua'))
  end)
  R.it("refuse /src/../../etc/passwd", function()
    return R.is_nil(http_server.safe_static_path('/src/../../etc/passwd'))
  end)
  R.it("refuse la variante encodée %2e%2e", function()
    return R.is_nil(http_server.safe_static_path('/src/%2e%2e/etc/passwd'))
  end)
  R.it("refuse la variante encodée %2E%2E (majuscules)", function()
    return R.is_nil(http_server.safe_static_path('/src/%2E%2E/etc/passwd'))
  end)
  R.it("refuse le double slash //", function()
    return R.is_nil(http_server.safe_static_path('/vendor//app.js'))
  end)
  R.it("refuse l'octet nul (troncature de chemin côté C)", function()
    return R.is_nil(http_server.safe_static_path('/src/app.js\0.png'))
  end)
  return R.it("refuse un chemin UNC (backslash)", function()
    return R.is_nil(http_server.safe_static_path('\\\\server\\share\\app.js'))
  end)
end)
R.describe("safe_static_path — chemins absolus refusés", function()
  R.it("refuse l'URI absolue http://127.0.0.1/etc/passwd", function()
    return R.is_nil(http_server.safe_static_path('http://127.0.0.1/etc/passwd'))
  end)
  R.it("refuse la lettre de lecteur C:/Windows/win.ini", function()
    return R.is_nil(http_server.safe_static_path('C:/Windows/win.ini'))
  end)
  R.it("refuse le chemin relatif src/app.js", function()
    return R.is_nil(http_server.safe_static_path('src/app.js'))
  end)
  return R.it("refuse /../etc/passwd (absolu hors de la racine)", function()
    return R.is_nil(http_server.safe_static_path('/../etc/passwd'))
  end)
end)
R.describe("serve_static — jamais de contenu hors de FRONTEND_DIR", function()
  R.it("contrôle : /css/app.css est servi (200)", function()
    local res = http_server.serve_static(mk_req('/css/app.css'))
    return R.eq(res.status, 200)
  end)
  R.it("/../backend/init.lua -> 404, jamais le contenu", function()
    local res = http_server.serve_static(mk_req('/../backend/init.lua'))
    R.eq(res.status, 404)
    return R.nok(tostring(res.body):find('package.path', 1, true))
  end)
  R.it("/src/%2e%2e/../etc/passwd -> 404", function()
    local res = http_server.serve_static(mk_req('/src/%2e%2e/etc/passwd'))
    return R.eq(res.status, 404)
  end)
  R.it("l'octet nul ne tronque pas le chemin -> 404", function()
    local res = http_server.serve_static(mk_req('/src/app.js\0.png'))
    return R.eq(res.status, 404)
  end)
  return R.it("/etc/passwd -> 404 (le join reste sous FRONTEND_DIR)", function()
    local res = http_server.serve_static(mk_req('/etc/passwd'))
    return R.eq(res.status, 404)
  end)
end)
R.describe("parse_export_query — analyse propre de la requête", function()
  R.it("query absente -> défauts false/false", function()
    local q = http_server.parse_export_query(nil)
    R.eq(q.compress, false)
    return R.eq(q.include_data, false)
  end)
  R.it("compress=true&includeData=true -> true/true", function()
    local q = http_server.parse_export_query('compress=true&includeData=true')
    R.eq(q.compress, true)
    return R.eq(q.include_data, true)
  end)
  R.it("valeurs autres que 'true' -> false/false", function()
    local q = http_server.parse_export_query('compress=yes&includeData=1')
    R.eq(q.compress, false)
    return R.eq(q.include_data, false)
  end)
  return R.it("paramètres inconnus ignorés", function()
    local q = http_server.parse_export_query('foo=bar&includeData=true')
    R.eq(q.compress, false)
    return R.eq(q.include_data, true)
  end)
end)
R.describe("handle_export — authentification", function()
  R.it("sans token -> 401", function()
    local res = http_server.handle_export(mk_export_req())
    return R.eq(res.status, 401)
  end)
  return R.it("token invalide -> 401", function()
    local res = http_server.handle_export(mk_export_req({
      token = 'not-a-token'
    }))
    return R.eq(res.status, 401)
  end)
end)
return R.describe("handle_export — admin = groupe admin, plus le nom 'admin'", function()
  R.it("utilisateur hors groupe admin -> 403", function()
    local user = auth.create_user("export_user_" .. tostring(SFX), "export_user_" .. tostring(SFX) .. "@test.local", "pass1234")
    local sess = auth.create_session(user.id)
    local res = http_server.handle_export(mk_export_req({
      token = sess.token
    }))
    R.eq(res.status, 403)
    auth.delete_session(sess.token)
    return box.space._tdb_users:delete(user.id)
  end)
  R.it("membre du groupe admin, nom != 'admin' -> 200 (YAML)", function()
    local user = auth.create_user("export_admin_" .. tostring(SFX), "export_admin_" .. tostring(SFX) .. "@test.local", "pass1234")
    local gid = admin_group_id()
    perms.add_member(user.id, gid)
    local sess = auth.create_session(user.id)
    local res = http_server.handle_export(mk_export_req({
      token = sess.token
    }))
    R.eq(res.status, 200)
    R.matches(tostring(res.headers['content-type']), 'text/yaml')
    R.matches(tostring(res.headers['content-disposition']), 'schema%.tdb%.yaml')
    perms.remove_member(user.id, gid)
    auth.delete_session(sess.token)
    return box.space._tdb_users:delete(user.id)
  end)
  return R.it("admin historique + includeData=true -> backup.tdb.yaml", function()
    local admin = auth.get_user_by_username('admin')
    local sess = auth.create_session(admin.id)
    local res = http_server.handle_export(mk_export_req({
      token = sess.token,
      query = 'includeData=true'
    }))
    R.eq(res.status, 200)
    R.matches(tostring(res.headers['content-disposition']), 'backup%.tdb%.yaml')
    R.ok(#res.body > 10)
    return auth.delete_session(sess.token)
  end)
end)
