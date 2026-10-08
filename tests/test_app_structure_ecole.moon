-- tests/test_app_structure_ecole.moon
-- T3 — structure « école » de l'application Bibliothèque.
-- Charge backend/apps/bibliotheque (app.yaml + structure/ecole.yaml) via
-- tools.app_builder, installe les huit espaces, insère un jeu de lignes via
-- data_r.Mutation.insertRecord et lit les champs calculés via
-- data_r.Query.records : l'item retenu porte un proxy dont l'accès aux champs
-- évalue la formule à la lecture (core.formula_proxy.eval_computed_formula).
R = require 'tests.runner'
B = require 'tools.app_builder'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
triggers = require 'core.triggers'
auth = require 'core.auth'
data_r = require 'resolvers.data_resolvers'
json = require 'json'

SUFFIX = tostring math.random 100000, 999999
APP_ID = "org.test.ecole_#{SUFFIX}"
DIR = '/app/backend/apps/bibliotheque'
ECOLE = { 'Titres', 'Sections', 'Annee', 'Niveaux', 'Prefectures', 'Classes', 'Personnes', 'ClassesEleves' }

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

FIX = {}
PKG = nil

wanted = {}
wanted[n] = true for n in *ECOLE

clean_app_rows = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

drop_relations = (name) ->
  sp = spaces.get_space_by_name name
  return unless sp
  for t in *box.space._tdb_relations.index.by_from\select { sp.id }
    box.space._tdb_relations\delete t[1]
  for t in *box.space._tdb_relations.index.by_to\select { sp.id }
    box.space._tdb_relations\delete t[1]

insert_row = (space_name, data) ->
  sp = spaces.get_space_by_name space_name
  r = data_r.Mutation.insertRecord {}, { spaceId: sp.id, data: data }, CTX
  json.decode(r.data).id

records = (space_name) ->
  sp = spaces.get_space_by_name space_name
  return {} unless sp
  res = data_r.Query.records nil, { spaceId: sp.id, limit: 1000 }, CTX
  res.items

-- Retourne le proxy de la ligne dont le champ stocké `field` vaut `value` :
-- l'accès aux champs calculés sur ce proxy évalue leur formule.
row = (space_name, field, value) ->
  items = records space_name
  for it in *items
    return it.proxy if it.raw[field] == value
  nil

check_formulas = ->
  for n in *ECOLE
    sp = spaces.get_space_by_name n
    continue unless sp
    for f in *spaces.list_fields sp.id
      continue unless f.formula != ''
      fn = triggers.compile_formula f.formula, "#{n}.#{f.name}", f.language
      R.ok (type(fn) == 'function'), "formule non compilable #{n}.#{f.name}"

-- Réchauffe les cartes de relations (core.relation_maps.build_fk_def_map) en
-- touchant les champs de clé étrangère HORS de tout garde d'instructions.
-- Mesuré le 2026-10-08 (instance de test) : build_fk_def_map coûte 1 628 hooks
-- d'instructions (≈16 M) avec 3 relations et 4 598 (≈46 M) avec 20, alors que
-- core.config.safe_formula_call n'autorise que 20 M instructions par formule.
-- Construite à l'intérieur d'une formule, la carte fait donc échouer la lecture
-- avec « instruction limit exceeded ». Cette passe hors garde remplit
-- ctx._fk_cache.fk_def_maps, que Query.records réutilise pour tous les items.
warm_fk = (space_name, depth) ->
  return 0 if depth < 0
  sp = spaces.get_space_by_name space_name
  return 0 unless sp
  fk_map = triggers.build_fk_def_map sp.id
  res = data_r.Query.records nil, { spaceId: sp.id, limit: 1000 }, CTX
  touched = 0
  for it in *res.items
    for name, def in pairs fk_map
      v = it.proxy[name]
      if type(v) == 'table'
        touched += 1
        touched += warm_fk def.toSpaceName, depth - 1
  touched

R.describe "app structure — ecole", ->

  R.it "installs the eight school spaces", ->
    structure = B.load_structure DIR
    loaded = {}
    loaded[s.name] = true for s in *structure.spaces
    for n in *ECOLE
      R.ok loaded[n], "espace absent de backend/apps/bibliotheque: #{n}"
    structure.spaces = [s for s in *structure.spaces when wanted[s.name]]
    structure.app.id = APP_ID
    structure.app.name = "Ecole test #{SUFFIX}"
    PKG = B.expand structure
    report = apply.apply_update PKG, {}, {}
    R.ok report.ok, "apply_update: #{report.error}"
    R.is_nil report.reinit_error, 'reinit_schema'
    for n in *ECOLE
      R.ok spaces.get_space_by_name(n), "espace non installé: #{n}"

  R.it "compiles every formula", ->
    check_formulas!

  R.it "inserts the school fixture rows", ->
    FIX.sec = insert_row 'Sections', { section: 'Primaire', abregee: 'PRIM' }
    FIX.an1 = insert_row 'Annee', {
      debut: '2025-09-01', fin: '2026-06-30', en_cours: false, section: FIX.sec }
    FIX.an2 = insert_row 'Annee', {
      debut: '2026-09-01', fin: '2027-06-30', en_cours: true, section: FIX.sec }
    FIX.niv = insert_row 'Niveaux', { niveau: 1, classe: 'CP', abrege: 'CP', generique: 'CP' }
    FIX.cl1 = insert_row 'Classes', { niveau: FIX.niv, annee: FIX.an1 }
    FIX.cl2 = insert_row 'Classes', { niveau: FIX.niv, annee: FIX.an2 }
    FIX.jeanne = insert_row 'Personnes', { nom: 'Dupont', particule: 'de', prenom: 'Jeanne' }
    FIX.luc = insert_row 'Personnes', { nom: 'Martin', prenom: 'Luc' }
    FIX.ce_j = insert_row 'ClassesEleves', {
      classe: FIX.cl2, eleve: FIX.jeanne, entree: '2026-09-01' }
    FIX.ce_l = insert_row 'ClassesEleves', {
      classe: FIX.cl1, eleve: FIX.luc, entree: '2025-09-01',
      depart: '2026-06-30', redoublement: false }
    R.ok FIX.ce_l, 'ClassesEleves de Luc'

  R.it "warms the FK metadata caches", ->
    touched = 0
    for n in *ECOLE
      touched += warm_fk n, 3
    R.ok touched > 0, 'aucun champ de clé étrangère résolu'

  R.it "computes the formula columns", ->
    an2 = row 'Annee', 'id', FIX.an2
    R.ok an2, 'Annee 2'
    R.eq an2.annee, '2026 - 2027', 'Annee.annee'
    niv = row 'Niveaux', 'id', FIX.niv
    R.ok niv, 'Niveaux 1'
    R.eq niv.descriptif, '01 − CP', 'Niveaux.descriptif'
    j = row 'Personnes', 'id', FIX.jeanne
    R.ok j, 'Jeanne'
    R.eq j.descriptif, 'DUPONT (de) Jeanne', 'Personnes.descriptif de Jeanne'
    R.eq j.classe_actuelle, FIX.cl2, 'classe_actuelle de Jeanne'
    R.eq j.emprunts_en_cours, 0, 'emprunts_en_cours de Jeanne'
    l = row 'Personnes', 'id', FIX.luc
    R.ok l, 'Luc'
    R.is_nil l.classe_actuelle, 'classe_actuelle de Luc'
    R.eq l.emprunts_en_cours, 0, 'emprunts_en_cours de Luc'
    c1 = row 'Classes', 'id', FIX.cl1
    c2 = row 'Classes', 'id', FIX.cl2
    R.ok c1 and c2, 'classes'
    R.eq c1.descriptif, 'CP', 'Classes.descriptif'
    R.eq c2.effectif, 1, 'effectif de la classe 2'
    R.eq c1.effectif, 0, 'effectif de la classe 1'
    ce_j = row 'ClassesEleves', 'id', FIX.ce_j
    ce_l = row 'ClassesEleves', 'id', FIX.ce_l
    R.ok ce_j and ce_l, 'liaisons ClassesEleves'
    R.eq ce_j.annee, FIX.an2, 'ClassesEleves.annee de Jeanne'
    R.eq ce_j.annee_en_cours, true, 'annee_en_cours de Jeanne'
    R.eq ce_l.annee_en_cours, false, 'annee_en_cours de Luc'

  R.it "cleans up", ->
    clean_app_rows APP_ID
    for n in *ECOLE
      drop_relations n
      spaces.delete_user_space n
    R.is_nil spaces.get_space_by_name 'Personnes'
