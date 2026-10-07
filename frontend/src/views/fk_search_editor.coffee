# fk_search_editor.coffee — fuzzy-search editor for foreign-key cells.
# Extracted from frontend/src/views/data_view.coffee (no functional change).
# Exposed on window because DataView (data_view.js) references it.

_fkSearchEditorSeq = 0

window.FkSearchEditor = class FkSearchEditor
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

