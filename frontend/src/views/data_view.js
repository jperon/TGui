(function() {
  // data_view.coffee
  // Raw data grid view using Toast UI Grid (tui.Grid).
  var DataView, FkSearchEditor, GRID_COL_PREFS_QUERY, INSERT_RECORD, RECORDS_QUERY, SAVE_GRID_COL_PREFS_MUTATION, UPDATE_RECORD, gqlName,
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

  GRID_COL_PREFS_QUERY = `query GridColumnPrefs($spaceId: ID!) {
  gridColumnPrefs(spaceId: $spaceId)
}`;

  SAVE_GRID_COL_PREFS_MUTATION = `mutation SaveGridColumnPrefs($spaceId: ID!, $prefs: JSON!, $asDefault: Boolean) {
  saveGridColumnPrefs(spaceId: $spaceId, prefs: $prefs, asDefault: $asDefault)
}`;

  // FkSearchEditor lives in fk_search_editor.coffee (loaded before this file).
  FkSearchEditor = window.FkSearchEditor;

  window.DataView = DataView = class DataView {
    constructor(container, space, filter = null, relations = [], opts = {}) {
      this.container = container;
      this.space = space;
      this.filter = filter;
      this._grid = null; // tui.Grid instance
      this._rows = []; // rows from server
      this._currentData = []; // rows currently displayed (filtered + sentinel)
      this._defaultValues = {}; // FK defaults for new records (set by depends_on)
      this._mounted = false; // true after mount() completes, false after unmount()
      this._relations = relations;
      if (typeof opts.onColumnFocus === 'function') {
        this.onColumnFocus = opts.onColumnFocus;
      }
      this.opts = opts;
      this._fkMaps = {}; // field name → { id → display label }
      this._fkOptions = {}; // field name → [{ text, value }]
      this._formulaFilter = ''; // Lua/MoonScript formula for server-side row filtering
      this._formulaTimer = null; // debounce handle
      this._sortState = []; // tri demandé (survit aux resetData de Toast UI Grid)
      this._applyingSort = false; // true pendant la réapplication du tri
      this._focusedColumnName = null;
      this._colWidthsCache = {};
      this._saveWidthsTimer = null;
      this._activeRowKey = null; // rowKey of the row highlighted by depends_on cascade
    }

    
      // Build FK display maps for all relation fields.
    async _buildFkMaps() {
      var data, display, e, field, fkId, formula, j, l, len, len1, map, options, rec, records, ref, ref1, ref2, ref3, ref4, ref5, ref6, rel, results1;
      ref = this._relations;
      results1 = [];
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
            display = (rec._repr != null) && String(rec._repr).trim() !== '' ? String(rec._repr) : String((ref2 = (ref3 = (ref4 = rec.id) != null ? ref4 : rec.__rowId) != null ? ref3 : rec[Object.keys(rec).find(function(k) {
              return k !== '__rowId';
            })]) != null ? ref2 : '');
            fkId = (ref5 = (ref6 = rec.id) != null ? ref6 : rec.__rowId) != null ? ref5 : rec[Object.keys(rec).find(function(k) {
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
          results1.push(this._fkOptions[field.name] = options);
        } catch (error) {
          e = error;
          results1.push(console.warn(`FK map build failed for ${field.name}:`, e));
        }
      }
      return results1;
    }

    async mount() {
      var allCols, boolNames, col, columns, editableCols, editableSet, escapeHtml, f, fields, fkMap, fkOptions, fmtError, formulaNames, moveTo, navColumns, ref, saved, seqNames, setFocusedColumn, toBool, wrapper;
      this._mounted = true;
      this.container.innerHTML = '';
      wrapper = document.createElement('div');
      wrapper.style.cssText = 'width:100%;height:100%;';
      wrapper.tabIndex = -1; // focusable programmatically, invisible in tab order
      this.container.appendChild(wrapper);
      this._gridWrapper = wrapper;
      fields = this.space.fields || [];
      seqNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.fieldType === 'Sequence') {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      boolNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.fieldType === 'Boolean') {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      formulaNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.formula && f.formula !== '' && !f.triggerFields) {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      escapeHtml = (s) => {
        return this._escapeHtml(s);
      };
      toBool = (v) => {
        return this._toBoolean(v);
      };
      fmtError = (v) => {
        return this._formatFormulaError(v);
      };
      saved = (await this._loadColWidths());
      if (((ref = this._relations) != null ? ref.length : void 0) > 0) {
        await this._buildFkMaps();
      }
      columns = (function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          col = {
            name: f.name,
            header: f.name,
            width: this._columnWidth(f, saved),
            minWidth: 40,
            resizable: true,
            sortable: true
          };
          if (this._fkMaps[f.name] != null) {
            fkMap = this._fkMaps[f.name];
            fkOptions = this._fkOptions[f.name] || [];
            col.formatter = ((fkMap) => {
              return (props) => {
                var display, err, ref1, val;
                val = props.value;
                err = fmtError(val);
                if (err) {
                  return err;
                }
                display = (ref1 = fkMap[String(val)]) != null ? ref1 : String(val != null ? val : '');
                return escapeHtml(display);
              };
            })(fkMap);
            col.editor = {
              type: FkSearchEditor,
              options: {
                items: fkOptions
              }
            };
          } else {
            if (boolNames.has(f.name)) {
              col.align = 'center';
              col.editor = {
                type: 'checkbox',
                options: {
                  listItems: [
                    {
                      text: '',
                      value: 'true'
                    }
                  ]
                }
              };
              if (seqNames.has(f.name) || formulaNames.has(f.name)) {
                col.editor = null;
              }
              col.formatter = ((fieldName) => {
                return (props) => {
                  var displayVal, err, row, val;
                  row = props.row;
                  val = props.value;
                  displayVal = row[`_repr_${fieldName}`] != null ? row[`_repr_${fieldName}`] : val;
                  err = fmtError(displayVal);
                  if (err) {
                    return err;
                  }
                  if (toBool(displayVal)) {
                    return '☑';
                  } else {
                    return '☐';
                  }
                };
              })(f.name);
            } else {
              if (!(seqNames.has(f.name) || formulaNames.has(f.name))) {
                col.editor = 'text';
              }
              if (this.opts.readOnly) {
                col.editor = null;
              }
              // Highlight formula errors in normal text columns
              col.formatter = ((fieldName) => {
                return (props) => {
                  var displayVal, err, row, safe, val;
                  row = props.row;
                  val = props.value;
                  displayVal = val;
                  // Use per-field representation if available from backend
                  if (row[`_repr_${fieldName}`] != null) {
                    displayVal = row[`_repr_${fieldName}`];
                  }
                  err = fmtError(displayVal);
                  if (err) {
                    return err;
                  }
                  safe = escapeHtml(String(displayVal != null ? displayVal : ''));
                  return `<span class=\"tdb-cell-text\" data-full-text=\"${safe}\">${safe}</span>`;
                };
              })(f.name);
            }
          }
          if (f.hidden) {
            // Champ de liaison chargé mais non affiché (T21) : la colonne reste dans
            // la grille et dans la requête, mais Toast UI Grid la masque (en-tête,
            // panneau de largeurs) ; elle est aussi exclue de la navigation Tab.
            col.hidden = true;
          }
          results1.push(col);
        }
        return results1;
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
        saved2 = Object.assign({}, this._colWidthsCache);
        saved2[columnName] = width;
        this._colWidthsCache = saved2;
        clearTimeout(this._saveWidthsTimer);
        return this._saveWidthsTimer = setTimeout((() => {
          return this._saveColWidths(saved2);
        }), 150);
      });
      setFocusedColumn = (colName) => {
        if (!colName) {
          return;
        }
        this._focusedColumnName = colName;
        return typeof this.onColumnFocus === "function" ? this.onColumnFocus(colName) : void 0;
      };
      this._grid.on('focusChange', (ev) => {
        return setFocusedColumn(ev.columnName);
      });
      this._grid.on('click', (ev) => {
        if (ev != null ? ev.columnName : void 0) {
          setFocusedColumn(ev.columnName);
        }
        if ((ev != null ? ev.rowKey : void 0) != null) {
          return this.setActiveRow(ev.rowKey);
        }
      });
      this._grid.on('mouseover', (ev) => {
        var cellEl, fullText, ref1, ref2, textEl;
        if ((ev != null ? ev.targetType : void 0) !== 'cell') {
          return;
        }
        cellEl = (ref1 = ev.nativeEvent) != null ? (ref2 = ref1.target) != null ? typeof ref2.closest === "function" ? ref2.closest('.tui-grid-cell') : void 0 : void 0 : void 0;
        if (!cellEl) {
          return;
        }
        textEl = cellEl.querySelector('.tdb-cell-text');
        if (!textEl) {
          return;
        }
        fullText = textEl.getAttribute('data-full-text') || textEl.textContent || '';
        if (textEl.scrollWidth > textEl.clientWidth + 1) {
          return cellEl.setAttribute('title', fullText);
        } else {
          return cellEl.removeAttribute('title');
        }
      });
      // Clic sur un en-tête : mémoriser le tri pour qu'il survive au prochain
      // resetData (rechargement du filtre, insertion, suppression…).
      this._grid.on('afterSort', (ev) => {
        return this._onGridSortChanged();
      });
      this._grid.on('afterUnsort', (ev) => {
        return this._onGridSortChanged();
      });
      // Maj+clic sur un en-tête : Toast UI Grid ne fait du tri multiple qu'avec
      // Ctrl/Cmd (comportement natif). On intercepte Maj+clic en phase de capture
      // pour ajouter (ou inverser) un critère secondaire sans effacer les autres.
      this._shiftSortListener = (ev) => {
        var btn, columnName, ref1, ref2;
        if (!(ev != null ? ev.shiftKey : void 0)) {
          return;
        }
        btn = (ref1 = ev.target) != null ? typeof ref1.closest === "function" ? ref1.closest('.tui-grid-btn-sorting') : void 0 : void 0;
        if (!btn) {
          return;
        }
        columnName = typeof btn.closest === "function" ? (ref2 = btn.closest('[data-column-name]')) != null ? typeof ref2.getAttribute === "function" ? ref2.getAttribute('data-column-name') : void 0 : void 0 : void 0;
        if (!columnName) {
          return;
        }
        if (typeof ev.preventDefault === "function") {
          ev.preventDefault();
        }
        if (typeof ev.stopPropagation === "function") {
          ev.stopPropagation();
        }
        return this.sortWithShiftClick(columnName);
      };
      wrapper.addEventListener('click', this._shiftSortListener, true);
      // Tab / Shift+Tab: move to next/prev cell (all columns), wrapping at row
      // boundaries. Start editing only if the target cell is editable.
      // Listener on document (capture) so it fires even when focus is on wrapper
      // itself (non-editable cell); guarded by wrapper.contains(activeElement).
      navColumns = columns.filter(function(c) {
        return !c.hidden;
      });
      editableCols = navColumns.filter(function(c) {
        return c.editor;
      }).map(function(c) {
        return c.name;
      });
      allCols = navColumns.map(function(c) {
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
        var action, afterData, beforeData, byRow, c, changes, clipErr, clipRow, clipRows, clipText, colNames, data, i, j, l, len, len1, len2, len3, len4, n, name, name1, name2, o, ops, p, patch, prevByRow, prevVal, q, ref1, ref2, ref3, ref4, ref5, ref6, ref7, rk, row, sentinelPatch, val;
        changes = (ev.changes || []).filter(function(c) {
          return String(c.value) !== String(c.prevValue);
        });
        if (!changes.length) {
          return;
        }
        // Group field changes by row
        byRow = {};
        prevByRow = {};
        for (j = 0, len = changes.length; j < len; j++) {
          c = changes[j];
          if (byRow[name1 = c.rowKey] == null) {
            byRow[name1] = {};
          }
          if (prevByRow[name2 = c.rowKey] == null) {
            prevByRow[name2] = {};
          }
          byRow[c.rowKey][c.columnName] = c.value;
          prevByRow[c.rowKey][c.columnName] = c.prevValue;
        }
        colNames = (function() {
          var l, len1, results1;
          results1 = [];
          for (l = 0, len1 = fields.length; l < len1; l++) {
            f = fields[l];
            if (!seqNames.has(f.name) && !formulaNames.has(f.name)) {
              results1.push(f.name);
            }
          }
          return results1;
        })();
        ops = [];
        sentinelPatch = null;
        action = {
          spaceId: this.space.id,
          context: this._actionContext(),
          updates: [],
          inserts: [],
          deletes: []
        };
        for (rk in byRow) {
          if (!hasProp.call(byRow, rk)) continue;
          patch = byRow[rk];
          for (name in patch) {
            if (!hasProp.call(patch, name)) continue;
            val = patch[name];
            if ((this._fkMaps[name] != null) && (val != null) && val !== '') {
              patch[name] = Number(val);
            }
            if (boolNames.has(name)) {
              patch[name] = this._toBoolean(val);
            }
          }
          // Resolve actual row data from tui.Grid (rowKey ≠ array index after resetData)
          row = this._grid.getRow(Number(rk));
          if (row != null ? row.__isNew : void 0) {
            sentinelPatch = patch;
          } else if (row != null ? row.__rowId : void 0) {
            beforeData = {};
            afterData = {};
            ref1 = prevByRow[rk] || {};
            for (n in ref1) {
              if (!hasProp.call(ref1, n)) continue;
              prevVal = ref1[n];
              beforeData[n] = this._coerceCellValue(n, prevVal, boolNames);
              afterData[n] = this._coerceCellValue(n, row != null ? row[n] : void 0, boolNames);
            }
            action.updates.push({
              id: String(row.__rowId),
              before: beforeData,
              after: afterData
            });
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
                  data[name] = (ref2 = (ref3 = clipRow[i]) != null ? ref3 : this._defaultValues[name]) != null ? ref2 : '';
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
                data[n] = (ref4 = (ref5 = sentinelPatch[n]) != null ? ref5 : this._defaultValues[n]) != null ? ref4 : '';
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
              data[n] = (ref6 = (ref7 = sentinelPatch[n]) != null ? ref7 : this._defaultValues[n]) != null ? ref6 : '';
            }
            ops.push(GQL.mutate(INSERT_RECORD, {
              spaceId: this.space.id,
              data: JSON.stringify(data)
            }));
          }
        }
        return Promise.all(ops).then((results) => {
          var ref8, ref9;
          action.inserts = this._extractInsertedRecords(results);
          if (action.updates.length > 0 || action.inserts.length > 0) {
            if ((ref8 = window.AppUndoHelpers) != null) {
              if (typeof ref8.pushAction === "function") {
                ref8.pushAction(action);
              }
            }
          }
          if ((ref9 = window.AppUndoHelpers) != null) {
            if (typeof ref9.refreshUI === "function") {
              ref9.refreshUI(window.App);
            }
          }
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
          row[f.name] = (ref1 = this._defaultValues[f.name]) != null ? ref1 : this._defaultCellValue(f);
        }
      }
      return row;
    }

    async load() {
      var computedNames, data, e, f, fieldList, fields, focus, focusedRow, gqlFilter, gridHasFocus, nm, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, reprNames, spaceFilter, spaceQuery, tname;
      if (!this._mounted) {
        return;
      }
      // Save current focus to restore it after resetData — but only when the browser
      // focus is actually inside the grid. A reload triggered from an input outside
      // the grid (e.g. the live formula filter) must not steal the focus back.
      this._lastFocus = null;
      gridHasFocus = (ref = this.container) != null ? ref.contains(document.activeElement) : void 0;
      if (gridHasFocus) {
        focus = (ref1 = this._grid) != null ? ref1.getFocusedCell() : void 0;
      }
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
      // Every field carrying a formula (trigger or not) must be read through the
      // dynamic space query: a trigger formula may have no stored value yet.
      computedNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.formula && f.formula !== '') {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      reprNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.reprFormula && f.reprFormula !== '') {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      if (this.space.isView) {
        try {
          // For Data Views, we use the specialized execution query
          data = (await DataViews.execute(this.space.viewId, 2000, 0));
          if (!this._mounted) {
            return;
          }
          this._rows = data.map(function(r) {
            var row;
            row = Object.assign({}, r);
            row.__rowId = r.id;
            return row;
          });
        } catch (error) {
          e = error;
          this._showError(`Erreur d'exécution de la vue : ${e.message}`);
          this._rows = [];
        }
      } else if (computedNames.size > 0 || reprNames.size > 0) {
        // Use the space-specific dynamic resolver so formula fields are evaluated.
        tname = gqlName(this.space.name);
        fieldList = (function() {
          var j, len, results1;
          results1 = [];
          for (j = 0, len = fields.length; j < len; j++) {
            f = fields[j];
            nm = gqlName(f.name);
            if (f.reprFormula && f.reprFormula !== '') {
              results1.push(nm + ` _repr_${nm}`);
            } else {
              results1.push(nm);
            }
          }
          return results1;
        })();
        fieldList = fieldList.join(' ');
        // The dynamic space query also accepts a RecordFilter (dynamic.moon), so an
        // active formula filter no longer forces the plain records query — which
        // would drop read-computed columns (no stored value for them).
        spaceFilter = this._formulaFilter ? {
          formula: this._formulaFilter,
          language: 'moonscript'
        } : void 0;
        spaceQuery = `query($filter: RecordFilter) { ${tname}(limit: 2000, filter: $filter) { items { _id ${fieldList} } } }`;
        try {
          data = (await GQL.query(spaceQuery, {
            filter: spaceFilter
          }));
          if (!this._mounted) {
            return;
          }
          this._rows = data[tname].items.map(function(item) {
            var row;
            row = Object.assign({}, item);
            row.__rowId = item._id;
            return row;
          });
          if ((ref2 = this._formulaInputEl) != null) {
            ref2.classList.remove('input-error');
          }
          if ((ref3 = document.getElementById('formula-filter-input')) != null) {
            ref3.classList.remove('input-error');
          }
        } catch (error) {
          e = error;
          this._showError(`Erreur de colonne calculée : ${e.message}`);
          if (this._formulaFilter) {
            if ((ref4 = this._formulaInputEl) != null) {
              ref4.classList.add('input-error');
            }
            if ((ref5 = document.getElementById('formula-filter-input')) != null) {
              ref5.classList.add('input-error');
            }
          }
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
          if ((ref6 = this._formulaInputEl) != null) {
            ref6.classList.remove('input-error');
          }
          if ((ref7 = document.getElementById('formula-filter-input')) != null) {
            ref7.classList.remove('input-error');
          }
        } catch (error) {
          e = error;
          if ((ref8 = this._formulaInputEl) != null) {
            ref8.classList.add('input-error');
          }
          if ((ref9 = document.getElementById('formula-filter-input')) != null) {
            ref9.classList.add('input-error');
          }
          this._rows = [];
          this._rows = [];
        }
      }
      this._applyData();
      return this._rows;
    }

    _applyData() {
      var base, base1, base2, columnName, displayVal, f, isError, isNew, j, l, len, len1, name1, ref, ref1, ref2, row, rowId, rows, sentinel, sentinelRow, targetRow, val;
      if (!this._grid) {
        return;
      }
      // « aucun résultat » : un widget dépendant dont la source n'a aucune ligne
      // correspondante n'affiche aucune ligne (ni donnée, ni sentinelle).
      if (this.filter && this.filter.none) {
        this._currentData = [];
        this._activeRowKey = null;
        this._grid.resetData(this._currentData);
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
          displayVal = val;
          if (row[`_repr_${f.name}`] != null) {
            displayVal = row[`_repr_${f.name}`];
          } else if (this._fkMaps[f.name] != null) {
            displayVal = this._fkMaps[f.name][String(val)];
          }
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
      // resetData rebuilds rows: the highlighted row key is no longer tracked.
      this._activeRowKey = null;
      // resetData remet le tri de Toast UI Grid à zéro : réapplique celui demandé
      // (préréglage ou tri manuel mémorisé) pour qu'il persiste après un load.
      // Le tri porte sur TOUTES les lignes, sentinelle comprise : on la remet
      // ensuite en dernière position (cf. _pinSentinelLast).
      if ((ref2 = this._sortState) != null ? ref2.length : void 0) {
        this._applySortState();
        this._pinSentinelLast();
      }
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
      // La sentinelle se repère par `__isNew`, jamais par son index : le tri peut
      // avoir changé l'ordre visuel. Repli par index pour une grille sans getData.
      sentinelRow = typeof this._grid.getData === 'function' ? (this._grid.getData() || []).find(function(row) {
        return row != null ? row.__isNew : void 0;
      }) : this._grid.getRowAt(this._currentData.length - 1);
      if (sentinelRow != null) {
        return this._grid.addRowClassName(sentinelRow.rowKey, 'tdb-new-row');
      }
    }

    // ── Record actions ────────────────────────────────────────────────────────────
    insertBlank() {
      var data, f, fields, formulaNames, j, len, seqNames;
      fields = this.space.fields || [];
      seqNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.fieldType === 'Sequence') {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      formulaNames = new Set((function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = fields.length; j < len; j++) {
          f = fields[j];
          if (f.formula && f.formula !== '' && !f.triggerFields) {
            results1.push(f.name);
          }
        }
        return results1;
      })());
      data = {};
      for (j = 0, len = fields.length; j < len; j++) {
        f = fields[j];
        if (!seqNames.has(f.name) && !formulaNames.has(f.name)) {
          data[f.name] = this._defaultCellValue(f);
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
      var action, ids, keys, row, toDelete;
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
        var j, len, results1;
        results1 = [];
        for (j = 0, len = toDelete.length; j < len; j++) {
          row = toDelete[j];
          results1.push(row.__rowId);
        }
        return results1;
      })();
      action = {
        spaceId: this.space.id,
        context: this._actionContext(),
        updates: [],
        inserts: [],
        deletes: (function() {
          var j, len, results1;
          results1 = [];
          for (j = 0, len = toDelete.length; j < len; j++) {
            row = toDelete[j];
            results1.push({
              id: String(row.__rowId),
              before: this._serializeRowForMutation(row)
            });
          }
          return results1;
        }).call(this)
      };
      return Spaces.deleteRecords(this.space.id, ids).then(() => {
        var ref, ref1;
        if (action.deletes.length > 0) {
          if ((ref = window.AppUndoHelpers) != null) {
            if (typeof ref.pushAction === "function") {
              ref.pushAction(action);
            }
          }
        }
        if ((ref1 = window.AppUndoHelpers) != null) {
          if (typeof ref1.refreshUI === "function") {
            ref1.refreshUI(window.App);
          }
        }
        return this.load();
      }).catch((err) => {
        return this._showError(`Erreur suppression : ${err.message}`);
      });
    }

    _formatFormulaError(val) {
      var cls, isInternal, m, safeFull, safeShort;
      if (typeof val === 'string') {
        m = val.match(/^\[ERROR\|(.*?)\|(.*)\]$/);
        if (m) {
          safeShort = window.TdbHtml.escape(m[1]);
          safeFull = window.TdbHtml.escape(m[2]);
          isInternal = safeShort.indexOf('inconnue') > -1;
          cls = isInternal ? 'formula-error internal-error' : 'formula-error';
          return `<span class=\"${cls}\" title=\"${safeFull}\">⚠ ${safeShort}</span>`;
        } else if (val.indexOf('[Erreur de formule:') === 0) {
          return `<span class=\"formula-error\" title=\"${window.TdbHtml.escape(val)}\">⚠ Erreur</span>`;
        }
      }
      return null;
    }

    _escapeHtml(s) {
      return window.TdbHtml.escape(s);
    }

    getFocusedColumnName() {
      return this._focusedColumnName;
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────────
    unmount() {
      var ref, ref1, ref2;
      this._mounted = false;
      clearTimeout(this._formulaTimer);
      clearTimeout(this._saveWidthsTimer);
      if ((ref = this._viewPresetsMenu) != null) {
        if (typeof ref.destroy === "function") {
          ref.destroy();
        }
      }
      this._viewPresetsMenu = null;
      if (this._pasteListener) {
        document.removeEventListener('keydown', this._pasteListener);
      }
      if (this._tabListener) {
        document.removeEventListener('keydown', this._tabListener, true);
      }
      if (this._shiftSortListener) {
        if ((ref1 = this._gridWrapper) != null) {
          if (typeof ref1.removeEventListener === "function") {
            ref1.removeEventListener('click', this._shiftSortListener, true);
          }
        }
      }
      this._gridWrapper = null;
      if ((ref2 = this._grid) != null) {
        ref2.destroy();
      }
      this._grid = null;
      this._currentData = [];
      this._rows = [];
      this._activeRowKey = null;
      return this.container.innerHTML = '';
    }

  };

}).call(this);
