local R = require('tests.runner')
local triggers = require('core.triggers')
local spaces_mod = require('core.spaces')
R.describe("Multiple Relations Detection", function()
  R.it("build_relation_map should return empty map for space with no relations", function()
    local relation_map = triggers.build_relation_map("999999")
    assert(type(relation_map) == 'table')
    return assert(next(relation_map) == nil)
  end)
  R.it("build_single_and_multiple_maps should return empty tables for invalid space", function()
    local single_map, multiple_map = triggers.build_single_and_multiple_maps("999999")
    assert(type(single_map) == 'table')
    assert(type(multiple_map) == 'table')
    assert(next(single_map) == nil)
    return assert(next(multiple_map) == nil)
  end)
  R.it("classification follows the declared cardinality, not the data", function()
    local src = spaces_mod.create_user_space('CardSimpleSrc')
    local tgt = spaces_mod.create_user_space('CardSimpleTgt')
    local fk_legacy = spaces_mod.add_field(src.id, 'legacy_target_id', 'Int')
    local fk_many = spaces_mod.add_field(src.id, 'multi_target_id', 'Int')
    local key_legacy = spaces_mod.add_field(tgt.id, 'legacy_code', 'Int')
    local key_many = spaces_mod.add_field(tgt.id, 'multi_code', 'Int')
    box.space._tdb_relations:insert({
      'rel_card_simple_one',
      src.id,
      fk_legacy.id,
      tgt.id,
      key_legacy.id,
      'src_legacy',
      ''
    })
    box.space._tdb_relations:insert({
      'rel_card_simple_many',
      src.id,
      fk_many.id,
      tgt.id,
      key_many.id,
      'src_multi',
      '',
      'many'
    })
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(src.id)
    assert(single_map['legacy_target_id'] ~= nil)
    assert(multiple_map['legacy_target_id'] == nil)
    assert(multiple_map['multi_target_id'] ~= nil)
    assert(single_map['multi_target_id'] == nil)
    return assert(multiple_map['multi_target_id'].toSpaceName == 'CardSimpleTgt')
  end)
  R.it("functions should be exported from triggers module", function()
    assert(type(triggers.build_relation_map) == 'function')
    return assert(type(triggers.build_single_and_multiple_maps) == 'function')
  end)
  return R.it("build_fk_def_map should still work (backward compatibility)", function()
    local fk_map = triggers.build_fk_def_map("999999")
    assert(type(fk_map) == 'table')
    return assert(next(fk_map) == nil)
  end)
end)
local _list_0 = {
  'rel_card_simple_one',
  'rel_card_simple_many'
}
for _index_0 = 1, #_list_0 do
  local rid = _list_0[_index_0]
  if box.space._tdb_relations:get({
    rid
  }) then
    box.space._tdb_relations:delete({
      rid
    })
  end
end
spaces_mod.delete_user_space('CardSimpleSrc')
return spaces_mod.delete_user_space('CardSimpleTgt')
