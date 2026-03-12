(function() {
  // app_undo_helpers.coffee — global undo/redo stack with optimistic conflict checks
  var RECORD_QUERY, RESTORE_RECORDS, UPDATE_RECORDS, isPlainObject, waitUntil,
    hasProp = {}.hasOwnProperty;

  RECORD_QUERY = `query Record($spaceId: ID!, $id: ID!) {
  record(spaceId: $spaceId, id: $id) { id data }
}`;

  UPDATE_RECORDS = `mutation UpdateRecords($spaceId: ID!, $records: [RecordUpdateInput!]!) {
  updateRecords(spaceId: $spaceId, records: $records) { id data }
}`;

  RESTORE_RECORDS = `mutation RestoreRecords($spaceId: ID!, $records: [RecordUpdateInput!]!) {
  restoreRecords(spaceId: $spaceId, records: $records) { id data }
}`;

  waitUntil = function(fn, timeoutMs = 3000, stepMs = 40) {
    return new Promise(function(resolve) {
      var started, tick;
      started = Date.now();
      tick = function() {
        if (fn()) {
          return resolve(true);
        } else if (Date.now() - started >= timeoutMs) {
          return resolve(false);
        } else {
          return setTimeout(tick, stepMs);
        }
      };
      return tick();
    });
  };

  isPlainObject = function(v) {
    return !!v && Object.prototype.toString.call(v) === '[object Object]';
  };

  window.AppUndoHelpers = {
    _undoStack: [],
    _redoStack: [],
    _maxDepth: 150,
    _keyboardBound: false,
    currentContext: function(spaceId = null) {
      var hash, hashSpaceId, m, ref, viewId;
      hash = ((ref = window.location) != null ? ref.hash : void 0) || '';
      viewId = null;
      hashSpaceId = null;
      if (m = hash.match(/^#view\/(.+)$/)) {
        viewId = m[1];
      } else if (m = hash.match(/^#space\/(.+)$/)) {
        hashSpaceId = m[1];
      }
      return {
        hash: hash,
        viewId: viewId,
        spaceId: spaceId || hashSpaceId
      };
    },
    clear: function() {
      this._undoStack = [];
      return this._redoStack = [];
    },
    pushAction: function(action) {
      if (!action) {
        return;
      }
      if (!action.spaceId) {
        return;
      }
      action.createdAt = Date.now();
      this._undoStack.push(action);
      if (this._undoStack.length > this._maxDepth) {
        this._undoStack.shift();
      }
      return this._redoStack = [];
    },
    canUndo: function() {
      return this._undoStack.length > 0;
    },
    canRedo: function() {
      return this._redoStack.length > 0;
    },
    _clone: function(v) {
      return JSON.parse(JSON.stringify(v != null ? v : null));
    },
    _normalizeData: function(v) {
      if (v === null) {
        return v;
      }
      if (typeof v === 'string') {
        try {
          return JSON.parse(v);
        } catch (error) {
          return v;
        }
      }
      return v;
    },
    _stableJson: function(v) {
      var keys;
      if (Array.isArray(v)) {
        return '[' + (v.map((x) => {
          return this._stableJson(x);
        })).join(',') + ']';
      }
      if (isPlainObject(v)) {
        keys = Object.keys(v).sort();
        return '{' + (keys.map((k) => {
          return JSON.stringify(k) + ':' + this._stableJson(v[k]);
        })).join(',') + '}';
      }
      return JSON.stringify(v);
    },
    _sameData: function(a, b) {
      return this._stableJson(this._normalizeData(a)) === this._stableJson(this._normalizeData(b));
    },
    _sameDataSubset: function(currentData, expectedData) {
      var cur, exp, k, v;
      cur = this._normalizeData(currentData);
      exp = this._normalizeData(expectedData);
      if (!isPlainObject(exp)) {
        return this._sameData(cur, exp);
      }
      if (!isPlainObject(cur)) {
        return false;
      }
      for (k in exp) {
        if (!hasProp.call(exp, k)) continue;
        v = exp[k];
        if (!this._sameData(cur[k], v)) {
          return false;
        }
      }
      return true;
    },
    _fetchRecord: async function(spaceId, id) {
      var data, rec;
      data = (await GQL.query(RECORD_QUERY, {spaceId, id}));
      rec = data != null ? data.record : void 0;
      if (!rec) {
        return null;
      }
      return {
        id: String(rec.id),
        data: this._normalizeData(rec.data)
      };
    },
    _fetchRecordMap: async function(spaceId, ids) {
      var id, out, uniq;
      uniq = [
        ...new Set((function() {
          var i,
        len,
        results;
          results = [];
          for (i = 0, len = ids.length; i < len; i++) {
            id = ids[i];
            if (id != null) {
              results.push(String(id));
            }
          }
          return results;
        })())
      ];
      out = {};
      await Promise.all(uniq.map(async(id) => {
        var rec;
        rec = (await this._fetchRecord(spaceId, id));
        return out[id] = rec;
      }));
      return out;
    },
    _buildPlan: function(action, direction) {
      var checks, deleteIds, deletes, i, inserts, j, l, len, len1, len2, len3, len4, len5, n, o, p, rec, restoreRecords, updateRecords, updates;
      updates = action.updates || [];
      inserts = action.inserts || [];
      deletes = action.deletes || [];
      checks = [];
      updateRecords = [];
      deleteIds = [];
      restoreRecords = [];
      if (direction === 'undo') {
        for (i = 0, len = updates.length; i < len; i++) {
          rec = updates[i];
          checks.push({
            id: rec.id,
            expect: 'match',
            mode: 'subset',
            expected: rec.after,
            reason: `Le record ${rec.id} a changé sur le serveur`
          });
          updateRecords.push({
            id: rec.id,
            data: rec.before
          });
        }
        for (j = 0, len1 = inserts.length; j < len1; j++) {
          rec = inserts[j];
          checks.push({
            id: rec.id,
            expect: 'match',
            expected: rec.after,
            reason: `Le record inséré ${rec.id} a changé sur le serveur`
          });
          deleteIds.push(rec.id);
        }
        for (l = 0, len2 = deletes.length; l < len2; l++) {
          rec = deletes[l];
          checks.push({
            id: rec.id,
            expect: 'absent',
            reason: `Le record supprimé ${rec.id} existe déjà`
          });
          restoreRecords.push({
            id: rec.id,
            data: rec.before
          });
        }
      } else {
        for (n = 0, len3 = updates.length; n < len3; n++) {
          rec = updates[n];
          checks.push({
            id: rec.id,
            expect: 'match',
            mode: 'subset',
            expected: rec.before,
            reason: `Le record ${rec.id} a changé sur le serveur`
          });
          updateRecords.push({
            id: rec.id,
            data: rec.after
          });
        }
        for (o = 0, len4 = inserts.length; o < len4; o++) {
          rec = inserts[o];
          checks.push({
            id: rec.id,
            expect: 'absent',
            reason: `Le record ${rec.id} existe déjà`
          });
          restoreRecords.push({
            id: rec.id,
            data: rec.after
          });
        }
        for (p = 0, len5 = deletes.length; p < len5; p++) {
          rec = deletes[p];
          checks.push({
            id: rec.id,
            expect: 'match',
            expected: rec.before,
            reason: `Le record ${rec.id} a changé sur le serveur`
          });
          deleteIds.push(rec.id);
        }
      }
      return {
        spaceId: action.spaceId,
        context: action.context || {},
        checks: checks,
        updateRecords: updateRecords,
        deleteIds: deleteIds,
        restoreRecords: restoreRecords
      };
    },
    _verifyPlan: async function(plan) {
      var c, chk, cur, i, ids, len, ref, same, server;
      ids = (function() {
        var i, len, ref, results;
        ref = plan.checks;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          c = ref[i];
          results.push(c.id);
        }
        return results;
      })();
      server = (await this._fetchRecordMap(plan.spaceId, ids));
      ref = plan.checks;
      for (i = 0, len = ref.length; i < len; i++) {
        chk = ref[i];
        cur = server[String(chk.id)];
        if (chk.expect === 'absent') {
          if (cur != null) {
            return {
              ok: false,
              message: chk.reason
            };
          }
        } else if (chk.expect === 'match') {
          if (cur == null) {
            return {
              ok: false,
              message: `Record ${chk.id} introuvable`
            };
          }
          same = chk.mode === 'subset' ? this._sameDataSubset(cur.data, chk.expected) : this._sameData(cur.data, chk.expected);
          if (!same) {
            return {
              ok: false,
              message: chk.reason
            };
          }
        }
      }
      return {
        ok: true
      };
    },
    _executePlan: async function(plan) {
      var id, payload;
      if (plan.updateRecords.length > 0) {
        payload = plan.updateRecords.map(function(r) {
          var ref;
          return {
            id: String(r.id),
            data: JSON.stringify((ref = r.data) != null ? ref : {})
          };
        });
        await GQL.mutate(UPDATE_RECORDS, {
          spaceId: plan.spaceId,
          records: payload
        });
      }
      if (plan.deleteIds.length > 0) {
        await Spaces.deleteRecords(plan.spaceId, (function() {
          var i, len, ref, results;
          ref = plan.deleteIds;
          results = [];
          for (i = 0, len = ref.length; i < len; i++) {
            id = ref[i];
            results.push(String(id));
          }
          return results;
        })());
      }
      if (plan.restoreRecords.length > 0) {
        payload = plan.restoreRecords.map(function(r) {
          var ref;
          return {
            id: String(r.id),
            data: JSON.stringify((ref = r.data) != null ? ref : {})
          };
        });
        return (await GQL.mutate(RESTORE_RECORDS, {
          spaceId: plan.spaceId,
          records: payload
        }));
      }
    },
    _navigateToContext: async function(app, context) {
      var ctx, li, ref, ref1, ref2, ref3, sp;
      if (!app) {
        return;
      }
      ctx = context || {};
      if (ctx.viewId) {
        if (((ref = app._currentCustomView) != null ? ref.id : void 0) !== ctx.viewId) {
          li = (ref1 = app.el.customViewList()) != null ? ref1.querySelector(`.leaf-item[data-id='${ctx.viewId}']`) : void 0;
          if (!li) {
            await app.loadCustomViews();
            li = (ref2 = app.el.customViewList()) != null ? ref2.querySelector(`.leaf-item[data-id='${ctx.viewId}']`) : void 0;
          }
          if (li != null) {
            li.click();
          }
          await waitUntil((function() {
            var ref3;
            return ((ref3 = app._currentCustomView) != null ? ref3.id : void 0) === ctx.viewId;
          }));
        }
        return;
      }
      if (ctx.spaceId) {
        if (((ref3 = app._currentSpace) != null ? ref3.id : void 0) !== ctx.spaceId) {
          sp = (app._allSpaces || []).find(function(s) {
            return s.id === ctx.spaceId;
          });
          if (!sp) {
            await app.loadSpaces();
            sp = (app._allSpaces || []).find(function(s) {
              return s.id === ctx.spaceId;
            });
          }
          if (sp) {
            app.selectSpace(sp);
          }
          return (await waitUntil((function() {
            var ref4;
            return ((ref4 = app._currentSpace) != null ? ref4.id : void 0) === ctx.spaceId;
          })));
        }
      }
    },
    _refreshAfterApply: async function(app, context) {
      var ref, ref1;
      if (!app) {
        return;
      }
      if (context != null ? context.viewId : void 0) {
        if (((ref = app._currentCustomView) != null ? ref.yaml : void 0) != null) {
          return app._renderCustomViewPreview(app._currentCustomView.yaml);
        }
      } else {
        if (((ref1 = app._activeDataView) != null ? ref1.load : void 0) != null) {
          return (await app._activeDataView.load());
        }
      }
    },
    _applyAction: async function(app, direction) {
      var action, plan, stackFrom, stackTo, verdict;
      stackFrom = direction === 'undo' ? this._undoStack : this._redoStack;
      stackTo = direction === 'undo' ? this._redoStack : this._undoStack;
      if (!(stackFrom.length > 0)) {
        return false;
      }
      action = stackFrom[stackFrom.length - 1];
      await this._navigateToContext(app, action.context);
      plan = this._buildPlan(action, direction);
      verdict = (await this._verifyPlan(plan));
      if (!verdict.ok) {
        action.blockedReason = verdict.message;
        await this.refreshUI(app);
        return false;
      }
      await this._executePlan(plan);
      action.blockedReason = null;
      stackFrom.pop();
      stackTo.push(action);
      await this._refreshAfterApply(app, action.context);
      await this.refreshUI(app);
      return true;
    },
    undo: async function(app) {
      var e;
      try {
        return (await this._applyAction(app, 'undo'));
      } catch (error) {
        e = error;
        console.error('undo failed', e);
        await this.refreshUI(app);
        return false;
      }
    },
    redo: async function(app) {
      var e;
      try {
        return (await this._applyAction(app, 'redo'));
      } catch (error) {
        e = error;
        console.error('redo failed', e);
        await this.refreshUI(app);
        return false;
      }
    },
    peekUndoStatus: async function() {
      var action, plan, verdict;
      if (!(this._undoStack.length > 0)) {
        return {
          available: false,
          blocked: false,
          message: ''
        };
      }
      action = this._undoStack[this._undoStack.length - 1];
      plan = this._buildPlan(action, 'undo');
      verdict = (await this._verifyPlan(plan));
      return {
        available: true,
        blocked: !verdict.ok,
        message: verdict.ok ? '' : verdict.message
      };
    },
    _isEditableTarget: function(target) {
      var tag;
      if (!target) {
        return false;
      }
      tag = (target.tagName || '').toUpperCase();
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
        return true;
      }
      if (target.isContentEditable) {
        return true;
      }
      if (typeof target.closest === "function" ? target.closest('.CodeMirror') : void 0) {
        return true;
      }
      return false;
    },
    bindGlobalShortcuts: function(app) {
      if (this._keyboardBound) {
        return;
      }
      this._keyboardBound = true;
      return document.addEventListener('keydown', (e) => {
        var isRedo, isUndo, key, mod;
        if (this._isEditableTarget(e.target)) {
          return;
        }
        mod = e.ctrlKey || e.metaKey;
        if (!mod) {
          return;
        }
        key = String(e.key || '').toLowerCase();
        isUndo = key === 'z' && !e.shiftKey;
        isRedo = key === 'y' || (key === 'z' && e.shiftKey);
        if (!(isUndo || isRedo)) {
          return;
        }
        e.preventDefault();
        e.stopPropagation();
        if (isUndo) {
          return this.undo(app);
        } else {
          return this.redo(app);
        }
      });
    },
    refreshUI: async function(app) {
      var base, base1, redoBtn, status, undoBtn;
      if (!app) {
        return;
      }
      undoBtn = typeof (base = app.el).undoBtn === "function" ? base.undoBtn() : void 0;
      redoBtn = typeof (base1 = app.el).redoBtn === "function" ? base1.redoBtn() : void 0;
      if (undoBtn) {
        undoBtn.classList.remove('toolbar-btn--blocked');
        undoBtn.disabled = true;
        undoBtn.title = 'Annuler';
        if (this._undoStack.length > 0) {
          status = (await this.peekUndoStatus());
          undoBtn.disabled = status.blocked;
          if (status.blocked) {
            undoBtn.classList.add('toolbar-btn--blocked');
            undoBtn.title = `Annulation bloquée : ${status.message}`;
          } else {
            undoBtn.title = 'Annuler (Ctrl/Cmd+Z)';
          }
        }
      }
      if (redoBtn) {
        redoBtn.disabled = this._redoStack.length === 0;
        return redoBtn.title = this._redoStack.length > 0 ? 'Rétablir (Ctrl/Cmd+Shift+Z)' : 'Rétablir';
      }
    }
  };

}).call(this);
