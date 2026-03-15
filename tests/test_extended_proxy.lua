local triggers = require('core.triggers')
local spaces_mod = require('core.spaces')
return describe("Extended Self Proxy with List Support", function()
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
  it("make_self_proxy_extended should create proxy with list functions", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
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
    assert(type(proxy) == 'table')
    assert(type(proxy.list) == 'table')
    assert(type(proxy.list.length) == 'function')
    assert(type(proxy.list.first) == 'function')
    assert(type(proxy.list.last) == 'function')
    assert(type(proxy.list.map) == 'function')
    assert(type(proxy.list.filter) == 'function')
    return assert(type(proxy.list.reduce) == 'function')
  end)
  it("make_self_proxy_extended should handle single relations like standard proxy", function()
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
    local record = {
      target_ref = '1',
      _id = '1'
    }
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    local proxy = triggers.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSource')
    local target = proxy.target_ref
    assert(target ~= nil)
    return assert(target.name == 'Target 1')
  end)
  it("make_self_proxy_extended should return list for multiple relations", function()
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
    local record = {
      name = 'Source 1',
      _id = '1'
    }
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    local proxy = triggers.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSource')
    local targets = proxy.target_ref
    assert(type(targets) == 'table')
    assert(#targets > 0)
    assert(proxy.list.length(targets) == #targets)
    assert(proxy.list.first(targets) ~= nil)
    return assert(proxy.list.last(targets) ~= nil)
  end)
  it("list functions should work correctly", function()
    local test_list = {
      1,
      2,
      3,
      4,
      5
    }
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local record = {
      name = 'Test',
      _id = '1'
    }
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    local proxy = triggers.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSource')
    assert(proxy.list.length(test_list) == 5)
    local _ = #Test(first)
    assert(proxy.list.first(test_list) == 1)
    _ = #Test(last)
    assert(proxy.list.last(test_list) == 5)
    _ = #Test(map)
    local doubled = proxy.list.map(test_list, function(x)
      return x * 2
    end)
    assert(#doubled == 5)
    assert(doubled[1] == 2)
    assert(doubled[5] == 10)
    _ = #Test(filter)
    local evens = proxy.list.filter(test_list, function(x)
      return x % 2 == 0
    end)
    assert(#evens == 2)
    assert(evens[1] == 2)
    assert(evens[2] == 4)
    _ = #Test(reduce)
    local sum = proxy.list.reduce(test_list, function(acc, x)
      return acc + x, 0
    end)
    return assert(sum == 15)
  end)
  it("make_self_proxy_extended should handle computed fields", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local name_field_id = spaces_mod.add_field(source_id, 'name', 'String')
    local computed_field_id = spaces_mod.add_field(source_id, 'display_name', 'String', nil, '@name .. " (computed)"', nil, 'moonscript')
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
    local display_name = proxy.display_name
    return assert(display_name == 'Test Record (computed)')
  end)
  it("make_self_proxy_extended should cache resolved values", function()
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
    local source_space = box.space["data_TestSource"]
    source_space:insert({
      '1',
      json.encode({
        target_ref = '1'
      })
    })
    local record = {
      target_ref = '1',
      _id = '1'
    }
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    local proxy = triggers.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSource')
    local target1 = proxy.target_ref
    assert(target1.name == 'Target 1')
    local target2 = proxy.target_ref
    return assert(target1 == target2)
  end)
  it("make_self_proxy_extended should return nil for missing relations", function()
    local source_id = spaces_mod.create_space('TestSource', 'Test source space')
    local record = {
      missing_ref = '999',
      _id = '1'
    }
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(source_id)
    local proxy = triggers.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSource')
    local missing = proxy.missing_ref
    return assert(missing == nil)
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
end)
