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
  constructor: (@container, @yamlText, @allSpaces) ->
    @_widgets   = []   # list of { dataView, node, el }
    @_widgetsById = {} # id -> entry
    @_pluginStateByWidgetId = {}
    @_pluginSelectionListenersByWidgetId = {}

  mount: ->
    @container.innerHTML = ''
    @_widgets     = []
    @_widgetsById = {}
    try
      parsed = jsyaml.load @yamlText
    catch e
      @container.innerHTML = "<p style='color:red;padding:1rem'>YAML invalide : #{e.message}</p>"
      return

    root = parsed?.layout
    unless root
      @container.innerHTML = "<p style='color:#888;padding:1rem'>Pas de section <code>layout</code> dans le YAML.</p>"
      return

    el = @_renderZoneOrWidget root
    @container.style.cssText = 'display:flex;flex-direction:column;height:100%;'
    @container.appendChild el

    # Wire depends_on after all widgets are mounted
    @_wireDepends()

    # Refresh grid layouts now that elements are in the live DOM
    setTimeout =>
      for entry in @_widgets
        entry.dataView?._grid?.refreshLayout()
    , 0

  # Renders either a zone (direction+children) or a widget node.
  # Applies `factor` (flex proportion) when specified (default: 1).
  # Supports both inline zone keys (direction/children) and wrapped "- layout:" syntax.
  _renderZoneOrWidget: (node) ->
    zone = if node.layout then node.layout else node
    if zone.widget
      el = @_renderWidget zone.widget
    else
      el = document.createElement 'div'
      el.className = "cv-zone #{zone.direction or 'vertical'}"
      for child in (zone.children or [])
        el.appendChild @_renderZoneOrWidget child
    el.style.flex = if node.factor? then String(node.factor) else '1'
    el

  _renderWidget: (wNode) ->
    wrapper = document.createElement 'div'
    wrapper.className = 'cv-widget'

    # Title bar
    titleBar = document.createElement 'div'
    titleBar.className = 'cv-widget-title'
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
      @_renderPluginWidget body, wNode
      entry = { dataView: null, node: wNode, el: wrapper, plugin: true }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    # Regular data widget
    sp = @_findSpace wNode.space
    delBtn = document.createElement 'button'
    delBtn.className = 'cv-widget-delete-btn'
    delBtn.title = 'Supprimer les enregistrements sélectionnés'
    delBtn.textContent = '🗑'
    titleBar.appendChild delBtn

    unless sp
      body.innerHTML = "<p style='color:#aaa;padding:.5rem'>Espace « #{wNode.space} » introuvable.</p>"
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
    # Apply formula filter from YAML widget config
    if wNode.filter
      formula = if typeof wNode.filter == 'string' then wNode.filter else (wNode.filter.formula or '')
      lang    = if typeof wNode.filter == 'object' then (wNode.filter.language or 'moonscript') else 'moonscript'
      dv._formulaFilter = formula if formula
    dv.mount()
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
      container.innerHTML = "<p style='color:#c55;padding:.5rem'>Erreur : #{err.message or err}</p>"

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
            rowKey = ev.rowKey
            return unless rowKey?
            rowData = src.dataView._currentData[rowKey]
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
      @_sendPluginMessage entry.node.id, {
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

  _renderPluginWidget: (container, wNode) ->
    pluginName = wNode.type
    pluginParams = wNode.params or {}
    unless pluginName
      container.innerHTML = "<p style='color:#c55;padding:.5rem'>Plugin manquant (<code>type</code>).</p>"
      return
    container.innerHTML = "<p style='color:#888;padding:.5rem'>Chargement du plugin #{pluginName}…</p>"
    WidgetPlugins.getByName(pluginName).then (plugin) =>
      unless plugin
        container.innerHTML = "<p style='color:#c55;padding:.5rem'>Plugin introuvable : #{pluginName}</p>"
        return
      widgetId = wNode.id or "plugin_#{Math.random().toString(36).slice(2)}"
      @_mountPluginIframe container, widgetId, plugin, pluginParams
    .catch (err) =>
      container.innerHTML = "<p style='color:#c55;padding:.5rem'>Erreur plugin : #{err.message or err}</p>"

  _mountPluginIframe: (container, widgetId, plugin, pluginParams) ->
    compiled = @_compilePlugin plugin
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
    srcDoc = @_buildPluginIframeDoc widgetId, pluginParams, compiled
    iframe.srcdoc = srcDoc
    @_pluginStateByWidgetId[widgetId].onMessage = onMessage

  _compilePlugin: (plugin) ->
    scriptLanguage = (plugin.scriptLanguage or 'coffeescript').toLowerCase()
    templateLanguage = (plugin.templateLanguage or 'pug').toLowerCase()
    scriptCode = plugin.scriptCode or ''
    templateCode = plugin.templateCode or ''

    jsScript = scriptCode
    if scriptLanguage == 'coffeescript'
      unless window.CoffeeScript?.compile
        throw new Error 'CoffeeScript runtime indisponible'
      jsScript = window.CoffeeScript.compile scriptCode, { bare: true }

    htmlTemplate = templateCode
    if templateLanguage == 'pug'
      unless window.pug?.compile
        throw new Error 'Pug runtime indisponible'
      fn = window.pug.compile templateCode
      htmlTemplate = fn {}
    { jsScript, htmlTemplate }

  _buildPluginIframeDoc: (widgetId, params, compiled) ->
    paramsJson = JSON.stringify params or {}
    tpl = JSON.stringify compiled.htmlTemplate or ''
    js = compiled.jsScript or ''
    """
<!doctype html>
<html>
<head><meta charset='utf-8'><style>body{margin:0;font-family:sans-serif}.plugin-root{padding:.5rem}</style></head>
<body>
  <div id='root'></div>
  <script>
    (function() {
      var widgetId = #{JSON.stringify(widgetId)};
      var root = document.getElementById('root');
      var inputSelection = null;
      var listeners = [];
      var pending = {};
      var reqSeq = 1;
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
        render("<div style='padding:.5rem;color:#c55'>Erreur plugin: " + (e && e.message ? e.message : e) + "</div>");
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
    @allSpaces.find (sp) -> sp.name == nameOrId or sp.id == nameOrId

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
