local R = require('tests.runner')
local triggers = require('core.triggers')
local spaces_mod = require('core.spaces')
local json = require('json')
R.describe("Extended Self Proxy with List Support", function()
  R.before_all(function()
    local source_space = box.space._tdb_spaces.index.by_name:get({
      'TestSource'
    })
    if source_space then
      local data_space = box.space["data_" .. tostring(source_space[2])]
      if data_space then
        data_space:truncate()
      end
      box.space._tdb_spaces:delete({
        source_space[1]
      })
    end
    local target_space = box.space._tdb_spaces.index.by_name:get({
      'TestTarget'
    })
    if target_space then
      local data_space = box.space["data_" .. tostring(target_space[2])]
      if data_space then
        data_space:truncate()
      end
      box.space._tdb_spaces:delete({
        target_space[1]
      })
    end
    local _list_0 = box.space._tdb_relations:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      if t[3] == 'TestSource' or t[3] == 'TestTarget' then
        box.space._tdb_relations:delete({
          t[1]
        })
      end
    end
  end)
  R.after_all(function() end)
  return R.it("make_self_proxy_extended should create proxy with list functions", function()
    local sp = spaces_mod.create_user_space('TestSource')
    local source_id = sp.id
    local field_id = spaces_mod.add_field(source_id, 'name', 'String')
    local source_space = box.space["data_TestSource"]
    source_space:insert({
      '1',
      json.encode({
        name = 'Test Record'
      })
    })
    local record = {
      name = 'Test Record',
      _id = '1'
    }
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    local proxy = triggers.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSource')
    R.assert(type(proxy) == 'table')
    R.assert(type(proxy.list) == 'table')
    R.assert(type(proxy.list.length) == 'function')
    R.assert(type(proxy.list.first) == 'function')
    R.assert(type(proxy.list.last) == 'function')
    R.assert(type(proxy.list.map) == 'function')
    R.assert(type(proxy.list.filter) == 'function')
    return R.assert(type(proxy.list.reduce) == 'function')
  end)
end)
return spaces_mod.delete_user_space('TestSource')
