-- tests/test_relations.moon
-- Tests FK relation behavior: create_relation, list_relations, update_relation
-- (reprFormula), delete_relation.
-- Requires Tarantool (box already initialized in run.moon).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
{ :Query, :Mutation } = require 'resolvers.schema_resolvers'

SUFFIX  = tostring math.random(100000, 999999)
SP_SRC  = "rel_src_#{SUFFIX}"  -- source space (contains FK field)
SP_TGT  = "rel_tgt_#{SUFFIX}"  -- target space

-- Minimal authenticated context (require_auth only checks user_id presence)
CTX = { user_id: 'test-user' }

src_id, tgt_id, src_fk_field_id, tgt_seq_field_id, rel_id = nil, nil, nil, nil, nil

-- ── Fixture: create two spaces and required fields ───────────────────────────

do
  src = spaces_mod.create_user_space SP_SRC, 'Source space'
  tgt = spaces_mod.create_user_space SP_TGT, 'Target space'
  src_id = src.id
  tgt_id = tgt.id

  -- Sequence field in target space (FK target)
  seq = spaces_mod.add_field tgt_id, 'seq_id', 'Sequence'
  tgt_seq_field_id = seq.id

  -- Int field in source space (stores FK reference)
  fk  = spaces_mod.add_field src_id, 'cible_id', 'Int'
  src_fk_field_id = fk.id

-- ── Tests: relation creation ──────────────────────────────────────────────────

R.describe "Relations — createRelation", ->
  R.it "creates a relation and returns metadata", ->
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

  R.it "without reprFormula -> empty reprFormula", ->
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
    -- Immediate cleanup
    Mutation.deleteRelation {}, { id: tmp.id }, CTX

-- ── Tests: relation query ─────────────────────────────────────────────────────

R.describe "Relations — Query.relations", ->
  R.it "returns relations for source space", ->
    rels = Query.relations {}, { spaceId: src_id }, CTX
    R.ok rels
    found = false
    for r in *rels
      if r.id == rel_id
        found = true
        R.eq r.name,        'src_vers_tgt'
        R.eq r.reprFormula, '@nom'
    R.ok found, "created relation must be listed"

  R.it "does not return relations for another space", ->
    rels = Query.relations {}, { spaceId: tgt_id }, CTX
    for r in *rels
      R.nok (r.id == rel_id), "source relation must not appear for target"

-- ── Tests: formula update ─────────────────────────────────────────────────────

R.describe "Relations — updateRelation (reprFormula)", ->
  R.it "updates reprFormula", ->
    res = Mutation.updateRelation {}, {
      id:    rel_id
      input: { reprFormula: '@prenom .. " " .. @nom' }
    }, CTX
    R.ok res
    R.eq res.id,          rel_id
    R.eq res.reprFormula, '@prenom .. " " .. @nom'

  R.it "new value is persisted (readback)", ->
    rels = Query.relations {}, { spaceId: src_id }, CTX
    for r in *rels
      if r.id == rel_id
        R.eq r.reprFormula, '@prenom .. " " .. @nom'
        return
    R.ok false, "relation not found after update"

  R.it "passing empty reprFormula clears formula", ->
    res = Mutation.updateRelation {}, {
      id:    rel_id
      input: { reprFormula: '' }
    }, CTX
    R.eq res.reprFormula, ''

  R.it "unknown id -> returns nil without crashing", ->
    res = Mutation.updateRelation {}, {
      id:    'unknown-00000000-0000-0000-0000-000000000000'
      input: { reprFormula: '@x' }
    }, CTX
    R.is_nil res

-- ── Tests: deletion ───────────────────────────────────────────────────────────

R.describe "Relations — deleteRelation", ->
  R.it "deletes relation", ->
    ok = Mutation.deleteRelation {}, { id: rel_id }, CTX
    R.ok ok

  R.it "relation no longer appears in list", ->
    rels = Query.relations {}, { spaceId: src_id }, CTX
    for r in *rels
      R.nok (r.id == rel_id), "deleted relation must no longer be listed"

-- ── Cleanup ───────────────────────────────────────────────────────────────────

spaces_mod.delete_user_space SP_SRC
spaces_mod.delete_user_space SP_TGT
