# custom_view_plugins.coffee — plugin/iframe methods extracted from custom_view.coffee
# Extends the CustomView class (defined in custom_view.js) via its prototype.
# Loaded after views/custom_view.js.

Object.assign window.CustomView::,
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

  # Relais d'une requête GraphQL demandée par un widget. Seul le parent peut
  # ajouter l'en-tête `X-TDB-Widget` : le serveur n'autorise alors que les
  # lectures et les mutations d'enregistrements de données (spec §6,
  # backend/graphql/executor.moon). L'iframe est sandboxée sans jeton ni accès
  # HTTP direct, elle ne peut donc pas contourner ce contrôle.
  _relayWidgetQuery: (query, variables) ->
    GQL.queryWidget query, variables or {}

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
        @_relayWidgetQuery(q, vars).then (data) =>
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
