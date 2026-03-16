-- tests/test_multiple_relations.moon
-- Tests for multiple relations detection functionality

R = require 'tests.runner'
triggers = require 'core.triggers'
spaces_mod = require 'core.spaces'

-- Setup test environment
json = require 'json'

R.describe "Multiple Relations Detection", ->
  R.before_all ->
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

  R.after_all ->

  R.it "build_relation_map should return empty map for space with no relations", ->
    -- Create test space
    sp = spaces_mod.create_user_space 'TestSource'
    source_id = sp.id

    relation_map = triggers.build_relation_map source_id

    assert type(relation_map) == 'table'
    assert next(relation_map) == nil  -- Should be empty

  R.it "build_single_and_multiple_maps should return empty tables for invalid space", ->
    single_map, multiple_map = triggers.build_single_and_multiple_maps "999999"

    assert type(single_map) == 'table'
    assert type(multiple_map) == 'table'
    assert next(single_map) == nil
    assert next(multiple_map) == nil

  R.it "is_multiple_relation should return false for non-existent space", ->
    is_multiple = triggers.is_multiple_relation "999999", "NonExistent", "id"

    assert is_multiple == false

  R.it "is_multiple_relation should return false for non-existent target space", ->
    is_multiple = triggers.is_multiple_relation "999999", "NonExistent", "id"

    assert is_multiple == false

  R.it "functions should be exported from triggers module", ->
    assert type(triggers.build_relation_map) == 'function'
    assert type(triggers.is_multiple_relation) == 'function'
    assert type(triggers.build_single_and_multiple_maps) == 'function'

  R.it "build_fk_def_map should still work (backward compatibility)", ->
    fk_map = triggers.build_fk_def_map "999999"

    assert type(fk_map) == 'table'
    assert next(fk_map) == nil  -- Should be empty for non-existent space

-- Cleanup: delete spaces created for these tests
spaces_mod.delete_user_space 'TestSource'
