(function() {
  // custom_view_plugins.coffee — plugin/iframe methods extracted from custom_view.coffee
  // Extends the CustomView class (defined in custom_view.js) via its prototype.
  // Loaded after views/custom_view.js.

  // Mutations d'enregistrements autorisées depuis un widget (spec §6). Elles sont
  // relayées avec l'en-tête widget : le serveur garde sa propre liste blanche
  // (backend/graphql/executor.moon WIDGET_ALLOWED_MUTATIONS).
  var BUILTIN_WIDGET_TYPES, DELETE_RECORD_MUTATION, DETACHED_PAGE_QUERY, DETACH_WIDGET_PLUGIN_MUTATION, INSERT_RECORD_MUTATION, UPDATE_RECORD_MUTATION,
    indexOf = [].indexOf;

  UPDATE_RECORD_MUTATION = `mutation WidgetUpdateRecord($spaceId: ID!, $id: ID!, $data: JSON!) {
  updateRecord(spaceId: $spaceId, id: $id, data: $data) { id data }
}`;

  INSERT_RECORD_MUTATION = `mutation WidgetInsertRecord($spaceId: ID!, $data: JSON!) {
  insertRecord(spaceId: $spaceId, data: $data) { id data }
}`;

  DELETE_RECORD_MUTATION = `mutation WidgetDeleteRecord($spaceId: ID!, $id: ID!) {
  deleteRecord(spaceId: $spaceId, id: $id)
}`;

  // « Détacher » une instance (spec widgets personnalisés §4) : la mutation copie
  // la définition et réécrit le `type:` de cette seule instance.
  DETACH_WIDGET_PLUGIN_MUTATION = `mutation DetachWidgetPlugin($pageId: ID!, $widgetId: ID!, $newName: String) {
  detachWidgetPlugin(pageId: $pageId, widgetId: $widgetId, newName: $newName) {
    id
    name
    description
    scriptLanguage
    templateLanguage
    scriptCode
    templateCode
    manifest
    appId
  }
}`;

  // Relecture de la page après détachement : le serveur a réécrit son YAML.
  DETACHED_PAGE_QUERY = `query DetachedPage($id: ID!) {
  customView(id: $id) {
    id
    name
    description
    yaml
    createdAt
    updatedAt
  }
}`;

  // Types fournis par le programme : ils n'ont pas de définition à détacher.
  BUILTIN_WIDGET_TYPES = ['aggregate', 'table'];

  Object.assign(window.CustomView.prototype, {
    _setPluginSelectionListener: function(widgetId, listener) {
      var base, st;
      if (!widgetId) {
        return;
      }
      if ((base = this._pluginSelectionListenersByWidgetId)[widgetId] == null) {
        base[widgetId] = [];
      }
      this._pluginSelectionListenersByWidgetId[widgetId].push(listener);
      st = this._pluginStateByWidgetId[widgetId];
      if (st) {
        if (st.listeners == null) {
          st.listeners = [];
        }
        return st.listeners.push(listener);
      }
    },
    _emitPluginSelection: function(widgetId, selection) {
      var e, fn, j, len, ref, results, st;
      st = this._pluginStateByWidgetId[widgetId];
      if (!st) {
        return;
      }
      ref = st.listeners || [];
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        fn = ref[j];
        try {
          results.push(fn(selection));
        } catch (error1) {
          e = error1;
          results.push(console.warn('plugin selection listener error', e));
        }
      }
      return results;
    },
    // Relais d'une requête GraphQL demandée par un widget. Seul le parent peut
    // ajouter l'en-tête `X-TDB-Widget` : le serveur n'autorise alors que les
    // lectures et les mutations d'enregistrements de données (spec §6,
    // backend/graphql/executor.moon). L'iframe est sandboxée sans jeton ni accès
    // HTTP direct, elle ne peut donc pas contourner ce contrôle.
    _relayWidgetQuery: function(query, variables) {
      return GQL.queryWidget(query, variables || {});
    },
    // ── Manifest, accès et mappage (spec widgets personnalisés §3, §6) ─────────
    // Le manifeste est du YAML analysé côté parent : c'est lui qui décide de ce
    // que l'iframe reçoit. Un manifeste invalide (import direct en base) est
    // traité comme `read` : jamais plus de droits que déclaré.
    _pluginManifest: function(plugin) {
      var e, parsed, parser, text;
      text = plugin != null ? plugin.manifest : void 0;
      if (!(text && String(text).trim() !== '')) {
        return null;
      }
      parser = window.jsyaml;
      if (!(parser && typeof parser.load === 'function')) {
        return {
          invalid: true
        };
      }
      try {
        parsed = parser.load(text);
      } catch (error1) {
        e = error1;
        console.warn('widget manifest: YAML invalide', e);
        return {
          invalid: true
        };
      }
      if (!(parsed && typeof parsed === 'object')) {
        // Fichier ne contenant que des commentaires : pas de manifeste.
        return null;
      }
      return parsed;
    },
    // `access` effectif : valeur du manifeste, `read` si elle manque, `full` sans
    // manifeste (rétrocompatibilité : aucun plugin existant ne casse).
    _pluginAccessOf: function(plugin) {
      var access, manifest;
      manifest = this._pluginManifest(plugin);
      if (!manifest) {
        return 'full';
      }
      if (manifest.invalid) {
        return 'read';
      }
      access = String(manifest.access || 'read').toLowerCase();
      if (access === 'none' || access === 'read' || access === 'full') {
        return access;
      }
      return 'read';
    },
    // Mappage déclaré → champ de la source. Un tableau (`columns: [a, b]`) est un
    // widget tableau, pas un mappage.
    _pluginColumnMapping: function(node) {
      var columns;
      columns = node != null ? node.columns : void 0;
      if (!(columns && typeof columns === 'object')) {
        return null;
      }
      if (Array.isArray(columns)) {
        return null;
      }
      return columns;
    },
    // Colonnes obligatoires du manifeste absentes du mappage.
    _pluginMissingColumns: function(manifest, mapping) {
      var col, j, len, missing, ref;
      if (!(manifest && manifest.columns && manifest.columns.length)) {
        return [];
      }
      missing = [];
      ref = manifest.columns;
      for (j = 0, len = ref.length; j < len; j++) {
        col = ref[j];
        if (!(col && col.name)) {
          continue;
        }
        if (col.optional === true) {
          continue;
        }
        if (!(mapping && mapping[col.name])) {
          missing.push(col.name);
        }
      }
      return missing;
    },
    // Type d'opération GraphQL, sans faire confiance au texte brut : on saute
    // espaces, virgules et commentaires `#…`, puis on lit le premier mot. `{` est
    // une query anonyme ; query/mutation/subscription sont explicites ; tout le
    // reste (fragment, texte inattendu) renvoie null et sera refusé.
    _widgetQueryOperation: function(query) {
      var i, m, n, s, word;
      s = String(query || '');
      n = s.length;
      i = 0;
      while (true) {
        while (i < n && /[\s,]/.test(s.charAt(i))) {
          i++;
        }
        if (s.charAt(i) === '#') {
          while (i < n && s.charAt(i) !== '\n') {
            i++;
          }
          continue;
        }
        break;
      }
      if (i >= n) {
        return null;
      }
      if (s.charAt(i) === '{') {
        return 'query';
      }
      m = s.slice(i).match(/^([_A-Za-z][_0-9A-Za-z]*)/);
      if (!m) {
        return null;
      }
      word = m[1].toLowerCase();
      if (word === 'query' || word === 'mutation' || word === 'subscription') {
        return word;
      }
      return null;
    },
    // nil quand la requête est autorisée, sinon le message de refus (spec §6).
    // En cas de doute (opération illisible), on refuse.
    _widgetQueryRefusal: function(access, query) {
      var op;
      if (access === 'none') {
        return 'Ce widget n’a pas accès aux données (manifest access: none).';
      }
      op = this._widgetQueryOperation(query);
      if (!op) {
        return 'Requête GraphQL illisible : refusée par sécurité (le type d’opération doit être explicite).';
      }
      if (access === 'read' && op !== 'query') {
        return `Seules les lectures sont autorisées (manifest access: read) : opération « ${op} » refusée.`;
      }
      if (access === 'full' && op === 'subscription') {
        return 'Les souscriptions sont refusées depuis un widget.';
      }
      return null;
    },
    // Ligne de la source renommée selon le mappage (+ `id`), pour l'API de
    // données de l'iframe. Sans mappage : la ligne telle quelle.
    _pluginRenameRow: function(node, row) {
      var declared, field, mapping, out;
      if (!row) {
        return row;
      }
      mapping = this._pluginColumnMapping(node);
      if (!mapping) {
        return row;
      }
      out = {};
      if (row.id != null) {
        out.id = row.id;
      }
      for (declared in mapping) {
        field = mapping[declared];
        if (!field) {
          continue;
        }
        if (row[field] != null) {
          out[declared] = row[field];
        }
      }
      return out;
    },
    // Valeurs de l'iframe (noms déclarés) → noms de champs. Sans mappage, les
    // noms sont déjà ceux de la source. `id` n'est jamais écrit.
    _pluginTranslateValues: function(mapping, values) {
      var field, key, out, value;
      out = {};
      if (!(values && typeof values === 'object')) {
        return out;
      }
      for (key in values) {
        value = values[key];
        if (key === 'id') {
          continue;
        }
        field = mapping ? mapping[key] : key;
        if (!field) {
          continue;
        }
        out[field] = value;
      }
      return out;
    },
    _renderPluginWidget: function(container, wNode, runtimeWidgetId = null) {
      var pluginName, pluginParams;
      pluginName = wNode.type;
      pluginParams = wNode.params || {};
      if (!pluginName) {
        container.innerHTML = "<p style='color:#c55;padding:.5rem'>Plugin manquant (<code>type</code>).</p>";
        return;
      }
      this._setMessage(container, `Chargement du plugin ${pluginName}…`, 'color:#888;padding:.5rem');
      // Résolution par portée : définition de l'app de la page, puis globale
      // (spec widgets personnalisés §5). `@pageId` est l'id de la page montée.
      return WidgetPlugins.getByName(pluginName, this.pageId).then((plugin) => {
        var access, manifest, mapping, missing, space, widgetId;
        if (!plugin) {
          this._setMessage(container, `Plugin introuvable : ${pluginName}`, 'color:#c55;padding:.5rem');
          return;
        }
        widgetId = runtimeWidgetId || wNode.id || `plugin_${Math.random().toString(36).slice(2)}`;
        manifest = this._pluginManifest(plugin);
        access = this._pluginAccessOf(plugin);
        mapping = this._pluginColumnMapping(wNode);
        space = this._findSpace(wNode.space);
        missing = this._pluginMissingColumns(manifest, mapping);
        if (missing.length > 0) {
          // Colonne obligatoire non mappée : message dans le widget, aucun
          // chargement (spec §3). Le YAML de page doit déclarer
          // `columns: {<nom déclaré>: <champ>}`.
          this._setMessage(container, `Widget « ${pluginName} » : colonne(s) obligatoire(s) non mappée(s) : ${missing.join(', ')}. ` + `Ajoutez <code>columns: {${missing[0]}: <champ>}</code> au widget.`, 'color:#c55;padding:.5rem');
          return;
        }
        return this._mountPluginIframe(container, widgetId, plugin, pluginParams, {
          access,
          manifest,
          mapping,
          space,
          node: wNode
        });
      }).catch((err) => {
        return this._setMessage(container, `Erreur plugin : ${err.message || err}`, 'color:#c55;padding:.5rem');
      });
    },
    // Lignes de la source du widget, pour `onRecords`. Même résolution que la
    // grille (Data View, champs calculés via le résolveur dynamique, ou records
    // bruts), limitée aux colonnes utiles.
    _loadPluginSourceRows: function(node, space, access) {
      var computed, f, fields, names, query, tname;
      if (access !== 'read' && access !== 'full') {
        return Promise.resolve([]);
      }
      if (!(node != null ? node.space : void 0)) {
        return Promise.resolve([]);
      }
      if (!space) {
        return Promise.reject(new Error(`Source introuvable : ${node.space}`));
      }
      if (space.isView) {
        return DataViews.execute(space.viewId, 2000, 0).then(function(rows) {
          var j, len, r, ref, results, row;
          ref = rows || [];
          results = [];
          for (j = 0, len = ref.length; j < len; j++) {
            r = ref[j];
            row = Object.assign({}, r);
            if (row.id == null) {
              row.id = r.id;
            }
            results.push(row);
          }
          return results;
        });
      }
      fields = space.fields || [];
      if (!fields.length) {
        return Promise.resolve([]);
      }
      computed = (function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if ((f.formula && f.formula !== '') || (f.reprFormula && f.reprFormula !== '')) {
            results.push(f);
          }
        }
        return results;
      })();
      if (computed.length > 0) {
        tname = this._pluginGqlName(space.name);
        names = (function() {
          var j, len, results;
          results = [];
          for (j = 0, len = fields.length; j < len; j++) {
            f = fields[j];
            if (f.name) {
              results.push(this._pluginGqlName(f.name));
            }
          }
          return results;
        }).call(this);
        query = `query($limit: Int) { ${tname}(limit: $limit) { items { _id ${names.join(' ')} } } }`;
        return GQL.query(query, {
          limit: 2000
        }).then(function(data) {
          var item, j, len, ref, ref1, results, row;
          ref1 = (data != null ? (ref = data[tname]) != null ? ref.items : void 0 : void 0) || [];
          results = [];
          for (j = 0, len = ref1.length; j < len; j++) {
            item = ref1[j];
            row = Object.assign({}, item);
            row.id = item._id;
            delete row._id;
            results.push(row);
          }
          return results;
        });
      }
      query = `query PluginRecords($spaceId: ID!, $limit: Int) {
  records(spaceId: $spaceId, limit: $limit) { items { id data } }
}`;
      return GQL.query(query, {
        spaceId: space.id,
        limit: 2000
      }).then(function(data) {
        var j, len, parsed, r, ref, ref1, results, row;
        ref1 = (data != null ? (ref = data.records) != null ? ref.items : void 0 : void 0) || [];
        results = [];
        for (j = 0, len = ref1.length; j < len; j++) {
          r = ref1[j];
          parsed = typeof r.data === 'string' ? JSON.parse(r.data) : r.data || {};
          row = Object.assign({}, parsed);
          row.id = r.id;
          results.push(row);
        }
        return results;
      });
    },
    _pluginGqlName: function(name) {
      var s;
      s = String(name || '').replace(/[^\w]/g, '_');
      if (/^\d/.test(s)) {
        return '_' + s;
      } else {
        return s;
      }
    },
    // Compilation d'abord (asynchrone : les compilateurs CoffeeScript/pug sont
    // chargés à la demande, spec §7), puis construction de l'iframe. Un échec de
    // chargement ou de compilation s'affiche dans le widget, jamais avalé.
    _mountPluginIframe: function(container, widgetId, plugin, pluginParams, ctx = {}) {
      return this._compilePlugin(plugin, pluginParams).then((compiled) => {
        return this._mountCompiledPluginIframe(container, widgetId, plugin, pluginParams, compiled, ctx);
      }).catch((err) => {
        return this._setMessage(container, `Erreur plugin : ${err.message || err}`, 'color:#c55;padding:.5rem');
      });
    },
    _mountCompiledPluginIframe: function(container, widgetId, plugin, pluginParams, compiled, ctx = {}) {
      var fn, iframe, j, len, listeners, onMessage, postToFrame, ref, reload, reqSeq, requestMap, sendRecords, srcDoc, state;
      iframe = document.createElement('iframe');
      iframe.setAttribute('sandbox', 'allow-scripts');
      iframe.style.cssText = 'width:100%;height:100%;border:0;background:#fff;';
      container.innerHTML = '';
      container.appendChild(iframe);
      requestMap = {};
      reqSeq = 0;
      listeners = [];
      ref = this._pluginSelectionListenersByWidgetId[widgetId] || [];
      for (j = 0, len = ref.length; j < len; j++) {
        fn = ref[j];
        listeners.push(fn);
      }
      state = {
        iframe,
        listeners,
        requestMap,
        reqSeq,
        access: ctx.access || 'full',
        mapping: ctx.mapping || null,
        space: ctx.space || null,
        node: ctx.node || null,
        ready: false,
        rows: [],
        rawRows: []
      };
      this._pluginStateByWidgetId[widgetId] = state;
      postToFrame = (msg) => {
        var ref1;
        return (ref1 = iframe.contentWindow) != null ? ref1.postMessage(Object.assign({widgetId}, msg), '*') : void 0;
      };
      sendRecords = () => {
        if (!state.ready) {
          return;
        }
        return postToFrame({
          type: 'records',
          rows: state.rows
        });
      };
      reload = () => {
        return this._loadPluginSourceRows(ctx.node, ctx.space, state.access).then((rawRows) => {
          var r;
          if (this._pluginStateByWidgetId[widgetId] !== state) {
            return;
          }
          state.rawRows = rawRows || [];
          state.rows = (function() {
            var k, len1, ref1, results;
            ref1 = state.rawRows;
            results = [];
            for (k = 0, len1 = ref1.length; k < len1; k++) {
              r = ref1[k];
              results.push(this._pluginRenameRow(ctx.node, r));
            }
            return results;
          }).call(this);
          return sendRecords();
        }).catch((err) => {
          return postToFrame({
            type: 'records',
            rows: [],
            error: (err != null ? err.message : void 0) || String(err)
          });
        });
      };
      onMessage = (ev) => {
        var k, len1, msg, raw, ref1, refusal, row, selection;
        if (ev.source !== iframe.contentWindow) {
          return;
        }
        msg = ev.data || {};
        if (msg.widgetId !== widgetId) {
          return;
        }
        switch (msg.type) {
          case 'gql_request':
            refusal = this._widgetQueryRefusal(state.access, msg.query);
            if (refusal) {
              postToFrame({
                type: 'gql_error',
                requestId: msg.requestId,
                error: refusal
              });
              return;
            }
            return this._relayWidgetQuery(msg.query || '', msg.variables || {}).then((data) => {
              return postToFrame({
                type: 'gql_response',
                requestId: msg.requestId,
                data
              });
            }).catch((err) => {
              return postToFrame({
                type: 'gql_error',
                requestId: msg.requestId,
                error: err.message || String(err)
              });
            });
          case 'emitSelection':
            return this._emitPluginSelection(widgetId, msg.selection || {});
          case 'plugin_ready':
            state.ready = true;
            return reload();
          case 'setCursor':
            raw = null;
            ref1 = state.rawRows;
            for (k = 0, len1 = ref1.length; k < len1; k++) {
              row = ref1[k];
              if ((row.id != null) && String(row.id) === String(msg.id)) {
                raw = row;
                break;
              }
            }
            selection = raw ? {
              rows: [raw]
            } : {
              rows: [
                {
                  id: msg.id
                }
              ]
            };
            return this._emitPluginSelection(widgetId, selection);
          case 'updateRecord':
          case 'insertRecord':
          case 'deleteRecord':
            return this._handlePluginWrite(widgetId, state, msg);
          default:
            return null;
        }
      };
      window.addEventListener('message', onMessage);
      srcDoc = this._buildPluginIframeDoc(widgetId, pluginParams, compiled, plugin, state);
      iframe.srcdoc = srcDoc;
      state.onMessage = onMessage;
      return state.reload = reload;
    },
    // Écritures demandées par l'iframe : réservées à `access: full`, valeurs
    // traduites noms déclarés → noms de champs, mutations relayées via
    // GQL.queryWidget (le serveur garde sa liste blanche), puis rechargement.
    _handlePluginWrite: function(widgetId, state, msg) {
      var mapping, postToFrame, promise, ref, refuse, spaceId, values;
      postToFrame = (payload) => {
        var ref;
        return (ref = state.iframe.contentWindow) != null ? ref.postMessage(Object.assign({widgetId}, payload), '*') : void 0;
      };
      refuse = (error) => {
        return postToFrame({
          type: 'write_error',
          requestId: msg.requestId,
          error
        });
      };
      if (state.access !== 'full') {
        return refuse('Écriture refusée : ce widget est en lecture seule (manifest access ≠ full).');
      }
      if (!((ref = state.space) != null ? ref.id : void 0)) {
        return refuse('Écriture impossible : aucune source de données pour ce widget.');
      }
      spaceId = state.space.id;
      mapping = state.mapping;
      promise = null;
      switch (msg.type) {
        case 'updateRecord':
          values = this._pluginTranslateValues(mapping, msg.values);
          promise = GQL.queryWidget(UPDATE_RECORD_MUTATION, {
            spaceId,
            id: msg.id,
            data: values
          });
          break;
        case 'insertRecord':
          values = this._pluginTranslateValues(mapping, msg.values);
          promise = GQL.queryWidget(INSERT_RECORD_MUTATION, {
            spaceId,
            data: values
          });
          break;
        case 'deleteRecord':
          promise = GQL.queryWidget(DELETE_RECORD_MUTATION, {
            spaceId,
            id: msg.id
          });
      }
      if (!promise) {
        return refuse('Opération d’écriture inconnue.');
      }
      return promise.then((data) => {
        postToFrame({
          type: 'write_response',
          requestId: msg.requestId,
          data
        });
        return typeof state.reload === "function" ? state.reload() : void 0;
      }).catch((err) => {
        return refuse(err.message || String(err));
      });
    },
    // Compile a widget definition. Asynchronous: the compilers (CoffeeScript,
    // pug) are loaded on demand (§7), only for the languages it uses. A widget
    // written in javascript + html triggers no load at all.
    _compilePlugin: function(plugin, pluginParams = {}) {
      var pluginName, runtimes, scriptLanguage, templateLanguage;
      scriptLanguage = (plugin.scriptLanguage || 'coffeescript').toLowerCase();
      templateLanguage = (plugin.templateLanguage || 'pug').toLowerCase();
      pluginName = plugin.name || plugin.id || '(sans nom)';
      runtimes = window.PluginRuntimes;
      if (!(runtimes && typeof runtimes.ensure === 'function')) {
        return Promise.reject(new Error(`Plugin ${pluginName} — chargeur de compilateurs absent (views/plugin_runtimes.js non chargé)`));
      }
      return runtimes.ensure([scriptLanguage, templateLanguage]).then(() => {
        return this._compilePluginCode(plugin, pluginParams, scriptLanguage, templateLanguage);
      });
    },
    _compilePluginCode: function(plugin, pluginParams, scriptLanguage, templateLanguage) {
      var csCompile, err, fn, htmlTemplate, jsScript, makeCompileError, pluginName, pugCompile, ref, ref1, scriptCode, templateCode;
      scriptCode = plugin.scriptCode || '';
      templateCode = plugin.templateCode || '';
      pluginName = plugin.name || plugin.id || '(sans nom)';
      makeCompileError = function(source, language, err) {
        var col, line, loc, msg, ref, ref1;
        msg = (err != null ? err.message : void 0) || String(err);
        line = err != null ? (ref = err.location) != null ? ref.first_line : void 0 : void 0;
        col = err != null ? (ref1 = err.location) != null ? ref1.first_column : void 0 : void 0;
        if (line != null) {
          line += 1;
          col = (col || 0) + 1;
        } else {
          line = err != null ? err.line : void 0;
          col = err != null ? err.column : void 0;
        }
        loc = line != null ? ` (ligne ${line}${col != null ? `, colonne ${col}` : ''})` : '';
        return new Error(`Plugin ${pluginName} — ${source} ${language} invalide${loc} : ${msg}`);
      };
      jsScript = scriptCode;
      if (scriptLanguage === 'coffeescript') {
        csCompile = (ref = window.PluginRuntimes) != null ? typeof ref.compiler === "function" ? ref.compiler('coffeescript') : void 0 : void 0;
        if (!csCompile) {
          throw new Error(`Plugin ${pluginName} — runtime CoffeeScript indisponible`);
        }
        try {
          jsScript = csCompile(scriptCode, {
            bare: true
          });
        } catch (error1) {
          err = error1;
          throw makeCompileError('script', 'CoffeeScript', err);
        }
      }
      htmlTemplate = templateCode;
      if (templateLanguage === 'pug') {
        pugCompile = (ref1 = window.PluginRuntimes) != null ? typeof ref1.compiler === "function" ? ref1.compiler('pug') : void 0 : void 0;
        if (!pugCompile) {
          throw new Error(`Plugin ${pluginName} — runtime Pug indisponible`);
        }
        try {
          fn = pugCompile(templateCode);
          htmlTemplate = fn({
            params: pluginParams || {}
          });
        } catch (error1) {
          err = error1;
          throw makeCompileError('template', 'Pug', err);
        }
      }
      return {jsScript, htmlTemplate};
    },
    _buildPluginIframeDoc: function(widgetId, params, compiled, plugin, ctx = {}) {
      var access, canRead, canWrite, dataApiJs, gqlExposed, js, paramsJson, pluginName, tpl, writeApiJs;
      paramsJson = JSON.stringify(params || {});
      tpl = JSON.stringify(compiled.htmlTemplate || '');
      js = compiled.jsScript || '';
      pluginName = JSON.stringify((plugin != null ? plugin.name : void 0) || (plugin != null ? plugin.id : void 0) || '(sans nom)');
      access = (ctx != null ? ctx.access : void 0) || 'full';
      canRead = access === 'read' || access === 'full';
      canWrite = access === 'full';
      gqlExposed = access === 'read' || access === 'full';
      dataApiJs = canRead ? `var latestRows = [];
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
}` : '';
      writeApiJs = canWrite ? `var pendingWrites = {};
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
function deleteRecord(id) { return writeRequest('deleteRecord', { id: id }); }` : '';
      return `<!doctype html>
<html>
<head><meta charset='utf-8'><style>body{margin:0;font-family:sans-serif}.plugin-root{padding:.5rem}</style></head>
<body>
  <div id='root'></div>
  <script>
    (function() {
      var widgetId = ${JSON.stringify(widgetId)};
      var pluginName = ${pluginName};
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
${dataApiJs}
${writeApiJs}
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

      var params = ${paramsJson};
      render(${tpl});
      var module = { exports: null };
      var api = {
        emitSelection: emitSelection,
        onInputSelection: onInputSelection,
        render: render,
        params: params,
        setCursor: setCursor
      };
      ${gqlExposed ? 'api.gql = gql;' : ''}
      ${canRead ? 'api.onRecords = onRecords; api.onRecord = onRecord;' : ''}
      ${canWrite ? 'api.updateRecord = updateRecord; api.insertRecord = insertRecord; api.deleteRecord = deleteRecord;' : ''}
      try {
${js}
        if (typeof module.exports === 'function') module.exports(api);
      } catch (e) {
        renderRuntimeError(e);
      }
      post({ type: 'plugin_ready' });
    })();
  </script>
</body>
</html>`;
    },
    _sendPluginMessage: function(widgetId, msg) {
      var payload, ref, st;
      st = this._pluginStateByWidgetId[widgetId];
      if (!(st != null ? (ref = st.iframe) != null ? ref.contentWindow : void 0 : void 0)) {
        return;
      }
      payload = Object.assign({widgetId}, msg);
      return st.iframe.contentWindow.postMessage(payload, '*');
    },
    // ── Détacher une instance (spec widgets personnalisés §4) ────────────────────
    // Le bouton n'apparaît qu'en édition de page (une page montée avec un id), pour
    // un admin, et sur un widget personnalisé (pas un widget fourni par le
    // programme). Le type seul ne prouve pas qu'une définition existe ; le serveur
    // répond alors par une erreur claire.
    _canDetachPluginWidget: function(wNode) {
      var ref, ref1;
      if (!(this.pageId && !this.presentationMode)) {
        return false;
      }
      if (!(wNode != null ? wNode.type : void 0)) {
        return false;
      }
      if (ref = wNode.type, indexOf.call(BUILTIN_WIDGET_TYPES, ref) >= 0) {
        return false;
      }
      if (!((ref1 = window.Auth) != null ? typeof ref1.isAdmin === "function" ? ref1.isAdmin() : void 0 : void 0)) {
        return false;
      }
      return true;
    },
    _addPluginDetachButton: function(titleBar, wNode) {
      var btn;
      if (!(titleBar && this._canDetachPluginWidget(wNode))) {
        return null;
      }
      btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'cv-widget-detach-btn no-drag';
      btn.textContent = 'Détacher';
      btn.title = 'Détacher — copier ce widget personnalisé pour cette page';
      btn.addEventListener('click', (ev) => {
        if (ev != null) {
          if (typeof ev.preventDefault === "function") {
            ev.preventDefault();
          }
        }
        if (ev != null) {
          if (typeof ev.stopPropagation === "function") {
            ev.stopPropagation();
          }
        }
        return this._detachPluginWidget(wNode);
      });
      titleBar.appendChild(btn);
      return btn;
    },
    // Demande le nom de la copie (pré-rempli « <type> (<titre de page>) »),
    // envoie detachWidgetPlugin puis recharge la page. Le nom réellement retenu
    // (suffixé si pris) revient dans `detachWidgetPlugin.name`.
    _detachPluginWidget: async function(wNode) {
      var defaultName, name, pageId, pageTitle, ref, ref1, widgetId;
      pageId = this.pageId;
      widgetId = wNode != null ? wNode.id : void 0;
      if (!(pageId && widgetId)) {
        return;
      }
      pageTitle = ((ref = window.App) != null ? (ref1 = ref._currentCustomView) != null ? ref1.name : void 0 : void 0) || '';
      defaultName = pageTitle ? `${wNode.type} (${pageTitle})` : wNode.type;
      name = (await tdbPrompt('Nom du widget détaché :', defaultName));
      if (name == null) {
        return;
      }
      name = String(name).trim();
      if (name === '') {
        return;
      }
      return GQL.mutate(DETACH_WIDGET_PLUGIN_MUTATION, {
        pageId,
        widgetId,
        newName: name
      }).then((data) => {
        var created, ref2;
        created = data != null ? data.detachWidgetPlugin : void 0;
        if (!created) {
          return;
        }
        if ((ref2 = window.CustomView) != null) {
          if (typeof ref2.showNotification === "function") {
            ref2.showNotification(`Widget détaché sous « ${created.name} »`, 'success');
          }
        }
        return this._reloadPageAfterDetach(created);
      }).catch((err) => {
        var ref2;
        return tdbAlert(((ref2 = window.App) != null ? typeof ref2._err === "function" ? ref2._err(err) : void 0 : void 0) || (err != null ? err.message : void 0) || String(err), 'error');
      });
    },
    // Recharge le YAML de la page depuis la base (le serveur vient de le réécrire),
    // puis ouvre l'éditeur de définitions sur la copie : c'est elle que l'on vient
    // de créer et que l'on veut personnaliser.
    _reloadPageAfterDetach: function(created) {
      var app;
      app = window.App;
      if (!(app && typeof GQL !== 'undefined')) {
        return;
      }
      return GQL.query(DETACHED_PAGE_QUERY, {
        id: this.pageId
      }).then((data) => {
        var base, cv, ref, ref1, ref2;
        cv = data != null ? data.customView : void 0;
        if (!cv) {
          return;
        }
        app._currentCustomView = cv;
        if ((ref = app._cmYaml) != null) {
          ref.setValue(cv.yaml);
        }
        if ((ref1 = window.AppViewHelpers) != null) {
          if (typeof ref1.renderCustomViewPreview === "function") {
            ref1.renderCustomViewPreview(app, cv.yaml);
          }
        }
        if ((ref2 = window.AppViewHelpers) != null ? ref2.openWidgetPluginModal : void 0) {
          window.AppViewHelpers.openWidgetPluginModal(app);
          return typeof (base = window.AppViewHelpers)._loadWidgetPlugins === "function" ? base._loadWidgetPlugins(app, created.id) : void 0;
        }
      }).catch(function(err) {
        var ref;
        return tdbAlert(((ref = window.App) != null ? typeof ref._err === "function" ? ref._err(err) : void 0 : void 0) || (err != null ? err.message : void 0) || String(err), 'error');
      });
    }
  });

}).call(this);
