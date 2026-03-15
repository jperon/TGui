-- tests/test_multiple_relations.moon
-- Tests for multiple relations detection functionality

triggers = require 'core.triggers'
spaces_mod = require 'core.spaces'

describe "Multiple Relations Detection", ->
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
    
    target1_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget1' }
    if target1_space
      data_space = box.space["data_#{target1_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target1_space[1] }
    
    target2_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget2' }
    if target2_space
      data_space = box.space["data_#{target2_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target2_space[1] }
    
    -- Clean up relations
    for t in *box.space._tdb_relations\select {}
      if t[3] == 'TestSource' or t[3] == 'TestTarget' or t[3] == 'TestTarget1' or t[3] == 'TestTarget2'
        box.space._tdb_relations\delete { t[1] }

  it "build_relation_map should return empty map for space with no relations", ->
    -- Create test space
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    
    relation_map = triggers.build_relation_map source_id
    
    assert type(relation_map) == 'table'
    assert next(relation_map) == nil  -- Should be empty

  it "build_relation_map should detect single relation", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'
    
    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'
    
    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id
    
    -- Add test data (single references)
    target_space = box.space["data_TestTarget"]
    target_space\insert { '1', json.encode{name: 'Target 1'} }
    target_space\insert { '2', json.encode{name: 'Target 2'} }
    
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{target_ref: '1'} }
    source_space\insert { '2', json.encode{target_ref: '2'} }
    
    relation_map = triggers.build_relation_map source_id
    
    assert relation_map.target_ref
    assert relation_map.target_ref.toSpaceName == 'TestTarget'
    assert relation_map.target_ref.toFieldName == 'name'
    assert relation_map.target_ref.isMultiple == false

  it "build_relation_map should detect multiple relation", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'
    
    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'
    
    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id
    
    -- Add test data (multiple references to same source)
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{name: 'Source 1'} }
    source_space\insert { '2', json.encode{name: 'Source 2'} }
    
    target_space = box.space["data_TestTarget"]
    -- Multiple targets reference the same source
    for i = 1, 15
      target_space\insert { tostring(i), json.encode{name: "Target #{i}", source_ref: '1'} }
    
    relation_map = triggers.build_relation_map source_id
    
    assert relation_map.target_ref
    assert relation_map.target_ref.toSpaceName == 'TestTarget'
    assert relation_map.target_ref.toFieldName == 'name'
    assert relation_map.target_ref.isMultiple == true

  it "build_single_and_multiple_maps should separate relations correctly", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target1_id = spaces_mod.create_space 'TestTarget1', 'Test target space 1'
    target2_id = spaces_mod.create_space 'TestTarget2', 'Test target space 2'
    
    -- Add fields
    single_field_id = spaces_mod.add_field source_id, 'single_ref', 'Relation'
    multiple_field_id = spaces_mod.add_field source_id, 'multiple_ref', 'Relation'
    target1_field_id = spaces_mod.add_field target1_id, 'name', 'String'
    target2_field_id = spaces_mod.add_field target2_id, 'name', 'String'
    
    -- Create relations
    single_relation_id = spaces_mod.add_relation 'TestSource->TestTarget1', source_id, single_field_id, target1_id, target1_field_id
    multiple_relation_id = spaces_mod.add_relation 'TestSource->TestTarget2', source_id, multiple_field_id, target2_id, target2_field_id
    
    -- Add test data
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{name: 'Source 1'} }
    
    target1_space = box.space["data_TestTarget1"]
    target1_space\insert { '1', json.encode{name: 'Target 1'} }
    
    target2_space = box.space["data_TestTarget2"]
    -- Multiple references to create multiple relation
    for i = 1, 15
      target2_space\insert { tostring(i), json.encode{name: "Target #{i}", source_ref: '1'} }
    
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id
    
    -- Check single relations
    assert type(single_map) == 'table'
    assert single_map.single_ref
    assert single_map.single_ref.isMultiple == false
    
    -- Check multiple relations
    assert type(multiple_map) == 'table'
    assert multiple_map.multiple_ref
    assert multiple_map.multiple_ref.isMultiple == true

  it "is_multiple_relation should return false for empty target space", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'
    
    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'
    
    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id
    
    -- Don't add any data to target space
    is_multiple = triggers.is_multiple_relation source_id, 'TestTarget', 'name'
    
    assert is_multiple == false

  it "is_multiple_relation should return false for insufficient data", ->
    -- Create test spaces
    source_id = spaces_mod.create_space 'TestSource', 'Test source space'
    target_id = spaces_mod.create_space 'TestTarget', 'Test target space'
    
    -- Add fields
    source_field_id = spaces_mod.add_field source_id, 'target_ref', 'Relation'
    target_field_id = spaces_mod.add_field target_id, 'name', 'String'
    
    -- Create relation
    relation_id = spaces_mod.add_relation 'TestSource->TestTarget', source_id, source_field_id, target_id, target_field_id
    
    -- Add minimal data (not enough to be considered multiple)
    target_space = box.space["data_TestTarget"]
    target_space\insert { '1', json.encode{name: 'Target 1', source_ref: '1'} }
    target_space\insert { '2', json.encode{name: 'Target 2', source_ref: '2'} }
    
    is_multiple = triggers.is_multiple_relation source_id, 'TestTarget', 'source_ref'
    
    assert is_multiple == false

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
    
    target1_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget1' }
    if target1_space
      data_space = box.space["data_#{target1_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target1_space[1] }
    
    target2_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget2' }
    if target2_space
      data_space = box.space["data_#{target2_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target2_space[1] }
    
    -- Clean up relations
    for t in *box.space._tdb_relations\select {}
      if t[3] == 'TestSource' or t[3] == 'TestTarget' or t[3] == 'TestTarget1' or t[3] == 'TestTarget2'
        box.space._tdb_relations\delete { t[1] }
