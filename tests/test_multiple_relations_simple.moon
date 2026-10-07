-- tests/test_multiple_relations_simple.moon
-- Simple tests for the declared cardinality of relations

R = require 'tests.runner'

triggers = require 'core.triggers'
spaces_mod = require 'core.spaces'

R.describe "Multiple Relations Detection", ->
  R.it "build_relation_map should return empty map for space with no relations", ->
    -- Use existing space ID that should exist
    relation_map = triggers.build_relation_map "999999"
    
    assert type(relation_map) == 'table'
    assert next(relation_map) == nil  -- Should be empty

  R.it "build_single_and_multiple_maps should return empty tables for invalid space", ->
    single_map, multiple_map = triggers.build_single_and_multiple_maps "999999"
    
    assert type(single_map) == 'table'
    assert type(multiple_map) == 'table'
    assert next(single_map) == nil
    assert next(multiple_map) == nil

  R.it "classification follows the declared cardinality, not the data", ->
    src = spaces_mod.create_user_space 'CardSimpleSrc'
    tgt = spaces_mod.create_user_space 'CardSimpleTgt'
    fk_legacy = spaces_mod.add_field src.id, 'legacy_target_id', 'Int'
    fk_many   = spaces_mod.add_field src.id, 'multi_target_id', 'Int'
    key_legacy = spaces_mod.add_field tgt.id, 'legacy_code', 'Int'
    key_many   = spaces_mod.add_field tgt.id, 'multi_code', 'Int'

    -- Legacy row without the cardinality column -> 'one'
    box.space._tdb_relations\insert { 'rel_card_simple_one', src.id, fk_legacy.id, tgt.id, key_legacy.id, 'src_legacy', '' }
    -- Declared 'many'
    box.space._tdb_relations\insert { 'rel_card_simple_many', src.id, fk_many.id, tgt.id, key_many.id, 'src_multi', '', 'many' }

    single_map, multiple_map = triggers.build_single_and_multiple_maps src.id

    assert single_map['legacy_target_id'] != nil
    assert multiple_map['legacy_target_id'] == nil
    assert multiple_map['multi_target_id'] != nil
    assert single_map['multi_target_id'] == nil
    assert multiple_map['multi_target_id'].toSpaceName == 'CardSimpleTgt'

  R.it "functions should be exported from triggers module", ->
    assert type(triggers.build_relation_map) == 'function'
    assert type(triggers.build_single_and_multiple_maps) == 'function'

  R.it "build_fk_def_map should still work (backward compatibility)", ->
    fk_map = triggers.build_fk_def_map "999999"
    
    assert type(fk_map) == 'table'
    assert next(fk_map) == nil  -- Should be empty for non-existent space

-- Cleanup: relations and spaces created above
for rid in *{'rel_card_simple_one', 'rel_card_simple_many'}
  box.space._tdb_relations\delete { rid } if box.space._tdb_relations\get { rid }
spaces_mod.delete_user_space 'CardSimpleSrc'
spaces_mod.delete_user_space 'CardSimpleTgt'
