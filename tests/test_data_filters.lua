local R = require('tests.runner')
local triggers = require('core.triggers')
local matches_filter
matches_filter = function(parsed, flt)
  if not (flt) then
    return true
  end
  local ok
  if flt.formula and flt.formula ~= '' then
    if type(flt._formula_fn) == 'function' then
      local r_ok, r_val = pcall(flt._formula_fn, parsed)
      ok = r_ok and r_val and r_val ~= false
    else
      ok = false
    end
  else
    if flt.field then
      local v = tostring((parsed[flt.field] or ''))
      local _exp_0 = flt.op
      if 'EQ' == _exp_0 then
        ok = v == flt.value
      elseif 'NEQ' == _exp_0 then
        ok = v ~= flt.value
      elseif 'LT' == _exp_0 then
        ok = tonumber(v) < tonumber(flt.value)
      elseif 'GT' == _exp_0 then
        ok = tonumber(v) > tonumber(flt.value)
      elseif 'LTE' == _exp_0 then
        ok = tonumber(v) <= tonumber(flt.value)
      elseif 'GTE' == _exp_0 then
        ok = tonumber(v) >= tonumber(flt.value)
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
local apply_filter
apply_filter = function(tuples, filter)
  if not (filter and (filter.field or filter.formula or filter["and"] or filter["or"])) then
    return tuples
  end
  if filter.formula and filter.formula ~= '' and filter._formula_fn == nil then
    local lang = filter.language or 'lua'
    local ok_c, fn = pcall(triggers.compile_formula, filter.formula, 'filter', lang)
    if ok_c and type(fn) == 'function' then
      filter._formula_fn = fn
    else
      filter._formula_fn = false
    end
  end
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #tuples do
    local r = tuples[_index_0]
    if matches_filter(r, filter) then
      _accum_0[_len_0] = r
      _len_0 = _len_0 + 1
    end
  end
  return _accum_0
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
R.describe("matches_filter — opérateurs LT / GT / LTE / GTE", function()
  R.it("LT : strictement inférieur → true", function()
    return R.ok(matches_filter({
      age = 30
    }, {
      field = 'age',
      op = 'LT',
      value = '40'
    }))
  end)
  R.it("LT : égal → false", function()
    return R.eq(matches_filter({
      age = 40
    }, {
      field = 'age',
      op = 'LT',
      value = '40'
    }), false)
  end)
  R.it("GT : strictement supérieur → true", function()
    return R.ok(matches_filter({
      age = 50
    }, {
      field = 'age',
      op = 'GT',
      value = '40'
    }))
  end)
  R.it("GT : égal → false", function()
    return R.eq(matches_filter({
      age = 40
    }, {
      field = 'age',
      op = 'GT',
      value = '40'
    }), false)
  end)
  R.it("LTE : inférieur ou égal → true", function()
    R.ok(matches_filter({
      age = 40
    }, {
      field = 'age',
      op = 'LTE',
      value = '40'
    }))
    return R.ok(matches_filter({
      age = 39
    }, {
      field = 'age',
      op = 'LTE',
      value = '40'
    }))
  end)
  return R.it("GTE : supérieur ou égal → true", function()
    R.ok(matches_filter({
      age = 40
    }, {
      field = 'age',
      op = 'GTE',
      value = '40'
    }))
    return R.ok(matches_filter({
      age = 41
    }, {
      field = 'age',
      op = 'GTE',
      value = '40'
    }))
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
R.describe("matches_filter — opérateur inconnu", function()
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
R.describe("matches_filter — filtre formule Lua", function()
  R.it("formule vraie → true", function()
    local fn = triggers.compile_formula('self.age > 18', 'test', 'moonscript')
    local flt = {
      formula = 'self.age > 18',
      language = 'moonscript',
      _formula_fn = fn
    }
    return R.ok(matches_filter({
      age = 30
    }, flt))
  end)
  R.it("formule fausse → false", function()
    local fn = triggers.compile_formula('self.age > 18', 'test', 'moonscript')
    local flt = {
      formula = 'self.age > 18',
      language = 'moonscript',
      _formula_fn = fn
    }
    return R.eq(matches_filter({
      age = 10
    }, flt), false)
  end)
  R.it("formule avec accès à un champ string", function()
    local fn = triggers.compile_formula('self.nom == "Hugo"', 'test', 'moonscript')
    local flt = {
      formula = 'self.nom == "Hugo"',
      language = 'moonscript',
      _formula_fn = fn
    }
    R.ok(matches_filter({
      nom = 'Hugo'
    }, flt))
    return R.eq(matches_filter({
      nom = 'Balzac'
    }, flt), false)
  end)
  R.it("formule erreur de compilation → false (_formula_fn = false)", function()
    local flt = {
      formula = 'syntax_error???',
      _formula_fn = false
    }
    return R.eq(matches_filter({
      x = 1
    }, flt), false)
  end)
  return R.it("formule Lua native (sans return)", function()
    local fn = triggers.compile_formula('self.score >= 5', 'filter_test', 'lua')
    R.ok(fn ~= nil, "compile_formula doit retourner une fonction")
    local flt = {
      formula = 'self.score >= 5',
      language = 'lua',
      _formula_fn = fn
    }
    R.ok(matches_filter({
      score = 7
    }, flt))
    return R.eq(matches_filter({
      score = 3
    }, flt), false)
  end)
end)
R.describe("apply_filter — filtre formule (compilation auto)", function()
  R.it("formule filtre une liste, ne modifie pas les enregistrements sans match", function()
    local data = {
      {
        nom = 'Alice',
        age = 25
      },
      {
        nom = 'Bob',
        age = 15
      },
      {
        nom = 'Charlie',
        age = 30
      }
    }
    local flt = {
      formula = 'self.age >= 18',
      language = 'moonscript'
    }
    local result = apply_filter(data, flt)
    R.eq(#result, 2)
    R.eq(result[1].nom, 'Alice')
    return R.eq(result[2].nom, 'Charlie')
  end)
  R.it("formule vide → toutes les lignes retournées", function()
    local data = {
      {
        x = 1
      },
      {
        x = 2
      }
    }
    local flt = {
      formula = ''
    }
    local result = apply_filter(data, flt)
    return R.eq(#result, 2)
  end)
  return R.it("formule compilée une seule fois (cache _formula_fn)", function()
    local data = {
      {
        n = 1
      },
      {
        n = 2
      },
      {
        n = 3
      }
    }
    local flt = {
      formula = 'self.n > 1',
      language = 'moonscript'
    }
    local result = apply_filter(data, flt)
    R.eq(#result, 2)
    return R.ok(flt._formula_fn ~= nil and flt._formula_fn ~= false)
  end)
end)
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
