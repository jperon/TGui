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

  R.it "a relation without declared cardinality is classified as single", ->
    -- Legacy row: 7 columns, no cardinality => must be read as 'one'
    tgt = spaces_mod.create_user_space 'TestTarget'
    src_meta = box.space._tdb_spaces.index.by_name\get { 'TestSource' }
    source_id = src_meta[1]
    fk  = spaces_mod.add_field source_id, 'legacy_target_id', 'Int'
    key = spaces_mod.add_field tgt.id, 'legacy_code', 'Int'
    box.space._tdb_relations\insert { 'rel_card_one', source_id, fk.id, tgt.id, key.id, 'src_legacy', '' }

    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    assert single_map['legacy_target_id'] != nil
    assert multiple_map['legacy_target_id'] == nil

  R.it "a relation declared 'many' is classified as multiple", ->
    tgt = box.space._tdb_spaces.index.by_name\get { 'TestTarget' }
    src_meta = box.space._tdb_spaces.index.by_name\get { 'TestSource' }
    source_id = src_meta[1]
    fk  = spaces_mod.add_field source_id, 'multi_target_id', 'Int'
    key = spaces_mod.add_field tgt[1], 'multi_code', 'Int'
    box.space._tdb_relations\insert { 'rel_card_many', source_id, fk.id, tgt[1], key.id, 'src_multi', '', 'many' }

    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    assert single_map['multi_target_id'] == nil
    assert multiple_map['multi_target_id'] != nil
    assert multiple_map['multi_target_id'].toSpaceName == 'TestTarget'

  R.it "functions should be exported from triggers module", ->
    assert type(triggers.build_relation_map) == 'function'
    assert type(triggers.build_single_and_multiple_maps) == 'function'

  R.it "build_fk_def_map should still work (backward compatibility)", ->
    fk_map = triggers.build_fk_def_map "999999"

    assert type(fk_map) == 'table'
    assert next(fk_map) == nil  -- Should be empty for non-existent space

-- Cleanup: delete relations and spaces created for these tests
for rid in *{'rel_card_one', 'rel_card_many'}
  box.space._tdb_relations\delete { rid } if box.space._tdb_relations\get { rid }
spaces_mod.delete_user_space 'TestSource'
spaces_mod.delete_user_space 'TestTarget'
