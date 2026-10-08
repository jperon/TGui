local R = require('tests.runner')
local json = require('json')
local auth = require('core.auth')
local perms_mod = require('core.permissions')
local spaces_mod = require('core.spaces')
local triggers = require('core.triggers')
local config_mod = require('core.config')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local A_NAME = "fsc_a_" .. tostring(SUFFIX)
local B_NAME = "fsc_b_" .. tostring(SUFFIX)
local D_NAME = "fsc_d_" .. tostring(SUFFIX)
local E_NAME = "fsc_e_" .. tostring(SUFFIX)
local T_NAME = "fsc_t_" .. tostring(SUFFIX)
local SA_NAME = "fsc_sa_" .. tostring(SUFFIX)
local U_NAME = "fsc_u_" .. tostring(SUFFIX)
local PA_NAME = "fsc_pa_" .. tostring(SUFFIX)
local PB_NAME = "fsc_pb_" .. tostring(SUFFIX)
local SECRET = "secret-t10-" .. tostring(SUFFIX)
local MAX_BOUNDED_SECONDS = 20
local admin_user = auth.get_user_by_username('admin')
local admin_sess = auth.create_session(admin_user.id)
local fresh_ctx
fresh_ctx = function()
  return {
    user_id = admin_user.id,
    token = admin_sess.token
  }
end
local ins
ins = function(space_id, data)
  return data_r.Mutation.insertRecord(nil, {
    spaceId = space_id,
    data = data
  }, fresh_ctx())
end
local run_records
run_records = function(space_id, ctx)
  return data_r.Query.records(nil, {
    spaceId = space_id,
    limit = 500
  }, ctx)
end
local decode_item
decode_item = function(item)
  if type(item.data) == 'string' then
    return json.decode(item.data)
  else
    return item.data
  end
end
local err_count
err_count = function(key)
  local m = config_mod.get_formula_metrics().error_details[key]
  if not (m) then
    return 0
  end
  return m.count
end
local read_field
read_field = function(space_name, id, fname)
  local t = box.space["data_" .. tostring(space_name)]:get(id)
  if not (t) then
    return nil
  end
  return json.decode(t[2])[fname]
end
local a_sp = spaces_mod.create_user_space(A_NAME, 'T10 — espace lu par space()')
local a_id = a_sp.id
spaces_mod.add_field(a_id, 'k', 'Int')
local b_sp = spaces_mod.create_user_space(B_NAME, 'T10 — colonne calculée lisant A')
local b_id = b_sp.id
spaces_mod.add_field(b_id, 'id', 'Int')
local count_formula = '#[a for a in *space("' .. A_NAME .. '") when a.k == @id]'
spaces_mod.add_field(b_id, 'n', 'Int', false, '', count_formula, nil, 'moonscript', 'self.n')
for i = 1, 150 do
  ins(a_id, {
    k = ((i - 1) % 25) + 1
  })
  ins(b_id, {
    id = i
  })
end
local d_sp = spaces_mod.create_user_space(D_NAME, 'T10 — boucle infinie')
local d_id = d_sp.id
spaces_mod.add_field(d_id, 'label', 'String')
spaces_mod.add_field(d_id, 'boucle', 'String', false, '', '(function() while true do end end)()', nil, 'lua', 'self.boucle')
ins(d_id, {
  label = 'x'
})
local e_sp = spaces_mod.create_user_space(E_NAME, 'T10 — boucle sur space()')
local e_id = e_sp.id
spaces_mod.add_field(e_id, 'label', 'String')
local e_formula = '(function() while true do space("' .. A_NAME .. '") end end)()'
spaces_mod.add_field(e_id, 'boucle', 'String', false, '', e_formula, nil, 'lua', 'self.boucle')
ins(e_id, {
  label = 'x'
})
local t_sp = spaces_mod.create_user_space(T_NAME, 'T10 — trigger bouclé')
local t_id = t_sp.id
spaces_mod.add_field(t_id, 'label', 'String')
spaces_mod.add_field(t_id, 'boucle', 'String', false, '', e_formula, { }, 'lua')
triggers.register_space_trigger(T_NAME)
local sa_sp = spaces_mod.create_user_space(SA_NAME, 'T10 — espace compté par un trigger')
local sa_id = sa_sp.id
spaces_mod.add_field(sa_id, 'k', 'Int')
for i = 1, 3 do
  ins(sa_id, {
    k = i
  })
end
local u_sp = spaces_mod.create_user_space(U_NAME, 'T10 — trigger compteur')
local u_id = u_sp.id
spaces_mod.add_field(u_id, 'label', 'String')
local count_trigger = '#space("' .. SA_NAME .. '")'
spaces_mod.add_field(u_id, 'nb', 'Int', false, '', count_trigger, { }, 'lua')
triggers.register_space_trigger(U_NAME)
local pa_sp = spaces_mod.create_user_space(PA_NAME, 'T10 — espace secret')
local pa_id = pa_sp.id
spaces_mod.add_field(pa_id, 'secret', 'String')
ins(pa_id, {
  secret = SECRET
})
local pb_sp = spaces_mod.create_user_space(PB_NAME, 'T10 — colonne calculée lisant PA')
local pb_id = pb_sp.id
spaces_mod.add_field(pb_id, 'label', 'String')
local seen_formula = 'space("' .. PA_NAME .. '")[1] and space("' .. PA_NAME .. '")[1].secret or "none"'
spaces_mod.add_field(pb_id, 'seen', 'String', false, '', seen_formula, nil, 'lua', 'self.seen')
ins(pb_id, {
  label = 'x'
})
local user_x = auth.create_user("fscx_" .. tostring(SUFFIX), "fscx_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
local sess_x = auth.create_session(user_x.id)
local ctx_x = {
  user_id = user_x.id,
  token = sess_x.token
}
local grp_x = perms_mod.create_group("fscx_" .. tostring(SUFFIX), '')
perms_mod.grant(grp_x.id, 'space', pb_id, 'read')
local perm_a = perms_mod.grant(grp_x.id, 'space', pa_id, 'read')
perms_mod.add_member(user_x.id, grp_x.id)
R.describe("T10 — space() dans une colonne calculée (150 lignes)", function()
  return R.it("records(B) rend le bon compte pour chaque ligne, sans instruction limit exceeded", function()
    local t0 = os.clock()
    local res = run_records(b_id, fresh_ctx())
    local elapsed = os.clock() - t0
    print("    [measure] " .. tostring(B_NAME) .. ": " .. tostring(res.total) .. " lignes lues en " .. tostring(elapsed) .. "s")
    R.eq(res.total, 150, 'total records(B)')
    local bad = { }
    local _list_0 = res.items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      local d = decode_item(item)
      local n_id = tonumber(d.id)
      local expected = 0
      if n_id and n_id <= 25 then
        expected = 6
      end
      local got = tonumber(d._repr_n)
      if got ~= expected then
        table.insert(bad, "id=" .. tostring(tostring(d.id)) .. ": _repr_n=" .. tostring(tostring(d._repr_n)) .. " (attendu " .. tostring(expected) .. ")")
      end
    end
    return R.eq(#bad, 0, tostring(#bad) .. "/150 comptes incorrects; premier: " .. tostring(bad[1]))
  end)
end)
R.describe("T10 — la garde reste sur le code de la formule", function()
  R.it("boucle infinie dans une colonne calculée -> instruction limit exceeded", function()
    local res = run_records(d_id, fresh_ctx())
    R.eq(res.total, 1, 'total records(D)')
    local d = decode_item(res.items[1])
    return R.matches(tostring(d._repr_boucle), 'instruction limit exceeded', "colonne calculée en boucle, got " .. tostring(tostring(d._repr_boucle)))
  end)
  R.it("while true do space(A) end en colonne calculée (chemin mémoïsé) reste borné", function()
    local t0 = os.clock()
    local res = run_records(e_id, fresh_ctx())
    local elapsed = os.clock() - t0
    print("    [measure] colonne calculée bouclée sur space(): coupée en " .. tostring(elapsed) .. "s")
    R.eq(res.total, 1, 'total records(E)')
    local d = decode_item(res.items[1])
    R.matches(tostring(d._repr_boucle), 'instruction limit exceeded', "colonne calculée bouclée sur space(), got " .. tostring(tostring(d._repr_boucle)))
    return R.ok(elapsed < MAX_BOUNDED_SECONDS, "doit revenir en moins de " .. tostring(MAX_BOUNDED_SECONDS) .. "s (" .. tostring(elapsed) .. "s)")
  end)
  return R.it("while true do space(A) end dans un trigger reste borné", function()
    local key = "trigger " .. tostring(T_NAME) .. ".boucle"
    local before = err_count(key)
    local t0 = os.clock()
    local res = data_r.Mutation.insertRecord(nil, {
      spaceId = t_id,
      data = {
        label = 'loop'
      }
    }, fresh_ctx())
    local elapsed = os.clock() - t0
    local after = err_count(key)
    print("    [measure] trigger bouclé sur space(): coupé en " .. tostring(elapsed) .. "s")
    R.ok(res.id, "l'insertion doit aboutir (le trigger attrape l'erreur)")
    R.ok(after > before, "la garde doit s'être déclenchée (" .. tostring(before) .. " -> " .. tostring(after) .. ")")
    local m = config_mod.get_formula_metrics().error_details[key]
    R.matches(tostring(m and m.last_error), 'instruction limit exceeded', "message de la garde, got " .. tostring(m and m.last_error))
    return R.ok(elapsed < MAX_BOUNDED_SECONDS, "doit revenir en moins de " .. tostring(MAX_BOUNDED_SECONDS) .. "s (" .. tostring(elapsed) .. "s)")
  end)
end)
R.describe("T10 — mémoïsation : fraîcheur et permissions", function()
  R.it("un trigger comptant les lignes voit l'écriture fraîche dans l'espace lu", function()
    local r1 = ins(u_id, {
      label = 'u1'
    })
    R.eq(read_field(U_NAME, r1.id, 'nb'), 3, "3 lignes dans SA avant insertion")
    ins(sa_id, {
      k = 4
    })
    local r2 = ins(u_id, {
      label = 'u2'
    })
    return R.eq(read_field(U_NAME, r2.id, 'nb'), 4, "la 4e ligne de SA doit être vue (pas de cache)")
  end)
  R.it("le cache est par requête : deux records successifs voient la modification de A", function()
    local res1 = run_records(b_id, fresh_ctx())
    local d1 = nil
    local _list_0 = res1.items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      local d = decode_item(item)
      if tonumber(d.id) == 1 then
        d1 = d
      end
    end
    R.ok(d1, "ligne id=1 trouvée")
    R.eq(tonumber(d1._repr_n), 6, "compte avant insertion dans A")
    ins(a_id, {
      k = 1
    })
    local res2 = run_records(b_id, fresh_ctx())
    local d2 = nil
    local _list_1 = res2.items
    for _index_0 = 1, #_list_1 do
      local item = _list_1[_index_0]
      local d = decode_item(item)
      if tonumber(d.id) == 1 then
        d2 = d
      end
    end
    R.ok(d2, "ligne id=1 trouvée (2e requête)")
    return R.eq(tonumber(d2._repr_n), 7, "compte après insertion dans A (nouvelle requête)")
  end)
  return R.it("space() refuse un espace non lisible même quand il est déjà en cache", function()
    local res = run_records(pb_id, ctx_x)
    local d = decode_item(res.items[1])
    R.eq(d._repr_seen, SECRET, "témoin avec droit de lecture sur PA")
    local fk_cache = ctx_x._fk_cache
    R.ok(fk_cache and fk_cache.spaces and fk_cache.spaces[PA_NAME], "PA doit être en cache dans le fk_cache de la requête")
    perms_mod.revoke(perm_a.id)
    local res2 = run_records(pb_id, ctx_x)
    local d2 = decode_item(res2.items[1])
    R.eq(d2._repr_seen, 'none', "sans droit de lecture, space() doit renvoyer une liste vide")
    return R.ok(ctx_x._fk_cache and ctx_x._fk_cache.spaces and ctx_x._fk_cache.spaces[PA_NAME], "le cache de la requête reste chaud")
  end)
end)
auth.delete_session(sess_x.token)
box.space._tdb_users:delete(user_x.id)
auth.delete_session(admin_sess.token)
perms_mod.delete_group(grp_x.id)
local _list_0 = {
  B_NAME,
  E_NAME,
  D_NAME,
  T_NAME,
  U_NAME,
  SA_NAME,
  PB_NAME,
  PA_NAME,
  A_NAME
}
for _index_0 = 1, #_list_0 do
  local name = _list_0[_index_0]
  spaces_mod.delete_user_space(name)
end
return require('resolvers.init').reinit()
