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
      } catch (error) {
        e = error;
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
    }
  };

}).call(this);
