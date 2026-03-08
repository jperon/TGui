local R = require('tests.runner')
local matches_filter
matches_filter = function(parsed, flt)
  if not (flt) then
    return true
  end
  local ok
  if flt.field then
    local v = tostring((parsed[flt.field] or ''))
    local _exp_0 = flt.op
    if 'EQ' == _exp_0 then
      ok = v == flt.value
    elseif 'NEQ' == _exp_0 then
      ok = v ~= flt.value
    elseif 'CONTAINS' == _exp_0 then
      ok = v:find(flt.value, 1, true) ~= nil
    elseif 'STARTS_WITH' == _exp_0 then
      ok = v:sub(1, #flt.value) == flt.value
    else
      ok = true
    end
  else
    ok = true
  end
  if ok and flt["and"] then
    local _list_0 = flt["and"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if not (ok) then
        break
      end
      ok = matches_filter(parsed, sub)
    end
  end
  if flt["or"] then
    local any = false
    local _list_0 = flt["or"]
    for _index_0 = 1, #_list_0 do
      local sub = _list_0[_index_0]
      if matches_filter(parsed, sub) then
        any = true
        break
      end
    end
    ok = ok and any
  end
  return ok
end
R.describe("matches_filter — opérateur EQ", function()
  R.it("EQ : égalité exacte → true", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'EQ',
      value = 'Dupont'
    }))
  end)
  R.it("EQ : inégalité → false", function()
    return R.eq(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'EQ',
      value = 'Martin'
    }), false)
  end)
  R.it("EQ : champ absent → compare '' à valeur", function()
    R.eq(matches_filter({ }, {
      field = 'x',
      op = 'EQ',
      value = ''
    }), true)
    return R.eq(matches_filter({ }, {
      field = 'x',
      op = 'EQ',
      value = 'truc'
    }), false)
  end)
  return R.it("EQ : comparaison numérique convertie en string", function()
    return R.ok(matches_filter({
      age = 42
    }, {
      field = 'age',
      op = 'EQ',
      value = '42'
    }))
  end)
end)
R.describe("matches_filter — opérateur NEQ", function()
  R.it("NEQ : valeurs différentes → true", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'NEQ',
      value = 'Martin'
    }))
  end)
  return R.it("NEQ : valeurs égales → false", function()
    return R.eq(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'NEQ',
      value = 'Dupont'
    }), false)
  end)
end)
R.describe("matches_filter — opérateur CONTAINS", function()
  R.it("CONTAINS : sous-chaîne présente → true", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'CONTAINS',
      value = 'pont'
    }))
  end)
  R.it("CONTAINS : sous-chaîne absente → false", function()
    return R.eq(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'CONTAINS',
      value = 'xyz'
    }), false)
  end)
  R.it("CONTAINS : chaîne vide correspond toujours", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'CONTAINS',
      value = ''
    }))
  end)
  return R.it("CONTAINS : caractères spéciaux Lua non interprétés comme patterns", function()
    R.eq(matches_filter({
      code = 'abc'
    }, {
      field = 'code',
      op = 'CONTAINS',
      value = 'a.c'
    }), false)
    return R.ok(matches_filter({
      code = 'a.c'
    }, {
      field = 'code',
      op = 'CONTAINS',
      value = 'a.c'
    }))
  end)
end)
R.describe("matches_filter — opérateur STARTS_WITH", function()
  R.it("STARTS_WITH : début exact → true", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'STARTS_WITH',
      value = 'Du'
    }))
  end)
  R.it("STARTS_WITH : ne commence pas par → false", function()
    return R.eq(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'STARTS_WITH',
      value = 'pont'
    }), false)
  end)
  return R.it("STARTS_WITH : chaîne vide → true (tout commence par '')", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, {
      field = 'nom',
      op = 'STARTS_WITH',
      value = ''
    }))
  end)
end)
R.describe("matches_filter — combinaisons AND / OR", function()
  R.it("AND : les deux conditions vraies → true", function()
    local flt = { }
    flt["and"] = {
      {
        field = 'a',
        op = 'EQ',
        value = '1'
      },
      {
        field = 'b',
        op = 'EQ',
        value = '2'
      }
    }
    return R.ok(matches_filter({
      a = '1',
      b = '2'
    }, flt))
  end)
  R.it("AND : une condition fausse → false", function()
    local flt = { }
    flt["and"] = {
      {
        field = 'a',
        op = 'EQ',
        value = '1'
      },
      {
        field = 'b',
        op = 'EQ',
        value = '2'
      }
    }
    return R.eq(matches_filter({
      a = '1',
      b = '99'
    }, flt), false)
  end)
  R.it("OR : au moins une condition vraie → true", function()
    local flt = { }
    flt["or"] = {
      {
        field = 'nom',
        op = 'EQ',
        value = 'Dupont'
      },
      {
        field = 'nom',
        op = 'EQ',
        value = 'Martin'
      }
    }
    return R.ok(matches_filter({
      nom = 'Martin'
    }, flt))
  end)
  R.it("OR : aucune condition vraie → false", function()
    local flt = { }
    flt["or"] = {
      {
        field = 'nom',
        op = 'EQ',
        value = 'Dupont'
      },
      {
        field = 'nom',
        op = 'EQ',
        value = 'Martin'
      }
    }
    return R.eq(matches_filter({
      nom = 'Durand'
    }, flt), false)
  end)
  R.it("filtre nil → true (pas de filtre)", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, nil))
  end)
  return R.it("filtre sans field ni and/or → true (filtre vide)", function()
    return R.ok(matches_filter({
      nom = 'Dupont'
    }, { }))
  end)
end)
return R.describe("matches_filter — opérateur inconnu", function()
  return R.it("opérateur inconnu → toujours true (non filtrant)", function()
    return R.ok(matches_filter({
      x = 'y'
    }, {
      field = 'x',
      op = 'UNKNOWN_OP',
      value = 'z'
    }))
  end)
end)
