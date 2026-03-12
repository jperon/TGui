(function() {
  // data_view.coffee
  // Raw data grid view using Toast UI Grid (tui.Grid).
  var DataView, FkSearchEditor, GRID_COL_PREFS_QUERY, INSERT_RECORD, RECORDS_QUERY, SAVE_GRID_COL_PREFS_MUTATION, UPDATE_RECORD, _fkSearchEditorSeq, gqlName,
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

  _fkSearchEditorSeq = 0;

  FkSearchEditor = class FkSearchEditor {
    constructor(props) {
      var current, item, j, label, len, listItems, onKeyDown, raw, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, val, value;
      listItems = (props != null ? (ref = props.columnInfo) != null ? (ref1 = ref.editor) != null ? (ref2 = ref1.options) != null ? ref2.items : void 0 : void 0 : void 0 : void 0) || (props != null ? (ref3 = props.columnInfo) != null ? (ref4 = ref3.editor) != null ? (ref5 = ref4.options) != null ? ref5.listItems : void 0 : void 0 : void 0 : void 0) || [];
      value = props != null ? props.value : void 0;
      this.el = document.createElement('input');
      this.el.type = 'text';
      this.el.className = 'tui-grid-content-text';
      this.el.style.width = '100%';
      this.el.style.boxSizing = 'border-box';
      this.el.autocomplete = 'off';
      this.el.spellcheck = false;
      this.labelToValue = {};
      this.valueToLabel = {};
      this.items = [];
      for (j = 0, len = listItems.length; j < len; j++) {
        item = listItems[j];
        label = String((ref6 = item != null ? item.text : void 0) != null ? ref6 : '');
        raw = item != null ? item.value : void 0;
        val = raw != null ? String(raw) : '';
        this.labelToValue[label] = val;
        if (this.valueToLabel[val] == null) {
          this.valueToLabel[val] = label;
        }
        this.items.push({
          label: label,
          value: val,
          norm: this._normalize(label)
        });
      }
      current = value != null ? String(value) : '';
      this.initialValue = current;
      this.el.value = (ref7 = this.valueToLabel[current]) != null ? ref7 : current;
      this.selectedIndex = 0;
      this.visibleItems = [];
      this.menuVisible = false;
      this.menu = document.createElement('div');
      _fkSearchEditorSeq += 1;
      this.menu.id = `fk-editor-menu-${_fkSearchEditorSeq}`;
      this.menu.className = 'fk-editor-menu';
      this.menu.style.cssText = ['position:fixed', 'z-index:9999', 'display:none', 'max-height:220px', 'overflow:auto', 'background:#fff', 'color:#1f2937', 'border:1px solid #d1d5db', 'border-radius:6px', 'box-shadow:0 8px 20px rgba(0,0,0,0.12)'].join(';');
      onKeyDown = (ev) => {
        var ref8;
        if (ev.key === 'Escape') {
          this.el.value = (ref8 = this.valueToLabel[this.initialValue]) != null ? ref8 : this.initialValue;
          this._hideMenu();
          ev.preventDefault();
          return ev.stopPropagation();
        } else if (ev.key === 'ArrowDown') {
          this._moveSelection(1);
          ev.preventDefault();
          return ev.stopPropagation();
        } else if (ev.key === 'ArrowUp') {
          this._moveSelection(-1);
          ev.preventDefault();
          return ev.stopPropagation();
        } else if (ev.key === 'Enter') {
          if (this.menuVisible && this.visibleItems.length > 0) {
            this._applySelection(this.selectedIndex);
          }
          this._hideMenu();
          ev.preventDefault();
          return ev.stopPropagation();
        }
      };
      this.onKeyDown = onKeyDown;
      this.onInput = () => {
        return this._renderMenu(this.el.value);
      };
      this.onFocus = () => {
        return this._renderMenu(this.el.value);
      };
      this.onBlur = () => {
        return setTimeout((() => {
          return this._hideMenu();
        }), 120);
      };
      this.onWindowChange = () => {
        if (this.menuVisible) {
          return this._positionMenu();
        }
      };
      this.el.addEventListener('keydown', this.onKeyDown);
      this.el.addEventListener('input', this.onInput);
      this.el.addEventListener('focus', this.onFocus);
      this.el.addEventListener('blur', this.onBlur);
    }

    getElement() {
      return this.el;
    }

    mounted() {
      if (this.menu && !this.menu.parentNode) {
        document.body.appendChild(this.menu);
      }
      window.addEventListener('resize', this.onWindowChange);
      window.addEventListener('scroll', this.onWindowChange, true);
      setTimeout((() => {
        var ref;
        return (ref = this.el) != null ? ref.focus() : void 0;
      }), 0);
      setTimeout((() => {
        var ref;
        return (ref = this.el) != null ? ref.select() : void 0;
      }), 0);
      return setTimeout((() => {
        var ref;
        return this._renderMenu((ref = this.el) != null ? ref.value : void 0);
      }), 0);
    }

    getValue() {
      var best, chosen, ref, ref1, ref2, ref3, typed;
      typed = String((ref = (ref1 = this.el) != null ? ref1.value : void 0) != null ? ref : '').trim();
      if (typed === '') {
        return '';
      }
      if (this.labelToValue[typed] != null) {
        return this.labelToValue[typed];
      }
      if (this.menuVisible && this.visibleItems.length > 0) {
        chosen = this.visibleItems[this.selectedIndex];
        if (chosen != null) {
          return String((ref2 = chosen != null ? chosen.value : void 0) != null ? ref2 : '');
        }
      }
      if (/^\d+$/.test(typed)) {
        return typed;
      }
      best = this._filterItems(typed)[0];
      return String((ref3 = best != null ? best.value : void 0) != null ? ref3 : '');
    }

    beforeDestroy() {
      var ref, ref1, ref2, ref3, ref4;
      if (this.onKeyDown) {
        if ((ref = this.el) != null) {
          ref.removeEventListener('keydown', this.onKeyDown);
        }
      }
      if (this.onInput) {
        if ((ref1 = this.el) != null) {
          ref1.removeEventListener('input', this.onInput);
        }
      }
      if (this.onFocus) {
        if ((ref2 = this.el) != null) {
          ref2.removeEventListener('focus', this.onFocus);
        }
      }
      if (this.onBlur) {
        if ((ref3 = this.el) != null) {
          ref3.removeEventListener('blur', this.onBlur);
        }
      }
      if (this.onWindowChange) {
        window.removeEventListener('resize', this.onWindowChange);
      }
      if (this.onWindowChange) {
        window.removeEventListener('scroll', this.onWindowChange, true);
      }
      if ((ref4 = this.menu) != null ? ref4.parentNode : void 0) {
        return this.menu.parentNode.removeChild(this.menu);
      }
    }

    _normalize(s) {
      return String(s != null ? s : '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    }

    _fuzzyScore(query, target) {
      var i, idx, prev, q, score;
      if (query === '') {
        return 0;
      }
      idx = target.indexOf(query);
      if (idx >= 0) {
        return 200 - idx * 4 - (target.length - query.length);
      }
      q = 0;
      score = 0;
      prev = -1;
      i = 0;
      while (i < target.length && q < query.length) {
        if (target[i] === query[q]) {
          score += 4;
          if (prev >= 0 && i === prev + 1) {
            score += 3;
          }
          if (i === q) {
            score += 2;
          }
          prev = i;
          q += 1;
        }
        i += 1;
      }
      if (q !== query.length) {
        return null;
      }
      return score - (target.length - query.length);
    }

    _filterItems(query) {
      var item, j, len, q, ref, s, scored;
      q = this._normalize(String(query != null ? query : '').trim());
      if (q === '') {
        return this.items.slice(0, 25);
      }
      scored = [];
      ref = this.items;
      for (j = 0, len = ref.length; j < len; j++) {
        item = ref[j];
        s = this._fuzzyScore(q, item.norm);
        if (s == null) {
          continue;
        }
        scored.push({
          item,
          score: s
        });
      }
      scored.sort(function(a, b) {
        if (b.score !== a.score) {
          return b.score - a.score;
        } else {
          return a.item.label.localeCompare(b.item.label);
        }
      });
      return scored.slice(0, 25).map(function(x) {
        return x.item;
      });
    }

    _renderMenu(query) {
      var idx, item, j, len, ref, row;
      this.visibleItems = this._filterItems(query);
      if (this.visibleItems.length === 0) {
        this._hideMenu();
        return;
      }
      this.selectedIndex = Math.min(this.selectedIndex, this.visibleItems.length - 1);
      if (this.selectedIndex < 0) {
        this.selectedIndex = 0;
      }
      this.menu.innerHTML = '';
      ref = this.visibleItems;
      for (idx = j = 0, len = ref.length; j < len; idx = ++j) {
        item = ref[idx];
        row = document.createElement('div');
        row.textContent = item.label;
        row.dataset.idx = String(idx);
        row.style.cssText = ['padding:6px 10px', 'cursor:pointer', 'white-space:nowrap', idx === this.selectedIndex ? 'background:#eef2ff' : ''].join(';');
        row.addEventListener('mouseenter', ((idx) => {
          return () => {
            return this.selectedIndex = idx;
          };
        })(idx));
        row.addEventListener('mousedown', ((idx) => {
          return (ev) => {
            ev.preventDefault();
            return this._applySelection(idx);
          };
        })(idx));
        this.menu.appendChild(row);
      }
      this._positionMenu();
      return this._showMenu();
    }

    _positionMenu() {
      var rect;
      if (!(this.el && this.menu)) {
        return;
      }
      rect = this.el.getBoundingClientRect();
      this.menu.style.left = `${Math.round(rect.left)}px`;
      this.menu.style.top = `${Math.round(rect.bottom + 2)}px`;
      return this.menu.style.minWidth = `${Math.max(220, Math.round(rect.width))}px`;
    }

    _showMenu() {
      if (!this.menu) {
        return;
      }
      this.menu.style.display = 'block';
      return this.menuVisible = true;
    }

    _hideMenu() {
      if (!this.menu) {
        return;
      }
      this.menu.style.display = 'none';
      return this.menuVisible = false;
    }

    _moveSelection(delta) {
      var ref, ref1, row;
      if (!(this.visibleItems.length > 0)) {
        return;
      }
      this.selectedIndex = (this.selectedIndex + delta + this.visibleItems.length) % this.visibleItems.length;
      this._renderMenu((ref = this.el) != null ? ref.value : void 0);
      row = (ref1 = this.menu) != null ? typeof ref1.querySelector === "function" ? ref1.querySelector(`[data-idx='${this.selectedIndex}']`) : void 0 : void 0;
      return row != null ? typeof row.scrollIntoView === "function" ? row.scrollIntoView({
        block: 'nearest'
      }) : void 0 : void 0;
    }

    _applySelection(idx) {
      var item;
      item = this.visibleItems[idx];
      if (!item) {
        return;
      }
      this.selectedIndex = idx;
      this.el.value = item.label;
      return this._hideMenu();
    }

  };

  window.DataView = DataView = class DataView {
    constructor(container, space, filter1 = null, relations = [], opts = {}) {
      this.container = container;
      this.space = space;
      this.filter = filter1;
      this._grid = null; // tui.Grid instance
      this._rows = []; // rows from server
      this._currentData = []; // rows currently displayed (filtered + sentinel)
      this._defaultValues = {}; // FK defaults for new records (set by depends_on)
      this._mounted = false; // true after mount() completes, false after unmount()
      this._relations = relations;
      if (typeof opts.onColumnFocus === 'function') {
        this.onColumnFocus = opts.onColumnFocus;
      }
      this._fkMaps = {}; // field name → { id → display label }
      this._fkOptions = {}; // field name → [{ text, value }]
      this._formulaFilter = ''; // Lua/MoonScript formula for server-side row filtering
      this._formulaTimer = null; // debounce handle
      this._focusedColumnName = null;
      this._colWidthsCache = {};
      this._saveWidthsTimer = null;
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
      var allCols, boolNames, col, columns, editableCols, editableSet, escapeHtml, f, fields, fkMap, fkOptions, formulaNames, moveTo, ref, saved, seqNames, setFocusedColumn, toBool, wrapper;
      this._mounted = true;
      this.container.innerHTML = '';
      wrapper = document.createElement('div');
      wrapper.style.cssText = 'width:100%;height:100%;';
      wrapper.tabIndex = -1; // focusable programmatically, invisible in tab order
      this.container.appendChild(wrapper);
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
                var cls, display, isInternal, m, ref1, safeFull, safeShort, val;
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
                  var cls, displayVal, isInternal, m, row, safeFull, safeShort, val;
                  row = props.row;
                  val = props.value;
                  displayVal = row[`_repr_${fieldName}`] != null ? row[`_repr_${fieldName}`] : val;
                  if (typeof displayVal === 'string') {
                    m = displayVal.match(/^\[ERROR\|(.*?)\|(.*)\]$/);
                    if (m) {
                      safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                      safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                      isInternal = safeShort.indexOf('inconnue') > -1;
                      cls = isInternal ? 'formula-error internal-error' : 'formula-error';
                      return `<span class=\"${cls}\" title=\"${safeFull}\">⚠ ${safeShort}</span>`;
                    }
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
              // Highlight formula errors in normal text columns
              col.formatter = ((fieldName) => {
                return (props) => {
                  var cls, displayVal, isInternal, m, row, safe, safeFull, safeShort, val;
                  row = props.row;
                  val = props.value;
                  displayVal = val;
                  // Use per-field representation if available from backend
                  if (row[`_repr_${fieldName}`] != null) {
                    displayVal = row[`_repr_${fieldName}`];
                  }
                  if (typeof displayVal === 'string') {
                    m = displayVal.match(/^\[ERROR\|(.*?)\|(.*)\]$/);
                    if (m) {
                      safeShort = m[1].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                      safeFull = m[2].replace(/"/g, '&quot;').replace(/</g, '&lt;');
                      isInternal = safeShort.indexOf('inconnue') > -1;
                      cls = isInternal ? 'formula-error internal-error' : 'formula-error';
                      return `<span class=\"${cls}\" title=\"${safeFull}\">⚠ ${safeShort}</span>`;
                    } else if (displayVal.indexOf('[Erreur de formule:') === 0) {
                      return `<span class=\"formula-error\" title=\"${displayVal.replace(/"/g, '&quot;')}\">⚠ Erreur</span>`;
                    }
                  }
                  safe = escapeHtml(String(displayVal != null ? displayVal : ''));
                  return `<span class=\"tdb-cell-text\" data-full-text=\"${safe}\">${safe}</span>`;
                };
              })(f.name);
            }
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
          return setFocusedColumn(ev.columnName);
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
        var action, afterData, beforeData, byRow, c, changes, clipErr, clipRow, clipRows, clipText, colNames, data, i, j, l, len, len1, len2, len3, len4, n, name, name1, name2, o, ops, p, patch, prevByRow, prevVal, ref1, ref2, ref3, ref4, ref5, ref6, ref7, rk, row, sentinelPatch, t, val;
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
            for (t = 0, len4 = colNames.length; t < len4; t++) {
              n = colNames[t];
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
      var data, e, f, fieldList, fields, focus, focusedRow, formulaNames, gqlFilter, msg, nm, ref, ref1, ref2, reprNames, spaceQuery, tname;
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
      if ((formulaNames.size > 0 || reprNames.size > 0) && !this._formulaFilter) {
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

    async _loadColWidths() {
      var data, local, prefs, remote;
      local = {};
      try {
        local = JSON.parse(localStorage.getItem(this._lsKey()) || '{}');
      } catch (error) {
        local = {};
      }
      try {
        data = (await GQL.query(GRID_COL_PREFS_QUERY, {
          spaceId: this.space.id
        }));
        remote = data.gridColumnPrefs || {};
        prefs = Object.keys(remote).length > 0 ? remote : local;
        this._colWidthsCache = prefs;
        localStorage.setItem(this._lsKey(), JSON.stringify(prefs));
        return prefs;
      } catch (error) {
        this._colWidthsCache = local;
        return local;
      }
    }

    async _saveColWidths(prefs) {
      var e, isAdmin, ref;
      isAdmin = !!(((ref = window.Auth) != null ? typeof ref.isAdmin === "function" ? ref.isAdmin() : void 0 : void 0) && window.Auth.isAdmin());
      try {
        await GQL.mutate(SAVE_GRID_COL_PREFS_MUTATION, {
          spaceId: this.space.id,
          prefs: prefs || {},
          asDefault: isAdmin ? true : false
        });
      } catch (error) {
        e = error;
        console.warn('saveGridColumnPrefs failed, local fallback only:', e);
      }
      return localStorage.setItem(this._lsKey(), JSON.stringify(prefs || {}));
    }

    _columnWidth(field, saved) {
      var v;
      v = saved[field.name];
      if ((v != null) && !Number.isNaN(Number(v))) {
        return Number(v);
      }
      if (field.name === 'id') {
        return 72;
      }
      if (field.fieldType === 'Boolean') {
        return 72;
      }
      return 160;
    }

    _toBoolean(v) {
      var s;
      if (v === true) {
        return true;
      }
      s = String(v != null ? v : '').toLowerCase();
      return s === 'true' || s === '1' || s === 'yes' || s === 'on';
    }

    _coerceCellValue(fieldName, value, boolNames = null) {
      var boolSet, f;
      if ((this._fkMaps[fieldName] != null) && (value != null) && value !== '') {
        return Number(value);
      }
      boolSet = boolNames || new Set((function() {
        var j, len, ref, results1;
        ref = this.space.fields || [];
        results1 = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          if (f.fieldType === 'Boolean') {
            results1.push(f.name);
          }
        }
        return results1;
      }).call(this));
      if (boolSet.has(fieldName)) {
        return this._toBoolean(value);
      }
      return value;
    }

    _serializeRowForMutation(row, colNames = null, boolNames = null) {
      var f, j, len, name, names, out;
      names = colNames || ((function() {
        var j, len, ref, results1;
        ref = this.space.fields || [];
        results1 = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          if (f.fieldType !== 'Sequence' && !(f.formula && f.formula !== '' && !f.triggerFields)) {
            results1.push(f.name);
          }
        }
        return results1;
      }).call(this));
      out = {};
      for (j = 0, len = names.length; j < len; j++) {
        name = names[j];
        out[name] = this._coerceCellValue(name, row != null ? row[name] : void 0, boolNames);
      }
      return out;
    }

    _cloneJson(obj) {
      return JSON.parse(JSON.stringify(obj != null ? obj : {}));
    }

    _extractInsertedRecords(results) {
      var j, len, out, parsed, r, rec, ref;
      out = [];
      ref = results || [];
      for (j = 0, len = ref.length; j < len; j++) {
        r = ref[j];
        rec = r != null ? r.insertRecord : void 0;
        if (!(rec != null ? rec.id : void 0)) {
          continue;
        }
        parsed = typeof rec.data === 'string' ? JSON.parse(rec.data) : rec.data;
        out.push({
          id: String(rec.id),
          after: parsed || {}
        });
      }
      return out;
    }

    _actionContext() {
      var ref, ref1;
      if (((ref = window.AppUndoHelpers) != null ? ref.currentContext : void 0) != null) {
        return window.AppUndoHelpers.currentContext(this.space.id);
      } else {
        return {
          spaceId: this.space.id,
          hash: ((ref1 = window.location) != null ? ref1.hash : void 0) || ''
        };
      }
    }

    _defaultCellValue(field) {
      if (field.fieldType === 'Boolean') {
        return false;
      } else {
        return '';
      }
    }

    _escapeHtml(s) {
      return String(s != null ? s : '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    getFocusedColumnName() {
      return this._focusedColumnName;
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────────
    unmount() {
      var ref;
      this._mounted = false;
      clearTimeout(this._formulaTimer);
      clearTimeout(this._saveWidthsTimer);
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
