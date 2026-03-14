(function() {
  // app_view_helpers.coffee — custom views and YAML editor helpers extracted from app.coffee
  var hasProp = {}.hasOwnProperty;

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
      app.el.yamlAddWidgetBtn().addEventListener('click', function() {
        return window.AppViewHelpers._openAddWidgetModal(app);
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
      var applyValidationLayout, cv, ref, yamlPane;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      app.el.yamlModalTitle().textContent = cv.name;
      app.el.yamlModal().classList.remove('hidden');
      // Ajouter la palette d'insertion de layouts dans le header de la modale YAML
      this.setupLayoutPalette(app);
      // Configurer le listener global d'insertion de layouts
      if ((ref = window.CustomView) != null) {
        if (typeof ref.setupLayoutInsertion === "function") {
          ref.setupLayoutInsertion();
        }
      }
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
          var e, ref1, ref2, ref3;
          if (!app._yamlValidMsg) {
            app._yamlValidMsg = document.getElementById('yaml-validation-msg');
          }
          if (change.origin === 'setValue') {
            if ((ref1 = app._yamlValidMsg) != null) {
              ref1.classList.add('hidden');
            }
            applyValidationLayout();
            return;
          }
          if ((ref2 = app._yamlBuilder) != null) {
            ref2.reloadFromYaml(cm.getValue());
          }
          try {
            jsyaml.load(cm.getValue());
            if ((ref3 = app._yamlValidMsg) != null) {
              ref3.classList.add('hidden');
            }
            return applyValidationLayout();
          } catch (error1) {
            e = error1;
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
            var ref1;
            return (ref1 = app._cmYaml) != null ? ref1.setValue(yaml) : void 0;
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
    _pulseModalButton: function(btn) {
      if (!btn) {
        return;
      }
      btn.classList.remove('is-pressed');
      btn.classList.add('is-pressed');
      return setTimeout((function() {
        return btn.classList.remove('is-pressed');
      }), 120);
    },
    _markWidgetPluginDirty: function(app, pluginName) {
      if (!pluginName) {
        return;
      }
      app._widgetPluginDirty = true;
      if (app._widgetPluginDirtyNames == null) {
        app._widgetPluginDirtyNames = {};
      }
      return app._widgetPluginDirtyNames[pluginName] = true;
    },
    _collectWidgetTypesFromYaml: function(yamlText) {
      var e, parsed, types, walk;
      types = {};
      walk = function(node) {
        var _, child, i, len, nodeType, results1, val;
        if (node == null) {
          return;
        }
        if (Array.isArray(node)) {
          for (i = 0, len = node.length; i < len; i++) {
            child = node[i];
            walk(child);
          }
          return;
        }
        if (typeof node === 'object') {
          nodeType = node.type;
          if (typeof nodeType === 'string' && nodeType && nodeType !== 'aggregate') {
            types[nodeType] = true;
          }
          results1 = [];
          for (_ in node) {
            if (!hasProp.call(node, _)) continue;
            val = node[_];
            results1.push(walk(val));
          }
          return results1;
        }
      };
      try {
        parsed = jsyaml.load(yamlText || '');
        walk(parsed);
      } catch (error1) {
        e = error1;
        console.warn('collect plugin dependencies from yaml failed', e);
      }
      return types;
    },
    _refreshViewsDependingOnDirtyPlugins: function(app) {
      var dirtyNames, i, len, name, needsRefresh, ref, usedTypes;
      if (!app._widgetPluginDirty) {
        return;
      }
      if (!(app._activeCustomView && ((ref = app._currentCustomView) != null ? ref.yaml : void 0))) {
        return;
      }
      dirtyNames = Object.keys(app._widgetPluginDirtyNames || {});
      if (!(dirtyNames.length > 0)) {
        return;
      }
      usedTypes = window.AppViewHelpers._collectWidgetTypesFromYaml(app._currentCustomView.yaml);
      needsRefresh = false;
      for (i = 0, len = dirtyNames.length; i < len; i++) {
        name = dirtyNames[i];
        if (!usedTypes[name]) {
          continue;
        }
        needsRefresh = true;
        break;
      }
      if (needsRefresh) {
        return app._renderCustomViewPreview(app._currentCustomView.yaml);
      }
    },
    _closeWidgetPluginModal: function(app) {
      var ref;
      if ((ref = app.el.widgetPluginModal()) != null) {
        ref.classList.add('hidden');
      }
      window.AppViewHelpers._refreshViewsDependingOnDirtyPlugins(app);
      app._widgetPluginDirty = false;
      return app._widgetPluginDirtyNames = {};
    },
    bindWidgetPlugins: function(app) {
      var ref, ref1, ref2, ref3, ref4, ref5, ref6;
      if ((ref = app.el.widgetPluginModalCloseBtn()) != null) {
        ref.addEventListener('click', function(ev) {
          window.AppViewHelpers._pulseModalButton(ev.currentTarget);
          return window.AppViewHelpers._closeWidgetPluginModal(app);
        });
      }
      if ((ref1 = app.el.widgetPluginNewBtn()) != null) {
        ref1.addEventListener('click', function(ev) {
          var defaults, ref2, ref3, ref4, ref5, ref6;
          window.AppViewHelpers._pulseModalButton(ev.currentTarget);
          defaults = window.AppViewHelpers._defaultWidgetPlugin();
          app._selectedWidgetPlugin = null;
          if ((ref2 = app.el.widgetPluginSelect()) != null) {
            ref2.value = '';
          }
          app.el.widgetPluginName().value = defaults.name;
          app.el.widgetPluginDescription().value = defaults.description;
          app.el.widgetPluginScriptLanguage().value = defaults.scriptLanguage;
          app.el.widgetPluginTemplateLanguage().value = defaults.templateLanguage;
          if ((ref3 = app._cmWidgetPluginScript) != null) {
            ref3.setOption('mode', defaults.scriptLanguage);
          }
          if ((ref4 = app._cmWidgetPluginTemplate) != null) {
            ref4.setOption('mode', defaults.templateLanguage);
          }
          if ((ref5 = app._cmWidgetPluginScript) != null) {
            ref5.setValue(defaults.scriptCode);
          }
          return (ref6 = app._cmWidgetPluginTemplate) != null ? ref6.setValue(defaults.templateCode) : void 0;
        });
      }
      if ((ref2 = app.el.widgetPluginSaveBtn()) != null) {
        ref2.addEventListener('click', function(ev) {
          var input, mutation, name, previousName, ref3, vars;
          window.AppViewHelpers._pulseModalButton(ev.currentTarget);
          name = app.el.widgetPluginName().value.trim();
          if (!name) {
            return tdbAlert('Nom du plugin requis', 'error');
          }
          previousName = (ref3 = app._selectedWidgetPlugin) != null ? ref3.name : void 0;
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
          return GQL.mutate(mutation, vars).then(function(data) {
            var saved;
            saved = data.updateWidgetPlugin || data.createWidgetPlugin || null;
            window.AppViewHelpers._markWidgetPluginDirty(app, previousName);
            window.AppViewHelpers._markWidgetPluginDirty(app, saved != null ? saved.name : void 0);
            if (saved) {
              app._selectedWidgetPlugin = saved;
            }
            return window.AppViewHelpers._loadWidgetPlugins(app, saved != null ? saved.id : void 0);
          }).catch(function(err) {
            return tdbAlert(app._err(err), 'error');
          });
        });
      }
      if ((ref3 = app.el.widgetPluginDeleteBtn()) != null) {
        ref3.addEventListener('click', async function(ev) {
          var plugin;
          window.AppViewHelpers._pulseModalButton(ev.currentTarget);
          plugin = app._selectedWidgetPlugin;
          if (!plugin) {
            return tdbAlert('Sélectionnez un plugin à supprimer', 'error');
          }
          if (!(await tdbConfirm(`Supprimer le plugin « ${plugin.name} » ?`))) {
            return;
          }
          return GQL.mutate(app._deleteWidgetPluginMutation, {
            id: plugin.id
          }).then(function() {
            window.AppViewHelpers._markWidgetPluginDirty(app, plugin.name);
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
      if ((ref5 = app.el.widgetPluginTemplateLanguage()) != null) {
        ref5.addEventListener('change', function() {
          var mode, ref6;
          mode = app.el.widgetPluginTemplateLanguage().value || 'pug';
          return (ref6 = app._cmWidgetPluginTemplate) != null ? ref6.setOption('mode', mode) : void 0;
        });
      }
      return (ref6 = app.el.widgetPluginSelect()) != null ? ref6.addEventListener('change', function() {
        var id, plugin, ref10, ref7, ref8, ref9;
        id = app.el.widgetPluginSelect().value;
        if (!id) {
          return;
        }
        plugin = (app._widgetPluginCache || []).find(function(p) {
          return p.id === id;
        });
        if (!plugin) {
          return;
        }
        app._selectedWidgetPlugin = plugin;
        app.el.widgetPluginName().value = plugin.name || '';
        app.el.widgetPluginDescription().value = plugin.description || '';
        app.el.widgetPluginScriptLanguage().value = plugin.scriptLanguage || 'coffeescript';
        app.el.widgetPluginTemplateLanguage().value = plugin.templateLanguage || 'pug';
        if ((ref7 = app._cmWidgetPluginScript) != null) {
          ref7.setOption('mode', app.el.widgetPluginScriptLanguage().value);
        }
        if ((ref8 = app._cmWidgetPluginTemplate) != null) {
          ref8.setOption('mode', app.el.widgetPluginTemplateLanguage().value);
        }
        if ((ref9 = app._cmWidgetPluginScript) != null) {
          ref9.setValue(plugin.scriptCode || '');
        }
        return (ref10 = app._cmWidgetPluginTemplate) != null ? ref10.setValue(plugin.templateCode || '') : void 0;
      }) : void 0;
    },
    _defaultWidgetPlugin: function() {
      return {
        name: '',
        description: '',
        scriptLanguage: 'coffeescript',
        templateLanguage: 'pug',
        templateCode: `div.plugin-root
  h3= params.title || 'Widget'
  .content Chargement…`,
        scriptCode: `module.exports = ({ gql, emitSelection, onInputSelection, render, params }) ->
  rows = []
  onInputSelection (selection) ->
    rows = selection?.rows or []
    emitSelection { rows }
  title = if params?.title then params.title else 'sans titre'
  render \"<div class='plugin-info'>Plugin prêt : \#{title}</div>\"`
      };
    },
    _loadWidgetPlugins: function(app, preferredId = null) {
      return GQL.query(app._listWidgetPluginsQuery).then(function(data) {
        var defaults, emptyOpt, firstPlugin, i, len, opt, p, plugins, ref, ref1, ref2, ref3, ref4, sel, selectPlugin, selected, wantedId;
        plugins = data.widgetPlugins || [];
        app._widgetPluginCache = plugins;
        sel = app.el.widgetPluginSelect();
        if (!sel) {
          tdbAlert('UI plugins indisponible dans cette page. Rechargez la page (Ctrl+F5).', 'error');
          return;
        }
        sel.innerHTML = '';
        selectPlugin = function(p) {
          var ref, ref1, ref2, ref3;
          app._selectedWidgetPlugin = p;
          if (p != null ? p.id : void 0) {
            sel.value = p.id;
          }
          app.el.widgetPluginName().value = p.name || '';
          app.el.widgetPluginDescription().value = p.description || '';
          app.el.widgetPluginScriptLanguage().value = p.scriptLanguage || 'coffeescript';
          app.el.widgetPluginTemplateLanguage().value = p.templateLanguage || 'pug';
          if ((ref = app._cmWidgetPluginScript) != null) {
            ref.setOption('mode', app.el.widgetPluginScriptLanguage().value);
          }
          if ((ref1 = app._cmWidgetPluginTemplate) != null) {
            ref1.setOption('mode', app.el.widgetPluginTemplateLanguage().value);
          }
          if ((ref2 = app._cmWidgetPluginScript) != null) {
            ref2.setValue(p.scriptCode || '');
          }
          return (ref3 = app._cmWidgetPluginTemplate) != null ? ref3.setValue(p.templateCode || '') : void 0;
        };
        wantedId = preferredId || ((ref = app._selectedWidgetPlugin) != null ? ref.id : void 0);
        firstPlugin = null;
        for (i = 0, len = plugins.length; i < len; i++) {
          p = plugins[i];
          if (firstPlugin == null) {
            firstPlugin = p;
          }
          opt = document.createElement('option');
          opt.value = p.id;
          opt.textContent = p.name;
          opt.title = p.description || p.name;
          sel.appendChild(opt);
        }
        if (plugins.length > 0) {
          selected = plugins.find(function(p) {
            return p.id === wantedId;
          }) || firstPlugin;
          if (selected) {
            return selectPlugin(selected);
          }
        } else {
          app._selectedWidgetPlugin = null;
          emptyOpt = document.createElement('option');
          emptyOpt.value = '';
          emptyOpt.textContent = '— Aucun plugin —';
          sel.appendChild(emptyOpt);
          sel.value = '';
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
    _ensureWidgetPluginEditorsSplit: function(app) {
      var base, base1, base2, base3, base4, ensureLabel, i, j, langRow, len, len1, oldRow, pane, ref, ref1, results1, root, row, scriptCol, scriptColCurrent, scriptEl, scriptLabel, scriptLangLabel, scriptLangSel, tplCol, tplColCurrent, tplEl, tplLabel, tplLangLabel, tplLangSel;
      root = typeof (base = app.el).widgetPluginModal === "function" ? base.widgetPluginModal() : void 0;
      if (!root) {
        return;
      }
      tplEl = typeof (base1 = app.el).widgetPluginTemplateEditor === "function" ? base1.widgetPluginTemplateEditor() : void 0;
      scriptEl = typeof (base2 = app.el).widgetPluginScriptEditor === "function" ? base2.widgetPluginScriptEditor() : void 0;
      if (!(tplEl && scriptEl)) {
        return;
      }
      tplLangSel = typeof (base3 = app.el).widgetPluginTemplateLanguage === "function" ? base3.widgetPluginTemplateLanguage() : void 0;
      scriptLangSel = typeof (base4 = app.el).widgetPluginScriptLanguage === "function" ? base4.widgetPluginScriptLanguage() : void 0;
      row = root.querySelector('.widget-plugin-editors-row');
      tplColCurrent = tplEl.closest('.widget-plugin-editor-col');
      scriptColCurrent = scriptEl.closest('.widget-plugin-editor-col');
      if (row && row.contains(tplEl) && row.contains(scriptEl) && tplColCurrent && scriptColCurrent && tplColCurrent !== scriptColCurrent && tplColCurrent.parentElement === row && scriptColCurrent.parentElement === row) {
        return;
      }
      pane = tplEl.closest('.yaml-editor-pane') || scriptEl.closest('.yaml-editor-pane');
      if (!pane) {
        return;
      }
      ref = pane.querySelectorAll('.widget-plugin-editors-row');
      for (i = 0, len = ref.length; i < len; i++) {
        oldRow = ref[i];
        oldRow.remove();
      }
      tplLabel = tplEl.previousElementSibling;
      scriptLabel = scriptEl.previousElementSibling;
      tplLangLabel = root.querySelector("label[for='widget-plugin-template-language']");
      scriptLangLabel = root.querySelector("label[for='widget-plugin-script-language']");
      ensureLabel = function(lbl, txt, forId) {
        var n;
        if (lbl) {
          return lbl;
        }
        n = document.createElement('label');
        n.className = 'formula-hint';
        n.htmlFor = forId;
        n.textContent = txt;
        return n;
      };
      tplLangLabel = ensureLabel(tplLangLabel, 'Template language', 'widget-plugin-template-language');
      scriptLangLabel = ensureLabel(scriptLangLabel, 'Script language', 'widget-plugin-script-language');
      if (!tplLabel) {
        tplLabel = document.createElement('label');
        tplLabel.className = 'formula-hint';
        tplLabel.textContent = 'Template';
      }
      if (!scriptLabel) {
        scriptLabel = document.createElement('label');
        scriptLabel.className = 'formula-hint';
        scriptLabel.textContent = 'Script';
      }
      tplEl.style.height = '';
      scriptEl.style.height = '';
      tplEl.style.flex = '1';
      scriptEl.style.flex = '1';
      row = document.createElement('div');
      row.className = 'widget-plugin-editors-row';
      tplCol = document.createElement('div');
      tplCol.className = 'widget-plugin-editor-col';
      if (tplLangSel && tplLangLabel) {
        tplCol.appendChild(tplLangLabel);
      }
      if (tplLangSel) {
        tplCol.appendChild(tplLangSel);
      }
      if (tplLabel) {
        tplCol.appendChild(tplLabel);
      }
      tplCol.appendChild(tplEl);
      scriptCol = document.createElement('div');
      scriptCol.className = 'widget-plugin-editor-col';
      if (scriptLangSel && scriptLangLabel) {
        scriptCol.appendChild(scriptLangLabel);
      }
      if (scriptLangSel) {
        scriptCol.appendChild(scriptLangSel);
      }
      if (scriptLabel) {
        scriptCol.appendChild(scriptLabel);
      }
      scriptCol.appendChild(scriptEl);
      row.appendChild(tplCol);
      row.appendChild(scriptCol);
      pane.appendChild(row);
      ref1 = pane.querySelectorAll('.formula-lang-row');
      results1 = [];
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        langRow = ref1[j];
        results1.push(langRow.remove());
      }
      return results1;
    },
    _ensureWidgetPluginMetaRow: function(app) {
      var anchor, base, base1, base2, base3, descCol, descEl, descLabel, ensureLabel, i, len, makeCol, nameCol, nameEl, nameLabel, oldRow, pane, ref, root, row, selCol, selEl, selLabel;
      root = typeof (base = app.el).widgetPluginModal === "function" ? base.widgetPluginModal() : void 0;
      if (!root) {
        return;
      }
      selEl = typeof (base1 = app.el).widgetPluginSelect === "function" ? base1.widgetPluginSelect() : void 0;
      nameEl = typeof (base2 = app.el).widgetPluginName === "function" ? base2.widgetPluginName() : void 0;
      descEl = typeof (base3 = app.el).widgetPluginDescription === "function" ? base3.widgetPluginDescription() : void 0;
      if (!(selEl && nameEl && descEl)) {
        return;
      }
      pane = selEl.closest('.yaml-editor-pane') || nameEl.closest('.yaml-editor-pane') || descEl.closest('.yaml-editor-pane');
      if (!pane) {
        return;
      }
      row = pane.querySelector('.widget-plugin-meta-row');
      selCol = selEl.closest('.widget-plugin-meta-col');
      nameCol = nameEl.closest('.widget-plugin-meta-col');
      descCol = descEl.closest('.widget-plugin-meta-col');
      if (row && selCol && nameCol && descCol && selCol !== nameCol && nameCol !== descCol && selCol.parentElement === row && nameCol.parentElement === row && descCol.parentElement === row) {
        return;
      }
      ref = pane.querySelectorAll('.widget-plugin-meta-row');
      for (i = 0, len = ref.length; i < len; i++) {
        oldRow = ref[i];
        oldRow.remove();
      }
      selLabel = root.querySelector("label[for='widget-plugin-select']") || selEl.previousElementSibling;
      nameLabel = root.querySelector("label[for='widget-plugin-name']") || nameEl.previousElementSibling;
      descLabel = root.querySelector("label[for='widget-plugin-description']") || descEl.previousElementSibling;
      ensureLabel = function(lbl, txt, forId) {
        var n;
        if (lbl) {
          return lbl;
        }
        n = document.createElement('label');
        n.className = 'formula-hint';
        n.htmlFor = forId;
        n.textContent = txt;
        return n;
      };
      selLabel = ensureLabel(selLabel, 'Plugins existants', 'widget-plugin-select');
      nameLabel = ensureLabel(nameLabel, 'Nom', 'widget-plugin-name');
      descLabel = ensureLabel(descLabel, 'Description', 'widget-plugin-description');
      row = document.createElement('div');
      row.className = 'widget-plugin-meta-row';
      makeCol = function(lbl, inputEl) {
        var col;
        col = document.createElement('div');
        col.className = 'widget-plugin-meta-col';
        if (lbl) {
          col.appendChild(lbl);
        }
        if (inputEl) {
          col.appendChild(inputEl);
        }
        return col;
      };
      row.appendChild(makeCol(selLabel, selEl));
      row.appendChild(makeCol(nameLabel, nameEl));
      row.appendChild(makeCol(descLabel, descEl));
      anchor = pane.querySelector('.widget-plugin-editors-row') || pane.querySelector('.formula-lang-row');
      if (anchor) {
        return pane.insertBefore(row, anchor);
      } else {
        return pane.appendChild(row);
      }
    },
    openWidgetPluginModal: function(app) {
      var ref;
      if ((ref = app.el.widgetPluginModal()) != null) {
        ref.classList.remove('hidden');
      }
      app._widgetPluginDirty = false;
      app._widgetPluginDirtyNames = {};
      window.AppViewHelpers._ensureWidgetPluginMetaRow(app);
      window.AppViewHelpers._ensureWidgetPluginEditorsSplit(app);
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
      return window.AppViewHelpers._loadWidgetPlugins(app);
    },
    setupLayoutPalette: function(app) {
      var actionsContainer, btnHoriz, btnVert, existingPalette, palette;
      // Vérifier si la palette existe déjà pour éviter les doublons
      existingPalette = document.querySelector('.cv-layout-palette');
      if (existingPalette) {
        return;
      }
      // Créer la palette d'insertion de layouts
      palette = document.createElement('div');
      palette.className = 'cv-layout-palette';
      btnVert = document.createElement('button');
      btnVert.textContent = 'Ajouter layout vertical';
      btnVert.className = 'cv-layout-btn';
      btnVert.title = 'Insérer un layout vertical';
      btnHoriz = document.createElement('button');
      btnHoriz.textContent = 'Ajouter layout horizontal';
      btnHoriz.className = 'cv-layout-btn';
      btnHoriz.title = 'Insérer un layout horizontal';
      palette.appendChild(btnVert);
      palette.appendChild(btnHoriz);
      // Insérer la palette dans le header de la modale YAML
      actionsContainer = document.querySelector('.modal-editor-actions');
      if (actionsContainer) {
        actionsContainer.insertBefore(palette, actionsContainer.firstChild);
        // Gestion des clics sur la palette
        btnVert.addEventListener('click', function() {
          return window.dispatchEvent(new CustomEvent('cv-insert-layout', {
            detail: {
              direction: 'vertical'
            }
          }));
        });
        return btnHoriz.addEventListener('click', function() {
          return window.dispatchEvent(new CustomEvent('cv-insert-layout', {
            detail: {
              direction: 'horizontal'
            }
          }));
        });
      }
    },
    _openAddWidgetModal: function(app) {
      var cv;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      // Afficher la modale
      app.el.addWidgetModal().classList.remove('hidden');
      // Corriger le HTML manquant dynamiquement
      window.AppViewHelpers._fixModalHTML();
      // Initialiser la modale avec les fonctions de base
      return window.AppViewHelpers._initializeWidgetModal(app);
    },
    _fixModalHTML: function() {
      var dataSourceConfig, fieldsContainer, fieldsSection, groupBySection, groupBySelect;
      // Ajouter les sections manquantes si elles n'existent pas
      dataSourceConfig = document.querySelector('.data-source-config');
      if (!dataSourceConfig) {
        return;
      }
      // Vérifier si les sections manquent
      fieldsContainer = document.getElementById('widget-fields-container');
      groupBySelect = document.getElementById('widget-groupby-select');
      if (!fieldsContainer) {
        // Créer la section des champs
        fieldsSection = document.createElement('div');
        fieldsSection.className = 'config-row';
        fieldsSection.innerHTML = `<label>Colonnes à afficher:</label>
<div id="widget-fields-container" class="fields-container">
  <div class="fields-header">
    <div class="field-group">Disponibles:</div>
    <div class="field-group">Sélectionnées:</div>
  </div>
  <div class="fields-lists">
    <div id="available-fields" class="fields-list"> </div>
    <div id="selected-fields" class="fields-list selected"> </div>
  </div>
</div>`;
        dataSourceConfig.appendChild(fieldsSection);
      }
      if (!groupBySelect) {
        // Créer la section de groupement
        groupBySection = document.createElement('div');
        groupBySection.className = 'config-row';
        groupBySection.innerHTML = `<label>Groupement (GROUP BY):</label>
<select id="widget-groupby-select" class="widget-select">
  <option value="">Aucun groupement</option>
</select>`;
        return dataSourceConfig.appendChild(groupBySection);
      }
    },
    _initializeWidgetModal: function(app) {
      console.log('_initializeWidgetModal called');
      // Charger les espaces disponibles
      window.AppViewHelpers._loadAvailableSpaces(app);
      // Lier les événements de base
      return window.AppViewHelpers._bindBasicWidgetEvents(app);
    },
    _loadAvailableSpaces: function(app) {
      console.log('_loadAvailableSpaces called');
      // Charger la liste des espaces avec la fonction existante
      return window.Spaces.list().then(function(spaces) {
        var i, len, option, select, space;
        console.log('spaces loaded:', spaces);
        select = document.getElementById('widget-space-select');
        if (!select) {
          return;
        }
        select.innerHTML = '<option value="">Sélectionner un espace...</option>';
        // Stocker les données pour utilisation ultérieure
        app._spacesData = spaces;
        // Stocker aussi globalement pour accès dans les événements
        window._currentSpacesData = spaces;
        console.log('spaces stored in window._currentSpacesData');
        for (i = 0, len = spaces.length; i < len; i++) {
          space = spaces[i];
          option = document.createElement('option');
          option.value = space.id;
          option.textContent = space.name;
          select.appendChild(option);
        }
        // Écouter les changements pour charger les champs
        return select.addEventListener('change', function() {
          var selectedSpace, spaceId, spacesData;
          spaceId = this.value;
          if (!spaceId) {
            return;
          }
          // Trouver l'espace correspondant (utiliser les données globales)
          spacesData = window._currentSpacesData || [];
          selectedSpace = spacesData.find(function(space) {
            return space.id === spaceId;
          });
          console.log('selected space:', selectedSpace);
          // Charger les champs de l'espace sélectionné
          if (selectedSpace) {
            return window.AppViewHelpers._loadSpaceFields(selectedSpace, function() {
              window.AppViewHelpers._populateFieldsLists(selectedSpace);
              return window.AppViewHelpers._populateGroupByOptions(selectedSpace);
            });
          }
        });
      });
    },
    _loadSpaceFields: function(space, callback) {
      var query;
      // Charger les champs d'un espace spécifique
      query = `query GetSpaceFields($spaceId: ID!) {
  space(id: $spaceId) {
    id name
    fields {
      id name fieldType notNull position description formula triggerFields language reprFormula
    }
  }
}`;
      return window.GQL.query(query, {
        spaceId: space.id
      }).then(function(result) {
        if (result.space && result.space.fields) {
          space.fields = result.space.fields;
          console.log('fields loaded for space:', space.name, space.fields);
        }
        return callback();
      }).catch(function(error) {
        console.error('Error loading fields:', error);
        // En cas d'erreur, continuer sans champs
        return callback();
      });
    },
    _toggleFieldSelection: function(fieldItem) {
      var availableContainer, isSelected, selectedContainer;
      isSelected = fieldItem.classList.contains('selected');
      availableContainer = document.getElementById('available-fields');
      selectedContainer = document.getElementById('selected-fields');
      if (isSelected) {
        // Retirer de la sélection
        fieldItem.classList.remove('selected');
        return availableContainer.appendChild(fieldItem);
      } else {
        // Ajouter à la sélection
        fieldItem.classList.add('selected');
        return selectedContainer.appendChild(fieldItem);
      }
    },
    _populateFieldsLists: function(space) {
      var availableContainer, field, fieldItem, i, len, ref, results1, selectedContainer;
      console.log('populateFieldsLists called with space:', space);
      availableContainer = document.getElementById('available-fields');
      selectedContainer = document.getElementById('selected-fields');
      if (!(availableContainer && selectedContainer && space)) {
        return;
      }
      console.log('space fields:', space.fields);
      // Vider les conteneurs
      availableContainer.innerHTML = '';
      selectedContainer.innerHTML = '';
      // Si pas de champs, afficher un message
      if (!space.fields) {
        availableContainer.innerHTML = '<div class="field-item">Cet espace n\'a pas de champs configurés</div>';
        return;
      }
      ref = space.fields || [];
      // Ajouter les champs disponibles
      results1 = [];
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        console.log('creating field item for:', field);
        fieldItem = document.createElement('div');
        fieldItem.className = 'field-item';
        fieldItem.textContent = `${field.name} (${field.fieldType})`;
        fieldItem.dataset.fieldName = field.name;
        fieldItem.dataset.fieldType = field.fieldType;
        fieldItem.addEventListener('click', function() {
          return window.AppViewHelpers._toggleFieldSelection(this);
        });
        results1.push(availableContainer.appendChild(fieldItem));
      }
      return results1;
    },
    _populateGroupByOptions: function(space) {
      var field, groupBySelect, i, len, option, ref, results1;
      groupBySelect = document.getElementById('widget-groupby-select');
      if (!(groupBySelect && space)) {
        return;
      }
      // Vider et repeupler
      groupBySelect.innerHTML = '<option value="">Aucun groupement</option>';
      ref = space.fields;
      // Ajouter chaque champ comme option de GROUP BY
      results1 = [];
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        option = document.createElement('option');
        option.value = field.name;
        option.textContent = field.name;
        results1.push(groupBySelect.appendChild(option));
      }
      return results1;
    },
    _bindBasicWidgetEvents: function(app) {
      var cancelBtn, confirmBtn, i, len, option, typeOptions;
      // Gérer la sélection du type de widget
      typeOptions = document.querySelectorAll('.widget-type-option');
      for (i = 0, len = typeOptions.length; i < len; i++) {
        option = typeOptions[i];
        option.addEventListener('click', function() {
          var j, len1, opt;
// Désélectionner les autres
          for (j = 0, len1 = typeOptions.length; j < len1; j++) {
            opt = typeOptions[j];
            opt.classList.remove('selected');
          }
          // Sélectionner celui-ci
          this.classList.add('selected');
          return this.querySelector('input[type="radio"]').checked = true;
        });
      }
      // Gérer les boutons de la modale
      confirmBtn = document.getElementById('add-widget-confirm-btn');
      cancelBtn = document.getElementById('add-widget-cancel-btn');
      if (confirmBtn) {
        confirmBtn.addEventListener('click', function() {
          return window.AppViewHelpers._submitWidget(app);
        });
      }
      if (cancelBtn) {
        cancelBtn.addEventListener('click', function() {
          return window.AppViewHelpers._closeWidgetModal(app);
        });
      }
      // Gérer les paramètres
      return window.AppViewHelpers._bindParamsManagement(app);
    },
    _bindParamsManagement: function(app) {
      var addBtn, paramsList;
      addBtn = document.getElementById('add-param-btn');
      paramsList = document.getElementById('widget-params-list');
      if (!(addBtn && paramsList)) {
        return;
      }
      addBtn.addEventListener('click', function() {
        return window.AppViewHelpers._addParamRow(paramsList);
      });
      // Gérer les boutons de suppression existants
      return window.AppViewHelpers._bindParamRemoval(paramsList);
    },
    _addParamRow: function(paramsList) {
      var paramRow;
      paramRow = document.createElement('div');
      paramRow.className = 'param-row';
      paramRow.innerHTML = `<input type="text" placeholder="Clé" class="param-key">
<input type="text" placeholder="Valeur" class="param-value">
<button type="button" class="param-remove-btn">✕</button>`;
      paramsList.appendChild(paramRow);
      return window.AppViewHelpers._bindParamRemoval(paramsList);
    },
    _bindParamRemoval: function(paramsList) {
      var btn, i, len, removeBtns, results1;
      removeBtns = paramsList.querySelectorAll('.param-remove-btn');
      results1 = [];
      for (i = 0, len = removeBtns.length; i < len; i++) {
        btn = removeBtns[i];
        // Éviter les doublons d'event listeners
        btn.removeEventListener('click', arguments.callee);
        results1.push(btn.addEventListener('click', function() {
          return this.parentElement.remove();
        }));
      }
      return results1;
    },
    _validateWidgetForm: function() {
      var errors, selectedFields, spaceSelect, titleInput;
      titleInput = document.getElementById('widget-title-input');
      spaceSelect = document.getElementById('widget-space-select');
      selectedFields = document.querySelectorAll('#selected-fields .field-item');
      errors = [];
      // Valider le titre
      if (!(titleInput && titleInput.value.trim())) {
        errors.push('Le titre du widget est requis');
      }
      // Valider l'espace
      if (!(spaceSelect && spaceSelect.value)) {
        errors.push('La sélection d\'un espace est requise');
      }
      // Valider les champs (au moins un champ sélectionné)
      if (!(selectedFields.length > 0)) {
        errors.push('Au moins un champ doit être sélectionné');
      }
      return errors;
    },
    _collectWidgetData: function() {
      var field, fields, groupBySelect, i, j, keyInput, len, len1, paramRow, paramRows, params, selectedFields, selectedType, spaceSelect, titleInput, valueInput;
      titleInput = document.getElementById('widget-title-input');
      spaceSelect = document.getElementById('widget-space-select');
      groupBySelect = document.getElementById('widget-groupby-select');
      selectedType = document.querySelector('input[name="widget-type"]:checked');
      selectedFields = document.querySelectorAll('#selected-fields .field-item');
      paramRows = document.querySelectorAll('#widget-params-list .param-row');
      // Collecter les champs sélectionnés
      fields = [];
      for (i = 0, len = selectedFields.length; i < len; i++) {
        field = selectedFields[i];
        fields.push(field.dataset.fieldName || field.textContent);
      }
      // Collecter les paramètres
      params = {};
      for (j = 0, len1 = paramRows.length; j < len1; j++) {
        paramRow = paramRows[j];
        keyInput = paramRow.querySelector('.param-key');
        valueInput = paramRow.querySelector('.param-value');
        if (keyInput && valueInput && keyInput.value.trim()) {
          params[keyInput.value.trim()] = valueInput.value.trim();
        }
      }
      return {
        title: titleInput.value.trim(),
        spaceId: spaceSelect.value,
        groupBy: groupBySelect.value || null,
        type: selectedType.value || 'table',
        fields: fields,
        params: params
      };
    },
    _submitWidget: function(app) {
      var errors, mutation, ref, variables, viewId, widgetData;
      // Valider le formulaire
      errors = window.AppViewHelpers._validateWidgetForm();
      if (errors.length > 0) {
        alert('Erreurs de validation:\n' + errors.join('\n'));
        return;
      }
      // Collecter les données
      widgetData = window.AppViewHelpers._collectWidgetData();
      // Récupérer l'ID de la vue actuelle depuis l'URL
      viewId = (ref = window.location.hash.match(/view\/([a-f0-9-]+)/)) != null ? ref[1] : void 0;
      if (!viewId) {
        alert('Erreur: impossible de déterminer l\'ID de la vue actuelle');
        return;
      }
      // Préparer la mutation GraphQL
      mutation = `mutation AddWidgetToView($viewId: ID!, $widget: WidgetInput!) {
  addWidgetToView(viewId: $viewId, widget: $widget) {
    id
    name
    yaml
  }
}`;
      // Préparer les variables
      variables = {
        viewId: viewId,
        widget: {
          title: widgetData.title,
          type: widgetData.type,
          spaceId: widgetData.spaceId,
          fields: widgetData.fields,
          groupBy: widgetData.groupBy,
          params: widgetData.params,
          position: {
            x: 0,
            y: 0,
            w: 6,
            h: 4
          }
        }
      };
      // Exécuter la mutation
      return window.GQL.mutate(mutation, variables).then(function(result) {
        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          return alert('Erreur lors de la création du widget: ' + result.errors[0].message);
        } else {
          console.log('Widget créé avec succès:', result.data.addWidgetToView);
          window.AppViewHelpers._closeWidgetModal(app);
          return alert('Widget créé avec succès!');
        }
      // TODO: Recharger la vue pour afficher le nouveau widget
      }).catch(function(error) {
        console.error('Network error:', error);
        return alert('Erreur réseau lors de la création du widget: ' + error.message);
      });
    }
  };

  ({
    _getWidgetConfig: function(app) {
      var config, field, groupBySelect, i, len, paramRows, ref, selectedFields, spaceSelect, titleInput, widgetTypeRadio;
      // Récupérer la configuration complète du widget
      titleInput = document.getElementById('widget-title-input');
      spaceSelect = document.getElementById('widget-space-select');
      groupBySelect = document.getElementById('widget-groupby-select');
      selectedFields = document.querySelectorAll('#selected-fields .field-item');
      widgetTypeRadio = document.querySelector('input[name="widget-type"]:checked');
      paramRows = document.querySelectorAll('#widget-params-list .param-row');
      config = {
        title: (titleInput != null ? titleInput.value : void 0) || 'Widget sans titre',
        space: (spaceSelect != null ? spaceSelect.value : void 0) || '',
        spaceName: (spaceSelect != null ? (ref = spaceSelect.options[spaceSelect != null ? spaceSelect.selectedIndex : void 0]) != null ? ref.textContent : void 0 : void 0) || '',
        groupBy: (groupBySelect != null ? groupBySelect.value : void 0) || '',
        widgetType: (widgetTypeRadio != null ? widgetTypeRadio.value : void 0) || 'table',
        fields: [],
        params: {}
      };
// Ajouter les champs sélectionnés
      for (i = 0, len = selectedFields.length; i < len; i++) {
        field = selectedFields[i];
        config.fields.push({
          id: field.dataset.fieldId,
          name: field.dataset.fieldName,
          type: field.dataset.fieldType
        });
      }
      config;
      return {
        _closeWidgetModal: function(app) {
          var modal;
          modal = document.getElementById('add-widget-modal');
          if (!modal) {
            return;
          }
          // Masquer la modale
          modal.classList.add('hidden');
          // Réinitialiser le formulaire
          return window.AppViewHelpers._resetWidgetForm();
        },
        _resetWidgetForm: function() {
          var availableContainer, firstRow, j, keyInput, len1, paramsList, selectedContainer, tableType, valueInput;
          titleInput = document.getElementById('widget-title-input');
          spaceSelect = document.getElementById('widget-space-select');
          groupBySelect = document.getElementById('widget-groupby-select');
          // Réinitialiser les champs
          if (titleInput) {
            titleInput.value = 'Mon widget';
          }
          if (spaceSelect) {
            spaceSelect.value = '';
          }
          if (groupBySelect) {
            groupBySelect.value = '';
          }
          // Réinitialiser les champs sélectionnés
          availableContainer = document.getElementById('available-fields');
          selectedContainer = document.getElementById('selected-fields');
          if (availableContainer && selectedContainer) {
            // Remettre les champs sélectionnés dans disponibles
            selectedFields = selectedContainer.querySelectorAll('.field-item');
            for (j = 0, len1 = selectedFields.length; j < len1; j++) {
              field = selectedFields[j];
              field.classList.remove('selected');
              availableContainer.appendChild(field);
            }
          }
          // Réinitialiser le type de widget
          tableType = document.getElementById('widget-type-table');
          if (tableType) {
            tableType.checked = true;
          }
          // Réinitialiser les paramètres
          paramsList = document.getElementById('widget-params-list');
          if (paramsList) {
            // Garder seulement la première ligne de paramètres
            while (paramsList.children.length > 1) {
              paramsList.removeChild(paramsList.lastChild);
            }
            // Vider les champs de la première ligne
            firstRow = paramsList.querySelector('.param-row');
            if (firstRow) {
              keyInput = firstRow.querySelector('.param-key');
              valueInput = firstRow.querySelector('.param-value');
              if (keyInput) {
                keyInput.value = '';
              }
              if (valueInput) {
                return valueInput.value = '';
              }
            }
          }
        },
        _getWidgetConfig: function(app) {
          var j, k, keyInput, len1, len2, paramRow, ref1, valueInput;
          // Récupérer la configuration complète du widget
          titleInput = document.getElementById('widget-title-input');
          spaceSelect = document.getElementById('widget-space-select');
          groupBySelect = document.getElementById('widget-groupby-select');
          selectedFields = document.querySelectorAll('#selected-fields .field-item');
          widgetTypeRadio = document.querySelector('input[name="widget-type"]:checked');
          paramRows = document.querySelectorAll('#widget-params-list .param-row');
          config = {
            title: (titleInput != null ? titleInput.value : void 0) || 'Widget sans titre',
            space: (spaceSelect != null ? spaceSelect.value : void 0) || '',
            spaceName: (spaceSelect != null ? (ref1 = spaceSelect.options[spaceSelect != null ? spaceSelect.selectedIndex : void 0]) != null ? ref1.textContent : void 0 : void 0) || '',
            groupBy: (groupBySelect != null ? groupBySelect.value : void 0) || '',
            widgetType: (widgetTypeRadio != null ? widgetTypeRadio.value : void 0) || 'table',
            fields: [],
            params: {}
          };
// Ajouter les champs sélectionnés
          for (j = 0, len1 = selectedFields.length; j < len1; j++) {
            field = selectedFields[j];
            config.fields.push({
              id: field.dataset.fieldId,
              name: field.dataset.fieldName,
              type: field.dataset.fieldType
            });
          }
// Ajouter les paramètres
          for (k = 0, len2 = paramRows.length; k < len2; k++) {
            paramRow = paramRows[k];
            keyInput = paramRow.querySelector('.param-key');
            valueInput = paramRow.querySelector('.param-value');
            if ((keyInput != null ? keyInput.value : void 0) && (valueInput != null ? valueInput.value : void 0)) {
              config.params[keyInput.value] = valueInput.value;
            }
          }
          return config;
        },
        _showWidgetConfig: function(app, type, data) {
          var container;
          container = app.el.widgetConfigForm();
          container.innerHTML = '';
          if (type === 'table') {
            config = document.createElement('div');
            config.innerHTML = `<div class="config-field">
  <label>Titre:</label>
  <input type="text" id="widget-title" value="${data.name}" />
</div>
<div class="config-field">
  <label>Espace:</label>
  <span>${data.name}</span>
</div>
<div class="config-field">
  <label>Type de widget:</label>
  <div class="widget-type-options">
    <div class="widget-type-option">
      <input type="radio" name="widget-type" value="table" checked>
      <span>Table</span>
    </div>
    <div class="widget-type-option">
      <input type="radio" name="widget-type" value="chart">
      <span>Graphique</span>
    </div>
  </div>
</div>
<div class="config-field">
  <label>Espace:</label>
  <select id="widget-space-select">
    <option value="">Sélectionner un espace...</option>
  </select>
</div>
<div class="config-field">
  <label>Champs:</label>
  <div id="available-fields"></div>
  <div id="selected-fields"></div>
</div>
<div class="config-field">
  <label>Paramètres:</label>
  <button type="button" id="add-param-btn">Ajouter un paramètre</button>
  <div id="widget-params-list"></div>
</div>`;
            return container.appendChild(config);
          } else if (type === 'plugin') {
            config = document.createElement('div');
            config.innerHTML = `<div class="config-field">
  <label>Titre:</label>
  <input type="text" id="widget-title" value="${data.name}" />
</div>
<div class="config-field">
  <label>Type:</label>
  <span>${data.type}</span>
</div>`;
            return container.appendChild(config);
          }
        },
        _bindAddWidgetModal: function(app) {
          // Lier les événements pour la nouvelle structure
          window.AppViewHelpers._bindWidgetTypeSelection(app);
          return window.AppViewHelpers._bindParamsManagement(app);
        },
        _confirmAddWidget: function(app) {
          var cv, e, newYaml, parsed, widgetConfig, widgetYaml;
          cv = app._currentCustomView;
          if (!cv) {
            return;
          }
          // Récupérer la configuration complète
          widgetConfig = window.AppViewHelpers._getWidgetConfig(app);
          // Validation
          if (!widgetConfig.space) {
            tdbAlert("Veuillez sélectionner un espace", 'error');
            return;
          }
          if (!(widgetConfig.fields.length > 0)) {
            tdbAlert("Veuillez sélectionner au moins un champ", 'error');
            return;
          }
          try {
            // Parser le YAML existant
            parsed = jsyaml.load(cv.yaml);
            // Créer le widget YAML selon le type
            widgetYaml = window.AppViewHelpers._createWidgetYaml(widgetConfig);
            // Ajouter le widget comme enfant du layout racine
            parsed.layout.children.push(jsyaml.load(widgetYaml)[0]);
            // Mettre à jour le YAML
            newYaml = jsyaml.dump(parsed);
            // Sauvegarder
            return GQL.mutate(app._updateCustomViewMutation, {
              id: cv.id,
              input: {
                yaml: newYaml
              }
            }).then(function(data) {
              app._currentCustomView = data.updateCustomView;
              window.AppViewHelpers._closeAddWidgetModal(app);
              return window.AppViewHelpers._renderCustomViewPreview(app, newYaml);
            }).catch(function(err) {
              return tdbAlert(app._err(err), 'error');
            });
          } catch (error1) {
            e = error1;
            return tdbAlert(`Erreur YAML : ${e.message}`, 'error');
          }
        },
        _createWidgetYaml: function(config) {
          var key, ref1, value, widget;
          // Créer le YAML du widget selon la configuration
          widget = {
            title: config.title,
            type: config.widgetType,
            space: config.space
          };
          // Ajouter les champs
          if (config.fields.length > 0) {
            widget.fields = config.fields.map(function(field) {
              return field.name;
            });
          }
          // Ajouter le groupement si spécifié
          if (config.groupBy) {
            widget.groupBy = config.groupBy;
          }
          // Ajouter les paramètres personnalisés
          if (Object.keys(config.params).length > 0) {
            ref1 = config.params;
            for (key in ref1) {
              value = ref1[key];
              widget[key] = value;
            }
          }
          // Convertir en YAML
          return jsyaml.dump([widget]);
        },
        _renderCustomViewPreview: function(app, yaml) {
          // Cette fonction sera implémentée plus tard pour rafraîchir l'aperçu
          return console.log("Preview refreshed with YAML:", yaml);
        },
        _closeAddWidgetModal: function(app) {
          app.el.addWidgetModal().classList.add('hidden');
          return app._selectedWidget = null;
        }
      };
    }
  });

  // Gestionnaires d'événements principaux pour la modale
  window.AppViewHelpers._bindAddWidgetModal = function(app) {
    // Bouton de confirmation
    app.el.addWidgetConfirmBtn().addEventListener('click', function() {
      return window.AppViewHelpers._confirmAddWidget(app);
    });
    // Bouton d'annulation
    return app.el.addWidgetCancelBtn().addEventListener('click', function() {
      return window.AppViewHelpers._closeAddWidgetModal(app);
    });
  };

}).call(this);
