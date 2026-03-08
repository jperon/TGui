# data_view.coffee
# Raw data grid view using Toast UI Grid (tui.Grid).

RECORDS_QUERY = """
  query Records($spaceId: ID!, $limit: Int, $offset: Int) {
    records(spaceId: $spaceId, limit: $limit, offset: $offset) {
      items { id data }
      total
    }
  }
"""

# Convert a space name to a valid GraphQL identifier (mirrors backend gql_name).
gqlName = (name) ->
  s = name.replace(/[^\w]/g, '_')
  if /^\d/.test(s) then '_' + s else s

INSERT_RECORD = """
  mutation InsertRecord($spaceId: ID!, $data: JSON!) {
    insertRecord(spaceId: $spaceId, data: $data) { id data }
  }
"""

UPDATE_RECORD = """
  mutation UpdateRecord($spaceId: ID!, $id: ID!, $data: JSON!) {
    updateRecord(spaceId: $spaceId, id: $id, data: $data) { id data }
  }
"""

DELETE_RECORD = """
  mutation DeleteRecord($spaceId: ID!, $id: ID!) {
    deleteRecord(spaceId: $spaceId, id: $id)
  }
"""

window.DataView = class DataView
  constructor: (@container, @space, @filter = null, relations = []) ->
    @_grid          = null   # tui.Grid instance
    @_rows          = []     # rows from server
    @_currentData   = []     # rows currently displayed (filtered + sentinel)
    @_defaultValues = {}     # FK defaults for new records (set by depends_on)
    @_mounted       = false  # true after mount() completes, false after unmount()
    @_relations     = relations
    @_fkMaps        = {}     # field name → { id → display label }
    @_fkOptions     = {}     # field name → [{ text, value }]

  # Build FK display maps for all relation fields.
  _buildFkMaps: ->
    for rel in @_relations
      field = (@space.fields or []).find (f) -> f.id == rel.fromFieldId
      continue unless field
      try
        data    = await GQL.query RECORDS_QUERY, { spaceId: rel.toSpaceId, limit: 5000 }
        records = data.records.items.map (r) ->
          parsed = if typeof r.data == 'string' then JSON.parse(r.data) else r.data
          Object.assign { __rowId: r.id }, parsed

        reprFn  = null
        formula = rel.reprFormula?.trim()
        if formula
          try
            reprFn = new Function('row', "try { return String(#{formula}); } catch(e) { return String(row.id || ''); }")
          catch
            reprFn = null

        map     = {}
        options = []
        for rec in records
          display = if reprFn
            reprFn rec
          else if rec._repr?
            String rec._repr
          else
            String(rec.id ? rec[Object.keys(rec)[0]] ? '')
          # FK columns store the integer sequence value (rec.id), not the Tarantool UUID
          fkId = rec.id ? rec[Object.keys(rec).find (k) -> k != '__rowId']
          map[String fkId] = display
          options.push { text: display, value: String(fkId) }

        options.sort (a, b) -> a.text.localeCompare b.text

        @_fkMaps[field.name]    = map
        @_fkOptions[field.name] = options
      catch e
        console.warn "FK map build failed for #{field.name}:", e

  mount: ->
    @_mounted = true
    @container.innerHTML = ''
    wrapper = document.createElement 'div'
    wrapper.style.cssText = 'width:100%;height:100%;'
    @container.appendChild wrapper

    fields   = @space.fields or []
    seqNames     = new Set (f.name for f in fields when f.fieldType == 'Sequence')
    formulaNames = new Set (f.name for f in fields when f.formula and f.formula != '' and not f.triggerFields)
    saved    = @_loadColWidths()

    await @_buildFkMaps() if @_relations?.length > 0

    columns = for f in fields
      col =
        name:      f.name
        header:    f.name
        width:     saved[f.name] or 160
        minWidth:  40
        resizable: true
        sortable:  true
      if @_fkMaps[f.name]?
        fkMap     = @_fkMaps[f.name]
        fkOptions = @_fkOptions[f.name] or []
        col.formatter = do (fkMap) -> (props) ->
          val = props.value
          fkMap[String val] ? String(val ? '')
        col.editor =
          type: 'select'
          options:
            listItems: fkOptions
      else
        col.editor = 'text' unless seqNames.has(f.name) or formulaNames.has(f.name)
      col

    @_grid = new tui.Grid
      el:           wrapper
      columns:      columns
      data:         []
      bodyHeight:   'fitToParent'
      rowHeight:    28
      minRowHeight: 28
      header:       { height: 28 }
      rowHeaders:   ['checkbox']
      scrollX:      true
      scrollY:      true
      copyOptions:  { useFormattedValue: true }

    # Detect Ctrl+V to distinguish paste from manual edit on the sentinel
    @_pasting = false
    @_pasteListener = (e) =>
      if e.key == 'v' and (e.ctrlKey or e.metaKey)
        @_pasting = true
        setTimeout (=> @_pasting = false), 300
    document.addEventListener 'keydown', @_pasteListener

    # Persist column widths on resize
    @_grid.on 'columnResized', ({ columnName, width }) =>
      saved2 = @_loadColWidths()
      saved2[columnName] = width
      localStorage.setItem @_lsKey(), JSON.stringify(saved2)

    # Tab / Shift+Tab: move to next/prev editable cell on the same row,
    # wrapping to the next/prev row at row boundaries.
    # Use capture phase to intercept before tui.Grid's own Tab handler.
    editableCols = columns.filter((c) -> c.editor).map((c) -> c.name)
    wrapper.addEventListener 'keydown', (e) =>
      return unless e.key == 'Tab'
      cell = @_grid.getFocusedCell()
      return unless cell?.columnName
      idx = editableCols.indexOf cell.columnName
      return if idx < 0
      e.preventDefault()
      e.stopImmediatePropagation()
      rowIdx  = @_grid.getIndexOfRow cell.rowKey
      rowCount = @_grid.getRowCount()
      if e.shiftKey
        if idx > 0
          # Previous column, same row
          setTimeout =>
            @_grid.focus cell.rowKey, editableCols[idx - 1]
            @_grid.startEditing cell.rowKey, editableCols[idx - 1]
          , 0
        else if rowIdx > 0
          # Last column of previous row (skip sentinel at end)
          prevRow = @_grid.getRowAt rowIdx - 1
          unless prevRow?.__isNew
            setTimeout =>
              @_grid.focus prevRow.rowKey, editableCols[editableCols.length - 1]
              @_grid.startEditing prevRow.rowKey, editableCols[editableCols.length - 1]
            , 0
      else
        if idx < editableCols.length - 1
          # Next column, same row
          setTimeout =>
            @_grid.focus cell.rowKey, editableCols[idx + 1]
            @_grid.startEditing cell.rowKey, editableCols[idx + 1]
          , 0
        else
          # First column of next row (skip sentinel)
          nextRow = @_grid.getRowAt rowIdx + 1
          if nextRow? and not nextRow.__isNew
            setTimeout =>
              @_grid.focus nextRow.rowKey, editableCols[0]
              @_grid.startEditing nextRow.rowKey, editableCols[0]
            , 0
    , true  # capture: true

    # Handle cell edits (single edit and paste)
    @_grid.on 'afterChange', (ev) =>
      changes = (ev.changes or []).filter (c) -> String(c.value) != String(c.prevValue)
      return unless changes.length
      # Group field changes by row
      byRow = {}
      for c in changes
        byRow[c.rowKey] ?= {}
        byRow[c.rowKey][c.columnName] = c.value

      colNames      = (f.name for f in fields when not seqNames.has(f.name) and not formulaNames.has(f.name))
      ops           = []
      sentinelPatch = null

      for own rk, patch of byRow
        # Convert FK string values back to numeric IDs before sending to backend
        for own name, val of patch
          if @_fkMaps[name]? and val? and val != ''
            patch[name] = Number(val)
        # Resolve actual row data from tui.Grid (rowKey ≠ array index after resetData)
        row = @_grid.getRow Number(rk)
        if row?.__isNew
          sentinelPatch = patch
        else if row?.__rowId
          ops.push GQL.mutate UPDATE_RECORD, { spaceId: @space.id, id: row.__rowId, data: JSON.stringify(patch) }

      # Insertion(s) from sentinel
      if sentinelPatch
        if @_pasting
          # Re-read clipboard to get all pasted rows (TUI only fills the one sentinel row)
          try
            clipText = await navigator.clipboard.readText()
            clipRows = clipText
              .replace(/\r\n/g, '\n').replace(/\r/g, '\n')
              .split('\n')
              .map (line) -> line.split('\t')
              .filter (cols) -> cols.some (c) -> c.trim()
            for clipRow in clipRows
              data = {}
              data[name] = clipRow[i] ? @_defaultValues[name] ? '' for name, i in colNames
              ops.push GQL.mutate INSERT_RECORD, { spaceId: @space.id, data: JSON.stringify(data) }
          catch clipErr
            console.warn 'clipboard unavailable, single insert fallback', clipErr
            data = {}
            data[n] = sentinelPatch[n] ? @_defaultValues[n] ? '' for n in colNames
            ops.push GQL.mutate INSERT_RECORD, { spaceId: @space.id, data: JSON.stringify(data) }
        else
          # Manual edit: insert from sentinel values + defaults
          data = {}
          data[n] = sentinelPatch[n] ? @_defaultValues[n] ? '' for n in colNames
          ops.push GQL.mutate INSERT_RECORD, { spaceId: @space.id, data: JSON.stringify(data) }

      Promise.all(ops).then(=> @load()).catch (err) =>
        @_showError "Erreur d'enregistrement : #{err.message}"

    await @load()

  # ── Data loading ─────────────────────────────────────────────────────────────
  _sentinel: ->
    row = { __isNew: true }
    for f in (@space.fields or [])
      unless f.fieldType == 'Sequence'
        row[f.name] = @_defaultValues[f.name] ? ''
    row

  load: ->
    return unless @_mounted
    fields       = @space.fields or []
    formulaNames = new Set (f.name for f in fields when f.formula and f.formula != '' and not f.triggerFields)

    if formulaNames.size > 0
      # Use the space-specific dynamic resolver so formula fields are evaluated.
      tname      = gqlName @space.name
      fieldList  = (gqlName f.name for f in fields).join(' ')
      spaceQuery = "query { #{tname}(limit: 2000) { items { _id #{fieldList} } } }"
      data       = await GQL.query spaceQuery, {}
      return unless @_mounted
      @_rows = data[tname].items.map (item) ->
        row           = Object.assign {}, item
        row.__rowId   = item._id
        row
    else
      data    = await GQL.query RECORDS_QUERY, { spaceId: @space.id, limit: 2000 }
      return unless @_mounted
      @_rows  = data.records.items.map (r) ->
        parsed      = if typeof r.data == 'string' then JSON.parse(r.data) else r.data
        row         = Object.assign {}, parsed
        row.__rowId = r.id
        row
    @_applyData()
    @_rows

  _applyData: ->
    return unless @_grid
    rows = @_rows
    if @filter
      rows = rows.filter (r) => String(r[@filter.field]) == String(@filter.value)
    @_currentData = rows.concat [@_sentinel()]
    @_grid.resetData @_currentData
    # Find the actual rowKey tui.Grid assigned to the sentinel (last visual row)
    lastIdx = @_currentData.length - 1
    sentinelRow = @_grid.getRowAt lastIdx
    if sentinelRow?
      @_grid.addRowClassName sentinelRow.rowKey, 'tdb-new-row'

  # ── Record actions ────────────────────────────────────────────────────────────
  insertBlank: ->
    fields       = @space.fields or []
    seqNames     = new Set (f.name for f in fields when f.fieldType == 'Sequence')
    formulaNames = new Set (f.name for f in fields when f.formula and f.formula != '' and not f.triggerFields)
    data         = {}
    data[f.name] = '' for f in fields when not seqNames.has(f.name) and not formulaNames.has(f.name)
    GQL.mutate(INSERT_RECORD, { spaceId: @space.id, data: JSON.stringify(data) })
      .then(=> @load())
      .catch (err) => @_showError "Erreur insertion : #{err.message}"

  deleteSelected: ->
    keys    = @_grid.getCheckedRowKeys()
    return unless keys.length
    # Filter out sentinel row
    toDelete = keys
      .map    (rk) => @_currentData[Number rk]
      .filter (row) -> row and not row.__isNew and row.__rowId
    return unless toDelete.length
    ops = toDelete.map (row) =>
      GQL.mutate DELETE_RECORD, { spaceId: @space.id, id: row.__rowId }
    Promise.all(ops).then(=> @load()).catch (err) => @_showError "Erreur suppression : #{err.message}"

  setDefaultValues: (values) ->
    @_defaultValues = values or {}

  setFilter: (filter) ->
    @filter = filter
    @_applyData()

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
    try JSON.parse(localStorage.getItem(@_lsKey()) or '{}') catch then {}

  # ── Cleanup ───────────────────────────────────────────────────────────────────
  unmount: ->
    @_mounted = false
    document.removeEventListener 'keydown', @_pasteListener if @_pasteListener
    @_grid?.destroy()
    @_grid = null
    @_currentData = []
    @_rows = []
    @container.innerHTML = ''
