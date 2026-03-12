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

GRID_COL_PREFS_QUERY = """
  query GridColumnPrefs($spaceId: ID!) {
    gridColumnPrefs(spaceId: $spaceId)
  }
"""

SAVE_GRID_COL_PREFS_MUTATION = """
  mutation SaveGridColumnPrefs($spaceId: ID!, $prefs: JSON!, $asDefault: Boolean) {
    saveGridColumnPrefs(spaceId: $spaceId, prefs: $prefs, asDefault: $asDefault)
  }
"""

_fkSearchEditorSeq = 0

class FkSearchEditor
  constructor: (props) ->
    listItems = props?.columnInfo?.editor?.options?.items or props?.columnInfo?.editor?.options?.listItems or []
    value = props?.value
    @el = document.createElement 'input'
    @el.type = 'text'
    @el.className = 'tui-grid-content-text'
    @el.style.width = '100%'
    @el.style.boxSizing = 'border-box'
    @el.autocomplete = 'off'
    @el.spellcheck = false

    @labelToValue = {}
    @valueToLabel = {}
    @items = []
    for item in listItems
      label = String(item?.text ? '')
      raw = item?.value
      val = if raw? then String(raw) else ''
      @labelToValue[label] = val
      @valueToLabel[val] = label unless @valueToLabel[val]?
      @items.push
        label: label
        value: val
        norm: @_normalize(label)

    current = if value? then String(value) else ''
    @initialValue = current
    @el.value = @valueToLabel[current] ? current
    @selectedIndex = 0
    @visibleItems = []
    @menuVisible = false

    @menu = document.createElement 'div'
    _fkSearchEditorSeq += 1
    @menu.id = "fk-editor-menu-#{_fkSearchEditorSeq}"
    @menu.className = 'fk-editor-menu'
    @menu.style.cssText = [
      'position:fixed'
      'z-index:9999'
      'display:none'
      'max-height:220px'
      'overflow:auto'
      'background:#fff'
      'color:#1f2937'
      'border:1px solid #d1d5db'
      'border-radius:6px'
      'box-shadow:0 8px 20px rgba(0,0,0,0.12)'
    ].join ';'

    onKeyDown = (ev) =>
      if ev.key == 'Escape'
        @el.value = @valueToLabel[@initialValue] ? @initialValue
        @_hideMenu()
        ev.preventDefault()
        ev.stopPropagation()
      else if ev.key == 'ArrowDown'
        @_moveSelection 1
        ev.preventDefault()
        ev.stopPropagation()
      else if ev.key == 'ArrowUp'
        @_moveSelection -1
        ev.preventDefault()
        ev.stopPropagation()
      else if ev.key == 'Enter'
        if @menuVisible and @visibleItems.length > 0
          @_applySelection @selectedIndex
        @_hideMenu()
        ev.preventDefault()
        ev.stopPropagation()
    @onKeyDown = onKeyDown
    @onInput = => @_renderMenu @el.value
    @onFocus = => @_renderMenu @el.value
    @onBlur = =>
      setTimeout (=> @_hideMenu()), 120
    @onWindowChange = => @_positionMenu() if @menuVisible
    @el.addEventListener 'keydown', @onKeyDown
    @el.addEventListener 'input', @onInput
    @el.addEventListener 'focus', @onFocus
    @el.addEventListener 'blur', @onBlur

  getElement: ->
    @el

  mounted: ->
    if @menu and not @menu.parentNode
      document.body.appendChild @menu
    window.addEventListener 'resize', @onWindowChange
    window.addEventListener 'scroll', @onWindowChange, true
    setTimeout (=> @el?.focus()), 0
    setTimeout (=> @el?.select()), 0
    setTimeout (=> @_renderMenu @el?.value), 0

  getValue: ->
    typed = String(@el?.value ? '').trim()
    return '' if typed == ''
    return @labelToValue[typed] if @labelToValue[typed]?
    if @menuVisible and @visibleItems.length > 0
      chosen = @visibleItems[@selectedIndex]
      return String(chosen?.value ? '') if chosen?
    if /^\d+$/.test typed
      return typed
    best = @_filterItems(typed)[0]
    return String(best?.value ? '')

  beforeDestroy: ->
    @el?.removeEventListener 'keydown', @onKeyDown if @onKeyDown
    @el?.removeEventListener 'input', @onInput if @onInput
    @el?.removeEventListener 'focus', @onFocus if @onFocus
    @el?.removeEventListener 'blur', @onBlur if @onBlur
    window.removeEventListener 'resize', @onWindowChange if @onWindowChange
    window.removeEventListener 'scroll', @onWindowChange, true if @onWindowChange
    if @menu?.parentNode
      @menu.parentNode.removeChild @menu

  _normalize: (s) ->
    String(s ? '')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')

  _fuzzyScore: (query, target) ->
    return 0 if query == ''
    idx = target.indexOf query
    if idx >= 0
      return 200 - idx * 4 - (target.length - query.length)
    q = 0
    score = 0
    prev = -1
    i = 0
    while i < target.length and q < query.length
      if target[i] == query[q]
        score += 4
        score += 3 if prev >= 0 and i == prev + 1
        score += 2 if i == q
        prev = i
        q += 1
      i += 1
    return null unless q == query.length
    score - (target.length - query.length)

  _filterItems: (query) ->
    q = @_normalize(String(query ? '').trim())
    return @items.slice(0, 25) if q == ''
    scored = []
    for item in @items
      s = @_fuzzyScore q, item.norm
      continue unless s?
      scored.push { item, score: s }
    scored.sort (a, b) ->
      if b.score != a.score then b.score - a.score else a.item.label.localeCompare b.item.label
    scored.slice(0, 25).map (x) -> x.item

  _renderMenu: (query) ->
    @visibleItems = @_filterItems query
    if @visibleItems.length == 0
      @_hideMenu()
      return
    @selectedIndex = Math.min @selectedIndex, @visibleItems.length - 1
    @selectedIndex = 0 if @selectedIndex < 0
    @menu.innerHTML = ''
    for item, idx in @visibleItems
      row = document.createElement 'div'
      row.textContent = item.label
      row.dataset.idx = String idx
      row.style.cssText = [
        'padding:6px 10px'
        'cursor:pointer'
        'white-space:nowrap'
        if idx == @selectedIndex then 'background:#eef2ff' else ''
      ].join ';'
      row.addEventListener 'mouseenter', do (idx) => => @selectedIndex = idx
      row.addEventListener 'mousedown', do (idx) => (ev) =>
        ev.preventDefault()
        @_applySelection idx
      @menu.appendChild row
    @_positionMenu()
    @_showMenu()

  _positionMenu: ->
    return unless @el and @menu
    rect = @el.getBoundingClientRect()
    @menu.style.left = "#{Math.round(rect.left)}px"
    @menu.style.top = "#{Math.round(rect.bottom + 2)}px"
    @menu.style.minWidth = "#{Math.max(220, Math.round(rect.width))}px"

  _showMenu: ->
    return unless @menu
    @menu.style.display = 'block'
    @menuVisible = true

  _hideMenu: ->
    return unless @menu
    @menu.style.display = 'none'
    @menuVisible = false

  _moveSelection: (delta) ->
    return unless @visibleItems.length > 0
    @selectedIndex = (@selectedIndex + delta + @visibleItems.length) % @visibleItems.length
    @_renderMenu @el?.value
    row = @menu?.querySelector? "[data-idx='#{@selectedIndex}']"
    row?.scrollIntoView? block: 'nearest'

  _applySelection: (idx) ->
    item = @visibleItems[idx]
    return unless item
    @selectedIndex = idx
    @el.value = item.label
    @_hideMenu()

window.DataView = class DataView
  constructor: (@container, @space, @filter = null, relations = [], opts = {}) ->
    @_grid          = null   # tui.Grid instance
    @_rows          = []     # rows from server
    @_currentData   = []     # rows currently displayed (filtered + sentinel)
    @_defaultValues = {}     # FK defaults for new records (set by depends_on)
    @_mounted       = false  # true after mount() completes, false after unmount()
    @_relations     = relations
    @onColumnFocus  = opts.onColumnFocus if typeof opts.onColumnFocus == 'function'
    @_fkMaps        = {}     # field name → { id → display label }
    @_fkOptions     = {}     # field name → [{ text, value }]
    @_formulaFilter = ''     # Lua/MoonScript formula for server-side row filtering
    @_formulaTimer  = null   # debounce handle
    @_focusedColumnName = null
    @_colWidthsCache = {}
    @_saveWidthsTimer = null

   # Build FK display maps for all relation fields.
  _buildFkMaps: ->
    for rel in @_relations
      field = (@space.fields or []).find (f) -> f.id == rel.fromFieldId
      continue unless field
      try
        formula = rel.reprFormula?.trim() or '@_repr'
        data    = await GQL.query RECORDS_QUERY, {
          spaceId:     rel.toSpaceId
          limit:       5000
          reprFormula: formula
          reprLanguage: 'moonscript'
        }
        records = data.records.items.map (r) ->
          parsed = if typeof r.data == 'string' then JSON.parse(r.data) else r.data
          Object.assign { __rowId: r.id }, parsed

        map     = {}
        options = []
        for rec in records
          display = if rec._repr? and String(rec._repr).trim() != ''
            String rec._repr
          else
            String(rec.id ? rec.__rowId ? rec[Object.keys(rec).find((k) -> k != '__rowId')] ? '')
          fkId = rec.id ? rec.__rowId ? rec[Object.keys(rec).find (k) -> k != '__rowId']
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
    boolNames    = new Set (f.name for f in fields when f.fieldType == 'Boolean')
    formulaNames = new Set (f.name for f in fields when f.formula and f.formula != '' and not f.triggerFields)
    escapeHtml = (s) => @_escapeHtml s
    toBool = (v) => @_toBoolean v
    saved    = await @_loadColWidths()

    await @_buildFkMaps() if @_relations?.length > 0

    columns = for f in fields
      col =
        name:      f.name
        header:    f.name
        width:     @_columnWidth f, saved
        minWidth:  40
        resizable: true
        sortable:  true
      if @_fkMaps[f.name]?
        fkMap     = @_fkMaps[f.name]
        fkOptions = @_fkOptions[f.name] or []
        col.formatter = do (fkMap) => (props) =>
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
          display = fkMap[String val] ? String(val ? '')
          escapeHtml display
        col.editor =
          type: FkSearchEditor
          options:
            items: fkOptions
      else
        if boolNames.has f.name
          col.align = 'center'
          col.editor =
            type: 'checkbox'
            options:
              listItems: [{ text: '', value: 'true' }]
          col.editor = null if seqNames.has(f.name) or formulaNames.has(f.name)
          col.formatter = do (fieldName = f.name) => (props) =>
            row = props.row
            val = props.value
            displayVal = if row["_repr_#{fieldName}"]? then row["_repr_#{fieldName}"] else val
            if typeof displayVal == 'string'
              m = displayVal.match /^\[ERROR\|(.*?)\|(.*)\]$/
              if m
                safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;')
                safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;')
                isInternal = safeShort.indexOf('inconnue') > -1
                cls = if isInternal then 'formula-error internal-error' else 'formula-error'
                return "<span class=\"#{cls}\" title=\"#{safeFull}\">⚠ #{safeShort}</span>"
            if toBool(displayVal) then '☑' else '☐'
        else
          col.editor = 'text' unless seqNames.has(f.name) or formulaNames.has(f.name)
          # Highlight formula errors in normal text columns
          col.formatter = do (fieldName = f.name) => (props) =>
            row = props.row
            val = props.value
            displayVal = val
            # Use per-field representation if available from backend
            if row["_repr_#{fieldName}"]?
              displayVal = row["_repr_#{fieldName}"]

            if typeof displayVal == 'string'
              m = displayVal.match /^\[ERROR\|(.*?)\|(.*)\]$/
              if m
                safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;')
                safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;')
                isInternal = safeShort.indexOf('inconnue') > -1
                cls = if isInternal then 'formula-error internal-error' else 'formula-error'
                return "<span class=\"#{cls}\" title=\"#{safeFull}\">⚠ #{safeShort}</span>"
              else if displayVal.indexOf('[Erreur de formule:') == 0
                return "<span class=\"formula-error\" title=\"#{displayVal.replace(/"/g, '&quot;')}\">⚠ Erreur</span>"
            safe = escapeHtml String(displayVal ? '')
            "<span class=\"tdb-cell-text\" data-full-text=\"#{safe}\">#{safe}</span>"
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
      saved2 = Object.assign {}, @_colWidthsCache
      saved2[columnName] = width
      @_colWidthsCache = saved2
      clearTimeout @_saveWidthsTimer
      @_saveWidthsTimer = setTimeout (=> @_saveColWidths saved2), 150

    setFocusedColumn = (colName) =>
      return unless colName
      @_focusedColumnName = colName
      @onColumnFocus? colName

    @_grid.on 'focusChange', (ev) =>
      setFocusedColumn ev.columnName

    @_grid.on 'click', (ev) =>
      setFocusedColumn ev.columnName if ev?.columnName

    @_grid.on 'mouseover', (ev) =>
      return unless ev?.targetType == 'cell'
      cellEl = ev.nativeEvent?.target?.closest? '.tui-grid-cell'
      return unless cellEl
      textEl = cellEl.querySelector '.tdb-cell-text'
      return unless textEl
      fullText = textEl.getAttribute('data-full-text') or textEl.textContent or ''
      if textEl.scrollWidth > textEl.clientWidth + 1
        cellEl.setAttribute 'title', fullText
      else
        cellEl.removeAttribute 'title'

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
      prevByRow = {}
      for c in changes
        byRow[c.rowKey] ?= {}
        prevByRow[c.rowKey] ?= {}
        byRow[c.rowKey][c.columnName] = c.value
        prevByRow[c.rowKey][c.columnName] = c.prevValue

      colNames      = (f.name for f in fields when not seqNames.has(f.name) and not formulaNames.has(f.name))
      ops           = []
      sentinelPatch = null
      action =
        spaceId: @space.id
        context: @_actionContext()
        updates: []
        inserts: []
        deletes: []

      for own rk, patch of byRow
        # Convert FK string values back to numeric IDs before sending to backend
        for own name, val of patch
          if @_fkMaps[name]? and val? and val != ''
            patch[name] = Number(val)
          if boolNames.has(name)
            patch[name] = @_toBoolean val
        # Resolve actual row data from tui.Grid (rowKey ≠ array index after resetData)
        row = @_grid.getRow Number(rk)
        if row?.__isNew
          sentinelPatch = patch
        else if row?.__rowId
          beforeData = {}
          afterData = {}
          for own n, prevVal of (prevByRow[rk] or {})
            beforeData[n] = @_coerceCellValue n, prevVal, boolNames
            afterData[n] = @_coerceCellValue n, row?[n], boolNames
          action.updates.push
            id: String(row.__rowId)
            before: beforeData
            after: afterData
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

      Promise.all(ops).then((results) =>
        action.inserts = @_extractInsertedRecords results
        if action.updates.length > 0 or action.inserts.length > 0
          window.AppUndoHelpers?.pushAction? action
        window.AppUndoHelpers?.refreshUI? window.App
        @load()
      ).catch (err) =>
        @_showError "Erreur d'enregistrement : #{err.message}"

    await @load()

  # ── Data loading ─────────────────────────────────────────────────────────────
  _sentinel: ->
    row = { __isNew: true }
    for f in (@space.fields or [])
      unless f.fieldType == 'Sequence'
        row[f.name] = @_defaultValues[f.name] ? @_defaultCellValue(f)
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
    reprNames    = new Set (f.name for f in fields when f.reprFormula and f.reprFormula != '')

    if (formulaNames.size > 0 or reprNames.size > 0) and not @_formulaFilter
      # Use the space-specific dynamic resolver so formula fields are evaluated.
      tname      = gqlName @space.name
      fieldList  = for f in fields
        nm = gqlName f.name
        if f.reprFormula and f.reprFormula != ''
          nm + " _repr_#{nm}"
        else
          nm
      fieldList = fieldList.join(' ')
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

    # Pre-calculate cell classes for formula errors
    for row in @_currentData
      row._attributes ?= {}
      row._attributes.className ?= {}
      row._attributes.className.column ?= {}
      for f in (@space.fields or [])
        val = row[f.name]
        displayVal = val
        if row["_repr_#{f.name}"]?
          displayVal = row["_repr_#{f.name}"]
        else if @_fkMaps[f.name]?
          displayVal = @_fkMaps[f.name][String val]
        if typeof displayVal == 'string'
          isError = displayVal.indexOf('[ERROR|') == 0 or displayVal.indexOf('[Erreur de formule:') == 0
          if isError
            row._attributes.className.column[f.name] ?= []
            row._attributes.className.column[f.name].push 'cell-formula-error'
            if displayVal.indexOf('inconnue') > -1
              row._attributes.className.column[f.name].push 'cell-formula-error-internal'

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
    data[f.name] = @_defaultCellValue(f) for f in fields when not seqNames.has(f.name) and not formulaNames.has(f.name)
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
    action =
      spaceId: @space.id
      context: @_actionContext()
      updates: []
      inserts: []
      deletes: (for row in toDelete
        id: String(row.__rowId)
        before: @_serializeRowForMutation row
      )
    Spaces.deleteRecords(@space.id, ids)
      .then(=>
        window.AppUndoHelpers?.pushAction? action if action.deletes.length > 0
        window.AppUndoHelpers?.refreshUI? window.App
        @load()
      )
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

  _escapeHtml: (s) ->
    String(s ? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')

  getFocusedColumnName: ->
    @_focusedColumnName

  # ── Cleanup ───────────────────────────────────────────────────────────────────
  unmount: ->
    @_mounted = false
    clearTimeout @_formulaTimer
    clearTimeout @_saveWidthsTimer
    document.removeEventListener 'keydown', @_pasteListener if @_pasteListener
    document.removeEventListener 'keydown', @_tabListener,  true if @_tabListener
    @_grid?.destroy()
    @_grid = null
    @_currentData = []
    @_rows = []
    @container.innerHTML = ''
