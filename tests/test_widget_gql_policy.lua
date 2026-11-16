local R = require('tests.runner')
local auth = require('core.auth')
local spaces_mod = require('core.spaces')
local executor = require('graphql.executor')
local http_server = require('http_server')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local SPACE_NAME = "wgq_" .. tostring(SUFFIX)
local DATA_SPACE = "data_" .. tostring(SPACE_NAME)
local sp = spaces_mod.create_user_space(SPACE_NAME, 'widget gql policy')
spaces_mod.add_field(sp.id, 'label', 'String')
box.space[DATA_SPACE]:insert({
  'rec1',
  json.encode({
    label = 'initial'
  })
})
box.space[DATA_SPACE]:insert({
  'rec2',
  json.encode({
    label = 'deletable'
  })
})
require('resolvers.init').reinit()
local admin_user = auth.get_user_by_username('admin')
R.ok(admin_user, 'fixture: admin user must exist')
local admin_sess = auth.create_session(admin_user.id)
local ADMIN_CTX = {
  user_id = admin_user.id,
  token = admin_sess.token
}
local WIDGET_CTX = {
  user_id = admin_user.id,
  token = admin_sess.token,
  widget = true
}
local EVIL_NAME = "wgq_evil_" .. tostring(SUFFIX)
local PLAIN_NAME = "wgq_plain_" .. tostring(SUFFIX)
local run
run = function(query, ctx, vars)
  return executor.execute({
    query = query,
    variables = vars or { },
    context = ctx
  })
end
local err_msgs
err_msgs = function(res)
  if not (res.errors) then
    return ''
  end
  local msgs
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = res.errors
    for _index_0 = 1, #_list_0 do
      local e = _list_0[_index_0]
      _accum_0[_len_0] = tostring(e.message)
      _len_0 = _len_0 + 1
    end
    msgs = _accum_0
  end
  return table.concat(msgs, ' | ')
end
local has_err
has_err = function(res, pattern)
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
local stored_label
stored_label = function(id)
  local t = box.space[DATA_SPACE]:get(id)
  if not (t) then
    return nil
  end
  return json.decode(t[2]).label
end
local create_user_q
create_user_q = function(username)
  return "mutation { createUser(input: {username: \"" .. tostring(username) .. "\", email: \"" .. tostring(username) .. "@test.local\", password: \"pass1234\"}) { id username } }"
end
local update_q
update_q = function(label)
  return "mutation { updateRecord(spaceId: \"" .. tostring(sp.id) .. "\", id: \"rec1\", data: {label: \"" .. tostring(label) .. "\"}) { id } }"
end
local mk_gql_req
mk_gql_req = function(headers, body)
  local req = {
    headers = headers
  }
  req.read_cached = function()
    return json.encode(body)
  end
  req.render = function(_, res)
    return res
  end
  return req
end
local auth_headers
auth_headers = function(extra)
  local h = {
    authorization = "Bearer " .. tostring(admin_sess.token)
  }
  for k, v in pairs(extra or { }) do
    h[k] = v
  end
  return h
end
R.describe("Widget relay — lectures autorisées", function()
  R.it("une query passe (les résolveurs gardent core.permissions.can)", function()
    local res = run('{ spaces { id name } }', WIDGET_CTX)
    R.nok(res.errors, err_msgs(res))
    return R.ok(#res.data.spaces > 0, 'les espaces doivent être listés')
  end)
  return R.it("une query typée d’espace passe", function()
    spaces_mod.add_field(sp.id, 'note', 'String')
    require('resolvers.init').reinit()
    local gql_name = require('graphql.dynamic').gql_name(SPACE_NAME)
    local res = run("{ " .. tostring(gql_name) .. " { items { label } } }", WIDGET_CTX)
    R.nok(res.errors, err_msgs(res))
    return R.eq(#res.data[gql_name].items, 2)
  end)
end)
R.describe("Widget relay — mutations de données autorisées", function()
  R.it("updateRecord passe", function()
    local res = run(update_q('updated'), WIDGET_CTX)
    R.nok(res.errors, err_msgs(res))
    return R.eq(stored_label('rec1'), 'updated')
  end)
  R.it("insertRecord passe", function()
    local res = run("mutation { insertRecord(spaceId: \"" .. tostring(sp.id) .. "\", data: {label: \"inserted\"}) { id } }", WIDGET_CTX)
    R.nok(res.errors, err_msgs(res))
    local new_id = res.data.insertRecord.id
    return R.eq(stored_label(new_id), 'inserted')
  end)
  return R.it("deleteRecords passe", function()
    local res = run("mutation { deleteRecords(spaceId: \"" .. tostring(sp.id) .. "\", ids: [\"rec2\"]) }", WIDGET_CTX)
    R.nok(res.errors, err_msgs(res))
    return R.is_nil(box.space[DATA_SPACE]:get('rec2'))
  end)
end)
R.describe("Widget relay — mutations hors données refusées", function()
  R.it("createUser refusé, aucun utilisateur créé", function()
    local res = run(create_user_q(EVIL_NAME), WIDGET_CTX)
    R.ok(has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs(res))
    R.is_nil(auth.get_user_by_username(EVIL_NAME), 'aucun utilisateur ne doit être créé')
    return R.eq(type(res.data), 'cdata', 'aucune donnée ne doit être retournée')
  end)
  R.it("grant refusé", function()
    local res = run('mutation { grant(groupId: "g1", input: {resourceType: "*", level: "admin"}) { id } }', WIDGET_CTX)
    return R.ok(has_err(res, "Mutation 'grant' not allowed from a widget"), err_msgs(res))
  end)
  R.it("createSpace refusé", function()
    local name = "wgq_new_" .. tostring(SUFFIX)
    local res = run("mutation { createSpace(input: {name: \"" .. tostring(name) .. "\"}) { id } }", WIDGET_CTX)
    R.ok(has_err(res, "Mutation 'createSpace' not allowed from a widget"), err_msgs(res))
    return R.is_nil(box.space._tdb_spaces.index.by_name:get(name), 'aucun espace ne doit être créé')
  end)
  R.it("updateWidgetPlugin refusé", function()
    local res = run('mutation { updateWidgetPlugin(id: "p1", input: {scriptCode: "x"}) { id } }', WIDGET_CTX)
    return R.ok(has_err(res, "Mutation 'updateWidgetPlugin' not allowed from a widget"), err_msgs(res))
  end)
  R.it("un alias ne masque pas le nom du champ (x: createUser)", function()
    local q = "mutation { x: createUser(input: {username: \"alias_" .. tostring(SUFFIX) .. "\", email: \"alias_" .. tostring(SUFFIX) .. "@test.local\", password: \"pass1234\"}) { id } }"
    local res = run(q, WIDGET_CTX)
    R.ok(has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs(res))
    return R.is_nil(auth.get_user_by_username("alias_" .. tostring(SUFFIX)), 'aucun utilisateur ne doit être créé')
  end)
  R.it("un fragment racine est déplié puis refusé", function()
    local q = "mutation { ...F } fragment F on Mutation { createUser(input: {username: \"frag_" .. tostring(SUFFIX) .. "\", email: \"frag_" .. tostring(SUFFIX) .. "@test.local\", password: \"pass1234\"}) { id } }"
    local res = run(q, WIDGET_CTX)
    R.ok(has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs(res))
    return R.is_nil(auth.get_user_by_username("frag_" .. tostring(SUFFIX)), 'aucun utilisateur ne doit être créé')
  end)
  R.it("un fragment racine autorisé est déplié et exécuté", function()
    local q = "mutation { ...F } fragment F on Mutation { updateRecord(spaceId: \"" .. tostring(sp.id) .. "\", id: \"rec1\", data: {label: \"fragmented\"}) { id } }"
    local res = run(q, WIDGET_CTX)
    R.nok(res.errors, err_msgs(res))
    return R.eq(stored_label('rec1'), 'fragmented')
  end)
  R.it("mutation mixte (autorisée + interdite) refusée en bloc, sans effet", function()
    run(update_q('before-mix'), WIDGET_CTX)
    local q = "mutation { updateRecord(spaceId: \"" .. tostring(sp.id) .. "\", id: \"rec1\", data: {label: \"mixed\"}) { id } createUser(input: {username: \"mix_" .. tostring(SUFFIX) .. "\", email: \"mix_" .. tostring(SUFFIX) .. "@test.local\", password: \"pass1234\"}) { id } }"
    local res = run(q, WIDGET_CTX)
    R.ok(has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs(res))
    R.eq(stored_label('rec1'), 'before-mix', 'le champ autorisé ne doit pas être résolu')
    return R.is_nil(auth.get_user_by_username("mix_" .. tostring(SUFFIX)), 'aucun utilisateur ne doit être créé')
  end)
  R.it("subscription refusée", function()
    local res = run('subscription { __typename }', WIDGET_CTX)
    R.ok(has_err(res, 'Subscription operations are not allowed from a widget'), err_msgs(res))
    return R.eq(type(res.data), 'cdata', 'aucune donnée ne doit être retournée')
  end)
  return R.it("l’opération nommée interdite est refusée, la nommée autorisée passe", function()
    local q = "mutation Bad { createUser(input: {username: \"multi_" .. tostring(SUFFIX) .. "\", email: \"multi@test.local\", password: \"pass1234\"}) { id } } query Good { spaces { id } }"
    local res = executor.execute({
      query = q,
      operationName = 'Bad',
      context = WIDGET_CTX
    })
    R.ok(has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs(res))
    res = executor.execute({
      query = q,
      operationName = 'Good',
      context = WIDGET_CTX
    })
    R.nok(res.errors, err_msgs(res))
    return R.ok(#res.data.spaces > 0)
  end)
end)
R.describe("Sans contexte widget — comportement inchangé", function()
  R.it("createUser passe pour un admin", function()
    local res = run(create_user_q(PLAIN_NAME), ADMIN_CTX)
    R.nok(res.errors, err_msgs(res))
    return R.eq(res.data.createUser.username, PLAIN_NAME)
  end)
  return R.it("la même mutation serait refusée avec ctx.widget", function()
    local res = run(create_user_q(EVIL_NAME), WIDGET_CTX)
    return R.ok(has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs(res))
  end)
end)
R.describe("handle_graphql — en-tête X-TDB-Widget", function()
  R.it("has_widget_header : reconnu quelle que soit la casse", function()
    R.ok(http_server.has_widget_header({
      headers = {
        ['x-tdb-widget'] = '1'
      }
    }))
    return R.ok(http_server.has_widget_header({
      headers = {
        ['X-TDB-Widget'] = '1'
      }
    }))
  end)
  R.it("has_widget_header : absent, vide ou '0' -> false", function()
    R.nok(http_server.has_widget_header({
      headers = { }
    }))
    R.nok(http_server.has_widget_header({
      headers = {
        ['x-tdb-widget'] = '0'
      }
    }))
    R.nok(http_server.has_widget_header({
      headers = {
        ['x-tdb-widget'] = ''
      }
    }))
    return R.nok(http_server.has_widget_header(nil))
  end)
  R.it("createUser relayé (en-tête) -> erreur, aucun utilisateur créé", function()
    local req = mk_gql_req(auth_headers({
      ['x-tdb-widget'] = '1'
    }), {
      query = create_user_q("hdr_" .. tostring(SUFFIX))
    })
    local res = http_server.handle_graphql(req)
    R.ok(has_err(res.json, "Mutation 'createUser' not allowed from a widget"), err_msgs(res.json))
    return R.is_nil(auth.get_user_by_username("hdr_" .. tostring(SUFFIX)))
  end)
  R.it("query relayée (en-tête) -> données servies", function()
    local req = mk_gql_req(auth_headers({
      ['x-tdb-widget'] = '1'
    }), {
      query = '{ spaces { id name } }'
    })
    local res = http_server.handle_graphql(req)
    R.nok(res.json.errors, err_msgs(res.json))
    return R.ok(#res.json.data.spaces > 0)
  end)
  return R.it("sans en-tête : createUser aboutit (chemin admin normal)", function()
    local req = mk_gql_req(auth_headers(nil), {
      query = create_user_q("nohdr_" .. tostring(SUFFIX))
    })
    local res = http_server.handle_graphql(req)
    R.nok(res.json.errors, err_msgs(res.json))
    return R.eq(res.json.data.createUser.username, "nohdr_" .. tostring(SUFFIX))
  end)
end)
local _list_0 = {
  "nohdr_" .. tostring(SUFFIX),
  PLAIN_NAME
}
for _index_0 = 1, #_list_0 do
  local name = _list_0[_index_0]
  local u = auth.get_user_by_username(name)
  if u and u.id then
    box.space._tdb_users:delete(u.id)
  end
end
auth.delete_session(admin_sess.token)
spaces_mod.delete_user_space(SPACE_NAME)
return require('resolvers.init').reinit()
