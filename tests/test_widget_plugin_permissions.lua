local R = require('tests.runner')
local wpr = require('resolvers.widget_plugin_resolvers')
local auth = require('core.auth')
local perms_mod = require('core.permissions')
local executor = require('graphql.executor')
local SUFFIX = tostring(math.random(100000, 999999))
local SCRIPT_CS = [[module.exports = ({ render }) ->
  render '<div>Hello</div>'
]]
local TEMPLATE_PUG = [[div.widget
  h3 Hello Plugin
]]
local admin_user = auth.get_user_by_username('admin')
R.ok(admin_user, 'fixture: admin user must exist')
local ADMIN_CTX = {
  user_id = admin_user.id
}
local make_actor
make_actor = function(prefix, level)
  local user = auth.create_user(tostring(prefix) .. "_" .. tostring(SUFFIX), tostring(prefix) .. "_" .. tostring(SUFFIX) .. "@test.local", 'pass1234')
  local grp = perms_mod.create_group("wpg_" .. tostring(prefix) .. "_" .. tostring(SUFFIX), '')
  if level then
    perms_mod.grant(grp.id, '*', nil, level)
  end
  perms_mod.add_member(user.id, grp.id)
  return {
    user = user,
    group = grp,
    ctx = {
      user_id = user.id
    }
  }
end
local actor_write = make_actor('wpwrite', 'write')
local actor_read = make_actor('wpread', 'read')
local actor_admin_perm = make_actor('wpadminperm', 'admin')
local plugin_input
plugin_input = function(name)
  return {
    name = name,
    description = 'permissions test',
    scriptLanguage = 'coffeescript',
    templateLanguage = 'pug',
    scriptCode = SCRIPT_CS,
    templateCode = TEMPLATE_PUG
  }
end
local plugin_exists
plugin_exists = function(name)
  local p = box.space._tdb_widget_plugins.index.by_name:get(name)
  return p ~= nil
end
R.describe("WidgetPlugins — le code du plugin exige le niveau admin", function()
  R.it("utilisateur `write` global : createWidgetPlugin -> Forbidden", function()
    local name = "denied_create_" .. tostring(SUFFIX)
    R.raises((function()
      return wpr.Mutation.createWidgetPlugin({ }, {
        input = plugin_input(name)
      }, actor_write.ctx)
    end), 'Forbidden')
    return R.nok(plugin_exists(name), 'aucune définition ne doit être créée')
  end)
  R.it("utilisateur `write` global : updateWidgetPlugin -> Forbidden", function()
    local name = "denied_update_" .. tostring(SUFFIX)
    local created = wpr.Mutation.createWidgetPlugin({ }, {
      input = plugin_input(name)
    }, ADMIN_CTX)
    R.raises((function()
      return wpr.Mutation.updateWidgetPlugin({ }, {
        id = created.id,
        input = {
          scriptCode = 'module.exports = -> null'
        }
      }, actor_write.ctx)
    end), 'Forbidden')
    local stored = box.space._tdb_widget_plugins:get(created.id)
    R.eq(stored[6], SCRIPT_CS, 'le script stocké ne doit pas changer')
    return wpr.Mutation.deleteWidgetPlugin({ }, {
      id = created.id
    }, ADMIN_CTX)
  end)
  R.it("utilisateur `read` global : createWidgetPlugin -> Forbidden", function()
    return R.raises((function()
      return wpr.Mutation.createWidgetPlugin({ }, {
        input = plugin_input("denied_read_" .. tostring(SUFFIX))
      }, actor_read.ctx)
    end), 'Forbidden')
  end)
  R.it("admin (groupe admin) : createWidgetPlugin et updateWidgetPlugin -> OK", function()
    local name = "admin_ok_" .. tostring(SUFFIX)
    local res = wpr.Mutation.createWidgetPlugin({ }, {
      input = plugin_input(name)
    }, ADMIN_CTX)
    R.ok(res.id, 'admin doit pouvoir créer')
    local upd = wpr.Mutation.updateWidgetPlugin({ }, {
      id = res.id,
      input = {
        scriptCode = "module.exports = ({ render }) ->\n  render '<b>ok</b>'\n"
      }
    }, ADMIN_CTX)
    R.eq(upd.id, res.id)
    R.matches(upd.scriptCode, 'ok')
    return wpr.Mutation.deleteWidgetPlugin({ }, {
      id = res.id
    }, ADMIN_CTX)
  end)
  R.it("permission `admin` globale sans groupe admin : autorisé", function()
    local name = "admin_perm_" .. tostring(SUFFIX)
    local res = wpr.Mutation.createWidgetPlugin({ }, {
      input = plugin_input(name)
    }, actor_admin_perm.ctx)
    R.ok(res.id, 'le niveau admin suffit')
    return wpr.Mutation.deleteWidgetPlugin({ }, {
      id = res.id
    }, actor_admin_perm.ctx)
  end)
  return R.it("chemin GraphQL : mutation createWidgetPlugin refusée pour `write`", function()
    require('resolvers.init').reinit()
    local name = "denied_gql_" .. tostring(SUFFIX)
    local vars = {
      input = plugin_input(name)
    }
    local res = executor.execute({
      query = 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id } }',
      variables = vars,
      context = actor_write.ctx
    })
    R.ok(res.errors, 'la mutation doit échouer')
    R.matches(tostring(res.errors[1].message), 'Forbidden')
    return R.nok(plugin_exists(name), 'aucune définition ne doit être créée')
  end)
end)
local _list_0 = {
  actor_write,
  actor_read,
  actor_admin_perm
}
for _index_0 = 1, #_list_0 do
  local a = _list_0[_index_0]
  local _list_1 = box.space._tdb_sessions.index.by_user:select({
    a.user.id
  })
  for _index_1 = 1, #_list_1 do
    local s = _list_1[_index_1]
    box.space._tdb_sessions:delete(s[1])
  end
  perms_mod.delete_group(a.group.id)
  box.space._tdb_users:delete(a.user.id)
end
return require('resolvers.init').reinit()
