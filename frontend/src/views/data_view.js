(function() {
  // data_view.coffee
  // Raw data grid view using Toast UI Grid (tui.Grid).
  var DataView, INSERT_RECORD, RECORDS_QUERY, UPDATE_RECORD, gqlName,
    hasProp = {}.hasOwnProperty;

  RECORDS_QUERY = `query Records($spaceId: ID!, $limit: Int, $offset: Int, $filter: RecordFilter, $reprFormula: String, $reprLanguage: String) {
  records(spaceId: $spaceId, limit: $limit, offset: $offset, filter: $filter, reprFormula: $reprFormula, reprLanguage: $reprLanguage) {
    items { id data }
    total
  }
}`;

  // Convert a space name to a valid GraphQL identifier (mirrors backend gql_name).
  gqlName = function(name) {
    var s;
    s = name.replace(/[^\w]/g, '_');
    if (/^\d/.test(s)) {
      return '_' + s;
    } else {
      return s;
    }
  };

  INSERT_RECORD = `mutation InsertRecord($spaceId: ID!, $data: JSON!) {
  insertRecord(spaceId: $spaceId, data: $data) { id data }
}`;

  UPDATE_RECORD = `mutation UpdateRecord($spaceId: ID!, $id: ID!, $data: JSON!) {
  updateRecord(spaceId: $spaceId, id: $id, data: $data) { id data }
}`;

  window.DataView = DataView = class DataView {
    constructor(container, space, filter1 = null, relations = []) {
      this.container = container;
      this.space = space;
      this.filter = filter1;
      this._grid = null; // tui.Grid instance
      this._rows = []; // rows from server
      this._currentData = []; // rows currently displayed (filtered + sentinel)
      this._defaultValues = {}; // FK defaults for new records (set by depends_on)
      this._mounted = false; // true after mount() completes, false after unmount()
      this._relations = relations;
      this._fkMaps = {}; // field name → { id → display label }
      this._fkOptions = {}; // field name → [{ text, value }]
      this._formulaFilter = ''; // Lua/MoonScript formula for server-side row filtering
      this._formulaTimer = null; // debounce handle
    }

    
      // Build FK display maps for all relation fields.
    async _buildFkMaps() {
      var data, display, e, field, fkId, formula, j, l, len, len1, map, options, rec, records, ref, ref1, ref2, ref3, ref4, rel, results;
      ref = this._relations;
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        rel = ref[j];
        field = (this.space.fields || []).find(function(f) {
          return f.id === rel.fromFieldId;
        });
        if (!field) {
          continue;
        }
        try {
          formula = ((ref1 = rel.reprFormula) != null ? ref1.trim() : void 0) || '@_repr';
          data = (await GQL.query(RECORDS_QUERY, {
            spaceId: rel.toSpaceId,
            limit: 5000,
            reprFormula: formula,
            reprLanguage: 'moonscript'
          }));
          records = data.records.items.map(function(r) {
            var parsed;
            parsed = typeof r.data === 'string' ? JSON.parse(r.data) : r.data;
            return Object.assign({
              __rowId: r.id
            }, parsed);
          });
          map = {};
          options = [];
          for (l = 0, len1 = records.length; l < len1; l++) {
            rec = records[l];
            display = (rec._repr != null) && String(rec._repr).trim() !== '' ? String(rec._repr) : String((ref2 = (ref3 = rec.id) != null ? ref3 : rec[Object.keys(rec).find(function(k) {
              return k !== '__rowId';
            })]) != null ? ref2 : '');
            fkId = (ref4 = rec.id) != null ? ref4 : rec[Object.keys(rec).find(function(k) {
              return k !== '__rowId';
            })];
            map[String(fkId)] = display;
            options.push({
              text: display,
              value: String(fkId)
            });
          }
          options.sort(function(a, b) {
            return a.text.localeCompare(b.text);
          });
          this._fkMaps[field.name] = map;
          results.push(this._fkOptions[field.name] = options);
        } catch (error) {
          e = error;
          results.push(console.warn(`FK map build failed for ${field.name}:`, e));
        }
      }
      return results;
    }

    async mount() {
      var allCols, col, columns, editableCols, editableSet, f, fields, fkMap, fkOptions, formulaNames, moveTo, ref, saved, seqNames, wrapper;
      this._mounted = true;
      this.container.innerHTML = '';
      wrapper = document.createElement('div');
      wrapper.style.cssText = 'width:100%;height:100%;';
      wrapper.tabIndex = -1; // focusable programmatically, invisible in tab order
      this.container.appendChild(wrapper);
      fields = this.space.fields || [];
      seqNames = new Set((function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.fieldType === 'Sequence') {
            results.push(f.name);
          }
        }
        return results;
      })());
      formulaNames = new Set((function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.formula && f.formula !== '' && !f.triggerFields) {
            results.push(f.name);
          }
        }
        return results;
      })());
      saved = this._loadColWidths();
      if (((ref = this._relations) != null ? ref.length : void 0) > 0) {
        await this._buildFkMaps();
      }
      columns = (function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          col = {
            name: f.name,
            header: f.name,
            width: saved[f.name] || 160,
            minWidth: 40,
            resizable: true,
            sortable: true
          };
          if (this._fkMaps[f.name] != null) {
            fkMap = this._fkMaps[f.name];
            fkOptions = this._fkOptions[f.name] || [];
            col.formatter = (function(fkMap) {
              return function(props) {
                var cls, isInternal, m, ref1, safeFull, safeShort, val;
                val = props.value;
                if (typeof val === 'string') {
                  m = val.match(/^\[ERROR\|(.*?)\|(.*)\]$/);
                  if (m) {
                    safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                    safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                    isInternal = safeShort.indexOf('inconnue') > -1;
                    cls = isInternal ? 'formula-error internal-error' : 'formula-error';
                    return `<span class=\"${cls}\" title=\"${safeFull}\">⚠ ${safeShort}</span>`;
                  } else if (val.indexOf('[Erreur de formule:') === 0) {
                    return `<span class=\"formula-error\" title=\"${val.replace(/"/g, '&quot;')}\">⚠ Erreur</span>`;
                  }
                }
                return (ref1 = fkMap[String(val)]) != null ? ref1 : String(val != null ? val : '');
              };
            })(fkMap);
            col.editor = {
              type: 'select',
              options: {
                listItems: fkOptions
              }
            };
          } else {
            if (!(seqNames.has(f.name) || formulaNames.has(f.name))) {
              col.editor = 'text';
            }
            // Highlight formula errors in normal text columns
            col.formatter = function(props) {
              var cls, isInternal, m, safeFull, safeShort, val;
              val = props.value;
              if (typeof val === 'string') {
                m = val.match(/^\[ERROR\|(.*?)\|(.*)\]$/);
                if (m) {
                  safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                  safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                  isInternal = safeShort.indexOf('inconnue') > -1;
                  cls = isInternal ? 'formula-error internal-error' : 'formula-error';
                  return `<span class=\"${cls}\" title=\"${safeFull}\">⚠ ${safeShort}</span>`;
                } else if (val.indexOf('[Erreur de formule:') === 0) {
                  return `<span class=\"formula-error\" title=\"${val.replace(/"/g, '&quot;')}\">⚠ Erreur</span>`;
                }
              }
              return String(val != null ? val : '');
            };
          }
          results.push(col);
        }
        return results;
      }).call(this);
      this._grid = new tui.Grid({
        el: wrapper,
        columns: columns,
        data: [],
        bodyHeight: 'fitToParent',
        rowHeight: 28,
        minRowHeight: 28,
        header: {
          height: 28
        },
        rowHeaders: ['checkbox'],
        scrollX: true,
        scrollY: true,
        copyOptions: {
          useFormattedValue: true
        }
      });
      // Detect Ctrl+V to distinguish paste from manual edit on the sentinel
      this._pasting = false;
      this._pasteListener = (e) => {
        if (e.key === 'v' && (e.ctrlKey || e.metaKey)) {
          this._pasting = true;
          return setTimeout((() => {
            return this._pasting = false;
          }), 300);
        }
      };
      document.addEventListener('keydown', this._pasteListener);
      // Persist column widths on resize
      this._grid.on('columnResized', ({columnName, width}) => {
        var saved2;
        saved2 = this._loadColWidths();
        saved2[columnName] = width;
        return localStorage.setItem(this._lsKey(), JSON.stringify(saved2));
      });
      // Tab / Shift+Tab: move to next/prev cell (all columns), wrapping at row
      // boundaries. Start editing only if the target cell is editable.
      // Listener on document (capture) so it fires even when focus is on wrapper
      // itself (non-editable cell); guarded by wrapper.contains(activeElement).
      editableCols = columns.filter(function(c) {
        return c.editor;
      }).map(function(c) {
        return c.name;
      });
      allCols = columns.map(function(c) {
        return c.name;
      });
      editableSet = new Set(editableCols);
      moveTo = (rowKey, colName) => {
        return setTimeout(() => {
          this._grid.focus(rowKey, colName);
          if (editableSet.has(colName)) {
            return this._grid.startEditing(rowKey, colName);
          } else {
            return wrapper.focus(); // keep browser focus inside grid for non-editable cells
          }
        }, 0);
      };
      this._tabListener = (e) => {
        var cell, colIdx, nextRow, prevRow, rowCount, rowIdx;
        if (e.key !== 'Tab') {
          return;
        }
        if (this._grid == null) {
          return;
        }
        if (!wrapper.contains(document.activeElement)) {
          return;
        }
        cell = this._grid.getFocusedCell();
        if (!(cell != null ? cell.columnName : void 0)) {
          return;
        }
        colIdx = allCols.indexOf(cell.columnName);
        if (colIdx < 0) {
          return;
        }
        rowIdx = this._grid.getIndexOfRow(cell.rowKey);
        rowCount = this._grid.getRowCount();
        // Let browser handle Tab/Shift+Tab if at start/end of grid
        if (e.shiftKey) {
          if (colIdx === 0 && rowIdx === 0) {
            return;
          }
        } else {
          if (colIdx === allCols.length - 1 && rowIdx === rowCount - 1) {
            return;
          }
        }
        e.preventDefault();
        e.stopImmediatePropagation();
        if (e.shiftKey) {
          if (colIdx > 0) {
            return moveTo(cell.rowKey, allCols[colIdx - 1]);
          } else if (rowIdx > 0) {
            prevRow = this._grid.getRowAt(rowIdx - 1);
            return moveTo(prevRow.rowKey, allCols[allCols.length - 1]);
          }
        } else {
          if (colIdx < allCols.length - 1) {
            return moveTo(cell.rowKey, allCols[colIdx + 1]);
          } else if (rowIdx < rowCount - 1) {
            nextRow = this._grid.getRowAt(rowIdx + 1);
            return moveTo(nextRow.rowKey, allCols[0]);
          }
        }
      };
      document.addEventListener('keydown', this._tabListener, true);
      // Handle cell edits (single edit and paste)
      this._grid.on('afterChange', async(ev) => {
        var byRow, c, changes, clipErr, clipRow, clipRows, clipText, colNames, data, i, j, l, len, len1, len2, len3, len4, n, name, name1, o, ops, p, patch, q, ref1, ref2, ref3, ref4, ref5, ref6, rk, row, sentinelPatch, val;
        changes = (ev.changes || []).filter(function(c) {
          return String(c.value) !== String(c.prevValue);
        });
        if (!changes.length) {
          return;
        }
        // Group field changes by row
        byRow = {};
        for (j = 0, len = changes.length; j < len; j++) {
          c = changes[j];
          if (byRow[name1 = c.rowKey] == null) {
            byRow[name1] = {};
          }
          byRow[c.rowKey][c.columnName] = c.value;
        }
        colNames = (function() {
          var l, len1, results;
          results = [];
          for (l = 0, len1 = fields.length; l < len1; l++) {
            f = fields[l];
            if (!seqNames.has(f.name) && !formulaNames.has(f.name)) {
              results.push(f.name);
            }
          }
          return results;
        })();
        ops = [];
        sentinelPatch = null;
        for (rk in byRow) {
          if (!hasProp.call(byRow, rk)) continue;
          patch = byRow[rk];
          for (name in patch) {
            if (!hasProp.call(patch, name)) continue;
            val = patch[name];
            if ((this._fkMaps[name] != null) && (val != null) && val !== '') {
              patch[name] = Number(val);
            }
          }
          // Resolve actual row data from tui.Grid (rowKey ≠ array index after resetData)
          row = this._grid.getRow(Number(rk));
          if (row != null ? row.__isNew : void 0) {
            sentinelPatch = patch;
          } else if (row != null ? row.__rowId : void 0) {
            ops.push(GQL.mutate(UPDATE_RECORD, {
              spaceId: this.space.id,
              id: row.__rowId,
              data: JSON.stringify(patch)
            }));
          }
        }
        // Insertion(s) from sentinel
        if (sentinelPatch) {
          if (this._pasting) {
            try {
              // Re-read clipboard to get all pasted rows (TUI only fills the one sentinel row)
              clipText = (await navigator.clipboard.readText());
              clipRows = clipText.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n').map(function(line) {
                return line.split('\t');
              }).filter(function(cols) {
                return cols.some(function(c) {
                  return c.trim();
                });
              });
              for (l = 0, len1 = clipRows.length; l < len1; l++) {
                clipRow = clipRows[l];
                data = {};
                for (i = o = 0, len2 = colNames.length; o < len2; i = ++o) {
                  name = colNames[i];
                  data[name] = (ref1 = (ref2 = clipRow[i]) != null ? ref2 : this._defaultValues[name]) != null ? ref1 : '';
                }
                ops.push(GQL.mutate(INSERT_RECORD, {
                  spaceId: this.space.id,
                  data: JSON.stringify(data)
                }));
              }
            } catch (error) {
              clipErr = error;
              console.warn('clipboard unavailable, single insert fallback', clipErr);
              data = {};
              for (p = 0, len3 = colNames.length; p < len3; p++) {
                n = colNames[p];
                data[n] = (ref3 = (ref4 = sentinelPatch[n]) != null ? ref4 : this._defaultValues[n]) != null ? ref3 : '';
              }
              ops.push(GQL.mutate(INSERT_RECORD, {
                spaceId: this.space.id,
                data: JSON.stringify(data)
              }));
            }
          } else {
            // Manual edit: insert from sentinel values + defaults
            data = {};
            for (q = 0, len4 = colNames.length; q < len4; q++) {
              n = colNames[q];
              data[n] = (ref5 = (ref6 = sentinelPatch[n]) != null ? ref6 : this._defaultValues[n]) != null ? ref5 : '';
            }
            ops.push(GQL.mutate(INSERT_RECORD, {
              spaceId: this.space.id,
              data: JSON.stringify(data)
            }));
          }
        }
        return Promise.all(ops).then(() => {
          return this.load();
        }).catch((err) => {
          return this._showError(`Erreur d'enregistrement : ${err.message}`);
        });
      });
      return (await this.load());
    }

    // ── Data loading ─────────────────────────────────────────────────────────────
    _sentinel() {
      var f, j, len, ref, ref1, row;
      row = {
        __isNew: true
      };
      ref = this.space.fields || [];
      for (j = 0, len = ref.length; j < len; j++) {
        f = ref[j];
        if (f.fieldType !== 'Sequence') {
          row[f.name] = (ref1 = this._defaultValues[f.name]) != null ? ref1 : '';
        }
      }
      return row;
    }

    async load() {
      var data, e, f, fieldList, fields, focus, focusedRow, formulaNames, gqlFilter, msg, ref, ref1, ref2, spaceQuery, tname;
      if (!this._mounted) {
        return;
      }
      // Save current focus to restore it after resetData
      focus = (ref = this._grid) != null ? ref.getFocusedCell() : void 0;
      if (((focus != null ? focus.rowKey : void 0) != null) && focus.columnName) {
        focusedRow = this._grid.getRow(focus.rowKey);
        if (focusedRow) {
          this._lastFocus = {
            rowId: focusedRow.__rowId,
            isNew: focusedRow.__isNew,
            columnName: focus.columnName
          };
        }
      }
      fields = this.space.fields || [];
      formulaNames = new Set((function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.formula && f.formula !== '' && !f.triggerFields) {
            results.push(f.name);
          }
        }
        return results;
      })());
      if (formulaNames.size > 0 && !this._formulaFilter) {
        // Use the space-specific dynamic resolver so formula fields are evaluated.
        tname = gqlName(this.space.name);
        fieldList = ((function() {
          var j, len, results;
          results = [];
          for (j = 0, len = fields.length; j < len; j++) {
            f = fields[j];
            results.push(gqlName(f.name));
          }
          return results;
        })()).join(' ');
        spaceQuery = `query { ${tname}(limit: 2000) { items { _id ${fieldList} } } }`;
        try {
          data = (await GQL.query(spaceQuery, {}));
          if (!this._mounted) {
            return;
          }
          this._rows = data[tname].items.map(function(item) {
            var row;
            row = Object.assign({}, item);
            row.__rowId = item._id;
            return row;
          });
        } catch (error) {
          e = error;
          this._showError(`Erreur de colonne calculée : ${e.message}`);
          this._rows = [];
        }
      } else {
        gqlFilter = this._formulaFilter ? {
          formula: this._formulaFilter,
          language: 'moonscript'
        } : void 0;
        try {
          data = (await GQL.query(RECORDS_QUERY, {
            spaceId: this.space.id,
            limit: 2000,
            filter: gqlFilter
          }));
          if (!this._mounted) {
            return;
          }
          this._rows = data.records.items.map(function(r) {
            var parsed, row;
            parsed = typeof r.data === 'string' ? JSON.parse(r.data) : r.data;
            row = Object.assign({}, parsed);
            row.__rowId = r.id;
            return row;
          });
          if ((ref1 = document.getElementById('formula-filter-input')) != null) {
            ref1.classList.remove('input-error');
          }
        } catch (error) {
          e = error;
          msg = this._formulaFilter ? `Erreur de filtre : ${e.message}` : `Erreur de chargement : ${e.message}`;
          this._showError(msg);
          if (this._formulaFilter) {
            if ((ref2 = document.getElementById('formula-filter-input')) != null) {
              ref2.classList.add('input-error');
            }
          }
          this._rows = [];
        }
      }
      this._applyData();
      return this._rows;
    }

    _applyData() {
      var base, base1, base2, columnName, displayVal, f, isError, isNew, j, l, lastIdx, len, len1, name1, ref, ref1, row, rowId, rows, sentinel, sentinelRow, targetRow, val;
      if (!this._grid) {
        return;
      }
      rows = this._rows;
      if (this.filter) {
        rows = rows.filter((r) => {
          return String(r[this.filter.field]) === String(this.filter.value);
        });
      }
      sentinel = this._sentinel();
      this._currentData = rows.concat([sentinel]);
      ref = this._currentData;
      
      // Pre-calculate cell classes for formula errors
      for (j = 0, len = ref.length; j < len; j++) {
        row = ref[j];
        if (row._attributes == null) {
          row._attributes = {};
        }
        if ((base = row._attributes).className == null) {
          base.className = {};
        }
        if ((base1 = row._attributes.className).column == null) {
          base1.column = {};
        }
        ref1 = this.space.fields || [];
        for (l = 0, len1 = ref1.length; l < len1; l++) {
          f = ref1[l];
          val = row[f.name];
          displayVal = this._fkMaps[f.name] != null ? this._fkMaps[f.name][String(val)] : val;
          if (typeof displayVal === 'string') {
            isError = displayVal.indexOf('[ERROR|') === 0 || displayVal.indexOf('[Erreur de formule:') === 0;
            if (isError) {
              if ((base2 = row._attributes.className.column)[name1 = f.name] == null) {
                base2[name1] = [];
              }
              row._attributes.className.column[f.name].push('cell-formula-error');
              if (displayVal.indexOf('inconnue') > -1) {
                row._attributes.className.column[f.name].push('cell-formula-error-internal');
              }
            }
          }
        }
      }
      this._grid.resetData(this._currentData);
      // Restore focus if we have saved it
      if (this._lastFocus) {
        ({rowId, isNew, columnName} = this._lastFocus);
        this._lastFocus = null;
        
        // Find the new row object matching the old one
        targetRow = isNew ? this._grid.getData().find(function(r) {
          return r.__isNew;
        }) : rowId ? this._grid.getData().find(function(r) {
          return r.__rowId === rowId;
        }) : null;
        if (targetRow) {
          // Small delay to ensure TUI has finished DOM updates
          setTimeout((() => {
            return this._grid.focus(targetRow.rowKey, columnName);
          }), 0);
        }
      }
      // Find the actual rowKey tui.Grid assigned to the sentinel (last visual row)
      lastIdx = this._currentData.length - 1;
      sentinelRow = this._grid.getRowAt(lastIdx);
      if (sentinelRow != null) {
        return this._grid.addRowClassName(sentinelRow.rowKey, 'tdb-new-row');
      }
    }

    // ── Record actions ────────────────────────────────────────────────────────────
    insertBlank() {
      var data, f, fields, formulaNames, j, len, seqNames;
      fields = this.space.fields || [];
      seqNames = new Set((function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.fieldType === 'Sequence') {
            results.push(f.name);
          }
        }
        return results;
      })());
      formulaNames = new Set((function() {
        var j, len, results;
        results = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.formula && f.formula !== '' && !f.triggerFields) {
            results.push(f.name);
          }
        }
        return results;
      })());
      data = {};
      for (j = 0, len = fields.length; j < len; j++) {
        f = fields[j];
        if (!seqNames.has(f.name) && !formulaNames.has(f.name)) {
          data[f.name] = '';
        }
      }
      return GQL.mutate(INSERT_RECORD, {
        spaceId: this.space.id,
        data: JSON.stringify(data)
      }).then(() => {
        return this.load();
      }).catch((err) => {
        return this._showError(`Erreur insertion : ${err.message}`);
      });
    }

    deleteSelected() {
      var ids, keys, row, toDelete;
      keys = this._grid.getCheckedRowKeys();
      if (!keys.length) {
        return;
      }
      // Filter out sentinel row
      toDelete = keys.map((rk) => {
        return this._currentData[Number(rk)];
      }).filter(function(row) {
        return row && !row.__isNew && row.__rowId;
      });
      if (!toDelete.length) {
        return;
      }
      ids = (function() {
        var j, len, results;
        results = [];
        for (j = 0, len = toDelete.length; j < len; j++) {
          row = toDelete[j];
          results.push(row.__rowId);
        }
        return results;
      })();
      return Spaces.deleteRecords(this.space.id, ids).then(() => {
        return this.load();
      }).catch((err) => {
        return this._showError(`Erreur suppression : ${err.message}`);
      });
    }

    setDefaultValues(values) {
      return this._defaultValues = values || {};
    }

    setFilter(filter) {
      this.filter = filter;
      return this._applyData();
    }

    setFormulaFilter(formula) {
      this._formulaFilter = formula || '';
      return this.load();
    }

    // ── Error display ─────────────────────────────────────────────────────────────
    _showError(msg) {
      var close;
      if (!this._errorBanner) {
        this._errorBanner = document.createElement('div');
        this._errorBanner.className = 'data-view-error-banner';
        close = document.createElement('button');
        close.textContent = '✕';
        close.onclick = () => {
          return this._clearError();
        };
        this._errorBanner.appendChild(close);
        this._errorText = document.createElement('span');
        this._errorBanner.appendChild(this._errorText);
        this.container.insertBefore(this._errorBanner, this.container.firstChild);
      }
      this._errorText.textContent = msg;
      this._errorBanner.classList.remove('hidden');
      clearTimeout(this._errorTimer);
      return this._errorTimer = setTimeout((() => {
        return this._clearError();
      }), 6000);
    }

    _clearError() {
      var ref;
      return (ref = this._errorBanner) != null ? ref.classList.add('hidden') : void 0;
    }

    // ── Column width persistence ──────────────────────────────────────────────────
    _lsKey() {
      return `tdb_colwidths_${this.space.id}`;
    }

    _loadColWidths() {
      try {
        return JSON.parse(localStorage.getItem(this._lsKey()) || '{}');
      } catch (error) {
        return {};
      }
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────────
    unmount() {
      var ref;
      this._mounted = false;
      clearTimeout(this._formulaTimer);
      if (this._pasteListener) {
        document.removeEventListener('keydown', this._pasteListener);
      }
      if (this._tabListener) {
        document.removeEventListener('keydown', this._tabListener, true);
      }
      if ((ref = this._grid) != null) {
        ref.destroy();
      }
      this._grid = null;
      this._currentData = [];
      this._rows = [];
      return this.container.innerHTML = '';
    }

  };

}).call(this);
