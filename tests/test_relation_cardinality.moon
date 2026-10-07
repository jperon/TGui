-- tests/test_relation_cardinality.moon
-- Declared relation cardinality ('one' | 'many'): storage, GraphQL API and
-- classification of relations (no data-content heuristic any more).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
triggers = require 'core.triggers'
json = require 'json'
{ :Query, :Mutation } = require 'resolvers.schema_resolvers'
{ :execute } = require 'graphql.executor'
{ Mutation: data_Mutation } = require 'resolvers.data_resolvers'
{ :trusted_ctx } = require 'resolvers.utils'

SUFFIX = tostring math.random 100000, 999999
SP_SRC = "card_src_#{SUFFIX}"
SP_TGT = "card_tgt_#{SUFFIX}"
CTX = trusted_ctx 'test-user'

src_id, tgt_id = nil, nil
tgt_seq_id, tgt_code_id = nil, nil
f_one, f_dup, f_many, f_legacy = nil, nil, nil, nil
rel_one_id, rel_many_id, rel_dup_id = nil, nil, nil

-- ── Fixture: one source space (FK fields) and one target space ────────────────

do
  src = spaces_mod.create_user_space SP_SRC, 'Cardinality source'
  tgt = spaces_mod.create_user_space SP_TGT, 'Cardinality target'
  src_id = src.id
  tgt_id = tgt.id

  seq  = spaces_mod.add_field tgt_id, 'seq_id', 'Sequence'
  code = spaces_mod.add_field tgt_id, 'code', 'String'
  tgt_seq_id  = seq.id
  tgt_code_id = code.id

  f_one    = spaces_mod.add_field src_id, 'fk_one', 'Int'
  f_dup    = spaces_mod.add_field src_id, 'fk_dup_one', 'Int'
  f_many   = spaces_mod.add_field src_id, 'fk_many', 'String'
  f_legacy = spaces_mod.add_field src_id, 'fk_legacy', 'Int'

  require('resolvers.init').reinit!

-- ── Storage ──────────────────────────────────────────────────────────────────

R.describe "Relation cardinality — storage", ->
  R.it "_tdb_relations exposes a nullable 8th cardinality column", ->
    fmt = box.space._tdb_relations\format!
    R.eq #fmt, 8, 'format field count'
    R.eq fmt[8].name, 'cardinality'
    R.eq fmt[8].is_nullable, true

  R.it "a pre-migration row (7 columns, no cardinality) reads as 'one'", ->
    rid = 'rel_card_legacy_row'
    box.space._tdb_relations\insert { rid, src_id, f_legacy.id, tgt_id, tgt_seq_id, 'legacy_rel', '' }

    rels = Query.relations {}, { spaceId: src_id }, CTX
    found = false
    for r in *rels
      if r.id == rid
        found = true
        R.eq r.cardinality, 'one'
    R.ok found, 'legacy relation must be listed'

-- ── GraphQL API ──────────────────────────────────────────────────────────────

R.describe "Relation cardinality — API", ->
  R.it "createRelation without cardinality defaults to 'one'", ->
    res = Mutation.createRelation {}, {
      input: {
        name:        'rel_one'
        fromSpaceId: src_id
        fromFieldId: f_one.id
        toSpaceId:   tgt_id
        toFieldId:   tgt_seq_id
        reprFormula: '@repr'
      }
    }, CTX
    R.ok res
    R.eq res.cardinality, 'one'
    R.eq res.reprFormula, '@repr'
    rel_one_id = res.id

  R.it "createRelation with cardinality 'many' stores 'many'", ->
    res = Mutation.createRelation {}, {
      input: {
        name:        'rel_many'
        fromSpaceId: src_id
        fromFieldId: f_many.id
        toSpaceId:   tgt_id
        toFieldId:   tgt_code_id
        cardinality: 'many'
      }
    }, CTX
    R.ok res
    R.eq res.cardinality, 'many'
    rel_many_id = res.id

  R.it "createRelation on the duplicated target field defaults to 'one'", ->
    res = Mutation.createRelation {}, {
      input: {
        name:        'rel_dup_one'
        fromSpaceId: src_id
        fromFieldId: f_dup.id
        toSpaceId:   tgt_id
        toFieldId:   tgt_code_id
      }
    }, CTX
    R.ok res
    R.eq res.cardinality, 'one'
    rel_dup_id = res.id

  R.it "invalid cardinality is rejected with a clear error on create", ->
    R.raises (->
      Mutation.createRelation nil, {
        input: {
          name:        'rel_bad'
          fromSpaceId: src_id
          fromFieldId: f_dup.id
          toSpaceId:   tgt_id
          toFieldId:   tgt_code_id
          cardinality: 'several'
        }
      }, CTX
    ), 'Invalid relation cardinality'

  R.it "invalid cardinality is rejected with a clear error on update", ->
    R.raises (->
      Mutation.updateRelation nil, { id: rel_one_id, input: { cardinality: 'lots' } }, CTX
    ), 'Invalid relation cardinality'

  R.it "updateRelation changes the cardinality and keeps reprFormula", ->
    res = Mutation.updateRelation {}, { id: rel_one_id, input: { cardinality: 'many' } }, CTX
    R.ok res
    R.eq res.cardinality, 'many'
    R.eq res.reprFormula, '@repr', 'reprFormula must survive a cardinality-only update'

    rels = Query.relations {}, { spaceId: src_id }, CTX
    for r in *rels
      if r.id == rel_one_id
        R.eq r.cardinality, 'many', 'readback'

    res2 = Mutation.updateRelation {}, { id: rel_one_id, input: { cardinality: 'one' } }, CTX
    R.eq res2.cardinality, 'one'

  R.it "GraphQL relations query returns cardinality", ->
    q = [[
      query($spaceId: ID!) {
        relations(spaceId: $spaceId) {
          id
          name
          cardinality
        }
      }
    ]]
    res = execute { query: q, variables: { spaceId: src_id }, context: CTX }
    if res.errors
      error json.encode res.errors
    R.ok res.data.relations, 'relations payload'

    found_one, found_many = false, false
    for r in *res.data.relations
      if r.id == rel_one_id
        found_one = true
        R.eq r.cardinality, 'one'
      if r.id == rel_many_id
        found_many = true
        R.eq r.cardinality, 'many'
    R.ok found_one, 'relation one must be in the GraphQL list'
    R.ok found_many, 'relation many must be in the GraphQL list'

-- ── Classification (build_single_and_multiple_maps) ──────────────────────────

R.describe "Relation cardinality — classification", ->
  R.it "declared cardinality decides single vs multiple", ->
    single_map, multiple_map = triggers.build_single_and_multiple_maps src_id

    R.ok single_map['fk_one'], "'one' relation must be single"
    R.ok single_map['fk_dup_one'], "duplicated target field declared 'one' must be single"
    R.is_nil multiple_map['fk_dup_one']
    R.ok single_map['fk_legacy'], 'legacy relation must be single'
    R.ok multiple_map['fk_many'], "'many' relation must be multiple"
    R.is_nil single_map['fk_many']

  R.it "classification does not change once 50 records are inserted", ->
    -- 50 target records sharing the same code value: the removed heuristic
    -- (avg 50 > 1.5, total 50 > 10, max 50 > 2) classified fk_dup_one as
    -- multiple. The declared cardinality must win over the data.
    for i = 1, 50
      data_Mutation.insertRecord {}, { spaceId: tgt_id, data: { code: 'shared' } }, CTX

    data_sp = box.space["data_#{SP_TGT}"]
    R.eq data_sp\count!, 50

    single_map, multiple_map = triggers.build_single_and_multiple_maps src_id

    R.ok single_map['fk_dup_one'], 'declared one stays single with duplicated data'
    R.is_nil multiple_map['fk_dup_one']
    R.ok multiple_map['fk_many'], 'declared many stays multiple'
    R.ok single_map['fk_one'], "'one' relation unchanged"
    R.ok single_map['fk_legacy'], 'legacy relation unchanged'

-- ── Cleanup ──────────────────────────────────────────────────────────────────

for t in *box.space._tdb_relations.index.by_from\select { src_id }
  box.space._tdb_relations\delete { t[1] }
spaces_mod.delete_user_space SP_SRC
spaces_mod.delete_user_space SP_TGT
