-- tests/test_app_structure_bibliotheque.moon
-- T4 — structure « bibliothèque » du paquet Bibliothèque.
--
-- Charge uniquement structure/bibliotheque.yaml (app.yaml appartient à T3, une
-- autre tâche), construit la structure avec tools.app_builder et installe les
-- sept espaces déclarés, plus un espace Personnes minimal créé par le test
-- (cible de la clé étrangère Emprunts.personne et de space('Personnes')).
-- La FK Emprunts.personne vers Personnes est retirée de la structure avant
-- installation (l'espace Personnes n'appartient pas à cette tâche).
R = require 'tests.runner'
yaml = require 'yaml'
fio = require 'fio'
json = require 'json'
B = require 'tools.app_builder'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
triggers = require 'core.triggers'
auth = require 'core.auth'
data_r = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999
APP_ID = "org.test.biblio_#{SUFFIX}"
SP_PERS = 'Personnes'
STRUCT_PATH = '/app/backend/apps/bibliotheque/structure/bibliotheque.yaml'
OWN_SPACES = { 'Genres', 'Auteurs', 'MotsCles', 'Livres', 'LivresMotsCles',
  'Exemplaires', 'Emprunts' }

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

FIX = {}
PKG = nil

read_yaml = (path) ->
  fh = fio.open path, { 'O_RDONLY' }
  error "cannot open #{path}" unless fh
  text = fh\read!
  fh\close!
  yaml.decode text

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

row = (space_name, field, value) ->
  items = records space_name
  for it in *items
    return it.proxy if it.raw[field] == value
  nil

check_formulas = ->
  for n in *OWN_SPACES
    sp = spaces.get_space_by_name n
    continue unless sp
    for f in *spaces.list_fields sp.id
      continue unless f.formula != ''
      fn = triggers.compile_formula f.formula, "#{n}.#{f.name}", f.language
      R.ok (type(fn) == 'function'), "formule non compilable #{n}.#{f.name}"

-- Réchauffe les cartes de relations HORS de tout garde d'instructions (même
-- mesure que T3 : build_fk_def_map coûte plusieurs millions d'instructions,
-- ce qui ferait échouer une formule qui le construirait dans son propre garde).
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

R.describe "app structure — bibliotheque", ->

  R.it "installs the seven library spaces", ->
    part = read_yaml STRUCT_PATH
    wanted = {}
    wanted[n] = true for n in *OWN_SPACES
    declared = {}
    declared[sp.name] = true for sp in *part.spaces
    for n in *OWN_SPACES
      R.ok declared[n], "declares #{n}"
    -- Le conteneur de test démarre avec les espaces de démonstration de
    -- fixtures.moon (Auteurs, Livres, Emprunts). Le spec a tranché que le paquet
    -- s'installe dans une base vide dédiée, sans renommage : on retire ici les
    -- espaces de démonstration homonymes dont aucun test de la suite ne dépend.
    for n in *OWN_SPACES
      if spaces.get_space_by_name n
        drop_relations n
        spaces.delete_user_space n
    pers = spaces.create_user_space SP_PERS, 'T4 minimal persons'
    spaces.add_field pers.id, 'id', 'Sequence', true, 'Identifiant'
    spaces.add_field pers.id, 'nom', 'String', false, ''
    spaces.add_field pers.id, 'prenom', 'String', false, ''
    -- Retire les FK vers des espaces absents de cette tâche (Emprunts.personne).
    for sp in *part.spaces
      for f in *(sp.fields or {})
        if f.ref
          target = f.ref\match '^([^.]+)'
          f.ref = nil unless wanted[target]
    structure = {
      app: { id: APP_ID, name: "Biblio test #{SUFFIX}", version: '1.0.0', description: 'T4' }
      spaces: part.spaces
    }
    PKG = B.expand structure
    report = apply.apply_update PKG, {}, {}
    R.ok report.ok, "apply_update: #{report.error}"
    R.is_nil report.reinit_error, 'reinit_schema'
    for n in *OWN_SPACES
      R.ok spaces.get_space_by_name(n), "espace non installé: #{n}"

  R.it "compiles every formula", ->
    check_formulas!

  R.it "inserts the library fixture rows", ->
    FIX.fiction = insert_row 'Genres', { genre: 'Fiction' }
    FIX.roman = insert_row 'Genres', { genre: 'Roman', parent: FIX.fiction }
    FIX.policier = insert_row 'Genres', { genre: 'Policier', parent: FIX.roman }
    FIX.lafontaine = insert_row 'Auteurs', {
      nom: 'La Fontaine', particule: 'de', prenom: 'Jean' }
    FIX.sans_livre = insert_row 'Auteurs', { nom: 'Solitaire', prenom: 'Anne' }
    FIX.livre1 = insert_row 'Livres', {
      titre: 'Fables', auteur: FIX.lafontaine, genre: FIX.policier }
    FIX.ex1 = insert_row 'Exemplaires', { livre: FIX.livre1, cote: 'A1' }
    FIX.ex_sup = insert_row 'Exemplaires', {
      livre: FIX.livre1, cote: 'A2', suppression: '2026-01-01' }
    FIX.livre2 = insert_row 'Livres', {
      titre: 'Fables', auteur: FIX.lafontaine, genre: FIX.policier }
    FIX.livre3 = insert_row 'Livres', {
      titre: 'Contes', auteur: FIX.lafontaine, genre: FIX.roman }
    FIX.luc = insert_row SP_PERS, { nom: 'Martin', prenom: 'Luc' }
    FIX.ex_a = insert_row 'Exemplaires', { livre: FIX.livre3, cote: 'B1' }
    FIX.ex_b = insert_row 'Exemplaires', { livre: FIX.livre3, cote: 'B2' }
    FIX.emp_a = insert_row 'Emprunts', {
      personne: FIX.luc, exemplaire: FIX.ex_a, emprunt: '2026-09-20' }
    FIX.emp_b = insert_row 'Emprunts', {
      personne: FIX.luc, exemplaire: FIX.ex_b, emprunt: '2025-10-01',
      retour: '2025-10-10' }
    R.ok FIX.emp_a and FIX.emp_b, 'emprunts insérés'

  R.it "warms the FK metadata caches", ->
    touched = 0
    for n in *OWN_SPACES
      touched += warm_fk n, 3
    R.ok touched > 0, 'aucun champ de clé étrangère résolu'

  R.it "computes the genre hierarchy (niveau, chemin)", ->
    p = row 'Genres', 'id', FIX.policier
    R.ok p, 'Policier'
    R.eq p.niveau, 3, 'Genres.niveau de Policier'
    R.eq p.chemin, 'Fiction › Roman › Policier', 'Genres.chemin de Policier'
    f = row 'Genres', 'id', FIX.fiction
    R.ok f, 'Fiction'
    R.eq f.niveau, 1, 'Genres.niveau de Fiction (racine)'
    R.eq f.chemin, 'Fiction', 'Genres.chemin de Fiction (racine)'

  R.it "computes the author fields (nom_complet, n_ouvrages)", ->
    lf = row 'Auteurs', 'id', FIX.lafontaine
    R.ok lf, 'La Fontaine'
    R.eq lf.nom_complet, 'Jean de La Fontaine', 'Auteurs.nom_complet'
    R.eq lf.n_ouvrages, 3, 'Auteurs.n_ouvrages de La Fontaine'
    sl = row 'Auteurs', 'id', FIX.sans_livre
    R.ok sl, 'auteur sans livre'
    R.eq sl.n_ouvrages, 0, 'Auteurs.n_ouvrages sans livre'

  R.it "counts exemplaires excluding suppressed ones", ->
    l1 = row 'Livres', 'id', FIX.livre1
    R.ok l1, 'livre 1'
    R.eq l1.n_exemplaires, 1, 'n_exemplaires (A1 seul non supprimé)'
    l2 = row 'Livres', 'id', FIX.livre2
    R.ok l2, 'livre 2 sans exemplaire'
    R.eq l2.n_exemplaires, 0, 'n_exemplaires d\'un livre sans exemplaire'

  R.it "detects duplicate (same title and author)", ->
    l1 = row 'Livres', 'id', FIX.livre1
    l2 = row 'Livres', 'id', FIX.livre2
    R.eq l1.doublon, true, 'livre 1 doublon'
    R.eq l2.doublon, true, 'livre 2 doublon'
    R.eq l1.descriptif, 'Fables (Jean de La Fontaine)', 'Livres.descriptif'

  R.it "resolves the current borrower of an open loan (emprunteur)", ->
    ex_a = row 'Exemplaires', 'id', FIX.ex_a
    ex_b = row 'Exemplaires', 'id', FIX.ex_b
    R.ok ex_a and ex_b, 'exemplaires A et B'
    R.eq ex_a.emprunteur, 'Martin Luc', 'emprunteur du prêt non rendu'
    R.is_nil ex_b.emprunteur, 'emprunteur vide si le prêt est rendu'

  R.it "cleans up", ->
    clean_app_rows APP_ID
    for n in *OWN_SPACES
      drop_relations n
      spaces.delete_user_space n
    drop_relations SP_PERS
    spaces.delete_user_space SP_PERS
    for n in *OWN_SPACES
      R.is_nil spaces.get_space_by_name(n), "#{n} removed"
    R.is_nil spaces.get_space_by_name SP_PERS
