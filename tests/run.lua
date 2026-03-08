local R = require('tests.runner')
print("══════════════════════════════════════")
print("   TGui — suite de tests")
print("══════════════════════════════════════")
do
  local auth = require('core.auth')
  local perms = require('core.permissions')
  local admin_user = auth.get_user_by_username('admin')
  if admin_user then
    local admin_grp = nil
    local _list_0 = box.space._tdb_groups:select({ })
    for _index_0 = 1, #_list_0 do
      local g = _list_0[_index_0]
      if g[2] == 'admin' then
        admin_grp = g
      end
    end
    if not (admin_grp) then
      local _list_1 = box.space._tdb_memberships.index.by_user:select({
        admin_user.id
      })
      for _index_0 = 1, #_list_1 do
        local m = _list_1[_index_0]
        box.space._tdb_memberships:delete({
          m[1],
          m[2]
        })
      end
      local new_grp = perms.create_group('admin', 'Administrators with full access')
      admin_grp = box.space._tdb_groups:get(new_grp.id)
      print("   [fixture] groupe admin recréé: " .. tostring(new_grp.id))
    end
    local mems = box.space._tdb_memberships.index.by_user:select({
      admin_user.id
    })
    local is_member = false
    for _index_0 = 1, #mems do
      local m = mems[_index_0]
      if m[2] == admin_grp[1] then
        is_member = true
      end
    end
    if not (is_member) then
      box.space._tdb_memberships:insert({
        admin_user.id,
        admin_grp[1]
      })
      print("   [fixture] admin membership restauré")
    end
  end
end
require('tests.test_lexer')
require('tests.test_parser')
require('tests.test_schema')
require('tests.test_executor')
math.randomseed(os.time())
require('tests.test_spaces')
require('tests.test_triggers')
require('tests.test_custom_views')
require('tests.test_relations')
require('tests.test_snapshot')
require('tests.test_permissions')
require('tests.test_data_filters')
R.summary()
return require('resolvers.init').reinit()
