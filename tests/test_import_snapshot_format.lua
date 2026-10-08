local R = require('tests.runner')
local auth = require('core.auth')
local spaces = require('core.spaces')
local export_r = require('resolvers.export_resolvers')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local admin_user = auth.get_user_by_username('admin')
local ADMIN_CTX = {
  user_id = admin_user and admin_user.id
}
local PKG_YAML = "app:\n  id: org.test.t13_" .. tostring(SUFFIX) .. "\n  version: \"1.0.0\"\nitems: []\n"
local UNKNOWN_YAML = "foo: bar\n"
local space_exists
space_exists = function(name)
  local _list_0 = spaces.list_spaces()
  for _index_0 = 1, #_list_0 do
    local s = _list_0[_index_0]
    if s.name == name then
      return true
    end
  end
  return false
end
R.describe("importSnapshot — unknown document refused", function()
  return R.it("raises an unrecognized-file error", function()
    return R.raises((function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = UNKNOWN_YAML,
        mode = 'merge'
      }, ADMIN_CTX)
    end), "non reconnu")
  end)
end)
R.describe("importSnapshot — valid snapshot accepted", function()
  local RT = "t13_rt_" .. tostring(SUFFIX)
  local rt_yaml = nil
  R.it("creates a space and exports a snapshot", function()
    local ok, sp = pcall(spaces.create_user_space, RT, 'round trip space')
    R.ok(ok, tostring(sp))
    local ok2, err2 = pcall(spaces.add_field, sp.id, 'titre', 'String', false)
    R.ok(ok2, tostring(err2))
    rt_yaml = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    return R.ok(rt_yaml)
  end)
  R.it("exported snapshot holds the test space in schema.spaces", function()
    local snap = yaml.decode(rt_yaml)
    R.ok(snap.schema)
    R.ok(type(snap.schema.spaces) == 'table')
    local found = false
    local _list_0 = snap.schema.spaces
    for _index_0 = 1, #_list_0 do
      local entry = _list_0[_index_0]
      if entry.name == RT then
        found = true
      end
    end
    return R.ok(found)
  end)
  R.it("deletes the space then reimports the snapshot in merge mode", function()
    spaces.delete_user_space(RT)
    R.nok(space_exists(RT))
    local res = export_r.Mutation.importSnapshot(nil, {
      yaml = rt_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(res.ok, table.concat(res.errors or { }, ' | '))
    return R.ok((res.created > 0), 'created')
  end)
  R.it("space and field are back after the round trip", function()
    R.ok(space_exists(RT))
    local sp = nil
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == RT then
        sp = s
      end
    end
    R.ok(sp)
    local has = false
    local _list_1 = spaces.list_fields(sp.id)
    for _index_0 = 1, #_list_1 do
      local f = _list_1[_index_0]
      if f.name == 'titre' then
        has = true
      end
    end
    return R.ok(has, 'field titre')
  end)
  R.it("accepts a snapshot whose schema.spaces list is empty", function()
    local empty_snap = {
      version = '1',
      schema = {
        spaces = { },
        relations = { },
        custom_views = { },
        data_views = { },
        widget_plugins = { },
        groups = { }
      }
    }
    local res = export_r.Mutation.importSnapshot(nil, {
      yaml = yaml.encode(empty_snap),
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(res.ok, table.concat(res.errors or { }, ' | '))
    return R.eq(res.created, 0)
  end)
  return R.it("cleanup round-trip space", function()
    if space_exists(RT) then
      spaces.delete_user_space(RT)
    end
    return R.nok(space_exists(RT))
  end)
end)
return R.describe("importSnapshot — application package refused", function()
  local SP = "t13_pkg_" .. tostring(SUFFIX)
  R.it("creates a guard space", function()
    local ok, err = pcall(spaces.create_user_space, SP, 'guard space')
    R.ok(ok, tostring(err))
    return R.ok(space_exists(SP))
  end)
  R.it("merge mode raises a package error", function()
    return R.raises((function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = PKG_YAML,
        mode = 'merge'
      }, ADMIN_CTX)
    end), "paquet d.application")
  end)
  R.it("replace mode raises and deletes nothing", function()
    R.raises((function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = PKG_YAML,
        mode = 'replace'
      }, ADMIN_CTX)
    end), "paquet d.application")
    return R.ok(space_exists(SP, "guard space must survive a refused replace import"))
  end)
  return R.it("cleanup guard space", function()
    if space_exists(SP) then
      spaces.delete_user_space(SP)
    end
    return R.nok(space_exists(SP))
  end)
end)
