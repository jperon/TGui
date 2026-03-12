require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

# Minimal stubs for AppUndoHelpers
store = {}
lastUpdatePayload = null
lastRestorePayload = null
lastDeleteIds = null

global.GQL =
  query: (q, vars = {}) ->
    if /query Record/.test q
      rec = store[vars.id]
      Promise.resolve
        record: if rec? then { id: vars.id, data: JSON.stringify(rec) } else null
    else
      Promise.resolve {}

  mutate: (q, vars = {}) ->
    if /updateRecords/.test q
      lastUpdatePayload = vars.records
      for rec in (vars.records or [])
        current = store[String(rec.id)] or {}
        patch = JSON.parse(rec.data)
        store[String(rec.id)] = { ...current, ...patch }
      Promise.resolve updateRecords: vars.records.map (r) -> { id: r.id, data: r.data }
    else if /restoreRecords/.test q
      lastRestorePayload = vars.records
      for rec in (vars.records or [])
        store[String(rec.id)] = JSON.parse(rec.data)
      Promise.resolve restoreRecords: vars.records.map (r) -> { id: r.id, data: r.data }
    else
      Promise.resolve {}

global.Spaces =
  deleteRecords: (spaceId, ids) ->
    lastDeleteIds = ids
    delete store[String(id)] for id in (ids or [])
    Promise.resolve true

require '../../frontend/src/app_undo_helpers'
UH = global.window.AppUndoHelpers

makeApp = ->
  undoBtn = global.document.createElement 'button'
  redoBtn = global.document.createElement 'button'
  app =
    _allSpaces: [{ id: 's1', name: 'Space1' }]
    _currentSpace: { id: 's1', name: 'Space1' }
    _activeDataView:
      load: -> Promise.resolve true
    el:
      undoBtn: -> undoBtn
      redoBtn: -> redoBtn
      customViewList: -> querySelector: -> null
    selectSpace: (sp) -> app._currentSpace = sp
    loadSpaces: -> Promise.resolve()
    loadCustomViews: -> Promise.resolve()
  { app, undoBtn, redoBtn }

describe 'AppUndoHelpers', ->
  it 'gère update, blocage conflit, et delete undo/redo', ->
    # 1) Update undo/redo
    UH.clear()
    store = { '1': { nom: 'B' } }
    lastUpdatePayload = null
    UH.pushAction
      spaceId: 's1'
      context: { spaceId: 's1' }
      updates: [{ id: '1', before: { nom: 'A' }, after: { nom: 'B' } }]
      inserts: []
      deletes: []
    { app } = makeApp()
    okUndo = await UH.undo app
    assert okUndo, 'undo update doit réussir'
    eq store['1'].nom, 'A'
    assert lastUpdatePayload?.length == 1, 'updateRecords doit être appelé'
    okRedo = await UH.redo app
    assert okRedo, 'redo update doit réussir'
    eq store['1'].nom, 'B'

    # 2) Régression subset: un champ non modifié peut diverger sans bloquer undo
    UH.clear()
    store = { '1': { nom: 'B', prenom: 'Victor' } }
    UH.pushAction
      spaceId: 's1'
      context: { spaceId: 's1' }
      updates: [{ id: '1', before: { nom: 'A' }, after: { nom: 'B' } }]
      inserts: []
      deletes: []
    { app } = makeApp()
    okSubset = await UH.undo app
    assert okSubset, 'undo subset doit réussir'
    eq store['1'].nom, 'A'
    eq store['1'].prenom, 'Victor'

    # 3) Multi-update dans une seule action
    UH.clear()
    store = { '1': { nom: 'B' }, '2': { nom: 'Y' } }
    UH.pushAction
      spaceId: 's1'
      context: { spaceId: 's1' }
      updates: [
        { id: '1', before: { nom: 'A' }, after: { nom: 'B' } }
        { id: '2', before: { nom: 'X' }, after: { nom: 'Y' } }
      ]
      inserts: []
      deletes: []
    { app } = makeApp()
    okMulti = await UH.undo app
    assert okMulti, 'undo multi-update doit réussir'
    eq store['1'].nom, 'A'
    eq store['2'].nom, 'X'

    # 4) Conflit serveur bloque undo
    UH.clear()
    store = { '1': { nom: 'X' } }
    UH.pushAction
      spaceId: 's1'
      context: { spaceId: 's1' }
      updates: [{ id: '1', before: { nom: 'A' }, after: { nom: 'B' } }]
      inserts: []
      deletes: []
    { app, undoBtn } = makeApp()
    okBlocked = await UH.undo app
    assert not okBlocked, 'undo doit être bloqué en conflit'
    await UH.refreshUI app
    assert undoBtn.classList.contains('toolbar-btn--blocked'), 'le bouton undo doit être marqué bloqué'
    assert String(undoBtn.title).includes('bloquée'), 'le tooltip doit expliquer le blocage'

    # 5) Delete undo/redo
    UH.clear()
    store = {}
    lastRestorePayload = null
    lastDeleteIds = null
    UH.pushAction
      spaceId: 's1'
      context: { spaceId: 's1' }
      updates: []
      inserts: []
      deletes: [{ id: '9', before: { nom: 'Supp' } }]
    { app } = makeApp()
    okUndoDelete = await UH.undo app
    assert okUndoDelete, 'undo delete doit réussir'
    eq store['9'].nom, 'Supp'
    assert lastRestorePayload?.length == 1, 'restoreRecords doit être appelé'
    okRedoDelete = await UH.redo app
    assert okRedoDelete, 'redo delete doit réussir'
    assert not store['9']?, 'record doit être supprimé à nouveau'
    assert (lastDeleteIds or []).includes('9'), 'deleteRecords doit être appelé'

summary()
