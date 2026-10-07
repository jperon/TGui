(function() {
  // custom_view_aggregate.coffee — aggregate widget rendering extracted from custom_view.coffee
  // Extends the CustomView class (defined in custom_view.js) via its prototype.
  // Loaded after views/custom_view.js.
  var indexOf = [].indexOf;

  Object.assign(window.CustomView.prototype, {
    // Render an aggregate (GROUP BY) widget as a read-only table.
    _renderAggregate: function(container, wNode) {
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
        return this._setMessage(container, `Erreur : ${err.message || err}`, 'color:#c55;padding:.5rem');
      });
    }
  });

}).call(this);
