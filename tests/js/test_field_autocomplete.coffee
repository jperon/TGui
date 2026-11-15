# tests/js/test_field_autocomplete.coffee
# Autocomplete des noms de champs dans le filtre MoonScript ("λ") :
# détection du jeton, résolution des relations (profondeur quelconque),
# filtrage par préfixe et insertion.

require './dom_stub'
{ describe, it, eq, assert, deepEq, summary } = require './runner'

# Stubs des appels réseau utilisés pour les espaces autres que celui affiché.
calls = { get: 0, rels: 0, getIds: [] }
SPACES = {
  's2':
    id: 's2'
    fields: [
      { id: 'g1', name: 'classe', fieldType: 'Relation' }
      { id: 'g2', name: 'nom',    fieldType: 'String' }
      { id: 'g3', name: 'age',    fieldType: 'Number' }
    ]
  's3':
    id: 's3'
    fields: [{ id: 'h1', name: 'niveau', fieldType: 'String' }]
  # Espaces dédiés au test de cache, non touchés par les autres tests.
  's6':
    id: 's6'
    fields: [{ id: 'i1', name: 'cache_field', fieldType: 'String' }]
}
RELS = {
  's2': [{ id: 'r2', fromFieldId: 'g1', toSpaceId: 's3' }]
  's1': []
  's5': [{ id: 'r5', fromFieldId: 'fc', toSpaceId: 's6' }]
  's6': []
}

global.Spaces =
  getWithFields: (id) ->
    calls.get++
    calls.getIds.push id
    Promise.resolve SPACES[id]
  listRelations: (id) ->
    calls.rels++
    Promise.resolve RELS[id] or []

require '../../frontend/src/views/field_autocomplete'
FA = global.window.FieldAutocomplete

# DataView minimale : espace affiché s1 avec un champ relation `eleve` → s2.
makeDv = ->
  space:
    id: 's1'
    fields: [
      { id: 'f1', name: 'eleve', fieldType: 'Relation' }
      { id: 'f2', name: 'eleves', fieldType: 'Relation' }
      { id: 'f3', name: 'date',  fieldType: 'Date' }
    ]
  _relations: [{ id: 'r1', fromFieldId: 'f1', toSpaceId: 's2' }]

describe 'FieldAutocomplete._token', ->
  it 'détecte un @ seul', ->
    deepEq FA._token('@'), { path: [], prefix: '' }

  it 'détecte @eleve.de', ->
    deepEq FA._token('self.x == 1 and @eleve.de'), { path: ['eleve'], prefix: 'de' }

  it 'détecte un chemin profond terminé par un point', ->
    deepEq FA._token('@a.b.'), { path: ['a', 'b'], prefix: '' }

  it 'ne détecte rien sans @', ->
    eq FA._token('self.nom'), null

describe 'FieldAutocomplete._filter', ->
  fields = [
    { name: 'Nom' }
    { name: 'nombre' }
    { name: 'date' }
    { name: 'nom_secours' }
  ]

  it 'filtre par préfixe sans tenir compte de la casse', ->
    deepEq (f.name for f in FA._filter(fields, 'NO')), ['Nom', 'nom_secours', 'nombre']

  it 'renvoie tout, trié, sans préfixe', ->
    deepEq (f.name for f in FA._filter(fields, '')), ['date', 'Nom', 'nom_secours', 'nombre']

  it 'renvoie un tableau vide si aucun préfixe ne correspond', ->
    deepEq FA._filter(fields, 'zzz'), []

  it 'plafonne à 12 entrées', ->
    many = ({ name: "f#{i}" } for i in [0..30])
    eq FA._filter(many, 'f').length, 12

describe 'FieldAutocomplete._resolve', ->
  it 'niveau 1 : propose les champs de l\'espace cible', ->
    FA._resolve(makeDv(), ['eleve']).then (res) ->
      deepEq (f.name for f in res.fields), ['classe', 'nom', 'age']
      eq res.relations.length, 1

  it 'niveau 2 : suit la relation de l\'espace cible', ->
    FA._resolve(makeDv(), ['eleve', 'classe']).then (res) ->
      deepEq (f.name for f in res.fields), ['niveau']

  it 'segment inconnu : aucune proposition', ->
    FA._resolve(makeDv(), ['inconnu']).then (res) ->
      deepEq res.fields, []

  it 'champ sans relation : aucune proposition', ->
    FA._resolve(makeDv(), ['date', 'x']).then (res) ->
      deepEq res.fields, []

  it 'met les champs d\'un espace en cache', ->
    cacheDv = ->
      space: { id: 's5', fields: [{ id: 'fc', name: 'ref', fieldType: 'Relation' }] }
      _relations: [{ id: 'r5', fromFieldId: 'fc', toSpaceId: 's6' }]
    FA._reset()
    calls.getIds = []
    FA._resolve(cacheDv(), ['ref']).then ->
      FA._resolve(cacheDv(), ['ref']).then (res) ->
        deepEq (f.name for f in res.fields), ['cache_field']
        eq (calls.getIds.filter((id) -> id == 's6')).length, 1

describe 'FieldAutocomplete._insert', ->
  it 'remplace le préfixe par le nom et place le curseur après', ->
    res = FA._insert('@eleve.no and 1', 9, { name: 'nom' })
    eq res.value, '@eleve.nom and 1'
    eq res.caret, 10

  it 'remplace le jeton entier pour une proposition du premier niveau', ->
    deepEq FA._insert('@da', 3, { name: 'date' }), { value: '@date', caret: 5 }

# --- intégration attach() : liste ouverte, non vide, insertion par Entrée ------
flush = -> new Promise (r) -> setTimeout r, 0

makeInput = (value) ->
  el = global.document.createElement 'input'
  el.value = value
  el.selectionStart = value.length
  el.selectionEnd   = value.length
  el.dispatchEvent = (ev) ->
    for fn in (el._listeners[ev.type] or [])
      fn ev
  el

fire = (el, type, ev = {}) ->
  ev.type = type
  ev.preventDefault ?= ->
  for fn in (el._listeners[type] or [])
    fn ev
  ev

describe 'FieldAutocomplete.attach', ->
  it 'ouvre une liste non vide, insère au clavier, puis ferme', ->
    global.Event = class Event
      constructor: (@type, @opts) ->
    body = global.document.body = global.document.createElement 'body'
    input = makeInput '@ele'
    FA.attach input, -> makeDv()
    fire input, 'input'
    flush().then ->
      list = body.children[0]
      assert list?, 'la liste .field-ac doit être attachée à document.body'
      eq list.className, 'field-ac'
      # `eleve` et `eleves` commencent par « ele », tri alphabétique.
      eq list.children.length, 2
      eq list.children[0].children[0].textContent, '→ eleve'
      fire input, 'keydown', { key: 'Enter' }
      eq input.value, '@eleve'
      eq body.children.length, 0, 'la liste doit être fermée après insertion'
      # Le jeton disparaît : plus aucune liste.
      input.value = 'self.nom'
      input.selectionStart = input.value.length
      fire input, 'input'
      flush().then ->
        eq body.children.length, 0, 'aucune liste sans jeton @'

summary()
