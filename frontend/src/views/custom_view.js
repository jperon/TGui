(function() {
  // custom_view.coffee
  // YAML-driven layout renderer.

  // YAML format example:

  //   layout:
  //     direction: vertical
  //     children:
  //       - factor: 2                         # prend 2/3 de la place (optionnel, défaut: 1)
  //         direction: horizontal
  //         children:
  //           - widget:
  //               id: liste-chorales          # identifiant unique du widget (obligatoire si référencé)
  //               title: Chorales
  //               space: chorale
  //               columns: [annee, pupitre]   # colonnes à afficher (optionnel, défaut: toutes)
  //           - widget:
  //               title: Choristes
  //               space: choristes
  //               depends_on:
  //                 widget: liste-chorales    # id du widget source
  //                 field: chorale_id         # FK field in this space
  //                 from_field: id            # referenced field in the source widget's space (défaut: id)
  //       - factor: 1
  //         widget:
  //           title: Personnes
  //           space: personnes
  var CustomView,
    indexOf = [].indexOf;

  window.CustomView = CustomView = class CustomView {
    constructor(container1, yamlText, allSpaces) {
      this.container = container1;
      this.yamlText = yamlText;
      this.allSpaces = allSpaces;
      this._widgets = []; // list of { dataView, node, el }
      this._widgetsById = {}; // id -> entry
    }

    mount() {
      var e, el, parsed, root;
      this.container.innerHTML = '';
      this._widgets = [];
      this._widgetsById = {};
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
      // Wire depends_on after all widgets are mounted
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
      var body, col, delBtn, dv, entry, f, fieldMap, formula, i, lang, len, ref, sp, titleBar, titleText, wrapper;
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
      // Regular data widget
      sp = this._findSpace(wNode.space);
      delBtn = document.createElement('button');
      delBtn.className = 'cv-widget-delete-btn';
      delBtn.title = 'Supprimer les enregistrements sélectionnés';
      delBtn.textContent = '🗑';
      titleBar.appendChild(delBtn);
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
      // Apply formula filter from YAML widget config
      if (wNode.filter) {
        formula = typeof wNode.filter === 'string' ? wNode.filter : wNode.filter.formula || '';
        lang = typeof wNode.filter === 'object' ? wNode.filter.language || 'moonscript' : 'moonscript';
        if (formula) {
          dv._formulaFilter = formula;
        }
      }
      dv.mount();
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
        var c, col, computed, computedFns, errDiv, formulaErrors, i, j, k, keys, l, len, len1, len2, len3, len4, len5, len6, len7, m, n, o, p, q, ref, ref1, row, tbl, tbody, td, th, thead, tr, v;
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
          for (q = 0, len7 = keys.length; q < len7; q++) {
            k = keys[q];
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
        if (!(src != null ? src.dataView : void 0)) {
          console.warn(`depends_on: widget id '${dep.widget}' introuvable ou sans dataView`);
          continue;
        }
        // When a row is clicked in the source grid, filter this widget and set FK default.
        // from_field defaults to 'id' when omitted.
        results.push(((entry, dep, src) => {
          var ref1;
          return (ref1 = src.dataView._grid) != null ? ref1.on('click', (ev) => {
            var defaults, filterVal, ref2, ref3, rowData, rowKey;
            rowKey = ev.rowKey;
            if (rowKey == null) {
              return;
            }
            rowData = src.dataView._currentData[rowKey];
            if (!(rowData && !rowData.__isNew)) {
              return;
            }
            filterVal = String(rowData[dep.from_field || 'id']);
            defaults = {};
            defaults[dep.field] = filterVal;
            if ((ref2 = entry.dataView) != null) {
              ref2.setDefaultValues(defaults);
            }
            return (ref3 = entry.dataView) != null ? ref3.setFilter({
              field: dep.field,
              value: filterVal
            }) : void 0;
          }) : void 0;
        })(entry, dep, src));
      }
      return results;
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
      var entry, i, len, ref, ref1;
      ref = this._widgets;
      for (i = 0, len = ref.length; i < len; i++) {
        entry = ref[i];
        if ((ref1 = entry.dataView) != null) {
          if (typeof ref1.unmount === "function") {
            ref1.unmount();
          }
        }
      }
      this.container.innerHTML = '';
      this._widgets = [];
      return this._widgetsById = {};
    }

  };

}).call(this);
