# app.coffee — main application bootstrap and UI orchestration.

REMOVE_FIELD = """
  mutation RemoveField($fieldId: ID!) { removeField(fieldId: $fieldId) }
"""

REORDER_FIELDS = """
  mutation ReorderFields($spaceId: ID!, $fieldIds: [ID!]!) {
    reorderFields(spaceId: $spaceId, fieldIds: $fieldIds) { id name fieldType notNull position }
  }
"""

LIST_CUSTOM_VIEWS = """
  query { customViews { id name description yaml } }
"""

CREATE_CUSTOM_VIEW = """
  mutation CreateCustomView($input: CreateCustomViewInput!) {
    createCustomView(input: $input) { id name yaml }
  }
"""

UPDATE_CUSTOM_VIEW = """
  mutation UpdateCustomView($id: ID!, $input: UpdateCustomViewInput!) {
    updateCustomView(id: $id, input: $input) { id name yaml }
  }
"""

DELETE_CUSTOM_VIEW = """
  mutation DeleteCustomView($id: ID!) { deleteCustomView(id: $id) }
"""

CREATE_WIDGET_PLUGIN = """
  mutation CreateWidgetPlugin($input: CreateWidgetPluginInput!) {
    createWidgetPlugin(input: $input) {
      id
      name
      description
      scriptLanguage
      templateLanguage
      scriptCode
      templateCode
      manifest
      appId
      updatedAt
    }
  }
"""

UPDATE_WIDGET_PLUGIN = """
  mutation UpdateWidgetPlugin($id: ID!, $input: UpdateWidgetPluginInput!) {
    updateWidgetPlugin(id: $id, input: $input) {
      id
      name
      description
      scriptLanguage
      templateLanguage
      scriptCode
      templateCode
      manifest
      appId
      updatedAt
    }
  }
"""

DELETE_WIDGET_PLUGIN = """
  mutation DeleteWidgetPlugin($id: ID!) { deleteWidgetPlugin(id: $id) }
"""

window.App =
  _currentSpace:     null
  _currentCustomView: null
  _activeDataView:   null
  _activeCustomView: null
  _allSpaces:        []
  _editingFieldId:   null   # fieldId being edited in the Champs form, or null
  _localeListenerBound: false
  _removeFieldMutation: REMOVE_FIELD
  _reorderFieldsMutation: REORDER_FIELDS
  _createCustomViewMutation: CREATE_CUSTOM_VIEW
  _listCustomViewsQuery: LIST_CUSTOM_VIEWS
  _updateCustomViewMutation: UPDATE_CUSTOM_VIEW
  _deleteCustomViewMutation: DELETE_CUSTOM_VIEW
  _listWidgetPluginsQuery: window.WidgetPlugins.LIST_QUERY
  _createWidgetPluginMutation: CREATE_WIDGET_PLUGIN
  _updateWidgetPluginMutation: UPDATE_WIDGET_PLUGIN
  _deleteWidgetPluginMutation: DELETE_WIDGET_PLUGIN

  _t: (key, vars = {}) ->
    if window.I18N?.t then window.I18N.t key, vars else key

  _err: (err, key = 'common.error') ->
    "#{@_t(key)} : #{err.message}"

  # ── DOM refs ────────────────────────────────────────────────────────────────
  el:
    loginOverlay:      -> document.getElementById 'login-overlay'
    main:              -> document.getElementById 'main'
    loginUser:         -> document.getElementById 'login-username'
    loginPass:         -> document.getElementById 'login-password'
    loginBtn:          -> document.getElementById 'login-btn'
    loginError:        -> document.getElementById 'login-error'
    currentUserBtn:    -> document.getElementById 'current-user-btn'
    userMenu:          -> document.getElementById 'user-menu'
    changePasswordBtn: -> document.getElementById 'change-password-btn'
    logoutBtn:         -> document.getElementById 'logout-btn'
    langFrBtn:         -> document.getElementById 'lang-fr-btn'
    langEnBtn:         -> document.getElementById 'lang-en-btn'
    spaceList:         -> document.getElementById 'space-list'
    newSpaceBtn:       -> document.getElementById 'new-space-btn'
    pageList:          -> document.getElementById 'page-list'
    newPageBtn:         -> document.getElementById 'new-page-btn'
    dataViewList:      -> document.getElementById 'data-view-list'
    newDataViewBtn:    -> document.getElementById 'new-data-view-btn'
    adminSidebarSection: -> document.getElementById 'admin-sidebar-section'
    adminNavUsers:     -> document.getElementById 'admin-nav-users'
    adminNavGroups:    -> document.getElementById 'admin-nav-groups'
    adminNavSnapshot:  -> document.getElementById 'admin-nav-snapshot'
    adminNavApps:      -> document.getElementById 'admin-nav-apps'
    dataToolbar:       -> document.getElementById 'data-toolbar'
    dataTitle:         -> document.getElementById 'data-title'
    undoBtn:           -> document.getElementById 'undo-btn'
    redoBtn:           -> document.getElementById 'redo-btn'
    formulaFilterInput: -> document.getElementById 'formula-filter-input'
    renameSpaceBtn:    -> document.getElementById 'rename-space-btn'
    deleteSpaceBtn:    -> document.getElementById 'delete-space-btn'
    fieldsBtn:         -> document.getElementById 'fields-btn'
    deleteRowsBtn:     -> document.getElementById 'delete-rows-btn'
    gridContainer:     -> document.getElementById 'grid-container'
    customViewContainer: -> document.getElementById 'custom-view-container'
    fieldsPanel:       -> document.getElementById 'fields-panel'
    fieldsPanelClose:  -> document.getElementById 'fields-panel-close'
    fieldsList:        -> document.getElementById 'fields-list'
    fieldName:         -> document.getElementById 'field-name'
    fieldType:         -> document.getElementById 'field-type'
    fieldNotNull:      -> document.getElementById 'field-notnull'
    fieldFormula:      -> document.getElementById 'field-formula'
    formulaLanguage:   -> document.getElementById 'formula-language'
    fieldTriggerFields: -> document.getElementById 'field-trigger-fields'
    formulaBody:       -> document.getElementById 'formula-body'
    triggerFieldsRow:  -> document.getElementById 'trigger-fields-row'
    fieldAddBtn:       -> document.getElementById 'field-add-btn'
    fieldCancelBtn:    -> document.getElementById 'field-cancel-btn'
    fieldReprFormula:  -> document.getElementById 'field-repr-formula'
    relTargetRow:      -> document.getElementById 'rel-target-row'
    relToSpace:        -> document.getElementById 'rel-to-space'
    relReprRow:        -> document.getElementById 'rel-repr-row'
    relReprFormula:    -> document.getElementById 'rel-repr-formula'
    yamlEditorPanel:   -> document.getElementById 'yaml-editor-panel'
    yamlPageName:      -> document.getElementById 'yaml-page-name'
    yamlEditBtn:       -> document.getElementById 'yaml-edit-btn'
    yamlDeleteBtn:     -> document.getElementById 'yaml-delete-btn'
    # YAML modal (CodeMirror)
    yamlModal:         -> document.getElementById 'yaml-modal'
    yamlModalTitle:    -> document.getElementById 'yaml-modal-title'
    yamlModalSaveBtn:  -> document.getElementById 'yaml-modal-save-btn'
    yamlModalCloseBtn: -> document.getElementById 'yaml-modal-close-btn'
    yamlModalPreviewBtn: -> document.getElementById 'yaml-modal-preview-btn'
    yamlAddWidgetBtn: -> document.getElementById 'yaml-add-widget-btn'
    # Add widget modal
    addWidgetModal:    -> document.getElementById 'add-widget-modal'
    addWidgetConfirmBtn: -> document.getElementById 'add-widget-confirm-btn'
    addWidgetCancelBtn: -> document.getElementById 'add-widget-cancel-btn'
    availableSpaces:  -> document.getElementById 'available-spaces'
    availablePlugins: -> document.getElementById 'available-plugins'
    widgetConfigForm: -> document.getElementById 'widget-config-form'
    # Plugins sidebar section
    pluginsSidebarSection: -> document.getElementById 'plugins-sidebar-section'
    pluginsNavManage: -> document.getElementById 'plugins-nav-manage'
    widgetPluginModal: -> document.getElementById 'widget-plugin-modal'
    widgetPluginModalCloseBtn: -> document.getElementById 'widget-plugin-modal-close-btn'
    widgetPluginNewBtn: -> document.getElementById 'widget-plugin-new-btn'
    widgetPluginDeleteBtn: -> document.getElementById 'widget-plugin-delete-btn'
    widgetPluginSaveBtn: -> document.getElementById 'widget-plugin-save-btn'
    widgetPluginSelect: -> document.getElementById 'widget-plugin-select'
    widgetPluginName: -> document.getElementById 'widget-plugin-name'
    widgetPluginDescription: -> document.getElementById 'widget-plugin-description'
    widgetPluginScope: -> document.getElementById 'widget-plugin-scope'
    widgetPluginScriptLanguage: -> document.getElementById 'widget-plugin-script-language'
    widgetPluginTemplateLanguage: -> document.getElementById 'widget-plugin-template-language'
    widgetPluginScriptEditor: -> document.getElementById 'widget-plugin-script-editor'
    widgetPluginTemplateEditor: -> document.getElementById 'widget-plugin-template-editor'
    widgetPluginManifestEditor: -> document.getElementById 'widget-plugin-manifest-editor'
    # Formula modal (CodeMirror)
    formulaModal:      -> document.getElementById 'formula-modal'
    formulaModalApplyBtn: -> document.getElementById 'formula-modal-apply-btn'
    formulaModalCloseBtn: -> document.getElementById 'formula-modal-close-btn'
    welcome:           -> document.getElementById 'welcome'
    contentRow:        -> document.getElementById 'content-row'
    adminPanel:        -> document.getElementById 'admin-panel'
    adminUsersSection: -> document.getElementById 'admin-users-section'
    adminGroupsSection: -> document.getElementById 'admin-groups-section'
    adminSnapshotSection: -> document.getElementById 'admin-snapshot-section'
    adminAppsSection: -> document.getElementById 'admin-apps-section'
    appsList:          -> document.getElementById 'apps-list'
    appsPurgeOpenBtn:  -> document.getElementById 'apps-purge-open-btn'
    appsPackageInput:  -> document.getElementById 'apps-package-input'
    appsPackageName:   -> document.getElementById 'apps-package-name'
    appsAllowDowngrade: -> document.getElementById 'apps-allow-downgrade'
    appsPlanErrors:    -> document.getElementById 'apps-plan-errors'
    appsPlanBox:       -> document.getElementById 'apps-plan-box'
    appsApplyBtn:      -> document.getElementById 'apps-apply-btn'
    appsApplyReport:   -> document.getElementById 'apps-apply-report'
    appsExportId:          -> document.getElementById 'apps-export-id'
    appsExportName:        -> document.getElementById 'apps-export-name'
    appsExportVersion:     -> document.getElementById 'apps-export-version'
    appsExportDescription: -> document.getElementById 'apps-export-description'
    appsExportSeed:        -> document.getElementById 'apps-export-seed'
    appsExportError:       -> document.getElementById 'apps-export-error'
    appsExportBtn:         -> document.getElementById 'apps-export-btn'
    appsPurgeBox:          -> document.getElementById 'apps-purge-box'
    appsPurgeAppName:      -> document.getElementById 'apps-purge-app-name'
    appsPurgeItems:        -> document.getElementById 'apps-purge-items'
    appsPurgePreviewBtn:   -> document.getElementById 'apps-purge-preview-btn'
    appsPurgePreview:      -> document.getElementById 'apps-purge-preview'
    appsPurgeConfirmInput: -> document.getElementById 'apps-purge-confirm-input'
    appsPurgeConfirmHint:  -> document.getElementById 'apps-purge-confirm-hint'
    appsPurgeConfirmBtn:   -> document.getElementById 'apps-purge-confirm-btn'
    appsPurgeReport:       -> document.getElementById 'apps-purge-report'
    adminUsersList:    -> document.getElementById 'admin-users-list'
    adminGroupsList:   -> document.getElementById 'admin-groups-list'
    adminCreateUserBtn: -> document.getElementById 'admin-create-user-btn'
    adminCreateGroupBtn: -> document.getElementById 'admin-create-group-btn'
    adminNavSnapshot:  -> document.getElementById 'admin-nav-snapshot'
    snapshotExportSchemaBtn: -> document.getElementById 'snapshot-export-schema-btn'
    snapshotExportFullBtn:   -> document.getElementById 'snapshot-export-full-btn'
    snapshotCompressCheckbox: -> document.getElementById 'snapshot-compress-checkbox'
    snapshotFileInput:       -> document.getElementById 'snapshot-file-input'
    snapshotFileName:        -> document.getElementById 'snapshot-file-name'
    snapshotDiffBox:         -> document.getElementById 'snapshot-diff-box'
    snapshotDiffContent:     -> document.getElementById 'snapshot-diff-content'
    snapshotImportError:     -> document.getElementById 'snapshot-import-error'
    snapshotImportConfirmBtn: -> document.getElementById 'snapshot-import-confirm-btn'
    snapshotImportResult:    -> document.getElementById 'snapshot-import-result'
    defaultPasswordWarning: -> document.getElementById 'default-password-warning'
    warningChangePasswordBtn: -> document.getElementById 'warning-change-password-btn'
    # Dialog: change password
    changePasswordDialog: -> document.getElementById 'change-password-dialog'
    cpCurrent:         -> document.getElementById 'cp-current'
    cpNew:             -> document.getElementById 'cp-new'
    cpConfirm:         -> document.getElementById 'cp-confirm'
    cpError:           -> document.getElementById 'cp-error'
    cpSubmitBtn:       -> document.getElementById 'cp-submit-btn'
    cpCancelBtn:       -> document.getElementById 'cp-cancel-btn'
    # Dialog: create user
    createUserDialog:  -> document.getElementById 'create-user-dialog'
    cuUsername:        -> document.getElementById 'cu-username'
    cuEmail:           -> document.getElementById 'cu-email'
    cuPassword:        -> document.getElementById 'cu-password'
    cuError:           -> document.getElementById 'cu-error'
    cuSubmitBtn:       -> document.getElementById 'cu-submit-btn'
    cuCancelBtn:       -> document.getElementById 'cu-cancel-btn'
    # Dialog: create group
    createGroupDialog: -> document.getElementById 'create-group-dialog'
    cgName:            -> document.getElementById 'cg-name'
    cgDescription:     -> document.getElementById 'cg-description'
    cgError:           -> document.getElementById 'cg-error'
    cgSubmitBtn:       -> document.getElementById 'cg-submit-btn'
    cgCancelBtn:       -> document.getElementById 'cg-cancel-btn'
    # Data View Config Modal
    dataViewModal:     -> document.getElementById 'data-view-modal'
    dataViewModalTitle: -> document.getElementById 'data-view-modal-title'
    dataViewSaveBtn:   -> document.getElementById 'data-view-save-btn'
    dataViewModalCloseBtn: -> document.getElementById 'data-view-modal-close-btn'
    dvName:            -> document.getElementById 'dv-name'
    dvSource:          -> document.getElementById 'dv-source'
    dvTabFields:      -> document.getElementById 'dv-tab-fields'
    dvTabFilter:       -> document.getElementById 'dv-tab-filter'
    dvTabGroup:        -> document.getElementById 'dv-tab-group'
    dvFilterFormula:   -> document.getElementById 'dv-filter-formula'
    dvAggregatesList:  -> document.getElementById 'dv-aggregates-list'
    dvAddAggBtn:       -> document.getElementById 'dv-add-agg-btn'
    # YAML Editor elements
    dvYamlContent:     -> document.getElementById 'dv-yaml-content'
    dvFormatYamlBtn:   -> document.getElementById 'dv-format-yaml-btn'
    dvApplyYamlBtn:    -> document.getElementById 'dv-apply-yaml-btn'

  # ── Bootstrap ───────────────────────────────────────────────────────────────
  init: ->
    window.I18N?.init?()
    @_bindLocaleChange()
    @_bindLogin()
    @_bindSidebar()
    @_bindDataToolbar()
    @_bindFieldsPanel()
    @_bindYamlEditor()
    @_bindWidgetPlugins()
    @_bindDataViewModal()
    @_applyI18nDynamic()

  _bindLocaleChange: ->
    return if @_localeListenerBound
    @_localeListenerBound = true
    window.addEventListener 'i18n:locale-changed', =>
      @_applyI18nDynamic()

  _applySidebarState: ->
    window.AppSidebarHelpers.applySidebarState @

  _applyI18nDynamic: ->
    @el.fieldAddBtn()?.textContent = if @_editingFieldId then @_t('ui.fields.update') else @_t('ui.fields.add')

  # ── Login ───────────────────────────────────────────────────────────────────
  _bindLogin: ->
    doLogin = =>
      username = @el.loginUser().value.trim()
      password = @el.loginPass().value
      return unless username and password
      @el.loginError().textContent = ''
      Auth.login(username, password)
        .then (user) =>
          @showMain user
          @_loadAll()
        .catch (err) =>
          @el.loginError().textContent = err.message

    @el.loginBtn().addEventListener 'click', doLogin
    onEnter = (e) -> doLogin() if e.key == 'Enter'
    @el.loginUser().addEventListener 'keydown', onEnter
    @el.loginPass().addEventListener 'keydown', onEnter

  showLogin: ->
    @el.loginOverlay().classList.remove 'hidden'
    @el.main().classList.add 'hidden'

  showMain: (user) ->
    @el.loginOverlay().classList.add 'hidden'
    @el.main().classList.remove 'hidden'
    @el.currentUserBtn().textContent = user.username
    if Auth.isAdmin()
      @el.adminSidebarSection().classList.remove 'hidden'
      @el.pluginsSidebarSection().classList.remove 'hidden'
    else
      @el.adminSidebarSection().classList.add 'hidden'
      @el.pluginsSidebarSection().classList.add 'hidden'
    # Show warning banner when the account still uses the default password.
    # The flag is computed and exposed by the server (spec §7 / audit 1.4).
    if user.mustChangePassword
      @el.defaultPasswordWarning().classList.remove 'hidden'
    else
      @el.defaultPasswordWarning().classList.add 'hidden'

  # ── Sidebar ─────────────────────────────────────────────────────────────────
  _bindSidebar: ->
    window.AppSidebarHelpers.bindSidebar @

  # ── Load everything ─────────────────────────────────────────────────────────
  _loadAll: ->
    window.AppDataHelpers.loadAll @

  # ── Admin panel ──────────────────────────────────────────────────────────────
  _showAdminPanel: (section = 'users') ->
    window.AppSidebarHelpers.showAdminPanel @, section

  _hideAdminPanel: ->
    window.AppSidebarHelpers.hideAdminPanel @

  _loadAdminUsers: ->
    window.AppSidebarHelpers.loadAdminUsers @

  _loadAdminGroups: ->
    window.AppSidebarHelpers.loadAdminGroups @

  # ── App versioning ───────────────────────────────────────────────────────────
  _bindAppsPanel: ->
    window.AppAppsHelpers.bindAppsPanel @

  _loadApps: ->
    window.AppAppsHelpers.loadApps @

  # ── Dialog: change password ──────────────────────────────────────────────────
  _openChangePasswordDialog: (message) ->
    window.AppSidebarHelpers.openChangePasswordDialog @, message

  _bindChangePasswordDialog: ->
    window.AppSidebarHelpers.bindChangePasswordDialog @

  # ── Dialog: create user ──────────────────────────────────────────────────────
  _bindCreateUserDialog: ->
    window.AppSidebarHelpers.bindCreateUserDialog @

  # ── Dialog: create group ─────────────────────────────────────────────────────
  _bindCreateGroupDialog: ->
    window.AppSidebarHelpers.bindCreateGroupDialog @

  # ── Snapshot export / import ─────────────────────────────────────────────────
  _bindSnapshotPanel: ->
    window.AppSnapshotHelpers.bindSnapshotPanel @

  _renderSnapshotDiff: (diff) ->
    window.AppSnapshotHelpers.renderSnapshotDiff @, diff

  # ── Hash-based navigation ────────────────────────────────────────────────────
  _restoreFromHash: ->
    window.AppDataHelpers.restoreFromHash @

  # ── Spaces (Data section) ────────────────────────────────────────────────────
  loadSpaces: ->
    window.AppDataHelpers.loadSpaces @

  renderSpaceList: (spaces) ->
    window.AppDataHelpers.renderSpaceList @, spaces

  selectSpace: (sp) ->
    window.AppDataHelpers.selectSpace @, sp

  # Keep @_allSpaces in sync after any field mutation on the current space.
  # If a custom view is active, rebuilds it so widgets get the fresh columns.
  _syncSpaceFields: (space) ->
    window.AppDataHelpers.syncSpaceFields @, space

  _mountDataView: (space) ->
    window.AppDataHelpers.mountDataView @, space

  # ── Data Views ─────────────────────────────────────────────────────────────
  loadDataViews: ->
    window.AppDataHelpers.loadDataViews @

  renderDataViewList: (views) ->
    window.AppDataHelpers.renderDataViewList @, views

  selectDataView: (view) ->
    window.AppDataHelpers.selectDataView @, view

  _mountDataViewFromView: (view) ->
    window.AppDataHelpers.mountDataViewFromView @, view

  # ── Pages (formerly Custom views) ─────────────────────────────────────────
  loadPages: ->
    window.AppViewHelpers.loadPages @

  renderPageList: (views) ->
    window.AppViewHelpers.renderPageList @, views

  selectPage: (cv) ->
    window.AppViewHelpers.selectPage @, cv

  _renderCustomViewPreview: (yamlText) ->
    window.AppViewHelpers.renderCustomViewPreview @, yamlText, @_allSpaces, @_allDataViews

  # ── Data View Config ───────────────────────────────────────────────────────
  _bindDataViewModal: ->
    window.AppViewConfigHelpers.bindDataViewModal @

  _openDataViewConfigModal: (view = null) ->
    window.AppViewConfigHelpers.openDataViewConfigModal @, view

  # ── YAML editor ─────────────────────────────────────────────────────────────
  _bindYamlEditor: ->
    window.AppViewHelpers.bindYamlEditor @

  _openYamlModal: ->
    window.AppViewHelpers.openYamlModal @

  _bindWidgetPlugins: ->
    window.AppViewHelpers.bindWidgetPlugins @

  _openWidgetPluginModal: ->
    window.AppViewHelpers.openWidgetPluginModal @

  _loadAllRelations: ->
    window.AppViewHelpers.loadAllRelations @

  # ── Data toolbar ─────────────────────────────────────────────────────────────
  _bindDataToolbar: ->
    window.AppDataHelpers.bindDataToolbar @

  # ── Fields panel ─────────────────────────────────────────────────────────────
  _bindFieldsPanel: ->
    window.AppFieldsHelpers.bindFieldsPanel @

  _refreshActiveDataViewLayout: ->
    refresh = =>
      @_activeDataView?._grid?.refreshLayout?()
    requestAnimationFrame -> requestAnimationFrame refresh
    setTimeout refresh, 220

  _onGridColumnFocused: (columnName) ->
    window.AppFieldsHelpers.onGridColumnFocused @, columnName

  _highlightFieldInPanel: (fieldName) ->
    window.AppFieldsHelpers.highlightFieldInPanel @, fieldName

  _openFieldEditorByName: (fieldName) ->
    window.AppFieldsHelpers.openFieldEditorByName @, fieldName

  _startEditField: (field, relation = null) ->
    window.AppFieldsHelpers.startEditField @, field, relation

  _onFieldTypeChange: ->
    window.AppFieldsHelpers.onFieldTypeChange @

  _resetFieldForm: ->
    window.AppFieldsHelpers.resetFieldForm @

  updateFieldProperties: (fieldId, opts, formulaType) ->
    window.AppFieldsHelpers.updateFieldProperties @, fieldId, opts, formulaType

  renderFieldsList: ->
    window.AppFieldsHelpers.renderFieldsList @

# ── Entry point ────────────────────────────────────────────────────────────────
document.addEventListener 'DOMContentLoaded', ->
  GQL.loadToken()
  App.init()
  # Initial page flash is avoided by the inline script in index.moon.
  Auth.restoreSession()
    .then (user) ->
      if user
        App.showMain user
        App._loadAll()
      else
        App.showLogin()
    .catch ->
      App.showLogin()
      GQL.clearToken()
