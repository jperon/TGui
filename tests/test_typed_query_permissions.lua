local R = require('tests.runner')
local auth = require('core.auth')
local perms_mod = require('core.permissions')
local spaces_mod = require('core.spaces')
local executor = require('graphql.executor')
local dynamic = require('graphql.dynamic')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local SRC_NAME = "tqp_src_" .. tostring(SUFFIX)
local TGT_NAME = "tqp_tgt_" .. tostring(SUFFIX)
local src_sp = spaces_mod.create_user_space(SRC_NAME, "typed query permissions — source")
local tgt_sp = spaces_mod.create_user_space(TGT_NAME, "typed query permissions — target")
local src_id = src_sp.id
local tgt_id = tgt_sp.id
spaces_mod.add_field(src_id, 'label', 'String')
local src_fk = spaces_mod.add_field(src_id, 'tgt_id', 'Int')
local tgt_seq = spaces_mod.add_field(tgt_id, 'ref_id', 'Sequence')
spaces_mod.add_field(tgt_id, 'nom', 'String')
local rel_id = tostring(require('uuid').new())
box.space._tdb_relations:insert({
  rel_id,
  src_id,
  src_fk.id,
  tgt_id,
  tgt_seq.id,
  'link_to_tgt'
})
box.space["data_" .. tostring(SRC_NAME)]:insert({
  'tqp-src-1',
  json.encode({
    label = 'src-row',
    tgt_id = 1
  })
})
box.space["data_" .. tostring(TGT_NAME)]:insert({
  'tqp-tgt-1',
  json.encode({
    ref_id = 1,
    nom = 'secret-target'
  })
})
require('resolvers.init').reinit()
local SRC_T = dynamic.gql_name(SRC_NAME)
local TGT_T = dynamic.gql_name(TGT_NAME)
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
grant_read = function(user, resource_id)
  local grp = perms_mod.create_group("tqg_" .. tostring(user.username) .. "_" .. tostring(SUFFIX), '')
  perms_mod.grant(grp.id, 'space', resource_id, 'read')
  perms_mod.add_member(user.id, grp.id)
  return grp
end
local actor_none = make_user('tqnone')
local actor_src = make_user('tqsrc')
local grp_src = grant_read(actor_src.user, src_id)
local actor_tgt = make_user('tqtgt')
local grp_tgt = grant_read(actor_tgt.user, tgt_id)
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
local has_error
has_error = function(res, pattern)
  if not (res.errors) then
    return false
  end
  local _list_0 = res.errors
  for _index_0 = 1, #_list_0 do
    local e = _list_0[_index_0]
    if tostring(e.message):find(pattern) then
      return true
    end
  end
  return false
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
R.describe("Typed space queries — read permission", function()
  R.it("fixture: rebuilt schema exposes the typed queries", function()
    local res = run_q("{ " .. tostring(SRC_T) .. " { items { label } } }", admin_ctx)
    R.nok(res.errors, "typed query must exist: " .. tostring(errs_json(res)))
    R.eq(#res.data[SRC_T].items, 1)
    return R.eq(res.data[SRC_T].items[1].label, 'src-row')
  end)
  R.it("ctx = {} (no token) -> Unauthorized, no data", function()
    local res = run_q("{ " .. tostring(SRC_T) .. " { items { label } } }", { })
    R.ok(has_error(res, 'Unauthorized'), "expected Unauthorized, got " .. tostring(errs_json(res)))
    return R.eq(type(res.data[SRC_T]), 'cdata', "no data must be returned")
  end)
  R.it("real user with a session but no group -> Forbidden, no data", function()
    local res = run_q("{ " .. tostring(SRC_T) .. " { items { label } } }", ctx_of(actor_none))
    R.ok(has_error(res, 'Forbidden'), "expected Forbidden, got " .. tostring(errs_json(res)))
    return R.eq(type(res.data[SRC_T]), 'cdata', "no data must be returned")
  end)
  R.it("user with a read grant on the space -> data", function()
    local res = run_q("{ " .. tostring(SRC_T) .. " { items { label } } }", ctx_of(actor_src))
    R.nok(res.errors, errs_json(res))
    R.eq(#res.data[SRC_T].items, 1)
    return R.eq(res.data[SRC_T].items[1].label, 'src-row')
  end)
  R.it("member of the admin group -> data", function()
    local res = run_q("{ " .. tostring(SRC_T) .. " { items { label } } }", admin_ctx)
    R.nok(res.errors, errs_json(res))
    R.eq(#res.data[SRC_T].items, 1)
    return R.eq(res.data[SRC_T].items[1].label, 'src-row')
  end)
  R.it("FK to a space without read -> field null, target data never leaked", function()
    local res = run_q("{ " .. tostring(SRC_T) .. " { items { label tgt_id { nom } } } }", ctx_of(actor_src))
    R.nok(res.errors, errs_json(res))
    local item = res.data[SRC_T].items[1]
    R.eq(type(item.tgt_id), 'cdata', "FK field must resolve to null")
    return R.nok((leaks(res, 'secret-target')), "target record must not leak")
  end)
  return R.it("back-reference to a space without read -> empty list", function()
    local q = "{ " .. tostring(TGT_T) .. " { items { nom link_to_tgt { total items { label } } } } }"
    local res = run_q(q, ctx_of(actor_tgt))
    R.nok(res.errors, errs_json(res))
    local bk = res.data[TGT_T].items[1].link_to_tgt
    R.eq(bk.total, 0, "back-reference must be empty")
    R.eq(#bk.items, 0, "back-reference must be empty")
    return R.nok((leaks(res, 'src-row')), "source records must not leak")
  end)
end)
local _list_0 = {
  actor_none,
  actor_src,
  actor_tgt
}
for _index_0 = 1, #_list_0 do
  local a = _list_0[_index_0]
  auth.delete_session(a.token)
  box.space._tdb_users:delete(a.user.id)
end
auth.delete_session(admin_sess.token)
perms_mod.delete_group(grp_src.id)
perms_mod.delete_group(grp_tgt.id)
box.space._tdb_relations:delete(rel_id)
spaces_mod.delete_user_space(SRC_NAME)
spaces_mod.delete_user_space(TGT_NAME)
return require('resolvers.init').reinit()
