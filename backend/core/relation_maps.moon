-- core/relation_maps.moon
-- Builds FK / relation definition maps for a space from the _tdb_relations,
-- _tdb_spaces and _tdb_fields metadata. Extracted from core.triggers (T14),
-- no functional change.

-- Build { field_name => { toSpaceName, toFieldName } } for a space's FK fields.
build_fk_def_map = (space_id) ->
  rels = {}
  for t in *box.space._tdb_relations\select {}
    if t[2] == space_id
      rels[t[3]] = { toSpaceId: t[4], toFieldId: t[5] }
  -- Resolve space names and field names
  fk_def_map = {}
  space_by_id = {}
  for t in *box.space._tdb_spaces\select {}
    space_by_id[t[1]] = { name: t[2] }
  field_by_id = {}
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    field_by_id[t[1]] = { name: t[3] }
  -- Also need field names from other spaces for toFieldId
  for _, rel in pairs rels
    tf = box.space._tdb_fields\get rel.toFieldId
    field_by_id[rel.toFieldId] = { name: tf and tf[3] or 'id' }
  for field_id, rel in pairs rels
    fld = box.space._tdb_fields\get field_id
    sp  = space_by_id[rel.toSpaceId]
    if fld and sp
      fk_def_map[fld[3]] =
        toSpaceName: sp.name
        toFieldName: (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'
  fk_def_map

-- Build { field_name => { toSpaceName, toFieldName, isMultiple } } for a space's FK fields.
-- isMultiple comes from the declared cardinality of the relation (column 8 of
-- _tdb_relations): 'many' => true, anything else (missing column included) => false.
build_relation_map = (space_id) ->
  relations = {}
  space_by_id = {}
  for t in *box.space._tdb_spaces\select {}
    space_by_id[t[1]] = { name: t[2] }

  field_by_id = {}
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    field_by_id[t[1]] = { name: t[3] }

  -- Also need field names from other spaces for toFieldId
  for t in *box.space._tdb_relations\select {}
    field_by_id[t[5]] = { name: t[3] } if t[5]  -- toFieldId -> field name

  for t in *box.space._tdb_relations\select {}
    if t[2] == space_id  -- fromSpaceId
      fld = box.space._tdb_fields\get t[3]  -- fromFieldId
      sp  = space_by_id[t[4]]  -- toSpaceId
      tf  = box.space._tdb_fields\get t[5]  -- toFieldId

      if fld and sp and tf
        cardinality = t[8] or 'one'
        relations[fld[3]] = {
          toSpaceName: sp.name
          toFieldName: tf[3]
          isMultiple: cardinality == 'many'
        }

  relations

-- Build separate maps for single and multiple relations
build_single_and_multiple_maps = (space_id) ->
  relation_map = build_relation_map space_id
  single_map = {}
  multiple_map = {}

  for field_name, relation in pairs relation_map
    if relation.isMultiple
      multiple_map[field_name] = relation
    else
      single_map[field_name] = relation

  single_map, multiple_map

{ :build_fk_def_map, :build_relation_map, :build_single_and_multiple_maps }
