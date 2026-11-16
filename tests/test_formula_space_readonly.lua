local R = require('tests.runner')
local json = require('json')
local spaces_mod = require('core.spaces')
local formula_proxy = require('core.formula_proxy')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local A_NAME = "fsro_a_" .. tostring(SUFFIX)
local B_NAME = "fsro_b_" .. tostring(SUFFIX)
local admin_user = require('core.auth').get_user_by_username('admin')
local CTX = {
  user_id = admin_user.id
}
local ins
ins = function(space_id, data)
  return data_r.Mutation.insertRecord(nil, {
    spaceId = space_id,
    data = data
  }, CTX)
end
local decode_item
decode_item = function(item)
  if type(item.data) == 'string' then
    return json.decode(item.data)
  else
    return item.data
  end
end
local a_sp = spaces_mod.create_user_space(A_NAME, 'fsro — espace lu par space()')
local a_id = a_sp.id
spaces_mod.add_field(a_id, 'prix', 'Int')
ins(a_id, {
  prix = 10
})
ins(a_id, {
  prix = 20
})
local b_sp = spaces_mod.create_user_space(B_NAME, 'fsro — colonne calculée qui écrit dans space()')
local b_id = b_sp.id
spaces_mod.add_field(b_id, 'label', 'String')
local tamper_formula = '(function() local r = space("' .. A_NAME .. '")[1]; r.prix = 999; ' .. 'return tostring(space("' .. A_NAME .. '")[1].prix) end)()'
spaces_mod.add_field(b_id, 'tamper', 'String', false, '', tamper_formula, nil, 'lua', 'self.tamper')
ins(b_id, {
  label = 'x'
})
R.describe("space() — cache par requête en lecture seule", function()
  R.it("rend des lignes en lecture seule (cache par requête)", function()
    local fk_cache = {
      can_read = function()
        return true
      end
    }
    local helper = formula_proxy.make_space_helper(fk_cache)
    local rows = helper(A_NAME)
    R.eq(#rows, 2, 'deux lignes')
    local values
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #rows do
        local r = rows[_index_0]
        _accum_0[_len_0] = r.prix
        _len_0 = _len_0 + 1
      end
      values = _accum_0
    end
    table.sort(values)
    R.eq(values[1], 10, 'première valeur')
    R.eq(values[2], 20, 'seconde valeur')
    local before = rows[1].prix
    R.raises((function()
      rows[1].prix = 999
    end), 'read%-only', "l'affectation d'un champ existant doit lever")
    R.raises((function()
      rows[2].nouveau = 1
    end), 'read%-only', "l'ajout d'un champ doit lever")
    R.eq(rows[1].prix, before, 'la ligne rendue reste inchangée')
    local after
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = helper(A_NAME)
      for _index_0 = 1, #_list_0 do
        local r = _list_0[_index_0]
        _accum_0[_len_0] = r.prix
        _len_0 = _len_0 + 1
      end
      after = _accum_0
    end
    table.sort(after)
    R.eq(after[1], 10, "l'évaluation suivante doit toujours voir 10")
    return R.eq(after[2], 20, "l'évaluation suivante doit toujours voir 20")
  end)
  R.it("sans cache (chemin trigger), space() relit la base à chaque appel", function()
    local helper = formula_proxy.make_space_helper(nil)
    local rows = helper(A_NAME)
    local before = rows[1].prix
    rows[1].prix = 999
    R.eq(helper(A_NAME)[1].prix, before, 'aucune mémoïsation sans fk_cache')
    return R.ne(helper(A_NAME)[1].prix, 999, 'la valeur fabriquée ne doit pas ressortir')
  end)
  return R.it("une formule qui écrit dans space('A') est signalée et ne contamine rien", function()
    local res = data_r.Query.records(nil, {
      spaceId = b_id,
      limit = 10
    }, CTX)
    R.eq(res.total, 1, 'une ligne dans B')
    local d = decode_item(res.items[1])
    R.matches(tostring(d._repr_tamper), 'read%-only', "la formule doit être arrêtée avec un message clair, got " .. tostring(tostring(d._repr_tamper)))
    local fk_cache = CTX._fk_cache
    R.ok(fk_cache and fk_cache.spaces and fk_cache.spaces[A_NAME], 'A doit être en cache dans la requête')
    local cached = fk_cache.spaces[A_NAME]
    local cached_values
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = cached.list
      for _index_0 = 1, #_list_0 do
        local r = _list_0[_index_0]
        _accum_0[_len_0] = r.prix
        _len_0 = _len_0 + 1
      end
      cached_values = _accum_0
    end
    table.sort(cached_values)
    R.eq(cached_values[1], 10, "le cache de la requête n'a pas été contaminé")
    R.eq(cached_values[2], 20, "le cache de la requête n'a pas été contaminé (2e ligne)")
    local t = box.space["data_" .. tostring(A_NAME)]:select({ })
    local prix = { }
    for _index_0 = 1, #t do
      local tuple = t[_index_0]
      table.insert(prix, json.decode(tuple[2]).prix)
    end
    table.sort(prix)
    R.eq(prix[1], 10, 'valeur stockée intacte')
    return R.eq(prix[2], 20, 'valeur stockée intacte (2e ligne)')
  end)
end)
spaces_mod.delete_user_space(B_NAME)
spaces_mod.delete_user_space(A_NAME)
return require('resolvers.init').reinit()
