(function() {
  // app_data_helpers.coffee — space/data toolbar/hash helpers extracted from app.coffee
  window.AppDataHelpers = {
    loadAll: function(app) {
      return Promise.all([app.loadSpaces(), app.loadCustomViews()]).then(function() {
        return app._restoreFromHash();
      });
    },
    restoreFromHash: function(app) {
      var cvItems, hash, i, len, li, m, results, sp, spaceId, ul, viewId;
      hash = window.location.hash;
      if (m = hash.match(/^#space\/(.+)$/)) {
        spaceId = m[1];
        sp = (app._allSpaces || []).find(function(s) {
          return s.id === spaceId;
        });
        if (sp) {
          return app.selectSpace(sp);
        }
      } else if (m = hash.match(/^#view\/(.+)$/)) {
        viewId = m[1];
        ul = app.el.customViewList();
        cvItems = ul.querySelectorAll('li');
        results = [];
        for (i = 0, len = cvItems.length; i < len; i++) {
          li = cvItems[i];
          if (li.dataset.id === viewId) {
            li.click();
            break;
          } else {
            results.push(void 0);
          }
        }
        return results;
      }
    },
    loadSpaces: function(app) {
      return Spaces.list().then(function(spaces) {
        app._allSpaces = spaces;
        return app.renderSpaceList(spaces);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderSpaceList: function(app, spaces) {
      var i, len, li, results, sortedSpaces, sp, ul;
      ul = app.el.spaceList();
      ul.innerHTML = '';
      sortedSpaces = [...spaces].sort(function(a, b) {
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
      });
      results = [];
      for (i = 0, len = sortedSpaces.length; i < len; i++) {
        sp = sortedSpaces[i];
        li = document.createElement('li');
        li.textContent = sp.name;
        li.dataset.id = sp.id;
        (function(sp) {
          return li.addEventListener('click', function() {
            return app.selectSpace(sp);
          });
        })(sp);
        results.push(ul.appendChild(li));
      }
      return results;
    },
    selectSpace: function(app, sp) {
      var i, j, len, len1, li, ref, ref1, ref2;
      history.replaceState(null, '', `#space/${sp.id}`);
      ref = app.el.customViewList().querySelectorAll('li');
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = app.el.spaceList().querySelectorAll('li');
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.toggle('active', li.dataset.id === sp.id);
      }
      app._currentCustomView = null;
      if ((ref2 = app._activeCustomView) != null) {
        if (typeof ref2.unmount === "function") {
          ref2.unmount();
        }
      }
      app._activeCustomView = null;
      app.el.fieldsPanel().classList.add('hidden');
      app.el.fieldsBtn().classList.remove('active');
      app.el.adminPanel().classList.add('hidden');
      app.el.dataToolbar().classList.remove('hidden');
      app.el.yamlEditorPanel().classList.add('hidden');
      app.el.customViewContainer().classList.add('hidden');
      app.el.gridContainer().classList.remove('hidden');
      app.el.welcome().classList.add('hidden');
      app.el.contentRow().classList.remove('hidden');
      return Spaces.getWithFields(sp.id).then(function(full) {
        var ref3;
        app._currentSpace = full;
        app.el.dataTitle().textContent = full.name;
        app._mountDataView(full);
        return (ref3 = window.AppUndoHelpers) != null ? typeof ref3.refreshUI === "function" ? ref3.refreshUI(app) : void 0 : void 0;
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    syncSpaceFields: function(app, space) {
      var ref, ref1;
      app._allSpaces = (app._allSpaces || []).map(function(s) {
        if (s.id === space.id) {
          return space;
        } else {
          return s;
        }
      });
      if (app._activeCustomView && ((ref = app._currentCustomView) != null ? (ref1 = ref.yaml) != null ? ref1.trim() : void 0 : void 0)) {
        return app._renderCustomViewPreview(app._currentCustomView.yaml);
      }
    },
    mountDataView: async function(app, space) {
      var container, input, ref, ref1, relations;
      if ((ref = app._activeDataView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container = app.el.gridContainer();
      relations = (await Spaces.listRelations(space.id));
      app._activeDataView = new DataView(container, space, null, relations, {
        onColumnFocus: function(colName) {
          return app._onGridColumnFocused(colName);
        }
      });
      app._activeDataView.mount();
      input = app.el.formulaFilterInput();
      if (input) {
        input.value = '';
        input.classList.remove('active');
      }
      return (ref1 = window.AppUndoHelpers) != null ? typeof ref1.refreshUI === "function" ? ref1.refreshUI(app) : void 0 : void 0;
    },
    bindDataToolbar: function(app) {
      var ref, ref1, ref2, ref3;
      if ((ref = window.AppUndoHelpers) != null) {
        if (typeof ref.bindGlobalShortcuts === "function") {
          ref.bindGlobalShortcuts(app);
        }
      }
      if ((ref1 = app.el.undoBtn()) != null) {
        ref1.addEventListener('click', function() {
          var ref2;
          return (ref2 = window.AppUndoHelpers) != null ? typeof ref2.undo === "function" ? ref2.undo(app) : void 0 : void 0;
        });
      }
      if ((ref2 = app.el.redoBtn()) != null) {
        ref2.addEventListener('click', function() {
          var ref3;
          return (ref3 = window.AppUndoHelpers) != null ? typeof ref3.redo === "function" ? ref3.redo(app) : void 0 : void 0;
        });
      }
      app.el.deleteRowsBtn().addEventListener('click', function() {
        var ref3, ref4;
        if ((ref3 = app._activeDataView) != null) {
          ref3.deleteSelected();
        }
        return (ref4 = window.AppUndoHelpers) != null ? typeof ref4.refreshUI === "function" ? ref4.refreshUI(app) : void 0 : void 0;
      });
      window.AppFieldsHelpers.bindFormulaFilter(app);
      app.el.deleteSpaceBtn().addEventListener('click', async function() {
        var name;
        if (!app._currentSpace) {
          return;
        }
        name = app._currentSpace.name;
        if (!(await tdbConfirm(app._t('ui.confirms.deleteSpace', {name})))) {
          return;
        }
        return Spaces.delete(app._currentSpace.id).then(function() {
          var ref3, ref4;
          app._currentSpace = null;
          if ((ref3 = app._activeDataView) != null) {
            if (typeof ref3.unmount === "function") {
              ref3.unmount();
            }
          }
          app._activeDataView = null;
          app.el.dataToolbar().classList.add('hidden');
          app.el.fieldsPanel().classList.add('hidden');
          app.el.fieldsBtn().classList.remove('active');
          app.el.welcome().classList.remove('hidden');
          app._loadAll();
          return (ref4 = window.AppUndoHelpers) != null ? typeof ref4.refreshUI === "function" ? ref4.refreshUI(app) : void 0 : void 0;
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      app.el.renameSpaceBtn().addEventListener('click', async function() {
        var newName;
        if (!app._currentSpace) {
          return;
        }
        newName = (await tdbPrompt(app._t('ui.prompts.renameSpace'), app._currentSpace.name));
        if (!((newName != null ? newName.trim() : void 0) && newName.trim() !== app._currentSpace.name)) {
          return;
        }
        return Spaces.update(app._currentSpace.id, newName.trim()).then(function(updated) {
          var li;
          app._currentSpace.name = updated.name;
          app.el.dataTitle().textContent = updated.name;
          li = app.el.spaceList().querySelector(`li[data-id='${updated.id}']`);
          if (li) {
            return li.textContent = updated.name;
          }
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      return (ref3 = window.AppUndoHelpers) != null ? typeof ref3.refreshUI === "function" ? ref3.refreshUI(app) : void 0 : void 0;
    }
  };

}).call(this);
