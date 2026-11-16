# view_presets_menu.coffee — menu « Trier / Filtrer » avec préréglages nommés.
#
# Module unique, réutilisé tel quel par la grille principale d'un espace et par
# chaque widget dataView d'une page (DRY). Il affiche :
#   - le tri courant (lu sur le DataView, qui le conserve après resetData) ;
#   - les préréglages nommés de la portée (filtre + tri) ;
#   - « Enregistrer sous… » (prompt du nom, puis saveViewPreset).
#
# Portées : `space:<spaceId>` pour la grille principale,
# `widget:<pageId>:<widgetId>` pour un widget de page.

VIEW_PRESETS_QUERY = """
  query ViewPresets($scope: String!, $spaceId: ID!) {
    viewPresets(scope: $scope, spaceId: $spaceId) {
      id scope spaceId name filter sort createdAt updatedAt
    }
  }
"""

SAVE_VIEW_PRESET_MUTATION = """
  mutation SaveViewPreset($scope: String!, $spaceId: ID!, $name: String!, $filter: String, $sort: String) {
    saveViewPreset(scope: $scope, spaceId: $spaceId, name: $name, filter: $filter, sort: $sort) {
      id scope spaceId name filter sort createdAt updatedAt
    }
  }
"""

DELETE_VIEW_PRESET_MUTATION = """
  mutation DeleteViewPreset($id: ID!) {
    deleteViewPreset(id: $id)
  }
"""

createEl = (tag, className, text) ->
  el = document.createElement tag
  el.className = className if className
  el.textContent = text if text?
  el

clearChildren = (el) ->
  el.removeChild el.children[0] while el.children and el.children.length > 0

# Un tri est une liste de { column, ascending }. On ignore la colonne technique
# `sortKey` que Toast UI Grid utilise pour représenter « aucun tri ».
normalizeEntries = (entries) ->
  out = []
  return out unless Array.isArray entries
  for entry in entries
    continue unless entry
    name = entry.column ? entry.columnName
    continue unless name
    continue if name == 'sortKey'
    out.push { column: String(name), ascending: !!entry.ascending }
  out

parseSort = (jsonText) ->
  return [] if jsonText == undefined or jsonText == null or jsonText == ''
  decoded = null
  try
    decoded = if typeof jsonText == 'string' then JSON.parse(jsonText) else jsonText
  catch e
    return []
  normalizeEntries decoded

serializeSort = (entries) -> JSON.stringify normalizeEntries(entries)

# Lit le tri courant. On privilégie le cache du DataView (qui survit aux
# resetData), et on retombe sur l'état brut de la grille pour un DataView
# minimal (tests, anciens objets).
sortEntriesFrom = (dv) ->
  return [] unless dv
  if typeof dv.getSortEntries == 'function'
    return normalizeEntries dv.getSortEntries()
  grid = dv._grid
  return [] unless grid and typeof grid.getSortState == 'function'
  state = null
  try
    state = grid.getSortState()
  catch e
    state = null
  normalizeEntries state?.columns

# Repli quand le DataView n'expose pas applySortEntries (objet factice).
applySortViaGrid = (dv, entries) ->
  grid = dv?._grid
  return unless grid
  grid.unsort?()
  for entry, i in normalizeEntries(entries)
    grid.sort? entry.column, entry.ascending, i > 0

window.ViewPresetsMenu =
  sortEntriesFrom: sortEntriesFrom
  normalizeEntries: normalizeEntries
  parseSort: parseSort
  serializeSort: serializeSort

  attach: (wrapEl, opts = {}) ->
    return null unless wrapEl
    wrapEl._viewPresetsMenu?.destroy?()

    wrapEl.classList.add 'view-presets-host'

    button = createEl 'button', 'toolbar-btn view-presets-btn no-drag', 'Trier / Filtrer'
    button.type = 'button'
    button.title = 'Trier / Filtrer — préréglages de vue'

    menu = createEl 'div', 'view-presets-menu no-drag hidden'
    errorEl = createEl 'div', 'view-presets-error hidden'

    sortSection = createEl 'div', 'view-presets-section'
    sortSection.appendChild createEl('div', 'view-presets-section-title', 'Tri courant')
    sortList = createEl 'div', 'view-presets-sort-list'
    sortSection.appendChild sortList

    presetSection = createEl 'div', 'view-presets-section'
    presetSection.appendChild createEl('div', 'view-presets-section-title', 'Préréglages')
    presetList = createEl 'div', 'view-presets-preset-list'
    presetSection.appendChild presetList

    actions = createEl 'div', 'view-presets-actions'
    saveBtn = createEl 'button', 'view-presets-save', 'Enregistrer sous…'
    saveBtn.type = 'button'
    actions.appendChild saveBtn

    menu.appendChild errorEl
    menu.appendChild sortSection
    menu.appendChild presetSection
    menu.appendChild actions

    wrapEl.appendChild button
    wrapEl.appendChild menu

    state = { presets: [], active: null, loaded: false }
    dataView = -> opts.getDataView?()
    isOpen = -> not menu.classList.contains 'hidden'

    updateButton = ->
      if state.active?.name
        button.textContent = "Trier / Filtrer · #{state.active.name}"
        button.classList.add 'active'
      else
        button.textContent = 'Trier / Filtrer'
        button.classList.remove 'active'

    showError = (message) ->
      errorEl.textContent = message
      errorEl.classList.remove 'hidden'

    clearError = -> errorEl.classList.add 'hidden'

    renderSort = ->
      clearChildren sortList
      entries = sortEntriesFrom dataView()
      if entries.length == 0
        sortList.appendChild createEl('div', 'view-presets-empty', 'Aucun tri (cliquez un en-tête de colonne)')
        return
      for entry in entries
        row = createEl 'div', 'view-presets-sort-row'
        row.dataset.column = entry.column
        label = createEl 'span', 'view-presets-sort-label',
          "#{entry.column} #{if entry.ascending then '↑' else '↓'}"
        removeBtn = createEl 'button', 'view-presets-remove', '✕'
        removeBtn.type = 'button'
        removeBtn.title = 'Retirer ce critère de tri'
        do (entry) ->
          removeBtn.addEventListener 'click', (ev) ->
            ev?.stopPropagation?()
            removeSortColumn entry.column
        row.appendChild label
        row.appendChild removeBtn
        sortList.appendChild row

    renderPresets = ->
      clearChildren presetList
      if state.presets.length == 0
        presetList.appendChild createEl('div', 'view-presets-empty', 'Aucun préréglage')
        return
      for preset in state.presets
        row = createEl 'div', 'view-presets-preset'
        row.dataset.id = preset.id
        row.classList.toggle 'active', state.active?.id == preset.id
        row.appendChild createEl('span', 'view-presets-preset-name', preset.name)
        delBtn = createEl 'button', 'view-presets-preset-delete', '✕'
        delBtn.type = 'button'
        delBtn.title = "Supprimer le préréglage « #{preset.name} »"
        do (preset, delBtn) ->
          row.addEventListener 'click', -> applyPreset preset
          delBtn.addEventListener 'click', (ev) ->
            ev?.stopPropagation?()
            deletePreset preset
        row.appendChild delBtn
        presetList.appendChild row

    matchesActive = ->
      return false unless state.active
      dv = dataView()
      return false unless dv
      currentFilter = (opts.filterInput?.value ? '').trim()
      return false unless currentFilter == (state.active.filter ? '').trim()
      serializeSort(sortEntriesFrom dv) == state.active.sort

    clearActive = ->
      return unless state.active
      state.active = null
      updateButton()
      renderPresets()

    syncActive = ->
      return unless state.active
      clearActive() unless matchesActive()

    loadPresets = ->
      unless window.GQL?.query
        showError 'Client GraphQL indisponible'
        return Promise.resolve state.presets
      unless opts.scope and opts.spaceId
        showError 'Portée du préréglage inconnue'
        return Promise.resolve state.presets
      window.GQL.query VIEW_PRESETS_QUERY, { scope: opts.scope, spaceId: opts.spaceId }
        .then (data) ->
          state.presets = (data?.viewPresets or []).slice()
          state.loaded = true
          clearError()
          renderPresets()
          state.presets
        .catch (err) ->
          showError (err?.message or String err)
          state.presets

    applyPreset = (preset) ->
      return unless preset
      dv = dataView()
      return unless dv
      entries = parseSort preset.sort
      filter = preset.filter ? ''
      state.active =
        id: preset.id
        name: preset.name
        filter: filter
        sort: serializeSort entries
      updateButton()
      if opts.filterInput
        opts.filterInput.value = filter
        opts.filterInput.classList.toggle 'active', filter.trim() != ''
      # Le tri est posé AVANT le rechargement du filtre : _applyData le
      # réapplique après resetData, sinon Toast UI Grid le perdrait.
      if typeof dv.applySortEntries == 'function'
        dv.applySortEntries entries
      else
        applySortViaGrid dv, entries
      dv.setFormulaFilter? filter
      clearError()
      renderSort()
      renderPresets()
      close()

    removeSortColumn = (column) ->
      dv = dataView()
      return unless dv
      entries = (e for e in sortEntriesFrom(dv) when e.column != column)
      if typeof dv.applySortEntries == 'function'
        dv.applySortEntries entries
      else
        applySortViaGrid dv, entries
      clearActive()
      renderSort()

    saveCurrent = ->
      dv = dataView()
      unless dv
        showError 'Aucune grille active'
        return Promise.resolve null
      unless window.GQL?.mutate
        showError 'Client GraphQL indisponible'
        return Promise.resolve null
      unless opts.scope and opts.spaceId
        showError 'Portée du préréglage inconnue'
        return Promise.resolve null
      entered = window.prompt? 'Nom du préréglage', (state.active?.name or '')
      return Promise.resolve null unless entered?.trim()
      name = entered.trim()
      filter = (opts.filterInput?.value ? '').trim()
      sort = serializeSort sortEntriesFrom(dv)
      window.GQL.mutate SAVE_VIEW_PRESET_MUTATION, {
        scope: opts.scope
        spaceId: opts.spaceId
        name: name
        filter: filter
        sort: sort
      }
        .then (data) ->
          saved = data?.saveViewPreset
          state.active =
            id: saved?.id
            name: saved?.name or name
            filter: filter
            sort: sort
          updateButton()
          clearError()
          loadPresets()
        .catch (err) ->
          showError "Erreur d'enregistrement du préréglage : #{err?.message or err}"

    deletePreset = (preset) ->
      return Promise.resolve false unless preset
      return Promise.resolve false unless window.confirm? "Supprimer le préréglage « #{preset.name} » ?"
      unless window.GQL?.mutate
        showError 'Client GraphQL indisponible'
        return Promise.resolve false
      window.GQL.mutate DELETE_VIEW_PRESET_MUTATION, { id: preset.id }
        .then ->
          state.presets = (p for p in state.presets when p.id != preset.id)
          if state.active?.id == preset.id
            state.active = null
            updateButton()
          clearError()
          renderPresets()
          true
        .catch (err) ->
          showError "Erreur de suppression du préréglage : #{err?.message or err}"
          false

    positionMenu = ->
      return unless wrapEl.getBoundingClientRect
      rect = wrapEl.getBoundingClientRect()
      menu.style.position = 'fixed'
      menu.style.left = "#{rect?.left ? 0}px"
      menu.style.top = "#{(rect?.bottom ? 0) + 4}px"

    close = ->
      menu.classList.add 'hidden'
      clearError()

    open = ->
      syncActive()
      renderSort()
      renderPresets()
      positionMenu()
      menu.classList.remove 'hidden'
      loadPresets()

    toggle = ->
      if isOpen() then close() else open()

    onDocumentClick = (ev) ->
      return unless isOpen()
      target = ev?.target
      return if target and wrapEl.contains? target
      close()

    onDocumentKey = (ev) ->
      close() if ev?.key == 'Escape' and isOpen()

    ensureDataViewBinding = ->
      dv = dataView()
      return unless dv
      return if dv._viewPresetsMenu == api
      dv._viewPresetsMenu = api
      dv._onSortChanged = ->
        syncActive()
        if isOpen()
          renderSort()
          renderPresets()

    onFilterInput = -> clearActive()

    destroy = ->
      document.removeEventListener? 'click', onDocumentClick, true
      document.removeEventListener? 'keydown', onDocumentKey
      # La grille principale réattache le menu au même input à chaque changement
      # d'espace : sans ce retrait, les écouteurs s'accumuleraient.
      opts.filterInput?.removeEventListener? 'input', onFilterInput
      dv = dataView()
      if dv and dv._viewPresetsMenu == api
        dv._viewPresetsMenu = null
        dv._onSortChanged = null
      button.parentNode?.removeChild? button
      menu.parentNode?.removeChild? menu

    api =
      button: button
      menu: menu
      elements:
        sortList: sortList
        presetList: presetList
        saveBtn: saveBtn
        errorEl: errorEl
      isOpen: isOpen
      open: open
      close: close
      toggle: toggle
      refresh: open
      applyPreset: applyPreset
      saveCurrent: saveCurrent
      deletePreset: deletePreset
      clearActive: clearActive
      destroy: destroy

    button.addEventListener 'click', (ev) ->
      ev?.stopPropagation?()
      toggle()
    saveBtn.addEventListener 'click', (ev) ->
      ev?.stopPropagation?()
      saveCurrent()
    opts.filterInput?.addEventListener? 'input', onFilterInput

    wrapEl._viewPresetsMenu = api
    ensureDataViewBinding()
    document.addEventListener? 'click', onDocumentClick, true
    document.addEventListener? 'keydown', onDocumentKey
    updateButton()
    api
