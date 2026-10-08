# tests/js/test_apps_reload_menu.coffee — T14
# Après une installation ou une purge de paquet, le MENU (espaces, pages,
# vues de données) doit être rechargé via app._loadAll, pas seulement la
# liste des applications (app._loadApps) — sinon il faut recharger la page
# pour voir les nouveaux éléments.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

require '../../frontend/src/app_apps_helpers'
EH = global.window.AppAppsHelpers

sleep = (ms) -> new Promise (r) -> setTimeout r, ms

# Les globals (GQL, tdbConfirm, tdbAlert) sont partagés : on sérialise les
# scénarios, comme dans test_sidebar_helpers.coffee.
_queue = Promise.resolve()
serialIt = (desc, fn) ->
  it desc, ->
    run = _queue.then fn, fn
    _queue = run
    run

# Fake app : éléments consultés par renderApplyReport / confirmPurge, plus
# les deux spies de rechargement.
makeApp = (events) ->
  elems = {}
  get = (id) -> elems[id] ?= global.document.createElement 'div'
  app =
    _t: (key, vars = {}) -> key
    _err: (e) -> if e and e.message then e.message else String(e)
    _appPlan: { conflict: [] }
    _appPackageYaml: "name: demo\n"
    _appChoices: {}
    _loadApps: -> events.push 'loadApps'
    _loadAll:  -> events.push 'loadAll'
    el:
      appsApplyBtn:        -> get 'apps-apply-btn'
      appsApplyReport:     -> get 'apps-apply-report'
      appsAllowDowngrade:  -> get 'apps-allow-downgrade'
      appsPurgeBox:        -> get 'apps-purge-box'
      appsPurgeReport:     -> get 'apps-purge-report'
      appsPurgePreview:    -> get 'apps-purge-preview'
      appsPurgeConfirmInput: -> get 'apps-purge-confirm-input'
      appsPurgeConfirmBtn:   -> get 'apps-purge-confirm-btn'
      appsPurgeConfirmHint:  -> get 'apps-purge-confirm-hint'
  app

# GQL.mutate simulé : trace 'mutate' à l'appel puis 'mutate-resolved' quand
# la promesse se résout — pour prouver l'ordre par rapport au rechargement.
stubGql = (result, events) ->
  global.GQL =
    mutate: (query, vars) ->
      events.push 'mutate'
      Promise.resolve(result).then (r) ->
        events.push 'mutate-resolved'
        r

applyResult = (over = {}) ->
  base =
    ok: true
    created: ['space:livres']
    updated: []
    kept: []
    unchanged: []
    obsolete: []
    skipped: []
    error: null
  Object.assign base, over

# ---------------------------------------------------------------------------
describe 'AppAppsHelpers.applyPackage — rechargement du menu (T14)', ->

  serialIt '(a) après installation réussie, _loadAll est appelé APRÈS la résolution de la mutation', ->
    events = []
    global.tdbConfirm = -> Promise.resolve true
    global.tdbAlert = (msg, kind) -> events.push 'alert'
    stubGql { applyAppUpdate: applyResult() }, events
    app = makeApp events

    await EH.applyPackage app
    await sleep 40

    deepEq events, ['mutate', 'mutate-resolved', 'loadApps', 'loadAll'],
      "_loadAll doit suivre la résolution de la mutation — obtenu #{JSON.stringify events}"

  serialIt '(d) les deux appels (_loadApps et _loadAll) ont lieu', ->
    events = []
    global.tdbConfirm = -> Promise.resolve true
    global.tdbAlert = (msg, kind) -> events.push 'alert'
    stubGql { applyAppUpdate: applyResult() }, events
    app = makeApp events

    await EH.applyPackage app
    await sleep 40

    assert events.indexOf('loadApps') >= 0, '_loadApps doit être appelé'
    assert events.indexOf('loadAll') >= 0, '_loadAll doit être appelé'

  serialIt 'installation partielle (ok faux mais created non vide) recharge aussi le menu', ->
    events = []
    global.tdbConfirm = -> Promise.resolve true
    global.tdbAlert = (msg, kind) -> events.push 'alert'
    stubGql { applyAppUpdate: applyResult(ok: false, created: ['space:x'], error: 'partiel') }, events
    app = makeApp events

    await EH.applyPackage app
    await sleep 40

    assert events.indexOf('loadAll') >= 0,
      "_loadAll doit être appelé si created n'est pas vide — obtenu #{JSON.stringify events}"

  serialIt '(c) échec complet : _loadAll n’est PAS appelé', ->
    events = []
    global.tdbConfirm = -> Promise.resolve true
    global.tdbAlert = (msg, kind) -> events.push 'alert'
    stubGql { applyAppUpdate: applyResult(ok: false, created: [], updated: [], error: 'boom') }, events
    app = makeApp events

    await EH.applyPackage app
    await sleep 40

    deepEq events, ['mutate', 'mutate-resolved'],
      "ni _loadApps ni _loadAll en cas d'échec complet — obtenu #{JSON.stringify events}"

# ---------------------------------------------------------------------------
describe 'AppAppsHelpers.confirmPurge — rechargement du menu (T14)', ->

  _purgeApp = (events) ->
    app = makeApp events
    app._appPurgeAppId = 'org.demo'
    app._appPurgePreview = { keys: ['space:livres'] }
    app._appPurgeTarget = 'livres'
    app.el.appsPurgeConfirmInput().value = 'livres'
    app

  serialIt '(b) après purge réussie, _loadAll est appelé après la résolution', ->
    events = []
    global.tdbConfirm = -> Promise.resolve true
    global.tdbAlert = (msg, kind) -> events.push 'alert'
    stubGql { purgeAppObsolete: { ok: true, purged: ['space:livres'], error: null } }, events
    app = _purgeApp events

    await EH.confirmPurge app
    await sleep 40

    deepEq events, ['mutate', 'mutate-resolved', 'loadApps', 'loadAll'],
      "purge réussie → _loadApps puis _loadAll — obtenu #{JSON.stringify events}"

  serialIt 'purge en échec : aucun rechargement', ->
    events = []
    global.tdbConfirm = -> Promise.resolve true
    global.tdbAlert = (msg, kind) -> events.push 'alert'
    stubGql { purgeAppObsolete: { ok: false, purged: [], error: 'nope' } }, events
    app = _purgeApp events

    await EH.confirmPurge app
    await sleep 40

    deepEq events, ['mutate', 'mutate-resolved'],
      "aucun rechargement en cas d'échec — obtenu #{JSON.stringify events}"

summary()
