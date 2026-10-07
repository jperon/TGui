local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local triggers = require('core.triggers')
local json = require('json')
local Query, Mutation
do
  local _obj_0 = require('resolvers.schema_resolvers')
  Query, Mutation = _obj_0.Query, _obj_0.Mutation
end
local execute
execute = require('graphql.executor').execute
local data_Mutation
data_Mutation = require('resolvers.data_resolvers').Mutation
local SUFFIX = tostring(math.random(100000, 999999))
local SP_SRC = "card_src_" .. tostring(SUFFIX)
local SP_TGT = "card_tgt_" .. tostring(SUFFIX)
local CTX = {
  user_id = 'test-user'
}
local src_id, tgt_id = nil, nil
local tgt_seq_id, tgt_code_id = nil, nil
local f_one, f_dup, f_many, f_legacy = nil, nil, nil, nil
local rel_one_id, rel_many_id, rel_dup_id = nil, nil, nil
do
  local src = spaces_mod.create_user_space(SP_SRC, 'Cardinality source')
  local tgt = spaces_mod.create_user_space(SP_TGT, 'Cardinality target')
  src_id = src.id
  tgt_id = tgt.id
  local seq = spaces_mod.add_field(tgt_id, 'seq_id', 'Sequence')
  local code = spaces_mod.add_field(tgt_id, 'code', 'String')
  tgt_seq_id = seq.id
  tgt_code_id = code.id
  f_one = spaces_mod.add_field(src_id, 'fk_one', 'Int')
  f_dup = spaces_mod.add_field(src_id, 'fk_dup_one', 'Int')
  f_many = spaces_mod.add_field(src_id, 'fk_many', 'String')
  f_legacy = spaces_mod.add_field(src_id, 'fk_legacy', 'Int')
  require('resolvers.init').reinit()
end
R.describe("Relation cardinality — storage", function()
  R.it("_tdb_relations exposes a nullable 8th cardinality column", function()
    local fmt = box.space._tdb_relations:format()
    R.eq(#fmt, 8, 'format field count')
    R.eq(fmt[8].name, 'cardinality')
    return R.eq(fmt[8].is_nullable, true)
  end)
  return R.it("a pre-migration row (7 columns, no cardinality) reads as 'one'", function()
    local rid = 'rel_card_legacy_row'
    box.space._tdb_relations:insert({
      rid,
      src_id,
      f_legacy.id,
      tgt_id,
      tgt_seq_id,
      'legacy_rel',
      ''
    })
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    local found = false
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      if r.id == rid then
        found = true
        R.eq(r.cardinality, 'one')
      end
    end
    return R.ok(found, 'legacy relation must be listed')
  end)
end)
R.describe("Relation cardinality — API", function()
  R.it("createRelation without cardinality defaults to 'one'", function()
    local res = Mutation.createRelation({ }, {
      input = {
        name = 'rel_one',
        fromSpaceId = src_id,
        fromFieldId = f_one.id,
        toSpaceId = tgt_id,
        toFieldId = tgt_seq_id,
        reprFormula = '@repr'
      }
    }, CTX)
    R.ok(res)
    R.eq(res.cardinality, 'one')
    R.eq(res.reprFormula, '@repr')
    rel_one_id = res.id
  end)
  R.it("createRelation with cardinality 'many' stores 'many'", function()
    local res = Mutation.createRelation({ }, {
      input = {
        name = 'rel_many',
        fromSpaceId = src_id,
        fromFieldId = f_many.id,
        toSpaceId = tgt_id,
        toFieldId = tgt_code_id,
        cardinality = 'many'
      }
    }, CTX)
    R.ok(res)
    R.eq(res.cardinality, 'many')
    rel_many_id = res.id
  end)
  R.it("createRelation on the duplicated target field defaults to 'one'", function()
    local res = Mutation.createRelation({ }, {
      input = {
        name = 'rel_dup_one',
        fromSpaceId = src_id,
        fromFieldId = f_dup.id,
        toSpaceId = tgt_id,
        toFieldId = tgt_code_id
      }
    }, CTX)
    R.ok(res)
    R.eq(res.cardinality, 'one')
    rel_dup_id = res.id
  end)
  R.it("invalid cardinality is rejected with a clear error on create", function()
    return R.raises((function()
      return Mutation.createRelation(nil, {
        input = {
          name = 'rel_bad',
          fromSpaceId = src_id,
          fromFieldId = f_dup.id,
          toSpaceId = tgt_id,
          toFieldId = tgt_code_id,
          cardinality = 'several'
        }
      }, CTX)
    end), 'Invalid relation cardinality')
  end)
  R.it("invalid cardinality is rejected with a clear error on update", function()
    return R.raises((function()
      return Mutation.updateRelation(nil, {
        id = rel_one_id,
        input = {
          cardinality = 'lots'
        }
      }, CTX)
    end), 'Invalid relation cardinality')
  end)
  R.it("updateRelation changes the cardinality and keeps reprFormula", function()
    local res = Mutation.updateRelation({ }, {
      id = rel_one_id,
      input = {
        cardinality = 'many'
      }
    }, CTX)
    R.ok(res)
    R.eq(res.cardinality, 'many')
    R.eq(res.reprFormula, '@repr', 'reprFormula must survive a cardinality-only update')
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      if r.id == rel_one_id then
        R.eq(r.cardinality, 'many', 'readback')
      end
    end
    local res2 = Mutation.updateRelation({ }, {
      id = rel_one_id,
      input = {
        cardinality = 'one'
      }
    }, CTX)
    return R.eq(res2.cardinality, 'one')
  end)
  return R.it("GraphQL relations query returns cardinality", function()
    local q = [[      query($spaceId: ID!) {
        relations(spaceId: $spaceId) {
          id
          name
          cardinality
        }
      }
    ]]
    local res = execute({
      query = q,
      variables = {
        spaceId = src_id
      },
      context = CTX
    })
    if res.errors then
      error(json.encode(res.errors))
    end
    R.ok(res.data.relations, 'relations payload')
    local found_one, found_many = false, false
    local _list_0 = res.data.relations
    for _index_0 = 1, #_list_0 do
      local r = _list_0[_index_0]
      if r.id == rel_one_id then
        found_one = true
        R.eq(r.cardinality, 'one')
      end
      if r.id == rel_many_id then
        found_many = true
        R.eq(r.cardinality, 'many')
      end
    end
    R.ok(found_one, 'relation one must be in the GraphQL list')
    return R.ok(found_many, 'relation many must be in the GraphQL list')
  end)
end)
R.describe("Relation cardinality — classification", function()
  R.it("declared cardinality decides single vs multiple", function()
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(src_id)
    R.ok(single_map['fk_one'], "'one' relation must be single")
    R.ok(single_map['fk_dup_one'], "duplicated target field declared 'one' must be single")
    R.is_nil(multiple_map['fk_dup_one'])
    R.ok(single_map['fk_legacy'], 'legacy relation must be single')
    R.ok(multiple_map['fk_many'], "'many' relation must be multiple")
    return R.is_nil(single_map['fk_many'])
  end)
  return R.it("classification does not change once 50 records are inserted", function()
    for i = 1, 50 do
      data_Mutation.insertRecord({ }, {
        spaceId = tgt_id,
        data = {
          code = 'shared'
        }
      }, CTX)
    end
    local data_sp = box.space["data_" .. tostring(SP_TGT)]
    R.eq(data_sp:count(), 50)
    local single_map, multiple_map = triggers.build_single_and_multiple_maps(src_id)
    R.ok(single_map['fk_dup_one'], 'declared one stays single with duplicated data')
    R.is_nil(multiple_map['fk_dup_one'])
    R.ok(multiple_map['fk_many'], 'declared many stays multiple')
    R.ok(single_map['fk_one'], "'one' relation unchanged")
    return R.ok(single_map['fk_legacy'], 'legacy relation unchanged')
  end)
end)
local _list_0 = box.space._tdb_relations.index.by_from:select({
  src_id
})
for _index_0 = 1, #_list_0 do
  local t = _list_0[_index_0]
  box.space._tdb_relations:delete({
    t[1]
  })
end
spaces_mod.delete_user_space(SP_SRC)
return spaces_mod.delete_user_space(SP_TGT)
