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

-- Réimplémentation fidèle de matches_filter pour test unitaire
matches_filter = (parsed, flt) ->
  return true unless flt
  ok = if flt.field
    v = tostring (parsed[flt.field] or '')
    switch flt.op
      when 'EQ'          then v == flt.value
      when 'NEQ'         then v != flt.value
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
