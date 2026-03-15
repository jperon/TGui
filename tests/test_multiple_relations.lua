local triggers = require('core.triggers')
local spaces_mod = require('core.spaces')
return describe("Multiple Relations Detection", function()
  setup(function()
    local json = require('json')
  end)
  before_each(function()
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
  it("build_relation_map should return empty map for space with no relations", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local relation_map = triggers.build_relation_map(source_id)
    assert(type(relation_map) == 'table')
    return assert(next(relation_map) == nil)
  end)
  it("build_relation_map should detect single relation", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local target_id = spaces_mod.create_space('TestTarget', 'Test target space')
    local source_field_id = spaces_mod.add_field(source_id, 'target_ref', 'Relation')
    local target_field_id = spaces_mod.add_field(target_id, 'name', 'String')
    local relation_id = spaces_mod.add_relation('TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id)
    local target_space = box.space["data_TestTarget"]
    target_space:insert({
      '1',
      json.encode({
        name = 'Target 1'
      })
    })
    target_space:insert({
      '2',
      json.encode({
        name = 'Target 2'
      })
    })
    local source_space = box.space["data_TestSource"]
    source_space:insert({
      '1',
      json.encode({
        target_ref = '1'
      })
    })
    source_space:insert({
      '2',
      json.encode({
        target_ref = '2'
      })
    })
    local relation_map = triggers.build_relation_map(source_id)
    assert(relation_map.target_ref)
    assert(relation_map.target_ref.toSpaceName == 'TestTarget')
    assert(relation_map.target_ref.toFieldName == 'name')
    return assert(relation_map.target_ref.isMultiple == false)
  end)
  it("build_relation_map should detect multiple relation", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local target_id = spaces_mod.create_space('TestTarget', 'Test target space')
    local source_field_id = spaces_mod.add_field(source_id, 'target_ref', 'Relation')
    local target_field_id = spaces_mod.add_field(target_id, 'name', 'String')
    local relation_id = spaces_mod.add_relation('TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id)
    local source_space = box.space["data_TestSource"]
    source_space:insert({
      '1',
      json.encode({
        name = 'Source 1'
      })
    })
    source_space:insert({
      '2',
      json.encode({
        name = 'Source 2'
      })
    })
    local target_space = box.space["data_TestTarget"]
    for i = 1, 15 do
      target_space:insert({
        tostring(i),
        json.encode({
          name = "Target " .. tostring(i),
          source_ref = '1'
        })
      })
    end
    local relation_map = triggers.build_relation_map(source_id)
    assert(relation_map.target_ref)
    assert(relation_map.target_ref.toSpaceName == 'TestTarget')
    assert(relation_map.target_ref.toFieldName == 'name')
    return assert(relation_map.target_ref.isMultiple == true)
  end)
  it("build_single_and_multiple_maps should separate relations correctly", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local target1_id = spaces_mod.create_space('TestTarget1', 'Test target space 1')
    local target2_id = spaces_mod.create_space('TestTarget2', 'Test target space 2')
    local single_field_id = spaces_mod.add_field(source_id, 'single_ref', 'Relation')
    local multiple_field_id = spaces_mod.add_field(source_id, 'multiple_ref', 'Relation')
    local target1_field_id = spaces_mod.add_field(target1_id, 'name', 'String')
    local target2_field_id = spaces_mod.add_field(target2_id, 'name', 'String')
    local single_relation_id = spaces_mod.add_relation('TestSource->TestTarget1', source_id, single_field_id, target1_id, target1_field_id)
    local multiple_relation_id = spaces_mod.add_relation('TestSource->TestTarget2', source_id, multiple_field_id, target2_id, target2_field_id)
    local source_space = box.space["data_TestSource"]
    source_space:insert({
      '1',
      json.encode({
        name = 'Source 1'
      })
    })
    local target1_space = box.space["data_TestTarget1"]
    target1_space:insert({
      '1',
      json.encode({
        name = 'Target 1'
      })
    })
    local target2_space = box.space["data_TestTarget2"]
    for i = 1, 15 do
      target2_space:insert({
        tostring(i),
        json.encode({
          name = "Target " .. tostring(i),
          source_ref = '1'
        })
      })
    end
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    assert(type(single_map) == 'table')
    assert(single_map.single_ref)
    assert(single_map.single_ref.isMultiple == false)
    assert(type(multiple_map) == 'table')
    assert(multiple_map.multiple_ref)
    return assert(multiple_map.multiple_ref.isMultiple == true)
  end)
  it("is_multiple_relation should return false for empty target space", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local target_id = spaces_mod.create_space('TestTarget', 'Test target space')
    local source_field_id = spaces_mod.add_field(source_id, 'target_ref', 'Relation')
    local target_field_id = spaces_mod.add_field(target_id, 'name', 'String')
    local relation_id = spaces_mod.add_relation('TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id)
    local is_multiple = triggers.is_multiple_relation(source_id, 'TestTarget', 'name')
    return assert(is_multiple == false)
  end)
  it("is_multiple_relation should return false for insufficient data", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local target_id = spaces_mod.create_space('TestTarget', 'Test target space')
    local source_field_id = spaces_mod.add_field(source_id, 'target_ref', 'Relation')
    local target_field_id = spaces_mod.add_field(target_id, 'name', 'String')
    local relation_id = spaces_mod.add_relation('TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id)
    local target_space = box.space["data_TestTarget"]
    target_space:insert({
      '1',
      json.encode({
        name = 'Target 1',
        source_ref = '1'
      })
    })
    target_space:insert({
      '2',
      json.encode({
        name = 'Target 2',
        source_ref = '2'
      })
    })
    local is_multiple = triggers.is_multiple_relation(source_id, 'TestTarget', 'source_ref')
    return assert(is_multiple == false)
  end)
  return after_each(function()
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
end)
