-- tests/test_seed_livres.moon
-- T7 — données fictives « bibliothèque » : volumes exacts, intégrité des clés
-- étrangères, contraintes de prêts, déterminisme.
-- `ecole` est un objet factice (aucune donnée personnelle réelle) :
-- élèves = ids 13..72, personnes = ids 1..72.
R = require 'tests.runner'
json = require 'json'
LIV = require 'tools.bibliotheque_seed_livres'
RNG = require 'tools.seed_rng'

ECOLE = { eleves: {}, personnes: {} }
for id = 1, 72
  table.insert ECOLE.personnes, id
for id = 13, 72
  table.insert ECOLE.eleves, id

ORDER = { 'Genres', 'Auteurs', 'MotsCles', 'Livres', 'LivresMotsCles', 'Exemplaires', 'Emprunts' }

GENRE_NAMES = { 'Fiction', 'Roman', 'Policier', 'Science-fiction', 'Aventure', 'Théâtre',
  'Poésie', 'Documentaire', 'Histoire', 'Sciences', 'Biographie', 'Bande dessinée',
  'Jeunesse', 'Contes', 'Albums' }
-- 0 = racine (pas de champ `parent`)
GENRE_PARENTS = { 0, 1, 2, 2, 2, 1, 1, 0, 8, 8, 8, 0, 0, 13, 13 }

ts = (s) -> os.time { year: tonumber(s\sub 1, 4), month: tonumber(s\sub 6, 7), day: tonumber(s\sub 9, 10), hour: 12 }
days_between = (a, b) -> math.floor((ts(b) - ts(a)) / 86400)

rows_of = (out) ->
  t = {}
  for tb in *out.tables
    t[tb.space] = tb.rows
  t

id_set = (rows) ->
  s = {}
  for r in *rows
    s[r.id] = true
  s

has_empty = (rows) ->
  for r in *rows
    for _, v in pairs r
      return true if v == '' or v == nil
  false

ISO = '^%d%d%d%d%-%d%d%-%d%d$'

-- Contraintes de prêts (plan T7) : au plus un prêt ouvert par exemplaire,
-- jamais sur un exemplaire supprimé, fenêtres de dates. Renvoie le nombre
-- de prêts non rendus.
check_loans = (rows, ex_rows, label) ->
  supp = {}
  for e in *ex_rows
    supp[e.id] = true if e.suppression
  ex_ids = id_set ex_rows
  open = {}
  n_open = 0
  for e in *rows
    R.ok ex_ids[e.exemplaire], "#{label}: emprunt #{e.id} → exemplaire #{e.exemplaire} existe"
    if not e.retour
      n_open += 1
      R.nok open[e.exemplaire], "#{label}: exemplaire #{e.exemplaire} avec deux prêts ouverts"
      R.nok supp[e.exemplaire], "#{label}: prêt ouvert sur exemplaire supprimé #{e.exemplaire}"
      open[e.exemplaire] = true
      R.ok e.emprunt >= '2026-09-10' and e.emprunt <= '2026-10-07', "#{label}: date de prêt ouvert #{e.emprunt}"
    else
      R.ok e.emprunt >= '2025-09-15' and e.emprunt <= '2026-06-15', "#{label}: date d'emprunt #{e.emprunt}"
      d = days_between e.emprunt, e.retour
      R.ok d >= 7 and d <= 40, "#{label}: retour à #{d} jours (emprunt #{e.id})"
  n_open

OUT1 = LIV.generate RNG.new(2002), 1, ECOLE
T = rows_of OUT1

R.describe "seed_livres (T7)", ->

  R.it "emits the seven tables in plan order", ->
    R.eq #OUT1.tables, 7, 'nb de tables'
    for i = 1, #ORDER
      R.eq OUT1.tables[i].space, ORDER[i], "table #{i}"

  R.it "has the exact k = 1 volumes", ->
    R.eq #T.Genres, 15, 'Genres'
    R.eq #T.Auteurs, 25, 'Auteurs'
    R.eq #T.MotsCles, 40, 'MotsCles'
    R.eq #T.Livres, 60, 'Livres'
    R.eq #T.LivresMotsCles, 120, 'LivresMotsCles'
    R.eq #T.Exemplaires, 100, 'Exemplaires'
    R.eq #T.Emprunts, 120, 'Emprunts'

  R.it "numbers every row with an explicit id from 1 to n", ->
    for name in *ORDER
      rows = T[name]
      for i = 1, #rows
        R.eq rows[i].id, i, "#{name}[#{i}].id"

  R.it "builds the 15-genre tree of the plan", ->
    for i = 1, 15
      g = T.Genres[i]
      R.eq g.genre, GENRE_NAMES[i], "genre #{i}"
      if GENRE_PARENTS[i] == 0
        R.is_nil g.parent, "genre #{i} racine"
      else
        R.eq g.parent, GENRE_PARENTS[i], "genre #{i} parent"

  R.it "keeps every foreign key on an existing row", ->
    A = id_set T.Auteurs
    G = id_set T.Genres
    L = id_set T.Livres
    M = id_set T.MotsCles
    E = id_set T.Exemplaires
    P = {}
    for id in *ECOLE.personnes
      P[id] = true
    for r in *T.Livres
      R.ok A[r.auteur], "livre #{r.id}: auteur #{r.auteur}"
      R.ok G[r.genre], "livre #{r.id}: genre #{r.genre}"
    for r in *T.LivresMotsCles
      R.ok L[r.livre], "livre-mot #{r.id}: livre #{r.livre}"
      R.ok M[r.mot_cle], "livre-mot #{r.id}: mot #{r.mot_cle}"
    for r in *T.Exemplaires
      R.ok L[r.livre], "exemplaire #{r.id}: livre #{r.livre}"
    for r in *T.Emprunts
      R.ok P[r.personne], "emprunt #{r.id}: personne #{r.personne}"
      R.ok E[r.exemplaire], "emprunt #{r.id}: exemplaire #{r.exemplaire}"

  R.it "stores no empty string anywhere", ->
    for name in *ORDER
      R.nok has_empty(T[name]), name

  R.it "writes ISO dates only", ->
    for r in *T.Exemplaires
      R.ok r.acquisition\match(ISO), "acquisition ex #{r.id}"
      R.ok r.suppression\match(ISO), "suppression ex #{r.id}" if r.suppression
    for r in *T.Emprunts
      R.ok r.emprunt\match(ISO), "emprunt #{r.id}"
      R.ok r.retour\match(ISO), "retour #{r.id}" if r.retour

  R.it "leaves one book out of four without exemplaire", ->
    counts = {}
    for e in *T.Exemplaires
      counts[e.livre] = (counts[e.livre] or 0) + 1
    n = 0
    for l in *T.Livres
      n += 1 unless counts[l.id]
    R.ok n >= 1, 'au moins un livre sans exemplaire'
    R.eq n, 15, 'livres sans exemplaire'

  R.it "leaves at least one author without book", ->
    used = {}
    for l in *T.Livres
      used[l.auteur] = true
    n = 0
    for a in *T.Auteurs
      n += 1 unless used[a.id]
    R.ok n >= 1, 'auteurs sans livre'

  R.it "has at least one author with a particule", ->
    n = 0
    for a in *T.Auteurs
      n += 1 if a.particule
    R.ok n >= 1, 'auteurs avec particule'

  R.it "marks a duplicate book (same title, same author)", ->
    seen = {}
    n_dup = 0
    for l in *T.Livres
      key = "#{l.auteur}|#{l.titre}"
      n_dup += 1 if seen[key]
      seen[key] = true
    R.ok n_dup >= 1, 'doublon présent'
    R.eq T.Livres[1].titre, T.Livres[2].titre, 'titre du couple'
    R.eq T.Livres[1].auteur, T.Livres[2].auteur, 'auteur du couple'

  R.it "links each book to two distinct keywords", ->
    per = {}
    for r in *T.LivresMotsCles
      per[r.livre] = per[r.livre] or {}
      R.nok per[r.livre][r.mot_cle], "livre #{r.livre}: mot #{r.mot_cle} en double"
      per[r.livre][r.mot_cle] = true
    for l in *T.Livres
      n = 0
      for _ in pairs (per[l.id] or {})
        n += 1
      R.eq n, 2, "livre #{l.id}: mots-clés"

  R.it "keeps one open loan per exemplaire, none on a deleted copy", ->
    n_open = check_loans T.Emprunts, T.Exemplaires, 'k=1'
    R.eq n_open, 30, 'prêts non rendus'

  R.it "borrows only from ecole.eleves", ->
    eleves = {}
    for id in *ECOLE.eleves
      eleves[id] = true
    for r in *T.Emprunts
      R.ok eleves[r.personne], "emprunt #{r.id}: personne #{r.personne}"

  R.it "is deterministic for a given seed", ->
    again = LIV.generate RNG.new(2002), 1, ECOLE
    R.eq json.encode(again), json.encode(OUT1)

  R.it "scales the catalog with k = 2", ->
    out2 = LIV.generate RNG.new(2002), 2, ECOLE
    T2 = rows_of out2
    R.eq #T2.Genres, 15, 'Genres'
    R.eq #T2.Auteurs, 50, 'Auteurs'
    R.eq #T2.MotsCles, 40, 'MotsCles'
    R.eq #T2.Livres, 120, 'Livres'
    R.eq #T2.LivresMotsCles, 240, 'LivresMotsCles'
    R.eq #T2.Exemplaires, 200, 'Exemplaires'
    R.eq #T2.Emprunts, 240, 'Emprunts'
    check_loans T2.Emprunts, T2.Exemplaires, 'k=2'
    R.nok has_empty(T2.Emprunts), 'Emprunts k=2'
    R.nok has_empty(T2.Exemplaires), 'Exemplaires k=2'
