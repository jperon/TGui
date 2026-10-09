# custom_view.coffee
# YAML-driven layout renderer.
#
# YAML format example:
#
#   layout:
#     direction: vertical
#     children:
#       - factor: 2                         # takes 2/3 of available space (optional, default: 1)
#         direction: horizontal
#         children:
#           - widget:
#               id: choir-list               # unique widget identifier (required when referenced)
#               title: Chorales
#               space: chorale
#               columns: [annee, pupitre]   # columns to display (optional, default: all)
#           - widget:
#               title: Choristes
#               space: choristes
#               depends_on:
#                 widget: choir-list        # source widget id
#                 field: chorale_id         # FK field in this space
#                 from_field: id            # referenced field in source widget space (default: id)
#       - factor: 1
#         widget:
#           title: Personnes
#           space: personnes

# Parse a Data View `config`: the list GraphQL query returns the raw serialized
# JSON string (data_views.coffee), while the detail query decodes it. Accept both.
_parseDataViewConfig = (raw) ->
  return {} unless raw
  return raw if typeof raw == 'object'
  try
    JSON.parse raw
  catch e
    null

# Output columns of a Data View, mirroring backend/core/data_views_executor.moon:
# groupBy names then aggregate aliases; explicit `columns`; otherwise the source
# space fields. Each entry is `{ name, fieldType }`, the type reused from the
# source space when it declares the column.
_dataViewColumns = (config, dv, allSpaces) ->
  source = null
  if dv.sourceSpace and allSpaces
    source = allSpaces.find (s) -> s.id == dv.sourceSpace or s.name == dv.sourceSpace

  typeFor = (name) ->
    if source
      f = (source.fields or []).find (sf) -> sf.name == name
      return f.fieldType if f?.fieldType
    'String'

  names = []
  if (config.groupBy and config.groupBy.length > 0) or (config.aggregates and config.aggregates.length > 0)
    names.push name for name in (config.groupBy or [])
    for agg in (config.aggregates or [])
      names.push agg.as or (if agg.field then "#{agg.fn}_#{agg.field}" else 'count')
  else if config.columns and config.columns.length > 0
    for col in config.columns
      names.push (if typeof col == 'string' then col else (col.as or col.field))
  else if source
    names.push f.name for f in (source.fields or [])

  fields = []
  seen = {}
  for name in names
    continue unless name
    continue if seen[name]
    seen[name] = true
    fields.push { name: name, fieldType: typeFor name }
  fields

window.CustomView = class CustomView
  constructor: (@container, @yamlText, @allSpaces, @allDataViews = [], @options = {}) ->
    @_widgets   = []   # list of { dataView, node, el }
    @_widgetsById = {} # id -> entry
    @_pluginStateByWidgetId = {}
    @_pluginSelectionListenersByWidgetId = {}
    @_resizeObserver = null
    @_resizeTimer = null
    @pageId = @container.getAttribute('data-page-id') or null
    @presentationMode = @options.presentationMode or false

  # Fonction globale pour gérer l'insertion de layouts pendant l'édition YAML
  @setupLayoutInsertion: ->
    # Éviter les doublons de listeners
    if window._cvLayoutListenerActive
      return

    window.addEventListener 'cv-insert-layout', (ev) =>
      direction = ev.detail?.direction
      return unless direction

      # Récupérer l'instance CodeMirror active
      cm = document.querySelector('.CodeMirror')
      return unless cm?.CodeMirror

      currentYaml = cm.CodeMirror.getValue()
      parsed = null
      try
        parsed = jsyaml.load currentYaml
        # Si le YAML est vide, jsyaml.load retourne null
        parsed = {} if not parsed
      catch e
        parsed = {}

      newLayout =
        direction: direction
        children: []

      # Logique d'insertion intelligente
      if not parsed.layout
        # Créer un layout racine
        parsed.layout = newLayout
        @showNotification 'Layout racine créé', 'success'
      else if parsed.layout and parsed.layout.children
        # Ajouter comme enfant du layout existant
        parsed.layout.children.push newLayout
        @showNotification "Layout #{direction} ajouté", 'success'
      else
        # Remplacer ou créer le layout
        parsed.layout = newLayout
        @showNotification 'Layout remplacé', 'success'

      newYaml = jsyaml.dump parsed

      # Valider le YAML généré
      try
        jsyaml.load newYaml
        cm.CodeMirror.setValue newYaml
        @showNotification 'Layout inséré avec succès', 'success'
      catch e
        @showNotification "Erreur YAML : #{e.message}", 'error'
        # Restaurer le YAML précédent en cas d'erreur
        cm.CodeMirror.setValue currentYaml

    window._cvLayoutListenerActive = true

  @showNotification: (message, type = 'info') ->
    # Créer une notification temporaire
    notification = document.createElement 'div'
    notification.className = "cv-notification cv-notification--#{type}"
    notification.textContent = message
    notification.style.cssText = """
      position: fixed;
      top: 20px;
      right: 20px;
      padding: 12px 16px;
      border-radius: 4px;
      color: white;
      font-weight: 500;
      z-index: 10000;
      opacity: 0;
      transform: translateX(100%);
      transition: all 0.3s ease;
    """

    # Couleurs selon le type
    colors =
      success: '#28a745'
      error: '#dc3545'
      info: '#17a2b8'

    notification.style.backgroundColor = colors[type] or colors.info

    # Ajouter au DOM
    document.body.appendChild notification

    # Animer l'entrée
    setTimeout ->
      notification.style.opacity = '1'
      notification.style.transform = 'translateX(0)'
    , 10

    # Auto-suppression après 3 secondes
    setTimeout ->
      notification.style.opacity = '0'
      notification.style.transform = 'translateX(100%)'
      setTimeout ->
        document.body.removeChild notification
      , 300
    , 3000

  # Rend un message simple dans un conteneur (textContent, jamais innerHTML).
  _setMessage: (container, text, style = 'color:#888;padding:.5rem') ->
    container.innerHTML = ''
    # Le stub DOM des tests ne vide pas _children via innerHTML : on vide aussi
    # les tableaux quand ils existent (HTMLCollection en navigateur → ignoré).
    if Array.isArray container._children
      container._children.length = 0
    if Array.isArray container.children
      container.children.length = 0
    p = document.createElement 'p'
    p.style.cssText = style
    p.textContent = String(text ? '')
    container.appendChild p

  # Anti-rebond : une seule passe de rafraîchissement par salve de changements.
  _refreshGridLayouts: ->
    for entry in @_widgets
      entry.dataView?._grid?.refreshLayout()

  # Recalcule la taille des grilles quand la surface d'une tuile change
  # (séparateurs, réouverture de la page, redimensionnement de la fenêtre).
  _setupResizeObserver: ->
    return unless typeof ResizeObserver != 'undefined'
    @_resizeObserver?.disconnect?()
    @_resizeObserver = new ResizeObserver (entries) =>
      clearTimeout @_resizeTimer
      @_resizeTimer = setTimeout (=> @_refreshGridLayouts()), 50
    @_resizeObserver.observe @container

  mount: ->
    @container.innerHTML = ''
    @_widgets     = []
    @_widgetsById = {}
    @_mountPromises = []

    # Apply presentation mode class
    if @presentationMode
      @container.classList.add 'presentation-mode'
    else
      @container.classList.remove 'presentation-mode'

    # Configurer le listener global d'insertion de layouts
    CustomView.setupLayoutInsertion()

    try
      parsed = jsyaml.load @yamlText
    catch e
      @_setMessage @container, "YAML invalide : #{e.message}", 'color:red;padding:1rem'
      return

    root = parsed?.layout
    unless root
      @container.innerHTML = "<p style='color:#888;padding:1rem'>Pas de section <code>layout</code> dans le YAML.</p>"
      return

     el = @_renderZoneOrWidget root
     @container.style.cssText = 'display:flex;flex-direction:column;height:100%;'
     @container.appendChild el

     # Wire depends_on after all DataView grids are ready (mount is async)
     Promise.all(@_mountPromises).then =>
       @_wireDepends()
       # Refresh grid layouts now that elements are in the live DOM
       setTimeout (=> @_refreshGridLayouts()), 0
       # Une tuile redimensionnée change la taille de sa grille : on rafraîchit
       # les layouts (avec anti-rebond) à chaque changement de taille.
       @_setupResizeObserver()

      # Initialiser le DragDropManager avec support des zones (Phase 3)
      # Disabled in presentation mode
      if @pageId and not @presentationMode
        @_dragDropManager?.destroy?()

        # Vérifier si DragDropManager est disponible
        if typeof DragDropManager != 'undefined'
         @_dragDropManager = new DragDropManager @container,
           pageId: @pageId
           handle: '.widget-header'
           filter: '.no-drag'
           onCreateZone: (zoneData) =>
             # TODO: Implement zone creation if needed
             console.log 'Zone creation not implemented in CustomView', zoneData
           onResizeZone: (zoneId, factor) =>
             @_onZoneResize zoneId, factor
           onReorder: (positions) =>
             window.AppViewHelpers.handleWidgetReorder @, positions
           onDataViewDrop: (dataViewId, evt) =>
             mutation = """
               mutation AddDataViewToPage($pageId: ID!, $dataViewId: ID!) {
                 addDataViewToPage(pageId: $pageId, dataViewId: $dataViewId) {
                   id
                   yaml
                 }
               }
             """
             GQL.mutate(mutation, { pageId: @pageId, dataViewId: dataViewId })
               .then (result) =>
                 if result.errors
                   console.error 'GraphQL errors:', result.errors
                   @showNotification "Erreur lors de l'ajout de la vue de données: #{result.errors[0].message}", 'error'
                 else
                   @showNotification 'Vue de données ajoutée avec succès', 'success'
                   @yamlText = result.addDataViewToPage.yaml
                   @unmount()
                   @mount()
               .catch (error) =>
                 console.error 'Network error:', error
                 @showNotification 'Erreur réseau lors de l\'ajout de la vue de données: ' + error.message, 'error'
       else
         console.warn "DragDropManager not available, drag & drop features disabled"

  # Renders either a zone (direction+children) or a widget node.
  # Applies `factor` (flex proportion) when specified (default: 1).
  # Supports both inline zone keys (direction/children) and wrapped "- layout:" syntax.
  _renderZoneOrWidget: (node) ->
    zone = if node.layout then node.layout else node
    if zone.widget
      el = @_renderWidget zone.widget
    else
      el = document.createElement 'div'
      el.className = "cv-zone #{zone.direction or 'vertical'} drop-zone"

      # Ajouter les attributs pour la gestion des zones (Phase 3)
      if zone.id
        el.setAttribute 'data-zone-id', zone.id
        el.setAttribute 'data-zone-title', zone.title or "Zone #{zone.id}"
        el.setAttribute 'data-zone-factor', String(zone.factor or 1)
        el.setAttribute 'data-zone-direction', zone.direction or 'vertical'

      # Ajouter un header de zone pour l'identification
      if zone.title or zone.id
        zoneHeader = document.createElement 'div'
        zoneHeader.className = 'cv-zone-header'
        zoneHeader.textContent = zone.title or "Zone #{zone.id}"
        el.appendChild zoneHeader

      # Container pour les widgets de la zone
      zoneContent = document.createElement 'div'
      zoneContent.className = 'cv-zone-content'

      for child in (zone.children or [])
        zoneContent.appendChild @_renderZoneOrWidget child

      el.appendChild zoneContent

      # Ajouter les poignées de redimensionnement si factor est défini
      if zone.factor
        @_addResizeHandle el, zone

    el.style.flex = if node.factor? then String(node.factor) else '1'
    el

  _renderWidget: (wNode) ->
    wrapper = document.createElement 'div'
    wrapper.className = 'cv-widget'

    # Ajouter les attributs pour le drag & drop
    if wNode.id
      wrapper.setAttribute 'data-widget-id', wNode.id
    wrapper.setAttribute 'data-widget-type', wNode.type or 'data'

    # Title bar avec classe pour le drag handle
    titleBar = document.createElement 'div'
    titleBar.className = 'cv-widget-title widget-header'
    titleText = document.createElement 'span'
    titleText.textContent = wNode.title or wNode.space or ''
    titleBar.appendChild titleText
    wrapper.appendChild titleBar

    body = document.createElement 'div'
    body.className = 'cv-widget-body'
    wrapper.appendChild body

    # Aggregate widget (read-only summary table)
    if wNode.type == 'aggregate'
      @_renderAggregate body, wNode
      entry = { dataView: null, node: wNode, el: wrapper }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    # Custom plugin widget (type = plugin name)
    if wNode.type
      runtimeWidgetId = wNode.id or "plugin_#{Math.random().toString(36).slice(2)}"
      @_renderPluginWidget body, wNode, runtimeWidgetId
      entry = { dataView: null, node: wNode, el: wrapper, plugin: true, runtimeWidgetId }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    # Regular data widget
    sp = @_findSpace wNode.space
    delBtn = document.createElement 'button'
    delBtn.className = 'cv-widget-delete-btn'
    delBtn.title = 'Supprimer les enregistrements sélectionnés'
    delBtn.textContent = '🗑'

    unless sp
      @_setMessage body, "Espace « #{wNode.space} » introuvable.", 'color:#aaa;padding:.5rem'
      entry = { dataView: null, node: wNode, el: wrapper }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    # Apply column filter/order if specified
    if wNode.columns and wNode.columns.length > 0
      fieldMap = {}
      fieldMap[f.name] = f for f in (sp.fields or [])
      sp = Object.assign {}, sp
      sp.fields = (fieldMap[col] for col in wNode.columns when fieldMap[col])

    dv = new DataView body, sp
    filterFormula = ''
    # Apply formula filter from YAML widget config
    if wNode.filter
      filterFormula = if typeof wNode.filter == 'string' then wNode.filter else (wNode.filter.formula or '')
      lang          = if typeof wNode.filter == 'object' then (wNode.filter.language or 'moonscript') else 'moonscript'
      dv._formulaFilter = filterFormula if filterFormula

    filterWrap = document.createElement 'div'
    filterWrap.className = 'cv-widget-filter toolbar-filter'
    filterLabel = document.createElement 'span'
    filterLabel.className = 'toolbar-filter-label'
    filterLabel.textContent = 'λ'
    filterInput = document.createElement 'input'
    filterInput.type = 'text'
    filterInput.className = 'toolbar-filter-input'
    filterInput.placeholder = 'Filtre (MoonScript)'
    filterInput.value = filterFormula
    filterInput.classList.toggle 'active', filterFormula != ''
    filterWrap.appendChild filterLabel
    filterWrap.appendChild filterInput
    titleBar.appendChild filterWrap
    titleBar.appendChild delBtn

    filterTimer = null
    filterInput.addEventListener 'input', (ev) =>
      val = ev.target.value.trim()
      ev.target.classList.toggle 'active', val != ''
      clearTimeout filterTimer
      filterTimer = setTimeout (=> dv.setFormulaFilter val), 400
    dv._formulaInputEl = filterInput

    @_mountPromises.push dv.mount()
    delBtn.addEventListener 'click', => dv.deleteSelected()
    entry = { dataView: dv, node: wNode, el: wrapper }
    @_widgets.push entry
    @_widgetsById[wNode.id] = entry if wNode.id
    wrapper

  _wireDepends: ->
    for entry in @_widgets
      dep = entry.node.depends_on
      continue unless dep
      src = @_widgetsById[dep.widget]
      unless src
        console.warn "depends_on: widget id '#{dep.widget}' introuvable"
        continue

      # When a row selection is emitted by source widget, propagate to target.
      # from_field defaults to 'id' when omitted.
      do (entry, dep, src) =>
        if src.dataView?._grid?
          src.dataView._grid.on 'click', (ev) =>
            return if ev?.nativeEvent?.detail and ev.nativeEvent.detail > 1
            rowKey = ev.rowKey
            return unless rowKey?
            rowData = src.dataView._grid.getRow rowKey
            return unless rowData and not rowData.__isNew
            @_applyDependencySelection entry, dep, rowData
        else if src.plugin and dep.widget
          @_setPluginSelectionListener dep.widget, (selection) =>
            rows = selection?.rows or []
            return unless rows.length > 0
            @_applyDependencySelection entry, dep, rows[0]

  _applyDependencySelection: (entry, dep, rowData) ->
    filterVal = String(rowData[dep.from_field or 'id'])
    defaults = {}
    defaults[dep.field] = filterVal
    if entry.dataView?
      entry.dataView.setDefaultValues defaults
      entry.dataView.setFilter { field: dep.field, value: filterVal }
    else if entry.plugin
      targetWidgetId = entry.runtimeWidgetId or entry.node.id
      return unless targetWidgetId
      @_sendPluginMessage targetWidgetId, {
        type: 'updateInputSelection'
        selection: {
          rows: [rowData]
          byField: defaults
        }
      }

  _findSpace: (nameOrId) ->
    return null unless nameOrId
    sp = @allSpaces.find (s) -> s.name == nameOrId or s.id == nameOrId
    return sp if sp

    # Search in Data Views if not found in regular spaces
    dv = @allDataViews.find (v) -> v.name == nameOrId or v.id == nameOrId
    if dv
      config = _parseDataViewConfig dv.config
      fields = if config then _dataViewColumns config, dv, @allSpaces else []
      # Create a virtual space object for DataView class compatibility
      return {
        id: dv.id
        name: dv.name
        isView: true
        viewId: dv.id
        fields: fields
      }
    null

  unmount: ->
    for own id, st of @_pluginStateByWidgetId
      window.removeEventListener 'message', st.onMessage if st.onMessage
    @_resizeObserver?.disconnect?()
    @_resizeObserver = null
    clearTimeout @_resizeTimer
    for entry in @_widgets
      entry.dataView?.unmount?()
    @container.innerHTML = ''
    @_widgets     = []
    @_pluginStateByWidgetId = {}
    @_pluginSelectionListenersByWidgetId = {}
    @_widgetsById = {}

  # Toggle grid overlay visibility
  toggleGrid: ->
    @_gridVisible = not @_gridVisible
    existing = @container.querySelector('.grid-overlay')
    if @_gridVisible
      unless existing
        overlay = document.createElement 'div'
        overlay.className = 'grid-overlay'
        @container.appendChild overlay
    else
      existing?.remove()

  # Get current grid visibility state
  isGridVisible: ->
    @_gridVisible or false

  # Toggle presentation mode (read-only, no drag & drop)
  togglePresentationMode: ->
    @presentationMode = not @presentationMode
    if @presentationMode
      @container.classList.add 'presentation-mode'
      @_dragDropManager?.destroy?()
      @_dragDropManager = null
    else
      @container.classList.remove 'presentation-mode'
      # Reinitialize drag drop if pageId exists
      if @pageId and typeof DragDropManager != 'undefined'
        @_dragDropManager = new DragDropManager @container,
          pageId: @pageId
          handle: '.widget-header'
          filter: '.no-drag'
          onResizeZone: (zoneId, factor) =>
            @_onZoneResize zoneId, factor
          onReorder: (positions) =>
            window.AppViewHelpers.handleWidgetReorder @, positions
    @presentationMode

  # Get presentation mode state
  isPresentationMode: ->
    @presentationMode
