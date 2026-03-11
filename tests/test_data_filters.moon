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

triggers   = require 'core.triggers'
spaces_mod = require 'core.spaces'
{ Query: schema_Query, Mutation: schema_Mutation } = require 'resolvers.schema_resolvers'
{ Query: data_Query,   Mutation: data_Mutation }   = require 'resolvers.data_resolvers'

CTX_FK = { user_id: 'test-user' }

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

-- fk_def_map is optional; when present, formula filters receive an FK-aware proxy
-- (matches new signature in data_resolvers: apply_filter(tuples, filter, fk_def_map))
apply_filter = (tuples, filter, fk_def_map) ->
  return tuples unless filter and (filter.field or filter.formula or filter["and"] or filter["or"])
  if filter.formula and filter.formula != '' and filter._formula_fn == nil
    lang = filter.language or 'lua'
    ok_c, fn = pcall triggers.compile_formula, filter.formula, 'filter', lang
    filter._formula_fn = if ok_c and type(fn) == 'function' then fn else false
  result = {}
  for r in *tuples
    self_val = if fk_def_map
      triggers.make_self_proxy r, fk_def_map
    else
      r
    table.insert result, r if matches_filter self_val, filter
  result

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

-- ────────────────────────────────────────────────────────────────────────────
-- FK proxy — traversée de relations dans les formules
-- ────────────────────────────────────────────────────────────────────────────

FKSFX = tostring math.random(100000, 999999)

local fk_genres_sp_id, fk_livres_sp_id, fk_rel_id
local fk_libelle_field_id, fk_genre_id_field_id
local genre_roman_uuid, genre_polar_uuid

do
  genres_sp = spaces_mod.create_user_space "fktest_genres_#{FKSFX}", "genres FK test"
  livres_sp = spaces_mod.create_user_space "fktest_livres_#{FKSFX}", "livres FK test"
  fk_genres_sp_id = genres_sp.id
  fk_livres_sp_id = livres_sp.id

  libelle_f   = spaces_mod.add_field fk_genres_sp_id, 'libelle',  'String'
  fk_libelle_field_id = libelle_f.id

  spaces_mod.add_field fk_livres_sp_id, 'titre', 'String'
  genre_id_f  = spaces_mod.add_field fk_livres_sp_id, 'genre_id', 'String'
  fk_genre_id_field_id = genre_id_f.id

  -- Relation FK : livres.genre_id → genres (target: libelle field as reference point)
  rel = schema_Mutation.createRelation {}, {
    input: {
      name:        "fktest_rel_#{FKSFX}"
      fromSpaceId: fk_livres_sp_id
      fromFieldId: fk_genre_id_field_id
      toSpaceId:   fk_genres_sp_id
      toFieldId:   fk_libelle_field_id
    }
  }, CTX_FK
  fk_rel_id = rel.id

  -- Insérer deux genres
  roman_rec = data_Mutation.insertRecord {}, { spaceId: fk_genres_sp_id, data: { libelle: 'Roman' } }, CTX_FK
  polar_rec = data_Mutation.insertRecord {}, { spaceId: fk_genres_sp_id, data: { libelle: 'Polar' } }, CTX_FK
  genre_roman_uuid = roman_rec.id
  genre_polar_uuid = polar_rec.id

  -- Insérer des livres ; genre_id stocke l'UUID (_id) du genre → PK lookup direct
  data_Mutation.insertRecord {}, { spaceId: fk_livres_sp_id, data: { titre: 'Les Misérables',  genre_id: genre_roman_uuid } }, CTX_FK
  data_Mutation.insertRecord {}, { spaceId: fk_livres_sp_id, data: { titre: 'Sherlock Holmes', genre_id: genre_polar_uuid } }, CTX_FK

R.describe "FK proxy — make_self_proxy résout les champs FK", ->

  R.it "proxy.genre_id retourne un sous-proxy (table)", ->
    fk_map = triggers.build_fk_def_map fk_livres_sp_id
    proxy  = triggers.make_self_proxy { titre: 'Test', genre_id: genre_roman_uuid }, fk_map
    genre_proxy = proxy.genre_id
    R.ok genre_proxy != nil, "genre_id doit retourner un proxy non nil"
    R.eq type(genre_proxy), 'table'

  R.it "proxy.genre_id.libelle retourne la valeur du champ de l'enregistrement lié", ->
    fk_map = triggers.build_fk_def_map fk_livres_sp_id
    proxy  = triggers.make_self_proxy { titre: 'Test', genre_id: genre_roman_uuid }, fk_map
    R.eq proxy.genre_id.libelle, 'Roman'

  R.it "proxy.titre retourne le champ non-FK directement", ->
    fk_map = triggers.build_fk_def_map fk_livres_sp_id
    proxy  = triggers.make_self_proxy { titre: 'Dune', genre_id: genre_polar_uuid }, fk_map
    R.eq proxy.titre, 'Dune'

  R.it "proxy FK nil → nil sans plantage", ->
    fk_map = triggers.build_fk_def_map fk_livres_sp_id
    proxy  = triggers.make_self_proxy { titre: 'Sans genre' }, fk_map
    R.is_nil proxy.genre_id

R.describe "FK proxy — apply_filter avec formule @fk_field.sub_field", ->

  R.it "filtre @genre_id.libelle == 'Roman' retourne seulement les romans", ->
    fk_map = triggers.build_fk_def_map fk_livres_sp_id
    tuples = {
      { titre: 'Les Misérables',  genre_id: genre_roman_uuid }
      { titre: 'Sherlock Holmes', genre_id: genre_polar_uuid }
    }
    flt    = { formula: '@genre_id.libelle == "Roman"', language: 'moonscript' }
    result = apply_filter tuples, flt, fk_map
    R.eq #result, 1
    R.eq result[1].titre, 'Les Misérables'

  R.it "filtre sans fk_def_map (nil) ne plante pas sur les tests non-FK", ->
    tuples = { { nom: 'Alice', age: 25 }, { nom: 'Bob', age: 15 } }
    flt    = { formula: '@age >= 18', language: 'moonscript' }
    result = apply_filter tuples, flt, nil
    R.eq #result, 1
    R.eq result[1].nom, 'Alice'

R.describe "FK proxy — intégration via Query.records avec filtre formule", ->

  R.it "records() filtre @genre_id.libelle == 'Roman' → 1 résultat", ->
    res = data_Query.records {}, {
      spaceId: fk_livres_sp_id
      filter:  { formula: '@genre_id.libelle == "Roman"', language: 'moonscript' }
    }, CTX_FK
    R.ok res
    R.eq res.total, 1
    R.ok res.items[1] != nil
    import json from require 'json' if require 'json'
    d = type(res.items[1].data) == 'string' and require('json').decode(res.items[1].data) or res.items[1].data
    R.eq d.titre, 'Les Misérables'

  R.it "records() filtre @genre_id.libelle == 'Polar' → 1 résultat", ->
    res = data_Query.records {}, {
      spaceId: fk_livres_sp_id
      filter:  { formula: '@genre_id.libelle == "Polar"', language: 'moonscript' }
    }, CTX_FK
    R.eq res.total, 1
    d = type(res.items[1].data) == 'string' and require('json').decode(res.items[1].data) or res.items[1].data
    R.eq d.titre, 'Sherlock Holmes'

  R.it "records() sans filtre FK → tous les livres", ->
    res = data_Query.records {}, { spaceId: fk_livres_sp_id }, CTX_FK
    R.eq res.total, 2

R.describe "FK proxy — chaîne imbriquée @livre.auteur.nom", ->
  NESTSFX = tostring math.random(100000, 999999)

  nested_authors_sp_id = nil
  nested_books_sp_id = nil
  nested_loans_sp_id = nil
  nested_rel_book_author_id = nil
  nested_rel_loan_book_id = nil

  do
    authors_sp = spaces_mod.create_user_space "fk_nested_authors_#{NESTSFX}", "nested FK authors"
    books_sp   = spaces_mod.create_user_space "fk_nested_books_#{NESTSFX}", "nested FK books"
    loans_sp   = spaces_mod.create_user_space "fk_nested_loans_#{NESTSFX}", "nested FK loans"

    nested_authors_sp_id = authors_sp.id
    nested_books_sp_id   = books_sp.id
    nested_loans_sp_id   = loans_sp.id

    spaces_mod.add_field nested_authors_sp_id, 'id', 'Sequence'
    spaces_mod.add_field nested_books_sp_id, 'id', 'Sequence'
    spaces_mod.add_field nested_loans_sp_id, 'id', 'Sequence'

    author_name_f = spaces_mod.add_field nested_authors_sp_id, 'nom', 'String'
    book_author_f = spaces_mod.add_field nested_books_sp_id, 'auteur', 'Int'
    loan_book_f   = spaces_mod.add_field nested_loans_sp_id, 'livre',  'Int'

    find_field_id = (space_id, field_name) ->
      for f in *spaces_mod.list_fields space_id
        return f.id if f.name == field_name
      nil

    author_id_field_id = find_field_id nested_authors_sp_id, 'id'
    book_id_field_id   = find_field_id nested_books_sp_id, 'id'

    rel_book_author = schema_Mutation.createRelation {}, {
      input: {
        name: "fk_nested_book_author_#{NESTSFX}"
        fromSpaceId: nested_books_sp_id
        fromFieldId: book_author_f.id
        toSpaceId: nested_authors_sp_id
        toFieldId: author_id_field_id
      }
    }, CTX_FK
    nested_rel_book_author_id = rel_book_author.id

    rel_loan_book = schema_Mutation.createRelation {}, {
      input: {
        name: "fk_nested_loan_book_#{NESTSFX}"
        fromSpaceId: nested_loans_sp_id
        fromFieldId: loan_book_f.id
        toSpaceId: nested_books_sp_id
        toFieldId: book_id_field_id
      }
    }, CTX_FK
    nested_rel_loan_book_id = rel_loan_book.id

    data_Mutation.insertRecord {}, { spaceId: nested_authors_sp_id, data: { nom: 'Hugo' } }, CTX_FK
    data_Mutation.insertRecord {}, { spaceId: nested_books_sp_id, data: { auteur: 1 } }, CTX_FK

  R.it "résout une FK imbriquée quand la relation cible un champ id (non _id)", ->
    fk_map = triggers.build_fk_def_map nested_loans_sp_id
    proxy = triggers.make_self_proxy { livre: 1 }, fk_map
    R.ok proxy.livre != nil
    R.ok proxy.livre.auteur != nil
    R.eq proxy.livre.auteur.nom, 'Hugo'

  R.it "nettoie les espaces et relations du test imbriqué", ->
    schema_Mutation.deleteRelation {}, { id: nested_rel_loan_book_id }, CTX_FK if nested_rel_loan_book_id
    schema_Mutation.deleteRelation {}, { id: nested_rel_book_author_id }, CTX_FK if nested_rel_book_author_id
    spaces_mod.delete_user_space "fk_nested_loans_#{NESTSFX}"
    spaces_mod.delete_user_space "fk_nested_books_#{NESTSFX}"
    spaces_mod.delete_user_space "fk_nested_authors_#{NESTSFX}"

-- ── Nettoyage ─────────────────────────────────────────────────────────────────

schema_Mutation.deleteRelation {}, { id: fk_rel_id }, CTX_FK
spaces_mod.delete_user_space "fktest_genres_#{FKSFX}"
spaces_mod.delete_user_space "fktest_livres_#{FKSFX}"
