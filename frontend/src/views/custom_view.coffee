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

# Facteur de répartition d'un nœud. Lu sur le mapping `widget`/`layout` (forme
# documentée de doc/fr/get-started.md), puis sur l'entrée elle-même (ancienne
# forme). Défaut : 1. L'écriture (setChildFactors) vise le mapping.
_nodeFactor = (node) ->
  return node.widget.factor if node.widget and node.widget.factor?
  return node.layout.factor if node.layout and node.layout.factor?
  return node.factor if node.factor?
  1

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

  # Répartit `sizeA + sizeB` px entre deux tuiles voisines après un glisser de
  # `delta` px, en respectant un minimum `min` pour chacune. Fonction pure.
  @redistribute: (sizeA, sizeB, delta, min) ->
    total = sizeA + sizeB
    return [sizeA, sizeB] if total < 2 * min
    a = Math.max(min, Math.min(total - min, sizeA + delta))
    [a, total - a]

  # Réécrit le YAML d'une page en mettant à jour le `factor` des enfants voulus.
  # `path` = indices d'enfants depuis `layout` jusqu'à la zone parente.
  # `factors` = liste de `{ index, factor }` (index dans les enfants de la zone).
  # Le facteur est écrit dans le mapping `widget`/`layout` de l'enfant.
  @setChildFactors: (yamlText, path, factors) ->
    parsed = jsyaml.load yamlText
    return yamlText unless parsed?.layout
    parent = parsed.layout
    for idx in (path or [])
      entry = parent?.children?[idx]
      return yamlText unless entry
      parent = if entry.layout then entry.layout else entry
    return yamlText unless parent?.children?
    for f in (factors or [])
      child = parent.children[f.index]
      continue unless child
      mapping = if child.widget then child.widget else if child.layout then child.layout else child
      mapping.factor = Math.round(f.factor * 100) / 100
      delete child.factor if child.widget or child.layout
    jsyaml.dump parsed

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

    # Index des `from_field` requis par chaque widget source, pour que les
    # champs de liaison soient chargés même s'ils sont absents de `columns`.
    @_linkFieldsByWidgetId = {}
    for w in @_collectWidgetNodes root
      dep = w.depends_on
      continue unless dep?.widget
      ff = dep.from_field or 'id'
      (@_linkFieldsByWidgetId[dep.widget] ?= []).push ff

     el = @_renderZoneOrWidget root
     @container.style.cssText = 'display:flex;flex-direction:column;height:100%;'
     @container.appendChild el

     # Wire depends_on after all DataView grids are ready (mount is async)
     Promise.all(@_mountPromises).then =>
       @_wireDepends()
       # Initial cascade: activate the first row of each root widget and
       # propagate down the depends_on chain (once per mount).
       @_initializeCascade()
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
  # `path` = indices des enfants depuis `layout` (racine) jusqu'à la zone parente ;
  # sert à réécrire le bon emplacement du YAML lors d'un glisser de séparateur.
  _renderZoneOrWidget: (node, path = []) ->
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

      children = zone.children or []
      childEls = []
      for child, i in children
        childEls.push @_renderZoneOrWidget child, path.concat([i])

      # Séparateurs glissables : uniquement sur une page éditable, hors mode
      # présentation, et pas dans une zone qui a déjà sa poignée (id+factor).
      canSplit = children.length > 1 and @pageId and not @presentationMode
      canSplit = canSplit and not (zone.id and zone.factor)
      for childEl, i in childEls
        zoneContent.appendChild childEl
        if canSplit and i < childEls.length - 1
          zoneContent.appendChild @_createSplitter zone.direction, childEl, childEls[i + 1], path, i

      el.appendChild zoneContent

      # Ajouter les poignées de redimensionnement si factor est défini
      if zone.factor
        @_addResizeHandle el, zone

    el.style.flex = String(_nodeFactor node)
    el

  # Séparateur glissable entre deux enfants consécutifs d'une zone. Le glisser
  # redistribue l'espace des DEUX voisins (minimum 80 px chacun) en conservant
  # la SOMME de leurs facteurs : les autres enfants de la zone ne changent donc
  # pas de taille. Un double-clic les remet à parts égales. Les écouteurs
  # `document` ne vivent que pendant le glisser (posés au mousedown, retirés au
  # mouseup) et un clic sans déplacement n'écrit rien dans le YAML.
  _createSplitter: (direction, a, b, path, index) ->
    horizontal = direction == 'horizontal'
    dir = if horizontal then 'horizontal' else 'vertical'
    axis = if horizontal then 'width' else 'height'
    sp = document.createElement 'div'
    sp.className = "cv-splitter cv-splitter--#{dir}"

    dragging = false
    startPos = 0
    startA = 0
    startB = 0
    startFactorA = 1
    startFactorB = 1
    sumFactors = 2

    # Facteur courant d'un enfant : le flex rendu est un simple nombre.
    factorOf = (el) ->
      f = parseFloat el.style.flex
      if isNaN(f) then 1 else f

    onMouseMove = (ev) =>
      return unless dragging
      pos = if horizontal then ev.clientX else ev.clientY
      delta = pos - startPos
      return if delta == 0
      [na, nb] = CustomView.redistribute startA, startB, delta, 80
      total = na + nb
      return if total <= 0
      # Pixels → facteurs, à somme constante : les voisins hors de la paire,
      # dont le flex reste inchangé, gardent leur taille.
      fa = Math.round((sumFactors * na / total) * 100) / 100
      fb = Math.round((sumFactors - fa) * 100) / 100
      a.style.flex = String fa
      b.style.flex = String fb

    onMouseUp = =>
      return unless dragging
      stopDrag()
      fa = factorOf a
      fb = factorOf b
      # Aucun déplacement : ne pas réécrire le YAML (jsyaml.dump y perdrait
      # les commentaires) ni redimensionner quoi que ce soit.
      return if fa == startFactorA and fb == startFactorB
      @_saveChildFactors path, [
        { index: index, factor: fa }
        { index: index + 1, factor: fb }
      ]

    stopDrag = ->
      dragging = false
      document.removeEventListener? 'mousemove', onMouseMove
      document.removeEventListener? 'mouseup', onMouseUp
      document.body?.style.cursor = ''

    sp.addEventListener 'mousedown', (ev) =>
      dragging = true
      startPos = if horizontal then ev.clientX else ev.clientY
      ra = a.getBoundingClientRect()
      rb = b.getBoundingClientRect()
      startA = ra[axis] or 0
      startB = rb[axis] or 0
      startFactorA = factorOf a
      startFactorB = factorOf b
      sumFactors = startFactorA + startFactorB
      document.body?.style.cursor = if horizontal then 'col-resize' else 'row-resize'
      document.addEventListener? 'mousemove', onMouseMove
      document.addEventListener? 'mouseup', onMouseUp
      ev.preventDefault?()

    sp.addEventListener 'dblclick', =>
      a.style.flex = '1'
      b.style.flex = '1'
      @_saveChildFactors path, [
        { index: index, factor: 1 }
        { index: index + 1, factor: 1 }
      ]
    sp

  # Persiste les facteurs d'une paire de voisins dans le YAML de la page, puis
  # recharge le rendu. Réutilise la mutation existante updateCustomView.
  _saveChildFactors: (path, factors) ->
    return unless @pageId
    newYaml = null
    try
      newYaml = CustomView.setChildFactors @yamlText, path, factors
    catch e
      return
    return unless newYaml
    @yamlText = newYaml
    app = window.App
    return unless app and typeof GQL != 'undefined'
    GQL.mutate(app._updateCustomViewMutation, { id: @pageId, input: { yaml: newYaml } })
      .then (data) =>
        app._currentCustomView = data.updateCustomView if data?.updateCustomView?
        window.AppViewHelpers?._renderCustomViewPreview? app, newYaml
      .catch (err) ->
        tdbAlert app._err(err), 'error' if typeof tdbAlert != 'undefined'

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

    # Apply column filter/order if specified. Les champs de liaison requis par
    # la chaîne depends_on (le `depends_on.field` du widget, et le `from_field`
    # de chaque widget qui dépend de lui) sont ajoutés en COPIE marquée
    # `hidden: true` : ils doivent être chargés (la requête GraphQL se construit
    # depuis sp.fields) mais pas affichés.
    if wNode.columns and wNode.columns.length > 0
      fieldMap = {}
      fieldMap[f.name] = f for f in (sp.fields or [])
      sp = Object.assign {}, sp
      visible = (fieldMap[col] for col in wNode.columns when fieldMap[col])
      present = {}
      present[f.name] = true for f in visible
      extras = []
      for lf in @_widgetLinkFields wNode when not present[lf]
        srcField = fieldMap[lf]
        unless srcField
          console.warn "depends_on: champ de liaison '#{lf}' absent de l'espace/vue '#{wNode.space}' (widget '#{wNode.id}')"
          continue
        extras.push Object.assign {}, srcField, { hidden: true }
        present[lf] = true
      sp.fields = visible.concat extras

    dv = new DataView body, sp
    filterFormula = ''
    # Apply formula filter from YAML widget config
    if wNode.filter
      filterFormula = if typeof wNode.filter == 'string' then wNode.filter else (wNode.filter.formula or '')
      lang          = if typeof wNode.filter == 'object' then (wNode.filter.language or 'moonscript') else 'moonscript'
      dv._formulaFilter = filterFormula if filterFormula

    filterWrap = document.createElement 'div'
    filterWrap.className = 'cv-widget-filter toolbar-filter no-drag'
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
    window.FieldAutocomplete?.attach filterInput, -> dv
    filterInput.addEventListener 'input', (ev) =>
      val = ev.target.value.trim()
      ev.target.classList.toggle 'active', val != ''
      clearTimeout filterTimer
      filterTimer = setTimeout (=> dv.setFormulaFilter val), 400
    dv._formulaInputEl = filterInput

    # Même menu que la grille principale, avec la portée du widget de page.
    # Jamais pour un widget dont la source est une Data View : `sp.id` est alors
    # l'id de la vue, et `saveViewPreset` le refuse (« Space not found »).
    if @pageId and wNode.id and not sp.isView
      window.ViewPresetsMenu?.attach filterWrap, {
        getDataView: -> dv
        scope: "widget:#{@pageId}:#{wNode.id}"
        spaceId: sp.id
        filterInput: filterInput
      }

    @_mountPromises.push dv.mount()
    delBtn.addEventListener 'click', => dv.deleteSelected()
    entry = { dataView: dv, node: wNode, el: wrapper }
    @_widgets.push entry
    @_widgetsById[wNode.id] = entry if wNode.id
    wrapper

  # Liste à plat des mappings `widget` d'un arbre de layout, dans l'ordre de
  # rendu. Sert à connaître les dépendances avant de rendre les widgets.
  _collectWidgetNodes: (node, out = []) ->
    zone = if node.layout then node.layout else node
    if zone.widget
      out.push zone.widget
    else
      @_collectWidgetNodes child, out for child in (zone.children or [])
    out

  # Champs de liaison obligatoires d'un widget : son propre `depends_on.field`,
  # puis le `from_field` (défaut `id`) de chaque widget qui dépend de lui.
  # Dédoublonnés, dans cet ordre.
  _widgetLinkFields: (wNode) ->
    out = []
    add = (name) ->
      return unless name
      out.push name unless name in out
    add wNode.depends_on?.field
    for ff in (@_linkFieldsByWidgetId?[wNode.id] or [])
      add ff
    out

  _wireDepends: ->
    for entry in @_widgets
      dep = entry.node.depends_on
      continue unless dep
      # Un widget plugin dépendant n'est pas rempli automatiquement.
      continue if entry.plugin
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

  _applyDependencySelection: (entry, dep, rowData, seen = new WeakSet) ->
    key = dep.from_field or 'id'
    raw = rowData?[key]
    # Garde-fou : le champ de liaison est absent de la ligne source (widget
    # source dépourvu de ce champ, vue agrégée, …). Ne jamais filtrer sur la
    # chaîne "undefined" (qui laisserait tout passer) : aucun résultat.
    if raw is undefined or raw is null or raw is ''
      console.warn "depends_on: champ de liaison '#{key}' absent de la ligne source du widget '#{dep.widget}' (widget cible '#{entry.node?.id}')"
      if entry.dataView?
        entry.dataView.setDefaultValues {}
        entry.dataView.setFilter { field: dep.field, value: null, none: true }
        @_cascadeNone entry, seen
      return
    filterVal = String raw
    defaults = {}
    defaults[dep.field] = filterVal
    if entry.dataView?
      entry.dataView.setDefaultValues defaults
      entry.dataView.setFilter { field: dep.field, value: filterVal }
      # Cascade : activer la première ligne affichée de ce widget et propager à
      # ses propres dépendants, ou passer en « aucun résultat » si vide.
      seen.add entry
      first = @_firstRow entry
      if first?
        @_selectRow entry, first.rowKey, seen
      else
        @_cascadeNone entry, seen
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

  # ── Sélection en cascade des widgets dépendants ─────────────────────────────

  # Entrées widgets dépendant directement de `entry` (via depends_on.widget).
  _dependentEntries: (entry) ->
    depId = entry?.node?.id
    return [] unless depId
    (e for e in @_widgets when e.node?.depends_on?.widget == depId)

  # Première ligne VISUELLE (hors sentinelle `__isNew`) d'une entrée, ou null.
  # L'index dans `_currentData` suit l'ordre de chargement alors que la grille
  # peut être triée : on parcourt donc les lignes affichées par la grille (qui
  # portent leur `rowKey`) au lieu de relier un index à `getRowAt`.
  _firstRow: (entry) ->
    grid = entry?.dataView?._grid
    return null unless grid
    rows = if typeof grid.getData == 'function' then (grid.getData() or []) else []
    for row in rows
      continue if row?.__isNew
      found = if row?.rowKey? and typeof grid.getRow == 'function' then grid.getRow(row.rowKey) else row
      return found if found? and not found.__isNew
    # Repli (grille sans getData, double de test minimal) : ordre de chargement.
    for row, i in (entry.dataView._currentData or [])
      continue if row?.__isNew
      found = grid.getRowAt? i
      return found if found? and not found.__isNew
    null

  # Marque `rowKey` active sur un widget dataView, puis propage la ligne à ses
  # dépendants (récursion). Ne vole pas le focus ni n'ouvre l'édition.
  _selectRow: (entry, rowKey, seen = new WeakSet) ->
    return unless entry?.dataView?
    rowData = entry.dataView._grid?.getRow rowKey
    return unless rowData? and not rowData.__isNew
    entry.dataView.setActiveRow rowKey
    seen.add entry
    @_cascadeToDependents entry, rowData, seen

  # Propage `rowData` de `entry` à ses dépendants dataView. Les widgets plugin
  # dépendants ne sont pas remplis automatiquement.
  _cascadeToDependents: (entry, rowData, seen = new WeakSet) ->
    for child in @_dependentEntries entry
      continue if child.plugin
      if seen.has child
        console.warn "depends_on: cycle détecté autour du widget '#{child.node?.id}'"
        continue
      @_applyDependencySelection child, child.node.depends_on, rowData, seen

  # Aucune ligne disponible : les dépendants (et descendants) passent en
  # « aucun résultat », sans reliquat de l'ancienne sélection.
  _cascadeNone: (entry, seen = new WeakSet) ->
    seen.add entry
    for child in @_dependentEntries entry
      continue if child.plugin
      if seen.has child
        console.warn "depends_on: cycle détecté autour du widget '#{child.node?.id}'"
        continue
      seen.add child
      child.dataView?.setFilter { field: child.node.depends_on?.field, value: null, none: true }
      @_cascadeNone child, seen

  # Au montage : chaque widget racine pourvu de dépendants active sa première
  # ligne et lance la cascade. Les widgets sans dépendants ne sont pas modifiés.
  _initializeCascade: ->
    for entry in @_widgets
      continue if entry.plugin
      continue if entry.node?.depends_on
      continue unless entry.dataView?
      continue unless @_dependentEntries(entry).length > 0
      first = @_firstRow entry
      if first?
        @_selectRow entry, first.rowKey
      else
        @_cascadeNone entry

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
