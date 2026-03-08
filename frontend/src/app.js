(function() {
  // app.coffee — main application bootstrap and UI orchestration.
  var CREATE_CUSTOM_VIEW, DELETE_CUSTOM_VIEW, LIST_CUSTOM_VIEWS, REMOVE_FIELD, REORDER_FIELDS, UPDATE_CUSTOM_VIEW;

  REMOVE_FIELD = `mutation RemoveField($fieldId: ID!) { removeField(fieldId: $fieldId) }`;

  REORDER_FIELDS = `mutation ReorderFields($spaceId: ID!, $fieldIds: [ID!]!) {
  reorderFields(spaceId: $spaceId, fieldIds: $fieldIds) { id name fieldType notNull position }
}`;

  LIST_CUSTOM_VIEWS = `query { customViews { id name description yaml } }`;

  CREATE_CUSTOM_VIEW = `mutation CreateCustomView($input: CreateCustomViewInput!) {
  createCustomView(input: $input) { id name yaml }
}`;

  UPDATE_CUSTOM_VIEW = `mutation UpdateCustomView($id: ID!, $input: UpdateCustomViewInput!) {
  updateCustomView(id: $id, input: $input) { id name yaml }
}`;

  DELETE_CUSTOM_VIEW = `mutation DeleteCustomView($id: ID!) { deleteCustomView(id: $id) }`;

  window.App = {
    _currentSpace: null,
    _currentCustomView: null,
    _activeDataView: null,
    _activeCustomView: null,
    _allSpaces: [],
    _editingFieldId: null, // fieldId being edited in the Champs form, or null
    
    // ── DOM refs ────────────────────────────────────────────────────────────────
    el: {
      loginOverlay: function() {
        return document.getElementById('login-overlay');
      },
      main: function() {
        return document.getElementById('main');
      },
      loginUser: function() {
        return document.getElementById('login-username');
      },
      loginPass: function() {
        return document.getElementById('login-password');
      },
      loginBtn: function() {
        return document.getElementById('login-btn');
      },
      loginError: function() {
        return document.getElementById('login-error');
      },
      currentUser: function() {
        return document.getElementById('current-user');
      },
      logoutBtn: function() {
        return document.getElementById('logout-btn');
      },
      spaceList: function() {
        return document.getElementById('space-list');
      },
      newSpaceBtn: function() {
        return document.getElementById('new-space-btn');
      },
      customViewList: function() {
        return document.getElementById('custom-view-list');
      },
      newViewBtn: function() {
        return document.getElementById('new-view-btn');
      },
      dataToolbar: function() {
        return document.getElementById('data-toolbar');
      },
      dataTitle: function() {
        return document.getElementById('data-title');
      },
      renameSpaceBtn: function() {
        return document.getElementById('rename-space-btn');
      },
      deleteSpaceBtn: function() {
        return document.getElementById('delete-space-btn');
      },
      fieldsBtn: function() {
        return document.getElementById('fields-btn');
      },
      deleteRowsBtn: function() {
        return document.getElementById('delete-rows-btn');
      },
      gridContainer: function() {
        return document.getElementById('grid-container');
      },
      customViewContainer: function() {
        return document.getElementById('custom-view-container');
      },
      fieldsPanel: function() {
        return document.getElementById('fields-panel');
      },
      fieldsPanelClose: function() {
        return document.getElementById('fields-panel-close');
      },
      fieldsList: function() {
        return document.getElementById('fields-list');
      },
      fieldName: function() {
        return document.getElementById('field-name');
      },
      fieldType: function() {
        return document.getElementById('field-type');
      },
      fieldNotNull: function() {
        return document.getElementById('field-notnull');
      },
      fieldFormula: function() {
        return document.getElementById('field-formula');
      },
      formulaLanguage: function() {
        return document.getElementById('formula-language');
      },
      fieldTriggerFields: function() {
        return document.getElementById('field-trigger-fields');
      },
      formulaBody: function() {
        return document.getElementById('formula-body');
      },
      triggerFieldsRow: function() {
        return document.getElementById('trigger-fields-row');
      },
      fieldAddBtn: function() {
        return document.getElementById('field-add-btn');
      },
      fieldCancelBtn: function() {
        return document.getElementById('field-cancel-btn');
      },
      relTargetRow: function() {
        return document.getElementById('rel-target-row');
      },
      relToSpace: function() {
        return document.getElementById('rel-to-space');
      },
      yamlEditorPanel: function() {
        return document.getElementById('yaml-editor-panel');
      },
      yamlViewName: function() {
        return document.getElementById('yaml-view-name');
      },
      yamlEditBtn: function() {
        return document.getElementById('yaml-edit-btn');
      },
      yamlCloseEditorBtn: function() {
        return document.getElementById('yaml-close-editor-btn');
      },
      yamlEditor: function() {
        return document.getElementById('yaml-editor');
      },
      yamlSaveBtn: function() {
        return document.getElementById('yaml-save-btn');
      },
      yamlPreviewBtn: function() {
        return document.getElementById('yaml-preview-btn');
      },
      yamlDeleteBtn: function() {
        return document.getElementById('yaml-delete-btn');
      },
      welcome: function() {
        return document.getElementById('welcome');
      },
      contentRow: function() {
        return document.getElementById('content-row');
      }
    },
    // ── Bootstrap ───────────────────────────────────────────────────────────────
    init: function() {
      this._bindLogin();
      this._bindSidebar();
      this._bindDataToolbar();
      this._bindFieldsPanel();
      return this._bindYamlEditor();
    },
    // ── Login ───────────────────────────────────────────────────────────────────
    _bindLogin: function() {
      var doLogin, onEnter;
      doLogin = () => {
        var password, username;
        username = this.el.loginUser().value.trim();
        password = this.el.loginPass().value;
        if (!(username && password)) {
          return;
        }
        this.el.loginError().textContent = '';
        return Auth.login(username, password).then((user) => {
          this.showMain(user);
          return this._loadAll();
        }).catch((err) => {
          return this.el.loginError().textContent = err.message;
        });
      };
      this.el.loginBtn().addEventListener('click', doLogin);
      onEnter = function(e) {
        if (e.key === 'Enter') {
          return doLogin();
        }
      };
      this.el.loginUser().addEventListener('keydown', onEnter);
      return this.el.loginPass().addEventListener('keydown', onEnter);
    },
    showLogin: function() {
      this.el.loginOverlay().classList.remove('hidden');
      return this.el.main().classList.add('hidden');
    },
    showMain: function(user) {
      this.el.loginOverlay().classList.add('hidden');
      this.el.main().classList.remove('hidden');
      return this.el.currentUser().textContent = user.username;
    },
    // ── Sidebar ─────────────────────────────────────────────────────────────────
    _bindSidebar: function() {
      this.el.newSpaceBtn().addEventListener('click', () => {
        var name;
        name = prompt('Nom du nouvel espace :');
        if (!(name != null ? name.trim() : void 0)) {
          return;
        }
        return Spaces.create(name.trim()).then(() => {
          return this._loadAll();
        }).catch(function(err) {
          return alert(`Erreur : ${err.message}`);
        });
      });
      this.el.newViewBtn().addEventListener('click', () => {
        var name;
        name = prompt('Nom de la nouvelle vue :');
        if (!(name != null ? name.trim() : void 0)) {
          return;
        }
        return GQL.mutate(CREATE_CUSTOM_VIEW, {
          input: {
            name: name.trim(),
            yaml: "layout:\n  direction: vertical\n  children: []\n"
          }
        }).then((data) => {
          return this.loadCustomViews().then(() => {
            var cv;
            cv = data.createCustomView;
            return this.selectCustomView(cv);
          });
        }).catch(function(err) {
          return alert(`Erreur : ${err.message}`);
        });
      });
      return this.el.logoutBtn().addEventListener('click', () => {
        return Auth.logout();
      });
    },
    // ── Load everything ─────────────────────────────────────────────────────────
    _loadAll: function() {
      return Promise.all([this.loadSpaces(), this.loadCustomViews()]).then(() => {
        return this._restoreFromHash();
      });
    },
    // ── Hash-based navigation ────────────────────────────────────────────────────
    _restoreFromHash: function() {
      var cvItems, hash, i, len, li, m, results, sp, spaceId, ul, viewId;
      hash = window.location.hash;
      if (m = hash.match(/^#space\/(.+)$/)) {
        spaceId = m[1];
        sp = (this._allSpaces || []).find(function(s) {
          return s.id === spaceId;
        });
        if (sp) {
          return this.selectSpace(sp);
        }
      } else if (m = hash.match(/^#view\/(.+)$/)) {
        viewId = m[1];
        ul = this.el.customViewList();
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
    // ── Spaces (Données section) ─────────────────────────────────────────────────
    loadSpaces: function() {
      return Spaces.list().then((spaces) => {
        this._allSpaces = spaces;
        return this.renderSpaceList(spaces);
      }).catch(function(err) {
        return console.error('loadSpaces', err);
      });
    },
    renderSpaceList: function(spaces) {
      var i, len, li, results, sp, ul;
      ul = this.el.spaceList();
      ul.innerHTML = '';
      results = [];
      for (i = 0, len = spaces.length; i < len; i++) {
        sp = spaces[i];
        li = document.createElement('li');
        li.textContent = sp.name;
        li.dataset.id = sp.id;
        ((sp) => {
          return li.addEventListener('click', () => {
            return this.selectSpace(sp);
          });
        })(sp);
        results.push(ul.appendChild(li));
      }
      return results;
    },
    selectSpace: function(sp) {
      var i, j, len, len1, li, ref, ref1, ref2;
      history.replaceState(null, '', `#space/${sp.id}`);
      ref = this.el.customViewList().querySelectorAll('li');
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = this.el.spaceList().querySelectorAll('li');
      // Highlight space item
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.toggle('active', li.dataset.id === sp.id);
      }
      this._currentCustomView = null;
      if ((ref2 = this._activeCustomView) != null) {
        if (typeof ref2.unmount === "function") {
          ref2.unmount();
        }
      }
      this._activeCustomView = null;
      // Close fields panel
      this.el.fieldsPanel().classList.add('hidden');
      this.el.fieldsBtn().classList.remove('active');
      // Show data toolbar, hide YAML panel + custom view
      this.el.dataToolbar().classList.remove('hidden');
      this.el.yamlEditorPanel().classList.add('hidden');
      this.el.customViewContainer().classList.add('hidden');
      this.el.gridContainer().classList.remove('hidden');
      this.el.welcome().classList.add('hidden');
      this.el.contentRow().classList.remove('hidden');
      return Spaces.getWithFields(sp.id).then((full) => {
        this._currentSpace = full;
        this.el.dataTitle().textContent = full.name;
        return this._mountDataView(full);
      }).catch(function(err) {
        return console.error('selectSpace', err);
      });
    },
    // Keep @_allSpaces in sync after any field mutation on the current space.
    // If a custom view is active, rebuilds it so widgets get the fresh columns.
    _syncSpaceFields: function(space) {
      var ref, ref1;
      this._allSpaces = (this._allSpaces || []).map((s) => {
        if (s.id === space.id) {
          return space;
        } else {
          return s;
        }
      });
      if (this._activeCustomView && ((ref = this._currentCustomView) != null ? (ref1 = ref.yaml) != null ? ref1.trim() : void 0 : void 0)) {
        return this._renderCustomViewPreview(this._currentCustomView.yaml);
      }
    },
    _mountDataView: function(space) {
      var container, ref;
      if ((ref = this._activeDataView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container = this.el.gridContainer();
      this._activeDataView = new DataView(container, space);
      return this._activeDataView.mount();
    },
    // ── Custom views (Vues section) ──────────────────────────────────────────────
    loadCustomViews: function() {
      return GQL.query(LIST_CUSTOM_VIEWS).then((data) => {
        return this.renderCustomViewList(data.customViews);
      }).catch(function(err) {
        return console.error('loadCustomViews', err);
      });
    },
    renderCustomViewList: function(views) {
      var cv, i, len, li, ref, results, ul;
      ul = this.el.customViewList();
      ul.innerHTML = '';
      ref = views || [];
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        cv = ref[i];
        li = document.createElement('li');
        li.textContent = cv.name;
        li.dataset.id = cv.id;
        ((cv) => {
          return li.addEventListener('click', () => {
            return this.selectCustomView(cv);
          });
        })(cv);
        results.push(ul.appendChild(li));
      }
      return results;
    },
    selectCustomView: function(cv) {
      var i, j, len, len1, li, panel, ref, ref1, ref2, ref3;
      history.replaceState(null, '', `#view/${cv.id}`);
      this._currentCustomView = cv;
      ref = this.el.spaceList().querySelectorAll('li');
      // Deactivate space items
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = this.el.customViewList().querySelectorAll('li');
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.toggle('active', li.dataset.id === cv.id);
      }
      this._currentSpace = null;
      if ((ref2 = this._activeDataView) != null) {
        if (typeof ref2.unmount === "function") {
          ref2.unmount();
        }
      }
      this._activeDataView = null;
      // Hide data grid area
      this.el.dataToolbar().classList.add('hidden');
      this.el.fieldsPanel().classList.add('hidden');
      this.el.gridContainer().classList.add('hidden');
      this.el.welcome().classList.add('hidden');
      this.el.contentRow().classList.remove('hidden');
      panel = this.el.yamlEditorPanel();
      panel.classList.remove('hidden');
      this.el.yamlViewName().textContent = cv.name;
      this.el.yamlEditor().value = cv.yaml || '';
      // If YAML exists, start in view mode; otherwise go straight to editor
      if ((ref3 = cv.yaml) != null ? ref3.trim() : void 0) {
        this._setYamlMode('view');
        return this._renderCustomViewPreview(cv.yaml);
      } else {
        this._setYamlMode('edit');
        return this.el.customViewContainer().classList.add('hidden');
      }
    },
    _setYamlMode: function(mode) { // 'view' or 'edit'
      var panel;
      panel = this.el.yamlEditorPanel();
      panel.classList.toggle('view-mode', mode === 'view');
      return panel.classList.toggle('edit-mode', mode === 'edit');
    },
    _renderCustomViewPreview: function(yamlText) {
      var container, ref;
      container = this.el.customViewContainer();
      if ((ref = this._activeCustomView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container.innerHTML = '';
      container.classList.remove('hidden');
      this._activeCustomView = new CustomView(container, yamlText, this._allSpaces);
      return this._activeCustomView.mount();
    },
    // ── YAML editor ─────────────────────────────────────────────────────────────
    _bindYamlEditor: function() {
      this.el.yamlEditBtn().addEventListener('click', () => {
        return this._setYamlMode('edit');
      });
      this.el.yamlCloseEditorBtn().addEventListener('click', () => {
        return this._setYamlMode('view');
      });
      this.el.yamlSaveBtn().addEventListener('click', () => {
        var cv, yaml;
        cv = this._currentCustomView;
        if (!cv) {
          return;
        }
        yaml = this.el.yamlEditor().value;
        return GQL.mutate(UPDATE_CUSTOM_VIEW, {
          id: cv.id,
          input: {yaml}
        }).then((data) => {
          this._currentCustomView = data.updateCustomView;
          this._renderCustomViewPreview(yaml);
          this._setYamlMode('view');
          return this.loadCustomViews();
        }).catch(function(err) {
          return alert(`Erreur : ${err.message}`);
        });
      });
      this.el.yamlPreviewBtn().addEventListener('click', () => {
        if (!this._currentCustomView) {
          return;
        }
        return this._renderCustomViewPreview(this.el.yamlEditor().value);
      });
      return this.el.yamlDeleteBtn().addEventListener('click', () => {
        var cv;
        cv = this._currentCustomView;
        if (!cv) {
          return;
        }
        if (!confirm(`Supprimer la vue « ${cv.name} » ?`)) {
          return;
        }
        return GQL.mutate(DELETE_CUSTOM_VIEW, {
          id: cv.id
        }).then(() => {
          var ref;
          this._currentCustomView = null;
          if ((ref = this._activeCustomView) != null) {
            if (typeof ref.unmount === "function") {
              ref.unmount();
            }
          }
          this._activeCustomView = null;
          this.el.yamlEditorPanel().classList.add('hidden');
          this.el.customViewContainer().classList.add('hidden');
          this.el.welcome().classList.remove('hidden');
          return this.loadCustomViews();
        }).catch(function(err) {
          return alert(`Erreur : ${err.message}`);
        });
      });
    },
    // ── Data toolbar ─────────────────────────────────────────────────────────────
    _bindDataToolbar: function() {
      this.el.deleteRowsBtn().addEventListener('click', () => {
        var ref;
        return (ref = this._activeDataView) != null ? ref.deleteSelected() : void 0;
      });
      this.el.deleteSpaceBtn().addEventListener('click', () => {
        var name;
        if (!this._currentSpace) {
          return;
        }
        name = this._currentSpace.name;
        if (!confirm(`Supprimer l'espace « ${name} » et toutes ses données ?`)) {
          return;
        }
        return Spaces.delete(this._currentSpace.id).then(() => {
          var ref;
          this._currentSpace = null;
          if ((ref = this._activeDataView) != null) {
            if (typeof ref.unmount === "function") {
              ref.unmount();
            }
          }
          this._activeDataView = null;
          this.el.dataToolbar().classList.add('hidden');
          this.el.fieldsPanel().classList.add('hidden');
          this.el.fieldsBtn().classList.remove('active');
          this.el.welcome().classList.remove('hidden');
          return this._loadAll();
        }).catch(function(err) {
          return alert(`Erreur : ${err.message}`);
        });
      });
      return this.el.renameSpaceBtn().addEventListener('click', () => {
        var newName;
        if (!this._currentSpace) {
          return;
        }
        newName = prompt("Nouveau nom de l'espace :", this._currentSpace.name);
        if (!((newName != null ? newName.trim() : void 0) && newName.trim() !== this._currentSpace.name)) {
          return;
        }
        return Spaces.update(this._currentSpace.id, newName.trim()).then((updated) => {
          var li;
          this._currentSpace.name = updated.name;
          this.el.dataTitle().textContent = updated.name;
          // Update sidebar
          li = this.el.spaceList().querySelector(`li[data-id='${updated.id}']`);
          if (li) {
            return li.textContent = updated.name;
          }
        }).catch(function(err) {
          return alert(`Erreur : ${err.message}`);
        });
      });
    },
    // ── Fields panel ─────────────────────────────────────────────────────────────
    _bindFieldsPanel: function() {
      this.el.fieldsBtn().addEventListener('click', () => {
        var btn, panel;
        panel = this.el.fieldsPanel();
        btn = this.el.fieldsBtn();
        if (panel.classList.contains('hidden')) {
          panel.classList.remove('hidden');
          btn.classList.add('active');
          return this.renderFieldsList();
        } else {
          panel.classList.add('hidden');
          return btn.classList.remove('active');
        }
      });
      this.el.fieldsPanelClose().addEventListener('click', () => {
        this.el.fieldsPanel().classList.add('hidden');
        return this.el.fieldsBtn().classList.remove('active');
      });
      // Show/hide formula section and relation target based on type selection
      this.el.fieldType().addEventListener('change', () => {
        return this._onFieldTypeChange();
      });
      // Show/hide formula textarea and trigger-fields row based on radio selection
      document.querySelectorAll('input[name="formula-type"]').forEach((radio) => {
        return radio.addEventListener('change', () => {
          var val;
          val = document.querySelector('input[name="formula-type"]:checked').value;
          this.el.formulaBody().classList.toggle('hidden', val === 'none');
          return this.el.triggerFieldsRow().classList.toggle('hidden', val !== 'trigger');
        });
      });
      this.el.fieldCancelBtn().addEventListener('click', () => {
        return this._resetFieldForm();
      });
      return this.el.fieldAddBtn().addEventListener('click', () => {
        var formula, formulaType, language, name, notNull, opts, raw, ref, ref1, s, toSpaceId, triggerFields, type;
        if (!this._currentSpace) {
          return;
        }
        name = this.el.fieldName().value.trim();
        type = this.el.fieldType().value;
        notNull = this.el.fieldNotNull().checked;
        if (!name) {
          return;
        }
        if (this._editingFieldId) {
          // ── Update existing field ──────────────────────────────────────────
          formulaType = document.querySelector('input[name="formula-type"]:checked').value;
          opts = {name, notNull};
          if (formulaType !== 'none') {
            opts.formula = this.el.fieldFormula().value.trim() || null;
            opts.language = ((ref = this.el.formulaLanguage()) != null ? ref.value : void 0) || 'lua';
            if (formulaType === 'trigger' && opts.formula) {
              raw = this.el.fieldTriggerFields().value.trim();
              if (raw === '*') {
                opts.triggerFields = ['*'];
              } else if (raw === '') {
                opts.triggerFields = [];
              } else {
                opts.triggerFields = (function() {
                  var i, len, ref1, results;
                  ref1 = raw.split(',');
                  results = [];
                  for (i = 0, len = ref1.length; i < len; i++) {
                    s = ref1[i];
                    if (s.trim()) {
                      results.push(s.trim());
                    }
                  }
                  return results;
                })();
              }
            }
          } else {
            opts.formula = '';
            opts.triggerFields = null;
            opts.language = 'lua';
          }
          Spaces.updateField(this._editingFieldId, opts).then(() => {
            return Spaces.getWithFields(this._currentSpace.id).then((full) => {
              this._currentSpace = full;
              this._syncSpaceFields(full);
              this.renderFieldsList();
              return this._mountDataView(full);
            });
          }).catch(function(err) {
            return alert(`Erreur : ${err.message}`);
          });
          return this._resetFieldForm();
        } else if (type === 'Relation') {
          // ── Create relation field ──────────────────────────────────────────
          toSpaceId = this.el.relToSpace().value;
          if (!toSpaceId) {
            return;
          }
          Spaces.getWithFields(toSpaceId).then((targetSpace) => {
            var idField;
            idField = (targetSpace.fields || []).find(function(f) {
              return f.fieldType === 'Sequence';
            });
            if (!idField) {
              return alert("L'espace cible n'a pas de champ Séquence.");
            }
            return Spaces.addField(this._currentSpace.id, name, 'Int', notNull, '').then((newField) => {
              return Spaces.createRelation(name, this._currentSpace.id, newField.id, toSpaceId, idField.id).then(() => {
                return Spaces.getWithFields(this._currentSpace.id).then((full) => {
                  this._currentSpace = full;
                  this._syncSpaceFields(full);
                  this.renderFieldsList();
                  return this._mountDataView(full);
                });
              }).catch(function(err) {
                return alert(`Erreur : ${err.message}`);
              });
            }).catch(function(err) {
              return alert(`Erreur : ${err.message}`);
            });
          });
          return this._resetFieldForm();
        } else {
          // ── Add new regular field ──────────────────────────────────────────
          formulaType = document.querySelector('input[name="formula-type"]:checked').value;
          formula = null;
          triggerFields = null;
          language = ((ref1 = this.el.formulaLanguage()) != null ? ref1.value : void 0) || 'lua';
          if (formulaType !== 'none') {
            formula = this.el.fieldFormula().value.trim() || null;
            if (formulaType === 'trigger' && formula) {
              raw = this.el.fieldTriggerFields().value.trim();
              if (raw === '*') {
                triggerFields = ['*'];
              } else if (raw === '') {
                triggerFields = [];
              } else {
                triggerFields = (function() {
                  var i, len, ref2, results;
                  ref2 = raw.split(',');
                  results = [];
                  for (i = 0, len = ref2.length; i < len; i++) {
                    s = ref2[i];
                    if (s.trim()) {
                      results.push(s.trim());
                    }
                  }
                  return results;
                })();
              }
            }
          }
          Spaces.addField(this._currentSpace.id, name, type, notNull, '', formula, triggerFields, language).then(() => {
            return Spaces.getWithFields(this._currentSpace.id).then((full) => {
              this._currentSpace = full;
              this._syncSpaceFields(full);
              this.renderFieldsList();
              return this._mountDataView(full);
            });
          }).catch(function(err) {
            return alert(`Erreur : ${err.message}`);
          });
          return this._resetFieldForm();
        }
      });
    },
    _onFieldTypeChange: function() {
      var formulaSection, i, isRelation, len, opt, ref, ref1, ref2, results, sel, sp, type;
      type = this.el.fieldType().value;
      isRelation = type === 'Relation';
      this.el.relTargetRow().classList.toggle('hidden', !isRelation);
      if ((ref = this.el.fieldNotNull().closest('label')) != null) {
        ref.classList.toggle('hidden', isRelation);
      }
      formulaSection = this.el.formulaBody().closest('.formula-section');
      if (formulaSection != null) {
        formulaSection.classList.toggle('hidden', isRelation);
      }
      if (isRelation) {
        // Populate target space selector
        sel = this.el.relToSpace();
        sel.innerHTML = '<option value="">Cible…</option>';
        ref1 = this._allSpaces || [];
        results = [];
        for (i = 0, len = ref1.length; i < len; i++) {
          sp = ref1[i];
          if (sp.id === ((ref2 = this._currentSpace) != null ? ref2.id : void 0)) {
            continue;
          }
          opt = document.createElement('option');
          opt.value = sp.id;
          opt.textContent = sp.name;
          results.push(sel.appendChild(opt));
        }
        return results;
      }
    },
    _resetFieldForm: function() {
      var formulaSection, ref;
      this._editingFieldId = null;
      this.el.fieldName().value = '';
      this.el.fieldType().value = 'String';
      this.el.fieldNotNull().checked = false;
      this.el.fieldFormula().value = '';
      this.el.fieldTriggerFields().value = '';
      if (this.el.formulaLanguage()) {
        this.el.formulaLanguage().value = 'lua';
      }
      document.querySelector('input[name="formula-type"][value="none"]').checked = true;
      this.el.formulaBody().classList.add('hidden');
      this.el.triggerFieldsRow().classList.add('hidden');
      this.el.relTargetRow().classList.add('hidden');
      if ((ref = this.el.fieldNotNull().closest('label')) != null) {
        ref.classList.remove('hidden');
      }
      formulaSection = this.el.formulaBody().closest('.formula-section');
      if (formulaSection != null) {
        formulaSection.classList.remove('hidden');
      }
      this.el.fieldAddBtn().textContent = 'Ajouter';
      return this.el.fieldCancelBtn().classList.add('hidden');
    },
    renderFieldsList: function() {
      var fields, ul;
      if (!this._currentSpace) {
        return;
      }
      ul = this.el.fieldsList();
      ul.innerHTML = '';
      fields = this._currentSpace.fields || [];
      // Fetch relations and render everything in one shot
      return Spaces.listRelations(this._currentSpace.id).then((relations) => {
        var badge, del, dragSrc, editBtn, f, fb, handle, i, j, k, langLabel, len, len1, len2, li, name, r, ref, ref1, rel, relMap, req, results, sp, spaceMap, targetName, triggerDesc;
        // Build a map: fromFieldId → relation (with target space name resolved)
        relMap = {};
        ref = relations || [];
        for (i = 0, len = ref.length; i < len; i++) {
          r = ref[i];
          relMap[r.fromFieldId] = r;
        }
        // Resolve target space names from _allSpaces
        spaceMap = {};
        ref1 = this._allSpaces || [];
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          sp = ref1[j];
          spaceMap[sp.id] = sp.name;
        }
        if (fields.length === 0) {
          li = document.createElement('li');
          li.textContent = 'Aucun champ défini.';
          li.style.color = '#aaa';
          ul.appendChild(li);
          return;
        }
        dragSrc = null;
        results = [];
        for (k = 0, len2 = fields.length; k < len2; k++) {
          f = fields[k];
          li = document.createElement('li');
          li.draggable = true;
          li.dataset.fieldId = f.id;
          li.style.cursor = 'grab';
          handle = document.createElement('span');
          handle.textContent = '⠿';
          handle.title = 'Glisser pour réordonner';
          handle.style.cssText = 'margin-right:.4rem;color:#888;cursor:grab;user-select:none;';
          rel = relMap[f.id];
          badge = document.createElement('span');
          badge.className = 'field-type-badge';
          if (rel) {
            targetName = spaceMap[rel.toSpaceId] || rel.toSpaceId;
            badge.textContent = `→ ${targetName}`;
            badge.title = `Relation vers ${targetName}`;
          } else {
            badge.textContent = f.fieldType;
          }
          name = document.createElement('span');
          name.textContent = ` ${f.name} `;
          name.style.flex = '1';
          if (f.notNull) {
            req = document.createElement('span');
            req.className = 'field-required';
            req.title = 'Requis';
            req.textContent = '*';
            name.appendChild(req);
          }
          if (f.formula && f.formula !== '' && !rel) {
            fb = document.createElement('span');
            langLabel = f.language === 'moonscript' ? ' [moon]' : '';
            if (f.triggerFields) {
              fb.className = 'field-trigger-badge';
              triggerDesc = f.triggerFields.length === 0 ? 'création' : f.triggerFields[0] === '*' ? 'tout changement' : f.triggerFields.join(', ');
              fb.textContent = '⚡';
              fb.title = `Trigger formula${langLabel} (${triggerDesc}) : ${f.formula}`;
            } else {
              fb.className = 'field-formula-badge';
              fb.textContent = 'λ';
              fb.title = `Colonne calculée${langLabel} : ${f.formula}`;
            }
            name.appendChild(fb);
          }
          // Edit button (not for Sequence fields)
          editBtn = document.createElement('button');
          editBtn.textContent = '✎';
          editBtn.title = 'Modifier ce champ';
          editBtn.style.cssText = 'background:none;border:none;cursor:pointer;color:#888;font-size:.9rem;margin-left:.2rem;';
          ((field, relation) => {
            return editBtn.addEventListener('click', () => {
              var tf;
              this._editingFieldId = field.id;
              this.el.fieldAddBtn().textContent = 'Mettre à jour';
              this.el.fieldCancelBtn().classList.remove('hidden');
              this.el.fieldName().value = field.name;
              if (relation) {
                // Editing a relation field: show only Cible
                this.el.fieldType().value = 'Relation';
                this._onFieldTypeChange();
                this.el.relToSpace().value = relation.toSpaceId;
              } else {
                this.el.fieldType().value = field.fieldType;
                this._onFieldTypeChange();
                this.el.fieldNotNull().checked = field.notNull;
                if (field.formula && field.formula !== '') {
                  if (field.triggerFields) {
                    document.querySelector('input[name="formula-type"][value="trigger"]').checked = true;
                    this.el.triggerFieldsRow().classList.remove('hidden');
                    tf = field.triggerFields;
                    this.el.fieldTriggerFields().value = tf.length === 0 ? '' : tf[0] === '*' ? '*' : tf.join(', ');
                  } else {
                    document.querySelector('input[name="formula-type"][value="formula"]').checked = true;
                  }
                  this.el.formulaBody().classList.remove('hidden');
                  this.el.fieldFormula().value = field.formula;
                  if (this.el.formulaLanguage()) {
                    this.el.formulaLanguage().value = field.language || 'lua';
                  }
                } else {
                  document.querySelector('input[name="formula-type"][value="none"]').checked = true;
                  this.el.formulaBody().classList.add('hidden');
                }
              }
              return this.el.fieldName().focus();
            });
          })(f, rel);
          del = document.createElement('button');
          del.textContent = '✕';
          del.title = 'Supprimer ce champ';
          del.style.cssText = 'margin-left:.2rem;background:none;border:none;cursor:pointer;color:#aaa;font-size:.9rem;';
          ((fieldId, fieldName, relation) => {
            return del.addEventListener('click', () => {
              var doDelete;
              if (!confirm(`Supprimer le champ « ${fieldName} » ?`)) {
                return;
              }
              doDelete = () => {
                return GQL.mutate(REMOVE_FIELD, {fieldId}).then(() => {
                  return Spaces.getWithFields(this._currentSpace.id).then((full) => {
                    this._currentSpace = full;
                    this._syncSpaceFields(full);
                    this.renderFieldsList();
                    return this._mountDataView(full);
                  });
                }).catch(function(err) {
                  return alert(`Erreur : ${err.message}`);
                });
              };
              if (relation) {
                return Spaces.deleteRelation(relation.id).then(doDelete).catch(function(err) {
                  return alert(`Erreur : ${err.message}`);
                });
              } else {
                return doDelete();
              }
            });
          })(f.id, f.name, rel);
          li.appendChild(handle);
          li.appendChild(badge);
          li.appendChild(name);
          li.appendChild(editBtn);
          li.appendChild(del);
          // Drag events
          li.addEventListener('dragstart', function(e) {
            dragSrc = this;
            e.dataTransfer.effectAllowed = 'move';
            e.dataTransfer.setData('text/plain', this.dataset.fieldId);
            return setTimeout((() => {
              return this.classList.add('dragging');
            }), 0);
          });
          li.addEventListener('dragend', function() {
            this.classList.remove('dragging');
            return ul.querySelectorAll('li').forEach(function(el) {
              return el.classList.remove('drag-over');
            });
          });
          li.addEventListener('dragover', function(e) {
            e.preventDefault();
            e.dataTransfer.dropEffect = 'move';
            ul.querySelectorAll('li').forEach(function(el) {
              return el.classList.remove('drag-over');
            });
            if (this !== dragSrc) {
              return this.classList.add('drag-over');
            }
          });
          li.addEventListener('drop', (e) => {
            var insertBefore, newOrder, rect, target;
            e.preventDefault();
            target = e.currentTarget;
            if (dragSrc === target) {
              return;
            }
            rect = target.getBoundingClientRect();
            insertBefore = e.clientY < rect.top + rect.height / 2;
            if (insertBefore) {
              ul.insertBefore(dragSrc, target);
            } else {
              target.after(dragSrc);
            }
            newOrder = Array.from(ul.querySelectorAll('li')).map(function(el) {
              return el.dataset.fieldId;
            });
            return GQL.mutate(REORDER_FIELDS, {
              spaceId: this._currentSpace.id,
              fieldIds: newOrder
            }).then((res) => {
              this._currentSpace.fields = res.reorderFields;
              this._syncSpaceFields(this._currentSpace);
              this.renderFieldsList();
              return this._mountDataView(this._currentSpace);
            }).catch(function(err) {
              return console.error('reorderFields', err);
            });
          });
          results.push(ul.appendChild(li));
        }
        return results;
      });
    }
  };

  // ── Entry point ────────────────────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', function() {
    GQL.loadToken();
    App.init();
    return Auth.restoreSession().then(function(user) {
      if (user) {
        App.showMain(user);
        return App._loadAll();
      }
    }).catch(function() {
      return GQL.clearToken();
    });
  });

}).call(this);
