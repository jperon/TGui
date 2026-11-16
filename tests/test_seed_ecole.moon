-- tests/test_seed_ecole.moon
-- T6 — Données fictives « école » : interface generate(rng, k) de
-- tools.bibliotheque_seed_ecole.
--
-- Le module n'existe pas encore au passage rouge : chaque cas signale son
-- absence par une assertion fausse au lieu de faire échouer toute la suite
-- par une erreur de `require`.
--
-- Note MoonScript : `for i, v in *list` ne donne PAS l'index (MoonScript
-- compile `local i, v = list[k]`, la 2e variable vaut nil) — les boucles à
-- deux variables sont écrites `for i = 1, #list`.

R = require 'tests.runner'
json = require 'json'
RNG = require 'tools.seed_rng'

_loaded, SEED = pcall require, 'tools.bibliotheque_seed_ecole'
SEED = nil unless _loaded

need = ->
  R.ok SEED, 'module tools.bibliotheque_seed_ecole absent'
  SEED != nil

gen = (k) -> SEED.generate RNG.new(1001), k or 1

rows_of = (out, space) ->
  for t in *out.tables
    return t.rows if t.space == space
  nil

count_of = (out, space) ->
  rows = rows_of out, space
  rows and #rows or 0

ORDER = 'Titres,Sections,Annee,Niveaux,Personnes,Prefectures,Classes,ClassesEleves'

VOLUMES = {
  { 'Titres', 4 }
  { 'Sections', 2 }
  { 'Annee', 3 }
  { 'Niveaux', 5 }
  { 'Personnes', 72 }
  { 'Prefectures', 3 }
  { 'Classes', 10 }
  { 'ClassesEleves', 108 }
}

FK_SPEC = {
  { from: 'Personnes', field: 'famille', to: 'Personnes' }
  { from: 'Personnes', field: 'titre', to: 'Titres' }
  { from: 'Annee', field: 'section', to: 'Sections' }
  { from: 'Niveaux', field: 'superieur', to: 'Niveaux' }
  { from: 'Prefectures', field: 'prefet', to: 'Personnes' }
  { from: 'Prefectures', field: 'annee', to: 'Annee' }
  { from: 'Prefectures', field: 'niveau_min', to: 'Niveaux' }
  { from: 'Prefectures', field: 'niveau_max', to: 'Niveaux' }
  { from: 'Classes', field: 'niveau', to: 'Niveaux' }
  { from: 'Classes', field: 'annee', to: 'Annee' }
  { from: 'Classes', field: 'prefecture', to: 'Prefectures' }
  { from: 'Classes', field: 'professeur_principal', to: 'Personnes' }
  { from: 'ClassesEleves', field: 'classe', to: 'Classes' }
  { from: 'ClassesEleves', field: 'eleve', to: 'Personnes' }
}

DATE_SPEC = {
  { space: 'Annee', field: 'debut' }
  { space: 'Annee', field: 'fin' }
  { space: 'Personnes', field: 'date_de_naissance' }
  { space: 'ClassesEleves', field: 'entree' }
  { space: 'ClassesEleves', field: 'depart' }
}

missing_ids = (rows, field, targets) ->
  ids = {}
  ids[r.id] = true for r in *targets
  bad = {}
  for r in *rows
    v = r[field]
    if v != nil and v != '' and not ids[v]
      table.insert bad, v
  bad

-- Niveau d'un élève d'après son rang dans la liste (12 élèves par niveau à k=1).
niveau_of = (idx) -> math.floor((idx - 1) / 12) + 1

_row_bad_keys = (space, idx, row) ->
  bad = {}
  for key, v in pairs row
    if v == nil or v == ''
      table.insert bad, "#{space}[#{idx}].#{key}"
  bad

empty_values = (out) ->
  bad = {}
  for t in *out.tables
    for i = 1, #t.rows
      row_bad = _row_bad_keys t.space, i, t.rows[i]
      for key in *row_bad
        table.insert bad, key
  bad

_row_bad_date = (space, idx, field, v) ->
  return nil if v == nil
  return "#{space}[#{idx}].#{field}=#{tostring v}" unless tostring(v)\match '^%d%d%d%d%-%d%d%-%d%d$'
  nil

bad_dates = (out) ->
  bad = {}
  for spec in *DATE_SPEC
    rows = rows_of out, spec.space
    for i = 1, #rows
      msg = _row_bad_date spec.space, i, spec.field, rows[i][spec.field]
      table.insert bad, msg if msg
  bad

R.describe "bibliotheque_seed_ecole.generate", ->

  R.it "returns the same rows for the same seed", ->
    return unless need!
    R.eq json.encode(gen!), json.encode(gen!), 'deux appels avec RNG.new(1001)'

  R.it "keeps the exact volumes at k = 1", ->
    return unless need!
    out = gen!
    R.eq #out.tables, 8, 'tables'
    for pair in *VOLUMES
      R.eq count_of(out, pair[1]), pair[2], pair[1]
    R.eq #out.adultes, 12, 'adultes'
    R.eq #out.eleves, 60, 'eleves'
    R.eq #out.personnes, 72, 'personnes'

  R.it "orders the tables as specified", ->
    return unless need!
    out = gen!
    names = [t.space for t in *out.tables]
    R.eq table.concat(names, ','), ORDER, 'ordre des tables'

  R.it "gives every row an explicit sequential id", ->
    return unless need!
    out = gen!
    for t in *out.tables
      for i = 1, #t.rows
        row = t.rows[i]
        R.eq row.id, i, "#{t.space} ligne #{i}"

  R.it "emits the reference rows of the plan", ->
    return unless need!
    out = gen!
    titres = rows_of out, 'Titres'
    labels = [t.titre for t in *titres]
    R.eq table.concat(labels, ','), 'M.,Mme,Frère,Sœur', 'titres'
    R.eq titres[1].femme, false, 'M. femme'
    R.eq titres[2].femme, true, 'Mme femme'
    R.eq titres[3].femme, false, 'Frère femme'
    R.eq titres[4].femme, true, 'Sœur femme'
    annees = rows_of out, 'Annee'
    R.eq annees[1].debut, '2024-09-01', 'annee 1 debut'
    R.eq annees[1].fin, '2025-06-30', 'annee 1 fin'
    R.eq annees[2].debut, '2025-09-01', 'annee 2 debut'
    R.eq annees[2].fin, '2026-06-30', 'annee 2 fin'
    R.eq annees[3].debut, '2026-09-01', 'annee 3 debut'
    R.eq annees[3].fin, '2027-06-30', 'annee 3 fin'
    R.nok annees[1].en_cours, 'annee 1 en_cours'
    R.nok annees[2].en_cours, 'annee 2 en_cours'
    R.eq annees[3].en_cours, true, 'annee 3 en_cours'
    niveaux = rows_of out, 'Niveaux'
    abreges = [n.abrege for n in *niveaux]
    R.eq table.concat(abreges, ','), 'CP,CE1,CE2,CM1,CM2', 'abreges'
    for i = 1, #niveaux
      n = niveaux[i]
      R.eq n.niveau, i, "niveau #{i}"
      if i < 5
        R.eq n.superieur, i + 1, "superieur du niveau #{i}"
      else
        R.is_nil n.superieur, 'superieur du niveau 5'

  R.it "points every foreign key at an existing id", ->
    return unless need!
    out = gen!
    for spec in *FK_SPEC
      bad = missing_ids rows_of(out, spec.from), spec.field, rows_of(out, spec.to)
      label = "#{spec.from}.#{spec.field} inconnus: #{table.concat(bad, ',')}"
      R.eq #bad, 0, label

  R.it "uses adults for the staff roles and parents for the families", ->
    return unless need!
    out = gen!
    for c in *rows_of(out, 'Classes')
      R.ok c.professeur_principal and c.professeur_principal <= 5, "professeur_principal #{tostring c.professeur_principal}"
    for p in *rows_of(out, 'Prefectures')
      R.ok p.prefet == 6 or p.prefet == 7, "prefet #{tostring p.prefet}"
    personnes = rows_of out, 'Personnes'
    for i = 13, #personnes
      p = personnes[i]
      R.ok p.famille and p.famille >= 8 and p.famille <= 12, "famille #{tostring p.famille} de la personne #{p.id}"

  R.it "keeps exactly one class row without depart per student", ->
    return unless need!
    out = gen!
    ces = rows_of out, 'ClassesEleves'
    for eleve in *out.eleves
      n = 0
      for r in *ces
        n += 1 if r.eleve == eleve and not r.depart
      R.eq n, 1, "eleve #{eleve}"

  R.it "places each student in the year-3 class of their own level", ->
    return unless need!
    out = gen!
    ces = rows_of out, 'ClassesEleves'
    for idx = 1, #out.eleves
      eleve = out.eleves[idx]
      current = nil
      for r in *ces
        current = r if r.eleve == eleve and not r.depart
      unless current
        R.ok false, "eleve #{eleve} sans classe en annee 3"
        continue
      R.eq current.classe, 5 + niveau_of(idx), "classe annee 3 de l'eleve #{eleve}"
      R.eq current.entree, '2026-09-01', "entree annee 3 de l'eleve #{eleve}"

  R.it "repeats every student of level 2+ in the class of the level below", ->
    return unless need!
    out = gen!
    ces = rows_of out, 'ClassesEleves'
    for idx = 1, #out.eleves
      eleve = out.eleves[idx]
      niveau = niveau_of idx
      prev = 0
      for r in *ces
        prev += 1 if r.eleve == eleve and r.depart
      if niveau == 1
        R.eq prev, 0, "eleve de niveau 1 (#{eleve})"
      else
        R.eq prev, 1, "eleve de niveau #{niveau} (#{eleve})"

  R.it "dates the year-2 class rows and marks no redoubling", ->
    return unless need!
    out = gen!
    ces = rows_of out, 'ClassesEleves'
    n_old = 0
    for r in *ces
      if r.depart
        n_old += 1
        R.eq r.entree, '2025-09-01', "entree ligne #{r.id}"
        R.eq r.depart, '2026-06-30', "depart ligne #{r.id}"
        R.eq r.redoublement, false, "redoublement ligne #{r.id}"
        R.eq r.classe, niveau_of(r.eleve - 12) - 1, "classe annee 2 ligne #{r.id}"
    R.eq n_old, 48, 'lignes de deuxieme annee'

  R.it "contains no empty string or nil value", ->
    return unless need!
    bad = empty_values gen!
    R.eq #bad, 0, "valeurs vides: #{table.concat(bad, ', ')}"

  R.it "writes dates as ISO strings", ->
    return unless need!
    bad = bad_dates gen!
    R.eq #bad, 0, "dates invalides: #{table.concat(bad, ', ')}"

  R.it "doubles the students at k = 2", ->
    return unless need!
    out = gen 2
    R.eq #out.eleves, 120, 'eleves'
    R.eq #out.adultes, 12, 'adultes'
    R.eq #out.personnes, 132, 'personnes'
    R.eq count_of(out, 'Personnes'), 132, 'Personnes'
    R.eq count_of(out, 'ClassesEleves'), 216, 'ClassesEleves'
    R.eq count_of(out, 'Classes'), 10, 'Classes'
    R.eq count_of(out, 'Titres'), 4, 'Titres'
