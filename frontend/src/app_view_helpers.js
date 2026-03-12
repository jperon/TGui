(function() {
  // app_view_helpers.coffee — custom views and YAML editor helpers extracted from app.coffee
  window.AppViewHelpers = {
    loadCustomViews: function(app) {
      return GQL.query(app._listCustomViewsQuery).then(function(data) {
        return app.renderCustomViewList(data.customViews);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderCustomViewList: function(app, views) {
      var base, curr, cv, dictName, i, j, len, len1, parts, ref, ref1, renderTree, tree, ul;
      ul = app.el.customViewList();
      ul.innerHTML = '';
      tree = {
        items: [],
        folders: {}
      };
      ref = views || [];
      for (i = 0, len = ref.length; i < len; i++) {
        cv = ref[i];
        parts = cv.name.split('/');
        curr = tree;
        ref1 = parts.slice(0, -1);
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          dictName = ref1[j];
          if ((base = curr.folders)[dictName] == null) {
            base[dictName] = {
              items: [],
              folders: {}
            };
          }
          curr = curr.folders[dictName];
        }
        curr.items.push({
          cv: cv,
          shortName: parts[parts.length - 1]
        });
      }
      renderTree = function(node, containerEl, pathStr = "") {
        var fName, fNode, folderLi, folderNames, fullPath, header, icon, item, k, l, len2, len3, li, lsKey, results1, sortedItems, subUl;
        folderNames = Object.keys(node.folders).sort(function(a, b) {
          return a.toLowerCase().localeCompare(b.toLowerCase());
        });
        for (k = 0, len2 = folderNames.length; k < len2; k++) {
          fName = folderNames[k];
          fNode = node.folders[fName];
          fullPath = pathStr ? `${pathStr}/${fName}` : fName;
          folderLi = document.createElement('li');
          folderLi.className = 'folder-item';
          header = document.createElement('div');
          header.className = 'folder-header';
          icon = document.createElement('span');
          icon.className = 'folder-toggle-icon';
          icon.textContent = '▾';
          header.appendChild(icon);
          header.appendChild(document.createTextNode(` ${fName}`));
          folderLi.appendChild(header);
          subUl = document.createElement('ul');
          subUl.className = 'folder-children';
          folderLi.appendChild(subUl);
          lsKey = `tdb_folder_view_${fullPath}`;
          if (localStorage.getItem(lsKey) === 'true') {
            folderLi.classList.add('collapsed');
          }
          header.addEventListener('click', function(e) {
            var isCollapsed;
            e.stopPropagation();
            isCollapsed = folderLi.classList.toggle('collapsed');
            return localStorage.setItem(lsKey, isCollapsed ? 'true' : 'false');
          });
          renderTree(fNode, subUl, fullPath);
          containerEl.appendChild(folderLi);
        }
        sortedItems = node.items.sort(function(a, b) {
          return a.shortName.toLowerCase().localeCompare(b.shortName.toLowerCase());
        });
        results1 = [];
        for (l = 0, len3 = sortedItems.length; l < len3; l++) {
          item = sortedItems[l];
          li = document.createElement('li');
          li.className = 'leaf-item';
          li.textContent = item.shortName;
          li.dataset.id = item.cv.id;
          li.title = item.cv.name;
          (function(cv) {
            return li.addEventListener('click', function(e) {
              e.stopPropagation();
              return app.selectCustomView(cv);
            });
          })(item.cv);
          results1.push(containerEl.appendChild(li));
        }
        return results1;
      };
      return renderTree(tree, ul);
    },
    selectCustomView: function(app, cv) {
      var i, j, len, len1, li, panel, parent, ref, ref1, ref2, ref3, ref4;
      history.replaceState(null, '', `#view/${cv.id}`);
      app._currentCustomView = cv;
      ref = app.el.spaceList().querySelectorAll('li');
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = app.el.customViewList().querySelectorAll('.leaf-item');
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.toggle('active', li.dataset.id === cv.id);
        if (li.dataset.id === cv.id) {
          parent = li.parentElement;
          while (parent && parent.id !== 'custom-view-list') {
            if (parent.tagName === 'LI' && parent.classList.contains('folder-item')) {
              parent.classList.remove('collapsed');
            }
            parent = parent.parentElement;
          }
        }
      }
      app._currentSpace = null;
      if ((ref2 = app._activeDataView) != null) {
        if (typeof ref2.unmount === "function") {
          ref2.unmount();
        }
      }
      app._activeDataView = null;
      app.el.dataToolbar().classList.add('hidden');
      app.el.fieldsPanel().classList.add('hidden');
      app.el.gridContainer().classList.add('hidden');
      app.el.welcome().classList.add('hidden');
      app.el.adminPanel().classList.add('hidden');
      app.el.contentRow().classList.remove('hidden');
      panel = app.el.yamlEditorPanel();
      panel.classList.remove('hidden');
      app.el.yamlViewName().textContent = cv.name;
      if ((ref3 = cv.yaml) != null ? ref3.trim() : void 0) {
        app._renderCustomViewPreview(cv.yaml);
      } else {
        app._openYamlModal();
      }
      return (ref4 = window.AppUndoHelpers) != null ? typeof ref4.refreshUI === "function" ? ref4.refreshUI(app) : void 0 : void 0;
    },
    renderCustomViewPreview: function(app, yamlText) {
      var container, ref;
      container = app.el.customViewContainer();
      if ((ref = app._activeCustomView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container.innerHTML = '';
      container.classList.remove('hidden');
      app._activeCustomView = new CustomView(container, yamlText, app._allSpaces);
      return app._activeCustomView.mount();
    },
    bindYamlEditor: function(app) {
      app.el.yamlEditBtn().addEventListener('click', function() {
        return app._openYamlModal();
      });
      app.el.yamlDeleteBtn().addEventListener('click', async function() {
        var cv;
        cv = app._currentCustomView;
        if (!cv) {
          return;
        }
        if (!(await tdbConfirm(app._t('ui.confirms.deleteView', {
          name: cv.name
        })))) {
          return;
        }
        return GQL.mutate(app._deleteCustomViewMutation, {
          id: cv.id
        }).then(function() {
          var ref;
          app._currentCustomView = null;
          if ((ref = app._activeCustomView) != null) {
            if (typeof ref.unmount === "function") {
              ref.unmount();
            }
          }
          app._activeCustomView = null;
          app.el.yamlEditorPanel().classList.add('hidden');
          app.el.customViewContainer().classList.add('hidden');
          app.el.welcome().classList.remove('hidden');
          return app.loadCustomViews();
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      app.el.yamlModalSaveBtn().addEventListener('click', function() {
        var cv, yaml;
        cv = app._currentCustomView;
        if (!cv) {
          return;
        }
        yaml = app._cmYaml.getValue();
        return GQL.mutate(app._updateCustomViewMutation, {
          id: cv.id,
          input: {yaml}
        }).then(function(data) {
          app._currentCustomView = data.updateCustomView;
          app.el.yamlModal().classList.add('hidden');
          app._renderCustomViewPreview(yaml);
          return app.loadCustomViews();
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      app.el.yamlModalCloseBtn().addEventListener('click', function() {
        return app.el.yamlModal().classList.add('hidden');
      });
      return app.el.yamlModalPreviewBtn().addEventListener('click', function() {
        if (!app._cmYaml) {
          return;
        }
        return app._renderCustomViewPreview(app._cmYaml.getValue());
      });
    },
    openYamlModal: function(app) {
      var cv;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      app.el.yamlModalTitle().textContent = cv.name;
      app.el.yamlModal().classList.remove('hidden');
      if (!app._cmYaml) {
        app._cmYaml = CodeMirror(document.getElementById('yaml-cm-editor'), {
          mode: 'yaml',
          theme: 'monokai',
          lineNumbers: true,
          lineWrapping: true,
          tabSize: 2,
          indentWithTabs: false
        });
        app._cmYaml.on('change', function(cm, change) {
          var e, ref, ref1, ref2;
          if (!app._yamlValidMsg) {
            app._yamlValidMsg = document.getElementById('yaml-validation-msg');
          }
          if (change.origin === 'setValue') {
            if ((ref = app._yamlValidMsg) != null) {
              ref.classList.add('hidden');
            }
            return;
          }
          if ((ref1 = app._yamlBuilder) != null) {
            ref1.reloadFromYaml(cm.getValue());
          }
          try {
            jsyaml.load(cm.getValue());
            return (ref2 = app._yamlValidMsg) != null ? ref2.classList.add('hidden') : void 0;
          } catch (error) {
            e = error;
            if (app._yamlValidMsg) {
              app._yamlValidMsg.textContent = `YAML invalide : ${e.message}`;
              return app._yamlValidMsg.classList.remove('hidden');
            }
          }
        });
      }
      app._cmYaml.setValue(cv.yaml || '');
      setTimeout((function() {
        return app._cmYaml.refresh();
      }), 10);
      return app._loadAllRelations().then(function(relations) {
        app._yamlBuilder = new YamlBuilder({
          container: document.getElementById('schema-browser'),
          allSpaces: app._allSpaces,
          allRelations: relations,
          initialYaml: cv.yaml || '',
          onChange: function(yaml) {
            var ref;
            return (ref = app._cmYaml) != null ? ref.setValue(yaml) : void 0;
          }
        });
        return app._yamlBuilder.mount();
      });
    },
    loadAllRelations: function(app) {
      if (app._allRelations) {
        return Promise.resolve(app._allRelations);
      }
      return Promise.all(app._allSpaces.map(function(sp) {
        return Spaces.listRelations(sp.id);
      })).then(function(results) {
        app._allRelations = results.reduce((function(a, b) {
          return a.concat(b);
        }), []);
        return app._allRelations;
      });
    }
  };

}).call(this);
