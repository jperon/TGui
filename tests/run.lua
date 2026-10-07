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
      print("   [fixture] admin group recreated: " .. tostring(new_grp.id))
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
      print("   [fixture] admin membership restored")
    end
  end
end
math.randomseed(os.time())
local fio = require('fio')
local test_files = { }
local paths = { }
local _list_0 = {
  '/app/tests/test_*.moon',
  'tests/test_*.moon'
}
for _index_0 = 1, #_list_0 do
  local pattern = _list_0[_index_0]
  paths = fio.glob(pattern)
  if paths and #paths > 0 then
    break
  end
end
if not (paths) then
  paths = { }
end
for _index_0 = 1, #paths do
  local path = paths[_index_0]
  local filename = path:match('([^/]+)%.moon$')
  if filename and not filename:match('_disabled') then
    local modname = filename:gsub('%.moon$', '')
    table.insert(test_files, modname)
  end
end
table.sort(test_files)
print("   Discovered " .. tostring(#test_files) .. " test files")
for _index_0 = 1, #test_files do
  local modname = test_files[_index_0]
  print("      - " .. tostring(modname))
  require("tests." .. tostring(modname))
end
local exit_code = R.summary()
require('resolvers.init').reinit()
local executor = require('graphql.executor')
local res = executor.execute({
  query = '{ __type(name: "Query") { fields { name } } }'
})
local spaces_ok = false
if res and type(res.data) == 'table' and res.data['__type'] and res.data['__type'].fields then
  local _list_1 = res.data['__type'].fields
  for _index_0 = 1, #_list_1 do
    local f = _list_1[_index_0]
    if f.name == 'spaces' then
      spaces_ok = true
    end
  end
end
if not (spaces_ok) then
  print('   [FAIL] production schema not restored: Query.spaces is missing')
  exit_code = 1
else
  print('   [ok] production schema restored (Query.spaces present)')
end
return exit_code
