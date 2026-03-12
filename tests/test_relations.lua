local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local Query, Mutation
do
  local _obj_0 = require('resolvers.schema_resolvers')
  Query, Mutation = _obj_0.Query, _obj_0.Mutation
end
local SUFFIX = tostring(math.random(100000, 999999))
local SP_SRC = "rel_src_" .. tostring(SUFFIX)
local SP_TGT = "rel_tgt_" .. tostring(SUFFIX)
local CTX = {
  user_id = 'test-user'
}
local src_id, tgt_id, src_fk_field_id, tgt_seq_field_id, rel_id = nil, nil, nil, nil, nil
do
  local src = spaces_mod.create_user_space(SP_SRC, 'Source space')
  local tgt = spaces_mod.create_user_space(SP_TGT, 'Target space')
  src_id = src.id
  tgt_id = tgt.id
  local seq = spaces_mod.add_field(tgt_id, 'seq_id', 'Sequence')
  tgt_seq_field_id = seq.id
  local fk = spaces_mod.add_field(src_id, 'cible_id', 'Int')
  src_fk_field_id = fk.id
end
R.describe("Relations — createRelation", function()
  R.it("creates a relation and returns metadata", function()
    local res = Mutation.createRelation({ }, {
      input = {
        name = 'src_vers_tgt',
        fromSpaceId = src_id,
        fromFieldId = src_fk_field_id,
        toSpaceId = tgt_id,
        toFieldId = tgt_seq_field_id,
        reprFormula = '@nom'
      }
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    R.eq(res.name, 'src_vers_tgt')
    R.eq(res.fromSpaceId, src_id)
    R.eq(res.toSpaceId, tgt_id)
    R.eq(res.reprFormula, '@nom')
    rel_id = res.id
  end)
  return R.it("without reprFormula -> empty reprFormula", function()
    local tmp = Mutation.createRelation({ }, {
      input = {
        name = 'tmp_rel',
        fromSpaceId = src_id,
        fromFieldId = src_fk_field_id,
        toSpaceId = tgt_id,
        toFieldId = tgt_seq_field_id
      }
    }, CTX)
    R.ok(tmp)
    R.eq(tmp.reprFormula, '')
    return Mutation.deleteRelation({ }, {
      id = tmp.id
    }, CTX)
  end)
end)
R.describe("Relations — Query.relations", function()
  R.it("returns relations for source space", function()
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    R.ok(rels)
    local found = false
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      if r.id == rel_id then
        found = true
        R.eq(r.name, 'src_vers_tgt')
        R.eq(r.reprFormula, '@nom')
      end
    end
    return R.ok(found, "created relation must be listed")
  end)
  return R.it("does not return relations for another space", function()
    local rels = Query.relations({ }, {
      spaceId = tgt_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      R.nok((r.id == rel_id), "source relation must not appear for target")
    end
  end)
end)
R.describe("Relations — updateRelation (reprFormula)", function()
  R.it("updates reprFormula", function()
    local res = Mutation.updateRelation({ }, {
      id = rel_id,
      input = {
        reprFormula = '@prenom .. " " .. @nom'
      }
    }, CTX)
    R.ok(res)
    R.eq(res.id, rel_id)
    return R.eq(res.reprFormula, '@prenom .. " " .. @nom')
  end)
  R.it("new value is persisted (readback)", function()
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      if r.id == rel_id then
        R.eq(r.reprFormula, '@prenom .. " " .. @nom')
        return 
      end
    end
    return R.ok(false, "relation not found after update")
  end)
  R.it("passing empty reprFormula clears formula", function()
    local res = Mutation.updateRelation({ }, {
      id = rel_id,
      input = {
        reprFormula = ''
      }
    }, CTX)
    return R.eq(res.reprFormula, '')
  end)
  return R.it("unknown id -> returns nil without crashing", function()
    local res = Mutation.updateRelation({ }, {
      id = 'unknown-00000000-0000-0000-0000-000000000000',
      input = {
        reprFormula = '@x'
      }
    }, CTX)
    return R.is_nil(res)
  end)
end)
R.describe("Relations — deleteRelation", function()
  R.it("deletes relation", function()
    local ok = Mutation.deleteRelation({ }, {
      id = rel_id
    }, CTX)
    return R.ok(ok)
  end)
  return R.it("relation no longer appears in list", function()
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      R.nok((r.id == rel_id), "deleted relation must no longer be listed")
    end
  end)
end)
spaces_mod.delete_user_space(SP_SRC)
return spaces_mod.delete_user_space(SP_TGT)
