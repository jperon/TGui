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

# Réordonne une liste de critères par glisser-déposer : `from` et `to` sont des
# index de la liste finale. Fonction pure (l'entrée n'est pas mutée), isolée du
# DOM pour être testable seule. Un déplacement identité ou hors bornes renvoie
# une copie inchangée.
moveEntry = (entries, from, to) ->
  list = []
  return list unless Array.isArray entries
  list.push entry for entry in entries
  return list if from == to
  return list if from < 0 or from >= list.length
  return list if to < 0 or to >= list.length
  moved = list.splice from, 1
  list.splice to, 0, moved[0]
  list

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

# Colonnes proposées par « + Ajouter un critère » : les champs de l'espace,
# dans l'ordre de la grille. Un champ masqué n'a pas d'en-tête, donc pas de tri.
columnNamesFrom = (dv) ->
  out = []
  fields = dv?.space?.fields
  if Array.isArray(fields) and fields.length > 0
    for f in fields
      continue unless f?.name and not f.hidden
      out.push f.name
    return out
  columns = dv?._grid?.getColumns?() or []
  for col in columns
    continue unless col?.name and not col.hidden
    out.push col.name
  out

window.ViewPresetsMenu =
  sortEntriesFrom: sortEntriesFrom
  normalizeEntries: normalizeEntries
  moveEntry: moveEntry
  parseSort: parseSort
  serializeSort: serializeSort
  columnNamesFrom: columnNamesFrom

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

    # « + Ajouter un critère » : colonne non encore triée + sens, ajouté en fin
    # de liste (priorité la plus faible).
    addRow = createEl 'div', 'view-presets-add'
    addColumnSelect = document.createElement 'select'
    addColumnSelect.className = 'view-presets-add-column'
    addColumnSelect.title = 'Colonne à ajouter au tri'
    addDirectionSelect = document.createElement 'select'
    addDirectionSelect.className = 'view-presets-add-direction'
    addDirectionSelect.title = 'Sens du tri'
    ascOpt = createEl 'option', null, '↑ croissant'
    ascOpt.value = 'asc'
    addDirectionSelect.appendChild ascOpt
    descOpt = createEl 'option', null, '↓ décroissant'
    descOpt.value = 'desc'
    addDirectionSelect.appendChild descOpt
    addDirectionSelect.value = 'asc'
    addBtn = createEl 'button', 'view-presets-add-btn', '+ Ajouter un critère'
    addBtn.type = 'button'
    addBtn.title = 'Ajouter un critère de tri en fin de liste'
    addRow.appendChild addColumnSelect
    addRow.appendChild addDirectionSelect
    addRow.appendChild addBtn
    sortSection.appendChild addRow

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

    # Applique une liste de critères au DataView (cache persistant) ou, à
    # défaut, à la grille. Retourne les critères normalisés.
    applyEntries = (entries) ->
      dv = dataView()
      return [] unless dv
      clean = normalizeEntries entries
      if typeof dv.applySortEntries == 'function'
        dv.applySortEntries clean
      else
        applySortViaGrid dv, clean
      clean

    # Une seule voie d'écriture : transformer la liste courante, l'appliquer,
    # puis rafraîchir le menu et l'état « préréglage actif » (matchesActive).
    mutateSort = (fn) ->
      dv = dataView()
      return [] unless dv
      entries = fn sortEntriesFrom(dv)
      entries = applyEntries entries
      syncActive()
      renderSort()
      entries

    toggleSortDirection = (column) ->
      mutateSort (entries) ->
        for entry in entries when entry.column == column
          entry.ascending = not entry.ascending
        entries

    # Réordonnancement : la source est l'index de départ, la cible l'index
    # d'arrivée dans la liste finale (cf. moveEntry).
    reorderSortEntry = (from, to) ->
      mutateSort (entries) -> moveEntry entries, from, to

    addSortCriterion = ->
      return if addColumnSelect.disabled
      name = addColumnSelect.value
      return unless name
      ascending = addDirectionSelect.value != 'desc'
      mutateSort (entries) ->
        return entries if entries.some (e) -> e.column == name
        entries.push { column: name, ascending: ascending }
        entries

    makeSortButton = (className, text, title, action, handler) ->
      btn = createEl 'button', className, text
      btn.type = 'button'
      btn.title = title
      btn.setAttribute 'data-action', action
      btn.addEventListener 'click', (ev) ->
        ev?.stopPropagation?()
        handler()
      btn

    # ── Glisser-déposer natif (HTML5) des critères ──────────────────────────
    # Chaque ligne est `draggable` ; la position de dépôt (avant/après la ligne
    # survolée) suit la moitié haute/basse du curseur et se voit via une barre
    # d'insertion (classes drop-before / drop-after). Aucun glisser ne doit
    # fermer le menu : le clic de fermeture global est neutralisé pendant le
    # glissement, et juste après le dépôt.
    dragState = { from: null, to: null, after: false }
    suppressCloseUntil = 0

    clearDropMarks = ->
      for el in (sortList.children or [])
        el.classList.remove 'drop-before'
        el.classList.remove 'drop-after'

    endDrag = ->
      dragState.from = null
      dragState.to = null
      dragState.after = false
      for el in (sortList.children or [])
        el.classList.remove 'dragging'
      clearDropMarks()

    onRowDragStart = (row, index, ev) ->
      dragState.from = index
      dragState.to = index
      dragState.after = false
      row.classList.add 'dragging'
      dt = ev?.dataTransfer
      if dt
        dt.effectAllowed = 'move'
        dt.setData? 'text/plain', "#{index}"
      ev?.stopPropagation?()

    onRowDragOver = (row, index, ev) ->
      return unless dragState.from?
      ev?.preventDefault?()
      dt = ev?.dataTransfer
      dt.dropEffect = 'move' if dt
      after = false
      rect = row.getBoundingClientRect?()
      y = ev?.clientY
      if rect? and y? and rect.height
        after = y > rect.top + rect.height / 2
      dragState.to = index
      dragState.after = after
      clearDropMarks()
      row.classList.add if after then 'drop-after' else 'drop-before'

    # Index final du dépôt : insérer « après la ligne i » revient à i+1 dans la
    # liste d'origine, puis à i quand la ligne déplacée vient d'avant.
    dropIndex = ->
      return null unless dragState.from? and dragState.to?
      insertAt = if dragState.after then dragState.to + 1 else dragState.to
      if insertAt > dragState.from then insertAt - 1 else insertAt

    onRowDrop = (row, index, ev) ->
      return unless dragState.from?
      ev?.preventDefault?()
      ev?.stopPropagation?()
      from = dragState.from
      to = dropIndex()
      endDrag()
      suppressCloseUntil = Date.now() + 400
      return unless to? and to != from
      reorderSortEntry from, to

    onRowDragEnd = (row, ev) ->
      endDrag()
      suppressCloseUntil = Date.now() + 400

    buildSortRow = (entry, index) ->
      row = createEl 'div', 'view-presets-sort-row'
      row.dataset.column = entry.column
      row.dataset.rank = "#{index + 1}"
      row.draggable = true
      handle = createEl 'span', 'view-presets-sort-handle', '⠿'
      handle.title = 'Glisser pour changer la priorité du critère'
      handle.setAttribute 'aria-hidden', 'true'
      row.appendChild handle
      row.appendChild createEl('span', 'view-presets-sort-rank', "#{index + 1}.")
      row.appendChild createEl('span', 'view-presets-sort-label', entry.column)
      dirText = if entry.ascending then '↑' else '↓'
      dirTitle = if entry.ascending then 'Croissant — cliquer pour trier en décroissant' else 'Décroissant — cliquer pour trier en croissant'
      row.appendChild makeSortButton 'view-presets-sort-dir', dirText, dirTitle,
        'dir', -> toggleSortDirection entry.column
      row.appendChild makeSortButton 'view-presets-remove', '✕', 'Retirer ce critère de tri',
        'remove', -> removeSortColumn entry.column
      row.addEventListener 'dragstart', (ev) -> onRowDragStart row, index, ev
      row.addEventListener 'dragover', (ev) -> onRowDragOver row, index, ev
      row.addEventListener 'drop', (ev) -> onRowDrop row, index, ev
      row.addEventListener 'dragend', (ev) -> onRowDragEnd row, ev
      row

    # Options de « + Ajouter un critère » : uniquement les colonnes non triées.
    renderAddSortRow = (entries) ->
      clearChildren addColumnSelect
      used = {}
      used[entry.column] = true for entry in entries
      names = columnNamesFrom dataView()
      available = []
      for name in names
        continue if used[name]
        available.push name
      if available.length == 0
        addColumnSelect.appendChild createEl('option', null, 'Toutes les colonnes sont triées')
        addColumnSelect.disabled = true
        addBtn.disabled = true
        return
      addColumnSelect.disabled = false
      addBtn.disabled = false
      for name in available
        opt = createEl 'option', null, name
        opt.value = name
        addColumnSelect.appendChild opt
      addColumnSelect.value = available[0]

    renderSort = ->
      clearChildren sortList
      entries = sortEntriesFrom dataView()
      if entries.length == 0
        sortList.appendChild createEl('div', 'view-presets-empty',
          "Aucun tri — ajoutez un critère ci-dessous, ou cliquez un en-tête de colonne (Maj+clic ou Ctrl/Cmd+clic pour en ajouter un autre)")
      for entry, index in entries
        sortList.appendChild buildSortRow entry, index
      renderAddSortRow entries

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
      applyEntries entries
      dv.setFormulaFilter? filter
      clearError()
      renderSort()
      renderPresets()
      close()

    removeSortColumn = (column) ->
      mutateSort (entries) ->
        (e for e in entries when e.column != column)

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
      # Ne jamais fermer le menu pendant un glissement de critère, ni dans les
      # 400 ms qui suivent le dépôt (un navigateur peut émettre un clic tardif
      # sur le fond après un glisser-déposer).
      return if dragState.from?
      return if Date.now() < suppressCloseUntil
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
        addRow: addRow
        addColumnSelect: addColumnSelect
        addDirectionSelect: addDirectionSelect
        addBtn: addBtn
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
    addBtn.addEventListener 'click', (ev) ->
      ev?.stopPropagation?()
      addSortCriterion()
    opts.filterInput?.addEventListener? 'input', onFilterInput

    wrapEl._viewPresetsMenu = api
    ensureDataViewBinding()
    document.addEventListener? 'click', onDocumentClick, true
    document.addEventListener? 'keydown', onDocumentKey
    updateButton()
    api
