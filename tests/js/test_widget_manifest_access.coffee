# tests/js/test_widget_manifest_access.coffee
# Manifest des widgets personnalisés : accès effectif (none/read/full),
# refus des opérations non autorisées avant tout relais, renommage des lignes
# selon le mappage de colonnes et traduction inverse pour les écritures.
# Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §3, §6.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

# js-yaml est fourni par le bundle navigateur en production ; en test, un
# analyseur minimal suffit : les manifestes sont écrits en JSON (YAML valide).
global.window.jsyaml =
  load: (text) ->
    trimmed = String(text or '').trim()
    return undefined if trimmed == '' or trimmed.indexOf('#') == 0
    JSON.parse trimmed

global.window.CustomView = -> null
relayed = []
writes = []
global.GQL =
  query: -> Promise.resolve {}
  queryWidget: (query, variables) ->
    writes.push { query, variables }
    Promise.resolve { data: {} }
require '../../frontend/src/views/custom_view_plugins'
CV = global.window.CustomView.prototype

asProto = (name) -> CV[name]

describe 'Widgets personnalisés — accès effectif', ->
  it 'sans manifeste : full (rétrocompatibilité)', ->
    accessOf = asProto '_pluginAccessOf'
    eq (accessOf.call CV, { manifest: '' }), 'full'
    eq (accessOf.call CV, {}), 'full'
    eq (accessOf.call CV, null), 'full'

  it 'manifeste sans access : read', ->
    eq (asProto('_pluginAccessOf').call CV, { manifest: '{}' }), 'read'

  it 'respecte none, read et full', ->
    for access in ['none', 'read', 'full']
      eq (asProto('_pluginAccessOf').call CV, { manifest: JSON.stringify { access } }), access

  it 'manifeste invalide ou access inconnu : read (jamais plus)', ->
    eq (asProto('_pluginAccessOf').call CV, { manifest: '{oops' }), 'read'
    eq (asProto('_pluginAccessOf').call CV, { manifest: JSON.stringify { access: 'write' } }), 'read'
    eq (asProto('_pluginAccessOf').call CV, { manifest: '# commentaire' }), 'full'

describe 'Widgets personnalisés — type d’opération GraphQL', ->
  op = asProto '_widgetQueryOperation'

  it 'reconnaît une query anonyme et nommée', ->
    eq op.call(CV, '{ spaces { id } }'), 'query'
    eq op.call(CV, '  query Foo($x: Int) { spaces { id } }'), 'query'

  it 'reconnaît mutation et subscription', ->
    eq op.call(CV, 'mutation { updateRecord(spaceId: "s", id: "r", data: "{}") { id } }'), 'mutation'
    eq op.call(CV, 'subscription { records { id } }'), 'subscription'

  it 'ignore commentaires et espaces avant le mot-clé', ->
    eq op.call(CV, '  # commentaire\n\n mutation { deleteRecord(spaceId: "s", id: "r") }'), 'mutation'
    eq op.call(CV, '# titre\n{ spaces { id } }'), 'query'

  it 'refuse (null) ce qui n’est pas une opération lisible', ->
    eq op.call(CV, 'fragment F on Query { spaces { id } }'), null
    eq op.call(CV, 'n’importe quoi'), null
    eq op.call(CV, '   '), null
    eq op.call(CV, ''), null

describe 'Widgets personnalisés — refus des requêtes', ->
  refusal = asProto '_widgetQueryRefusal'

  it 'access none : aucune requête relayée', ->
    msg = refusal.call CV, 'none', '{ spaces { id } }'
    assert msg, 'refus attendu'
    assert msg.indexOf('access: none') > -1, 'message explicite'
    eq refusal.call(CV, 'none', 'mutation { x }')?.indexOf('access: none') > -1, true

  it 'access read : query autorisée, mutation et subscription refusées', ->
    eq refusal.call(CV, 'read', '{ spaces { id } }'), null
    eq refusal.call(CV, 'read', 'query Q { spaces { id } }'), null
    msgMutation = refusal.call CV, 'read', 'mutation { updateRecord(spaceId: "s", id: "r", data: "{}") { id } }'
    assert msgMutation.indexOf('lectures') > -1, 'mutation refusée en lecture'
    assert refusal.call(CV, 'read', 'subscription { x }').indexOf('lectures') > -1, 'subscription refusée'

  it 'access read : requête illisible refusée (doute = refus)', ->
    assert refusal.call(CV, 'read', 'fragment F on Query { x }').indexOf('illisible') > -1
    assert refusal.call(CV, 'read', '').indexOf('illisible') > -1

  it 'access full : query et mutation autorisées, subscription refusée', ->
    eq refusal.call(CV, 'full', '{ spaces { id } }'), null
    eq refusal.call(CV, 'full', 'mutation { updateRecord(spaceId: "s", id: "r", data: "{}") { id } }'), null
    assert refusal.call(CV, 'full', 'subscription { x }').indexOf('souscriptions') > -1
    assert refusal.call(CV, 'full', 'fragment F on Query { x }').indexOf('illisible') > -1

describe 'Widgets personnalisés — mappage de colonnes', ->
  node =
    columns:
      titre: 'nom'
      debut: 'date_debut'

  row = { id: 'r1', nom: 'Fête', date_debut: '2026-01-01', secret: 'interne' }

  it 'renomme les colonnes déclarées et garde id, rien d’autre', ->
    renamed = asProto('_pluginRenameRow').call CV, node, row
    eq renamed.id, 'r1'
    eq renamed.titre, 'Fête'
    eq renamed.debut, '2026-01-01'
    eq renamed.secret, undefined
    eq renamed.nom, undefined

  it 'sans mappage (ou colonnes en liste) : ligne inchangée', ->
    eq asProto('_pluginRenameRow').call(CV, { columns: ['nom'] }, row), row
    eq asProto('_pluginRenameRow').call(CV, {}, row), row

  it 'traduit les noms déclarés vers les champs pour les écritures', ->
    values = asProto('_pluginTranslateValues').call CV, node.columns,
      { titre: 'Fête', debut: '2026-02-02', id: 'ignoré', inconnu: 'x' }
    eq values.nom, 'Fête'
    eq values.date_debut, '2026-02-02'
    eq values.id, undefined
    eq values.inconnu, undefined
    eq Object.keys(values).length, 2

  it 'sans mappage : les noms sont déjà ceux de la source', ->
    values = asProto('_pluginTranslateValues').call CV, null, { nom: 'A', secret: 'B' }
    eq values.nom, 'A'
    eq values.secret, 'B'

  it 'signale les colonnes obligatoires non mappées', ->
    manifest =
      columns: [
        { name: 'titre', type: 'String' }
        { name: 'debut', type: 'Date' }
        { name: 'fin', type: 'Date', optional: true }
      ]
    eq asProto('_pluginMissingColumns').call(CV, manifest, { titre: 'nom' }).join(','), 'debut'
    eq asProto('_pluginMissingColumns').call(CV, manifest, { titre: 'nom', debut: 'd' }).length, 0
    eq asProto('_pluginMissingColumns').call(CV, null, null).length, 0

describe 'Widgets personnalisés — API exposée dans l’iframe', ->
  docFor = (access) ->
    asProto('_buildPluginIframeDoc').call CV, 'w1', {},
      { jsScript: '', htmlTemplate: '' }, { name: 'demo', manifest: JSON.stringify { access } },
      { access }

  it 'access none : pas de gql, pas de données, pas d’écriture', ->
    doc = docFor 'none'
    assert doc.indexOf('api.gql = gql') == -1, 'gql ne doit pas être exposé'
    assert doc.indexOf('api.onRecords') == -1, 'onRecords ne doit pas être exposé'
    assert doc.indexOf('api.updateRecord') == -1, 'aucune écriture'
    assert doc.indexOf('setCursor: setCursor') > -1, 'setCursor (sélection) reste disponible'

  it 'access read : gql + onRecords/onRecord, sans écriture', ->
    doc = docFor 'read'
    assert doc.indexOf('api.gql = gql') > -1, 'gql présent'
    assert doc.indexOf('api.onRecords = onRecords') > -1, 'onRecords présent'
    assert doc.indexOf('api.onRecord = onRecord') > -1, 'onRecord présent'
    assert doc.indexOf('api.updateRecord') == -1, 'pas de updateRecord'
    assert doc.indexOf('api.insertRecord') == -1, 'pas de insertRecord'
    assert doc.indexOf('api.deleteRecord') == -1, 'pas de deleteRecord'

  it 'access full : écritures exposées', ->
    doc = docFor 'full'
    assert doc.indexOf('api.updateRecord = updateRecord') > -1
    assert doc.indexOf('api.insertRecord = insertRecord') > -1
    assert doc.indexOf('api.deleteRecord = deleteRecord') > -1

  it 'annonce plugin_ready après l’exécution du script', ->
    doc = docFor 'read'
    assert doc.indexOf("post({ type: 'plugin_ready' })") > -1

describe 'Éditeur de plugins — manifest', ->
  it 'propose un exemple YAML commenté (access, columns, options)', ->
    global.window.AppViewHelpers = {} unless global.window.AppViewHelpers
    require '../../frontend/src/app_view_helpers_widget_plugins'
    defaults = global.window.AppViewHelpers._defaultWidgetPlugin()
    manifest = defaults.manifest or ''
    assert manifest.indexOf('# access: none | read | full') > -1, 'ligne access commentée'
    assert manifest.indexOf('# columns:') > -1, 'exemple de colonnes'
    assert manifest.indexOf('# options:') > -1, 'exemple d’options'
    # Exemple entièrement commenté : il ne déclare rien tant qu'on ne l'édite pas.
    for line in manifest.split '\n'
      assert (line.trim().charAt(0) == '#' or line.trim() == ''), "ligne non commentée : #{line}"

summary()
