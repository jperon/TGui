-- tests/test_extended_proxy.moon
-- Tests for extended proxy with list support

triggers = require 'core.triggers'
spaces_mod = require 'core.spaces'

describe "Extended Self Proxy with List Support", ->
  setup ->
    -- Setup test environment
    json = require 'json'

  before_each ->
    -- Clean up any existing test data
    source_space = box.space._tdb_spaces.index.by_name\get { 'TestSource' }
    if source_space
      data_space = box.space["data_#{source_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { source_space[1] }

    target_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget' }
    if target_space
      data_space = box.space["data_#{target_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target_space[1] }

    -- Clean up relations
    for t in *box.space._tdb_relations\select {}
      if t[3] == 'TestSource' or t[3] == 'TestTarget'
        box.space._tdb_relations\delete { t[1] }

  it "make_self_proxy_extended should create proxy with list functions", ->
    -- Create test space
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'

    -- Add field
    field_id = spaces_mod.add_field source_id, 'name', 'String'

    -- Create record
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{name: 'Test Record'} }

    record = {name: 'Test Record', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    assert type(proxy) == 'table'
    assert type(proxy.list) == 'table'
    assert type(proxy.list.length) == 'function'
    assert type(proxy.list.first) == 'function'
    assert type(proxy.list.last) == 'function'
    assert type(proxy.list.map) == 'function'
    assert type(proxy.list.filter) == 'function'
    assert type(proxy.list.reduce) == 'function'

  it "make_self_proxy_extended should handle single relations like standard proxy", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'

    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'

    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id

    -- Add test data
    target_space = box.space["data_TestTarget"]
    target_space\insert { '1', json.encode{name: 'Target 1'} }
    target_space\insert { '2', json.encode{name: 'Target 2'} }

    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{target_ref: '1'} }

    record = {target_ref: '1', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    -- Should resolve single relation
    target = proxy.target_ref
    assert target ~= nil
    assert target.name == 'Target 1'

  it "make_self_proxy_extended should return list for multiple relations", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'

    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'

    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id

    -- Add test data (multiple targets reference same source)
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{name: 'Source 1'} }

    target_space = box.space["data_TestTarget"]
    for i = 1, 15
      target_space\insert { tostring(i), json.encode{name: "Target #{i}", source_ref: '1'} }

    record = {name: 'Source 1', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    -- Should detect as multiple relation and return list
    targets = proxy.target_ref
    assert type(targets) == 'table'
    assert #targets > 0

    -- Check that list functions work
    assert proxy.list.length(targets) == #targets
    assert proxy.list.first(targets) ~= nil
    assert proxy.list.last(targets) ~= nil

  it "list functions should work correctly", ->
    test_list = {1, 2, 3, 4, 5}

    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    record = {name: 'Test', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    -- Test length
    assert proxy.list.length(test_list) == 5

    # Test first
    assert proxy.list.first(test_list) == 1

    # Test last
    assert proxy.list.last(test_list) == 5

    # Test map
    doubled = proxy.list.map(test_list, (x) -> x * 2)
    assert #doubled == 5
    assert doubled[1] == 2
    assert doubled[5] == 10

    # Test filter
    evens = proxy.list.filter(test_list, (x) -> x % 2 == 0)
    assert #evens == 2
    assert evens[1] == 2
    assert evens[2] == 4

    # Test reduce
    sum = proxy.list.reduce(test_list, (acc, x) -> acc + x, 0)
    assert sum == 15

  it "make_self_proxy_extended should handle computed fields", ->
    -- Create test space with computed field
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'

    -- Add fields
    name_field_id = spaces_mod.add_field source_id, 'name', 'String'
    computed_field_id = spaces_mod.add_field source_id, 'display_name', 'String', nil, '@name .. " (computed)"', nil, 'moonscript'

    -- Create record
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{name: 'Test Record'} }

    record = {name: 'Test Record', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    -- Should resolve computed field
    display_name = proxy.display_name
    assert display_name == 'Test Record (computed)'

  it "make_self_proxy_extended should cache resolved values", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'

    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'

    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id

    -- Add test data
    target_space = box.space["data_TestTarget"]
    target_space\insert { '1', json.encode{name: 'Target 1'} }

    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{target_ref: '1'} }

    record = {target_ref: '1', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    -- First access should resolve
    target1 = proxy.target_ref
    assert target1.name == 'Target 1'

    -- Second access should return cached value (same object)
    target2 = proxy.target_ref
    assert target1 == target2

  it "make_self_proxy_extended should return nil for missing relations", ->
    -- Create test space
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'

    record = {missing_ref: '999', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    -- Should return nil for missing relation
    missing = proxy.missing_ref
    assert missing == nil

  after_each ->
    -- Clean up test data
    source_space = box.space._tdb_spaces.index.by_name\get { 'TestSource' }
    if source_space
      data_space = box.space["data_#{source_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { source_space[1] }

    target_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget' }
    if target_space
      data_space = box.space["data_#{target_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target_space[1] }

    -- Clean up relations
    for t in *box.space._tdb_relations\select {}
      if t[3] == 'TestSource' or t[3] == 'TestTarget'
        box.space._tdb_relations\delete { t[1] }
