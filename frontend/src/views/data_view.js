(function() {
  // data_view.coffee
  // Raw data grid view using Toast UI Grid (tui.Grid).
  var DELETE_RECORD, DataView, INSERT_RECORD, RECORDS_QUERY, UPDATE_RECORD, gqlName,
    hasProp = {}.hasOwnProperty;

  RECORDS_QUERY = `query Records($spaceId: ID!, $limit: Int, $offset: Int) {
  records(spaceId: $spaceId, limit: $limit, offset: $offset) {
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

  DELETE_RECORD = `mutation DeleteRecord($spaceId: ID!, $id: ID!) {
  deleteRecord(spaceId: $spaceId, id: $id)
}`;

  window.DataView = DataView = class DataView {
    constructor(container, space, filter1 = null) {
      this.container = container;
      this.space = space;
      this.filter = filter1;
      this._grid = null; // tui.Grid instance
      this._rows = []; // rows from server
      this._currentData = []; // rows currently displayed (filtered + sentinel)
      this._defaultValues = {}; // FK defaults for new records (set by depends_on)
      this._mounted = false; // true after mount() completes, false after unmount()
    }

    async mount() {
      var col, columns, editableCols, f, fields, formulaNames, saved, seqNames, wrapper;
      this._mounted = true;
      this.container.innerHTML = '';
      wrapper = document.createElement('div');
      wrapper.style.cssText = 'width:100%;height:100%;';
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
          if (!(seqNames.has(f.name) || formulaNames.has(f.name))) {
            col.editor = 'text';
          }
          results.push(col);
        }
        return results;
      })();
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
      // Tab / Shift+Tab: move to next/prev editable cell on the same row,
      // wrapping to the next/prev row at row boundaries.
      // Use capture phase to intercept before tui.Grid's own Tab handler.
      editableCols = columns.filter(function(c) {
        return c.editor;
      }).map(function(c) {
        return c.name;
      });
      wrapper.addEventListener('keydown', (e) => {
        var cell, idx, nextRow, prevRow, rowCount, rowIdx;
        if (e.key !== 'Tab') {
          return;
        }
        cell = this._grid.getFocusedCell();
        if (!(cell != null ? cell.columnName : void 0)) {
          return;
        }
        idx = editableCols.indexOf(cell.columnName);
        if (idx < 0) {
          return;
        }
        e.preventDefault();
        e.stopImmediatePropagation();
        rowIdx = this._grid.getIndexOfRow(cell.rowKey);
        rowCount = this._grid.getRowCount();
        if (e.shiftKey) {
          if (idx > 0) {
            // Previous column, same row
            return setTimeout(() => {
              this._grid.focus(cell.rowKey, editableCols[idx - 1]);
              return this._grid.startEditing(cell.rowKey, editableCols[idx - 1]);
            }, 0);
          } else if (rowIdx > 0) {
            // Last column of previous row (skip sentinel at end)
            prevRow = this._grid.getRowAt(rowIdx - 1);
            if (!(prevRow != null ? prevRow.__isNew : void 0)) {
              return setTimeout(() => {
                this._grid.focus(prevRow.rowKey, editableCols[editableCols.length - 1]);
                return this._grid.startEditing(prevRow.rowKey, editableCols[editableCols.length - 1]);
              }, 0);
            }
          }
        } else {
          if (idx < editableCols.length - 1) {
            // Next column, same row
            return setTimeout(() => {
              this._grid.focus(cell.rowKey, editableCols[idx + 1]);
              return this._grid.startEditing(cell.rowKey, editableCols[idx + 1]);
            }, 0);
          } else {
            // First column of next row (skip sentinel)
            nextRow = this._grid.getRowAt(rowIdx + 1);
            if ((nextRow != null) && !nextRow.__isNew) {
              return setTimeout(() => {
                this._grid.focus(nextRow.rowKey, editableCols[0]);
                return this._grid.startEditing(nextRow.rowKey, editableCols[0]);
              }, 0);
            }
          }
        }
      }, true); // capture: true
      
      // Handle cell edits (single edit and paste)
      this._grid.on('afterChange', async(ev) => {
        var byRow, c, changes, clipErr, clipRow, clipRows, clipText, colNames, data, i, j, k, l, len, len1, len2, len3, len4, m, n, name, name1, o, ops, patch, ref, ref1, ref2, ref3, ref4, ref5, rk, row, sentinelPatch;
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
          var k, len1, results;
          results = [];
          for (k = 0, len1 = fields.length; k < len1; k++) {
            f = fields[k];
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
              for (k = 0, len1 = clipRows.length; k < len1; k++) {
                clipRow = clipRows[k];
                data = {};
                for (i = l = 0, len2 = colNames.length; l < len2; i = ++l) {
                  name = colNames[i];
                  data[name] = (ref = (ref1 = clipRow[i]) != null ? ref1 : this._defaultValues[name]) != null ? ref : '';
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
              for (m = 0, len3 = colNames.length; m < len3; m++) {
                n = colNames[m];
                data[n] = (ref2 = (ref3 = sentinelPatch[n]) != null ? ref3 : this._defaultValues[n]) != null ? ref2 : '';
              }
              ops.push(GQL.mutate(INSERT_RECORD, {
                spaceId: this.space.id,
                data: JSON.stringify(data)
              }));
            }
          } else {
            // Manual edit: insert from sentinel values + defaults
            data = {};
            for (o = 0, len4 = colNames.length; o < len4; o++) {
              n = colNames[o];
              data[n] = (ref4 = (ref5 = sentinelPatch[n]) != null ? ref5 : this._defaultValues[n]) != null ? ref4 : '';
            }
            ops.push(GQL.mutate(INSERT_RECORD, {
              spaceId: this.space.id,
              data: JSON.stringify(data)
            }));
          }
        }
        return Promise.all(ops).then(() => {
          return this.load();
        }).catch(function(err) {
          return console.error('afterChange', err);
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
      var data, f, fieldList, fields, formulaNames, spaceQuery, tname;
      if (!this._mounted) {
        return;
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
      if (formulaNames.size > 0) {
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
      } else {
        data = (await GQL.query(RECORDS_QUERY, {
          spaceId: this.space.id,
          limit: 2000
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
      }
      this._applyData();
      return this._rows;
    }

    _applyData() {
      var lastIdx, rows, sentinelRow;
      if (!this._grid) {
        return;
      }
      rows = this._rows;
      if (this.filter) {
        rows = rows.filter((r) => {
          return String(r[this.filter.field]) === String(this.filter.value);
        });
      }
      this._currentData = rows.concat([this._sentinel()]);
      this._grid.resetData(this._currentData);
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
      }).catch(function(err) {
        return console.error('insertBlank', err);
      });
    }

    deleteSelected() {
      var keys, ops, toDelete;
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
      ops = toDelete.map((row) => {
        return GQL.mutate(DELETE_RECORD, {
          spaceId: this.space.id,
          id: row.__rowId
        });
      });
      return Promise.all(ops).then(() => {
        return this.load();
      }).catch(function(err) {
        return console.error('deleteSelected', err);
      });
    }

    setDefaultValues(values) {
      return this._defaultValues = values || {};
    }

    setFilter(filter) {
      this.filter = filter;
      return this._applyData();
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
      if (this._pasteListener) {
        document.removeEventListener('keydown', this._pasteListener);
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
