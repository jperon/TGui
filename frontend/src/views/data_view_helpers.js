(function() {
  // data_view_helpers.coffee — utility methods extracted from views/data_view.coffee
  // (error banner, column-width persistence, cell coercion, default values).
  // Loaded after data_view.js and extends DataView.prototype. No functional change.

  // Un tri est une liste de { column, ascending }. On ignore la colonne technique
  // `sortKey` que Toast UI Grid utilise pour représenter « aucun tri ».
  var normalizeSortEntries;

  normalizeSortEntries = function(entries) {
    var entry, j, len, name, out, ref;
    out = [];
    if (!Array.isArray(entries)) {
      return out;
    }
    for (j = 0, len = entries.length; j < len; j++) {
      entry = entries[j];
      if (!entry) {
        continue;
      }
      name = (ref = entry.column) != null ? ref : entry.columnName;
      if (!name) {
        continue;
      }
      if (name === 'sortKey') {
        continue;
      }
      out.push({
        column: String(name),
        ascending: !!entry.ascending
      });
    }
    return out;
  };

  Object.assign(window.DataView.prototype, {
    setDefaultValues: function(values) {
      return this._defaultValues = values || {};
    },
    setFilter: function(filter) {
      this.filter = filter;
      return this._applyData();
    },
    // Marque une ligne comme active (classe CSS) sans voler le focus clavier ni
    // ouvrir l'édition d'une cellule. Une seule ligne active par grille.
    setActiveRow: function(rowKey) {
      if (!this._grid) {
        return;
      }
      if ((this._activeRowKey != null) && this._activeRowKey !== rowKey) {
        this._grid.removeRowClassName(this._activeRowKey, 'tdb-selected-row');
      }
      this._activeRowKey = null;
      if (rowKey == null) {
        return;
      }
      this._grid.addRowClassName(rowKey, 'tdb-selected-row');
      return this._activeRowKey = rowKey;
    },
    setFormulaFilter: function(formula) {
      this._formulaFilter = formula || '';
      return this.load();
    },
    // ── Tri persistant ───────────────────────────────────────────────────────────
    // `grid.resetData` remet le tri interne de Toast UI Grid à « sortKey » : un tri
    // appliqué par un préréglage serait donc perdu au moindre rechargement (filtre
    // modifié, données rechargées). On garde le tri demandé et on le réapplique
    // après chaque resetData (voir _applyData dans views/data_view.coffee).
    getSortEntries: function() {
      return (this._sortState || []).slice();
    },
    applySortEntries: function(entries) {
      this._sortState = normalizeSortEntries(entries);
      this._applySortState();
      this._pinSentinelLast();
      return this._sortState;
    },
    _sortEntriesFromGrid: function() {
      var e, state;
      if (!(this._grid && typeof this._grid.getSortState === 'function')) {
        return [];
      }
      state = null;
      try {
        state = this._grid.getSortState();
      } catch (error) {
        e = error;
        state = null;
      }
      return normalizeSortEntries(state != null ? state.columns : void 0);
    },
    _applySortState: function() {
      var base, base1, entries, entry, i, j, len, results1;
      if (!this._grid) {
        return;
      }
      entries = this._sortState || [];
      this._applyingSort = true;
      try {
        if (typeof (base = this._grid).unsort === "function") {
          base.unsort();
        }
        results1 = [];
        for (i = j = 0, len = entries.length; j < len; i = ++j) {
          entry = entries[i];
          results1.push(typeof (base1 = this._grid).sort === "function" ? base1.sort(entry.column, entry.ascending, i > 0) : void 0);
        }
        return results1;
      } finally {
        this._applyingSort = false;
      }
    },
    // Tri/retri manuel (clic sur un en-tête) : mémoriser l'état réel de la grille
    // pour qu'il survive au prochain rechargement. Ignoré pendant nos propres
    // réapplications, sinon la remise à zéro de resetData écraserait le tri.
    _onGridSortChanged: function() {
      if (this._applyingSort) {
        return;
      }
      this._sortState = this._sortEntriesFromGrid();
      this._pinSentinelLast();
      if (typeof this._onSortChanged === "function") {
        this._onSortChanged();
      }
      return this._sortState;
    },
    // Toast UI Grid trie TOUTES les lignes, sentinelle comprise, et inverse même le
    // résultat d'un comparateur en tri descendant : aucun comparateur ne peut donc
    // la maintenir en fin de grille. On réinjecte l'ordre obtenu par la grille en
    // terminant par la sentinelle. Le `sortState` transmis à `resetData` ne sert
    // qu'à réafficher les flèches d'en-tête : il ne réordonne pas les lignes (cf.
    // la documentation de `resetData` dans Toast UI Grid, options.sortState).
    _pinSentinelLast: function() {
      var data, first, grid, options, ordered, ref, row, sentinel;
      grid = this._grid;
      if (!(grid && typeof grid.getData === 'function')) {
        return;
      }
      data = grid.getData() || [];
      sentinel = data.find(function(row) {
        return row != null ? row.__isNew : void 0;
      });
      if (!sentinel) {
        return;
      }
      // Déjà en dernière position : rien à réordonner (cas sans tri).
      if ((ref = data[data.length - 1]) != null ? ref.__isNew : void 0) {
        return;
      }
      ordered = (function() {
        var j, len, results1;
        results1 = [];
        for (j = 0, len = data.length; j < len; j++) {
          row = data[j];
          if (!(row != null ? row.__isNew : void 0)) {
            results1.push(row);
          }
        }
        return results1;
      })();
      ordered.push(sentinel);
      options = {};
      first = (this._sortState || [])[0];
      if (first) {
        options.sortState = {
          columnName: first.column,
          ascending: first.ascending,
          multiple: (this._sortState || []).length > 1
        };
      }
      grid.resetData(ordered, options);
      this._currentData = ordered;
      return this._activeRowKey = null;
    },
    // ── Error display ─────────────────────────────────────────────────────────────
    _showError: function(msg) {
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
    },
    _clearError: function() {
      var ref;
      return (ref = this._errorBanner) != null ? ref.classList.add('hidden') : void 0;
    },
    // ── Column width persistence ──────────────────────────────────────────────────
    _lsKey: function() {
      return `tdb_colwidths_${this.space.id}`;
    },
    _loadColWidths: async function() {
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
    },
    _saveColWidths: async function(prefs) {
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
    },
    _columnWidth: function(field, saved) {
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
    },
    _toBoolean: function(v) {
      var s;
      if (v === true) {
        return true;
      }
      s = String(v != null ? v : '').toLowerCase();
      return s === 'true' || s === '1' || s === 'yes' || s === 'on';
    },
    _coerceCellValue: function(fieldName, value, boolNames = null) {
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
    },
    _serializeRowForMutation: function(row, colNames = null, boolNames = null) {
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
    },
    _cloneJson: function(obj) {
      return JSON.parse(JSON.stringify(obj != null ? obj : {}));
    },
    _extractInsertedRecords: function(results) {
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
    },
    _actionContext: function() {
      var ref, ref1;
      if (((ref = window.AppUndoHelpers) != null ? ref.currentContext : void 0) != null) {
        return window.AppUndoHelpers.currentContext(this.space.id);
      } else {
        return {
          spaceId: this.space.id,
          hash: ((ref1 = window.location) != null ? ref1.hash : void 0) || ''
        };
      }
    },
    _defaultCellValue: function(field) {
      if (field.fieldType === 'Boolean') {
        return false;
      } else {
        return '';
      }
    }
  });

}).call(this);
