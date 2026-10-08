# tests/js/test_sidebar_helpers.coffee
# Handler « nouvel espace » de la barre latérale (AppSidebarHelpers.bindSidebar) :
# après création, l'espace doit être sélectionné via app.selectSpace une fois
# app._loadAll résolue (donc après _restoreFromHash, qui écraserait sinon la
# sélection — app_data_helpers.coffee:5-12).

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

require '../../frontend/src/app_sidebar_helpers'
ASH = global.window.AppSidebarHelpers

sleep = (ms) -> new Promise (r) -> setTimeout r, ms

# Le runner exécute les `it` en parallèle, or les globals (Spaces, tdbPrompt,
# tdbAlert) sont partagés : un handler encore en vol lirait le mock du
# scénario suivant. On sérialise explicitement nos scénarios.
_queue = Promise.resolve()
serialIt = (desc, fn) ->
  it desc, ->
    run = _queue.then fn, fn
    _queue = run
    run

# Déclenche le listener 'click' enregistré sur un élément stub et renvoie
# les promesses retournées par les handlers (handlers async en CoffeeScript 2).
dispatchClick = (el) ->
  (fn() for fn in (el._listeners['click'] or []))

# Fake app : seuls les éléments consultés À L'ENREGISTREMENT du handler sont
# nécessaires (app_sidebar_helpers.coffee:55-167) ; les méthodes appelées au
# moment du clic sont fournies par chaque scénario via hooks.
makeApp = (hooks) ->
  elems = {}
  get = (id) -> elems[id] ?= global.document.createElement 'div'
  app =
    _t: (key, vars = {}) -> key
    _err: (e) -> if e and e.message then e.message else String(e)
    _applySidebarState: ->
    _bindChangePasswordDialog: ->
    _bindCreateUserDialog: ->
    _bindCreateGroupDialog: ->
    _bindSnapshotPanel: ->
    _bindAppsPanel: ->
    _loadAll: hooks.loadAll
    selectSpace: hooks.selectSpace
    el:
      newSpaceBtn:              -> get 'new-space-btn'
      newPageBtn:               -> get 'new-page-btn'
      newDataViewBtn:           -> get 'new-data-view-btn'
      currentUserBtn:           -> get 'current-user-btn'
      userMenu:                 -> get 'user-menu'
      changePasswordBtn:        -> get 'change-password-btn'
      logoutBtn:                -> get 'logout-btn'
      langFrBtn:                -> get 'lang-fr-btn'
      langEnBtn:                -> get 'lang-en-btn'
      adminNavUsers:            -> get 'admin-nav-users'
      adminNavGroups:           -> get 'admin-nav-groups'
      adminNavSnapshot:         -> get 'admin-nav-snapshot'
      adminNavApps:             -> get 'admin-nav-apps'
      pluginsNavManage:         -> get 'plugins-nav-manage'
      warningChangePasswordBtn: -> get 'warning-change-password-btn'
      spaceList:                -> get 'space-list'
  app

# ---------------------------------------------------------------------------
describe 'AppSidebarHelpers.bindSidebar — bouton nouvel espace', ->
  serialIt 'sélectionne le nouvel espace APRÈS la résolution de _loadAll', ->
    events   = []
    selected = []
    created  = { id: 'sp-1', name: 'Livres', description: '' }
    existing = { id: 'sp-0', name: 'Ancien', description: '' }
    prompted = []
    alerted  = []

    global.tdbPrompt = (msg) ->
      prompted.push msg
      Promise.resolve 'Livres'
    global.tdbAlert = (msg, kind) ->
      alerted.push kind
      events.push 'alert'
    global.Spaces =
      create: (name) ->
        events.push 'create'
        Promise.resolve created

    app = makeApp
      # _loadAll se résout sur un tour de boucle d'événements (setTimeout),
      # comme AppDataHelpers.loadAll (app_data_helpers.coffee:4-5) : c'est
      # lui qui peuple app._allSpaces.
      loadAll: ->
        new Promise (resolve) ->
          setTimeout ->
            app._allSpaces = [existing, created]
            events.push 'loadAll'
            resolve()
          , 0
      selectSpace: (sp) ->
        events.push 'selectSpace'
        selected.push sp

    ASH.bindSidebar app
    eq prompted.length, 0, 'aucun prompt avant le clic'
    await Promise.all(dispatchClick(app.el.newSpaceBtn()))
    await sleep 40

    eq alerted.length, 0, "aucune alerte attendue (reçu : #{alerted})"
    eq prompted.length, 1, 'le prompt doit avoir été ouvert une fois'
    eq prompted[0], 'ui.prompts.newSpace'
    deepEq events, ['create', 'loadAll', 'selectSpace'],
      "selectSpace doit être appelé après la résolution de _loadAll — obtenu #{JSON.stringify events}"
    eq selected.length, 1, 'selectSpace doit être appelé une seule fois'
    eq selected[0].id, 'sp-1'
    eq selected[0], created, 'selectSpace doit recevoir l’espace créé'
    inList = (app._allSpaces or []).find (s) -> s.id == 'sp-1'
    assert selected[0] is inList, 'selectSpace doit recevoir l’objet de app._allSpaces'

  serialIt 'ne sélectionne rien si l’espace est introuvable dans _allSpaces', ->
    events  = []
    alerted = []
    created = { id: 'sp-9', name: 'Secret', description: '' }

    global.tdbPrompt = -> Promise.resolve 'Secret'
    global.tdbAlert = (msg, kind) ->
      alerted.push kind
      events.push 'alert'
    global.Spaces =
      create: ->
        events.push 'create'
        Promise.resolve created

    app = makeApp
      loadAll: ->
        new Promise (resolve) ->
          setTimeout ->
            # Droits de lecture insuffisants : le nouvel espace n'apparaît pas.
            app._allSpaces = [{ id: 'sp-0', name: 'Ancien', description: '' }]
            events.push 'loadAll'
            resolve()
          , 0
      selectSpace: (sp) ->
        events.push 'selectSpace'

    ASH.bindSidebar app
    await Promise.all(dispatchClick(app.el.newSpaceBtn()))
    await sleep 40

    deepEq events, ['create', 'loadAll'],
      "selectSpace ne doit pas être appelé si l’espace est absent de _allSpaces — obtenu #{JSON.stringify events}"
    eq alerted.length, 0, "aucune alerte attendue (reçu : #{alerted})"

summary()
