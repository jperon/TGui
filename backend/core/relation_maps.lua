local build_fk_def_map
build_fk_def_map = function(space_id)
  local rels = { }
  local _list_0 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[2] == space_id then
      rels[t[3]] = {
        toSpaceId = t[4],
        toFieldId = t[5]
      }
    end
  end
  local fk_def_map = { }
  local space_by_id = { }
  local _list_1 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    space_by_id[t[1]] = {
      name = t[2]
    }
  end
  local field_by_id = { }
  local _list_2 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_2 do
    local t = _list_2[_index_0]
    field_by_id[t[1]] = {
      name = t[3]
    }
  end
  for _, rel in pairs(rels) do
    local tf = box.space._tdb_fields:get(rel.toFieldId)
    field_by_id[rel.toFieldId] = {
      name = tf and tf[3] or 'id'
    }
  end
  for field_id, rel in pairs(rels) do
    local fld = box.space._tdb_fields:get(field_id)
    local sp = space_by_id[rel.toSpaceId]
    if fld and sp then
      fk_def_map[fld[3]] = {
        toSpaceName = sp.name,
        toFieldName = (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'
      }
    end
  end
  return fk_def_map
end
local build_relation_map
build_relation_map = function(space_id)
  local relations = { }
  local space_by_id = { }
  local _list_0 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    space_by_id[t[1]] = {
      name = t[2]
    }
  end
  local field_by_id = { }
  local _list_1 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    field_by_id[t[1]] = {
      name = t[3]
    }
  end
  local _list_2 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_2 do
    local t = _list_2[_index_0]
    if t[5] then
      field_by_id[t[5]] = {
        name = t[3]
      }
    end
  end
  local _list_3 = box.space._tdb_relations:select({ })
  for _index_0 = 1, #_list_3 do
    local t = _list_3[_index_0]
    if t[2] == space_id then
      local fld = box.space._tdb_fields:get(t[3])
      local sp = space_by_id[t[4]]
      local tf = box.space._tdb_fields:get(t[5])
      if fld and sp and tf then
        local cardinality = t[8] or 'one'
        relations[fld[3]] = {
          toSpaceName = sp.name,
          toFieldName = tf[3],
          isMultiple = cardinality == 'many'
        }
      end
    end
  end
  return relations
end
local build_single_and_multiple_maps
build_single_and_multiple_maps = function(space_id)
  local relation_map = build_relation_map(space_id)
  local single_map = { }
  local multiple_map = { }
  for field_name, relation in pairs(relation_map) do
    if relation.isMultiple then
      multiple_map[field_name] = relation
    else
      single_map[field_name] = relation
    end
  end
  return single_map, multiple_map
end
return {
  build_fk_def_map = build_fk_def_map,
  build_relation_map = build_relation_map,
  build_single_and_multiple_maps = build_single_and_multiple_maps
}
