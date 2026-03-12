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
      var ref;
      app.el.yamlEditBtn().addEventListener('click', function() {
        return app._openYamlModal();
      });
      if ((ref = app.el.yamlPluginsBtn()) != null) {
        ref.addEventListener('click', function() {
          return app._openWidgetPluginModal();
        });
      }
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
          var ref1;
          app._currentCustomView = null;
          if ((ref1 = app._activeCustomView) != null) {
            if (typeof ref1.unmount === "function") {
              ref1.unmount();
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
      var applyValidationLayout, cv, yamlPane;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      app.el.yamlModalTitle().textContent = cv.name;
      app.el.yamlModal().classList.remove('hidden');
      yamlPane = document.querySelector('.yaml-editor-pane');
      applyValidationLayout = function() {
        var hasError;
        if (!(yamlPane && app._yamlValidMsg)) {
          return;
        }
        hasError = !app._yamlValidMsg.classList.contains('hidden');
        return yamlPane.classList.toggle('has-validation-error', hasError);
      };
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
            applyValidationLayout();
            return;
          }
          if ((ref1 = app._yamlBuilder) != null) {
            ref1.reloadFromYaml(cm.getValue());
          }
          try {
            jsyaml.load(cm.getValue());
            if ((ref2 = app._yamlValidMsg) != null) {
              ref2.classList.add('hidden');
            }
            return applyValidationLayout();
          } catch (error) {
            e = error;
            if (app._yamlValidMsg) {
              app._yamlValidMsg.textContent = `YAML invalide : ${e.message}`;
              app._yamlValidMsg.classList.remove('hidden');
              return applyValidationLayout();
            }
          }
        });
      } else {
        if (app._yamlValidMsg == null) {
          app._yamlValidMsg = document.getElementById('yaml-validation-msg');
        }
        applyValidationLayout();
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
    },
    bindWidgetPlugins: function(app) {
      var ref, ref1, ref2, ref3, ref4, ref5;
      if ((ref = app.el.widgetPluginModalCloseBtn()) != null) {
        ref.addEventListener('click', function() {
          var ref1;
          return (ref1 = app.el.widgetPluginModal()) != null ? ref1.classList.add('hidden') : void 0;
        });
      }
      if ((ref1 = app.el.widgetPluginNewBtn()) != null) {
        ref1.addEventListener('click', function() {
          var defaults, ref2, ref3, ref4, ref5;
          defaults = window.AppViewHelpers._defaultWidgetPlugin();
          app._selectedWidgetPlugin = null;
          app.el.widgetPluginName().value = defaults.name;
          app.el.widgetPluginDescription().value = defaults.description;
          app.el.widgetPluginScriptLanguage().value = defaults.scriptLanguage;
          app.el.widgetPluginTemplateLanguage().value = defaults.templateLanguage;
          if ((ref2 = app._cmWidgetPluginScript) != null) {
            ref2.setOption('mode', defaults.scriptLanguage);
          }
          if ((ref3 = app._cmWidgetPluginTemplate) != null) {
            ref3.setOption('mode', defaults.templateLanguage);
          }
          if ((ref4 = app._cmWidgetPluginScript) != null) {
            ref4.setValue(defaults.scriptCode);
          }
          return (ref5 = app._cmWidgetPluginTemplate) != null ? ref5.setValue(defaults.templateCode) : void 0;
        });
      }
      if ((ref2 = app.el.widgetPluginSaveBtn()) != null) {
        ref2.addEventListener('click', function() {
          var input, mutation, name, vars;
          name = app.el.widgetPluginName().value.trim();
          if (!name) {
            return tdbAlert('Nom du plugin requis', 'error');
          }
          input = {
            name: name,
            description: app.el.widgetPluginDescription().value.trim(),
            scriptLanguage: app.el.widgetPluginScriptLanguage().value || 'coffeescript',
            templateLanguage: app.el.widgetPluginTemplateLanguage().value || 'pug',
            scriptCode: app._cmWidgetPluginScript ? app._cmWidgetPluginScript.getValue() : '',
            templateCode: app._cmWidgetPluginTemplate ? app._cmWidgetPluginTemplate.getValue() : ''
          };
          mutation = app._selectedWidgetPlugin ? app._updateWidgetPluginMutation : app._createWidgetPluginMutation;
          vars = app._selectedWidgetPlugin ? {
            id: app._selectedWidgetPlugin.id,
            input
          } : {input};
          return GQL.mutate(mutation, vars).then(function() {
            return window.AppViewHelpers._loadWidgetPlugins(app);
          }).catch(function(err) {
            return tdbAlert(app._err(err), 'error');
          });
        });
      }
      if ((ref3 = app.el.widgetPluginDeleteBtn()) != null) {
        ref3.addEventListener('click', async function() {
          var plugin;
          plugin = app._selectedWidgetPlugin;
          if (!plugin) {
            return;
          }
          if (!(await tdbConfirm(`Supprimer le plugin « ${plugin.name} » ?`))) {
            return;
          }
          return GQL.mutate(app._deleteWidgetPluginMutation, {
            id: plugin.id
          }).then(function() {
            app._selectedWidgetPlugin = null;
            return window.AppViewHelpers._loadWidgetPlugins(app);
          }).catch(function(err) {
            return tdbAlert(app._err(err), 'error');
          });
        });
      }
      if ((ref4 = app.el.widgetPluginScriptLanguage()) != null) {
        ref4.addEventListener('change', function() {
          var mode, ref5;
          mode = app.el.widgetPluginScriptLanguage().value || 'coffeescript';
          return (ref5 = app._cmWidgetPluginScript) != null ? ref5.setOption('mode', mode) : void 0;
        });
      }
      return (ref5 = app.el.widgetPluginTemplateLanguage()) != null ? ref5.addEventListener('change', function() {
        var mode, ref6;
        mode = app.el.widgetPluginTemplateLanguage().value || 'pug';
        return (ref6 = app._cmWidgetPluginTemplate) != null ? ref6.setOption('mode', mode) : void 0;
      }) : void 0;
    },
    _defaultWidgetPlugin: function() {
      return {
        name: '',
        description: '',
        scriptLanguage: 'coffeescript',
        templateLanguage: 'pug',
        templateCode: `div.plugin-root
  h3= params.title or 'Widget'
  .content Chargement…`,
        scriptCode: `module.exports = ({ gql, emitSelection, onInputSelection, render, params }) ->
  rows = []
  onInputSelection (selection) ->
    rows = selection?.rows or []
    emitSelection { rows }
  title = if params?.title then params.title else 'sans titre'
  render \"<div class='plugin-info'>Plugin prêt : ${title}</div>\"`
      };
    },
    _loadWidgetPlugins: function(app) {
      return GQL.query(app._listWidgetPluginsQuery).then(function(data) {
        var defaults, i, len, li, p, plugins, ref, ref1, ref2, ref3, ref4, ul;
        plugins = data.widgetPlugins || [];
        ul = app.el.widgetPluginList();
        ul.innerHTML = '';
        for (i = 0, len = plugins.length; i < len; i++) {
          p = plugins[i];
          li = document.createElement('li');
          li.className = 'leaf-item';
          li.textContent = p.name;
          li.title = p.description || p.name;
          li.classList.toggle('active', ((ref = app._selectedWidgetPlugin) != null ? ref.id : void 0) === p.id);
          (function(p) {
            return li.addEventListener('click', function() {
              var j, len1, n, ref1, ref2, ref3, ref4, ref5;
              app._selectedWidgetPlugin = p;
              app.el.widgetPluginName().value = p.name || '';
              app.el.widgetPluginDescription().value = p.description || '';
              app.el.widgetPluginScriptLanguage().value = p.scriptLanguage || 'coffeescript';
              app.el.widgetPluginTemplateLanguage().value = p.templateLanguage || 'pug';
              if ((ref1 = app._cmWidgetPluginScript) != null) {
                ref1.setOption('mode', app.el.widgetPluginScriptLanguage().value);
              }
              if ((ref2 = app._cmWidgetPluginTemplate) != null) {
                ref2.setOption('mode', app.el.widgetPluginTemplateLanguage().value);
              }
              if ((ref3 = app._cmWidgetPluginScript) != null) {
                ref3.setValue(p.scriptCode || '');
              }
              if ((ref4 = app._cmWidgetPluginTemplate) != null) {
                ref4.setValue(p.templateCode || '');
              }
              ref5 = ul.querySelectorAll('li');
              for (j = 0, len1 = ref5.length; j < len1; j++) {
                n = ref5[j];
                n.classList.remove('active');
              }
              return li.classList.add('active');
            });
          })(p);
          ul.appendChild(li);
        }
        if (!app._selectedWidgetPlugin && plugins.length === 0) {
          defaults = window.AppViewHelpers._defaultWidgetPlugin();
          app.el.widgetPluginName().value = defaults.name;
          app.el.widgetPluginDescription().value = defaults.description;
          app.el.widgetPluginScriptLanguage().value = defaults.scriptLanguage;
          app.el.widgetPluginTemplateLanguage().value = defaults.templateLanguage;
          if ((ref1 = app._cmWidgetPluginScript) != null) {
            ref1.setOption('mode', defaults.scriptLanguage);
          }
          if ((ref2 = app._cmWidgetPluginTemplate) != null) {
            ref2.setOption('mode', defaults.templateLanguage);
          }
          if ((ref3 = app._cmWidgetPluginScript) != null) {
            ref3.setValue(defaults.scriptCode);
          }
          return (ref4 = app._cmWidgetPluginTemplate) != null ? ref4.setValue(defaults.templateCode) : void 0;
        }
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    openWidgetPluginModal: function(app) {
      var ref;
      if ((ref = app.el.widgetPluginModal()) != null) {
        ref.classList.remove('hidden');
      }
      if (!app._cmWidgetPluginScript) {
        app._cmWidgetPluginScript = CodeMirror(app.el.widgetPluginScriptEditor(), {
          mode: app.el.widgetPluginScriptLanguage().value || 'coffeescript',
          theme: 'monokai',
          lineNumbers: true,
          lineWrapping: true,
          tabSize: 2,
          indentWithTabs: false
        });
      }
      if (!app._cmWidgetPluginTemplate) {
        app._cmWidgetPluginTemplate = CodeMirror(app.el.widgetPluginTemplateEditor(), {
          mode: app.el.widgetPluginTemplateLanguage().value || 'pug',
          theme: 'monokai',
          lineNumbers: true,
          lineWrapping: true,
          tabSize: 2,
          indentWithTabs: false
        });
      }
      setTimeout((function() {
        var ref1;
        return (ref1 = app._cmWidgetPluginScript) != null ? ref1.refresh() : void 0;
      }), 10);
      setTimeout((function() {
        var ref1;
        return (ref1 = app._cmWidgetPluginTemplate) != null ? ref1.refresh() : void 0;
      }), 10);
      app._selectedWidgetPlugin = null;
      return window.AppViewHelpers._loadWidgetPlugins(app);
    }
  };

}).call(this);
