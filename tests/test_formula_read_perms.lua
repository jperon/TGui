local R = require('tests.runner')
local auth = require('core.auth')
local perms_mod = require('core.permissions')
local spaces_mod = require('core.spaces')
local executor = require('graphql.executor')
local dynamic = require('graphql.dynamic')
local data_resolvers = require('resolvers.data_resolvers')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local A_NAME = "frp_a_" .. tostring(SUFFIX)
local B_NAME = "frp_b_" .. tostring(SUFFIX)
local C_NAME = "frp_c_" .. tostring(SUFFIX)
local B_SECRET = "secret-b-" .. tostring(SUFFIX)
local B_LABEL = "label-b-" .. tostring(SUFFIX)
local a_sp = spaces_mod.create_user_space(A_NAME, "formula read perms — source")
local b_sp = spaces_mod.create_user_space(B_NAME, "formula read perms — target")
local c_sp = spaces_mod.create_user_space(C_NAME, "formula read perms — trigger")
local a_id = a_sp.id
local b_id = b_sp.id
local c_id = c_sp.id
spaces_mod.add_field(a_id, 'label', 'String')
local a_fk = spaces_mod.add_field(a_id, 'tgt_id', 'Int')
local b_seq = spaces_mod.add_field(b_id, 'ref_id', 'Sequence')
spaces_mod.add_field(b_id, 'nom', 'String')
spaces_mod.add_field(b_id, 'secret', 'String')
local seen_b_formula = 'space("' .. B_NAME .. '")[1] and space("' .. B_NAME .. '")[1].secret or "none"'
spaces_mod.add_field(a_id, 'seen_b', 'String', false, '', seen_b_formula, nil, 'lua')
spaces_mod.add_field(a_id, 'via_fk', 'String', false, '', 'self.tgt_id and self.tgt_id.nom or "none"', nil, 'lua')
local rel_id = tostring(require('uuid').new())
box.space._tdb_relations:insert({
  rel_id,
  a_id,
  a_fk.id,
  b_id,
  b_seq.id,
  'link_to_b'
})
box.space["data_" .. tostring(A_NAME)]:insert({
  'frp-a-1',
  json.encode({
    label = 'row-a',
    tgt_id = 1
  })
})
box.space["data_" .. tostring(B_NAME)]:insert({
  'frp-b-1',
  json.encode({
    ref_id = 1,
    nom = B_LABEL,
    secret = B_SECRET
  })
})
local trig_formula = 'space("' .. B_NAME .. '")[1] and space("' .. B_NAME .. '")[1].secret or "none"'
spaces_mod.add_field(c_id, 'input', 'String')
spaces_mod.add_field(c_id, 'trig_b', 'String', false, '', trig_formula, { }, 'lua')
require('core.triggers').register_space_trigger(C_NAME)
require('resolvers.init').reinit()
local A_T = dynamic.gql_name(A_NAME)
local make_user
make_user = function(prefix)
  local user = auth.create_user(tostring(prefix) .. "_" .. tostring(SUFFIX), tostring(prefix) .. "_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
  local sess = auth.create_session(user.id)
  return {
    user = user,
    token = sess.token
  }
end
local ctx_of
ctx_of = function(a)
  return {
    user_id = a.user.id,
    token = a.token
  }
end
local grant_read
grant_read = function(user, resource_ids)
  local grp = perms_mod.create_group("fpg_" .. tostring(user.username) .. "_" .. tostring(SUFFIX), '')
  for _index_0 = 1, #resource_ids do
    local rid = resource_ids[_index_0]
    perms_mod.grant(grp.id, 'space', rid, 'read')
  end
  perms_mod.add_member(user.id, grp.id)
  return grp
end
local actor_a = make_user('frpa')
local grp_a = grant_read(actor_a.user, {
  a_id
})
local actor_ab = make_user('frpab')
local grp_ab = grant_read(actor_ab.user, {
  a_id,
  b_id
})
local admin_user = auth.get_user_by_username('admin')
local admin_sess = auth.create_session(admin_user.id)
local admin_ctx = {
  user_id = admin_user.id,
  token = admin_sess.token
}
local run_q
run_q = function(query, ctx)
  return executor.execute({
    query = query,
    context = ctx
  })
end
local errs_json
errs_json = function(res)
  return json.encode(res.errors or { })
end
local leaks
leaks = function(res, needle)
  local encoded = json.encode(res.data)
  return encoded:find(needle, 1, true) ~= nil
end
R.describe("Formula read permissions — indirect reads", function()
  R.it("fixture: typed query with formula fields exists", function()
    local res = run_q("{ " .. tostring(A_T) .. " { items { label } } }", admin_ctx)
    R.nok(res.errors, errs_json(res))
    return R.eq(#res.data[A_T].items, 1)
  end)
  R.it("space('B') in a formula column does not leak B without read", function()
    local res = run_q("{ " .. tostring(A_T) .. " { items { seen_b } } }", ctx_of(actor_a))
    R.nok(res.errors, errs_json(res))
    R.eq(res.data[A_T].items[1].seen_b, 'none', "space() must yield an empty list")
    return R.nok((leaks(res, B_SECRET)), "B data must not leak through space()")
  end)
  R.it("FK traversal in a formula does not leak B without read", function()
    local res = run_q("{ " .. tostring(A_T) .. " { items { via_fk tgt_id { nom } } } }", ctx_of(actor_a))
    R.nok(res.errors, errs_json(res))
    local item = res.data[A_T].items[1]
    R.eq(item.via_fk, 'none', "FK traversal must resolve to nil")
    R.eq(type(item.tgt_id), 'cdata', "typed FK field must be null")
    R.nok((leaks(res, B_LABEL)), "B label must not leak")
    return R.nok((leaks(res, B_SECRET)), "B secret must not leak")
  end)
  R.it("witness with read on A and B sees B data as before", function()
    local res = run_q("{ " .. tostring(A_T) .. " { items { label seen_b via_fk tgt_id { nom } } } }", ctx_of(actor_ab))
    R.nok(res.errors, errs_json(res))
    local item = res.data[A_T].items[1]
    R.eq(item.seen_b, B_SECRET)
    R.eq(item.via_fk, B_LABEL)
    return R.eq(item.tgt_id.nom, B_LABEL)
  end)
  R.it("admin sees B data on every path", function()
    local res = run_q("{ " .. tostring(A_T) .. " { items { label seen_b via_fk tgt_id { nom } } } }", admin_ctx)
    R.nok(res.errors, errs_json(res))
    local item = res.data[A_T].items[1]
    R.eq(item.seen_b, B_SECRET)
    R.eq(item.via_fk, B_LABEL)
    return R.eq(item.tgt_id.nom, B_LABEL)
  end)
  return R.it("write-time trigger formula reading space('B') still works", function()
    local res = data_resolvers.Mutation.insertRecord(nil, {
      spaceId = c_id,
      data = {
        input = 'x'
      }
    }, admin_ctx)
    R.ok(res.id, "insertRecord must return the new id")
    local row = json.decode((box.space["data_" .. tostring(C_NAME)]:get(res.id))[2])
    return R.eq(row.trig_b, B_SECRET, "write-time trigger keeps full access")
  end)
end)
local _list_0 = {
  actor_a,
  actor_ab
}
for _index_0 = 1, #_list_0 do
  local a = _list_0[_index_0]
  auth.delete_session(a.token)
  box.space._tdb_users:delete(a.user.id)
end
auth.delete_session(admin_sess.token)
perms_mod.delete_group(grp_a.id)
perms_mod.delete_group(grp_ab.id)
box.space._tdb_relations:delete(rel_id)
spaces_mod.delete_user_space(A_NAME)
spaces_mod.delete_user_space(B_NAME)
spaces_mod.delete_user_space(C_NAME)
return require('resolvers.init').reinit()
