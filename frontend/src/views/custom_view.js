(function() {
  // custom_view.coffee
  // YAML-driven layout renderer.

  // YAML format example:

  //   layout:
  //     direction: vertical
  //     children:
  //       - factor: 2                         # takes 2/3 of available space (optional, default: 1)
  //         direction: horizontal
  //         children:
  //           - widget:
  //               id: choir-list               # unique widget identifier (required when referenced)
  //               title: Chorales
  //               space: chorale
  //               columns: [annee, pupitre]   # columns to display (optional, default: all)
  //           - widget:
  //               title: Choristes
  //               space: choristes
  //               depends_on:
  //                 widget: choir-list        # source widget id
  //                 field: chorale_id         # FK field in this space
  //                 from_field: id            # referenced field in source widget space (default: id)
  //       - factor: 1
  //         widget:
  //           title: Personnes
  //           space: personnes
  var CustomView,
    indexOf = [].indexOf,
    hasProp = {}.hasOwnProperty;

  window.CustomView = CustomView = class CustomView {
    constructor(container1, yamlText, allSpaces) {
      this.container = container1;
      this.yamlText = yamlText;
      this.allSpaces = allSpaces;
      this._widgets = []; // list of { dataView, node, el }
      this._widgetsById = {}; // id -> entry
      this._pluginStateByWidgetId = {};
      this._pluginSelectionListenersByWidgetId = {};
    }

    mount() {
      var e, el, parsed, root;
      this.container.innerHTML = '';
      this._widgets = [];
      this._widgetsById = {};
      this._mountPromises = [];
      try {
        parsed = jsyaml.load(this.yamlText);
      } catch (error) {
        e = error;
        this.container.innerHTML = `<p style='color:red;padding:1rem'>YAML invalide : ${e.message}</p>`;
        return;
      }
      root = parsed != null ? parsed.layout : void 0;
      if (!root) {
        this.container.innerHTML = "<p style='color:#888;padding:1rem'>Pas de section <code>layout</code> dans le YAML.</p>";
        return;
      }
      el = this._renderZoneOrWidget(root);
      this.container.style.cssText = 'display:flex;flex-direction:column;height:100%;';
      this.container.appendChild(el);
      // Wire depends_on after all DataView grids are ready (mount is async)
      return Promise.all(this._mountPromises).then(() => {
        this._wireDepends();
        // Refresh grid layouts now that elements are in the live DOM
        return setTimeout(() => {
          var entry, i, len, ref, ref1, ref2, results;
          ref = this._widgets;
          results = [];
          for (i = 0, len = ref.length; i < len; i++) {
            entry = ref[i];
            results.push((ref1 = entry.dataView) != null ? (ref2 = ref1._grid) != null ? ref2.refreshLayout() : void 0 : void 0);
          }
          return results;
        }, 0);
      });
    }

    // Renders either a zone (direction+children) or a widget node.
    // Applies `factor` (flex proportion) when specified (default: 1).
    // Supports both inline zone keys (direction/children) and wrapped "- layout:" syntax.
    _renderZoneOrWidget(node) {
      var child, el, i, len, ref, zone;
      zone = node.layout ? node.layout : node;
      if (zone.widget) {
        el = this._renderWidget(zone.widget);
      } else {
        el = document.createElement('div');
        el.className = `cv-zone ${zone.direction || 'vertical'}`;
        ref = zone.children || [];
        for (i = 0, len = ref.length; i < len; i++) {
          child = ref[i];
          el.appendChild(this._renderZoneOrWidget(child));
        }
      }
      el.style.flex = node.factor != null ? String(node.factor) : '1';
      return el;
    }

    _renderWidget(wNode) {
      var body, col, delBtn, dv, entry, f, fieldMap, filterFormula, filterInput, filterLabel, filterTimer, filterWrap, i, lang, len, ref, runtimeWidgetId, sp, titleBar, titleText, wrapper;
      wrapper = document.createElement('div');
      wrapper.className = 'cv-widget';
      // Title bar
      titleBar = document.createElement('div');
      titleBar.className = 'cv-widget-title';
      titleText = document.createElement('span');
      titleText.textContent = wNode.title || wNode.space || '';
      titleBar.appendChild(titleText);
      wrapper.appendChild(titleBar);
      body = document.createElement('div');
      body.className = 'cv-widget-body';
      wrapper.appendChild(body);
      // Aggregate widget (read-only summary table)
      if (wNode.type === 'aggregate') {
        this._renderAggregate(body, wNode);
        entry = {
          dataView: null,
          node: wNode,
          el: wrapper
        };
        this._widgets.push(entry);
        if (wNode.id) {
          this._widgetsById[wNode.id] = entry;
        }
        return wrapper;
      }
      // Custom plugin widget (type = plugin name)
      if (wNode.type) {
        runtimeWidgetId = wNode.id || `plugin_${Math.random().toString(36).slice(2)}`;
        this._renderPluginWidget(body, wNode, runtimeWidgetId);
        entry = {
          dataView: null,
          node: wNode,
          el: wrapper,
          plugin: true,
          runtimeWidgetId
        };
        this._widgets.push(entry);
        if (wNode.id) {
          this._widgetsById[wNode.id] = entry;
        }
        return wrapper;
      }
      // Regular data widget
      sp = this._findSpace(wNode.space);
      delBtn = document.createElement('button');
      delBtn.className = 'cv-widget-delete-btn';
      delBtn.title = 'Supprimer les enregistrements sélectionnés';
      delBtn.textContent = '🗑';
      if (!sp) {
        body.innerHTML = `<p style='color:#aaa;padding:.5rem'>Espace « ${wNode.space} » introuvable.</p>`;
        entry = {
          dataView: null,
          node: wNode,
          el: wrapper
        };
        this._widgets.push(entry);
        if (wNode.id) {
          this._widgetsById[wNode.id] = entry;
        }
        return wrapper;
      }
      // Apply column filter/order if specified
      if (wNode.columns && wNode.columns.length > 0) {
        fieldMap = {};
        ref = sp.fields || [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          fieldMap[f.name] = f;
        }
        sp = Object.assign({}, sp);
        sp.fields = (function() {
          var j, len1, ref1, results;
          ref1 = wNode.columns;
          results = [];
          for (j = 0, len1 = ref1.length; j < len1; j++) {
            col = ref1[j];
            if (fieldMap[col]) {
              results.push(fieldMap[col]);
            }
          }
          return results;
        })();
      }
      dv = new DataView(body, sp);
      filterFormula = '';
      // Apply formula filter from YAML widget config
      if (wNode.filter) {
        filterFormula = typeof wNode.filter === 'string' ? wNode.filter : wNode.filter.formula || '';
        lang = typeof wNode.filter === 'object' ? wNode.filter.language || 'moonscript' : 'moonscript';
        if (filterFormula) {
          dv._formulaFilter = filterFormula;
        }
      }
      filterWrap = document.createElement('div');
      filterWrap.className = 'cv-widget-filter toolbar-filter';
      filterLabel = document.createElement('span');
      filterLabel.className = 'toolbar-filter-label';
      filterLabel.textContent = 'λ';
      filterInput = document.createElement('input');
      filterInput.type = 'text';
      filterInput.className = 'toolbar-filter-input';
      filterInput.placeholder = 'Filtre (MoonScript)';
      filterInput.value = filterFormula;
      filterInput.classList.toggle('active', filterFormula !== '');
      filterWrap.appendChild(filterLabel);
      filterWrap.appendChild(filterInput);
      titleBar.appendChild(filterWrap);
      titleBar.appendChild(delBtn);
      filterTimer = null;
      filterInput.addEventListener('input', (ev) => {
        var val;
        val = ev.target.value.trim();
        ev.target.classList.toggle('active', val !== '');
        clearTimeout(filterTimer);
        return filterTimer = setTimeout((() => {
          return dv.setFormulaFilter(val);
        }), 400);
      });
      dv._formulaInputEl = filterInput;
      this._mountPromises.push(dv.mount());
      delBtn.addEventListener('click', () => {
        return dv.deleteSelected();
      });
      entry = {
        dataView: dv,
        node: wNode,
        el: wrapper
      };
      this._widgets.push(entry);
      if (wNode.id) {
        this._widgetsById[wNode.id] = entry;
      }
      return wrapper;
    }

    // Render an aggregate (GROUP BY) widget as a read-only table.
    _renderAggregate(container, wNode) {
      var agg, aggInput, aggregate, groupBy, makeAlias, spaceName;
      groupBy = wNode.groupBy || [];
      aggregate = wNode.aggregate || [];
      spaceName = wNode.space;
      if (!spaceName) {
        container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Paramètre <code>space</code> manquant.</p>";
        return;
      }
      // Show loading state
      container.innerHTML = "<p style='color:#888;padding:.5rem'>Chargement…</p>";
      // Normalize aggregate: ensure each entry has fn and as
      makeAlias = function(agg) {
        if (agg.as) {
          return agg.as;
        }
        if (!agg.field) {
          return 'count';
        } else {
          return `${agg.fn}_${agg.field}`;
        }
      };
      aggInput = (function() {
        var i, len, results;
        results = [];
        for (i = 0, len = aggregate.length; i < len; i++) {
          agg = aggregate[i];
          results.push({
            fn: agg.fn,
            field: agg.field || null,
            as: makeAlias(agg)
          });
        }
        return results;
      })();
      return Spaces.aggregateSpace(spaceName, groupBy, aggInput).then((rows) => {
        var c, col, computed, computedFns, errDiv, formulaErrors, i, j, k, keys, l, len, len1, len2, len3, len4, len5, len6, len7, m, n, o, p, r, ref, ref1, row, tbl, tbody, td, th, thead, tr, v;
        container.innerHTML = '';
        if (!(rows && rows.length > 0)) {
          container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Aucun résultat.</p>";
          return;
        }
        // Evaluate computed columns (client-side JS expressions on each row)
        computed = wNode.computed || [];
        computedFns = [];
        formulaErrors = [];
        for (i = 0, len = computed.length; i < len; i++) {
          col = computed[i];
          (function(col) {
            var e, fn;
            try {
              fn = new Function('row', `try { return (${col.expr}); } catch(e) { return '⚠ ' + e.message; }`);
              return computedFns.push({
                as: col.as,
                fn
              });
            } catch (error) {
              e = error;
              formulaErrors.push(`${col.as}: ${e.message}`);
              return computedFns.push({
                as: col.as,
                fn: function() {
                  return "⚠ formule invalide";
                }
              });
            }
          })(col);
        }
        if (formulaErrors.length > 0) {
          errDiv = document.createElement('p');
          errDiv.style.cssText = 'color:#c55;padding:.3rem .5rem;font-size:.85rem;margin:0';
          errDiv.textContent = `Formule invalide : ${formulaErrors.join('; ')}`;
          container.appendChild(errDiv);
        }
        // Augment rows with computed values
        if (computedFns.length > 0) {
          for (j = 0, len1 = rows.length; j < len1; j++) {
            row = rows[j];
            for (l = 0, len2 = computedFns.length; l < len2; l++) {
              c = computedFns[l];
              row[c.as] = c.fn(row);
            }
          }
        }
        // Build column list from first row keys (preserve groupBy order first)
        keys = groupBy.slice();
        for (m = 0, len3 = aggInput.length; m < len3; m++) {
          agg = aggInput[m];
          if (ref = agg.as, indexOf.call(keys, ref) < 0) {
            keys.push(agg.as);
          }
        }
        for (n = 0, len4 = computed.length; n < len4; n++) {
          col = computed[n];
          if (ref1 = col.as, indexOf.call(keys, ref1) < 0) {
            keys.push(col.as);
          }
        }
        tbl = document.createElement('table');
        tbl.className = 'agg-table';
        thead = document.createElement('thead');
        tr = document.createElement('tr');
        for (o = 0, len5 = keys.length; o < len5; o++) {
          k = keys[o];
          th = document.createElement('th');
          th.textContent = k;
          tr.appendChild(th);
        }
        thead.appendChild(tr);
        tbl.appendChild(thead);
        tbody = document.createElement('tbody');
        for (p = 0, len6 = rows.length; p < len6; p++) {
          row = rows[p];
          tr = document.createElement('tr');
          for (r = 0, len7 = keys.length; r < len7; r++) {
            k = keys[r];
            td = document.createElement('td');
            v = row[k];
            td.textContent = v != null ? String(v) : '';
            tr.appendChild(td);
          }
          tbody.appendChild(tr);
        }
        tbl.appendChild(tbody);
        return container.appendChild(tbl);
      }).catch((err) => {
        return container.innerHTML = `<p style='color:#c55;padding:.5rem'>Erreur : ${err.message || err}</p>`;
      });
    }

    _wireDepends() {
      var dep, entry, i, len, ref, results, src;
      ref = this._widgets;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        entry = ref[i];
        dep = entry.node.depends_on;
        if (!dep) {
          continue;
        }
        src = this._widgetsById[dep.widget];
        if (!src) {
          console.warn(`depends_on: widget id '${dep.widget}' introuvable`);
          continue;
        }
        // When a row selection is emitted by source widget, propagate to target.
        // from_field defaults to 'id' when omitted.
        results.push(((entry, dep, src) => {
          var ref1;
          if (((ref1 = src.dataView) != null ? ref1._grid : void 0) != null) {
            return src.dataView._grid.on('click', (ev) => {
              var ref2, rowData, rowKey;
              if ((ev != null ? (ref2 = ev.nativeEvent) != null ? ref2.detail : void 0 : void 0) && ev.nativeEvent.detail > 1) {
                return;
              }
              rowKey = ev.rowKey;
              if (rowKey == null) {
                return;
              }
              rowData = src.dataView._grid.getRow(rowKey);
              if (!(rowData && !rowData.__isNew)) {
                return;
              }
              return this._applyDependencySelection(entry, dep, rowData);
            });
          } else if (src.plugin && dep.widget) {
            return this._setPluginSelectionListener(dep.widget, (selection) => {
              var rows;
              rows = (selection != null ? selection.rows : void 0) || [];
              if (!(rows.length > 0)) {
                return;
              }
              return this._applyDependencySelection(entry, dep, rows[0]);
            });
          }
        })(entry, dep, src));
      }
      return results;
    }

    _applyDependencySelection(entry, dep, rowData) {
      var defaults, filterVal, targetWidgetId;
      filterVal = String(rowData[dep.from_field || 'id']);
      defaults = {};
      defaults[dep.field] = filterVal;
      if (entry.dataView != null) {
        entry.dataView.setDefaultValues(defaults);
        return entry.dataView.setFilter({
          field: dep.field,
          value: filterVal
        });
      } else if (entry.plugin) {
        targetWidgetId = entry.runtimeWidgetId || entry.node.id;
        if (!targetWidgetId) {
          return;
        }
        return this._sendPluginMessage(targetWidgetId, {
          type: 'updateInputSelection',
          selection: {
            rows: [rowData],
            byField: defaults
          }
        });
      }
    }

    _setPluginSelectionListener(widgetId, listener) {
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
    }

    _emitPluginSelection(widgetId, selection) {
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
    }

    _renderPluginWidget(container, wNode, runtimeWidgetId = null) {
      var pluginName, pluginParams;
      pluginName = wNode.type;
      pluginParams = wNode.params || {};
      if (!pluginName) {
        container.innerHTML = "<p style='color:#c55;padding:.5rem'>Plugin manquant (<code>type</code>).</p>";
        return;
      }
      container.innerHTML = `<p style='color:#888;padding:.5rem'>Chargement du plugin ${pluginName}…</p>`;
      return WidgetPlugins.getByName(pluginName).then((plugin) => {
        var widgetId;
        if (!plugin) {
          container.innerHTML = `<p style='color:#c55;padding:.5rem'>Plugin introuvable : ${pluginName}</p>`;
          return;
        }
        widgetId = runtimeWidgetId || wNode.id || `plugin_${Math.random().toString(36).slice(2)}`;
        return this._mountPluginIframe(container, widgetId, plugin, pluginParams);
      }).catch((err) => {
        return container.innerHTML = `<p style='color:#c55;padding:.5rem'>Erreur plugin : ${err.message || err}</p>`;
      });
    }

    _mountPluginIframe(container, widgetId, plugin, pluginParams) {
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
    }

    _compilePlugin(plugin, pluginParams = {}) {
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
    }

    _buildPluginIframeDoc(widgetId, params, compiled, plugin) {
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
    }

    _sendPluginMessage(widgetId, msg) {
      var payload, ref, st;
      st = this._pluginStateByWidgetId[widgetId];
      if (!(st != null ? (ref = st.iframe) != null ? ref.contentWindow : void 0 : void 0)) {
        return;
      }
      payload = Object.assign({widgetId}, msg);
      return st.iframe.contentWindow.postMessage(payload, '*');
    }

    _findSpace(nameOrId) {
      if (!nameOrId) {
        return null;
      }
      return this.allSpaces.find(function(sp) {
        return sp.name === nameOrId || sp.id === nameOrId;
      });
    }

    unmount() {
      var entry, i, id, len, ref, ref1, ref2, st;
      ref = this._pluginStateByWidgetId;
      for (id in ref) {
        if (!hasProp.call(ref, id)) continue;
        st = ref[id];
        if (st.onMessage) {
          window.removeEventListener('message', st.onMessage);
        }
      }
      ref1 = this._widgets;
      for (i = 0, len = ref1.length; i < len; i++) {
        entry = ref1[i];
        if ((ref2 = entry.dataView) != null) {
          if (typeof ref2.unmount === "function") {
            ref2.unmount();
          }
        }
      }
      this.container.innerHTML = '';
      this._widgets = [];
      this._pluginStateByWidgetId = {};
      this._pluginSelectionListenersByWidgetId = {};
      return this._widgetsById = {};
    }

  };

}).call(this);
