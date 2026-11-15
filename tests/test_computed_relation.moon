-- tests/test_computed_relation.moon
-- Relation dont le champ source est CALCULÉ (formule de lecture, pas de valeur
-- stockée) : la valeur Int doit être calculée à la lecture, puis résolue comme
-- une relation ordinaire.
--
-- Cas reproduit : `classes` (Sequence id + nom) et `pers` dont le champ
-- `classe_actuelle` (Int calculé) vaut `self.classe_id`. Une relation déclare
-- `pers.classe_actuelle -> classes.id`. Effets attendus :
--   (a) requête dynamique `pers { items { classe_actuelle { nom } } }` ;
--   (b) navigation `@classe_actuelle.nom` dans une formule de filtre ;
--   (c) relation inverse depuis la cible (`classes { ct_classe { items } }`) ;
--   (d) valeur brute (Int) sans sous-sélection — chemin grille — et
--       non-régression d'une relation NON calculée du même espace ;
--   (e) navigation `@classe_actuelle.nom` dans une autre colonne calculée et
--       disponibilité de la valeur calculée dans Query.records.

R          = require 'tests.runner'
json       = require 'json'
spaces_mod = require 'core.spaces'
schema_r   = require 'resolvers.schema_resolvers'
executor   = require 'graphql.executor'
dynamic    = require 'graphql.dynamic'
data_r     = require 'resolvers.data_resolvers'
{ :trusted_ctx } = require 'resolvers.utils'

SUFFIX = tostring math.random 100000, 999999
CLS    = "crel_cls_#{SUFFIX}"
PERS   = "crel_pers_#{SUFFIX}"

CTX = trusted_ctx 'test-user'

CLASSES   = { 'CM2', '6eB', '3eA' }
PERSONS   = {
  { nom: 'Ada',   classe_id: 1 }
  { nom: 'Bruno', classe_id: 2 }
  { nom: 'Chloé', classe_id: 3 }
  { nom: 'David', classe_id: 2 }
}

ins = (name, id, data) ->
  box.space["data_#{name}"]\insert { id, json.encode data }

-- ── Fixture ──────────────────────────────────────────────────────────────────

cls_sp  = spaces_mod.create_user_space CLS,  'crel — classes (cible)'
pers_sp = spaces_mod.create_user_space PERS, 'crel — personnes (source)'

spaces_mod.add_field cls_sp.id, 'id',  'Sequence'
spaces_mod.add_field cls_sp.id, 'nom', 'String'

spaces_mod.add_field pers_sp.id, 'nom', 'String'
-- Champ Int qui porte la valeur stockée, lue par la formule de relation.
spaces_mod.add_field pers_sp.id, 'classe_id', 'Int'
-- Champ RELATION calculé : formule de lecture, aucune valeur stockée.
spaces_mod.add_field pers_sp.id, 'classe_actuelle', 'Int', false, '',
  'self.classe_id', nil, 'moonscript'
-- Relation NON calculée de contrôle (valeur stockée).
spaces_mod.add_field pers_sp.id, 'classe_fixe', 'Int'
-- Colonne calculée qui navigue la relation calculée (@classe_actuelle.nom).
spaces_mod.add_field pers_sp.id, 'classe_nom', 'String', false, '',
  '(@classe_actuelle and @classe_actuelle.nom) or ""', nil, 'moonscript'

fields_cls  = {}
fields_pers = {}
for f in *spaces_mod.list_fields cls_sp.id
  fields_cls[f.name] = f
for f in *spaces_mod.list_fields pers_sp.id
  fields_pers[f.name] = f

for i, nom in ipairs CLASSES
  ins CLS, "cls_#{i}", { id: i, nom: nom }
for i, p in ipairs PERSONS
  ins PERS, "pers_#{i}", { nom: p.nom, classe_id: p.classe_id, classe_fixe: p.classe_id }

rel_computed = schema_r.Mutation.createRelation nil, {
  input: {
    name:        'ct_classe'
    fromSpaceId: pers_sp.id
    fromFieldId: fields_pers['classe_actuelle'].id
    toSpaceId:   cls_sp.id
    toFieldId:   fields_cls['id'].id
    reprFormula: '@nom'
  }
}, CTX

rel_stored = schema_r.Mutation.createRelation nil, {
  input: {
    name:        'ct_fixe'
    fromSpaceId: pers_sp.id
    fromFieldId: fields_pers['classe_fixe'].id
    toSpaceId:   cls_sp.id
    toFieldId:   fields_cls['id'].id
    reprFormula: '@nom'
  }
}, CTX

PERS_T = dynamic.gql_name PERS
CLS_T  = dynamic.gql_name CLS

query = (q) ->
  res = executor.execute { query: q, context: CTX }
  R.nok res.errors, json.encode(res.errors)
  res.data

-- ── Tests ────────────────────────────────────────────────────────────────────

R.describe "Relation sur un champ calculé", ->
  R.it "(a) la requête dynamique résout le champ calculé en objet cible", ->
    data = query "{ #{PERS_T} { items { nom classe_actuelle { nom } } } }"
    items = data[PERS_T].items
    R.eq #items, #PERSONS, 'items'
    bad = {}
    for i, item in ipairs items
      expected = CLASSES[PERSONS[i].classe_id]
      got = item.classe_actuelle and item.classe_actuelle.nom
      table.insert bad, "#{item.nom}: #{tostring got} != #{expected}" if got != expected
    R.eq #bad, 0, "#{#bad} valeur(s) fausse(s); premiere: #{bad[1]}"

  R.it "(b) une formule de filtre navigue @classe_actuelle.nom", ->
    q = "{ #{PERS_T}(filter: { formula: \"@classe_actuelle.nom == '6eB'\", language: \"moonscript\" }) { total items { nom } } }"
    data = query q
    page = data[PERS_T]
    R.eq page.total, 2, 'deux personnes en 6eB'
    noms = [item.nom for item in *page.items]
    table.sort noms
    R.eq noms[1], 'Bruno'
    R.eq noms[2], 'David'

  R.it "(c) la relation inverse depuis la cible voit les lignes calculées", ->
    data = query "{ #{CLS_T} { items { nom ct_classe { items { nom } } } } }"
    by_name = {}
    for item in *data[CLS_T].items
      by_name[item.nom] = [p.nom for p in *item.ct_classe.items]
    table.sort by_name['6eB']
    R.eq #by_name['CM2'], 1, 'CM2'
    R.eq by_name['CM2'][1], 'Ada'
    R.eq #by_name['6eB'], 2, '6eB'
    R.eq by_name['6eB'][1], 'Bruno'
    R.eq by_name['6eB'][2], 'David'
    R.eq #by_name['3eA'], 1, '3eA'

  R.it "(d) sans sous-sélection, la valeur brute est un Int (chemin grille)", ->
    data = query "{ #{PERS_T} { items { nom classe_actuelle classe_fixe } } }"
    for i, item in ipairs data[PERS_T].items
      expected = PERSONS[i].classe_id
      R.eq item.classe_actuelle, expected, "classe_actuelle de #{item.nom}"
      R.eq item.classe_fixe, expected, "classe_fixe de #{item.nom}"

  R.it "(d bis) une relation non calculée continue de se résoudre en objet", ->
    data = query "{ #{PERS_T} { items { nom classe_fixe { nom } } } }"
    for i, item in ipairs data[PERS_T].items
      expected = CLASSES[PERSONS[i].classe_id]
      R.eq item.classe_fixe and item.classe_fixe.nom, expected, "classe_fixe de #{item.nom}"

  R.it "(e) une autre colonne calculée navigue @classe_actuelle.nom", ->
    data = query "{ #{PERS_T} { items { nom classe_nom } } }"
    for i, item in ipairs data[PERS_T].items
      expected = CLASSES[PERSONS[i].classe_id]
      R.eq item.classe_nom, expected, "classe_nom de #{item.nom}"

  R.it "(e bis) Query.records expose la valeur calculée (chemin custom views)", ->
    res = data_r.Query.records nil, { spaceId: pers_sp.id, limit: 100 }, CTX
    R.eq res.total, #PERSONS, 'total'
    by_nom = {}
    for item in *res.items
      d = if type(item.data) == 'string' then json.decode item.data else item.data
      by_nom[d.nom] = d
    for i, p in ipairs PERSONS
      R.eq by_nom[p.nom].classe_actuelle, p.classe_id, "classe_actuelle de #{p.nom}"

-- ── Nettoyage ────────────────────────────────────────────────────────────────

box.space._tdb_relations\delete { rel_computed.id }
box.space._tdb_relations\delete { rel_stored.id }
spaces_mod.delete_user_space PERS
spaces_mod.delete_user_space CLS
require('resolvers.init').reinit!
