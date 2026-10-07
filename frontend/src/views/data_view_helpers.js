(function() {
  // data_view_helpers.coffee — utility methods extracted from views/data_view.coffee
  // (error banner, column-width persistence, cell coercion, default values).
  // Loaded after data_view.js and extends DataView.prototype. No functional change.
  Object.assign(window.DataView.prototype, {
    setDefaultValues: function(values) {
      return this._defaultValues = values || {};
    },
    setFilter: function(filter) {
      this.filter = filter;
      return this._applyData();
    },
    setFormulaFilter: function(formula) {
      this._formulaFilter = formula || '';
      return this.load();
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
        var i, len, ref, results1;
        ref = this.space.fields || [];
        results1 = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
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
      var f, i, len, name, names, out;
      names = colNames || ((function() {
        var i, len, ref, results1;
        ref = this.space.fields || [];
        results1 = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          if (f.fieldType !== 'Sequence' && !(f.formula && f.formula !== '' && !f.triggerFields)) {
            results1.push(f.name);
          }
        }
        return results1;
      }).call(this));
      out = {};
      for (i = 0, len = names.length; i < len; i++) {
        name = names[i];
        out[name] = this._coerceCellValue(name, row != null ? row[name] : void 0, boolNames);
      }
      return out;
    },
    _cloneJson: function(obj) {
      return JSON.parse(JSON.stringify(obj != null ? obj : {}));
    },
    _extractInsertedRecords: function(results) {
      var i, len, out, parsed, r, rec, ref;
      out = [];
      ref = results || [];
      for (i = 0, len = ref.length; i < len; i++) {
        r = ref[i];
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
