# app_undo_helpers.coffee — global undo/redo stack with optimistic conflict checks

RECORD_QUERY = """
  query Record($spaceId: ID!, $id: ID!) {
    record(spaceId: $spaceId, id: $id) { id data }
  }
"""

UPDATE_RECORDS = """
  mutation UpdateRecords($spaceId: ID!, $records: [RecordUpdateInput!]!) {
    updateRecords(spaceId: $spaceId, records: $records) { id data }
  }
"""

RESTORE_RECORDS = """
  mutation RestoreRecords($spaceId: ID!, $records: [RecordUpdateInput!]!) {
    restoreRecords(spaceId: $spaceId, records: $records) { id data }
  }
"""

waitUntil = (fn, timeoutMs = 3000, stepMs = 40) ->
  new Promise (resolve) ->
    started = Date.now()
    tick = ->
      if fn()
        resolve true
      else if Date.now() - started >= timeoutMs
        resolve false
      else
        setTimeout tick, stepMs
    tick()

isPlainObject = (v) ->
  !!v and Object.prototype.toString.call(v) == '[object Object]'

window.AppUndoHelpers =
  _undoStack: []
  _redoStack: []
  _maxDepth: 150
  _keyboardBound: false

  currentContext: (spaceId = null) ->
    hash = window.location?.hash or ''
    viewId = null
    hashSpaceId = null
    if m = hash.match /^#view\/(.+)$/
      viewId = m[1]
    else if m = hash.match /^#space\/(.+)$/
      hashSpaceId = m[1]
    {
      hash: hash
      viewId: viewId
      spaceId: spaceId or hashSpaceId
    }

  clear: ->
    @_undoStack = []
    @_redoStack = []

  pushAction: (action) ->
    return unless action
    return unless action.spaceId
    action.createdAt = Date.now()
    @_undoStack.push action
    if @_undoStack.length > @_maxDepth
      @_undoStack.shift()
    @_redoStack = []

  canUndo: -> @_undoStack.length > 0
  canRedo: -> @_redoStack.length > 0

  _clone: (v) ->
    JSON.parse JSON.stringify(v ? null)

  _normalizeData: (v) ->
    return v if v == null
    if typeof v == 'string'
      try
        return JSON.parse(v)
      catch
        return v
    v

  _stableJson: (v) ->
    if Array.isArray(v)
      return '[' + (v.map (x) => @_stableJson(x)).join(',') + ']'
    if isPlainObject(v)
      keys = Object.keys(v).sort()
      return '{' + (keys.map (k) => JSON.stringify(k) + ':' + @_stableJson(v[k])).join(',') + '}'
    JSON.stringify(v)

  _sameData: (a, b) ->
    @_stableJson(@_normalizeData(a)) == @_stableJson(@_normalizeData(b))

  _sameDataSubset: (currentData, expectedData) ->
    cur = @_normalizeData(currentData)
    exp = @_normalizeData(expectedData)
    return @_sameData(cur, exp) unless isPlainObject(exp)
    return false unless isPlainObject(cur)
    for own k, v of exp
      return false unless @_sameData(cur[k], v)
    true

  _fetchRecord: (spaceId, id) ->
    data = await GQL.query RECORD_QUERY, { spaceId, id }
    rec = data?.record
    return null unless rec
    {
      id: String(rec.id)
      data: @_normalizeData(rec.data)
    }

  _fetchRecordMap: (spaceId, ids) ->
    uniq = [...new Set((String(id) for id in ids when id?))]
    out = {}
    await Promise.all uniq.map (id) =>
      rec = await @_fetchRecord spaceId, id
      out[id] = rec
    out

  _buildPlan: (action, direction) ->
    updates = action.updates or []
    inserts = action.inserts or []
    deletes = action.deletes or []
    checks = []
    updateRecords = []
    deleteIds = []
    restoreRecords = []

    if direction == 'undo'
      for rec in updates
        checks.push { id: rec.id, expect: 'match', mode: 'subset', expected: rec.after, reason: "Le record #{rec.id} a changé sur le serveur" }
        updateRecords.push { id: rec.id, data: rec.before }
      for rec in inserts
        checks.push { id: rec.id, expect: 'match', expected: rec.after, reason: "Le record inséré #{rec.id} a changé sur le serveur" }
        deleteIds.push rec.id
      for rec in deletes
        checks.push { id: rec.id, expect: 'absent', reason: "Le record supprimé #{rec.id} existe déjà" }
        restoreRecords.push { id: rec.id, data: rec.before }
    else
      for rec in updates
        checks.push { id: rec.id, expect: 'match', mode: 'subset', expected: rec.before, reason: "Le record #{rec.id} a changé sur le serveur" }
        updateRecords.push { id: rec.id, data: rec.after }
      for rec in inserts
        checks.push { id: rec.id, expect: 'absent', reason: "Le record #{rec.id} existe déjà" }
        restoreRecords.push { id: rec.id, data: rec.after }
      for rec in deletes
        checks.push { id: rec.id, expect: 'match', expected: rec.before, reason: "Le record #{rec.id} a changé sur le serveur" }
        deleteIds.push rec.id

    {
      spaceId: action.spaceId
      context: action.context or {}
      checks: checks
      updateRecords: updateRecords
      deleteIds: deleteIds
      restoreRecords: restoreRecords
    }

  _verifyPlan: (plan) ->
    ids = (c.id for c in plan.checks)
    server = await @_fetchRecordMap plan.spaceId, ids
    for chk in plan.checks
      cur = server[String(chk.id)]
      if chk.expect == 'absent'
        if cur?
          return { ok: false, message: chk.reason }
      else if chk.expect == 'match'
        unless cur?
          return { ok: false, message: "Record #{chk.id} introuvable" }
        same = if chk.mode == 'subset' then @_sameDataSubset(cur.data, chk.expected) else @_sameData(cur.data, chk.expected)
        unless same
          return { ok: false, message: chk.reason }
    { ok: true }

  _executePlan: (plan) ->
    if plan.updateRecords.length > 0
      payload = plan.updateRecords.map (r) -> { id: String(r.id), data: JSON.stringify(r.data ? {}) }
      await GQL.mutate UPDATE_RECORDS, { spaceId: plan.spaceId, records: payload }

    if plan.deleteIds.length > 0
      await Spaces.deleteRecords plan.spaceId, (String(id) for id in plan.deleteIds)

    if plan.restoreRecords.length > 0
      payload = plan.restoreRecords.map (r) -> { id: String(r.id), data: JSON.stringify(r.data ? {}) }
      await GQL.mutate RESTORE_RECORDS, { spaceId: plan.spaceId, records: payload }

  _navigateToContext: (app, context) ->
    return unless app
    ctx = context or {}

    if ctx.viewId
      if app._currentCustomView?.id != ctx.viewId
        li = app.el.customViewList()?.querySelector ".leaf-item[data-id='#{ctx.viewId}']"
        unless li
          await app.loadCustomViews()
          li = app.el.customViewList()?.querySelector ".leaf-item[data-id='#{ctx.viewId}']"
        li?.click()
        await waitUntil (-> app._currentCustomView?.id == ctx.viewId)
      return

    if ctx.spaceId
      if app._currentSpace?.id != ctx.spaceId
        sp = (app._allSpaces or []).find (s) -> s.id == ctx.spaceId
        unless sp
          await app.loadSpaces()
          sp = (app._allSpaces or []).find (s) -> s.id == ctx.spaceId
        app.selectSpace sp if sp
        await waitUntil (-> app._currentSpace?.id == ctx.spaceId)

  _refreshAfterApply: (app, context) ->
    return unless app
    if context?.viewId
      if app._currentCustomView?.yaml?
        app._renderCustomViewPreview app._currentCustomView.yaml
    else
      if app._activeDataView?.load?
        await app._activeDataView.load()

  _applyAction: (app, direction) ->
    stackFrom = if direction == 'undo' then @_undoStack else @_redoStack
    stackTo = if direction == 'undo' then @_redoStack else @_undoStack
    return false unless stackFrom.length > 0

    action = stackFrom[stackFrom.length - 1]
    await @_navigateToContext app, action.context

    plan = @_buildPlan action, direction
    verdict = await @_verifyPlan plan
    unless verdict.ok
      action.blockedReason = verdict.message
      await @refreshUI app
      return false

    await @_executePlan plan
    action.blockedReason = null
    stackFrom.pop()
    stackTo.push action
    await @_refreshAfterApply app, action.context
    await @refreshUI app
    true

  undo: (app) ->
    try
      await @_applyAction app, 'undo'
    catch e
      console.error 'undo failed', e
      await @refreshUI app
      false

  redo: (app) ->
    try
      await @_applyAction app, 'redo'
    catch e
      console.error 'redo failed', e
      await @refreshUI app
      false

  peekUndoStatus: ->
    return { available: false, blocked: false, message: '' } unless @_undoStack.length > 0
    action = @_undoStack[@_undoStack.length - 1]
    plan = @_buildPlan action, 'undo'
    verdict = await @_verifyPlan plan
    {
      available: true
      blocked: not verdict.ok
      message: if verdict.ok then '' else verdict.message
    }

  _isEditableTarget: (target) ->
    return false unless target
    tag = (target.tagName or '').toUpperCase()
    return true if tag in ['INPUT', 'TEXTAREA', 'SELECT']
    return true if target.isContentEditable
    return true if target.closest? '.CodeMirror'
    false

  bindGlobalShortcuts: (app) ->
    return if @_keyboardBound
    @_keyboardBound = true
    document.addEventListener 'keydown', (e) =>
      return if @_isEditableTarget e.target
      mod = e.ctrlKey or e.metaKey
      return unless mod
      key = String(e.key or '').toLowerCase()
      isUndo = key == 'z' and not e.shiftKey
      isRedo = key == 'y' or (key == 'z' and e.shiftKey)
      return unless isUndo or isRedo
      e.preventDefault()
      e.stopPropagation()
      if isUndo then @undo(app) else @redo(app)

  refreshUI: (app) ->
    return unless app
    undoBtn = app.el.undoBtn?()
    redoBtn = app.el.redoBtn?()

    if undoBtn
      undoBtn.classList.remove 'toolbar-btn--blocked'
      undoBtn.disabled = true
      undoBtn.title = 'Annuler'
      if @_undoStack.length > 0
        status = await @peekUndoStatus()
        undoBtn.disabled = status.blocked
        if status.blocked
          undoBtn.classList.add 'toolbar-btn--blocked'
          undoBtn.title = "Annulation bloquée : #{status.message}"
        else
          undoBtn.title = 'Annuler (Ctrl/Cmd+Z)'

    if redoBtn
      redoBtn.disabled = @_redoStack.length == 0
      redoBtn.title = if @_redoStack.length > 0 then 'Rétablir (Ctrl/Cmd+Shift+Z)' else 'Rétablir'
