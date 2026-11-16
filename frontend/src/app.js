(function() {
  // app.coffee — main application bootstrap and UI orchestration.
  var CREATE_CUSTOM_VIEW, CREATE_WIDGET_PLUGIN, DELETE_CUSTOM_VIEW, DELETE_WIDGET_PLUGIN, LIST_CUSTOM_VIEWS, REMOVE_FIELD, REORDER_FIELDS, UPDATE_CUSTOM_VIEW, UPDATE_WIDGET_PLUGIN;

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

  CREATE_WIDGET_PLUGIN = `mutation CreateWidgetPlugin($input: CreateWidgetPluginInput!) {
  createWidgetPlugin(input: $input) {
    id
    name
    description
    scriptLanguage
    templateLanguage
    scriptCode
    templateCode
    updatedAt
  }
}`;

  UPDATE_WIDGET_PLUGIN = `mutation UpdateWidgetPlugin($id: ID!, $input: UpdateWidgetPluginInput!) {
  updateWidgetPlugin(id: $id, input: $input) {
    id
    name
    description
    scriptLanguage
    templateLanguage
    scriptCode
    templateCode
    updatedAt
  }
}`;

  DELETE_WIDGET_PLUGIN = `mutation DeleteWidgetPlugin($id: ID!) { deleteWidgetPlugin(id: $id) }`;

  window.App = {
    _currentSpace: null,
    _currentCustomView: null,
    _activeDataView: null,
    _activeCustomView: null,
    _allSpaces: [],
    _editingFieldId: null, // fieldId being edited in the Champs form, or null
    _localeListenerBound: false,
    _removeFieldMutation: REMOVE_FIELD,
    _reorderFieldsMutation: REORDER_FIELDS,
    _createCustomViewMutation: CREATE_CUSTOM_VIEW,
    _listCustomViewsQuery: LIST_CUSTOM_VIEWS,
    _updateCustomViewMutation: UPDATE_CUSTOM_VIEW,
    _deleteCustomViewMutation: DELETE_CUSTOM_VIEW,
    _listWidgetPluginsQuery: window.WidgetPlugins.LIST_QUERY,
    _createWidgetPluginMutation: CREATE_WIDGET_PLUGIN,
    _updateWidgetPluginMutation: UPDATE_WIDGET_PLUGIN,
    _deleteWidgetPluginMutation: DELETE_WIDGET_PLUGIN,
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
      pageList: function() {
        return document.getElementById('page-list');
      },
      newPageBtn: function() {
        return document.getElementById('new-page-btn');
      },
      dataViewList: function() {
        return document.getElementById('data-view-list');
      },
      newDataViewBtn: function() {
        return document.getElementById('new-data-view-btn');
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
      adminNavApps: function() {
        return document.getElementById('admin-nav-apps');
      },
      dataToolbar: function() {
        return document.getElementById('data-toolbar');
      },
      dataTitle: function() {
        return document.getElementById('data-title');
      },
      undoBtn: function() {
        return document.getElementById('undo-btn');
      },
      redoBtn: function() {
        return document.getElementById('redo-btn');
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
      yamlEditorPanel: function() {
        return document.getElementById('yaml-editor-panel');
      },
      yamlPageName: function() {
        return document.getElementById('yaml-page-name');
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
      yamlAddWidgetBtn: function() {
        return document.getElementById('yaml-add-widget-btn');
      },
      // Add widget modal
      addWidgetModal: function() {
        return document.getElementById('add-widget-modal');
      },
      addWidgetConfirmBtn: function() {
        return document.getElementById('add-widget-confirm-btn');
      },
      addWidgetCancelBtn: function() {
        return document.getElementById('add-widget-cancel-btn');
      },
      availableSpaces: function() {
        return document.getElementById('available-spaces');
      },
      availablePlugins: function() {
        return document.getElementById('available-plugins');
      },
      widgetConfigForm: function() {
        return document.getElementById('widget-config-form');
      },
      // Plugins sidebar section
      pluginsSidebarSection: function() {
        return document.getElementById('plugins-sidebar-section');
      },
      pluginsNavManage: function() {
        return document.getElementById('plugins-nav-manage');
      },
      widgetPluginModal: function() {
        return document.getElementById('widget-plugin-modal');
      },
      widgetPluginModalCloseBtn: function() {
        return document.getElementById('widget-plugin-modal-close-btn');
      },
      widgetPluginNewBtn: function() {
        return document.getElementById('widget-plugin-new-btn');
      },
      widgetPluginDeleteBtn: function() {
        return document.getElementById('widget-plugin-delete-btn');
      },
      widgetPluginSaveBtn: function() {
        return document.getElementById('widget-plugin-save-btn');
      },
      widgetPluginSelect: function() {
        return document.getElementById('widget-plugin-select');
      },
      widgetPluginName: function() {
        return document.getElementById('widget-plugin-name');
      },
      widgetPluginDescription: function() {
        return document.getElementById('widget-plugin-description');
      },
      widgetPluginScriptLanguage: function() {
        return document.getElementById('widget-plugin-script-language');
      },
      widgetPluginTemplateLanguage: function() {
        return document.getElementById('widget-plugin-template-language');
      },
      widgetPluginScriptEditor: function() {
        return document.getElementById('widget-plugin-script-editor');
      },
      widgetPluginTemplateEditor: function() {
        return document.getElementById('widget-plugin-template-editor');
      },
      widgetPluginManifestEditor: function() {
        return document.getElementById('widget-plugin-manifest-editor');
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
      adminAppsSection: function() {
        return document.getElementById('admin-apps-section');
      },
      appsList: function() {
        return document.getElementById('apps-list');
      },
      appsPurgeOpenBtn: function() {
        return document.getElementById('apps-purge-open-btn');
      },
      appsPackageInput: function() {
        return document.getElementById('apps-package-input');
      },
      appsPackageName: function() {
        return document.getElementById('apps-package-name');
      },
      appsAllowDowngrade: function() {
        return document.getElementById('apps-allow-downgrade');
      },
      appsPlanErrors: function() {
        return document.getElementById('apps-plan-errors');
      },
      appsPlanBox: function() {
        return document.getElementById('apps-plan-box');
      },
      appsApplyBtn: function() {
        return document.getElementById('apps-apply-btn');
      },
      appsApplyReport: function() {
        return document.getElementById('apps-apply-report');
      },
      appsExportId: function() {
        return document.getElementById('apps-export-id');
      },
      appsExportName: function() {
        return document.getElementById('apps-export-name');
      },
      appsExportVersion: function() {
        return document.getElementById('apps-export-version');
      },
      appsExportDescription: function() {
        return document.getElementById('apps-export-description');
      },
      appsExportSeed: function() {
        return document.getElementById('apps-export-seed');
      },
      appsExportError: function() {
        return document.getElementById('apps-export-error');
      },
      appsExportBtn: function() {
        return document.getElementById('apps-export-btn');
      },
      appsPurgeBox: function() {
        return document.getElementById('apps-purge-box');
      },
      appsPurgeAppName: function() {
        return document.getElementById('apps-purge-app-name');
      },
      appsPurgeItems: function() {
        return document.getElementById('apps-purge-items');
      },
      appsPurgePreviewBtn: function() {
        return document.getElementById('apps-purge-preview-btn');
      },
      appsPurgePreview: function() {
        return document.getElementById('apps-purge-preview');
      },
      appsPurgeConfirmInput: function() {
        return document.getElementById('apps-purge-confirm-input');
      },
      appsPurgeConfirmHint: function() {
        return document.getElementById('apps-purge-confirm-hint');
      },
      appsPurgeConfirmBtn: function() {
        return document.getElementById('apps-purge-confirm-btn');
      },
      appsPurgeReport: function() {
        return document.getElementById('apps-purge-report');
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
      snapshotCompressCheckbox: function() {
        return document.getElementById('snapshot-compress-checkbox');
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
      // Dialog: change password
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
      // Dialog: create user
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
      // Dialog: create group
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
      },
      // Data View Config Modal
      dataViewModal: function() {
        return document.getElementById('data-view-modal');
      },
      dataViewModalTitle: function() {
        return document.getElementById('data-view-modal-title');
      },
      dataViewSaveBtn: function() {
        return document.getElementById('data-view-save-btn');
      },
      dataViewModalCloseBtn: function() {
        return document.getElementById('data-view-modal-close-btn');
      },
      dvName: function() {
        return document.getElementById('dv-name');
      },
      dvSource: function() {
        return document.getElementById('dv-source');
      },
      dvTabFields: function() {
        return document.getElementById('dv-tab-fields');
      },
      dvTabFilter: function() {
        return document.getElementById('dv-tab-filter');
      },
      dvTabGroup: function() {
        return document.getElementById('dv-tab-group');
      },
      dvFilterFormula: function() {
        return document.getElementById('dv-filter-formula');
      },
      dvAggregatesList: function() {
        return document.getElementById('dv-aggregates-list');
      },
      dvAddAggBtn: function() {
        return document.getElementById('dv-add-agg-btn');
      },
      // YAML Editor elements
      dvYamlContent: function() {
        return document.getElementById('dv-yaml-content');
      },
      dvFormatYamlBtn: function() {
        return document.getElementById('dv-format-yaml-btn');
      },
      dvApplyYamlBtn: function() {
        return document.getElementById('dv-apply-yaml-btn');
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
      this._bindWidgetPlugins();
      this._bindDataViewModal();
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
      return window.AppSidebarHelpers.applySidebarState(this);
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
        this.el.pluginsSidebarSection().classList.remove('hidden');
      } else {
        this.el.adminSidebarSection().classList.add('hidden');
        this.el.pluginsSidebarSection().classList.add('hidden');
      }
      // Show warning banner when the account still uses the default password.
      // The flag is computed and exposed by the server (spec §7 / audit 1.4).
      if (user.mustChangePassword) {
        return this.el.defaultPasswordWarning().classList.remove('hidden');
      } else {
        return this.el.defaultPasswordWarning().classList.add('hidden');
      }
    },
    // ── Sidebar ─────────────────────────────────────────────────────────────────
    _bindSidebar: function() {
      return window.AppSidebarHelpers.bindSidebar(this);
    },
    // ── Load everything ─────────────────────────────────────────────────────────
    _loadAll: function() {
      return window.AppDataHelpers.loadAll(this);
    },
    // ── Admin panel ──────────────────────────────────────────────────────────────
    _showAdminPanel: function(section = 'users') {
      return window.AppSidebarHelpers.showAdminPanel(this, section);
    },
    _hideAdminPanel: function() {
      return window.AppSidebarHelpers.hideAdminPanel(this);
    },
    _loadAdminUsers: function() {
      return window.AppSidebarHelpers.loadAdminUsers(this);
    },
    _loadAdminGroups: function() {
      return window.AppSidebarHelpers.loadAdminGroups(this);
    },
    // ── App versioning ───────────────────────────────────────────────────────────
    _bindAppsPanel: function() {
      return window.AppAppsHelpers.bindAppsPanel(this);
    },
    _loadApps: function() {
      return window.AppAppsHelpers.loadApps(this);
    },
    // ── Dialog: change password ──────────────────────────────────────────────────
    _openChangePasswordDialog: function(message) {
      return window.AppSidebarHelpers.openChangePasswordDialog(this, message);
    },
    _bindChangePasswordDialog: function() {
      return window.AppSidebarHelpers.bindChangePasswordDialog(this);
    },
    // ── Dialog: create user ──────────────────────────────────────────────────────
    _bindCreateUserDialog: function() {
      return window.AppSidebarHelpers.bindCreateUserDialog(this);
    },
    // ── Dialog: create group ─────────────────────────────────────────────────────
    _bindCreateGroupDialog: function() {
      return window.AppSidebarHelpers.bindCreateGroupDialog(this);
    },
    // ── Snapshot export / import ─────────────────────────────────────────────────
    _bindSnapshotPanel: function() {
      return window.AppSnapshotHelpers.bindSnapshotPanel(this);
    },
    _renderSnapshotDiff: function(diff) {
      return window.AppSnapshotHelpers.renderSnapshotDiff(this, diff);
    },
    // ── Hash-based navigation ────────────────────────────────────────────────────
    _restoreFromHash: function() {
      return window.AppDataHelpers.restoreFromHash(this);
    },
    // ── Spaces (Data section) ────────────────────────────────────────────────────
    loadSpaces: function() {
      return window.AppDataHelpers.loadSpaces(this);
    },
    renderSpaceList: function(spaces) {
      return window.AppDataHelpers.renderSpaceList(this, spaces);
    },
    selectSpace: function(sp) {
      return window.AppDataHelpers.selectSpace(this, sp);
    },
    // Keep @_allSpaces in sync after any field mutation on the current space.
    // If a custom view is active, rebuilds it so widgets get the fresh columns.
    _syncSpaceFields: function(space) {
      return window.AppDataHelpers.syncSpaceFields(this, space);
    },
    _mountDataView: function(space) {
      return window.AppDataHelpers.mountDataView(this, space);
    },
    // ── Data Views ─────────────────────────────────────────────────────────────
    loadDataViews: function() {
      return window.AppDataHelpers.loadDataViews(this);
    },
    renderDataViewList: function(views) {
      return window.AppDataHelpers.renderDataViewList(this, views);
    },
    selectDataView: function(view) {
      return window.AppDataHelpers.selectDataView(this, view);
    },
    _mountDataViewFromView: function(view) {
      return window.AppDataHelpers.mountDataViewFromView(this, view);
    },
    // ── Pages (formerly Custom views) ─────────────────────────────────────────
    loadPages: function() {
      return window.AppViewHelpers.loadPages(this);
    },
    renderPageList: function(views) {
      return window.AppViewHelpers.renderPageList(this, views);
    },
    selectPage: function(cv) {
      return window.AppViewHelpers.selectPage(this, cv);
    },
    _renderCustomViewPreview: function(yamlText) {
      return window.AppViewHelpers.renderCustomViewPreview(this, yamlText, this._allSpaces, this._allDataViews);
    },
    // ── Data View Config ───────────────────────────────────────────────────────
    _bindDataViewModal: function() {
      return window.AppViewConfigHelpers.bindDataViewModal(this);
    },
    _openDataViewConfigModal: function(view = null) {
      return window.AppViewConfigHelpers.openDataViewConfigModal(this, view);
    },
    // ── YAML editor ─────────────────────────────────────────────────────────────
    _bindYamlEditor: function() {
      return window.AppViewHelpers.bindYamlEditor(this);
    },
    _openYamlModal: function() {
      return window.AppViewHelpers.openYamlModal(this);
    },
    _bindWidgetPlugins: function() {
      return window.AppViewHelpers.bindWidgetPlugins(this);
    },
    _openWidgetPluginModal: function() {
      return window.AppViewHelpers.openWidgetPluginModal(this);
    },
    _loadAllRelations: function() {
      return window.AppViewHelpers.loadAllRelations(this);
    },
    // ── Data toolbar ─────────────────────────────────────────────────────────────
    _bindDataToolbar: function() {
      return window.AppDataHelpers.bindDataToolbar(this);
    },
    // ── Fields panel ─────────────────────────────────────────────────────────────
    _bindFieldsPanel: function() {
      return window.AppFieldsHelpers.bindFieldsPanel(this);
    },
    _refreshActiveDataViewLayout: function() {
      var refresh;
      refresh = () => {
        var ref, ref1;
        return (ref = this._activeDataView) != null ? (ref1 = ref._grid) != null ? typeof ref1.refreshLayout === "function" ? ref1.refreshLayout() : void 0 : void 0 : void 0;
      };
      requestAnimationFrame(function() {
        return requestAnimationFrame(refresh);
      });
      return setTimeout(refresh, 220);
    },
    _onGridColumnFocused: function(columnName) {
      return window.AppFieldsHelpers.onGridColumnFocused(this, columnName);
    },
    _highlightFieldInPanel: function(fieldName) {
      return window.AppFieldsHelpers.highlightFieldInPanel(this, fieldName);
    },
    _openFieldEditorByName: function(fieldName) {
      return window.AppFieldsHelpers.openFieldEditorByName(this, fieldName);
    },
    _startEditField: function(field, relation = null) {
      return window.AppFieldsHelpers.startEditField(this, field, relation);
    },
    _onFieldTypeChange: function() {
      return window.AppFieldsHelpers.onFieldTypeChange(this);
    },
    _resetFieldForm: function() {
      return window.AppFieldsHelpers.resetFieldForm(this);
    },
    updateFieldProperties: function(fieldId, opts, formulaType) {
      return window.AppFieldsHelpers.updateFieldProperties(this, fieldId, opts, formulaType);
    },
    renderFieldsList: function() {
      return window.AppFieldsHelpers.renderFieldsList(this);
    }
  };

  // ── Entry point ────────────────────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', function() {
    GQL.loadToken();
    App.init();
    // Initial page flash is avoided by the inline script in index.moon.
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
