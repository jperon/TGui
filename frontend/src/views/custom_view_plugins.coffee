# custom_view_plugins.coffee — plugin/iframe methods extracted from custom_view.coffee
# Extends the CustomView class (defined in custom_view.js) via its prototype.
# Loaded after views/custom_view.js.

# Mutations d'enregistrements autorisées depuis un widget (spec §6). Elles sont
# relayées avec l'en-tête widget : le serveur garde sa propre liste blanche
# (backend/graphql/executor.moon WIDGET_ALLOWED_MUTATIONS).
UPDATE_RECORD_MUTATION = """
  mutation WidgetUpdateRecord($spaceId: ID!, $id: ID!, $data: JSON!) {
    updateRecord(spaceId: $spaceId, id: $id, data: $data) { id data }
  }
"""

INSERT_RECORD_MUTATION = """
  mutation WidgetInsertRecord($spaceId: ID!, $data: JSON!) {
    insertRecord(spaceId: $spaceId, data: $data) { id data }
  }
"""

DELETE_RECORD_MUTATION = """
  mutation WidgetDeleteRecord($spaceId: ID!, $id: ID!) {
    deleteRecord(spaceId: $spaceId, id: $id)
  }
"""

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

  # ── Manifest, accès et mappage (spec widgets personnalisés §3, §6) ─────────
  # Le manifeste est du YAML analysé côté parent : c'est lui qui décide de ce
  # que l'iframe reçoit. Un manifeste invalide (import direct en base) est
  # traité comme `read` : jamais plus de droits que déclaré.
  _pluginManifest: (plugin) ->
    text = plugin?.manifest
    return null unless text and String(text).trim() != ''
    parser = window.jsyaml
    return { invalid: true } unless parser and typeof parser.load == 'function'
    try
      parsed = parser.load text
    catch e
      console.warn 'widget manifest: YAML invalide', e
      return { invalid: true }
    # Fichier ne contenant que des commentaires : pas de manifeste.
    return null unless parsed and typeof parsed == 'object'
    parsed

  # `access` effectif : valeur du manifeste, `read` si elle manque, `full` sans
  # manifeste (rétrocompatibilité : aucun plugin existant ne casse).
  _pluginAccessOf: (plugin) ->
    manifest = @_pluginManifest plugin
    return 'full' unless manifest
    return 'read' if manifest.invalid
    access = String(manifest.access or 'read').toLowerCase()
    return access if access in ['none', 'read', 'full']
    'read'

  # Mappage déclaré → champ de la source. Un tableau (`columns: [a, b]`) est un
  # widget tableau, pas un mappage.
  _pluginColumnMapping: (node) ->
    columns = node?.columns
    return null unless columns and typeof columns == 'object'
    return null if Array.isArray columns
    columns

  # Colonnes obligatoires du manifeste absentes du mappage.
  _pluginMissingColumns: (manifest, mapping) ->
    return [] unless manifest and manifest.columns and manifest.columns.length
    missing = []
    for col in manifest.columns
      continue unless col and col.name
      continue if col.optional == true
      missing.push col.name unless mapping and mapping[col.name]
    missing

  # Type d'opération GraphQL, sans faire confiance au texte brut : on saute
  # espaces, virgules et commentaires `#…`, puis on lit le premier mot. `{` est
  # une query anonyme ; query/mutation/subscription sont explicites ; tout le
  # reste (fragment, texte inattendu) renvoie null et sera refusé.
  _widgetQueryOperation: (query) ->
    s = String query or ''
    n = s.length
    i = 0
    loop
      while i < n and /[\s,]/.test s.charAt(i)
        i++
      if s.charAt(i) == '#'
        i++ while i < n and s.charAt(i) != '\n'
        continue
      break
    return null if i >= n
    return 'query' if s.charAt(i) == '{'
    m = s.slice(i).match /^([_A-Za-z][_0-9A-Za-z]*)/
    return null unless m
    word = m[1].toLowerCase()
    return word if word in ['query', 'mutation', 'subscription']
    null

  # nil quand la requête est autorisée, sinon le message de refus (spec §6).
  # En cas de doute (opération illisible), on refuse.
  _widgetQueryRefusal: (access, query) ->
    if access == 'none'
      return 'Ce widget n’a pas accès aux données (manifest access: none).'
    op = @_widgetQueryOperation query
    unless op
      return 'Requête GraphQL illisible : refusée par sécurité (le type d’opération doit être explicite).'
    if access == 'read' and op != 'query'
      return "Seules les lectures sont autorisées (manifest access: read) : opération « #{op} » refusée."
    if access == 'full' and op == 'subscription'
      return 'Les souscriptions sont refusées depuis un widget.'
    null

  # Ligne de la source renommée selon le mappage (+ `id`), pour l'API de
  # données de l'iframe. Sans mappage : la ligne telle quelle.
  _pluginRenameRow: (node, row) ->
    return row unless row
    mapping = @_pluginColumnMapping node
    return row unless mapping
    out = {}
    out.id = row.id if row.id?
    for declared, field of mapping
      continue unless field
      out[declared] = row[field] if row[field]?
    out

  # Valeurs de l'iframe (noms déclarés) → noms de champs. Sans mappage, les
  # noms sont déjà ceux de la source. `id` n'est jamais écrit.
  _pluginTranslateValues: (mapping, values) ->
    out = {}
    return out unless values and typeof values == 'object'
    for key, value of values
      continue if key == 'id'
      field = if mapping then mapping[key] else key
      continue unless field
      out[field] = value
    out

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
      manifest = @_pluginManifest plugin
      access = @_pluginAccessOf plugin
      mapping = @_pluginColumnMapping wNode
      space = @_findSpace wNode.space
      missing = @_pluginMissingColumns manifest, mapping
      if missing.length > 0
        # Colonne obligatoire non mappée : message dans le widget, aucun
        # chargement (spec §3). Le YAML de page doit déclarer
        # `columns: {<nom déclaré>: <champ>}`.
        @_setMessage container,
          "Widget « #{pluginName} » : colonne(s) obligatoire(s) non mappée(s) : #{missing.join ', '}. " +
          "Ajoutez <code>columns: {#{missing[0]}: <champ>}</code> au widget.",
          'color:#c55;padding:.5rem'
        return
      @_mountPluginIframe container, widgetId, plugin, pluginParams, {
        access, manifest, mapping, space, node: wNode
      }
    .catch (err) =>
      @_setMessage container, "Erreur plugin : #{err.message or err}", 'color:#c55;padding:.5rem'

  # Lignes de la source du widget, pour `onRecords`. Même résolution que la
  # grille (Data View, champs calculés via le résolveur dynamique, ou records
  # bruts), limitée aux colonnes utiles.
  _loadPluginSourceRows: (node, space, access) ->
    return Promise.resolve [] unless access in ['read', 'full']
    return Promise.resolve [] unless node?.space
    unless space
      return Promise.reject new Error "Source introuvable : #{node.space}"
    if space.isView
      return DataViews.execute(space.viewId, 2000, 0).then (rows) ->
        for r in rows or []
          row = Object.assign {}, r
          row.id ?= r.id
          row
    fields = space.fields or []
    if not fields.length
      return Promise.resolve []
    computed = (f for f in fields when (f.formula and f.formula != '') or (f.reprFormula and f.reprFormula != ''))
    if computed.length > 0
      tname = @_pluginGqlName space.name
      names = (@_pluginGqlName(f.name) for f in fields when f.name)
      query = "query($limit: Int) { #{tname}(limit: $limit) { items { _id #{names.join ' '} } } }"
      return GQL.query(query, { limit: 2000 }).then (data) ->
        for item in (data?[tname]?.items or [])
          row = Object.assign {}, item
          row.id = item._id
          delete row._id
          row
    query = """
      query PluginRecords($spaceId: ID!, $limit: Int) {
        records(spaceId: $spaceId, limit: $limit) { items { id data } }
      }
    """
    GQL.query(query, { spaceId: space.id, limit: 2000 }).then (data) ->
      for r in (data?.records?.items or [])
        parsed = if typeof r.data == 'string' then JSON.parse(r.data) else (r.data or {})
        row = Object.assign {}, parsed
        row.id = r.id
        row

  _pluginGqlName: (name) ->
    s = String(name or '').replace /[^\w]/g, '_'
    if /^\d/.test(s) then '_' + s else s

  # Compilation d'abord (asynchrone : les compilateurs CoffeeScript/pug sont
  # chargés à la demande, spec §7), puis construction de l'iframe. Un échec de
  # chargement ou de compilation s'affiche dans le widget, jamais avalé.
  _mountPluginIframe: (container, widgetId, plugin, pluginParams, ctx = {}) ->
    @_compilePlugin(plugin, pluginParams).then (compiled) =>
      @_mountCompiledPluginIframe container, widgetId, plugin, pluginParams, compiled, ctx
    .catch (err) =>
      @_setMessage container, "Erreur plugin : #{err.message or err}", 'color:#c55;padding:.5rem'

  _mountCompiledPluginIframe: (container, widgetId, plugin, pluginParams, compiled, ctx = {}) ->
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
    state = {
      iframe, listeners, requestMap, reqSeq
      access: ctx.access or 'full'
      mapping: ctx.mapping or null
      space: ctx.space or null
      node: ctx.node or null
      ready: false
      rows: []
      rawRows: []
    }
    @_pluginStateByWidgetId[widgetId] = state

    postToFrame = (msg) =>
      iframe.contentWindow?.postMessage Object.assign({ widgetId }, msg), '*'

    sendRecords = =>
      return unless state.ready
      postToFrame { type: 'records', rows: state.rows }

    reload = =>
      @_loadPluginSourceRows(ctx.node, ctx.space, state.access).then (rawRows) =>
        return unless @_pluginStateByWidgetId[widgetId] == state
        state.rawRows = rawRows or []
        state.rows = (@_pluginRenameRow ctx.node, r for r in state.rawRows)
        sendRecords()
      .catch (err) =>
        postToFrame { type: 'records', rows: [], error: (err?.message or String err) }

    onMessage = (ev) =>
      return unless ev.source == iframe.contentWindow
      msg = ev.data or {}
      return unless msg.widgetId == widgetId
      switch msg.type
        when 'gql_request'
          refusal = @_widgetQueryRefusal state.access, msg.query
          if refusal
            postToFrame { type: 'gql_error', requestId: msg.requestId, error: refusal }
            return
          @_relayWidgetQuery(msg.query or '', msg.variables or {}).then (data) =>
            postToFrame { type: 'gql_response', requestId: msg.requestId, data }
          .catch (err) =>
            postToFrame { type: 'gql_error', requestId: msg.requestId, error: (err.message or String(err)) }
        when 'emitSelection'
          @_emitPluginSelection widgetId, msg.selection or {}
        when 'plugin_ready'
          state.ready = true
          reload()
        when 'setCursor'
          raw = null
          for row in state.rawRows
            if row.id? and String(row.id) == String(msg.id)
              raw = row
              break
          selection = if raw then { rows: [raw] } else { rows: [{ id: msg.id }] }
          @_emitPluginSelection widgetId, selection
        when 'updateRecord', 'insertRecord', 'deleteRecord'
          @_handlePluginWrite widgetId, state, msg
        else
          null

    window.addEventListener 'message', onMessage
    srcDoc = @_buildPluginIframeDoc widgetId, pluginParams, compiled, plugin, state
    iframe.srcdoc = srcDoc
    state.onMessage = onMessage
    state.reload = reload

  # Écritures demandées par l'iframe : réservées à `access: full`, valeurs
  # traduites noms déclarés → noms de champs, mutations relayées via
  # GQL.queryWidget (le serveur garde sa liste blanche), puis rechargement.
  _handlePluginWrite: (widgetId, state, msg) ->
    postToFrame = (payload) =>
      state.iframe.contentWindow?.postMessage Object.assign({ widgetId }, payload), '*'
    refuse = (error) =>
      postToFrame { type: 'write_error', requestId: msg.requestId, error }
    if state.access != 'full'
      return refuse 'Écriture refusée : ce widget est en lecture seule (manifest access ≠ full).'
    unless state.space?.id
      return refuse 'Écriture impossible : aucune source de données pour ce widget.'
    spaceId = state.space.id
    mapping = state.mapping
    promise = null
    switch msg.type
      when 'updateRecord'
        values = @_pluginTranslateValues mapping, msg.values
        promise = GQL.queryWidget UPDATE_RECORD_MUTATION, { spaceId, id: msg.id, data: values }
      when 'insertRecord'
        values = @_pluginTranslateValues mapping, msg.values
        promise = GQL.queryWidget INSERT_RECORD_MUTATION, { spaceId, data: values }
      when 'deleteRecord'
        promise = GQL.queryWidget DELETE_RECORD_MUTATION, { spaceId, id: msg.id }
    return refuse 'Opération d’écriture inconnue.' unless promise
    promise.then (data) =>
      postToFrame { type: 'write_response', requestId: msg.requestId, data }
      state.reload?()
    .catch (err) =>
      refuse err.message or String(err)

  # Compile a widget definition. Asynchronous: the compilers (CoffeeScript,
  # pug) are loaded on demand (§7), only for the languages it uses. A widget
  # written in javascript + html triggers no load at all.
  _compilePlugin: (plugin, pluginParams = {}) ->
    scriptLanguage = (plugin.scriptLanguage or 'coffeescript').toLowerCase()
    templateLanguage = (plugin.templateLanguage or 'pug').toLowerCase()
    pluginName = plugin.name or plugin.id or '(sans nom)'
    runtimes = window.PluginRuntimes
    unless runtimes and typeof runtimes.ensure == 'function'
      return Promise.reject new Error(
        "Plugin #{pluginName} — chargeur de compilateurs absent (views/plugin_runtimes.js non chargé)"
      )
    runtimes.ensure([scriptLanguage, templateLanguage]).then =>
      @_compilePluginCode plugin, pluginParams, scriptLanguage, templateLanguage

  _compilePluginCode: (plugin, pluginParams, scriptLanguage, templateLanguage) ->
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

  _buildPluginIframeDoc: (widgetId, params, compiled, plugin, ctx = {}) ->
    paramsJson = JSON.stringify params or {}
    tpl = JSON.stringify compiled.htmlTemplate or ''
    js = compiled.jsScript or ''
    pluginName = JSON.stringify plugin?.name or plugin?.id or '(sans nom)'
    access = ctx?.access or 'full'
    canRead = access in ['read', 'full']
    canWrite = access == 'full'
    gqlExposed = access in ['read', 'full']

    dataApiJs = if canRead then """
      var latestRows = [];
      var recordsLoaded = false;
      var recordCallbacks = [];
      var currentRecord = null;
      var recordListeners = [];
      function notifyAll(list, value) {
        list.forEach(function(fn) { try { fn(value); } catch (e) {} });
      }
      function onRecords(cb) {
        if (typeof cb !== 'function') return;
        recordCallbacks.push(cb);
        if (recordsLoaded) { try { cb(latestRows); } catch (e) {} }
      }
      function onRecord(cb) {
        if (typeof cb !== 'function') return;
        recordListeners.push(cb);
        if (currentRecord !== null) { try { cb(currentRecord); } catch (e) {} }
      }
    """ else ''

    writeApiJs = if canWrite then """
      var pendingWrites = {};
      var writeSeq = 1;
      function writeRequest(type, payload) {
        return new Promise(function(resolve, reject) {
          var requestId = String(writeSeq++);
          pendingWrites[requestId] = { resolve: resolve, reject: reject };
          post(Object.assign({ type: type, requestId: requestId }, payload));
        });
      }
      function updateRecord(id, values) { return writeRequest('updateRecord', { id: id, values: values || {} }); }
      function insertRecord(values) { return writeRequest('insertRecord', { values: values || {} }); }
      function deleteRecord(id) { return writeRequest('deleteRecord', { id: id }); }
    """ else ''

    """<!doctype html>
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
      function setCursor(id) { post({ type: 'setCursor', id: id }); }
#{dataApiJs}
#{writeApiJs}
      window.addEventListener('message', function(ev) {
        var msg = ev.data || {};
        if (msg.widgetId !== widgetId) return;
        if (msg.type === 'gql_response' && pending[msg.requestId]) {
          pending[msg.requestId].resolve(msg.data);
          delete pending[msg.requestId];
        } else if (msg.type === 'gql_error' && pending[msg.requestId]) {
          pending[msg.requestId].reject(new Error(msg.error || 'GraphQL error'));
          delete pending[msg.requestId];
        } else if (msg.type === 'records') {
          latestRows = msg.rows || [];
          recordsLoaded = true;
          notifyAll(recordCallbacks, latestRows);
          if (msg.error) renderRuntimeError(new Error('Chargement des données : ' + msg.error));
        } else if (msg.type === 'write_response' && pendingWrites[msg.requestId]) {
          pendingWrites[msg.requestId].resolve(msg.data);
          delete pendingWrites[msg.requestId];
        } else if (msg.type === 'write_error' && pendingWrites[msg.requestId]) {
          pendingWrites[msg.requestId].reject(new Error(msg.error || 'Écriture refusée'));
          delete pendingWrites[msg.requestId];
        } else if (msg.type === 'updateInputSelection') {
          inputSelection = msg.selection || null;
          listeners.forEach(function(fn) { try { fn(inputSelection); } catch (e) {} });
          currentRecord = (msg.record === undefined) ? null : msg.record;
          notifyAll(recordListeners, currentRecord);
        }
      });

      var params = #{paramsJson};
      render(#{tpl});
      var module = { exports: null };
      var api = {
        emitSelection: emitSelection,
        onInputSelection: onInputSelection,
        render: render,
        params: params,
        setCursor: setCursor
      };
      #{if gqlExposed then 'api.gql = gql;' else ''}
      #{if canRead then 'api.onRecords = onRecords; api.onRecord = onRecord;' else ''}
      #{if canWrite then 'api.updateRecord = updateRecord; api.insertRecord = insertRecord; api.deleteRecord = deleteRecord;' else ''}
      try {
#{js}
        if (typeof module.exports === 'function') module.exports(api);
      } catch (e) {
        renderRuntimeError(e);
      }
      post({ type: 'plugin_ready' });
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
