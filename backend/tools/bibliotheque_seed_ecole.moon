-- tools/bibliotheque_seed_ecole.moon
-- T6 — Données fictives « école » du paquet Bibliothèque.
--
-- Interface : generate(rng, k) -> out
--   out.tables    : liste ordonnée de { space, rows } — Titres, Sections,
--                   Annee, Niveaux, Personnes, Prefectures, Classes,
--                   ClassesEleves
--   out.eleves    : ids (Personnes.id) des élèves
--   out.adultes   : ids (Personnes.id) des adultes — 1..12
--   out.personnes : tous les ids Personnes
--
-- Conventions : id entier explicite par ligne (1, 2, 3…), champs vides omis,
-- dates en chaînes ISO YYYY-MM-DD, clés étrangères = id de la table cible.
-- Aucune donnée personnelle réelle : prénoms et noms inventés.

PRENOMS_M = {
  'Antoine', 'Bastien', 'Cédric', 'Damien', 'Émile', 'Florian'
  'Gaël', 'Hugo', 'Isidore', 'Jérôme', 'Kilian', 'Loïc'
  'Marcel', 'Nathan', 'Oscar', 'Patrice', 'Quentin', 'Raphaël'
}

PRENOMS_F = {
  'Adèle', 'Béatrice', 'Clémence', 'Delphine', 'Éloïse', 'Flore'
  'Garance', 'Hélène', 'Inès', 'Joséphine', 'Karine', 'Lucie'
  'Marion', 'Noémie', 'Océane', 'Priscille', 'Rosalie', 'Solène'
}

NOMS = {
  'Aubert', 'Bélanger', 'Chevrier', 'Dauvers', 'Émery', 'Fauvel'
  'Grangier', 'Hurtaud', 'Imbert', 'Jourdan', 'Lambert', 'Montel'
  'Noizet', 'Perrin', 'Rouvier', 'Seguin', 'Tardif', 'Vasseur'
}

-- Les 12 adultes (ids 1..12) : 5 professeurs principaux, 2 préfets, 5 parents.
PROF_IDS = { 1, 2, 3, 4, 5 }
PREFET_IDS = { 6, 7 }
PARENT_IDS = { 8, 9, 10, 11, 12 }

NIVEAUX_NOMS = {
  { abrege: 'CP', classe: 'Cours préparatoire' }
  { abrege: 'CE1', classe: 'Cours élémentaire 1' }
  { abrege: 'CE2', classe: 'Cours élémentaire 2' }
  { abrege: 'CM1', classe: 'Cours moyen 1' }
  { abrege: 'CM2', classe: 'Cours moyen 2' }
}

-- Titre d'adulte : id 3 = Frère (homme), id 4 = Sœur (femme), sinon M./Mme.
_adulte_titre = (rng, i) ->
  return 3 if i == 3
  return 4 if i == 4
  rng.chance(0.5) and 1 or 2

_gen_titres = ->
  {
    { id: 1, titre: 'M.', abrege: 'M.', femme: false }
    { id: 2, titre: 'Mme', abrege: 'Mme', femme: true }
    { id: 3, titre: 'Frère', abrege: 'Fr.', femme: false }
    { id: 4, titre: 'Sœur', abrege: 'S.', femme: true }
  }

_gen_sections = ->
  {
    { id: 1, section: 'Générale', abregee: 'GEN' }
    { id: 2, section: 'Bilingue', abregee: 'BIL' }
  }

_gen_annee = ->
  {
    { id: 1, debut: '2024-09-01', fin: '2025-06-30', en_cours: false, section: 1 }
    { id: 2, debut: '2025-09-01', fin: '2026-06-30', en_cours: false, section: 1 }
    { id: 3, debut: '2026-09-01', fin: '2027-06-30', en_cours: true, section: 1 }
  }

_gen_niveaux = ->
  rows = {}
  for i = 1, 5
    n = NIVEAUX_NOMS[i]
    row = { id: i, niveau: i, classe: n.classe, abrege: n.abrege, generique: 'Primaire' }
    row.superieur = i + 1 if i < 5
    table.insert rows, row
  rows

_gen_adultes = (rng) ->
  rows = {}
  for i = 1, 12
    titre = _adulte_titre rng, i
    male = titre == 1 or titre == 3
    annee = 1970 + 2 * i
    row = {
      id: i
      nom: rng.pick NOMS
      prenom: male and rng.pick(PRENOMS_M) or rng.pick(PRENOMS_F)
      titre: titre
      date_de_naissance: "#{annee}-05-20"
    }
    row.particule = 'de' if rng.chance 0.25
    table.insert rows, row
  rows

_eleve_row = (rng, id, niveau) ->
  male = rng.chance 0.5
  annee = 2021 - niveau
  {
    id: id
    niveau: niveau
    nom: rng.pick NOMS
    prenom: male and rng.pick(PRENOMS_M) or rng.pick(PRENOMS_F)
    date_de_naissance: "#{annee}-09-01"
    famille: rng.pick PARENT_IDS
  }

-- 60 * k élèves : 12 par niveau, rangs de niveau 1 à 5, ids à partir de 13.
_gen_eleves = (rng, k) ->
  students = {}
  id = 12
  for niveau = 1, 5
    for _n = 1, 12 * k
      id += 1
      table.insert students, _eleve_row(rng, id, niveau)
  students

-- Les lignes Personnes = les 12 adultes puis les élèves (sans `niveau` :
-- ce champ n'existe pas dans l'espace Personnes).
_personnes_rows = (adultes, students) ->
  rows = {}
  table.insert rows, r for r in *adultes
  for s in *students
    table.insert rows, {
      id: s.id
      nom: s.nom
      prenom: s.prenom
      date_de_naissance: s.date_de_naissance
      famille: s.famille
    }
  rows

-- Une préfecture par année : son id est celui de l'année.
_gen_prefectures = (rng) ->
  rows = {}
  for annee_id = 1, 3
    table.insert rows, {
      id: annee_id
      nom: 'Préfecture'
      annee: annee_id
      prefet: rng.pick PREFET_IDS
      niveau_min: 1
      niveau_max: 5
    }
  rows

_classe_row = (rng, id, niveau, annee_id) ->
  {
    id: id
    niveau: niveau
    annee: annee_id
    prefecture: annee_id
    professeur_principal: rng.pick PROF_IDS
  }

-- Classes 1..5 = année 2 (niveaux 1..5), classes 6..10 = année 3.
_gen_classes = (rng) ->
  rows = {}
  for annee_id = 2, 3
    for niveau = 1, 5
      id = (annee_id - 2) * 5 + niveau
      table.insert rows, _classe_row(rng, id, niveau, annee_id)
  rows

-- Une ligne par élève en année 3 (sans départ) ; en année 2, une ligne pour
-- les élèves de niveau ≥ 2, placés dans la classe de niveau − 1.
_classes_eleves_rows = (students) ->
  rows = {}
  id = 0
  for s in *students
    id += 1
    table.insert rows, {
      id: id
      classe: 5 + s.niveau
      eleve: s.id
      entree: '2026-09-01'
    }
    if s.niveau >= 2
      id += 1
      table.insert rows, {
        id: id
        classe: s.niveau - 1
        eleve: s.id
        entree: '2025-09-01'
        depart: '2026-06-30'
        redoublement: false
      }
  rows

generate = (rng, k) ->
  adultes_rows = _gen_adultes rng
  students = _gen_eleves rng, k
  tables = {}
  add = (space, rows) -> table.insert tables, { space: space, rows: rows }
  add 'Titres', _gen_titres!
  add 'Sections', _gen_sections!
  add 'Annee', _gen_annee!
  add 'Niveaux', _gen_niveaux!
  add 'Personnes', _personnes_rows(adultes_rows, students)
  add 'Prefectures', _gen_prefectures rng
  add 'Classes', _gen_classes rng
  add 'ClassesEleves', _classes_eleves_rows students
  adultes = [r.id for r in *adultes_rows]
  eleves = [s.id for s in *students]
  personnes = {}
  table.insert personnes, id for id in *adultes
  table.insert personnes, id for id in *eleves
  {
    tables: tables
    eleves: eleves
    adultes: adultes
    personnes: personnes
  }

{ :generate }
