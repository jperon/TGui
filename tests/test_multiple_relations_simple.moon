-- tests/test_multiple_relations_simple.moon
-- Simple tests for multiple relations detection functionality

triggers = require 'core.triggers'

describe "Multiple Relations Detection", ->
  it "build_relation_map should return empty map for space with no relations", ->
    -- Use existing space ID that should exist
    relation_map = triggers.build_relation_map "999999"
    
    assert type(relation_map) == 'table'
    assert next(relation_map) == nil  -- Should be empty

  it "build_single_and_multiple_maps should return empty tables for invalid space", ->
    single_map, multiple_map = triggers.build_single_and_multiple_maps "999999"
    
    assert type(single_map) == 'table'
    assert type(multiple_map) == 'table'
    assert next(single_map) == nil
    assert next(multiple_map) == nil

  it "is_multiple_relation should return false for non-existent space", ->
    is_multiple = triggers.is_multiple_relation "999999", "NonExistent", "id"
    
    assert is_multiple == false

  it "is_multiple_relation should return false for non-existent target space", ->
    is_multiple = triggers.is_multiple_relation "999999", "NonExistent", "id"
    
    assert is_multiple == false

  it "functions should be exported from triggers module", ->
    assert type(triggers.build_relation_map) == 'function'
    assert type(triggers.is_multiple_relation) == 'function'
    assert type(triggers.build_single_and_multiple_maps) == 'function'

  it "build_fk_def_map should still work (backward compatibility)", ->
    fk_map = triggers.build_fk_def_map "999999"
    
    assert type(fk_map) == 'table'
    assert next(fk_map) == nil  -- Should be empty for non-existent space
