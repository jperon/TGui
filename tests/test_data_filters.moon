-- tests/test_data_filters.moon
-- Tests des opérateurs de filtrage (matches_filter / apply_filter).
-- La fonction matches_filter est locale dans data_resolvers ;
-- on la teste en allant chercher les records via le GraphQL ou en testant
-- directement via les fonctions du module (accès par require).

R = require 'tests.runner'

-- matches_filter et apply_filter sont locaux mais on peut les tester via
-- les resolvers en insérant des données et en filtrant via records().
-- On teste la logique métier en accédant aux fonctions via un require dédié.
-- Astuce : on recharge le module pour accéder aux fonctions locales via un
-- wrapper de test.

-- Pour accéder aux fonctions locales, on les expose temporairement via un
-- patch du module ou on les re-implémente ici pour tester la logique seule.
-- Approche choisie : copier la logique de matches_filter ici et la tester
-- indépendamment (test de logique pure sans dépendance Tarantool).

triggers = require 'core.triggers'

-- Réimplémentation fidèle de matches_filter pour test unitaire
matches_filter = (parsed, flt) ->
  return true unless flt
  ok = if flt.formula and flt.formula != ''
    if type(flt._formula_fn) == 'function'
      r_ok, r_val = pcall flt._formula_fn, parsed
      r_ok and r_val and r_val != false
    else false
  else if flt.field
    v = tostring (parsed[flt.field] or '')
    switch flt.op
      when 'EQ'          then v == flt.value
      when 'NEQ'         then v != flt.value
      when 'LT'          then tonumber(v) < tonumber(flt.value)
      when 'GT'          then tonumber(v) > tonumber(flt.value)
      when 'LTE'         then tonumber(v) <= tonumber(flt.value)
      when 'GTE'         then tonumber(v) >= tonumber(flt.value)
      when 'CONTAINS'    then v\find(flt.value, 1, true) != nil
      when 'STARTS_WITH' then v\sub(1, #flt.value) == flt.value
      else true
  else true
  if ok and flt["and"]
    for sub in *flt["and"]
      break unless ok
      ok = matches_filter parsed, sub
  if flt["or"]
    any = false
    for sub in *flt["or"]
      if matches_filter parsed, sub
        any = true
        break
    ok = ok and any
  ok

apply_filter = (tuples, filter) ->
  return tuples unless filter and (filter.field or filter.formula or filter["and"] or filter["or"])
  if filter.formula and filter.formula != '' and filter._formula_fn == nil
    lang = filter.language or 'lua'
    ok_c, fn = pcall triggers.compile_formula, filter.formula, 'filter', lang
    filter._formula_fn = if ok_c and type(fn) == 'function' then fn else false
  [r for r in *tuples when matches_filter r, filter]

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur EQ", ->

  R.it "EQ : égalité exacte → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Dupont' }

  R.it "EQ : inégalité → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Martin' }), false

  R.it "EQ : champ absent → compare '' à valeur", ->
    R.eq matches_filter({}, { field: 'x', op: 'EQ', value: '' }), true
    R.eq matches_filter({}, { field: 'x', op: 'EQ', value: 'truc' }), false

  R.it "EQ : comparaison numérique convertie en string", ->
    R.ok matches_filter { age: 42 }, { field: 'age', op: 'EQ', value: '42' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur NEQ", ->

  R.it "NEQ : valeurs différentes → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'NEQ', value: 'Martin' }

  R.it "NEQ : valeurs égales → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'NEQ', value: 'Dupont' }), false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateurs LT / GT / LTE / GTE", ->

  R.it "LT : strictement inférieur → true", ->
    R.ok matches_filter { age: 30 }, { field: 'age', op: 'LT', value: '40' }

  R.it "LT : égal → false", ->
    R.eq matches_filter({ age: 40 }, { field: 'age', op: 'LT', value: '40' }), false

  R.it "GT : strictement supérieur → true", ->
    R.ok matches_filter { age: 50 }, { field: 'age', op: 'GT', value: '40' }

  R.it "GT : égal → false", ->
    R.eq matches_filter({ age: 40 }, { field: 'age', op: 'GT', value: '40' }), false

  R.it "LTE : inférieur ou égal → true", ->
    R.ok matches_filter { age: 40 }, { field: 'age', op: 'LTE', value: '40' }
    R.ok matches_filter { age: 39 }, { field: 'age', op: 'LTE', value: '40' }

  R.it "GTE : supérieur ou égal → true", ->
    R.ok matches_filter { age: 40 }, { field: 'age', op: 'GTE', value: '40' }
    R.ok matches_filter { age: 41 }, { field: 'age', op: 'GTE', value: '40' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur CONTAINS", ->

  R.it "CONTAINS : sous-chaîne présente → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'CONTAINS', value: 'pont' }

  R.it "CONTAINS : sous-chaîne absente → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'CONTAINS', value: 'xyz' }), false

  R.it "CONTAINS : chaîne vide correspond toujours", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'CONTAINS', value: '' }

  R.it "CONTAINS : caractères spéciaux Lua non interprétés comme patterns", ->
    -- Le '.' en pattern Lua correspond à tout. Avec find(plain=true) il ne doit pas.
    R.eq matches_filter({ code: 'abc' }, { field: 'code', op: 'CONTAINS', value: 'a.c' }), false
    R.ok matches_filter  { code: 'a.c' }, { field: 'code', op: 'CONTAINS', value: 'a.c' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur STARTS_WITH", ->

  R.it "STARTS_WITH : début exact → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'STARTS_WITH', value: 'Du' }

  R.it "STARTS_WITH : ne commence pas par → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'STARTS_WITH', value: 'pont' }), false

  R.it "STARTS_WITH : chaîne vide → true (tout commence par '')", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'STARTS_WITH', value: '' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — combinaisons AND / OR", ->

  R.it "AND : les deux conditions vraies → true", ->
    flt = {}
    flt["and"] = { { field: 'a', op: 'EQ', value: '1' }, { field: 'b', op: 'EQ', value: '2' } }
    R.ok matches_filter { a: '1', b: '2' }, flt

  R.it "AND : une condition fausse → false", ->
    flt = {}
    flt["and"] = { { field: 'a', op: 'EQ', value: '1' }, { field: 'b', op: 'EQ', value: '2' } }
    R.eq matches_filter({ a: '1', b: '99' }, flt), false

  R.it "OR : au moins une condition vraie → true", ->
    flt = {}
    flt["or"] = { { field: 'nom', op: 'EQ', value: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Martin' } }
    R.ok matches_filter { nom: 'Martin' }, flt

  R.it "OR : aucune condition vraie → false", ->
    flt = {}
    flt["or"] = { { field: 'nom', op: 'EQ', value: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Martin' } }
    R.eq matches_filter({ nom: 'Durand' }, flt), false

  R.it "filtre nil → true (pas de filtre)", ->
    R.ok matches_filter { nom: 'Dupont' }, nil

  R.it "filtre sans field ni and/or → true (filtre vide)", ->
    R.ok matches_filter { nom: 'Dupont' }, {}

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur inconnu", ->

  R.it "opérateur inconnu → toujours true (non filtrant)", ->
    R.ok matches_filter { x: 'y' }, { field: 'x', op: 'UNKNOWN_OP', value: 'z' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — filtre formule Lua", ->

  R.it "formule vraie → true", ->
    fn = triggers.compile_formula 'self.age > 18', 'test', 'moonscript'
    flt = { formula: 'self.age > 18', language: 'moonscript', _formula_fn: fn }
    R.ok matches_filter { age: 30 }, flt

  R.it "formule fausse → false", ->
    fn = triggers.compile_formula 'self.age > 18', 'test', 'moonscript'
    flt = { formula: 'self.age > 18', language: 'moonscript', _formula_fn: fn }
    R.eq matches_filter({ age: 10 }, flt), false

  R.it "formule avec accès à un champ string", ->
    fn = triggers.compile_formula 'self.nom == "Hugo"', 'test', 'moonscript'
    flt = { formula: 'self.nom == "Hugo"', language: 'moonscript', _formula_fn: fn }
    R.ok matches_filter { nom: 'Hugo' }, flt
    R.eq matches_filter({ nom: 'Balzac' }, flt), false

  R.it "formule erreur de compilation → false (_formula_fn = false)", ->
    -- _formula_fn explicitement false = compilation échouée, filtre bloquant
    flt = { formula: 'syntax_error???', _formula_fn: false }
    R.eq matches_filter({ x: 1 }, flt), false

  R.it "formule Lua native (sans return)", ->
    fn = triggers.compile_formula 'self.score >= 5', 'filter_test', 'lua'
    R.ok fn != nil, "compile_formula doit retourner une fonction"
    flt = { formula: 'self.score >= 5', language: 'lua', _formula_fn: fn }
    R.ok matches_filter { score: 7 }, flt
    R.eq matches_filter({ score: 3 }, flt), false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "apply_filter — filtre formule (compilation auto)", ->

  R.it "formule filtre une liste, ne modifie pas les enregistrements sans match", ->
    data = { { nom: 'Alice', age: 25 }, { nom: 'Bob', age: 15 }, { nom: 'Charlie', age: 30 } }
    flt = { formula: 'self.age >= 18', language: 'moonscript' }
    result = apply_filter data, flt
    R.eq #result, 2
    R.eq result[1].nom, 'Alice'
    R.eq result[2].nom, 'Charlie'

  R.it "formule vide → toutes les lignes retournées", ->
    data = { { x: 1 }, { x: 2 } }
    flt = { formula: '' }
    result = apply_filter data, flt
    R.eq #result, 2

  R.it "formule compilée une seule fois (cache _formula_fn)", ->
    data = { { n: 1 }, { n: 2 }, { n: 3 } }
    flt = { formula: 'self.n > 1', language: 'moonscript' }
    result = apply_filter data, flt
    R.eq #result, 2
    -- _formula_fn doit être mis en cache
    R.ok flt._formula_fn != nil and flt._formula_fn != false


-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur EQ", ->

  R.it "EQ : égalité exacte → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Dupont' }

  R.it "EQ : inégalité → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Martin' }), false

  R.it "EQ : champ absent → compare '' à valeur", ->
    R.eq matches_filter({}, { field: 'x', op: 'EQ', value: '' }), true
    R.eq matches_filter({}, { field: 'x', op: 'EQ', value: 'truc' }), false

  R.it "EQ : comparaison numérique convertie en string", ->
    R.ok matches_filter { age: 42 }, { field: 'age', op: 'EQ', value: '42' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur NEQ", ->

  R.it "NEQ : valeurs différentes → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'NEQ', value: 'Martin' }

  R.it "NEQ : valeurs égales → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'NEQ', value: 'Dupont' }), false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur CONTAINS", ->

  R.it "CONTAINS : sous-chaîne présente → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'CONTAINS', value: 'pont' }

  R.it "CONTAINS : sous-chaîne absente → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'CONTAINS', value: 'xyz' }), false

  R.it "CONTAINS : chaîne vide correspond toujours", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'CONTAINS', value: '' }

  R.it "CONTAINS : caractères spéciaux Lua non interprétés comme patterns", ->
    -- Le '.' en pattern Lua correspond à tout. Avec find(plain=true) il ne doit pas.
    R.eq matches_filter({ code: 'abc' }, { field: 'code', op: 'CONTAINS', value: 'a.c' }), false
    R.ok matches_filter  { code: 'a.c' }, { field: 'code', op: 'CONTAINS', value: 'a.c' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur STARTS_WITH", ->

  R.it "STARTS_WITH : début exact → true", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'STARTS_WITH', value: 'Du' }

  R.it "STARTS_WITH : ne commence pas par → false", ->
    R.eq matches_filter({ nom: 'Dupont' }, { field: 'nom', op: 'STARTS_WITH', value: 'pont' }), false

  R.it "STARTS_WITH : chaîne vide → true (tout commence par '')", ->
    R.ok matches_filter { nom: 'Dupont' }, { field: 'nom', op: 'STARTS_WITH', value: '' }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — combinaisons AND / OR", ->

  R.it "AND : les deux conditions vraies → true", ->
    flt = {}
    flt["and"] = { { field: 'a', op: 'EQ', value: '1' }, { field: 'b', op: 'EQ', value: '2' } }
    R.ok matches_filter { a: '1', b: '2' }, flt

  R.it "AND : une condition fausse → false", ->
    flt = {}
    flt["and"] = { { field: 'a', op: 'EQ', value: '1' }, { field: 'b', op: 'EQ', value: '2' } }
    R.eq matches_filter({ a: '1', b: '99' }, flt), false

  R.it "OR : au moins une condition vraie → true", ->
    flt = {}
    flt["or"] = { { field: 'nom', op: 'EQ', value: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Martin' } }
    R.ok matches_filter { nom: 'Martin' }, flt

  R.it "OR : aucune condition vraie → false", ->
    flt = {}
    flt["or"] = { { field: 'nom', op: 'EQ', value: 'Dupont' }, { field: 'nom', op: 'EQ', value: 'Martin' } }
    R.eq matches_filter({ nom: 'Durand' }, flt), false

  R.it "filtre nil → true (pas de filtre)", ->
    R.ok matches_filter { nom: 'Dupont' }, nil

  R.it "filtre sans field ni and/or → true (filtre vide)", ->
    R.ok matches_filter { nom: 'Dupont' }, {}

-- ────────────────────────────────────────────────────────────────────────────
R.describe "matches_filter — opérateur inconnu", ->

  R.it "opérateur inconnu → toujours true (non filtrant)", ->
    R.ok matches_filter { x: 'y' }, { field: 'x', op: 'UNKNOWN_OP', value: 'z' }
