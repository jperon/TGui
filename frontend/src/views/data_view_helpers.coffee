# data_view_helpers.coffee — utility methods extracted from views/data_view.coffee
# (error banner, column-width persistence, cell coercion, default values).
# Loaded after data_view.js and extends DataView.prototype. No functional change.

# Un tri est une liste de { column, ascending }. On ignore la colonne technique
# `sortKey` que Toast UI Grid utilise pour représenter « aucun tri ».
normalizeSortEntries = (entries) ->
  out = []
  return out unless Array.isArray entries
  for entry in entries
    continue unless entry
    name = entry.column ? entry.columnName
    continue unless name
    continue if name == 'sortKey'
    out.push { column: String(name), ascending: !!entry.ascending }
  out

Object.assign window.DataView::,
  setDefaultValues: (values) ->
    @_defaultValues = values or {}

  setFilter: (filter) ->
    @filter = filter
    @_applyData()

  # Marque une ligne comme active (classe CSS) sans voler le focus clavier ni
  # ouvrir l'édition d'une cellule. Une seule ligne active par grille.
  setActiveRow: (rowKey) ->
    return unless @_grid
    if @_activeRowKey? and @_activeRowKey != rowKey
      @_grid.removeRowClassName @_activeRowKey, 'tdb-selected-row'
    @_activeRowKey = null
    return unless rowKey?
    @_grid.addRowClassName rowKey, 'tdb-selected-row'
    @_activeRowKey = rowKey

  setFormulaFilter: (formula) ->
    @_formulaFilter = formula or ''
    @load()

  # ── Tri persistant ───────────────────────────────────────────────────────────
  # `grid.resetData` remet le tri interne de Toast UI Grid à « sortKey » : un tri
  # appliqué par un préréglage serait donc perdu au moindre rechargement (filtre
  # modifié, données rechargées). On garde le tri demandé et on le réapplique
  # après chaque resetData (voir _applyData dans views/data_view.coffee).
  getSortEntries: ->
    (@_sortState or []).slice()

  applySortEntries: (entries) ->
    @_sortState = normalizeSortEntries entries
    @_applySortState()
    @_pinSentinelLast()
    @_sortState

  _sortEntriesFromGrid: ->
    return [] unless @_grid and typeof @_grid.getSortState == 'function'
    state = null
    try
      state = @_grid.getSortState()
    catch e
      state = null
    normalizeSortEntries state?.columns

  _applySortState: ->
    return unless @_grid
    entries = @_sortState or []
    @_applyingSort = true
    try
      @_grid.unsort?()
      for entry, i in entries
        @_grid.sort? entry.column, entry.ascending, i > 0
    finally
      @_applyingSort = false

  # Tri/retri manuel (clic sur un en-tête) : mémoriser l'état réel de la grille
  # pour qu'il survive au prochain rechargement. Ignoré pendant nos propres
  # réapplications, sinon la remise à zéro de resetData écraserait le tri.
  _onGridSortChanged: ->
    return if @_applyingSort
    @_sortState = @_sortEntriesFromGrid()
    @_pinSentinelLast()
    @_onSortChanged?()
    @_sortState

  # Toast UI Grid trie TOUTES les lignes, sentinelle comprise, et inverse même le
  # résultat d'un comparateur en tri descendant : aucun comparateur ne peut donc
  # la maintenir en fin de grille. On réinjecte l'ordre obtenu par la grille en
  # terminant par la sentinelle. Le `sortState` transmis à `resetData` ne sert
  # qu'à réafficher les flèches d'en-tête : il ne réordonne pas les lignes (cf.
  # la documentation de `resetData` dans Toast UI Grid, options.sortState).
  _pinSentinelLast: ->
    grid = @_grid
    return unless grid and typeof grid.getData == 'function'
    data = grid.getData() or []
    sentinel = data.find (row) -> row?.__isNew
    return unless sentinel
    # Déjà en dernière position : rien à réordonner (cas sans tri).
    return if data[data.length - 1]?.__isNew
    ordered = (row for row in data when not row?.__isNew)
    ordered.push sentinel
    options = {}
    first = (@_sortState or [])[0]
    if first
      options.sortState =
        columnName: first.column
        ascending:  first.ascending
        multiple:   (@_sortState or []).length > 1
    grid.resetData ordered, options
    @_currentData = ordered
    @_activeRowKey = null

  # ── Error display ─────────────────────────────────────────────────────────────
  _showError: (msg) ->
    unless @_errorBanner
      @_errorBanner = document.createElement 'div'
      @_errorBanner.className = 'data-view-error-banner'
      close = document.createElement 'button'
      close.textContent = '✕'
      close.onclick = => @_clearError()
      @_errorBanner.appendChild close
      @_errorText = document.createElement 'span'
      @_errorBanner.appendChild @_errorText
      @container.insertBefore @_errorBanner, @container.firstChild
    @_errorText.textContent = msg
    @_errorBanner.classList.remove 'hidden'
    clearTimeout @_errorTimer
    @_errorTimer = setTimeout (=> @_clearError()), 6000

  _clearError: ->
    @_errorBanner?.classList.add 'hidden'

  # ── Column width persistence ──────────────────────────────────────────────────
  _lsKey: -> "tdb_colwidths_#{@space.id}"

  _loadColWidths: ->
    local = {}
    try
      local = JSON.parse(localStorage.getItem(@_lsKey()) or '{}')
    catch
      local = {}

    try
      data = await GQL.query GRID_COL_PREFS_QUERY, { spaceId: @space.id }
      remote = data.gridColumnPrefs or {}
      prefs = if Object.keys(remote).length > 0 then remote else local
      @_colWidthsCache = prefs
      localStorage.setItem @_lsKey(), JSON.stringify(prefs)
      prefs
    catch
      @_colWidthsCache = local
      local

  _saveColWidths: (prefs) ->
    isAdmin = !!(window.Auth?.isAdmin?() and window.Auth.isAdmin())
    try
      await GQL.mutate SAVE_GRID_COL_PREFS_MUTATION, {
        spaceId: @space.id
        prefs: prefs or {}
        asDefault: if isAdmin then true else false
      }
    catch e
      console.warn 'saveGridColumnPrefs failed, local fallback only:', e
    localStorage.setItem @_lsKey(), JSON.stringify(prefs or {})

  _columnWidth: (field, saved) ->
    v = saved[field.name]
    return Number(v) if v? and not Number.isNaN Number(v)
    return 72 if field.name == 'id'
    return 72 if field.fieldType == 'Boolean'
    160

  _toBoolean: (v) ->
    return true if v == true
    s = String(v ? '').toLowerCase()
    s == 'true' or s == '1' or s == 'yes' or s == 'on'

  _coerceCellValue: (fieldName, value, boolNames = null) ->
    if @_fkMaps[fieldName]? and value? and value != ''
      return Number(value)
    boolSet = boolNames or new Set (f.name for f in (@space.fields or []) when f.fieldType == 'Boolean')
    if boolSet.has(fieldName)
      return @_toBoolean value
    value

  _serializeRowForMutation: (row, colNames = null, boolNames = null) ->
    names = colNames or (f.name for f in (@space.fields or []) when f.fieldType != 'Sequence' and not (f.formula and f.formula != '' and not f.triggerFields))
    out = {}
    for name in names
      out[name] = @_coerceCellValue name, row?[name], boolNames
    out

  _cloneJson: (obj) ->
    JSON.parse JSON.stringify(obj ? {})

  _extractInsertedRecords: (results) ->
    out = []
    for r in (results or [])
      rec = r?.insertRecord
      continue unless rec?.id
      parsed = if typeof rec.data == 'string' then JSON.parse(rec.data) else rec.data
      out.push
        id: String(rec.id)
        after: parsed or {}
    out

  _actionContext: ->
    if window.AppUndoHelpers?.currentContext?
      window.AppUndoHelpers.currentContext @space.id
    else
      { spaceId: @space.id, hash: window.location?.hash or '' }

  _defaultCellValue: (field) ->
    if field.fieldType == 'Boolean' then false else ''
