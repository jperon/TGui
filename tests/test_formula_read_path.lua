local R = require('tests.runner')
local json = require('json')
local auth = require('core.auth')
local perms_mod = require('core.permissions')
local spaces_mod = require('core.spaces')
local executor = require('graphql.executor')
local dynamic = require('graphql.dynamic')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local A_NAME = "frp2_a_" .. tostring(SUFFIX)
local B_NAME = "frp2_b_" .. tostring(SUFFIX)
local C_NAME = "frp2_c_" .. tostring(SUFFIX)
local D_NAME = "frp2_d_" .. tostring(SUFFIX)
local MAX_BOUNDED_SECONDS = 20
local ins
ins = function(name, id, data)
  return box.space["data_" .. tostring(name)]:insert({
    id,
    json.encode(data)
  })
end
local expected_emprunteur
expected_emprunteur = function(id)
  local p = ((id - 1) % 72) + 1
  return "NomP" .. tostring(p) .. " PreP" .. tostring(p)
end
local a_sp = spaces_mod.create_user_space(A_NAME, 'T12 — personnes lues par space()')
spaces_mod.add_field(a_sp.id, 'id', 'Int')
spaces_mod.add_field(a_sp.id, 'nom', 'String')
spaces_mod.add_field(a_sp.id, 'prenom', 'String')
for i = 1, 72 do
  ins(A_NAME, i, {
    id = i,
    nom = "NomP" .. tostring(i),
    prenom = "PreP" .. tostring(i)
  })
end
local b_sp = spaces_mod.create_user_space(B_NAME, 'T12 — emprunts')
spaces_mod.add_field(b_sp.id, 'personne', 'Int')
spaces_mod.add_field(b_sp.id, 'exemplaire', 'Int')
spaces_mod.add_field(b_sp.id, 'retour', 'String')
for i = 1, 100 do
  ins(B_NAME, i, {
    personne = ((i - 1) % 72) + 1,
    exemplaire = i
  })
end
for i = 101, 120 do
  ins(B_NAME, i, {
    personne = 1,
    exemplaire = i - 100,
    retour = '2026-01-01'
  })
end
local c_sp = spaces_mod.create_user_space(C_NAME, 'T12 — exemplaires')
spaces_mod.add_field(c_sp.id, 'id', 'Int')
spaces_mod.add_field(c_sp.id, 'label', 'String')
local EMP_FORMULA = "([p.nom .. ' ' .. (p.prenom or '') for p in *space('" .. tostring(A_NAME) .. "') when p.id == ([e.personne for e in *space('" .. tostring(B_NAME) .. "') when e.exemplaire == @id and (e.retour or '') == ''])[1]])[1]"
spaces_mod.add_field(c_sp.id, 'emprunteur', 'String', false, '', EMP_FORMULA, nil, 'moonscript', 'self.emprunteur')
for i = 1, 100 do
  ins(C_NAME, i, {
    id = i,
    label = "item" .. tostring(i)
  })
end
local d_sp = spaces_mod.create_user_space(D_NAME, 'T12 — imbriquée')
spaces_mod.add_field(d_sp.id, 'label', 'String')
spaces_mod.add_field(d_sp.id, 'a', 'String', false, '', 'self.b', nil, 'lua', 'self.a')
spaces_mod.add_field(d_sp.id, 'b', 'String', false, '', '(function() while true do end end)()', nil, 'lua')
ins(D_NAME, 'd_1', {
  label = 'x'
})
require('resolvers.init').reinit()
local admin_user = auth.get_user_by_username('admin')
local admin_sess = auth.create_session(admin_user.id)
local CTX = {
  user_id = admin_user.id,
  token = admin_sess.token
}
local user = auth.create_user("frp2u_" .. tostring(SUFFIX), "frp2u_" .. tostring(SUFFIX) .. "@test.local", 'pass1234')
local sess = auth.create_session(user.id)
local grp = perms_mod.create_group("frp2g_" .. tostring(SUFFIX), '')
perms_mod.grant(grp.id, 'space', c_sp.id, 'read')
perms_mod.add_member(user.id, grp.id)
local USER_CTX = {
  user_id = user.id,
  token = sess.token
}
local decode_item
decode_item = function(item)
  if type(item.data) == 'string' then
    return json.decode(item.data)
  else
    return item.data
  end
end
local C_T = dynamic.gql_name(C_NAME)
R.describe("T12 — colonne calculée lisant d'autres espaces", function()
  R.it("chemin GraphQL dynamique : emprunteur correct pour les 100 exemplaires", function()
    local res = executor.execute({
      query = "{ " .. tostring(C_T) .. " { items { id emprunteur } } }",
      context = CTX
    })
    R.nok(res.errors, json.encode(res.errors))
    local items = res.data[C_T].items
    R.eq(#items, 100, 'items')
    local bad = { }
    for _index_0 = 1, #items do
      local item = items[_index_0]
      local id = tonumber(item.id)
      local exp = expected_emprunteur(id)
      if item.emprunteur ~= exp then
        table.insert(bad, "id=" .. tostring(id) .. ": " .. tostring(tostring(item.emprunteur)) .. " != " .. tostring(exp))
      end
    end
    return R.eq(#bad, 0, tostring(#bad) .. "/100 valeurs fausses; premiere: " .. tostring(bad[1]))
  end)
  R.it("chemin Query.records : _repr_emprunteur correct pour les 100 exemplaires", function()
    local res = data_r.Query.records(nil, {
      spaceId = c_sp.id,
      limit = 500
    }, CTX)
    R.eq(res.total, 100, 'total')
    local bad = { }
    local _list_0 = res.items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      local d = decode_item(item)
      local id = tonumber(d.id)
      local exp = expected_emprunteur(id)
      if d._repr_emprunteur ~= exp then
        table.insert(bad, "id=" .. tostring(id) .. ": " .. tostring(tostring(d._repr_emprunteur)) .. " != " .. tostring(exp))
      end
    end
    return R.eq(#bad, 0, tostring(#bad) .. "/100 valeurs fausses; premiere: " .. tostring(bad[1]))
  end)
  R.it("formule calculée imbriquée infinie : bornee, instruction limit exceeded", function()
    local t0 = os.clock()
    local res = data_r.Query.records(nil, {
      spaceId = d_sp.id,
      limit = 10
    }, CTX)
    local elapsed = os.clock() - t0
    print("    [measure] formule imbriquee infinie bornee en " .. tostring(elapsed) .. "s")
    local d = decode_item(res.items[1])
    R.matches(tostring(d._repr_a), 'instruction limit exceeded', "valeur " .. tostring(tostring(d._repr_a)))
    return R.ok(elapsed < MAX_BOUNDED_SECONDS, "doit revenir en moins de " .. tostring(MAX_BOUNDED_SECONDS) .. "s (" .. tostring(elapsed) .. "s)")
  end)
  return R.it("sans droit de lecture sur A, space('A') renvoie une liste vide (chemin dynamique)", function()
    local res = executor.execute({
      query = "{ " .. tostring(C_T) .. " { items { id emprunteur } } }",
      context = USER_CTX
    })
    R.nok(res.errors, json.encode(res.errors))
    local encoded = json.encode(res.data)
    R.nok((encoded:find('PreP', 1, true)), "aucune donnee de A ne doit fuir")
    local leaked = false
    local _list_0 = res.data[C_T].items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      if item.emprunteur ~= nil and item.emprunteur ~= '' then
        leaked = true
      end
    end
    return R.nok(leaked, "emprunteur doit etre vide sans droit de lecture sur A")
  end)
end)
auth.delete_session(sess.token)
box.space._tdb_users:delete(user.id)
auth.delete_session(admin_sess.token)
perms_mod.delete_group(grp.id)
local _list_0 = {
  D_NAME,
  C_NAME,
  B_NAME,
  A_NAME
}
for _index_0 = 1, #_list_0 do
  local name = _list_0[_index_0]
  spaces_mod.delete_user_space(name)
end
return require('resolvers.init').reinit()
