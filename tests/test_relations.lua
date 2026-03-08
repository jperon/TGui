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
local src_id, tgt_id, src_fk_field_id, tgt_seq_field_id, rel_id
do
  local src = spaces_mod.create_user_space(SP_SRC, 'Espace source')
  local tgt = spaces_mod.create_user_space(SP_TGT, 'Espace cible')
  src_id = src.id
  tgt_id = tgt.id
  local seq = spaces_mod.add_field(tgt_id, 'seq_id', 'Sequence')
  tgt_seq_field_id = seq.id
  local fk = spaces_mod.add_field(src_id, 'cible_id', 'Int')
  src_fk_field_id = fk.id
end
R.describe("Relations — createRelation", function()
  R.it("crée une relation et retourne les métadonnées", function()
    local res = Mutation.createRelation({ }, {
      input = {
        name = 'src_vers_tgt',
        fromSpaceId = src_id,
        fromFieldId = src_fk_field_id,
        toSpaceId = tgt_id,
        toFieldId = tgt_seq_field_id,
        reprFormula = 'row.nom'
      }
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    R.eq(res.name, 'src_vers_tgt')
    R.eq(res.fromSpaceId, src_id)
    R.eq(res.toSpaceId, tgt_id)
    R.eq(res.reprFormula, 'row.nom')
    rel_id = res.id
  end)
  return R.it("sans reprFormula → reprFormula vide", function()
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
  R.it("retourne les relations de l'espace source", function()
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
        R.eq(r.reprFormula, 'row.nom')
      end
    end
    return R.ok(found, "relation créée doit être listée")
  end)
  return R.it("ne retourne pas les relations d'un autre espace", function()
    local rels = Query.relations({ }, {
      spaceId = tgt_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      R.nok((r.id == rel_id), "relation de src ne doit pas apparaître pour tgt")
    end
  end)
end)
R.describe("Relations — updateRelation (reprFormula)", function()
  R.it("met à jour reprFormula", function()
    local res = Mutation.updateRelation({ }, {
      id = rel_id,
      input = {
        reprFormula = 'row.prenom + " " + row.nom'
      }
    }, CTX)
    R.ok(res)
    R.eq(res.id, rel_id)
    return R.eq(res.reprFormula, 'row.prenom + " " + row.nom')
  end)
  R.it("la nouvelle valeur est persistée (relecture)", function()
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      if r.id == rel_id then
        R.eq(r.reprFormula, 'row.prenom + " " + row.nom')
        return 
      end
    end
    return R.ok(false, "relation introuvable après update")
  end)
  R.it("passer reprFormula vide efface la formule", function()
    local res = Mutation.updateRelation({ }, {
      id = rel_id,
      input = {
        reprFormula = ''
      }
    }, CTX)
    return R.eq(res.reprFormula, '')
  end)
  return R.it("id inconnu → retourne nil sans planter", function()
    local res = Mutation.updateRelation({ }, {
      id = 'inconnu-00000000-0000-0000-0000-000000000000',
      input = {
        reprFormula = 'row.x'
      }
    }, CTX)
    return R.is_nil(res)
  end)
end)
R.describe("Relations — deleteRelation", function()
  R.it("supprime la relation", function()
    local ok = Mutation.deleteRelation({ }, {
      id = rel_id
    }, CTX)
    return R.ok(ok)
  end)
  return R.it("la relation n'apparaît plus dans la liste", function()
    local rels = Query.relations({ }, {
      spaceId = src_id
    }, CTX)
    for _index_0 = 1, #rels do
      local r = rels[_index_0]
      R.nok((r.id == rel_id), "relation supprimée ne doit plus être listée")
    end
  end)
end)
spaces_mod.delete_user_space(SP_SRC)
return spaces_mod.delete_user_space(SP_TGT)
