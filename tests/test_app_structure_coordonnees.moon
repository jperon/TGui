-- tests/test_app_structure_coordonnees.moon
-- T5 — structure « coordonnées » du paquet Bibliothèque.
--
-- Charge uniquement structure/coordonnees.yaml (app.yaml appartient à T3, une
-- autre tâche), agrandit la structure avec tools.app_builder et installe les
-- trois espaces déclarés, plus un espace Personnes minimal créé par le test
-- (cible de la clé étrangère PersonnesCoordonnees.personne).

R = require 'tests.runner'
yaml = require 'yaml'
fio = require 'fio'
json = require 'json'
B = require 'tools.app_builder'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
auth = require 'core.auth'
data_r = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999
APP_ID = "org.test.coordonnees_#{SUFFIX}"
-- Cible littérale du ref Personnes.id déclaré dans coordonnees.yaml.
SP_PERS = 'Personnes'
STRUCT_PATH = '/app/backend/apps/bibliotheque/structure/coordonnees.yaml'
OWN_SPACES = { 'TypesCoordonnees', 'Coordonnees', 'PersonnesCoordonnees' }

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

read_yaml = (path) ->
  fh = fio.open path, { 'O_RDONLY' }
  error "cannot open #{path}" unless fh
  text = fh\read!
  fh\close!
  yaml.decode text

space_id = (name) ->
  sp = spaces.get_space_by_name name
  error "space missing: #{name}" unless sp
  sp.id

rows_of = (name) ->
  out = {}
  res = data_r.Query.records nil, { spaceId: space_id(name) }, CTX
  for it in *res.items
    table.insert out, json.decode(it.data)
  out

insert_into = (name, data) ->
  data_r.Mutation.insertRecord {}, { spaceId: space_id(name), data: data }, CTX

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

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_structure_coordonnees — install", ->

  R.it "installs the three spaces declared in structure/coordonnees.yaml", ->
    part = read_yaml STRUCT_PATH
    declared = {}
    declared[sp.name] = true for sp in *part.spaces
    R.eq #part.spaces, 3, 'declared spaces'
    for n in *OWN_SPACES
      R.ok declared[n], "declares #{n}"
    pers = spaces.create_user_space SP_PERS, 'T5 minimal persons'
    spaces.add_field pers.id, 'id', 'Sequence', true, 'Identifiant'
    spaces.add_field pers.id, 'nom', 'String', false, ''
    spaces.add_field pers.id, 'prenom', 'String', false, ''
    structure = {
      app: { id: APP_ID, name: 'Coordonnees T5', version: '1.0.0', description: 'T5' }
      spaces: part.spaces
    }
    pkg = B.expand structure
    report = apply.apply_update pkg, {}, {}
    R.ok report.ok, report.error
    for n in *OWN_SPACES
      R.ok spaces.get_space_by_name(n), "#{n} installed"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_structure_coordonnees — data", ->

  R.it "inserts the three contact types", ->
    for t in *{ 'tel', 'courriel', 'adresse' }
      insert_into 'TypesCoordonnees', { type: t }
    R.eq #rows_of('TypesCoordonnees'), 3, 'types'

  R.it "inserts one coordonnée whose type_coordonnee points at an existing type", ->
    types = rows_of 'TypesCoordonnees'
    insert_into 'Coordonnees', { type_coordonnee: types[1].id, valeur: '06 00 00 12 34' }
    coords = rows_of 'Coordonnees'
    R.eq #coords, 1, 'coordonnées'
    known = {}
    known[t.id] = true for t in *types
    R.ok known[coords[1].type_coordonnee], 'type_coordonnee points at an installed type'

  R.it "links two people to the same coordonnée (N-N)", ->
    p1 = insert_into SP_PERS, { nom: 'Martin', prenom: 'Luc' }
    p2 = insert_into SP_PERS, { nom: 'Dupont', prenom: 'Jeanne' }
    coord_id = rows_of('Coordonnees')[1].id
    for pid in *{ json.decode(p1.data).id, json.decode(p2.data).id }
      insert_into 'PersonnesCoordonnees', {
        personne: pid, coordonnee: coord_id, libelle: 'domicile'
      }
    links = rows_of 'PersonnesCoordonnees'
    R.eq #links, 2, 'liaisons N-N'
    R.eq links[1].coordonnee, coord_id, 'first link shares the coordonnée'
    R.eq links[2].coordonnee, coord_id, 'second link shares the coordonnée'
    R.ne links[1].personne, links[2].personne, 'two distinct personnes'

  R.it "refuses a Coordonnée without valeur (notNull)", ->
    R.raises (-> insert_into 'Coordonnees', { type_coordonnee: 1 }), 'not_null', 'valeur required'
    R.eq #rows_of('Coordonnees'), 1, 'no row written'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_structure_coordonnees — cleanup", ->

  R.it "removes the spaces, relations and tracking rows", ->
    clean_app_rows APP_ID
    for n in *OWN_SPACES
      drop_relations n
      spaces.delete_user_space n
    drop_relations SP_PERS
    spaces.delete_user_space SP_PERS
    for n in *OWN_SPACES
      R.is_nil spaces.get_space_by_name(n), "#{n} removed"
    R.is_nil spaces.get_space_by_name SP_PERS
    R.is_nil box.space._tdb_apps\get APP_ID
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_ID }), 0, 'tracking rows'
