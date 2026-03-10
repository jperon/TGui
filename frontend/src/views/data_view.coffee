# data_view.coffee
# Raw data grid view using Toast UI Grid (tui.Grid).

RECORDS_QUERY = """
  query Records($spaceId: ID!, $limit: Int, $offset: Int, $filter: RecordFilter, $reprFormula: String, $reprLanguage: String) {
    records(spaceId: $spaceId, limit: $limit, offset: $offset, filter: $filter, reprFormula: $reprFormula, reprLanguage: $reprLanguage) {
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
    @_formulaFilter = ''     # Lua/MoonScript formula for server-side row filtering
    @_formulaTimer  = null   # debounce handle

   # Build FK display maps for all relation fields.
  _buildFkMaps: ->
    for rel in @_relations
      field = (@space.fields or []).find (f) -> f.id == rel.fromFieldId
      continue unless field
      try
        formula = rel.reprFormula?.trim() or null
        data    = await GQL.query RECORDS_QUERY, {
          spaceId:     rel.toSpaceId
          limit:       5000
          reprFormula: formula
          reprLanguage: if formula then 'moonscript' else null
        }
        records = data.records.items.map (r) ->
          parsed = if typeof r.data == 'string' then JSON.parse(r.data) else r.data
          Object.assign { __rowId: r.id }, parsed

        map     = {}
        options = []
        for rec in records
          display = if rec._repr?
            String rec._repr
          else
            String(rec.id ? rec[Object.keys(rec).find((k) -> k != '__rowId')] ? '')
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
    wrapper.tabIndex = -1   # focusable programmatically, invisible in tab order
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
          if typeof val == 'string'
            m = val.match /^\[ERROR\|(.*?)\|(.*)\]$/
            if m
              safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;')
              safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;')
              isInternal = safeShort.indexOf('inconnue') > -1
              cls = if isInternal then 'formula-error internal-error' else 'formula-error'
              return "<span class=\"#{cls}\" title=\"#{safeFull}\">⚠ #{safeShort}</span>"
            else if val.indexOf('[Erreur de formule:') == 0
              return "<span class=\"formula-error\" title=\"#{val.replace(/"/g, '&quot;')}\">⚠ Erreur</span>"
          fkMap[String val] ? String(val ? '')
        col.editor =
          type: 'select'
          options:
            listItems: fkOptions
      else
        col.editor = 'text' unless seqNames.has(f.name) or formulaNames.has(f.name)
        # Highlight formula errors in normal text columns
        col.formatter = (props) ->
          val = props.value
          if typeof val == 'string'
            m = val.match /^\[ERROR\|(.*?)\|(.*)\]$/
            if m
              safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;')
              safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;')
              isInternal = safeShort.indexOf('inconnue') > -1
              cls = if isInternal then 'formula-error internal-error' else 'formula-error'
              return "<span class=\"#{cls}\" title=\"#{safeFull}\">⚠ #{safeShort}</span>"
            else if val.indexOf('[Erreur de formule:') == 0
              return "<span class=\"formula-error\" title=\"#{val.replace(/"/g, '&quot;')}\">⚠ Erreur</span>"
          String(val ? '')
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

    # Tab / Shift+Tab: move to next/prev cell (all columns), wrapping at row
    # boundaries. Start editing only if the target cell is editable.
    # Listener on document (capture) so it fires even when focus is on wrapper
    # itself (non-editable cell); guarded by wrapper.contains(activeElement).
    editableCols = columns.filter((c) -> c.editor).map((c) -> c.name)
    allCols      = columns.map (c) -> c.name
    editableSet  = new Set editableCols

    moveTo = (rowKey, colName) =>
      setTimeout =>
        @_grid.focus rowKey, colName
        if editableSet.has colName
          @_grid.startEditing rowKey, colName
        else
          wrapper.focus()   # keep browser focus inside grid for non-editable cells
      , 0

    @_tabListener = (e) =>
      return unless e.key == 'Tab'
      return unless @_grid?
      return unless wrapper.contains document.activeElement
      cell = @_grid.getFocusedCell()
      return unless cell?.columnName
      colIdx = allCols.indexOf cell.columnName
      return if colIdx < 0
      
      rowIdx = @_grid.getIndexOfRow cell.rowKey
      rowCount = @_grid.getRowCount()

      # Let browser handle Tab/Shift+Tab if at start/end of grid
      if e.shiftKey
        return if colIdx == 0 and rowIdx == 0
      else
        return if colIdx == allCols.length - 1 and rowIdx == rowCount - 1

      e.preventDefault()
      e.stopImmediatePropagation()
      
      if e.shiftKey
        if colIdx > 0
          moveTo cell.rowKey, allCols[colIdx - 1]
        else if rowIdx > 0
          prevRow = @_grid.getRowAt rowIdx - 1
          moveTo prevRow.rowKey, allCols[allCols.length - 1]
      else
        if colIdx < allCols.length - 1
          moveTo cell.rowKey, allCols[colIdx + 1]
        else if rowIdx < rowCount - 1
          nextRow = @_grid.getRowAt rowIdx + 1
          moveTo nextRow.rowKey, allCols[0]
    document.addEventListener 'keydown', @_tabListener, true

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

    # Save current focus to restore it after resetData
    focus = @_grid?.getFocusedCell()
    if focus?.rowKey? and focus.columnName
      focusedRow = @_grid.getRow focus.rowKey
      if focusedRow
        @_lastFocus =
          rowId:      focusedRow.__rowId
          isNew:      focusedRow.__isNew
          columnName: focus.columnName

    fields       = @space.fields or []
    formulaNames = new Set (f.name for f in fields when f.formula and f.formula != '' and not f.triggerFields)

    if formulaNames.size > 0 and not @_formulaFilter
      # Use the space-specific dynamic resolver so formula fields are evaluated.
      tname      = gqlName @space.name
      fieldList  = (gqlName f.name for f in fields).join(' ')
      spaceQuery = "query { #{tname}(limit: 2000) { items { _id #{fieldList} } } }"
      try
        data = await GQL.query spaceQuery, {}
        return unless @_mounted
        @_rows = data[tname].items.map (item) ->
          row           = Object.assign {}, item
          row.__rowId   = item._id
          row
      catch e
        @_showError "Erreur de colonne calculée : #{e.message}"
        @_rows = []
    else
      gqlFilter = if @_formulaFilter then { formula: @_formulaFilter, language: 'moonscript' } else undefined
      try
        data = await GQL.query RECORDS_QUERY, { spaceId: @space.id, limit: 2000, filter: gqlFilter }
        return unless @_mounted
        @_rows  = data.records.items.map (r) ->
          parsed      = if typeof r.data == 'string' then JSON.parse(r.data) else r.data
          row         = Object.assign {}, parsed
          row.__rowId = r.id
          row
        document.getElementById('formula-filter-input')?.classList.remove 'input-error'
      catch e
        msg = if @_formulaFilter then "Erreur de filtre : #{e.message}" else "Erreur de chargement : #{e.message}"
        @_showError msg
        document.getElementById('formula-filter-input')?.classList.add 'input-error' if @_formulaFilter
        @_rows = []

    @_applyData()
    @_rows

  _applyData: ->
    return unless @_grid
    rows = @_rows
    if @filter
      rows = rows.filter (r) => String(r[@filter.field]) == String(@filter.value)
    
    sentinel = @_sentinel()
    @_currentData = rows.concat [sentinel]
    @_grid.resetData @_currentData

    # Restore focus if we have saved it
    if @_lastFocus
      { rowId, isNew, columnName } = @_lastFocus
      @_lastFocus = null
      
      # Find the new row object matching the old one
      targetRow = if isNew
        @_grid.getData().find (r) -> r.__isNew
      else if rowId
        @_grid.getData().find (r) -> r.__rowId == rowId
      else
        null

      if targetRow
        # Small delay to ensure TUI has finished DOM updates
        setTimeout (=> @_grid.focus targetRow.rowKey, columnName), 0

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
    ids = (row.__rowId for row in toDelete)
    Spaces.deleteRecords(@space.id, ids)
      .then(=> @load())
      .catch (err) => @_showError "Erreur suppression : #{err.message}"

  setDefaultValues: (values) ->
    @_defaultValues = values or {}

  setFilter: (filter) ->
    @filter = filter
    @_applyData()

  setFormulaFilter: (formula) ->
    @_formulaFilter = formula or ''
    @load()

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
    clearTimeout @_formulaTimer
    document.removeEventListener 'keydown', @_pasteListener if @_pasteListener
    document.removeEventListener 'keydown', @_tabListener,  true if @_tabListener
    @_grid?.destroy()
    @_grid = null
    @_currentData = []
    @_rows = []
    @container.innerHTML = ''
