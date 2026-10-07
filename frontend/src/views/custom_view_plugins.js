(function() {
  // custom_view_plugins.coffee — plugin/iframe methods extracted from custom_view.coffee
  // Extends the CustomView class (defined in custom_view.js) via its prototype.
  // Loaded after views/custom_view.js.
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
      var e, fn, i, len, ref, results, st;
      st = this._pluginStateByWidgetId[widgetId];
      if (!st) {
        return;
      }
      ref = st.listeners || [];
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        fn = ref[i];
        try {
          results.push(fn(selection));
        } catch (error) {
          e = error;
          results.push(console.warn('plugin selection listener error', e));
        }
      }
      return results;
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
      return WidgetPlugins.getByName(pluginName).then((plugin) => {
        var widgetId;
        if (!plugin) {
          this._setMessage(container, `Plugin introuvable : ${pluginName}`, 'color:#c55;padding:.5rem');
          return;
        }
        widgetId = runtimeWidgetId || wNode.id || `plugin_${Math.random().toString(36).slice(2)}`;
        return this._mountPluginIframe(container, widgetId, plugin, pluginParams);
      }).catch((err) => {
        return this._setMessage(container, `Erreur plugin : ${err.message || err}`, 'color:#c55;padding:.5rem');
      });
    },
    _mountPluginIframe: function(container, widgetId, plugin, pluginParams) {
      var compiled, fn, i, iframe, len, listeners, onMessage, ref, reqSeq, requestMap, srcDoc;
      compiled = this._compilePlugin(plugin, pluginParams);
      iframe = document.createElement('iframe');
      iframe.setAttribute('sandbox', 'allow-scripts');
      iframe.style.cssText = 'width:100%;height:100%;border:0;background:#fff;';
      container.innerHTML = '';
      container.appendChild(iframe);
      requestMap = {};
      reqSeq = 0;
      listeners = [];
      ref = this._pluginSelectionListenersByWidgetId[widgetId] || [];
      for (i = 0, len = ref.length; i < len; i++) {
        fn = ref[i];
        listeners.push(fn);
      }
      this._pluginStateByWidgetId[widgetId] = {iframe, listeners, requestMap, reqSeq};
      onMessage = (ev) => {
        var msg, q, reqId, vars;
        if (ev.source !== iframe.contentWindow) {
          return;
        }
        msg = ev.data || {};
        if (msg.widgetId !== widgetId) {
          return;
        }
        if (msg.type === 'gql_request') {
          q = msg.query || '';
          vars = msg.variables || {};
          reqId = msg.requestId;
          return GQL.query(q, vars).then((data) => {
            var ref1;
            return (ref1 = iframe.contentWindow) != null ? ref1.postMessage({
              type: 'gql_response',
              widgetId,
              requestId: reqId,
              data
            }, '*') : void 0;
          }).catch((err) => {
            var ref1;
            return (ref1 = iframe.contentWindow) != null ? ref1.postMessage({
              type: 'gql_error',
              widgetId,
              requestId: reqId,
              error: err.message || String(err)
            }, '*') : void 0;
          });
        } else if (msg.type === 'emitSelection') {
          return this._emitPluginSelection(widgetId, msg.selection || {});
        }
      };
      window.addEventListener('message', onMessage);
      srcDoc = this._buildPluginIframeDoc(widgetId, pluginParams, compiled, plugin);
      iframe.srcdoc = srcDoc;
      return this._pluginStateByWidgetId[widgetId].onMessage = onMessage;
    },
    _compilePlugin: function(plugin, pluginParams = {}) {
      var csCompile, csRuntime, err, fn, htmlTemplate, jsScript, makeCompileError, pluginName, pugCompile, pugRuntime, ref, ref1, ref2, scriptCode, scriptLanguage, templateCode, templateLanguage;
      scriptLanguage = (plugin.scriptLanguage || 'coffeescript').toLowerCase();
      templateLanguage = (plugin.templateLanguage || 'pug').toLowerCase();
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
        csRuntime = window.CoffeeScript;
        csCompile = (csRuntime != null ? csRuntime.compile : void 0) || (csRuntime != null ? (ref = csRuntime.default) != null ? ref.compile : void 0 : void 0) || (csRuntime != null ? (ref1 = csRuntime.CoffeeScript) != null ? ref1.compile : void 0 : void 0);
        if (!csCompile) {
          throw new Error(`Plugin ${pluginName} — runtime CoffeeScript indisponible`);
        }
        try {
          jsScript = csCompile(scriptCode, {
            bare: true
          });
        } catch (error) {
          err = error;
          throw makeCompileError('script', 'CoffeeScript', err);
        }
      }
      htmlTemplate = templateCode;
      if (templateLanguage === 'pug') {
        pugRuntime = window.pug;
        pugCompile = (pugRuntime != null ? pugRuntime.compile : void 0) || (pugRuntime != null ? (ref2 = pugRuntime.default) != null ? ref2.compile : void 0 : void 0);
        if (!pugCompile) {
          throw new Error(`Plugin ${pluginName} — runtime Pug indisponible`);
        }
        try {
          fn = pugCompile(templateCode);
          htmlTemplate = fn({
            params: pluginParams || {}
          });
        } catch (error) {
          err = error;
          throw makeCompileError('template', 'Pug', err);
        }
      }
      return {jsScript, htmlTemplate};
    },
    _buildPluginIframeDoc: function(widgetId, params, compiled, plugin) {
      var js, paramsJson, pluginName, tpl;
      paramsJson = JSON.stringify(params || {});
      tpl = JSON.stringify(compiled.htmlTemplate || '');
      js = compiled.jsScript || '';
      pluginName = JSON.stringify((plugin != null ? plugin.name : void 0) || (plugin != null ? plugin.id : void 0) || '(sans nom)');
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

      var params = ${paramsJson};
      render(${tpl});
      var module = { exports: null };
      try {
${js}
        if (typeof module.exports === 'function') {
          module.exports({ gql: gql, emitSelection: emitSelection, onInputSelection: onInputSelection, render: render, params: params });
        }
      } catch (e) {
        renderRuntimeError(e);
      }
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
    }
  });

}).call(this);
