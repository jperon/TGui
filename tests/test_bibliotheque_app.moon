-- tests/test_bibliotheque_app.moon
-- T9a : tests de tools.bibliotheque_app.seed_tables (aucune dépendance
-- aux YAML de structure de backend/apps/bibliotheque/).

R = require 'tests.runner'
json = require 'json'

_mod = nil

-- Chargement tolerant : si le module n'existe pas encore, chaque `it` echoue
-- proprement (ERROR) au lieu de faire echouer toute la decouverte des tests.
load_app = ->
  return _mod if _mod
  ok, mod = pcall require, 'tools.bibliotheque_app'
  error "module 'tools.bibliotheque_app' indisponible : #{mod}" unless ok
  _mod = mod
  _mod

EXPECTED_COUNTS = {
  { 'Titres', 4 }
  { 'Sections', 2 }
  { 'Annee', 3 }
  { 'Niveaux', 5 }
  { 'Personnes', 72 }
  { 'Prefectures', 3 }
  { 'Classes', 10 }
  { 'ClassesEleves', 108 }
  { 'Genres', 15 }
  { 'Auteurs', 25 }
  { 'MotsCles', 40 }
  { 'Livres', 60 }
  { 'LivresMotsCles', 120 }
  { 'Exemplaires', 100 }
  { 'Emprunts', 120 }
  { 'TypesCoordonnees', 3 }
  { 'Coordonnees', 30 }
  { 'PersonnesCoordonnees', 50 }
}

-- {espace, champ, espace cible} — miroir des `ref:` des structure/*.yaml du plan
-- (T3 école, T4 bibliothèque, T5 coordonnées).
FOREIGN_KEYS = {
  { 'Annee', 'section', 'Sections' }
  { 'Niveaux', 'superieur', 'Niveaux' }
  { 'Personnes', 'titre', 'Titres' }
  { 'Personnes', 'famille', 'Personnes' }
  { 'Prefectures', 'annee', 'Annee' }
  { 'Prefectures', 'prefet', 'Personnes' }
  { 'Prefectures', 'niveau_min', 'Niveaux' }
  { 'Prefectures', 'niveau_max', 'Niveaux' }
  { 'Classes', 'niveau', 'Niveaux' }
  { 'Classes', 'annee', 'Annee' }
  { 'Classes', 'prefecture', 'Prefectures' }
  { 'Classes', 'professeur_principal', 'Personnes' }
  { 'ClassesEleves', 'classe', 'Classes' }
  { 'ClassesEleves', 'eleve', 'Personnes' }
  { 'Genres', 'parent', 'Genres' }
  { 'Livres', 'auteur', 'Auteurs' }
  { 'Livres', 'genre', 'Genres' }
  { 'LivresMotsCles', 'livre', 'Livres' }
  { 'LivresMotsCles', 'mot_cle', 'MotsCles' }
  { 'Exemplaires', 'livre', 'Livres' }
  { 'Emprunts', 'personne', 'Personnes' }
  { 'Emprunts', 'exemplaire', 'Exemplaires' }
  { 'Coordonnees', 'type_coordonnee', 'TypesCoordonnees' }
  { 'PersonnesCoordonnees', 'personne', 'Personnes' }
  { 'PersonnesCoordonnees', 'coordonnee', 'Coordonnees' }
}

by_space = (tables) ->
  map = {}
  map[t.space] = t.rows for t in *tables
  map

id_set = (rows) ->
  ids = {}
  ids[r.id] = true for r in *rows
  ids

missing_fk = (rows, field, ids) ->
  out = {}
  for r in *rows
    v = r[field]
    table.insert out, v if v != nil and v != '' and not ids[v]
  out

duplicate_ids = (rows) ->
  seen, out = {}, {}
  for r in *rows
    if r.id == nil
      table.insert out, 'nil'
    elseif seen[r.id]
      table.insert out, r.id
    else
      seen[r.id] = true
  out

space_names = (tables) ->
  [t.space for t in *tables]

expected_names = [e[1] for e in *EXPECTED_COUNTS]

R.describe "bibliotheque_app.seed_tables", ->
  R.it "is deterministic (two calls encode to the same JSON)", ->
    m = load_app!
    R.eq json.encode(m.seed_tables!), json.encode(m.seed_tables!)

  R.it "has the exact row counts at scale 1, in order", ->
    m = load_app!
    tables = m.seed_tables!
    map = by_space tables
    R.eq json.encode(space_names(tables)), json.encode(expected_names), 'space order'
    for e in *EXPECTED_COUNTS
      rows = map[e[1]]
      if rows
        R.eq #rows, e[2], e[1]
      else
        R.ok rows, "espace #{e[1]} absent"

  R.it "keeps every non-empty foreign key valid", ->
    m = load_app!
    map = by_space m.seed_tables!
    for fk in *FOREIGN_KEYS
      rows, target = map[fk[1]], map[fk[3]]
      unless rows and target
        R.ok false, "espace manquant #{fk[1]} → #{fk[3]}"
        continue
      bad = missing_fk rows, fk[2], id_set target
      R.eq #bad, 0, "#{fk[1]}.#{fk[2]} → #{fk[3]}: #{json.encode bad}"

  R.it "has unique ids in every space", ->
    m = load_app!
    for t in *m.seed_tables!
      dups = duplicate_ids t.rows
      R.eq #dups, 0, "#{t.space}: #{json.encode dups}"

  R.it "emits more rows at scale 2 (Personnes, Livres, Emprunts)", ->
    m = load_app!
    s1 = by_space m.seed_tables { scale: 1 }
    s2 = by_space m.seed_tables { scale: 2 }
    for name in *{ 'Personnes', 'Livres', 'Emprunts' }
      n1 = s1[name] and #s1[name]
      n2 = s2[name] and #s2[name]
      R.ok n1 and n2 and n2 > n1, "#{name}: #{n2} > #{n1}"
