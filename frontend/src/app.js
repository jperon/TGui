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
    _localeListenerBound: false,
    _t: function(key, vars = {}) {
      var ref;
      if ((ref = window.I18N) != null ? ref.t : void 0) {
        return window.I18N.t(key, vars);
      } else {
        return key;
      }
    },
    _err: function(err, key = 'common.error') {
      return `${this._t(key)} : ${err.message}`;
    },
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
      currentUserBtn: function() {
        return document.getElementById('current-user-btn');
      },
      userMenu: function() {
        return document.getElementById('user-menu');
      },
      changePasswordBtn: function() {
        return document.getElementById('change-password-btn');
      },
      logoutBtn: function() {
        return document.getElementById('logout-btn');
      },
      langFrBtn: function() {
        return document.getElementById('lang-fr-btn');
      },
      langEnBtn: function() {
        return document.getElementById('lang-en-btn');
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
      adminSidebarSection: function() {
        return document.getElementById('admin-sidebar-section');
      },
      adminNavUsers: function() {
        return document.getElementById('admin-nav-users');
      },
      adminNavGroups: function() {
        return document.getElementById('admin-nav-groups');
      },
      adminNavSnapshot: function() {
        return document.getElementById('admin-nav-snapshot');
      },
      dataToolbar: function() {
        return document.getElementById('data-toolbar');
      },
      dataTitle: function() {
        return document.getElementById('data-title');
      },
      formulaFilterInput: function() {
        return document.getElementById('formula-filter-input');
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
      fieldChangeTypeBtn: function() {
        return document.getElementById('field-change-type-btn');
      },
      fieldReprFormula: function() {
        return document.getElementById('field-repr-formula');
      },
      relTargetRow: function() {
        return document.getElementById('rel-target-row');
      },
      relToSpace: function() {
        return document.getElementById('rel-to-space');
      },
      relReprRow: function() {
        return document.getElementById('rel-repr-row');
      },
      relReprFormula: function() {
        return document.getElementById('rel-repr-formula');
      },
      // Change type dialog
      changeTypeDialog: function() {
        return document.getElementById('change-type-dialog');
      },
      changeTypeFieldName: function() {
        return document.getElementById('change-type-field-name');
      },
      changeTypeSelect: function() {
        return document.getElementById('change-type-select');
      },
      changeTypeLang: function() {
        return document.getElementById('change-type-lang');
      },
      changeTypeFormula: function() {
        return document.getElementById('change-type-formula');
      },
      changeTypeError: function() {
        return document.getElementById('change-type-error');
      },
      changeTypeConfirmBtn: function() {
        return document.getElementById('change-type-confirm-btn');
      },
      changeTypeCancelBtn: function() {
        return document.getElementById('change-type-cancel-btn');
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
      yamlDeleteBtn: function() {
        return document.getElementById('yaml-delete-btn');
      },
      // YAML modal (CodeMirror)
      yamlModal: function() {
        return document.getElementById('yaml-modal');
      },
      yamlModalTitle: function() {
        return document.getElementById('yaml-modal-title');
      },
      yamlModalSaveBtn: function() {
        return document.getElementById('yaml-modal-save-btn');
      },
      yamlModalCloseBtn: function() {
        return document.getElementById('yaml-modal-close-btn');
      },
      yamlModalPreviewBtn: function() {
        return document.getElementById('yaml-modal-preview-btn');
      },
      // Formula modal (CodeMirror)
      formulaModal: function() {
        return document.getElementById('formula-modal');
      },
      formulaModalApplyBtn: function() {
        return document.getElementById('formula-modal-apply-btn');
      },
      formulaModalCloseBtn: function() {
        return document.getElementById('formula-modal-close-btn');
      },
      welcome: function() {
        return document.getElementById('welcome');
      },
      contentRow: function() {
        return document.getElementById('content-row');
      },
      adminPanel: function() {
        return document.getElementById('admin-panel');
      },
      adminUsersSection: function() {
        return document.getElementById('admin-users-section');
      },
      adminGroupsSection: function() {
        return document.getElementById('admin-groups-section');
      },
      adminSnapshotSection: function() {
        return document.getElementById('admin-snapshot-section');
      },
      adminUsersList: function() {
        return document.getElementById('admin-users-list');
      },
      adminGroupsList: function() {
        return document.getElementById('admin-groups-list');
      },
      adminCreateUserBtn: function() {
        return document.getElementById('admin-create-user-btn');
      },
      adminCreateGroupBtn: function() {
        return document.getElementById('admin-create-group-btn');
      },
      adminNavSnapshot: function() {
        return document.getElementById('admin-nav-snapshot');
      },
      snapshotExportSchemaBtn: function() {
        return document.getElementById('snapshot-export-schema-btn');
      },
      snapshotExportFullBtn: function() {
        return document.getElementById('snapshot-export-full-btn');
      },
      snapshotFileInput: function() {
        return document.getElementById('snapshot-file-input');
      },
      snapshotFileName: function() {
        return document.getElementById('snapshot-file-name');
      },
      snapshotDiffBox: function() {
        return document.getElementById('snapshot-diff-box');
      },
      snapshotDiffContent: function() {
        return document.getElementById('snapshot-diff-content');
      },
      snapshotImportError: function() {
        return document.getElementById('snapshot-import-error');
      },
      snapshotImportConfirmBtn: function() {
        return document.getElementById('snapshot-import-confirm-btn');
      },
      snapshotImportResult: function() {
        return document.getElementById('snapshot-import-result');
      },
      defaultPasswordWarning: function() {
        return document.getElementById('default-password-warning');
      },
      warningChangePasswordBtn: function() {
        return document.getElementById('warning-change-password-btn');
      },
      // Dialog: changement de mot de passe
      changePasswordDialog: function() {
        return document.getElementById('change-password-dialog');
      },
      cpCurrent: function() {
        return document.getElementById('cp-current');
      },
      cpNew: function() {
        return document.getElementById('cp-new');
      },
      cpConfirm: function() {
        return document.getElementById('cp-confirm');
      },
      cpError: function() {
        return document.getElementById('cp-error');
      },
      cpSubmitBtn: function() {
        return document.getElementById('cp-submit-btn');
      },
      cpCancelBtn: function() {
        return document.getElementById('cp-cancel-btn');
      },
      // Dialog: créer utilisateur
      createUserDialog: function() {
        return document.getElementById('create-user-dialog');
      },
      cuUsername: function() {
        return document.getElementById('cu-username');
      },
      cuEmail: function() {
        return document.getElementById('cu-email');
      },
      cuPassword: function() {
        return document.getElementById('cu-password');
      },
      cuError: function() {
        return document.getElementById('cu-error');
      },
      cuSubmitBtn: function() {
        return document.getElementById('cu-submit-btn');
      },
      cuCancelBtn: function() {
        return document.getElementById('cu-cancel-btn');
      },
      // Dialog: créer groupe
      createGroupDialog: function() {
        return document.getElementById('create-group-dialog');
      },
      cgName: function() {
        return document.getElementById('cg-name');
      },
      cgDescription: function() {
        return document.getElementById('cg-description');
      },
      cgError: function() {
        return document.getElementById('cg-error');
      },
      cgSubmitBtn: function() {
        return document.getElementById('cg-submit-btn');
      },
      cgCancelBtn: function() {
        return document.getElementById('cg-cancel-btn');
      }
    },
    // ── Bootstrap ───────────────────────────────────────────────────────────────
    init: function() {
      var ref;
      if ((ref = window.I18N) != null) {
        if (typeof ref.init === "function") {
          ref.init();
        }
      }
      this._bindLocaleChange();
      this._bindLogin();
      this._bindSidebar();
      this._bindDataToolbar();
      this._bindFieldsPanel();
      this._bindYamlEditor();
      return this._applyI18nDynamic();
    },
    _bindLocaleChange: function() {
      if (this._localeListenerBound) {
        return;
      }
      this._localeListenerBound = true;
      return window.addEventListener('i18n:locale-changed', () => {
        return this._applyI18nDynamic();
      });
    },
    _applySidebarState: function() {
      var spBtn, spList;
      if (localStorage.getItem('tdb_menu_state') === 'collapsed') {
        this.el.main().classList.add('sidebar-collapsed');
      } else {
        this.el.main().classList.remove('sidebar-collapsed');
      }
      spList = this.el.spaceList();
      spBtn = document.getElementById('spaces-toggle-btn');
      if (localStorage.getItem('tdb_spaces_collapsed') === 'true') {
        spList.classList.add('hidden');
        return spBtn != null ? spBtn.classList.add('collapsed') : void 0;
      } else {
        spList.classList.remove('hidden');
        return spBtn != null ? spBtn.classList.remove('collapsed') : void 0;
      }
    },
    _applyI18nDynamic: function() {
      var ref;
      return (ref = this.el.fieldAddBtn()) != null ? ref.textContent = this._editingFieldId ? this._t('ui.fields.update') : this._t('ui.fields.add') : void 0;
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
      this.el.currentUserBtn().textContent = user.username;
      if (Auth.isAdmin()) {
        this.el.adminSidebarSection().classList.remove('hidden');
      } else {
        this.el.adminSidebarSection().classList.add('hidden');
      }
      // Bandeau avertissement si admin avec mot de passe par défaut
      if (user.username === 'admin' && !localStorage.getItem('tdb_password_changed')) {
        return this.el.defaultPasswordWarning().classList.remove('hidden');
      } else {
        return this.el.defaultPasswordWarning().classList.add('hidden');
      }
    },
    // ── Sidebar ─────────────────────────────────────────────────────────────────
    _bindSidebar: function() {
      var ref, ref1, ref2, ref3;
      this.el.newSpaceBtn().addEventListener('click', async() => {
        var name;
        name = (await tdbPrompt(this._t('ui.prompts.newSpace')));
        if (!(name != null ? name.trim() : void 0)) {
          return;
        }
        return Spaces.create(name.trim()).then(() => {
          return this._loadAll();
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      });
      this.el.newViewBtn().addEventListener('click', async() => {
        var name;
        name = (await tdbPrompt(this._t('ui.prompts.newView')));
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
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      });
      // Gestion de la sidebar repliable
      if ((ref = document.getElementById('sidebar-toggle')) != null) {
        ref.addEventListener('click', () => {
          var isCollapsed, mainEl;
          mainEl = this.el.main();
          isCollapsed = mainEl.classList.contains('sidebar-collapsed');
          if (isCollapsed) {
            mainEl.classList.remove('sidebar-collapsed');
            return localStorage.removeItem('tdb_menu_state');
          } else {
            mainEl.classList.add('sidebar-collapsed');
            return localStorage.setItem('tdb_menu_state', 'collapsed');
          }
        });
      }
      // Gestion de la section Données (Espaces)
      if ((ref1 = document.getElementById('spaces-toggle-btn')) != null) {
        ref1.addEventListener('click', () => {
          var isHidden, spBtn, spList;
          spList = this.el.spaceList();
          spBtn = document.getElementById('spaces-toggle-btn');
          isHidden = spList.classList.contains('hidden');
          if (isHidden) {
            spList.classList.remove('hidden');
            spBtn.classList.remove('collapsed');
            return localStorage.setItem('tdb_spaces_collapsed', 'false');
          } else {
            spList.classList.add('hidden');
            spBtn.classList.add('collapsed');
            return localStorage.setItem('tdb_spaces_collapsed', 'true');
          }
        });
      }
      // Appliquer l'état par défaut au chargement
      this._applySidebarState();
      // Menu profil utilisateur
      this.el.currentUserBtn().addEventListener('click', () => {
        var menu;
        menu = this.el.userMenu();
        return menu.classList.toggle('hidden');
      });
      document.addEventListener('click', (e) => {
        if (!(this.el.currentUserBtn().contains(e.target) || this.el.userMenu().contains(e.target))) {
          return this.el.userMenu().classList.add('hidden');
        }
      });
      this.el.changePasswordBtn().addEventListener('click', () => {
        this.el.userMenu().classList.add('hidden');
        return this._openChangePasswordDialog();
      });
      this.el.logoutBtn().addEventListener('click', () => {
        return Auth.logout();
      });
      if ((ref2 = this.el.langFrBtn()) != null) {
        ref2.addEventListener('click', () => {
          var ref3;
          return (ref3 = window.I18N) != null ? ref3.setLocale('fr') : void 0;
        });
      }
      if ((ref3 = this.el.langEnBtn()) != null) {
        ref3.addEventListener('click', () => {
          var ref4;
          return (ref4 = window.I18N) != null ? ref4.setLocale('en') : void 0;
        });
      }
      // Navigation admin
      this.el.adminNavUsers().addEventListener('click', () => {
        return this._showAdminPanel('users');
      });
      this.el.adminNavGroups().addEventListener('click', () => {
        return this._showAdminPanel('groups');
      });
      this.el.adminNavSnapshot().addEventListener('click', () => {
        return this._showAdminPanel('snapshot');
      });
      // Bandeau d'avertissement
      this.el.warningChangePasswordBtn().addEventListener('click', () => {
        return this._openChangePasswordDialog();
      });
      this._bindChangePasswordDialog();
      this._bindCreateUserDialog();
      this._bindCreateGroupDialog();
      return this._bindSnapshotPanel();
    },
    // ── Load everything ─────────────────────────────────────────────────────────
    _loadAll: function() {
      return Promise.all([this.loadSpaces(), this.loadCustomViews()]).then(() => {
        return this._restoreFromHash();
      });
    },
    // ── Panel administration ─────────────────────────────────────────────────────
    _showAdminPanel: function(section = 'users') {
      this.el.dataToolbar().classList.add('hidden');
      this.el.contentRow().classList.add('hidden');
      this.el.welcome().classList.add('hidden');
      this.el.yamlEditorPanel().classList.add('hidden');
      this.el.adminPanel().classList.remove('hidden');
      this.el.adminUsersSection().classList.add('hidden');
      this.el.adminGroupsSection().classList.add('hidden');
      this.el.adminSnapshotSection().classList.add('hidden');
      if (section === 'users') {
        this.el.adminUsersSection().classList.remove('hidden');
        return this._loadAdminUsers();
      } else if (section === 'groups') {
        this.el.adminGroupsSection().classList.remove('hidden');
        return this._loadAdminGroups();
      } else {
        return this.el.adminSnapshotSection().classList.remove('hidden');
      }
    },
    _hideAdminPanel: function() {
      return this.el.adminPanel().classList.add('hidden');
    },
    _loadAdminUsers: function() {
      return Auth.listUsers().then((users) => {
        var btnPwd, groupNames, i, len, li, u, ul;
        ul = this.el.adminUsersList();
        ul.innerHTML = '';
        for (i = 0, len = users.length; i < len; i++) {
          u = users[i];
          li = document.createElement('li');
          li.className = 'admin-list-item';
          groupNames = (u.groups || []).map(function(g) {
            return g.name;
          }).join(', ') || '—';
          li.innerHTML = `<span class='admin-item-name'>${u.username}</span><span class='admin-item-meta'>${groupNames}</span>`;
          // Bouton changer mot de passe
          btnPwd = document.createElement('button');
          btnPwd.className = 'toolbar-btn';
          btnPwd.textContent = '🔑';
          btnPwd.title = this._t('ui.admin.pwdBtnTitle');
          btnPwd.addEventListener('click', async() => {
            var newPwd, uid;
            uid = u.id;
            newPwd = (await tdbPrompt(this._t('ui.prompts.newPasswordFor', {
              username: u.username
            })));
            if (!(newPwd != null ? newPwd.trim() : void 0)) {
              return;
            }
            return GQL.mutate('mutation SetPwd($uid: ID!, $pwd: String!) { adminSetPassword(userId: $uid, newPassword: $pwd) }', {
              uid,
              pwd: newPwd
            }).then(() => {
              return tdbAlert(this._t('ui.alerts.passwordChanged'), 'info');
            }).catch((err) => {
              return tdbAlert(this._err(err), 'error');
            });
          });
          li.appendChild(btnPwd);
          ul.appendChild(li);
        }
        // Bouton créer
        return this.el.adminCreateUserBtn().onclick = () => {
          return this.el.createUserDialog().classList.remove('hidden');
        };
      }).catch((err) => {
        return tdbAlert(this._err(err), 'error');
      });
    },
    _loadAdminGroups: function() {
      return Auth.listGroups().then((groups) => {
        var btnDel, g, i, len, li, memberNames, ul;
        ul = this.el.adminGroupsList();
        ul.innerHTML = '';
        for (i = 0, len = groups.length; i < len; i++) {
          g = groups[i];
          li = document.createElement('li');
          li.className = 'admin-list-item';
          memberNames = (g.members || []).map(function(m) {
            return m.username;
          }).join(', ') || '—';
          li.innerHTML = `<span class='admin-item-name'>${g.name}</span><span class='admin-item-meta'>${memberNames}</span>`;
          // Bouton supprimer groupe
          if (g.name !== 'admin') {
            btnDel = document.createElement('button');
            btnDel.className = 'toolbar-btn toolbar-btn--icon toolbar-btn--danger';
            btnDel.textContent = '🗑';
            btnDel.title = this._t('ui.admin.deleteGroupTitle');
            btnDel.addEventListener('click', async() => {
              var gid, gname;
              gid = g.id;
              gname = g.name;
              if (!(await tdbConfirm(this._t('ui.confirms.deleteGroup', {
                name: gname
              })))) {
                return;
              }
              return Auth.deleteGroup(gid).then(() => {
                return this._loadAdminGroups();
              }).catch((err) => {
                return tdbAlert(this._err(err), 'error');
              });
            });
            li.appendChild(btnDel);
          }
          ul.appendChild(li);
        }
        return this.el.adminCreateGroupBtn().onclick = () => {
          return this.el.createGroupDialog().classList.remove('hidden');
        };
      }).catch((err) => {
        return tdbAlert(this._err(err), 'error');
      });
    },
    // ── Dialog: changement de mot de passe ──────────────────────────────────────
    _openChangePasswordDialog: function() {
      this.el.cpCurrent().value = '';
      this.el.cpNew().value = '';
      this.el.cpConfirm().value = '';
      this.el.cpError().textContent = '';
      return this.el.changePasswordDialog().classList.remove('hidden');
    },
    _bindChangePasswordDialog: function() {
      this.el.cpCancelBtn().addEventListener('click', () => {
        return this.el.changePasswordDialog().classList.add('hidden');
      });
      this.el.changePasswordDialog().addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          this.el.cpSubmitBtn().click();
        }
        if (e.key === 'Escape') {
          return this.el.changePasswordDialog().classList.add('hidden');
        }
      });
      return this.el.cpSubmitBtn().addEventListener('click', () => {
        var confirm, current, nw;
        current = this.el.cpCurrent().value;
        nw = this.el.cpNew().value;
        confirm = this.el.cpConfirm().value;
        this.el.cpError().textContent = '';
        if (!(current && nw)) {
          this.el.cpError().textContent = this._t('ui.validation.requiredAllFields');
          return;
        }
        if (nw !== confirm) {
          this.el.cpError().textContent = this._t('ui.validation.newPasswordsMismatch');
          return;
        }
        return Auth.changePassword(current, nw).then((ok) => {
          if (ok) {
            localStorage.setItem('tdb_password_changed', '1');
            this.el.changePasswordDialog().classList.add('hidden');
            this.el.defaultPasswordWarning().classList.add('hidden');
            return tdbAlert(this._t('ui.alerts.passwordChangedSuccess'), 'info');
          } else {
            return this.el.cpError().textContent = this._t('ui.validation.currentPasswordIncorrect');
          }
        }).catch((err) => {
          return this.el.cpError().textContent = this._err(err);
        });
      });
    },
    // ── Dialog: créer utilisateur ─────────────────────────────────────────────
    _bindCreateUserDialog: function() {
      this.el.cuCancelBtn().addEventListener('click', () => {
        return this.el.createUserDialog().classList.add('hidden');
      });
      return this.el.cuSubmitBtn().addEventListener('click', () => {
        var email, password, username;
        username = this.el.cuUsername().value.trim();
        email = this.el.cuEmail().value.trim();
        password = this.el.cuPassword().value;
        this.el.cuError().textContent = '';
        if (!(username && password)) {
          this.el.cuError().textContent = this._t('ui.validation.usernamePasswordRequired');
          return;
        }
        return Auth.createUser(username, email || null, password).then(() => {
          this.el.createUserDialog().classList.add('hidden');
          this.el.cuUsername().value = '';
          this.el.cuEmail().value = '';
          this.el.cuPassword().value = '';
          return this._loadAdminUsers();
        }).catch((err) => {
          return this.el.cuError().textContent = this._err(err);
        });
      });
    },
    // ── Dialog: créer groupe ──────────────────────────────────────────────────
    _bindCreateGroupDialog: function() {
      this.el.cgCancelBtn().addEventListener('click', () => {
        return this.el.createGroupDialog().classList.add('hidden');
      });
      return this.el.cgSubmitBtn().addEventListener('click', () => {
        var description, name;
        name = this.el.cgName().value.trim();
        description = this.el.cgDescription().value.trim();
        this.el.cgError().textContent = '';
        if (!name) {
          this.el.cgError().textContent = this._t('ui.validation.groupNameRequired');
          return;
        }
        return Auth.createGroup(name, description).then(() => {
          this.el.createGroupDialog().classList.add('hidden');
          this.el.cgName().value = '';
          this.el.cgDescription().value = '';
          return this._loadAdminGroups();
        }).catch((err) => {
          return this.el.cgError().textContent = this._err(err);
        });
      });
    },
    // ── Snapshot export / import ─────────────────────────────────────────────────
    _bindSnapshotPanel: function() {
      var _doExport;
      this._snapshotYaml = null;
      // ── Export ──────────────────────────────────────────────────────────────────
      _doExport = (includeData) => {
        return GQL.query(`query($d: Boolean!) { exportSnapshot(includeData: $d) }`, {
          d: includeData
        }).then(function(data) {
          var a, blob, fname, url, yaml;
          yaml = data.exportSnapshot;
          fname = includeData ? 'backup.tdb.yaml' : 'schema.tdb.yaml';
          blob = new Blob([yaml], {
            type: 'text/yaml'
          });
          url = URL.createObjectURL(blob);
          a = document.createElement('a');
          a.href = url;
          a.download = fname;
          a.click();
          return URL.revokeObjectURL(url);
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      };
      this.el.snapshotExportSchemaBtn().addEventListener('click', () => {
        return _doExport(false);
      });
      this.el.snapshotExportFullBtn().addEventListener('click', () => {
        return _doExport(true);
      });
      // ── Import — file selection → diff ──────────────────────────────────────────
      this.el.snapshotFileInput().addEventListener('change', (e) => {
        var file, reader;
        file = e.target.files[0];
        if (!file) {
          return;
        }
        this.el.snapshotFileName().textContent = file.name;
        this.el.snapshotDiffBox().classList.add('hidden');
        this.el.snapshotImportResult().classList.add('hidden');
        this.el.snapshotImportError().classList.add('hidden');
        reader = new FileReader();
        reader.onload = (ev) => {
          this._snapshotYaml = ev.target.result;
          return GQL.query(`query($y: String!) { diffSnapshot(yaml: $y) {
  spacesToCreate spacesToDelete
  fieldsToCreate { space field oldType newType }
  fieldsToDelete { space field oldType newType }
  fieldsToChange { space field oldType newType }
  customViewsToCreate customViewsToUpdate
} }`, {
            y: this._snapshotYaml
          }).then((data) => {
            var diff;
            diff = data.diffSnapshot;
            this._renderSnapshotDiff(diff);
            return this.el.snapshotDiffBox().classList.remove('hidden');
          }).catch((err) => {
            this.el.snapshotImportError().textContent = this._err(err);
            return this.el.snapshotImportError().classList.remove('hidden');
          });
        };
        return reader.readAsText(file);
      });
      // ── Import — confirm ─────────────────────────────────────────────────────────
      return this.el.snapshotImportConfirmBtn().addEventListener('click', async() => {
        var mode, ref;
        if (!this._snapshotYaml) {
          return;
        }
        mode = ((ref = document.querySelector('input[name="snapshot-mode"]:checked')) != null ? ref.value : void 0) || 'merge';
        if (mode === 'replace') {
          if (!(await tdbConfirm(this._t('ui.confirms.replaceImport')))) {
            return;
          }
        }
        this.el.snapshotImportConfirmBtn().disabled = true;
        return GQL.mutate(`mutation($y: String!, $m: ImportMode!) {
  importSnapshot(yaml: $y, mode: $m) { ok created skipped errors }
}`, {
          y: this._snapshotYaml,
          m: mode
        }).then((data) => {
          var r, res;
          r = data.importSnapshot;
          this.el.snapshotImportConfirmBtn().disabled = false;
          this.el.snapshotDiffBox().classList.add('hidden');
          res = this.el.snapshotImportResult();
          res.classList.remove('hidden');
          if (r.ok) {
            res.className = 'snapshot-import-result snapshot-result-ok';
            res.innerHTML = this._t('ui.snapshot.importOk', {
              created: r.created,
              skipped: r.skipped
            });
          } else {
            res.className = 'snapshot-import-result snapshot-result-err';
            res.innerHTML = this._t('ui.snapshot.importErr', {
              created: r.created,
              skipped: r.skipped
            }) + '<br>' + r.errors.map(function(e) {
              return `<code>${e}</code>`;
            }).join('<br>');
          }
          if (r.ok || r.created > 0) {
            // Reload spaces/views to reflect changes
            return this._loadAll();
          }
        }).catch((err) => {
          this.el.snapshotImportConfirmBtn().disabled = false;
          this.el.snapshotImportError().textContent = this._err(err);
          return this.el.snapshotImportError().classList.remove('hidden');
        });
      });
    },
    _renderSnapshotDiff: function(diff) {
      var _section, c, noop, p;
      c = this.el.snapshotDiffContent();
      c.innerHTML = '';
      _section = function(title, items, cls) {
        var h, i, item, len, li, ul;
        if (!(items && items.length > 0)) {
          return;
        }
        h = document.createElement('h5');
        h.textContent = title;
        c.appendChild(h);
        ul = document.createElement('ul');
        ul.className = cls;
        for (i = 0, len = items.length; i < len; i++) {
          item = items[i];
          li = document.createElement('li');
          if (typeof item === 'string') {
            li.textContent = item;
          } else {
            // FieldDiff
            if (item.oldType && item.newType) {
              li.innerHTML = `<code>${item.space}.${item.field}</code> : <em>${item.oldType}</em> → <strong>${item.newType}</strong>`;
            } else if (item.newType) {
              li.innerHTML = this._t('ui.snapshot.fieldToCreate', item);
            } else {
              li.innerHTML = this._t('ui.snapshot.fieldToDelete', item);
            }
          }
          ul.appendChild(li);
        }
        return c.appendChild(ul);
      };
      noop = diff.spacesToCreate.length === 0 && diff.spacesToDelete.length === 0 && diff.fieldsToCreate.length === 0 && diff.fieldsToDelete.length === 0 && diff.fieldsToChange.length === 0 && diff.customViewsToCreate.length === 0 && diff.customViewsToUpdate.length === 0;
      if (noop) {
        p = document.createElement('p');
        p.className = 'snapshot-diff-noop';
        p.textContent = this._t('ui.snapshot.noop');
        return c.appendChild(p);
      } else {
        _section(this._t('ui.snapshot.sectionSpacesDelete'), diff.spacesToDelete, 'diff-list diff-delete');
        _section(this._t('ui.snapshot.sectionSpacesCreate'), diff.spacesToCreate, 'diff-list diff-create');
        _section(this._t('ui.snapshot.sectionFieldsDelete'), diff.fieldsToDelete, 'diff-list diff-delete');
        _section(this._t('ui.snapshot.sectionFieldsChange'), diff.fieldsToChange, 'diff-list diff-change');
        _section(this._t('ui.snapshot.sectionFieldsCreate'), diff.fieldsToCreate, 'diff-list diff-create');
        _section(this._t('ui.snapshot.sectionCustomViewsCreate'), diff.customViewsToCreate, 'diff-list diff-create');
        return _section(this._t('ui.snapshot.sectionCustomViewsUpdate'), diff.customViewsToUpdate, 'diff-list diff-change');
      }
    },
    // ── Hash-based navigation ────────────────────────────────────────────────────
    _restoreFromHash: function() {
      var cvItems, hash, i, len, li, m, results1, sp, spaceId, ul, viewId;
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
        results1 = [];
        for (i = 0, len = cvItems.length; i < len; i++) {
          li = cvItems[i];
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
    // ── Spaces (Données section) ─────────────────────────────────────────────────
    loadSpaces: function() {
      return Spaces.list().then((spaces) => {
        this._allSpaces = spaces;
        return this.renderSpaceList(spaces);
      }).catch((err) => {
        return tdbAlert(this._err(err), 'error');
      });
    },
    renderSpaceList: function(spaces) {
      var i, len, li, results1, sortedSpaces, sp, ul;
      ul = this.el.spaceList();
      ul.innerHTML = '';
      // Tri alphabétique insensible à la casse
      sortedSpaces = [...spaces].sort(function(a, b) {
        return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
      });
      results1 = [];
      for (i = 0, len = sortedSpaces.length; i < len; i++) {
        sp = sortedSpaces[i];
        li = document.createElement('li');
        li.textContent = sp.name;
        li.dataset.id = sp.id;
        ((sp) => {
          return li.addEventListener('click', () => {
            return this.selectSpace(sp);
          });
        })(sp);
        ul.appendChild(li);
        li.textContent = sp.name;
        li.dataset.id = sp.id;
        ((sp) => {
          return li.addEventListener('click', () => {
            return this.selectSpace(sp);
          });
        })(sp);
        results1.push(ul.appendChild(li));
      }
      return results1;
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
      // Hide admin panel
      this.el.adminPanel().classList.add('hidden');
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
      }).catch((err) => {
        return tdbAlert(this._err(err), 'error');
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
    _mountDataView: async function(space) {
      var container, input, ref, relations;
      if ((ref = this._activeDataView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container = this.el.gridContainer();
      relations = (await Spaces.listRelations(space.id));
      this._activeDataView = new DataView(container, space, null, relations);
      this._activeDataView.mount();
      // Reset filter bar
      input = this.el.formulaFilterInput();
      if (input) {
        input.value = '';
        return input.classList.remove('active');
      }
    },
    // ── Custom views (Vues section) ──────────────────────────────────────────────
    loadCustomViews: function() {
      return GQL.query(LIST_CUSTOM_VIEWS).then((data) => {
        return this.renderCustomViewList(data.customViews);
      }).catch((err) => {
        return tdbAlert(this._err(err), 'error');
      });
    },
    renderCustomViewList: function(views) {
      var base, curr, cv, dictName, i, j, len, len1, parts, ref, ref1, renderTree, tree, ul;
      ul = this.el.customViewList();
      ul.innerHTML = '';
      
      // 1. Grouper en arbre
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
        // Dossiers intermédiaires
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
        // Insertion terminale (on garde cv original mais avec le nom court)
        curr.items.push({
          cv: cv,
          shortName: parts[parts.length - 1]
        });
      }
      // 2. Fonction récursive de rendu
      renderTree = (node, containerEl, pathStr = "") => {
        var fName, fNode, folderLi, folderNames, fullPath, header, icon, item, k, l, len2, len3, li, lsKey, results1, sortedItems, subUl;
        // Trier les dossiers par ordre alphabétique
        folderNames = Object.keys(node.folders).sort(function(a, b) {
          return a.toLowerCase().localeCompare(b.toLowerCase());
        });
        for (k = 0, len2 = folderNames.length; k < len2; k++) {
          fName = folderNames[k];
          fNode = node.folders[fName];
          fullPath = pathStr ? `${pathStr}/${fName}` : fName;
          folderLi = document.createElement('li');
          folderLi.className = 'folder-item';
          
          // Header du dossier
          header = document.createElement('div');
          header.className = 'folder-header';
          icon = document.createElement('span');
          icon.className = 'folder-toggle-icon';
          icon.textContent = '▾';
          header.appendChild(icon);
          header.appendChild(document.createTextNode(` ${fName}`));
          folderLi.appendChild(header);
          
          // Liste déroulante
          subUl = document.createElement('ul');
          subUl.className = 'folder-children';
          folderLi.appendChild(subUl);
          
          // État du dossier dans le localStorage
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
        // Trier les items (vues)
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
          li.title = item.cv.name; // Le vrai nom complet sur hover
          ((cv) => {
            return li.addEventListener('click', (e) => {
              e.stopPropagation();
              return this.selectCustomView(cv);
            });
          })(item.cv);
          results1.push(containerEl.appendChild(li));
        }
        return results1;
      };
      return renderTree(tree, ul);
    },
    selectCustomView: function(cv) {
      var i, j, len, len1, li, panel, parent, ref, ref1, ref2, ref3;
      history.replaceState(null, '', `#view/${cv.id}`);
      this._currentCustomView = cv;
      ref = this.el.spaceList().querySelectorAll('li');
      // Deactivate space items
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = this.el.customViewList().querySelectorAll('.leaf-item');
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.toggle('active', li.dataset.id === cv.id);
        // Si active, on s'assure que les dossiers parents sont ouverts
        if (li.dataset.id === cv.id) {
          parent = li.parentElement;
          while (parent && parent.id !== 'custom-view-list') {
            if (parent.tagName === 'LI' && parent.classList.contains('folder-item')) {
              parent.classList.remove('collapsed');
            }
            // Sauvegarder l'état ouvert du parent dans le localStorage
            // (Peut être délicat de retrouver le nom exact du parent,
            // mais on a la classe 'collapsed' enlevée).
            parent = parent.parentElement;
          }
        }
      }
      this._currentSpace = null;
      if ((ref2 = this._activeDataView) != null) {
        if (typeof ref2.unmount === "function") {
          ref2.unmount();
        }
      }
      this._activeDataView = null;
      // Hide data grid area and admin panel
      this.el.dataToolbar().classList.add('hidden');
      this.el.fieldsPanel().classList.add('hidden');
      this.el.gridContainer().classList.add('hidden');
      this.el.welcome().classList.add('hidden');
      this.el.adminPanel().classList.add('hidden');
      this.el.contentRow().classList.remove('hidden');
      panel = this.el.yamlEditorPanel();
      panel.classList.remove('hidden');
      this.el.yamlViewName().textContent = cv.name;
      // If YAML exists, render preview; otherwise open the editor modal directly
      if ((ref3 = cv.yaml) != null ? ref3.trim() : void 0) {
        return this._renderCustomViewPreview(cv.yaml);
      } else {
        return this._openYamlModal();
      }
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
        return this._openYamlModal();
      });
      this.el.yamlDeleteBtn().addEventListener('click', async() => {
        var cv;
        cv = this._currentCustomView;
        if (!cv) {
          return;
        }
        if (!(await tdbConfirm(this._t('ui.confirms.deleteView', {
          name: cv.name
        })))) {
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
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      });
      this.el.yamlModalSaveBtn().addEventListener('click', () => {
        var cv, yaml;
        cv = this._currentCustomView;
        if (!cv) {
          return;
        }
        yaml = this._cmYaml.getValue();
        return GQL.mutate(UPDATE_CUSTOM_VIEW, {
          id: cv.id,
          input: {yaml}
        }).then((data) => {
          this._currentCustomView = data.updateCustomView;
          this.el.yamlModal().classList.add('hidden');
          this._renderCustomViewPreview(yaml);
          return this.loadCustomViews();
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      });
      this.el.yamlModalCloseBtn().addEventListener('click', () => {
        return this.el.yamlModal().classList.add('hidden');
      });
      return this.el.yamlModalPreviewBtn().addEventListener('click', () => {
        if (!this._cmYaml) {
          return;
        }
        return this._renderCustomViewPreview(this._cmYaml.getValue());
      });
    },
    _openYamlModal: function() {
      var cv;
      cv = this._currentCustomView;
      if (!cv) {
        return;
      }
      this.el.yamlModalTitle().textContent = cv.name;
      this.el.yamlModal().classList.remove('hidden');
      if (!this._cmYaml) {
        this._cmYaml = CodeMirror(document.getElementById('yaml-cm-editor'), {
          mode: 'yaml',
          theme: 'monokai',
          lineNumbers: true,
          lineWrapping: true,
          tabSize: 2,
          indentWithTabs: false
        });
        // When the user manually edits the YAML, re-sync the ERD builder and validate.
        // 'setValue' origin = programmatic; anything else = user input.
        this._cmYaml.on('change', (cm, change) => {
          var e, ref, ref1, ref2;
          if (!this._yamlValidMsg) {
            this._yamlValidMsg = document.getElementById('yaml-validation-msg');
          }
          // Programmatic setValue: clear any stale error and skip ERD sync
          if (change.origin === 'setValue') {
            if ((ref = this._yamlValidMsg) != null) {
              ref.classList.add('hidden');
            }
            return;
          }
          if ((ref1 = this._yamlBuilder) != null) {
            ref1.reloadFromYaml(cm.getValue());
          }
          try {
            // Live YAML validation feedback while user types
            jsyaml.load(cm.getValue());
            return (ref2 = this._yamlValidMsg) != null ? ref2.classList.add('hidden') : void 0;
          } catch (error) {
            e = error;
            if (this._yamlValidMsg) {
              this._yamlValidMsg.textContent = `YAML invalide : ${e.message}`;
              return this._yamlValidMsg.classList.remove('hidden');
            }
          }
        });
      }
      this._cmYaml.setValue(cv.yaml || '');
      setTimeout((() => {
        return this._cmYaml.refresh();
      }), 10);
      // Schema browser
      return this._loadAllRelations().then((relations) => {
        this._yamlBuilder = new YamlBuilder({
          container: document.getElementById('schema-browser'),
          allSpaces: this._allSpaces,
          allRelations: relations,
          initialYaml: cv.yaml || '',
          onChange: (yaml) => {
            var ref;
            return (ref = this._cmYaml) != null ? ref.setValue(yaml) : void 0;
          }
        });
        return this._yamlBuilder.mount();
      });
    },
    _loadAllRelations: function() {
      if (this._allRelations) {
        return Promise.resolve(this._allRelations);
      }
      return Promise.all(this._allSpaces.map(function(sp) {
        return Spaces.listRelations(sp.id);
      })).then((results) => {
        this._allRelations = results.reduce((function(a, b) {
          return a.concat(b);
        }), []);
        return this._allRelations;
      });
    },
    // ── Data toolbar ─────────────────────────────────────────────────────────────
    _bindDataToolbar: function() {
      this.el.deleteRowsBtn().addEventListener('click', () => {
        var ref;
        return (ref = this._activeDataView) != null ? ref.deleteSelected() : void 0;
      });
      // Formula filter input (debounced, sends to active DataView)
      this._formulaTimer = null;
      this.el.formulaFilterInput().addEventListener('input', (e) => {
        var val;
        clearTimeout(this._formulaTimer);
        val = e.target.value.trim();
        e.target.classList.toggle('active', val !== '');
        return this._formulaTimer = setTimeout(() => {
          var ref;
          return (ref = this._activeDataView) != null ? ref.setFormulaFilter(val) : void 0;
        }, 400);
      });
      this.el.deleteSpaceBtn().addEventListener('click', async() => {
        var name;
        if (!this._currentSpace) {
          return;
        }
        name = this._currentSpace.name;
        if (!(await tdbConfirm(this._t('ui.confirms.deleteSpace', {name})))) {
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
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      });
      return this.el.renameSpaceBtn().addEventListener('click', async() => {
        var newName;
        if (!this._currentSpace) {
          return;
        }
        newName = (await tdbPrompt(this._t('ui.prompts.renameSpace'), this._currentSpace.name));
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
        }).catch((err) => {
          return tdbAlert(this._err(err), 'error');
        });
      });
    },
    // ── Fields panel ─────────────────────────────────────────────────────────────
    _bindFieldsPanel: function() {
      var ref;
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
      // CodeMirror formula modal
      document.getElementById('formula-expand-btn').addEventListener('click', () => {
        var lang, ref;
        lang = ((ref = this.el.formulaLanguage()) != null ? ref.value : void 0) || 'lua';
        this.el.formulaModal().classList.remove('hidden');
        if (!this._cmFormula) {
          this._cmFormula = CodeMirror(document.getElementById('formula-cm-editor'), {
            mode: lang,
            theme: 'monokai',
            lineNumbers: true,
            lineWrapping: true,
            tabSize: 2,
            indentWithTabs: false
          });
        } else {
          this._cmFormula.setOption('mode', lang);
        }
        this._cmFormula.setValue(this.el.fieldFormula().value);
        return setTimeout((() => {
          return this._cmFormula.refresh();
        }), 10);
      });
      this.el.formulaModalApplyBtn().addEventListener('click', () => {
        if (this._cmFormula) {
          this.el.fieldFormula().value = this._cmFormula.getValue();
        }
        return this.el.formulaModal().classList.add('hidden');
      });
      this.el.formulaModalCloseBtn().addEventListener('click', () => {
        return this.el.formulaModal().classList.add('hidden');
      });
      // Sync CM mode when language selector changes
      if ((ref = this.el.formulaLanguage()) != null) {
        ref.addEventListener('change', () => {
          var ref1;
          return (ref1 = this._cmFormula) != null ? ref1.setOption('mode', this.el.formulaLanguage().value) : void 0;
        });
      }
      this.el.fieldCancelBtn().addEventListener('click', () => {
        return this._resetFieldForm();
      });
      // Change field type button
      this.el.fieldChangeTypeBtn().addEventListener('click', () => {
        var err, field, ref1;
        if (!this._editingFieldId) {
          return;
        }
        field = (((ref1 = this._currentSpace) != null ? ref1.fields : void 0) || []).find((f) => {
          return f.id === this._editingFieldId;
        });
        if (!field) {
          return;
        }
        this.el.changeTypeFieldName().textContent = `Champ : ${field.name} (type actuel : ${field.fieldType})`;
        this.el.changeTypeSelect().value = field.fieldType;
        this.el.changeTypeFormula().value = '';
        this.el.changeTypeLang().value = 'lua';
        err = this.el.changeTypeError();
        err.textContent = '';
        err.classList.add('hidden');
        return this.el.changeTypeDialog().classList.remove('hidden');
      });
      this.el.changeTypeCancelBtn().addEventListener('click', () => {
        return this.el.changeTypeDialog().classList.add('hidden');
      });
      this.el.changeTypeConfirmBtn().addEventListener('click', () => {
        var errEl, formula, lang, newType;
        if (!this._editingFieldId) {
          return;
        }
        newType = this.el.changeTypeSelect().value;
        formula = this.el.changeTypeFormula().value.trim() || null;
        lang = this.el.changeTypeLang().value;
        errEl = this.el.changeTypeError();
        errEl.classList.add('hidden');
        return Spaces.changeFieldType(this._editingFieldId, newType, formula, lang).then(() => {
          this.el.changeTypeDialog().classList.add('hidden');
          return Spaces.getWithFields(this._currentSpace.id).then((full) => {
            var field;
            this._currentSpace = full;
            this._syncSpaceFields(full);
            this.renderFieldsList();
            this._mountDataView(full);
            // Update the type selector in edit form to reflect change
            field = (full.fields || []).find((f) => {
              return f.id === this._editingFieldId;
            });
            if (field) {
              return this.el.fieldType().value = field.fieldType;
            }
          });
        }).catch((err) => {
          errEl.textContent = this._err(err);
          return errEl.classList.remove('hidden');
        });
      });
      return this.el.fieldAddBtn().addEventListener('click', () => {
        var editRelation, formula, formulaType, language, name, notNull, opts, raw, ref1, ref2, ref3, ref4, relReprFormula, reprFormula, s, toSpaceId, triggerFields, type, updatePromise;
        if (!this._currentSpace) {
          return;
        }
        name = this.el.fieldName().value.trim();
        type = this.el.fieldType().value;
        notNull = this.el.fieldNotNull().checked;
        if (!name) {
          this.el.fieldName().classList.add('input-error');
          this.el.fieldName().placeholder = this._t('ui.validation.groupNameRequired');
          this.el.fieldName().focus();
          return;
        }
        this.el.fieldName().classList.remove('input-error');
        this.el.fieldName().placeholder = this._t('ui.fields.namePlaceholder');
        if (this._editingFieldId) {
          // ── Update existing field ──────────────────────────────────────────
          formulaType = document.querySelector('input[name="formula-type"]:checked').value;
          opts = {name, notNull};
          if (formulaType !== 'none') {
            opts.formula = this.el.fieldFormula().value.trim() || null;
            opts.language = ((ref1 = this.el.formulaLanguage()) != null ? ref1.value : void 0) || 'lua';
            if (formulaType === 'trigger' && opts.formula) {
              raw = this.el.fieldTriggerFields().value.trim();
              if (raw === '*') {
                opts.triggerFields = ['*'];
              } else if (raw === '') {
                opts.triggerFields = [];
              } else {
                opts.triggerFields = (function() {
                  var i, len, ref2, results1;
                  ref2 = raw.split(',');
                  results1 = [];
                  for (i = 0, len = ref2.length; i < len; i++) {
                    s = ref2[i];
                    if (s.trim()) {
                      results1.push(s.trim());
                    }
                  }
                  return results1;
                })();
              }
            }
          } else {
            opts.formula = '';
            opts.triggerFields = null;
            opts.language = 'lua';
          }
          opts.reprFormula = ((ref2 = this.el.fieldReprFormula()) != null ? ref2.value.trim() : void 0) || '';
          editRelation = this._editingRelation;
          relReprFormula = this.el.relReprFormula().value.trim();
          updatePromise = Spaces.updateField(this._editingFieldId, opts);
          if (editRelation) {
            updatePromise = updatePromise.then(() => {
              return Spaces.updateRelation(editRelation.id, relReprFormula);
            });
          }
          updatePromise.then(() => {
            return Spaces.getWithFields(this._currentSpace.id).then((full) => {
              this._currentSpace = full;
              this._syncSpaceFields(full);
              this.renderFieldsList();
              return this._mountDataView(full);
            });
          }).catch((err) => {
            return tdbAlert(this._err(err), 'error');
          });
          return this._resetFieldForm();
        } else if (type === 'Relation') {
          // ── Create relation field ──────────────────────────────────────────
          toSpaceId = this.el.relToSpace().value;
          reprFormula = this.el.relReprFormula().value.trim();
          if (!toSpaceId) {
            return;
          }
          Spaces.getWithFields(toSpaceId).then((targetSpace) => {
            var idField;
            idField = (targetSpace.fields || []).find(function(f) {
              return f.fieldType === 'Sequence';
            });
            if (!idField) {
              tdbAlert(this._t('ui.alerts.targetNoSequence'), 'warn');
              return;
            }
            return Spaces.addField(this._currentSpace.id, name, 'Int', notNull, '').then((newField) => {
              return Spaces.createRelation(name, this._currentSpace.id, newField.id, toSpaceId, idField.id, reprFormula).then(() => {
                return Spaces.getWithFields(this._currentSpace.id).then((full) => {
                  this._currentSpace = full;
                  this._syncSpaceFields(full);
                  this.renderFieldsList();
                  return this._mountDataView(full);
                });
              }).catch((err) => {
                return tdbAlert(this._err(err), 'error');
              });
            }).catch((err) => {
              return tdbAlert(this._err(err), 'error');
            });
          });
          return this._resetFieldForm();
        } else {
          // ── Add new regular field ──────────────────────────────────────────
          formulaType = document.querySelector('input[name="formula-type"]:checked').value;
          formula = null;
          triggerFields = null;
          language = ((ref3 = this.el.formulaLanguage()) != null ? ref3.value : void 0) || 'lua';
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
                  var i, len, ref4, results1;
                  ref4 = raw.split(',');
                  results1 = [];
                  for (i = 0, len = ref4.length; i < len; i++) {
                    s = ref4[i];
                    if (s.trim()) {
                      results1.push(s.trim());
                    }
                  }
                  return results1;
                })();
              }
            }
          }
          reprFormula = ((ref4 = this.el.fieldReprFormula()) != null ? ref4.value.trim() : void 0) || null;
          Spaces.addField(this._currentSpace.id, name, type, notNull, '', formula, triggerFields, language, reprFormula).then(() => {
            return Spaces.getWithFields(this._currentSpace.id).then((full) => {
              this._currentSpace = full;
              this._syncSpaceFields(full);
              this.renderFieldsList();
              return this._mountDataView(full);
            });
          }).catch((err) => {
            return tdbAlert(this._err(err), 'error');
          });
          return this._resetFieldForm();
        }
      });
    },
    _onFieldTypeChange: function() {
      var formulaSection, i, isRelation, len, opt, ref, ref1, ref2, results1, sel, sp, type;
      type = this.el.fieldType().value;
      isRelation = type === 'Relation';
      this.el.relTargetRow().classList.toggle('hidden', !isRelation);
      this.el.relReprRow().classList.toggle('hidden', !isRelation);
      if ((ref = this.el.fieldNotNull().closest('label')) != null) {
        ref.classList.toggle('hidden', isRelation);
      }
      formulaSection = this.el.formulaBody().closest('.formula-section');
      if (formulaSection != null) {
        formulaSection.classList.toggle('hidden', isRelation);
      }
      if ((ref1 = document.getElementById('field-repr-section')) != null) {
        ref1.classList.toggle('hidden', isRelation);
      }
      if (isRelation) {
        // Populate target space selector
        sel = this.el.relToSpace();
        sel.innerHTML = '<option value="">Cible…</option>';
        ref2 = this._allSpaces || [];
        results1 = [];
        for (i = 0, len = ref2.length; i < len; i++) {
          sp = ref2[i];
          opt = document.createElement('option');
          opt.value = sp.id;
          opt.textContent = sp.name;
          results1.push(sel.appendChild(opt));
        }
        return results1;
      }
    },
    _resetFieldForm: function() {
      var formulaSection, ref;
      this._editingFieldId = null;
      this._editingRelation = null;
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
      this.el.relReprRow().classList.add('hidden');
      this.el.relReprFormula().value = '';
      if (this.el.fieldReprFormula()) {
        this.el.fieldReprFormula().value = '';
      }
      if ((ref = this.el.fieldNotNull().closest('label')) != null) {
        ref.classList.remove('hidden');
      }
      formulaSection = this.el.formulaBody().closest('.formula-section');
      if (formulaSection != null) {
        formulaSection.classList.remove('hidden');
      }
      this.el.formulaModal().classList.add('hidden');
      this.el.fieldAddBtn().textContent = this._t('ui.fields.add');
      this.el.fieldCancelBtn().classList.add('hidden');
      return this.el.fieldChangeTypeBtn().classList.add('hidden');
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
        var badge, del, dragSrc, editBtn, f, fb, handle, i, j, k, langLabel, len, len1, len2, li, name, r, ref, ref1, rel, relMap, req, results1, sp, spaceMap, targetName, triggerDesc;
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
          li.textContent = this._t('ui.fields.noneDefined');
          li.style.color = '#aaa';
          ul.appendChild(li);
          return;
        }
        dragSrc = null;
        results1 = [];
        for (k = 0, len2 = fields.length; k < len2; k++) {
          f = fields[k];
          li = document.createElement('li');
          li.draggable = true;
          li.dataset.fieldId = f.id;
          li.style.cursor = 'grab';
          handle = document.createElement('span');
          handle.textContent = '⠿';
          handle.title = this._t('ui.fields.dragToReorder');
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
              triggerDesc = f.triggerFields.length === 0 ? this._t('ui.fields.triggerCreation') : f.triggerFields[0] === '*' ? this._t('ui.fields.triggerAnyChange') : f.triggerFields.join(', ');
              fb.textContent = '⚡';
              fb.title = `Trigger formula${langLabel} (${triggerDesc}) : ${f.formula}`;
            } else {
              fb.className = 'field-formula-badge';
              fb.textContent = 'λ';
              fb.title = `${this._t('ui.fields.computedColumn')}${langLabel} : ${f.formula}`;
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
              this._editingRelation = relation || null;
              this.el.fieldAddBtn().textContent = this._t('ui.fields.update');
              this.el.fieldCancelBtn().classList.remove('hidden');
              this.el.fieldChangeTypeBtn().classList.remove('hidden');
              this.el.fieldName().value = field.name;
              if (relation) {
                // Editing a relation field: show Cible and repr formula
                this.el.fieldType().value = 'Relation';
                this._onFieldTypeChange();
                this.el.relToSpace().value = relation.toSpaceId;
                this.el.relReprFormula().value = relation.reprFormula || '';
                if (this.el.fieldReprFormula()) {
                  this.el.fieldReprFormula().value = '';
                }
              } else {
                this.el.fieldType().value = field.fieldType;
                this._onFieldTypeChange();
                this.el.fieldNotNull().checked = field.notNull;
                if (this.el.fieldReprFormula()) {
                  this.el.fieldReprFormula().value = field.reprFormula || '';
                }
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
            return del.addEventListener('click', async() => {
              var doDelete;
              if (!(await tdbConfirm(this._t('ui.confirms.deleteField', {
                name: fieldName
              })))) {
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
                }).catch((err) => {
                  return tdbAlert(this._err(err), 'error');
                });
              };
              if (relation) {
                return Spaces.deleteRelation(relation.id).then(doDelete).catch((err) => {
                  return tdbAlert(this._err(err), 'error');
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
            }).catch((err) => {
              return tdbAlert(this._err(err), 'error');
            });
          });
          results1.push(ul.appendChild(li));
        }
        return results1;
      });
    }
  };

  // ── Entry point ────────────────────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', function() {
    GQL.loadToken();
    App.init();
    // Le flash initial est évité par le script inline dans index.moon.
    return Auth.restoreSession().then(function(user) {
      if (user) {
        App.showMain(user);
        return App._loadAll();
      } else {
        return App.showLogin();
      }
    }).catch(function() {
      App.showLogin();
      return GQL.clearToken();
    });
  });

}).call(this);
