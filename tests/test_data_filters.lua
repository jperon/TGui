local R = require('tests.runner')
local triggers = require('core.triggers')
local spaces_mod = require('core.spaces')
local schema_Query, schema_Mutation
do
  local _obj_0 = require('resolvers.schema_resolvers')
  schema_Query, schema_Mutation = _obj_0.Query, _obj_0.Mutation
end
local data_Query, data_Mutation
do
  local _obj_0 = require('resolvers.data_resolvers')
  data_Query, data_Mutation = _obj_0.Query, _obj_0.Mutation
end
local CTX_FK = {
  user_id = 'test-user'
}
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
apply_filter = function(tuples, filter, fk_def_map)
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
  local result = { }
  for _index_0 = 1, #tuples do
    local r = tuples[_index_0]
    local self_val
    if fk_def_map then
      self_val = triggers.make_self_proxy(r, fk_def_map)
    else
      self_val = r
    end
    if matches_filter(self_val, filter) then
      table.insert(result, r)
    end
  end
  return result
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
local FKSFX = tostring(math.random(100000, 999999))
local fk_genres_sp_id, fk_livres_sp_id, fk_rel_id
local fk_libelle_field_id, fk_genre_id_field_id
local genre_roman_uuid, genre_polar_uuid
do
  local genres_sp = spaces_mod.create_user_space("fktest_genres_" .. tostring(FKSFX), "genres FK test")
  local livres_sp = spaces_mod.create_user_space("fktest_livres_" .. tostring(FKSFX), "livres FK test")
  fk_genres_sp_id = genres_sp.id
  fk_livres_sp_id = livres_sp.id
  local libelle_f = spaces_mod.add_field(fk_genres_sp_id, 'libelle', 'String')
  fk_libelle_field_id = libelle_f.id
  spaces_mod.add_field(fk_livres_sp_id, 'titre', 'String')
  local genre_id_f = spaces_mod.add_field(fk_livres_sp_id, 'genre_id', 'String')
  fk_genre_id_field_id = genre_id_f.id
  local rel = schema_Mutation.createRelation({ }, {
    input = {
      name = "fktest_rel_" .. tostring(FKSFX),
      fromSpaceId = fk_livres_sp_id,
      fromFieldId = fk_genre_id_field_id,
      toSpaceId = fk_genres_sp_id,
      toFieldId = fk_libelle_field_id
    }
  }, CTX_FK)
  fk_rel_id = rel.id
  local roman_rec = data_Mutation.insertRecord({ }, {
    spaceId = fk_genres_sp_id,
    data = {
      libelle = 'Roman'
    }
  }, CTX_FK)
  local polar_rec = data_Mutation.insertRecord({ }, {
    spaceId = fk_genres_sp_id,
    data = {
      libelle = 'Polar'
    }
  }, CTX_FK)
  genre_roman_uuid = roman_rec.id
  genre_polar_uuid = polar_rec.id
  data_Mutation.insertRecord({ }, {
    spaceId = fk_livres_sp_id,
    data = {
      titre = 'Les Misérables',
      genre_id = genre_roman_uuid
    }
  }, CTX_FK)
  data_Mutation.insertRecord({ }, {
    spaceId = fk_livres_sp_id,
    data = {
      titre = 'Sherlock Holmes',
      genre_id = genre_polar_uuid
    }
  }, CTX_FK)
end
R.describe("FK proxy — make_self_proxy résout les champs FK", function()
  R.it("proxy.genre_id retourne un sous-proxy (table)", function()
    local fk_map = triggers.build_fk_def_map(fk_livres_sp_id)
    local proxy = triggers.make_self_proxy({
      titre = 'Test',
      genre_id = genre_roman_uuid
    }, fk_map)
    local genre_proxy = proxy.genre_id
    R.ok(genre_proxy ~= nil, "genre_id doit retourner un proxy non nil")
    return R.eq(type(genre_proxy), 'table')
  end)
  R.it("proxy.genre_id.libelle retourne la valeur du champ de l'enregistrement lié", function()
    local fk_map = triggers.build_fk_def_map(fk_livres_sp_id)
    local proxy = triggers.make_self_proxy({
      titre = 'Test',
      genre_id = genre_roman_uuid
    }, fk_map)
    return R.eq(proxy.genre_id.libelle, 'Roman')
  end)
  R.it("proxy.titre retourne le champ non-FK directement", function()
    local fk_map = triggers.build_fk_def_map(fk_livres_sp_id)
    local proxy = triggers.make_self_proxy({
      titre = 'Dune',
      genre_id = genre_polar_uuid
    }, fk_map)
    return R.eq(proxy.titre, 'Dune')
  end)
  return R.it("proxy FK nil → nil sans plantage", function()
    local fk_map = triggers.build_fk_def_map(fk_livres_sp_id)
    local proxy = triggers.make_self_proxy({
      titre = 'Sans genre'
    }, fk_map)
    return R.is_nil(proxy.genre_id)
  end)
end)
R.describe("FK proxy — apply_filter avec formule @fk_field.sub_field", function()
  R.it("filtre @genre_id.libelle == 'Roman' retourne seulement les romans", function()
    local fk_map = triggers.build_fk_def_map(fk_livres_sp_id)
    local tuples = {
      {
        titre = 'Les Misérables',
        genre_id = genre_roman_uuid
      },
      {
        titre = 'Sherlock Holmes',
        genre_id = genre_polar_uuid
      }
    }
    local flt = {
      formula = '@genre_id.libelle == "Roman"',
      language = 'moonscript'
    }
    local result = apply_filter(tuples, flt, fk_map)
    R.eq(#result, 1)
    return R.eq(result[1].titre, 'Les Misérables')
  end)
  return R.it("filtre sans fk_def_map (nil) ne plante pas sur les tests non-FK", function()
    local tuples = {
      {
        nom = 'Alice',
        age = 25
      },
      {
        nom = 'Bob',
        age = 15
      }
    }
    local flt = {
      formula = '@age >= 18',
      language = 'moonscript'
    }
    local result = apply_filter(tuples, flt, nil)
    R.eq(#result, 1)
    return R.eq(result[1].nom, 'Alice')
  end)
end)
R.describe("FK proxy — intégration via Query.records avec filtre formule", function()
  R.it("records() filtre @genre_id.libelle == 'Roman' → 1 résultat", function()
    local res = data_Query.records({ }, {
      spaceId = fk_livres_sp_id,
      filter = {
        formula = '@genre_id.libelle == "Roman"',
        language = 'moonscript'
      }
    }, CTX_FK)
    R.ok(res)
    R.eq(res.total, 1)
    R.ok(res.items[1] ~= nil)
    if require('json') then
      local json
      json = require('json').json
    end
    local d = type(res.items[1].data) == 'string' and require('json').decode(res.items[1].data) or res.items[1].data
    return R.eq(d.titre, 'Les Misérables')
  end)
  R.it("records() filtre @genre_id.libelle == 'Polar' → 1 résultat", function()
    local res = data_Query.records({ }, {
      spaceId = fk_livres_sp_id,
      filter = {
        formula = '@genre_id.libelle == "Polar"',
        language = 'moonscript'
      }
    }, CTX_FK)
    R.eq(res.total, 1)
    local d = type(res.items[1].data) == 'string' and require('json').decode(res.items[1].data) or res.items[1].data
    return R.eq(d.titre, 'Sherlock Holmes')
  end)
  return R.it("records() sans filtre FK → tous les livres", function()
    local res = data_Query.records({ }, {
      spaceId = fk_livres_sp_id
    }, CTX_FK)
    return R.eq(res.total, 2)
  end)
end)
R.describe("FK proxy — chaîne imbriquée @livre.auteur.nom", function()
  local NESTSFX = tostring(math.random(100000, 999999))
  local nested_authors_sp_id = nil
  local nested_books_sp_id = nil
  local nested_loans_sp_id = nil
  local nested_rel_book_author_id = nil
  local nested_rel_loan_book_id = nil
  do
    local authors_sp = spaces_mod.create_user_space("fk_nested_authors_" .. tostring(NESTSFX), "nested FK authors")
    local books_sp = spaces_mod.create_user_space("fk_nested_books_" .. tostring(NESTSFX), "nested FK books")
    local loans_sp = spaces_mod.create_user_space("fk_nested_loans_" .. tostring(NESTSFX), "nested FK loans")
    nested_authors_sp_id = authors_sp.id
    nested_books_sp_id = books_sp.id
    nested_loans_sp_id = loans_sp.id
    spaces_mod.add_field(nested_authors_sp_id, 'id', 'Sequence')
    spaces_mod.add_field(nested_books_sp_id, 'id', 'Sequence')
    spaces_mod.add_field(nested_loans_sp_id, 'id', 'Sequence')
    local author_name_f = spaces_mod.add_field(nested_authors_sp_id, 'nom', 'String')
    local book_author_f = spaces_mod.add_field(nested_books_sp_id, 'auteur', 'Int')
    local loan_book_f = spaces_mod.add_field(nested_loans_sp_id, 'livre', 'Int')
    local find_field_id
    find_field_id = function(space_id, field_name)
      local _list_0 = spaces_mod.list_fields(space_id)
      for _index_0 = 1, #_list_0 do
        local f = _list_0[_index_0]
        if f.name == field_name then
          return f.id
        end
      end
      return nil
    end
    local author_id_field_id = find_field_id(nested_authors_sp_id, 'id')
    local book_id_field_id = find_field_id(nested_books_sp_id, 'id')
    local rel_book_author = schema_Mutation.createRelation({ }, {
      input = {
        name = "fk_nested_book_author_" .. tostring(NESTSFX),
        fromSpaceId = nested_books_sp_id,
        fromFieldId = book_author_f.id,
        toSpaceId = nested_authors_sp_id,
        toFieldId = author_id_field_id
      }
    }, CTX_FK)
    nested_rel_book_author_id = rel_book_author.id
    local rel_loan_book = schema_Mutation.createRelation({ }, {
      input = {
        name = "fk_nested_loan_book_" .. tostring(NESTSFX),
        fromSpaceId = nested_loans_sp_id,
        fromFieldId = loan_book_f.id,
        toSpaceId = nested_books_sp_id,
        toFieldId = book_id_field_id
      }
    }, CTX_FK)
    nested_rel_loan_book_id = rel_loan_book.id
    data_Mutation.insertRecord({ }, {
      spaceId = nested_authors_sp_id,
      data = {
        nom = 'Hugo'
      }
    }, CTX_FK)
    data_Mutation.insertRecord({ }, {
      spaceId = nested_books_sp_id,
      data = {
        auteur = 1
      }
    }, CTX_FK)
  end
  R.it("résout une FK imbriquée quand la relation cible un champ id (non _id)", function()
    local fk_map = triggers.build_fk_def_map(nested_loans_sp_id)
    local proxy = triggers.make_self_proxy({
      livre = 1
    }, fk_map)
    R.ok(proxy.livre ~= nil)
    R.ok(proxy.livre.auteur ~= nil)
    return R.eq(proxy.livre.auteur.nom, 'Hugo')
  end)
  return R.it("nettoie les espaces et relations du test imbriqué", function()
    if nested_rel_loan_book_id then
      schema_Mutation.deleteRelation({ }, {
        id = nested_rel_loan_book_id
      }, CTX_FK)
    end
    if nested_rel_book_author_id then
      schema_Mutation.deleteRelation({ }, {
        id = nested_rel_book_author_id
      }, CTX_FK)
    end
    spaces_mod.delete_user_space("fk_nested_loans_" .. tostring(NESTSFX))
    spaces_mod.delete_user_space("fk_nested_books_" .. tostring(NESTSFX))
    return spaces_mod.delete_user_space("fk_nested_authors_" .. tostring(NESTSFX))
  end)
end)
schema_Mutation.deleteRelation({ }, {
  id = fk_rel_id
}, CTX_FK)
spaces_mod.delete_user_space("fktest_genres_" .. tostring(FKSFX))
return spaces_mod.delete_user_space("fktest_livres_" .. tostring(FKSFX))
