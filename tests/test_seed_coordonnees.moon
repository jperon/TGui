-- tests/test_seed_coordonnees.moon
-- T8 — données fictives : coordonnées. Déterminisme, volumes exacts, intégrité
-- des clés étrangères, coordonnée partagée, valeurs fictives.
R = require 'tests.runner'
json = require 'json'
COORD = require 'tools.bibliotheque_seed_coordonnees'
RNG = require 'tools.seed_rng'

-- École factice : 72 personnes (ids 1..72).
P = {}
for i = 1, 72
  table.insert P, i
ECOLE = { personnes: P }

LIBELLES_OK = { domicile: true, parents: true, travail: true }

by_space = (out) ->
  m = {}
  m[t.space] = t.rows for t in *out.tables
  m

-- Adresse inventée : numéro (1..150), voie, nom de rue, aucun code postal.
is_address = (v) ->
  return false unless type(v) == 'string'
  return false unless v\match '^%d+ %a+ des '
  n = tonumber(v\match '^(%d+)')
  return false unless n and n >= 1 and n <= 150
  not v\match '%d%d%d%d%d'

R.describe "bibliotheque_seed_coordonnees", ->
  out = COORD.generate(RNG.new(3003), 1, ECOLE)
  T = by_space out
  types = T.TypesCoordonnees
  coords = T.Coordonnees
  links = T.PersonnesCoordonnees

  R.it "returns the three tables in order", ->
    R.eq #out.tables, 3, 'tables'
    R.eq out.tables[1].space, 'TypesCoordonnees'
    R.eq out.tables[2].space, 'Coordonnees'
    R.eq out.tables[3].space, 'PersonnesCoordonnees'

  R.it "is deterministic for a given seed", ->
    again = COORD.generate(RNG.new(3003), 1, ECOLE)
    R.eq json.encode(again), json.encode(out)

  R.it "has the exact volumes at k = 1", ->
    R.eq #types, 3, 'TypesCoordonnees'
    R.eq #coords, 30, 'Coordonnees'
    R.eq #links, 50, 'PersonnesCoordonnees'

  R.it "scales with k", ->
    big = by_space(COORD.generate(RNG.new(3003), 2, ECOLE))
    R.eq #big.Coordonnees, 60, 'Coordonnees k=2'
    R.eq #big.PersonnesCoordonnees, 100, 'PersonnesCoordonnees k=2'

  R.it "defines tel, courriel and adresse", ->
    R.eq types[1].id, 1, 'id tel'
    R.eq types[1].type, 'tel'
    R.eq types[2].id, 2, 'id courriel'
    R.eq types[2].type, 'courriel'
    R.eq types[3].id, 3, 'id adresse'
    R.eq types[3].type, 'adresse'

  R.it "uses explicit sequential ids", ->
    bad = 0
    for i = 1, #types
      bad += 1 if types[i].id != i
    for i = 1, #coords
      bad += 1 if coords[i].id != i
    for i = 1, #links
      bad += 1 if links[i].id != i
    R.eq bad, 0, 'ids'

  R.it "points every foreign key at an existing row", ->
    type_ids, coord_ids, person_ids = {}, {}, {}
    for t in *types
      type_ids[t.id] = true
    for c in *coords
      coord_ids[c.id] = true
    for p in *P
      person_ids[p] = true
    bad_type, bad_coord, bad_person = 0, 0, 0
    for row in *coords
      bad_type += 1 unless type_ids[row.type_coordonnee]
    for row in *links
      bad_person += 1 unless person_ids[row.personne]
      bad_coord += 1 unless coord_ids[row.coordonnee]
    R.eq bad_type, 0, 'type_coordonnee'
    R.eq bad_person, 0, 'personne'
    R.eq bad_coord, 0, 'coordonnee'

  R.it "spreads coordinates over the three types", ->
    used = {}
    for row in *coords
      used[row.type_coordonnee] = (used[row.type_coordonnee] or 0) + 1
    R.eq (used[1] or 0) + (used[2] or 0) + (used[3] or 0), 30, 'total'
    R.ok (used[1] or 0) > 0 and (used[2] or 0) > 0 and (used[3] or 0) > 0, 'types utilisés'

  R.it "links distinct couples and shares at least one coordinate", ->
    seen, counts, dup = {}, {}, 0
    for row in *links
      key = "#{row.personne}|#{row.coordonnee}"
      dup += 1 if seen[key]
      seen[key] = true
      counts[row.coordonnee] = (counts[row.coordonnee] or 0) + 1
    R.eq dup, 0, 'couples distincts'
    shared = 0
    for _, n in pairs counts
      shared += 1 if n >= 2
    R.ok shared >= 1, 'coordonnée partagée'

  R.it "labels links with domicile, parents or travail", ->
    bad = 0
    for row in *links
      bad += 1 unless LIBELLES_OK[row.libelle]
    R.eq bad, 0, 'libelle'

  R.it "uses fictitious values (.invalid emails, reserved phone prefix, invented streets)", ->
    bad_tel, bad_mail, bad_addr = 0, 0, 0
    for row in *coords
      v = row.valeur
      if row.type_coordonnee == 1
        bad_tel += 1 unless v\match '^06 00 00 %d%d %d%d$'
      elseif row.type_coordonnee == 2
        bad_mail += 1 unless v\match '^[%w%.]+@exemple%.invalid$'
      elseif row.type_coordonnee == 3
        bad_addr += 1 unless is_address v
    R.eq bad_tel, 0, 'numéros fictifs'
    R.eq bad_mail, 0, 'courriels .invalid'
    R.eq bad_addr, 0, 'adresses inventées'

  R.it "stores no empty value", ->
    bad = 0
    for rows in *{ types, coords, links }
      for row in *rows
        for _, v in pairs row
          bad += 1 if v == nil or v == ''
    R.eq bad, 0, 'valeurs vides'
