(function() {
  // app_view_helpers_widget_plugins.coffee — widget plugin helpers extracted from app_view_helpers.coffee
  var hasProp = {}.hasOwnProperty;

  Object.assign(window.AppViewHelpers, {
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
        var _, child, i, len, nodeType, results, val;
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
          results = [];
          for (_ in node) {
            if (!hasProp.call(node, _)) continue;
            val = node[_];
            results.push(walk(val));
          }
          return results;
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
      var base, base1, base2, base3, base4, ensureLabel, i, j, langRow, len, len1, oldRow, pane, ref, ref1, results, root, row, scriptCol, scriptColCurrent, scriptEl, scriptLabel, scriptLangLabel, scriptLangSel, tplCol, tplColCurrent, tplEl, tplLabel, tplLangLabel, tplLangSel;
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
      results = [];
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        langRow = ref1[j];
        results.push(langRow.remove());
      }
      return results;
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
  });

}).call(this);
