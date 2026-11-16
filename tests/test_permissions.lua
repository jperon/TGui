local R = require('tests.runner')
local auth = require('core.auth')
local http_server = require('http_server')
local require_auth, require_admin
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_admin = _obj_0.require_auth, _obj_0.require_admin
end
local spaces_mod = require('core.spaces')
local auth_r = require('resolvers.auth_resolvers')
local data_r = require('resolvers.data_resolvers')
local custom_view_r = require('resolvers.custom_view_resolvers')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
R.describe("require_auth — blocked without authentication", function()
  R.it("ctx nil -> Unauthorized error", function()
    local ok, err = pcall(require_auth, nil)
    R.eq(ok, false)
    return R.ok(tostring(err):find('Unauthorized'))
  end)
  R.it("ctx without user_id -> Unauthorized", function()
    local ok, err = pcall(require_auth, { })
    R.eq(ok, false)
    return R.ok(tostring(err):find('Unauthorized'))
  end)
  return R.it("ctx with user_id -> returns id", function()
    local uid = require_auth({
      user_id = 'fake-uid'
    })
    return R.eq(uid, 'fake-uid')
  end)
end)
R.describe("require_admin — blocked for non-admin", function()
  R.it("ctx nil -> Unauthorized (not Forbidden)", function()
    local ok, err = pcall(require_admin, nil)
    R.eq(ok, false)
    return R.ok(tostring(err):find('Unauthorized'))
  end)
  R.it("non-admin user -> Forbidden", function()
    local ok_u, user = pcall(auth.create_user, "nonadmin_" .. tostring(SUFFIX), "nonadmin_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
    R.ok(ok_u)
    local sess = auth.create_session(user.id)
    local ctx = {
      user_id = user.id
    }
    local ok_a, err_a = pcall(require_admin, ctx)
    R.eq(ok_a, false)
    R.ok(tostring(err_a):find('Forbidden'))
    auth.delete_session(sess.token)
    return box.space._tdb_users:delete(user.id)
  end)
  return R.it("admin user -> success", function()
    local admin_user = auth.get_user_by_username('admin')
    R.ok(admin_user)
    local uid = require_admin({
      user_id = admin_user.id
    })
    return R.eq(uid, admin_user.id)
  end)
end)
R.describe("Sessions — creation, validation, expiration", function()
  local token, uid
  R.it("create_session returns a token", function()
    local user = auth.get_user_by_username('admin')
    R.ok(user)
    uid = user.id
    local sess = auth.create_session(uid)
    R.ok(sess)
    R.ok(sess.token)
    R.ok(#sess.token > 10)
    token = sess.token
  end)
  R.it("validate_session returns valid session", function()
    local sess = auth.validate_session(token)
    R.ok(sess)
    R.eq(sess.user_id, uid)
    return R.ok(sess.expires_at > os.time())
  end)
  R.it("delete_session invalide le token", function()
    auth.delete_session(token)
    local sess = auth.validate_session(token)
    return R.eq(sess, nil)
  end)
  return R.it("unknown token -> validate_session returns nil", function()
    local sess = auth.validate_session('tok-that-does-not-exist')
    return R.eq(sess, nil)
  end)
end)
R.describe("Sessions — expired purge", function()
  R.it("purge_expired_sessions returns deleted session count", function()
    local fake_token = "expired_test_" .. tostring(SUFFIX)
    box.space._tdb_sessions:insert({
      fake_token,
      'fake-user',
      os.time() - 7200,
      os.time() - 3600
    })
    local sess = auth.validate_session(fake_token)
    R.eq(sess, nil)
    local t = box.space._tdb_sessions:get(fake_token)
    return R.eq(t, nil)
  end)
  return R.it("purge_expired_sessions does not delete valid sessions", function()
    local admin = auth.get_user_by_username('admin')
    local sess = auth.create_session(admin.id)
    local n = auth.purge_expired_sessions()
    local still_valid = auth.validate_session(sess.token)
    R.ok(still_valid)
    return auth.delete_session(sess.token)
  end)
end)
R.describe("GraphQL resolver auth policy — admin queries", function()
  R.it("Query.users refuse un utilisateur non-admin", function()
    local ok_u, user = pcall(auth.create_user, "policy_nonadmin_" .. tostring(SUFFIX), "policy_nonadmin_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
    R.ok(ok_u)
    local ctx = {
      user_id = user.id
    }
    local ok_q, err_q = pcall(auth_r.Query.users, nil, { }, ctx)
    R.eq(ok_q, false)
    R.ok(tostring(err_q):find('Forbidden'))
    return box.space._tdb_users:delete(user.id)
  end)
  return R.it("Query.users accepte un admin", function()
    local admin_user = auth.get_user_by_username('admin')
    local res = auth_r.Query.users(nil, { }, {
      user_id = admin_user.id
    })
    return R.ok(type(res) == 'table')
  end)
end)
R.describe("GraphQL resolver auth policy — data/custom views", function()
  R.it("Query.record refuse ctx nil", function()
    local ok_q, err_q = pcall(data_r.Query.record, nil, {
      spaceId = 'any',
      id = 'any'
    }, nil)
    R.eq(ok_q, false)
    return R.ok(tostring(err_q):find('Unauthorized'))
  end)
  R.it("Query.record accepts an authenticated user", function()
    local admin_user = auth.get_user_by_username('admin')
    local sp_name = "policy_record_" .. tostring(SUFFIX)
    local sp = spaces_mod.create_user_space(sp_name, "policy record test")
    box.space["data_" .. tostring(sp_name)]:insert({
      "row1",
      json.encode({
        nom = "ok"
      })
    })
    local rec = data_r.Query.record(nil, {
      spaceId = sp.id,
      id = 'row1'
    }, {
      user_id = admin_user.id
    })
    R.ok(rec)
    R.eq(rec.id, 'row1')
    return spaces_mod.delete_user_space(sp_name)
  end)
  return R.it("customViews refuse ctx nil", function()
    local ok_q, err_q = pcall(custom_view_r.Query.customViews, nil, { }, nil)
    R.eq(ok_q, false)
    return R.ok(tostring(err_q):find('Unauthorized'))
  end)
end)
local perms_mod = require('core.permissions')
local views_mod = require('core.views')
local dv_core = require('core.data_views')
local schema_r = require('resolvers.schema_resolvers')
local dv_r = require('resolvers.data_view_resolvers')
local wpr = require('resolvers.widget_plugin_resolvers')
local agg_r = require('resolvers.aggregate_resolvers')
local export_r = require('resolvers.export_resolvers')
local uuid_mod = require('uuid')
local require_perm, perm_ok, trusted_ctx
do
  local _obj_0 = require('resolvers.utils')
  require_perm, perm_ok, trusted_ctx = _obj_0.require_perm, _obj_0.perm_ok, _obj_0.trusted_ctx
end
local new_actor
new_actor = function(prefix, resource_type, resource_id, level)
  local user = auth.create_user(tostring(prefix) .. "_" .. tostring(SUFFIX), tostring(prefix) .. "_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
  local grp = perms_mod.create_group(tostring(prefix) .. "g_" .. tostring(SUFFIX), '')
  if resource_type then
    perms_mod.grant(grp.id, resource_type, resource_id, level)
  end
  perms_mod.add_member(user.id, grp.id)
  return {
    user = user,
    group = grp
  }
end
local ctx_of
ctx_of = function(a)
  return {
    user_id = a.user.id
  }
end
local perm_sp = spaces_mod.create_user_space("perm_sp_" .. tostring(SUFFIX), "permission fixture")
local other_sp = spaces_mod.create_user_space("perm_other_" .. tostring(SUFFIX), "permission fixture 2")
local perm_sid = perm_sp.id
local other_sid = other_sp.id
spaces_mod.add_field(perm_sid, 'nom', 'String')
local perm_view_id = tostring(uuid_mod.new())
box.space._tdb_views:insert({
  perm_view_id,
  perm_sid,
  "perm_view_" .. tostring(SUFFIX),
  'grid',
  '{}',
  os.time(),
  os.time()
})
local perm_page_id = tostring(uuid_mod.new())
box.space._tdb_custom_views:insert({
  perm_page_id,
  "perm_page_" .. tostring(SUFFIX),
  '',
  'layout:\n  direction: vertical\n  children: []',
  os.time(),
  os.time()
})
local perm_dv = dv_core.create_view("perm_dv_" .. tostring(SUFFIX), "permission fixture", perm_sid, json.encode({
  columns = {
    'nom'
  }
}))
local perm_plugin_id = tostring(uuid_mod.new())
box.space._tdb_widget_plugins:insert({
  perm_plugin_id,
  "perm_plugin_" .. tostring(SUFFIX),
  '',
  'coffeescript',
  'pug',
  'x = 1',
  'div x',
  os.time(),
  os.time()
})
local act_none = {
  user = auth.create_user("pnone_" .. tostring(SUFFIX), "pnone_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
}
local act_noperm = new_actor('pnop')
local act_read = new_actor('prd', 'space', perm_sid, 'read')
local act_write = new_actor('pwr', 'space', perm_sid, 'write')
local act_typerd = new_actor('pty', 'space', nil, 'read')
local act_global = new_actor('pgb', '*', nil, 'admin')
local act_gread = new_actor('pgr', '*', nil, 'read')
local act_gwrite = new_actor('pgw', '*', nil, 'write')
local act_viewwr = new_actor('pvw', 'view', nil, 'write')
local act_viewad = new_actor('pva', 'view', nil, 'admin')
local act_otherrd = new_actor('por', 'space', other_sid, 'read')
R.describe("Task 1 — fixtures", function()
  return R.it("fixture view, page, data view and plugin rows exist", function()
    local t = box.space._tdb_views:get(perm_view_id)
    R.ok(t, "fixture view row")
    R.eq(type(t[5]), 'string', "fixture view config")
    R.ok(box.space._tdb_custom_views:get(perm_page_id, "fixture page row"))
    R.ok(dv_core.get_view(perm_dv.id, "fixture data view row"))
    return R.ok(box.space._tdb_widget_plugins:get(perm_plugin_id, "fixture plugin row"))
  end)
end)
R.describe("require_perm — user without group", function()
  R.it("refuses read, write and admin", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return require_perm(c, 'space', perm_sid, 'read')
    end), 'Forbidden')
    R.raises((function()
      return require_perm(c, 'space', perm_sid, 'write')
    end), 'Forbidden')
    return R.raises((function()
      return require_perm(c, '*', nil, 'admin')
    end), 'Forbidden')
  end)
  R.it("refuses when the user has a group but no grant at all", function()
    R.raises((function()
      return require_perm(ctx_of(act_noperm), 'space', perm_sid, 'read')
    end), 'Forbidden')
    return R.raises((function()
      return require_perm(ctx_of(act_noperm), 'space', perm_sid, 'write')
    end), 'Forbidden')
  end)
  return R.it("refuses reads of every resource family", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return require_perm(c, 'view', perm_page_id, 'read')
    end), 'Forbidden')
    R.raises((function()
      return require_perm(c, 'view', perm_dv.id, 'read')
    end), 'Forbidden')
    return R.raises((function()
      return require_perm(c, '*', nil, 'read')
    end), 'Forbidden')
  end)
end)
R.describe("require_perm — read level", function()
  R.it("read grant allows read and refuses write", function()
    local c = ctx_of(act_read)
    R.eq(require_perm(c, 'space', perm_sid, 'read'), act_read.user.id)
    return R.raises((function()
      return require_perm(c, 'space', perm_sid, 'write')
    end), 'Forbidden')
  end)
  R.it("read grant does not leak to another space", function()
    return R.raises((function()
      return require_perm(ctx_of(act_read), 'space', other_sid, 'read')
    end), 'Forbidden')
  end)
  return R.it("type wildcard gives read on any space of that type", function()
    local c = ctx_of(act_typerd)
    R.eq(require_perm(c, 'space', other_sid, 'read'), act_typerd.user.id)
    R.eq(require_perm(c, 'space', perm_sid, 'read'), act_typerd.user.id)
    return R.raises((function()
      return require_perm(c, 'space', perm_sid, 'write')
    end), 'Forbidden')
  end)
end)
R.describe("require_perm — write and admin levels", function()
  R.it("write grant allows write but not schema admin", function()
    local c = ctx_of(act_write)
    R.eq(require_perm(c, 'space', perm_sid, 'write'), act_write.user.id)
    R.eq(require_perm(c, 'space', perm_sid, 'read'), act_write.user.id)
    return R.raises((function()
      return require_perm(c, '*', nil, 'admin')
    end), 'Forbidden')
  end)
  R.it("global '*' admin wildcard passes space, view and schema checks", function()
    local c = ctx_of(act_global)
    R.ok(require_perm(c, 'space', perm_sid, 'read'))
    R.ok(require_perm(c, 'space', perm_sid, 'write'))
    R.ok(require_perm(c, 'view', nil, 'write'))
    return R.ok(require_perm(c, '*', nil, 'admin'))
  end)
  R.it("global read wildcard allows reads but not writes", function()
    local c = ctx_of(act_gread)
    R.ok(require_perm(c, 'space', other_sid, 'read'))
    R.ok(require_perm(c, '*', nil, 'read'))
    return R.raises((function()
      return require_perm(c, 'space', other_sid, 'write')
    end), 'Forbidden')
  end)
  R.it("global write wildcard allows writes but not schema admin", function()
    local c = ctx_of(act_gwrite)
    R.ok(require_perm(c, 'space', perm_sid, 'write'))
    return R.raises((function()
      return require_perm(c, '*', nil, 'admin')
    end), 'Forbidden')
  end)
  return R.it("admin group passes every check without any grant", function()
    local admin_user = auth.get_user_by_username('admin')
    local c = {
      user_id = admin_user.id
    }
    R.ok(require_perm(c, 'space', perm_sid, 'write'))
    R.ok(require_perm(c, '*', nil, 'admin'))
    return R.ok(require_perm(c, 'view', perm_page_id, 'read'))
  end)
end)
R.describe("require_perm — principal resolution", function()
  R.it("deleted user with a live session is refused", function()
    local u = auth.create_user("porph_" .. tostring(SUFFIX), "porph_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
    local sess = auth.create_session(u.id)
    box.space._tdb_users:delete(u.id)
    R.raises((function()
      return require_perm({
        user_id = u.id,
        token = sess.token
      }, 'space', perm_sid, 'read')
    end), 'Forbidden')
    return box.space._tdb_sessions:delete(sess.token)
  end)
  R.it("ctx without token and unknown principal is refused for a read", function()
    return R.raises((function()
      return require_perm({
        user_id = 'x'
      }, 'space', perm_sid, 'read')
    end), 'Forbidden')
  end)
  R.it("trusted in-process context passes every check", function()
    local c = trusted_ctx('trusted-uid')
    R.eq(require_perm(c, 'space', perm_sid, 'read'), 'trusted-uid')
    R.eq(require_perm(c, 'space', perm_sid, 'write'), 'trusted-uid')
    return R.eq(require_perm(c, '*', nil, 'admin'), 'trusted-uid')
  end)
  R.it("ctx with a live token of a user without group is refused", function()
    local u = auth.create_user("ptok_" .. tostring(SUFFIX), "ptok_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
    local sess = auth.create_session(u.id)
    R.raises((function()
      return require_perm({
        user_id = u.id,
        token = sess.token
      }, 'space', perm_sid, 'read')
    end), 'Forbidden')
    auth.delete_session(sess.token)
    return box.space._tdb_users:delete(u.id)
  end)
  return R.it("ctx without user_id is still Unauthorized", function()
    return R.raises((function()
      return require_perm(nil, 'space', perm_sid, 'read')
    end), 'Unauthorized')
  end)
end)
local closure_upvalue
closure_upvalue = function(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not (n) then
      break
    end
    if n == name then
      return v
    end
    i = i + 1
  end
  return nil
end
R.describe("handle_graphql — trusted cannot be forged by a request", function()
  local handle_graphql = closure_upvalue(http_server.start, 'handle_graphql')
  R.it("handle_graphql is reachable through the server closure", function()
    return R.eq(type(handle_graphql), 'function')
  end)
  R.it("a request body carrying trusted=true does not grant admin access", function()
    local u = auth.create_user("pgql_" .. tostring(SUFFIX), "pgql_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
    local sess = auth.create_session(u.id)
    local rendered = nil
    local body = json.encode({
      query = 'mutation { createSpace(input: { name: "forged_t10" }) { id } }',
      variables = {
        trusted = true
      },
      trusted = true
    })
    local req = {
      headers = {
        authorization = "Bearer " .. tostring(sess.token)
      },
      read_cached = function()
        return body
      end,
      render = function(_, response)
        rendered = response
      end
    }
    handle_graphql(req)
    R.ok(rendered, "handle_graphql renders a response")
    local errs = rendered.json.errors
    R.ok(errs and #errs > 0, "the protected mutation is refused")
    R.ok(tostring(errs[1].message):find('Forbidden'))
    auth.delete_session(sess.token)
    return box.space._tdb_users:delete(u.id)
  end)
  return R.it("a request body carrying trusted=true without any session is refused", function()
    local rendered = nil
    local body = json.encode({
      query = 'mutation { createSpace(input: { name: "forged_t10_noauth" }) { id } }',
      variables = {
        trusted = true
      },
      trusted = true
    })
    local req = {
      headers = { },
      read_cached = function()
        return body
      end,
      render = function(_, response)
        rendered = response
      end
    }
    handle_graphql(req)
    local errs = rendered.json.errors
    R.ok(errs and #errs > 0, "the protected mutation is refused")
    return R.ok(tostring(errs[1].message):find('Unauthorized'))
  end)
end)
R.describe("schema_resolvers — schema mutations need global admin", function()
  R.it("user without group: createSpace, addField, deleteSpace, relations refused", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return schema_r.Mutation.createSpace(nil, {
        input = {
          name = "permns_" .. tostring(SUFFIX)
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Mutation.addField(nil, {
        spaceId = perm_sid,
        input = {
          name = 'x',
          fieldType = 'String',
          notNull = false,
          description = ''
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Mutation.deleteSpace(nil, {
        id = perm_sid
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Mutation.createRelation(nil, {
        input = {
          name = 'relx',
          fromSpaceId = perm_sid,
          fromFieldId = 'f',
          toSpaceId = other_sid,
          toFieldId = 'g'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Mutation.deleteRelation(nil, {
        id = 'whatever'
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return schema_r.Mutation.updateSpace(nil, {
        id = perm_sid,
        input = { }
      }, c)
    end), 'Forbidden')
  end)
  R.it("read-only and write users cannot change the schema", function()
    R.raises((function()
      return schema_r.Mutation.createSpace(nil, {
        input = {
          name = "permrw_" .. tostring(SUFFIX)
        }
      }, ctx_of(act_read))
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Mutation.createSpace(nil, {
        input = {
          name = "permrw2_" .. tostring(SUFFIX)
        }
      }, ctx_of(act_write))
    end), 'Forbidden')
    return R.raises((function()
      return schema_r.Mutation.addField(nil, {
        spaceId = perm_sid,
        input = {
          name = 'y',
          fieldType = 'String',
          notNull = false,
          description = ''
        }
      }, ctx_of(act_write))
    end), 'Forbidden')
  end)
  R.it("global admin wildcard can create and delete a space", function()
    local c = ctx_of(act_global)
    local sp = schema_r.Mutation.createSpace(nil, {
      input = {
        name = "permgadm_" .. tostring(SUFFIX)
      }
    }, c)
    R.ok(sp)
    return R.eq(schema_r.Mutation.deleteSpace(nil, {
      id = sp.id
    }, c), true)
  end)
  return R.it("admin group can create and delete a space", function()
    local admin_user = auth.get_user_by_username('admin')
    local c = {
      user_id = admin_user.id
    }
    local sp = schema_r.Mutation.createSpace(nil, {
      input = {
        name = "permadm_" .. tostring(SUFFIX)
      }
    }, c)
    R.ok(sp)
    return R.eq(schema_r.Mutation.deleteSpace(nil, {
      id = sp.id
    }, c), true)
  end)
end)
R.describe("schema_resolvers — reads", function()
  R.it("user without group: single reads refused, lists empty", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return schema_r.Query.space(nil, {
        id = perm_sid
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Query.view(nil, {
        id = perm_view_id
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Query.relations(nil, {
        spaceId = perm_sid
      }, c)
    end), 'Forbidden')
    R.eq(#schema_r.Query.spaces(nil, { }, c), 0)
    return R.eq(#schema_r.Query.views(nil, {
      spaceId = perm_sid
    }, c), 0)
  end)
  R.it("read-only user: reads the granted space and only that space", function()
    local c = ctx_of(act_read)
    R.eq(schema_r.Query.space(nil, {
      id = perm_sid
    }, c).id, perm_sid)
    R.eq(schema_r.Query.view(nil, {
      id = perm_view_id
    }, c).id, perm_view_id)
    R.eq(#schema_r.Query.views(nil, {
      spaceId = perm_sid
    }, c), 1)
    local lst = schema_r.Query.spaces(nil, { }, c)
    R.eq(#lst, 1)
    return R.eq(lst[1].id, perm_sid)
  end)
  R.it("user reading another space: no view of the granted space", function()
    local c = ctx_of(act_otherrd)
    R.eq(#schema_r.Query.views(nil, {
      spaceId = perm_sid
    }, c), 0)
    return R.raises((function()
      return schema_r.Query.space(nil, {
        id = perm_sid
      }, c)
    end), 'Forbidden')
  end)
  return R.it("global read wildcard sees every space", function()
    local lst = schema_r.Query.spaces(nil, { }, ctx_of(act_gread))
    local found = false
    for _index_0 = 1, #lst do
      local sp = lst[_index_0]
      if sp.id == perm_sid then
        found = true
      end
    end
    return R.ok(found, "global read must list the fixture space")
  end)
end)
R.describe("schema_resolvers — view mutations", function()
  R.it("user without group: createView, updateView and deleteView refused", function()
    local c = ctx_of(act_none)
    local input = {
      spaceId = perm_sid,
      name = "permv_" .. tostring(SUFFIX),
      viewType = 'grid',
      config = {
        layout = {
          direction = 'vertical',
          children = { }
        }
      }
    }
    R.raises((function()
      return schema_r.Mutation.createView(nil, {
        input = input
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return schema_r.Mutation.deleteView(nil, {
        id = perm_view_id
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return schema_r.Mutation.updateView(nil, {
        id = perm_view_id,
        input = { }
      }, c)
    end), 'Forbidden')
  end)
  R.it("space write is not enough to create or edit a view", function()
    local input = {
      spaceId = perm_sid,
      name = "permv2_" .. tostring(SUFFIX),
      viewType = 'grid',
      config = {
        layout = {
          direction = 'vertical',
          children = { }
        }
      }
    }
    R.raises((function()
      return schema_r.Mutation.createView(nil, {
        input = input
      }, ctx_of(act_write))
    end), 'Forbidden')
    return R.raises((function()
      return schema_r.Mutation.updateView(nil, {
        id = perm_view_id,
        input = { }
      }, ctx_of(act_write))
    end), 'Forbidden')
  end)
  R.it("view write wildcard passes the createView permission check", function()
    local input = {
      spaceId = perm_sid,
      name = "permv3_" .. tostring(SUFFIX),
      viewType = 'grid',
      config = {
        layout = {
          direction = 'vertical',
          children = { }
        }
      }
    }
    local ok_c, err_c = pcall(schema_r.Mutation.createView, nil, {
      input = input
    }, ctx_of(act_viewwr))
    return R.ok((ok_c or not tostring(err_c):find('Forbidden')), "view writer passes the permission check")
  end)
  R.it("view write wildcard passes the updateView permission check", function()
    local ok_u, err_u = pcall(schema_r.Mutation.updateView, nil, {
      id = perm_view_id,
      input = { }
    }, ctx_of(act_viewwr))
    R.ok((ok_u or not tostring(err_u):find('Forbidden')), "view writer passes the permission check")
    return R.raises((function()
      return schema_r.Mutation.deleteView(nil, {
        id = perm_view_id
      }, ctx_of(act_viewwr))
    end), 'Forbidden')
  end)
  return R.it("view admin wildcard deletes a view", function()
    local vid = tostring(uuid_mod.new())
    local now_t = os.time()
    box.space._tdb_views:insert({
      vid,
      perm_sid,
      "permv_del_" .. tostring(SUFFIX),
      'grid',
      '{}',
      now_t,
      now_t
    })
    return R.eq(schema_r.Mutation.deleteView(nil, {
      id = vid
    }, ctx_of(act_viewad)), true)
  end)
end)
R.describe("data_resolvers — reads and writes on a space", function()
  R.it("user without group: every read and write refused", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return data_r.Query.records(nil, {
        spaceId = perm_sid
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Query.record(nil, {
        spaceId = perm_sid,
        id = 'row'
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = perm_sid,
        data = {
          nom = 'a'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Mutation.updateRecord(nil, {
        spaceId = perm_sid,
        id = 'row',
        data = {
          nom = 'b'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Mutation.deleteRecord(nil, {
        spaceId = perm_sid,
        id = 'row'
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Mutation.deleteRecords(nil, {
        spaceId = perm_sid,
        ids = {
          'row'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Mutation.insertRecords(nil, {
        spaceId = perm_sid,
        data = {
          {
            nom = 'a'
          }
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return data_r.Mutation.updateRecords(nil, {
        spaceId = perm_sid,
        records = { }
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return data_r.Mutation.restoreRecords(nil, {
        spaceId = perm_sid,
        records = { }
      }, c)
    end), 'Forbidden')
  end)
  R.it("read-only user: reads the granted space, cannot write", function()
    local c = ctx_of(act_read)
    local res = data_r.Query.records(nil, {
      spaceId = perm_sid
    }, c)
    R.eq(res.total, 0)
    R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = perm_sid,
        data = {
          nom = 'a'
        }
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return data_r.Query.records(nil, {
        spaceId = other_sid
      }, c)
    end), 'Forbidden')
  end)
  R.it("write user: inserts, reads and deletes", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = perm_sid,
      data = {
        nom = 'perm'
      }
    }, ctx_of(act_write))
    R.ok(rec)
    R.eq(data_r.Query.records(nil, {
      spaceId = perm_sid
    }, ctx_of(act_read)).total, 1)
    R.eq(data_r.Mutation.deleteRecord(nil, {
      spaceId = perm_sid,
      id = rec.id
    }, ctx_of(act_write)), true)
    return R.eq(data_r.Query.records(nil, {
      spaceId = perm_sid
    }, ctx_of(act_read)).total, 0)
  end)
  R.it("type wildcard read: reads any space but cannot write", function()
    local c = ctx_of(act_typerd)
    R.eq(data_r.Query.records(nil, {
      spaceId = other_sid
    }, c).total, 0)
    return R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = other_sid,
        data = {
          nom = 'a'
        }
      }, c)
    end), 'Forbidden')
  end)
  R.it("global admin wildcard can insert", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = perm_sid,
      data = {
        nom = 'adm'
      }
    }, ctx_of(act_global))
    R.ok(rec)
    return R.eq(data_r.Mutation.deleteRecord(nil, {
      spaceId = perm_sid,
      id = rec.id
    }, ctx_of(act_global)), true)
  end)
  return R.it("admin group can insert", function()
    local admin_user = auth.get_user_by_username('admin')
    local c = {
      user_id = admin_user.id
    }
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = perm_sid,
      data = {
        nom = 'root'
      }
    }, c)
    R.ok(rec)
    return data_r.Mutation.deleteRecord(nil, {
      spaceId = perm_sid,
      id = rec.id
    }, c)
  end)
end)
R.describe("custom_view_resolvers — pages", function()
  local fixture_page
  fixture_page = function()
    local pid = tostring(uuid_mod.new())
    local now_t = os.time()
    box.space._tdb_custom_views:insert({
      pid,
      "perm_page2_" .. tostring(SUFFIX),
      '',
      'layout:\n  direction: vertical\n  children: []',
      now_t,
      now_t
    })
    return pid
  end
  R.it("user without group: single read refused, list empty", function()
    local c = ctx_of(act_none)
    R.eq(#custom_view_r.Query.customViews(nil, { }, c), 0)
    R.raises((function()
      return custom_view_r.Query.customView(nil, {
        id = perm_page_id
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Query.exportLayout(nil, {
        pageId = perm_page_id
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return custom_view_r.Query.listLayoutSnapshots(nil, {
        pageId = perm_page_id
      }, c)
    end), 'Forbidden')
  end)
  R.it("user without group: every page mutation refused", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return custom_view_r.Mutation.createCustomView(nil, {
        input = {
          name = "permcp_" .. tostring(SUFFIX),
          yaml = 'layout:\n  direction: vertical\n  children: []'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Mutation.updateCustomView(nil, {
        id = perm_page_id,
        input = { }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Mutation.deleteCustomView(nil, {
        id = perm_page_id
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Mutation.addWidgetToView(nil, {
        viewId = perm_page_id,
        widget = {
          title = 't',
          space = 's'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Mutation.reorderWidgets(nil, {
        pageId = perm_page_id,
        widgetPositions = { }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Mutation.createZone(nil, {
        pageId = perm_page_id,
        zoneData = { }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return custom_view_r.Mutation.importLayout(nil, {
        pageId = perm_page_id,
        yaml = 'x'
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return custom_view_r.Mutation.createLayoutSnapshot(nil, {
        pageId = perm_page_id,
        yaml = 'x'
      }, c)
    end), 'Forbidden')
  end)
  R.it("space write is not enough to edit a page", function()
    return R.raises((function()
      return custom_view_r.Mutation.updateCustomView(nil, {
        id = perm_page_id,
        input = { }
      }, ctx_of(act_write))
    end), 'Forbidden')
  end)
  R.it("view write wildcard edits a page but cannot delete it", function()
    local pg = fixture_page()
    local c = ctx_of(act_viewwr)
    local updated = custom_view_r.Mutation.updateCustomView(nil, {
      id = pg,
      input = {
        yaml = 'layout:\n  direction: vertical\n  children: []'
      }
    }, c)
    R.ok(updated)
    R.raises((function()
      return custom_view_r.Mutation.deleteCustomView(nil, {
        id = pg
      }, c)
    end), 'Forbidden')
    return R.eq(custom_view_r.Mutation.deleteCustomView(nil, {
      id = pg
    }, ctx_of(act_viewad)), true)
  end)
  R.it("view write wildcard can create a page", function()
    local res = custom_view_r.Mutation.createCustomView(nil, {
      input = {
        name = "permcp2_" .. tostring(SUFFIX),
        yaml = 'layout:\n  direction: vertical\n  children: []'
      }
    }, ctx_of(act_viewwr))
    R.ok(res)
    return custom_view_r.Mutation.deleteCustomView(nil, {
      id = res.id
    }, ctx_of(act_viewad))
  end)
  R.it("read-only space user sees no page", function()
    R.eq(#custom_view_r.Query.customViews(nil, { }, ctx_of(act_read)), 0)
    return R.raises((function()
      return custom_view_r.Query.customView(nil, {
        id = perm_page_id
      }, ctx_of(act_read))
    end), 'Forbidden')
  end)
  return R.it("global read wildcard can read pages", function()
    R.ok(custom_view_r.Query.customView(nil, {
      id = perm_page_id
    }, ctx_of(act_gread)))
    return R.ok(#custom_view_r.Query.customViews({ }, { }, ctx_of(act_gread)) >= 1)
  end)
end)
R.describe("data_view_resolvers — permissions", function()
  R.it("user without group: lists empty and single fetch refused", function()
    local c = ctx_of(act_none)
    R.eq(#dv_r.Query.dataViews(nil, { }, c), 0)
    R.raises((function()
      return dv_r.Query.dataView(nil, {
        id = perm_dv.id
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return dv_r.Query.executeDataView(nil, {
        id = perm_dv.id
      }, c)
    end), 'Forbidden')
  end)
  R.it("user without group: create, update and delete refused", function()
    local c = ctx_of(act_none)
    local input = {
      name = "permdv_" .. tostring(SUFFIX),
      description = '',
      sourceSpace = perm_sid,
      config = '{}'
    }
    R.raises((function()
      return dv_r.Mutation.createDataView(nil, {
        input = input
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return dv_r.Mutation.updateDataView(nil, {
        id = perm_dv.id,
        input = { }
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return dv_r.Mutation.deleteDataView(nil, {
        id = perm_dv.id
      }, c)
    end), 'Forbidden')
  end)
  R.it("reader of the source space can list, fetch and execute", function()
    local c = ctx_of(act_read)
    R.eq(#dv_r.Query.dataViews(nil, { }, c), 1)
    R.ok(dv_r.Query.dataView(nil, {
      id = perm_dv.id
    }, c))
    local ok_e, err = pcall(dv_r.Query.executeDataView, nil, {
      id = perm_dv.id
    }, c)
    return R.ok((ok_e or not tostring(err):find('Forbidden')), "reader passes the permission check")
  end)
  R.it("user reading another space sees no data view", function()
    local c = ctx_of(act_otherrd)
    R.eq(#dv_r.Query.dataViews(nil, { }, c), 0)
    R.raises((function()
      return dv_r.Query.dataView(nil, {
        id = perm_dv.id
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return dv_r.Query.executeDataView(nil, {
        id = perm_dv.id
      }, c)
    end), 'Forbidden')
  end)
  return R.it("space write is not enough, view write creates and view admin deletes", function()
    local input = {
      name = "permdv2_" .. tostring(SUFFIX),
      description = '',
      sourceSpace = perm_sid,
      config = '{}'
    }
    R.raises((function()
      return dv_r.Mutation.createDataView(nil, {
        input = input
      }, ctx_of(act_write))
    end), 'Forbidden')
    local dv2 = dv_r.Mutation.createDataView(nil, {
      input = input
    }, ctx_of(act_viewwr))
    R.ok(dv2)
    R.raises((function()
      return dv_r.Mutation.deleteDataView(nil, {
        id = dv2.id
      }, ctx_of(act_viewwr))
    end), 'Forbidden')
    return R.eq(dv_r.Mutation.deleteDataView(nil, {
      id = dv2.id
    }, ctx_of(act_viewad)), true)
  end)
end)
R.describe("widget_plugin_resolvers — permissions", function()
  R.it("user without group: reads and writes refused", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return wpr.Query.widgetPlugins(nil, { }, c)
    end), 'Forbidden')
    R.raises((function()
      return wpr.Query.widgetPlugin(nil, {
        id = perm_plugin_id
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return wpr.Mutation.createWidgetPlugin(nil, {
        input = {
          name = "permpg_" .. tostring(SUFFIX),
          scriptCode = 'x = 1',
          templateCode = 'div x'
        }
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return wpr.Mutation.updateWidgetPlugin(nil, {
        id = perm_plugin_id,
        input = { }
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return wpr.Mutation.deleteWidgetPlugin(nil, {
        id = perm_plugin_id
      }, c)
    end), 'Forbidden')
  end)
  R.it("space-only reader cannot read plugins", function()
    R.raises((function()
      return wpr.Query.widgetPlugins(nil, { }, ctx_of(act_read))
    end), 'Forbidden')
    return R.raises((function()
      return wpr.Query.widgetPlugin(nil, {
        id = perm_plugin_id
      }, ctx_of(act_read))
    end), 'Forbidden')
  end)
  R.it("global read reads plugins but cannot create", function()
    R.eq(#wpr.Query.widgetPlugins({ }, { }, ctx_of(act_gread)), 1)
    R.ok(wpr.Query.widgetPlugin(nil, {
      id = perm_plugin_id
    }, ctx_of(act_gread)))
    return R.raises((function()
      return wpr.Mutation.createWidgetPlugin(nil, {
        input = {
          name = "permpg2_" .. tostring(SUFFIX),
          scriptCode = 'x = 1',
          templateCode = 'div x'
        }
      }, ctx_of(act_gread))
    end), 'Forbidden')
  end)
  R.it("global write cannot create nor update (code runs in other users' browsers)", function()
    R.raises((function()
      return wpr.Mutation.createWidgetPlugin(nil, {
        input = {
          name = "permpg3_" .. tostring(SUFFIX),
          scriptCode = 'x = 1',
          templateCode = 'div x'
        }
      }, ctx_of(act_gwrite))
    end), 'Forbidden')
    local p2 = wpr.Mutation.createWidgetPlugin(nil, {
      input = {
        name = "permpg3_" .. tostring(SUFFIX),
        scriptCode = 'x = 1',
        templateCode = 'div x'
      }
    }, ctx_of(act_global))
    R.ok(p2)
    R.raises((function()
      return wpr.Mutation.updateWidgetPlugin(nil, {
        id = p2.id,
        input = {
          scriptCode = 'y = 2'
        }
      }, ctx_of(act_gwrite))
    end), 'Forbidden')
    R.raises((function()
      return wpr.Mutation.deleteWidgetPlugin(nil, {
        id = p2.id
      }, ctx_of(act_gwrite))
    end), 'Forbidden')
    return R.eq(wpr.Mutation.deleteWidgetPlugin(nil, {
      id = p2.id
    }, ctx_of(act_global)), true)
  end)
  return R.it("admin group can delete", function()
    local p3 = wpr.Mutation.createWidgetPlugin(nil, {
      input = {
        name = "permpg4_" .. tostring(SUFFIX),
        scriptCode = 'x = 1',
        templateCode = 'div x'
      }
    }, ctx_of(act_global))
    R.ok(p3)
    return R.eq(wpr.Mutation.deleteWidgetPlugin(nil, {
      id = p3.id
    }, ctx_of(act_global)), true)
  end)
end)
R.describe("aggregate_resolvers — permissions", function()
  local agg_args
  agg_args = function()
    return {
      spaceName = perm_sp.name,
      aggregate = {
        {
          fn = 'count'
        }
      }
    }
  end
  R.it("user without group -> Forbidden", function()
    return R.raises((function()
      return agg_r.Query.aggregateSpace(nil, agg_args(), ctx_of(act_none))
    end), 'Forbidden')
  end)
  R.it("read-only user on that space -> allowed", function()
    local res = agg_r.Query.aggregateSpace(nil, agg_args(), ctx_of(act_read))
    return R.ok(type(res) == 'table')
  end)
  R.it("user reading another space -> Forbidden", function()
    return R.raises((function()
      return agg_r.Query.aggregateSpace(nil, agg_args(), ctx_of(act_otherrd))
    end), 'Forbidden')
  end)
  return R.it("global read -> allowed", function()
    local res = agg_r.Query.aggregateSpace(nil, agg_args(), ctx_of(act_gread))
    return R.ok(type(res) == 'table')
  end)
end)
R.describe("export_resolvers — permissions", function()
  local snap_yaml = 'version: "1"\nschema:\n  spaces: []\n'
  R.it("user without group: export, import and diff refused", function()
    local c = ctx_of(act_none)
    R.raises((function()
      return export_r.Query.exportSnapshot(nil, {
        includeData = false
      }, c)
    end), 'Forbidden')
    R.raises((function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = snap_yaml,
        mode = 'merge'
      }, c)
    end), 'Forbidden')
    return R.raises((function()
      return export_r.Query.diffSnapshot(nil, {
        yaml = snap_yaml
      }, c)
    end), 'Forbidden')
  end)
  R.it("read-only user: diff refused", function()
    return R.raises((function()
      return export_r.Query.diffSnapshot(nil, {
        yaml = snap_yaml
      }, ctx_of(act_read))
    end), 'Forbidden')
  end)
  return R.it("admin group can export", function()
    local admin_user = auth.get_user_by_username('admin')
    local res = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, {
      user_id = admin_user.id
    })
    return R.ok(type(res) == 'string')
  end)
end)
local _list_0 = {
  act_noperm,
  act_read,
  act_write,
  act_typerd,
  act_global,
  act_gread,
  act_gwrite,
  act_viewwr,
  act_viewad,
  act_otherrd
}
for _index_0 = 1, #_list_0 do
  local actor = _list_0[_index_0]
  perms_mod.delete_group(actor.group.id)
  box.space._tdb_users:delete(actor.user.id)
end
box.space._tdb_users:delete(act_none.user.id)
box.space._tdb_custom_views:delete(perm_page_id)
dv_core.delete_view(perm_dv.id)
box.space._tdb_widget_plugins:delete(perm_plugin_id)
views_mod.delete_view(perm_view_id)
spaces_mod.delete_user_space(perm_sp.name)
return spaces_mod.delete_user_space(other_sp.name)
