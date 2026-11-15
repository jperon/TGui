(function() {
  // app_data_helpers.coffee — space/data toolbar/hash helpers extracted from app.coffee
  window.AppDataHelpers = {
    loadAll: function(app) {
      return Promise.all([app.loadSpaces(), app.loadPages(), app.loadDataViews()]).then(function() {
        return app._restoreFromHash();
      });
    },
    restoreFromHash: function(app) {
      var cvItems, dvItems, hash, i, j, len, len1, li, m, results, results1, sp, spaceId, ul, viewId;
      hash = window.location.hash;
      if (m = hash.match(/^#space\/(.+)$/)) {
        spaceId = m[1];
        sp = (app._allSpaces || []).find(function(s) {
          return s.id === spaceId;
        });
        if (sp) {
          return app.selectSpace(sp);
        }
      } else if (m = hash.match(/^#page\/(.+)$/)) {
        viewId = m[1];
        ul = app.el.pageList();
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
      } else if (m = hash.match(/^#view\/(.+)$/)) {
        viewId = m[1];
        ul = app.el.dataViewList();
        dvItems = ul.querySelectorAll('li');
        results1 = [];
        for (j = 0, len1 = dvItems.length; j < len1; j++) {
          li = dvItems[j];
          if (li.dataset.id === viewId) {
            li.click();
            break;
          } else {
            results1.push(void 0);
          }
        }
        return results1;
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
      ref = app.el.pageList().querySelectorAll('li');
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
      // Toolbar visibility for Spaces
      app.el.fieldsBtn().classList.remove('hidden');
      app.el.deleteRowsBtn().classList.remove('hidden');
      app.el.undoBtn().classList.remove('hidden');
      app.el.redoBtn().classList.remove('hidden');
      app.el.formulaFilterInput().classList.remove('hidden');
      app.el.renameSpaceBtn().title = app._t('ui.toolbar.renameSpace');
      app.el.deleteSpaceBtn().title = app._t('ui.toolbar.deleteSpace');
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
      var container, input, ref, ref1, ref2, relations;
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
        // Menu « Trier / Filtrer » : un seul module pour la grille principale et
        // les widgets de page (portée `space:<id>` ici).
        if ((ref1 = window.ViewPresetsMenu) != null) {
          ref1.attach(input.parentNode, {
            getDataView: function() {
              return app._activeDataView;
            },
            scope: `space:${space.id}`,
            spaceId: space.id,
            filterInput: input
          });
        }
      }
      return (ref2 = window.AppUndoHelpers) != null ? typeof ref2.refreshUI === "function" ? ref2.refreshUI(app) : void 0 : void 0;
    },
    bindDataToolbar: function(app) {
      var ref, ref1, ref2, ref3, ref4;
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
      if ((ref3 = window.AppUndoHelpers) != null) {
        if (typeof ref3.refreshUI === "function") {
          ref3.refreshUI(app);
        }
      }
      app.el.renameSpaceBtn().addEventListener('click', async function() {
        var activeLi, newName, view, viewId;
        if (app._currentSpace) {
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
        } else {
          // Handle Data View config
          // We find currently active data view in sidebar
          activeLi = app.el.dataViewList().querySelector('li.active');
          if (activeLi) {
            viewId = activeLi.dataset.id;
            view = (app._allDataViews || []).find(function(v) {
              return v.id === viewId;
            });
            if (view) {
              return app._openDataViewConfigModal(view);
            }
          }
        }
      });
      app.el.deleteSpaceBtn().addEventListener('click', async function() {
        var activeLi, name, view, viewId;
        if (app._currentSpace) {
          name = app._currentSpace.name;
          if (!(await tdbConfirm(app._t('ui.confirms.deleteSpace', {name})))) {
            return;
          }
          return Spaces.delete(app._currentSpace.id).then(function() {
            var ref4, ref5;
            app._currentSpace = null;
            if ((ref4 = app._activeDataView) != null) {
              if (typeof ref4.unmount === "function") {
                ref4.unmount();
              }
            }
            app._activeDataView = null;
            app.el.dataToolbar().classList.add('hidden');
            app.el.fieldsPanel().classList.add('hidden');
            app.el.fieldsBtn().classList.remove('active');
            app.el.welcome().classList.remove('hidden');
            app._loadAll();
            return (ref5 = window.AppUndoHelpers) != null ? typeof ref5.refreshUI === "function" ? ref5.refreshUI(app) : void 0 : void 0;
          }).catch(function(err) {
            return tdbAlert(app._err(err), 'error');
          });
        } else {
          // Handle Data View deletion
          activeLi = app.el.dataViewList().querySelector('li.active');
          if (activeLi) {
            viewId = activeLi.dataset.id;
            view = (app._allDataViews || []).find(function(v) {
              return v.id === viewId;
            });
            if (!view) {
              return;
            }
            if (!(await tdbConfirm(`Supprimer la vue '${view.name}' ?`))) {
              return;
            }
            return DataViews.delete(viewId).then(function() {
              app.el.dataToolbar().classList.add('hidden');
              app.el.welcome().classList.remove('hidden');
              return app._loadAll();
            }).catch(function(err) {
              return tdbAlert(app._err(err), 'error');
            });
          }
        }
      });
      return (ref4 = window.AppUndoHelpers) != null ? typeof ref4.refreshUI === "function" ? ref4.refreshUI(app) : void 0 : void 0;
    },
    loadDataViews: function(app) {
      return DataViews.list().then(function(views) {
        app._allDataViews = views;
        return app.renderDataViewList(views);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderDataViewList: function(app, views) {
      var i, len, li, results, sorted, ul, view;
      ul = app.el.dataViewList();
      ul.innerHTML = '';
      sorted = [...views].sort(function(a, b) {
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
      });
      results = [];
      for (i = 0, len = sorted.length; i < len; i++) {
        view = sorted[i];
        li = document.createElement('li');
        li.textContent = view.name;
        li.dataset.id = view.id;
        (function(view) {
          return li.addEventListener('click', function() {
            return app.selectDataView(view);
          });
        })(view);
        results.push(ul.appendChild(li));
      }
      return results;
    },
    selectDataView: function(app, view) {
      var i, j, l, len, len1, len2, li, ref, ref1, ref2, ref3;
      history.replaceState(null, '', `#view/${view.id}`);
      ref = app.el.pageList().querySelectorAll('li');
      // Deactivate other sections
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = app.el.spaceList().querySelectorAll('li');
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.remove('active');
      }
      ref2 = app.el.dataViewList().querySelectorAll('li');
      for (l = 0, len2 = ref2.length; l < len2; l++) {
        li = ref2[l];
        li.classList.toggle('active', li.dataset.id === view.id);
      }
      app._currentSpace = null;
      app._currentCustomView = null;
      if ((ref3 = app._activeCustomView) != null) {
        if (typeof ref3.unmount === "function") {
          ref3.unmount();
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
      // Toolbar visibility for Data Views
      app.el.fieldsBtn().classList.add('hidden');
      app.el.deleteRowsBtn().classList.add('hidden');
      app.el.undoBtn().classList.add('hidden');
      app.el.redoBtn().classList.add('hidden');
      app.el.formulaFilterInput().classList.add('hidden');
      app.el.renameSpaceBtn().title = "Configurer la vue";
      app.el.deleteSpaceBtn().title = "Supprimer la vue";
      app.el.dataTitle().textContent = view.name;
      return app._mountDataViewFromView(view);
    },
    mountDataViewFromView: function(app, view) {
      var container, ref;
      if ((ref = app._activeDataView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container = app.el.gridContainer();
      
      // We need to build fake fields from the execution result or config
      // For now, we'll execute a dry run or use the config to get columns
      return DataViews.execute(view.id, 1, 0).then((data) => {
        var cols, fakeSpace, keys;
        if (!(data.length > 0)) {
          return;
        }
        keys = Object.keys(data[0]).filter(function(k) {
          return k !== 'id';
        });
        cols = keys.map(function(k) {
          return {
            name: k,
            fieldType: 'String' // fallback to String
          };
        });
        
        // Fake space object for DataView class
        fakeSpace = {
          id: `view_${view.id}`,
          name: view.name,
          fields: cols,
          isView: true,
          viewId: view.id
        };
        app._activeDataView = new DataView(container, fakeSpace, null, [], {
          readOnly: true
        });
        return app._activeDataView.mount();
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    }
  };

}).call(this);
