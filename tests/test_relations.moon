-- tests/test_relations.moon
-- Tests des relations FK : create_relation, list_relations, update_relation
-- (reprFormula), delete_relation.
-- Nécessite Tarantool (box déjà initialisé dans run.moon).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
{ :Query, :Mutation } = require 'resolvers.schema_resolvers'

SUFFIX  = tostring math.random(100000, 999999)
SP_SRC  = "rel_src_#{SUFFIX}"  -- espace source (contient le champ FK)
SP_TGT  = "rel_tgt_#{SUFFIX}"  -- espace cible

-- Contexte authentifié minimal (require_auth vérifie juste que user_id est défini)
CTX = { user_id: 'test-user' }

local src_id, tgt_id, src_fk_field_id, tgt_seq_field_id, rel_id

-- ── Fixture : créer deux espaces et les champs nécessaires ───────────────────

do
  src = spaces_mod.create_user_space SP_SRC, 'Espace source'
  tgt = spaces_mod.create_user_space SP_TGT, 'Espace cible'
  src_id = src.id
  tgt_id = tgt.id

  -- Champ Sequence dans l'espace cible (cible du FK)
  seq = spaces_mod.add_field tgt_id, 'seq_id', 'Sequence'
  tgt_seq_field_id = seq.id

  -- Champ Int dans l'espace source (stocke la référence)
  fk  = spaces_mod.add_field src_id, 'cible_id', 'Int'
  src_fk_field_id = fk.id

-- ── Tests : création de relation ─────────────────────────────────────────────

R.describe "Relations — createRelation", ->
  R.it "crée une relation et retourne les métadonnées", ->
    res = Mutation.createRelation {}, {
      input: {
        name:        'src_vers_tgt'
        fromSpaceId: src_id
        fromFieldId: src_fk_field_id
        toSpaceId:   tgt_id
        toFieldId:   tgt_seq_field_id
        reprFormula: '@nom'
      }
    }, CTX
    R.ok res
    R.ok res.id
    R.eq res.name,        'src_vers_tgt'
    R.eq res.fromSpaceId, src_id
    R.eq res.toSpaceId,   tgt_id
    R.eq res.reprFormula, '@nom'
    rel_id = res.id

  R.it "sans reprFormula → reprFormula vide", ->
    tmp = Mutation.createRelation {}, {
      input: {
        name:        'tmp_rel'
        fromSpaceId: src_id
        fromFieldId: src_fk_field_id
        toSpaceId:   tgt_id
        toFieldId:   tgt_seq_field_id
      }
    }, CTX
    R.ok tmp
    R.eq tmp.reprFormula, ''
    -- Nettoyage immédiat
    Mutation.deleteRelation {}, { id: tmp.id }, CTX

-- ── Tests : lecture des relations ────────────────────────────────────────────

R.describe "Relations — Query.relations", ->
  R.it "retourne les relations de l'espace source", ->
    rels = Query.relations {}, { spaceId: src_id }, CTX
    R.ok rels
    found = false
    for r in *rels
      if r.id == rel_id
        found = true
        R.eq r.name,        'src_vers_tgt'
        R.eq r.reprFormula, '@nom'
    R.ok found, "relation créée doit être listée"

  R.it "ne retourne pas les relations d'un autre espace", ->
    rels = Query.relations {}, { spaceId: tgt_id }, CTX
    for r in *rels
      R.nok (r.id == rel_id), "relation de src ne doit pas apparaître pour tgt"

-- ── Tests : mise à jour de la formule ────────────────────────────────────────

R.describe "Relations — updateRelation (reprFormula)", ->
  R.it "met à jour reprFormula", ->
    res = Mutation.updateRelation {}, {
      id:    rel_id
      input: { reprFormula: '@prenom .. " " .. @nom' }
    }, CTX
    R.ok res
    R.eq res.id,          rel_id
    R.eq res.reprFormula, '@prenom .. " " .. @nom'

  R.it "la nouvelle valeur est persistée (relecture)", ->
    rels = Query.relations {}, { spaceId: src_id }, CTX
    for r in *rels
      if r.id == rel_id
        R.eq r.reprFormula, '@prenom .. " " .. @nom'
        return
    R.ok false, "relation introuvable après update"

  R.it "passer reprFormula vide efface la formule", ->
    res = Mutation.updateRelation {}, {
      id:    rel_id
      input: { reprFormula: '' }
    }, CTX
    R.eq res.reprFormula, ''

  R.it "id inconnu → retourne nil sans planter", ->
    res = Mutation.updateRelation {}, {
      id:    'inconnu-00000000-0000-0000-0000-000000000000'
      input: { reprFormula: '@x' }
    }, CTX
    R.is_nil res

-- ── Tests : suppression ──────────────────────────────────────────────────────

R.describe "Relations — deleteRelation", ->
  R.it "supprime la relation", ->
    ok = Mutation.deleteRelation {}, { id: rel_id }, CTX
    R.ok ok

  R.it "la relation n'apparaît plus dans la liste", ->
    rels = Query.relations {}, { spaceId: src_id }, CTX
    for r in *rels
      R.nok (r.id == rel_id), "relation supprimée ne doit plus être listée"

-- ── Nettoyage ────────────────────────────────────────────────────────────────

spaces_mod.delete_user_space SP_SRC
spaces_mod.delete_user_space SP_TGT
