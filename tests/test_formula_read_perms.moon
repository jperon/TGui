-- tests/test_formula_read_perms.moon
-- Formula columns and FK traversal must not read a space the requesting user
-- has no `read` grant on. Covers the two indirect vectors in
-- core/triggers.moon: the space(name) helper and the FK walk (ensure_space).
-- A user with read on A but not on B must get no B data through a formula that
-- calls space('B'), nor through an FK traversal of a formula. A witness with
-- read on both, and an admin, keep the previous behaviour. Write-time trigger
-- formulas (no request user) stay unrestricted.

R              = require 'tests.runner'
auth           = require 'core.auth'
perms_mod      = require 'core.permissions'
spaces_mod     = require 'core.spaces'
executor       = require 'graphql.executor'
dynamic        = require 'graphql.dynamic'
data_resolvers = require 'resolvers.data_resolvers'
json           = require 'json'

SUFFIX = tostring math.random 100000, 999999

A_NAME = "frp_a_#{SUFFIX}"
B_NAME = "frp_b_#{SUFFIX}"
C_NAME = "frp_c_#{SUFFIX}"

B_SECRET = "secret-b-#{SUFFIX}"
B_LABEL  = "label-b-#{SUFFIX}"

-- ── Fixture: A -> B relation, formula columns on A, trigger formula on C ──────

a_sp = spaces_mod.create_user_space A_NAME, "formula read perms — source"
b_sp = spaces_mod.create_user_space B_NAME, "formula read perms — target"
c_sp = spaces_mod.create_user_space C_NAME, "formula read perms — trigger"
a_id = a_sp.id
b_id = b_sp.id
c_id = c_sp.id

spaces_mod.add_field a_id, 'label', 'String'
a_fk  = spaces_mod.add_field a_id, 'tgt_id', 'Int'
b_seq = spaces_mod.add_field b_id, 'ref_id', 'Sequence'
spaces_mod.add_field b_id, 'nom', 'String'
spaces_mod.add_field b_id, 'secret', 'String'

-- Formula column reading another space through the space() helper.
seen_b_formula = 'space("' .. B_NAME .. '")[1] and space("' .. B_NAME .. '")[1].secret or "none"'
spaces_mod.add_field a_id, 'seen_b', 'String', false, '', seen_b_formula, nil, 'lua'
-- Formula column traversing the FK to B (self proxy ensure_space path).
spaces_mod.add_field a_id, 'via_fk', 'String', false, '', 'self.tgt_id and self.tgt_id.nom or "none"', nil, 'lua'

rel_id = tostring require('uuid').new!
box.space._tdb_relations\insert { rel_id, a_id, a_fk.id, b_id, b_seq.id, 'link_to_b' }

box.space["data_#{A_NAME}"]\insert { 'frp-a-1', json.encode { label: 'row-a', tgt_id: 1 } }
box.space["data_#{B_NAME}"]\insert { 'frp-b-1', json.encode { ref_id: 1, nom: B_LABEL, secret: B_SECRET } }

-- Trigger formula on C reading space('B'); evaluated server-side at write time.
trig_formula = 'space("' .. B_NAME .. '")[1] and space("' .. B_NAME .. '")[1].secret or "none"'
spaces_mod.add_field c_id, 'input', 'String'
spaces_mod.add_field c_id, 'trig_b', 'String', false, '', trig_formula, {}, 'lua'
require('core.triggers').register_space_trigger C_NAME

require('resolvers.init').reinit!

A_T = dynamic.gql_name A_NAME

-- ── Actors ───────────────────────────────────────────────────────────────────

make_user = (prefix) ->
  user = auth.create_user "#{prefix}_#{SUFFIX}", "#{prefix}_#{SUFFIX}@test.local", "pass1234"
  sess = auth.create_session user.id
  { user: user, token: sess.token }

ctx_of = (a) -> { user_id: a.user.id, token: a.token }

grant_read = (user, resource_ids) ->
  grp = perms_mod.create_group "fpg_#{user.username}_#{SUFFIX}", ''
  for rid in *resource_ids
    perms_mod.grant grp.id, 'space', rid, 'read'
  perms_mod.add_member user.id, grp.id
  grp

actor_a  = make_user 'frpa'
grp_a    = grant_read actor_a.user, { a_id }
actor_ab = make_user 'frpab'
grp_ab   = grant_read actor_ab.user, { a_id, b_id }
admin_user = auth.get_user_by_username 'admin'
admin_sess = auth.create_session admin_user.id
admin_ctx  = { user_id: admin_user.id, token: admin_sess.token }

-- ── Helpers ──────────────────────────────────────────────────────────────────

run_q = (query, ctx) -> executor.execute { query: query, context: ctx }

errs_json = (res) -> json.encode(res.errors or {})

-- True when the response payload contains a forbidden needle (plain search).
leaks = (res, needle) ->
  encoded = json.encode res.data
  encoded\find(needle, 1, true) != nil

-- ── Tests ────────────────────────────────────────────────────────────────────

R.describe "Formula read permissions — indirect reads", ->
  R.it "fixture: typed query with formula fields exists", ->
    res = run_q "{ #{A_T} { items { label } } }", admin_ctx
    R.nok res.errors, errs_json res
    R.eq #res.data[A_T].items, 1

  R.it "space('B') in a formula column does not leak B without read", ->
    res = run_q "{ #{A_T} { items { seen_b } } }", ctx_of actor_a
    R.nok res.errors, errs_json res
    R.eq res.data[A_T].items[1].seen_b, 'none', "space() must yield an empty list"
    R.nok (leaks(res, B_SECRET)), "B data must not leak through space()"

  R.it "FK traversal in a formula does not leak B without read", ->
    res = run_q "{ #{A_T} { items { via_fk tgt_id { nom } } } }", ctx_of actor_a
    R.nok res.errors, errs_json res
    item = res.data[A_T].items[1]
    R.eq item.via_fk, 'none', "FK traversal must resolve to nil"
    R.eq type(item.tgt_id), 'cdata', "typed FK field must be null"
    R.nok (leaks(res, B_LABEL)), "B label must not leak"
    R.nok (leaks(res, B_SECRET)), "B secret must not leak"

  R.it "witness with read on A and B sees B data as before", ->
    res = run_q "{ #{A_T} { items { label seen_b via_fk tgt_id { nom } } } }", ctx_of actor_ab
    R.nok res.errors, errs_json res
    item = res.data[A_T].items[1]
    R.eq item.seen_b, B_SECRET
    R.eq item.via_fk, B_LABEL
    R.eq item.tgt_id.nom, B_LABEL

  R.it "admin sees B data on every path", ->
    res = run_q "{ #{A_T} { items { label seen_b via_fk tgt_id { nom } } } }", admin_ctx
    R.nok res.errors, errs_json res
    item = res.data[A_T].items[1]
    R.eq item.seen_b, B_SECRET
    R.eq item.via_fk, B_LABEL
    R.eq item.tgt_id.nom, B_LABEL

  R.it "write-time trigger formula reading space('B') still works", ->
    res = data_resolvers.Mutation.insertRecord nil, { spaceId: c_id, data: { input: 'x' } }, admin_ctx
    R.ok res.id, "insertRecord must return the new id"
    row = json.decode (box.space["data_#{C_NAME}"]\get res.id)[2]
    R.eq row.trig_b, B_SECRET, "write-time trigger keeps full access"

-- ── Cleanup ──────────────────────────────────────────────────────────────────

for a in *{ actor_a, actor_ab }
  auth.delete_session a.token
  box.space._tdb_users\delete a.user.id
auth.delete_session admin_sess.token
perms_mod.delete_group grp_a.id
perms_mod.delete_group grp_ab.id
box.space._tdb_relations\delete rel_id
spaces_mod.delete_user_space A_NAME
spaces_mod.delete_user_space B_NAME
spaces_mod.delete_user_space C_NAME
require('resolvers.init').reinit!
