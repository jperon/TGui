-- tests/test_data_views_relation_group.moon
-- Data Views — groupBy sur un champ Relation : l'étiquette de groupe doit être
-- la valeur brute (Int stocké, ou valeur calculée pour un champ calculé), jamais
-- le proxy FK rendu par make_self_proxy. Avant le correctif, l'étiquette était
-- une table (adresse mémoire) : une ligne par enregistrement au lieu d'un
-- groupe par valeur, et colonne inexploitable.

R          = require 'tests.runner'
json       = require 'json'
spaces_mod = require 'core.spaces'
schema_r   = require 'resolvers.schema_resolvers'
executor   = require 'core.data_views_executor'
{ :trusted_ctx } = require 'resolvers.utils'

SUFFIX = tostring math.random 100000, 999999
CLS  = "dvg_cls_#{SUFFIX}"
PERS = "dvg_pers_#{SUFFIX}"

CTX = trusted_ctx 'admin'

CLASSES = { 'CM2', '6eB', '3eA' }
PERSONS = {
  { nom: 'Ada',    classe_id: 1 }
  { nom: 'Bruno',  classe_id: 2 }
  { nom: 'Chloé',  classe_id: 2 }
  { nom: 'David',  classe_id: 3 }
}

ins = (name, id, data) ->
  box.space["data_#{name}"]\insert { id, json.encode data }

cls_sp  = spaces_mod.create_user_space CLS,  'dvg — classes (cible)'
pers_sp = spaces_mod.create_user_space PERS, 'dvg — personnes (source)'

spaces_mod.add_field cls_sp.id, 'id',  'Sequence'
spaces_mod.add_field cls_sp.id, 'nom', 'String'

spaces_mod.add_field pers_sp.id, 'nom', 'String'
-- Champ relation (Int stocké) : l'étiquette de groupe attendue est 1, 2 ou 3.
spaces_mod.add_field pers_sp.id, 'classe_id', 'Int'
-- Colonne calculée (aucune valeur stockée) : doit continuer de passer par le
-- proxy (non-régression du regroupement sur champ calculé).
spaces_mod.add_field pers_sp.id, 'initiale', 'String', false, '',
  "string.sub(self.nom or '', 1, 1)", nil, 'lua'

fields_cls  = {}
fields_pers = {}
for f in *spaces_mod.list_fields cls_sp.id
  fields_cls[f.name] = f
for f in *spaces_mod.list_fields pers_sp.id
  fields_pers[f.name] = f

for i, nom in ipairs CLASSES
  ins CLS, "cls_#{i}", { id: i, nom: nom }
for i, p in ipairs PERSONS
  ins PERS, "pers_#{i}", { nom: p.nom, classe_id: p.classe_id }

rel = schema_r.Mutation.createRelation nil, {
  input: {
    name:        'dvg_classe'
    fromSpaceId: pers_sp.id
    fromFieldId: fields_pers['classe_id'].id
    toSpaceId:   cls_sp.id
    toFieldId:   fields_cls['id'].id
    reprFormula: '@nom'
  }
}, CTX

run_view = (config) ->
  executor.execute_view pers_sp.id, json.encode(config), {}

R.describe "DataViews — groupBy sur une relation", ->

  R.it "regroupe par la valeur brute du champ relation (un groupe par valeur)", ->
    res = run_view {
      groupBy: { 'classe_id' }
      aggregates: { { fn: 'count', as: 'n' } }
      orderBy: { { field: 'classe_id' } }
    }
    R.eq #res, #CLASSES, 'un groupe par classe, pas un par enregistrement'
    by_group = {}
    for row in *res
      R.eq type(row.classe_id), 'number', "étiquette de groupe #{tostring row.classe_id} (table = proxy FK)"
      by_group[row.classe_id] = row if type(row.classe_id) == 'number'
    R.eq by_group[1] and by_group[1].n, 1, 'une personne en CM2'
    R.eq by_group[2] and by_group[2].n, 2, 'deux personnes en 6eB'
    R.eq by_group[3] and by_group[3].n, 1, 'une personne en 3eA'

  R.it "garde le regroupement sur une colonne calculée (proxy conservé)", ->
    res = run_view {
      groupBy: { 'initiale' }
      aggregates: { { fn: 'count', as: 'n' } }
    }
    R.eq #res, #PERSONS, 'une initiale distincte par personne'
    initiales = {}
    for row in *res
      R.eq type(row.initiale), 'string', "étiquette calculée #{tostring row.initiale}"
      initiales[row.initiale] = row.n
    R.eq initiales['A'], 1, 'une personne en A'
    R.eq initiales['B'], 1, 'une personne en B'

  R.it "agrège aussi une somme sur un champ relation voisin", ->
    res = run_view {
      groupBy: { 'classe_id' }
      aggregates: { { field: 'classe_id', fn: 'max', as: 'classe_max' } }
      orderBy: { { field: 'classe_id' } }
    }
    R.eq #res, #CLASSES, 'un groupe par classe'
    for row in *res
      R.eq type(row.classe_id), 'number', "étiquette #{tostring row.classe_id}"
      R.eq row.classe_max, row.classe_id, 'le max du champ relation reste son Int'

-- ── Nettoyage ────────────────────────────────────────────────────────────────

box.space._tdb_relations\delete { rel.id }
spaces_mod.delete_user_space PERS
spaces_mod.delete_user_space CLS
require('resolvers.init').reinit!
