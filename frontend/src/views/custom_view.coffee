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

window.CustomView = class CustomView
  constructor: (@container, @yamlText, @allSpaces, @allDataViews = [], @options = {}) ->
    @_widgets   = []   # list of { dataView, node, el }
    @_widgetsById = {} # id -> entry
    @_pluginStateByWidgetId = {}
    @_pluginSelectionListenersByWidgetId = {}
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
       setTimeout =>
         for entry in @_widgets
           entry.dataView?._grid?.refreshLayout()
       , 0

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

  # Render an aggregate (GROUP BY) widget as a read-only table.
  _renderAggregate: (container, wNode) ->
    groupBy   = wNode.groupBy   or []
    aggregate = wNode.aggregate or []
    spaceName = wNode.space
    unless spaceName
      container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Paramètre <code>space</code> manquant.</p>"
      return

    # Show loading state
    container.innerHTML = "<p style='color:#888;padding:.5rem'>Chargement…</p>"

    # Normalize aggregate: ensure each entry has fn and as
    makeAlias = (agg) ->
      return agg.as if agg.as
      if not agg.field then 'count' else "#{agg.fn}_#{agg.field}"

    aggInput = for agg in aggregate
      fn: agg.fn, field: (agg.field or null), as: makeAlias(agg)

    Spaces.aggregateSpace(spaceName, groupBy, aggInput).then (rows) =>
      container.innerHTML = ''
      unless rows and rows.length > 0
        container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Aucun résultat.</p>"
        return

      # Evaluate computed columns (client-side JS expressions on each row)
      computed = wNode.computed or []
      computedFns = []
      formulaErrors = []
      for col in computed
        do (col) ->
          try
            fn = new Function('row', "try { return (#{col.expr}); } catch(e) { return '⚠ ' + e.message; }")
            computedFns.push { as: col.as, fn }
          catch e
            formulaErrors.push "#{col.as}: #{e.message}"
            computedFns.push { as: col.as, fn: -> "⚠ formule invalide" }
      if formulaErrors.length > 0
        errDiv = document.createElement 'p'
        errDiv.style.cssText = 'color:#c55;padding:.3rem .5rem;font-size:.85rem;margin:0'
        errDiv.textContent = "Formule invalide : #{formulaErrors.join('; ')}"
        container.appendChild errDiv

      # Augment rows with computed values
      if computedFns.length > 0
        for row in rows
          for c in computedFns
            row[c.as] = c.fn row

      # Build column list from first row keys (preserve groupBy order first)
      keys = groupBy.slice()
      for agg in aggInput
        keys.push agg.as unless agg.as in keys
      for col in computed
        keys.push col.as unless col.as in keys

      tbl = document.createElement 'table'
      tbl.className = 'agg-table'

      thead = document.createElement 'thead'
      tr = document.createElement 'tr'
      for k in keys
        th = document.createElement 'th'
        th.textContent = k
        tr.appendChild th
      thead.appendChild tr
      tbl.appendChild thead

      tbody = document.createElement 'tbody'
      for row in rows
        tr = document.createElement 'tr'
        for k in keys
          td = document.createElement 'td'
          v = row[k]
          td.textContent = if v? then String(v) else ''
          tr.appendChild td
        tbody.appendChild tr
      tbl.appendChild tbody
      container.appendChild tbl
    .catch (err) =>
      @_setMessage container, "Erreur : #{err.message or err}", 'color:#c55;padding:.5rem'

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

  _setPluginSelectionListener: (widgetId, listener) ->
    return unless widgetId
    @_pluginSelectionListenersByWidgetId[widgetId] ?= []
    @_pluginSelectionListenersByWidgetId[widgetId].push listener
    st = @_pluginStateByWidgetId[widgetId]
    if st
      st.listeners ?= []
      st.listeners.push listener

  _emitPluginSelection: (widgetId, selection) ->
    st = @_pluginStateByWidgetId[widgetId]
    return unless st
    for fn in (st.listeners or [])
      try
        fn selection
      catch e
        console.warn 'plugin selection listener error', e

  _renderPluginWidget: (container, wNode, runtimeWidgetId = null) ->
    pluginName = wNode.type
    pluginParams = wNode.params or {}
    unless pluginName
      container.innerHTML = "<p style='color:#c55;padding:.5rem'>Plugin manquant (<code>type</code>).</p>"
      return
    @_setMessage container, "Chargement du plugin #{pluginName}…", 'color:#888;padding:.5rem'
    WidgetPlugins.getByName(pluginName).then (plugin) =>
      unless plugin
        @_setMessage container, "Plugin introuvable : #{pluginName}", 'color:#c55;padding:.5rem'
        return
      widgetId = runtimeWidgetId or wNode.id or "plugin_#{Math.random().toString(36).slice(2)}"
      @_mountPluginIframe container, widgetId, plugin, pluginParams
    .catch (err) =>
      @_setMessage container, "Erreur plugin : #{err.message or err}", 'color:#c55;padding:.5rem'

  _mountPluginIframe: (container, widgetId, plugin, pluginParams) ->
    compiled = @_compilePlugin plugin, pluginParams
    iframe = document.createElement 'iframe'
    iframe.setAttribute 'sandbox', 'allow-scripts'
    iframe.style.cssText = 'width:100%;height:100%;border:0;background:#fff;'
    container.innerHTML = ''
    container.appendChild iframe

    requestMap = {}
    reqSeq = 0
    listeners = []
    for fn in (@_pluginSelectionListenersByWidgetId[widgetId] or [])
      listeners.push fn
    @_pluginStateByWidgetId[widgetId] = { iframe, listeners, requestMap, reqSeq }

    onMessage = (ev) =>
      return unless ev.source == iframe.contentWindow
      msg = ev.data or {}
      return unless msg.widgetId == widgetId
      if msg.type == 'gql_request'
        q = msg.query or ''
        vars = msg.variables or {}
        reqId = msg.requestId
        GQL.query(q, vars).then (data) =>
          iframe.contentWindow?.postMessage { type: 'gql_response', widgetId, requestId: reqId, data }, '*'
        .catch (err) =>
          iframe.contentWindow?.postMessage { type: 'gql_error', widgetId, requestId: reqId, error: (err.message or String(err)) }, '*'
      else if msg.type == 'emitSelection'
        @_emitPluginSelection widgetId, msg.selection or {}

    window.addEventListener 'message', onMessage
    srcDoc = @_buildPluginIframeDoc widgetId, pluginParams, compiled, plugin
    iframe.srcdoc = srcDoc
    @_pluginStateByWidgetId[widgetId].onMessage = onMessage

  _compilePlugin: (plugin, pluginParams = {}) ->
    scriptLanguage = (plugin.scriptLanguage or 'coffeescript').toLowerCase()
    templateLanguage = (plugin.templateLanguage or 'pug').toLowerCase()
    scriptCode = plugin.scriptCode or ''
    templateCode = plugin.templateCode or ''
    pluginName = plugin.name or plugin.id or '(sans nom)'

    makeCompileError = (source, language, err) ->
      msg = err?.message or String(err)
      line = err?.location?.first_line
      col = err?.location?.first_column
      if line?
        line += 1
        col = (col or 0) + 1
      else
        line = err?.line
        col = err?.column
      loc = if line? then " (ligne #{line}#{if col? then ", colonne #{col}" else ''})" else ''
      new Error "Plugin #{pluginName} — #{source} #{language} invalide#{loc} : #{msg}"

    jsScript = scriptCode
    if scriptLanguage == 'coffeescript'
      csRuntime = window.CoffeeScript
      csCompile = csRuntime?.compile or csRuntime?.default?.compile or csRuntime?.CoffeeScript?.compile
      unless csCompile
        throw new Error "Plugin #{pluginName} — runtime CoffeeScript indisponible"
      try
        jsScript = csCompile scriptCode, { bare: true }
      catch err
        throw makeCompileError 'script', 'CoffeeScript', err

    htmlTemplate = templateCode
    if templateLanguage == 'pug'
      pugRuntime = window.pug
      pugCompile = pugRuntime?.compile or pugRuntime?.default?.compile
      unless pugCompile
        throw new Error "Plugin #{pluginName} — runtime Pug indisponible"
      try
        fn = pugCompile templateCode
        htmlTemplate = fn { params: pluginParams or {} }
      catch err
        throw makeCompileError 'template', 'Pug', err
    { jsScript, htmlTemplate }

  _buildPluginIframeDoc: (widgetId, params, compiled, plugin) ->
    paramsJson = JSON.stringify params or {}
    tpl = JSON.stringify compiled.htmlTemplate or ''
    js = compiled.jsScript or ''
    pluginName = JSON.stringify plugin?.name or plugin?.id or '(sans nom)'
    """
<!doctype html>
<html>
<head><meta charset='utf-8'><style>body{margin:0;font-family:sans-serif}.plugin-root{padding:.5rem}</style></head>
<body>
  <div id='root'></div>
  <script>
    (function() {
      var widgetId = #{JSON.stringify(widgetId)};
      var pluginName = #{pluginName};
      var root = document.getElementById('root');
      var inputSelection = null;
      var listeners = [];
      var pending = {};
      var reqSeq = 1;
      function escapeHtml(txt) {
        return String(txt == null ? '' : txt)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
      }
      function formatRuntimeError(err) {
        var msg = err && err.message ? err.message : String(err);
        var stack = err && err.stack ? String(err.stack) : '';
        var line = null;
        var col = null;
        var m = stack.match(/<anonymous>:(\\d+):(\\d+)/);
        if (m) {
          line = Number(m[1]);
          col = Number(m[2]);
        }
        var loc = line ? (" (ligne " + line + (col ? ", colonne " + col : "") + ")") : "";
        return "Plugin " + pluginName + " — exécution JavaScript invalide" + loc + " : " + msg;
      }
      function renderRuntimeError(err) {
        var txt = formatRuntimeError(err);
        root.innerHTML = "<div style='padding:.5rem;color:#c55;white-space:pre-wrap'>" + escapeHtml(txt) + "</div>";
      }
      function post(msg) { parent.postMessage(Object.assign({ widgetId: widgetId }, msg), '*'); }
      function gql(query, variables) {
        return new Promise(function(resolve, reject) {
          var requestId = String(reqSeq++);
          pending[requestId] = { resolve: resolve, reject: reject };
          post({ type: 'gql_request', requestId: requestId, query: query, variables: variables || {} });
        });
      }
      function emitSelection(selection) { post({ type: 'emitSelection', selection: selection || {} }); }
      function onInputSelection(cb) { if (typeof cb === 'function') listeners.push(cb); }
      function render(html) { root.innerHTML = html == null ? '' : String(html); }

      window.addEventListener('message', function(ev) {
        var msg = ev.data || {};
        if (msg.widgetId !== widgetId) return;
        if (msg.type === 'gql_response' && pending[msg.requestId]) {
          pending[msg.requestId].resolve(msg.data);
          delete pending[msg.requestId];
        } else if (msg.type === 'gql_error' && pending[msg.requestId]) {
          pending[msg.requestId].reject(new Error(msg.error || 'GraphQL error'));
          delete pending[msg.requestId];
        } else if (msg.type === 'updateInputSelection') {
          inputSelection = msg.selection || null;
          listeners.forEach(function(fn) { try { fn(inputSelection); } catch (e) {} });
        }
      });

      var params = #{paramsJson};
      render(#{tpl});
      var module = { exports: null };
      try {
#{js}
        if (typeof module.exports === 'function') {
          module.exports({ gql: gql, emitSelection: emitSelection, onInputSelection: onInputSelection, render: render, params: params });
        }
      } catch (e) {
        renderRuntimeError(e);
      }
    })();
  </script>
</body>
</html>
"""

  _sendPluginMessage: (widgetId, msg) ->
    st = @_pluginStateByWidgetId[widgetId]
    return unless st?.iframe?.contentWindow
    payload = Object.assign { widgetId }, msg
    st.iframe.contentWindow.postMessage payload, '*'

  _findSpace: (nameOrId) ->
    return null unless nameOrId
    sp = @allSpaces.find (s) -> s.name == nameOrId or s.id == nameOrId
    return sp if sp

    # Search in Data Views if not found in regular spaces
    dv = @allDataViews.find (v) -> v.name == nameOrId or v.id == nameOrId
    if dv
      # Create a virtual space object for DataView class compatibility
      return {
        id: dv.id
        name: dv.name
        isView: true
        viewId: dv.id
        fields: dv.config?.columns?.map (c) -> { name: c, fieldType: 'String' } or []
      }
    null

  unmount: ->
    for own id, st of @_pluginStateByWidgetId
      window.removeEventListener 'message', st.onMessage if st.onMessage
    for entry in @_widgets
      entry.dataView?.unmount?()
    @container.innerHTML = ''
    @_widgets     = []
    @_pluginStateByWidgetId = {}
    @_pluginSelectionListenersByWidgetId = {}
    @_widgetsById = {}

  # Ajouter les poignées de redimensionnement pour les zones (Phase 3)
  _addResizeHandle: (zoneElement, zone) ->
    return unless zone.factor and zone.id

    SNAP_POINTS = [0.25, 0.33, 0.5, 0.66, 0.75]
    SNAP_THRESHOLD = 0.05

    # Créer la poignée de redimensionnement
    resizeHandle = document.createElement 'div'
    resizeHandle.className = 'resize-handle'
    resizeHandle.setAttribute 'data-zone-id', zone.id
    resizeHandle.innerHTML = '⋮'

    # Positionner la poignée
    if zone.direction == 'horizontal'
      resizeHandle.style.position = 'absolute'
      resizeHandle.style.right = '0'
      resizeHandle.style.top = '50%'
      resizeHandle.style.transform = 'translateY(-50%)'
    else
      resizeHandle.style.position = 'absolute'
      resizeHandle.style.bottom = '0'
      resizeHandle.style.left = '50%'
      resizeHandle.style.transform = 'translateX(-50%)'

    # Ajouter les événements de drag
    isDragging = false
    startX = 0
    startY = 0
    startFactor = zone.factor

    resizeHandle.addEventListener 'mousedown', (evt) =>
      isDragging = true
      startX = evt.clientX
      startY = evt.clientY
      startFactor = parseFloat(zoneElement.getAttribute('data-zone-factor'))
      document.body.style.cursor = 'ew-resize'
      evt.preventDefault()

    document.addEventListener 'mousemove', (evt) =>
      return unless isDragging

      # Calculer le nouveau factor
      deltaX = evt.clientX - startX
      deltaY = evt.clientY - startY

      if zone.direction == 'horizontal'
        newFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaX / 200))
      else
        newFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaY / 200))

      # Mettre à jour visuellement
      zoneElement.style.flex = String(newFactor)
      zoneElement.setAttribute 'data-zone-factor', String(newFactor)

      # Afficher le tooltip
      @_showResizeTooltip zoneElement, newFactor

    document.addEventListener 'mouseup', (evt) =>
      return unless isDragging

      isDragging = false
      document.body.style.cursor = ''

      # Calculer le factor final
      deltaX = evt.clientX - startX
      deltaY = evt.clientY - startY

      if zone.direction == 'horizontal'
        finalFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaX / 200))
      else
        finalFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaY / 200))

      # Snap to predefined proportions
      for snapPoint in SNAP_POINTS
        if Math.abs(finalFactor - snapPoint) < SNAP_THRESHOLD
          finalFactor = snapPoint
          break

      # Déclencher la mutation GraphQL
      @_onZoneResize zone.id, finalFactor

      # Cacher le tooltip
      @_hideResizeTooltip()

    zoneElement.appendChild resizeHandle
    zoneElement.style.position = 'relative'  # Nécessaire pour le positionnement absolu

  # Afficher le tooltip de redimensionnement
  _showResizeTooltip: (zoneElement, factor) ->
    tooltip = document.createElement 'div'
    tooltip.className = 'resize-tooltip'
    tooltip.textContent = "#{Math.round(factor * 100)}%"
    tooltip.style.position = 'absolute'
    tooltip.style.top = '-30px'
    tooltip.style.left = '50%'
    tooltip.style.transform = 'translateX(-50%)'
    tooltip.style.background = '#333'
    tooltip.style.color = 'white'
    tooltip.style.padding = '4px 8px'
    tooltip.style.borderRadius = '4px'
    tooltip.style.fontSize = '12px'
    tooltip.style.zIndex = '1000'

    # Supprimer l'ancien tooltip s'il existe
    oldTooltip = zoneElement.querySelector('.resize-tooltip')
    oldTooltip?.remove()

    zoneElement.appendChild tooltip

  # Cacher le tooltip de redimensionnement
  _hideResizeTooltip: ->
    tooltips = document.querySelectorAll '.resize-tooltip'
    for tooltip in tooltips
      tooltip.remove()

  # Callback pour le redimensionnement de zone
  _onZoneResize: (zoneId, factor) ->
    # Émettre un événement personnalisé pour que l'application parente puisse gérer
    event = new CustomEvent 'zone-resize', {
      detail: { zoneId, factor }
    }
    document.dispatchEvent event

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
