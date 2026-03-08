# tests/js/test_yaml_builder.coffee — tests pour YamlBuilder (yaml_builder.js)
# Teste : génération YAML, clic champ, clic en-tête (aggregate), badges, dépendances.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# --- stubs ------------------------------------------------------------------
global.jsyaml =
  dump: (obj) -> JSON.stringify obj   # simplifie les comparaisons

# Chargement du module sous test (expose window.YamlBuilder)
require '../../frontend/src/yaml_builder'
YB = global.window.YamlBuilder

# --- helpers ----------------------------------------------------------------
makeSpaces = ->
  [
    { id: 'sp1', name: 'personnes', fields: [
        { id: 'f_nom',    name: 'nom',    fieldType: 'String' }
        { id: 'f_prenom', name: 'prenom', fieldType: 'String' }
        { id: 'f_age',    name: 'age',    fieldType: 'Int' }
    ]}
    { id: 'sp2', name: 'commandes', fields: [
        { id: 'f_client', name: 'client_id', fieldType: 'Int' }
        { id: 'f_total',  name: 'total',     fieldType: 'Int' }
    ]}
  ]

makeRelations = ->
  [{ id: 'r1', fromSpaceId: 'sp2', fromFieldId: 'f_client', toSpaceId: 'sp1', toFieldId: 'f_nom' }]

makeContainer = -> global.document.createElement 'div'

makeYB = (opts = {}) ->
  yb = new YB
    container:    makeContainer()
    allSpaces:    opts.spaces    or makeSpaces()
    allRelations: opts.relations or []
    onChange:     opts.onChange  or ->
  yb._render = ->   # no-op: tests d'état uniquement, pas de DOM SVG
  yb

# --- YamlBuilder : état initial ---------------------------------------------
describe 'YamlBuilder — initial', ->
  it 'pas de widgets au démarrage', ->
    yb = makeYB()
    eq yb._widgets.length, 0

  it 'toYaml() vide retourne squelette', ->
    yb = makeYB()
    yaml = yb.toYaml()
    assert yaml.indexOf('layout') != -1, 'contient layout'
    assert yaml.indexOf('children') != -1, 'contient children'

# --- YamlBuilder : clic champ -----------------------------------------------
describe 'YamlBuilder — clic champ', ->
  it 'ajouter un champ crée un widget régulier', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    eq yb._widgets.length, 1
    eq yb._widgets[0].spaceName, 'personnes'
    eq yb._widgets[0].columns.length, 1
    eq yb._widgets[0].columns[0], 'nom'

  it 'clic * crée un widget sans restriction de colonnes', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', '*'
    eq yb._widgets[0].columns.length, 0
    assert yb._widgets[0].type != 'aggregate', 'widget régulier, pas agrégat'

  it 'reclic * en mode all-columns supprime le widget', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', '*'
    yb._onFieldClick 'sp1', '*'
    eq yb._widgets.length, 0

  it 'reclic même champ le retire', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    yb._onFieldClick 'sp1', 'nom'
    eq yb._widgets.length, 0

  it 'plusieurs champs dans un même widget', ->
    yb = makeYB()
    yb._onFieldClick 'sp1', 'nom'
    yb._onFieldClick 'sp1', 'age'
    eq yb._widgets.length, 1
    eq yb._widgets[0].columns.length, 2

# --- YamlBuilder : clic en-tête (aggregate) ---------------------------------
describe 'YamlBuilder — clic en-tête (aggregate)', ->
  it 'crée un widget de type aggregate', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    eq yb._widgets.length, 1
    eq yb._widgets[0].type, 'aggregate'
    eq yb._widgets[0].spaceName, 'personnes'

  it 'groupBy contient tous les champs (pas de FK pour sp1)', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    deepEq yb._widgets[0].groupBy, ['age', 'nom', 'prenom']   # alphabetical

  it 'groupBy exclut les champs FK', ->
    yb = makeYB spaces: makeSpaces(), relations: makeRelations()
    yb._onHeaderClick 'sp2'
    # client_id est FK → exclus ; seul total reste
    deepEq yb._widgets[0].groupBy, ['total']

  it 'deuxième clic en-tête supprime le widget agrégat', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    yb._onHeaderClick 'sp1'
    eq yb._widgets.length, 0

  it 'widget agrégat et widget régulier peuvent coexister', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'     # aggregate
    yb._onFieldClick  'sp2', 'total'   # regular
    eq yb._widgets.length, 2
    eq (yb._widgets.filter (w) -> w.type == 'aggregate').length, 1
    eq (yb._widgets.filter (w) -> w.type != 'aggregate').length, 1

  it '_widgetForSpace n\'est pas sensible aux widgets agrégats', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    assert !yb._widgetForSpace('sp1'), 'pas de widget régulier pour sp1'
    assert yb._aggWidgetForSpace('sp1'), 'widget agrégat présent'

# --- YamlBuilder : toYaml avec aggregate ------------------------------------
describe 'YamlBuilder — toYaml aggregate', ->
  it 'génère type:aggregate avec groupBy', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    parsed = JSON.parse yb.toYaml()
    wObj = parsed.layout.children[0].widget
    eq wObj.type, 'aggregate'
    eq wObj.space, 'personnes'
    assert Array.isArray(wObj.groupBy), 'groupBy est un tableau'
    assert wObj.aggregate?.length > 0, 'aggregate a au moins une entrée'
    eq wObj.aggregate[0].fn, 'count'

  it 'génère le widget régulier correctement en présence d\'un agrégat', ->
    yb = makeYB()
    yb._onHeaderClick 'sp1'
    yb._onFieldClick  'sp2', 'total'
    parsed = JSON.parse yb.toYaml()
    eq parsed.layout.children.length, 2
    types = parsed.layout.children.map (c) -> c.widget.type
    assert 'aggregate' in types, 'agrégat présent'

# --- YamlBuilder : depends_on automatique -----------------------------------
describe 'YamlBuilder — depends_on', ->
  it 'détecte FK et génère depends_on', ->
    yb = makeYB spaces: makeSpaces(), relations: makeRelations()
    yb._onFieldClick 'sp1', 'nom'    # parent
    yb._onFieldClick 'sp2', 'total'  # enfant (a FK vers sp1)
    child = yb._widgets[1]
    assert child.dependsOn?, 'depends_on détecté'
    eq child.dependsOn.field, 'client_id'

summary()
