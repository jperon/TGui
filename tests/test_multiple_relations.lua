local R = require('tests.runner')
local triggers = require('core.triggers')
local spaces_mod = require('core.spaces')
local json = require('json')
R.describe("Multiple Relations Detection", function()
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
    local target1_space = box.space._tdb_spaces.index.by_name:get({
      'TestTarget1'
    })
    if target1_space then
      local data_space = box.space["data_" .. tostring(target1_space[2])]
      if data_space then
        data_space:truncate()
      end
      box.space._tdb_spaces:delete({
        target1_space[1]
      })
    end
    local target2_space = box.space._tdb_spaces.index.by_name:get({
      'TestTarget2'
    })
    if target2_space then
      local data_space = box.space["data_" .. tostring(target2_space[2])]
      if data_space then
        data_space:truncate()
      end
      box.space._tdb_spaces:delete({
        target2_space[1]
      })
    end
    local _list_0 = box.space._tdb_relations:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      if t[3] == 'TestSource' or t[3] == 'TestTarget' or t[3] == 'TestTarget1' or t[3] == 'TestTarget2' then
        box.space._tdb_relations:delete({
          t[1]
        })
      end
    end
  end)
  R.after_all(function() end)
  R.it("build_relation_map should return empty map for space with no relations", function()
    local sp = spaces_mod.create_user_space('TestSource')
    local source_id = sp.id
    local relation_map = triggers.build_relation_map(source_id)
    assert(type(relation_map) == 'table')
    return assert(next(relation_map) == nil)
  end)
  R.it("build_single_and_multiple_maps should return empty tables for invalid space", function()
    local single_map, multiple_map = triggers.build_single_and_multiple_maps("999999")
    assert(type(single_map) == 'table')
    assert(type(multiple_map) == 'table')
    assert(next(single_map) == nil)
    return assert(next(multiple_map) == nil)
  end)
  R.it("is_multiple_relation should return false for non-existent space", function()
    local is_multiple = triggers.is_multiple_relation("999999", "NonExistent", "id")
    return assert(is_multiple == false)
  end)
  R.it("is_multiple_relation should return false for non-existent target space", function()
    local is_multiple = triggers.is_multiple_relation("999999", "NonExistent", "id")
    return assert(is_multiple == false)
  end)
  R.it("functions should be exported from triggers module", function()
    assert(type(triggers.build_relation_map) == 'function')
    assert(type(triggers.is_multiple_relation) == 'function')
    return assert(type(triggers.build_single_and_multiple_maps) == 'function')
  end)
  return R.it("build_fk_def_map should still work (backward compatibility)", function()
    local fk_map = triggers.build_fk_def_map("999999")
    assert(type(fk_map) == 'table')
    return assert(next(fk_map) == nil)
  end)
end)
return spaces_mod.delete_user_space('TestSource')
