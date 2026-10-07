# tests/js/test_apps_helpers.coffee — tests de AppAppsHelpers (app_apps_helpers.js)
# Fonctions pures du versionnage des apps + rendu sécurisé (pas d'innerHTML).

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

require '../../frontend/src/app_apps_helpers'
EH = global.window.AppAppsHelpers

# --- fake app ---------------------------------------------------------------
makeApp = ->
  elems = {}
  get = (id) ->
    elems[id] ?= global.document.createElement 'div'
    elems[id]
  app =
    _t: (key, vars = {}) -> key
    _appChoices: {}
    el:
      appsList:        -> get 'apps-list'
      appsPurgeOpenBtn: -> get 'apps-purge-open-btn'
      appsPlanBox:     -> get 'apps-plan-box'
      appsPlanErrors:  -> get 'apps-plan-errors'
      appsApplyBtn:    -> get 'apps-apply-btn'
      appsPurgePreview:      -> get 'apps-purge-preview'
      appsPurgeConfirmInput: -> get 'apps-purge-confirm-input'
      appsPurgeConfirmBtn:   -> get 'apps-purge-confirm-btn'
      appsPurgeConfirmHint:  -> get 'apps-purge-confirm-hint'
  app

# Collecte récursive des tagName (pour vérifier l'absence d'éléments injectés).
collectTags = (node) ->
  tags = []
  walk = (n) ->
    tags.push n.tagName if n and n.tagName
    if n and n._children
      for c in n._children
        walk c
  walk node
  tags

# ---------------------------------------------------------------------------
describe 'AppAppsHelpers.isSemver', ->
  it 'accepte x.y.z numérique', ->
    assert EH.isSemver('1.2.3'), '1.2.3'
    assert EH.isSemver('10.0.42'), '10.0.42'

  it 'refuse les formes invalides', ->
    assert not EH.isSemver('1.2'), '1.2'
    assert not EH.isSemver('v1.2.3'), 'v1.2.3'
    assert not EH.isSemver('1.2.3-beta'), 'préfixe'
    assert not EH.isSemver('1.2.x'), 'non numérique'
    assert not EH.isSemver(''), 'vide'
    assert not EH.isSemver(null), 'null'

describe 'AppAppsHelpers.buildDecisions', ->
  it 'défaut « local » pour un conflit sans choix', ->
    d = EH.buildDecisions([{ key: 'space:a' }], {})
    deepEq d, [{ key: 'space:a', choice: 'local' }]

  it 'respecte les choix fournis', ->
    d = EH.buildDecisions([{ key: 'a' }, { key: 'b' }], { b: 'delivered' })
    deepEq d, [{ key: 'a', choice: 'local' }, { key: 'b', choice: 'delivered' }]

  it 'retourne un tableau vide sans conflit', ->
    deepEq EH.buildDecisions(null, null), []

describe 'AppAppsHelpers.confirmationTarget', ->
  it 'un seul élément → partie après le dernier « : »', ->
    eq EH.confirmationTarget(['space:livres'], 'org.app'), 'livres'
    eq EH.confirmationTarget(['field:livres.titre'], 'org.app'), 'livres.titre'

  it 'plusieurs éléments → identifiant de l’app', ->
    eq EH.confirmationTarget(['space:a', 'space:b'], 'org.app'), 'org.app'

  it 'clé sans « : » → clé entière', ->
    eq EH.confirmationTarget(['solitaire'], 'org.app'), 'solitaire'

describe 'AppAppsHelpers.summarizePlan', ->
  it 'compte chaque catégorie', ->
    plan =
      create: [{ key: 'a' }]
      update: [{ key: 'b' }, { key: 'c' }]
      conflict: [{ key: 'd' }]
      keepLocal: [{ key: 'e' }]
      obsolete: ['f']
      rename: [{ from: 'g', to: 'h' }]
      unchanged: ['i', 'j', 'k']
      errors: []
    s = EH.summarizePlan plan
    eq s.create, 1
    eq s.update, 2
    eq s.conflict, 1
    eq s.keepLocal, 1
    eq s.obsolete, 1
    eq s.rename, 1
    eq s.unchanged, 3
    eq s.errors, 0

  it 'tolère un plan vide', ->
    s = EH.summarizePlan({})
    eq s.create, 0
    eq s.conflict, 0

describe 'AppAppsHelpers.hasCodeChanges', ->
  it 'vrai si un item isCode', ->
    assert EH.hasCodeChanges({ create: [{ key: 'a', isCode: true }] })

  it 'vrai si le type est plugin/page/dataview', ->
    assert EH.hasCodeChanges({ update: [{ key: 'a', type: 'plugin' }] })
    assert EH.hasCodeChanges({ conflict: [{ key: 'a', type: 'page' }] })

  it 'faux si aucun code tiers', ->
    assert not EH.hasCodeChanges({ create: [{ key: 'a', type: 'space' }] })
    assert not EH.hasCodeChanges({})

describe 'AppAppsHelpers.renderAppsList — sécurité', ->
  it 'n’injecte pas de HTML depuis un nom de paquet', ->
    app = makeApp()
    malicious = '<img src=x onerror=alert(1)>'
    EH.renderAppsList app, [{ appId: 'x', name: malicious, version: '1.0.0', activeCount: 2, obsoleteCount: 0 }]
    tags = collectTags app.el.appsList()
    assert tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé'
    assert tags.indexOf('DIV') >= 0, 'le nom doit être rendu comme texte'

  it 'désactive le bouton de purge sans élément obsolète', ->
    app = makeApp()
    EH.renderAppsList app, [{ appId: 'x', name: 'App', version: '1.0.0', activeCount: 2, obsoleteCount: 0 }]
    assert app.el.appsPurgeOpenBtn().disabled, 'désactivé quand obsoleteCount = 0'

  it 'active le bouton de purge s’il existe des obsolètes', ->
    app = makeApp()
    EH.renderAppsList app, [{ appId: 'x', name: 'App', version: '1.0.0', activeCount: 1, obsoleteCount: 3 }]
    assert not app.el.appsPurgeOpenBtn().disabled, 'activé quand obsoleteCount > 0'

describe 'AppAppsHelpers.renderPlan', ->
  it 'rend un plan simulé avec conflit et code tiers', ->
    app = makeApp()
    plan =
      create: [{ key: 'plugin:demo', type: 'plugin', content: { name: 'demo' }, isCode: true }]
      update: [{ key: 'space:livres', type: 'space', content: {}, isCode: false }]
      keepLocal: [{ key: 'field:livres.titre', type: 'field', content: {} }]
      conflict: [{ key: 'view:livres.vue', type: 'view', local: { a: 1 }, delivered: { a: 2 } }]
      obsolete: ['page:ancienne']
      rename: [{ from: 'space:old', to: 'space:new' }]
      unchanged: ['group:admin']
      errors: []
    EH.renderPlan app, plan
    tags = collectTags app.el.appsPlanBox()
    eq app.el.appsApplyBtn().disabled, false
    assert app.el.appsPlanErrors().classList.contains('hidden'), 'pas d’erreurs affichées'
    assert tags.indexOf('DETAILS') >= 0, 'détails dépliables pour le code tiers'
    assert tags.indexOf('TABLE') < 0, 'aucun tableau dans le plan'
    text = JSON.stringify app.el.appsPlanBox()
    assert text.indexOf('ui.apps.conflicts') >= 0, 'section conflits'
    assert text.indexOf('ui.apps.codeBadge') >= 0, 'badge code tiers'
    assert text.indexOf('ui.apps.localVersion') >= 0, 'version locale'
    assert text.indexOf('ui.apps.deliveredVersion') >= 0, 'version livrée'

  it 'désactive Appliquer si plan.errors est non vide', ->
    app = makeApp()
    EH.renderPlan app, { errors: ['version trop ancienne'], create: [] }
    eq app.el.appsApplyBtn().disabled, true
    errEl = app.el.appsPlanErrors()
    assert not errEl.classList.contains('hidden'), 'erreurs visibles'

describe 'AppAppsHelpers purge', ->
  it 'confirmation désactivée sans aperçu', ->
    app = makeApp()
    app._appPurgeTarget = 'livres'
    EH.refreshPurgeConfirm app
    assert app.el.appsPurgeConfirmBtn().disabled, 'désactivé sans aperçu'

  it 'confirmation activée seulement après aperçu et saisie exacte', ->
    app = makeApp()
    app._appPurgeAppId = 'org.app'
    app._appPurgePreview = { keys: ['space:livres'] }
    EH.renderPurgePreview app,
      losses: [{ key: 'space:livres', type: 'space', records: 3, fields: 2, relations: 0, views: 1 }]
      totalRecords: 3
    eq app._appPurgeTarget, 'livres'
    app.el.appsPurgeConfirmInput().value = 'livres'
    EH.refreshPurgeConfirm app
    assert not app.el.appsPurgeConfirmBtn().disabled, 'activé quand la saisie correspond'
    app.el.appsPurgeConfirmInput().value = 'mauvais'
    EH.refreshPurgeConfirm app
    assert app.el.appsPurgeConfirmBtn().disabled, 'désactivé quand la saisie diffère'

  it 'n’injecte pas de HTML depuis une clé de perte', ->
    app = makeApp()
    app._appPurgeAppId = 'org.app'
    app._appPurgePreview = { keys: ['space:x'] }
    EH.renderPurgePreview app,
      losses: [{ key: '<img src=x onerror=alert(1)>', type: 'space', records: 1, fields: 0, relations: 0, views: 0 }]
      totalRecords: 1
    tags = collectTags app.el.appsPurgePreview()
    assert tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé'

summary()