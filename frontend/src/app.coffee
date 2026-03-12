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
    customViewList:    -> document.getElementById 'custom-view-list'
    newViewBtn:        -> document.getElementById 'new-view-btn'
    adminSidebarSection: -> document.getElementById 'admin-sidebar-section'
    adminNavUsers:     -> document.getElementById 'admin-nav-users'
    adminNavGroups:    -> document.getElementById 'admin-nav-groups'
    adminNavSnapshot:  -> document.getElementById 'admin-nav-snapshot'
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
    yamlViewName:      -> document.getElementById 'yaml-view-name'
    yamlEditBtn:       -> document.getElementById 'yaml-edit-btn'
    yamlDeleteBtn:     -> document.getElementById 'yaml-delete-btn'
    # YAML modal (CodeMirror)
    yamlModal:         -> document.getElementById 'yaml-modal'
    yamlModalTitle:    -> document.getElementById 'yaml-modal-title'
    yamlModalSaveBtn:  -> document.getElementById 'yaml-modal-save-btn'
    yamlModalCloseBtn: -> document.getElementById 'yaml-modal-close-btn'
    yamlModalPreviewBtn: -> document.getElementById 'yaml-modal-preview-btn'
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
    adminUsersList:    -> document.getElementById 'admin-users-list'
    adminGroupsList:   -> document.getElementById 'admin-groups-list'
    adminCreateUserBtn: -> document.getElementById 'admin-create-user-btn'
    adminCreateGroupBtn: -> document.getElementById 'admin-create-group-btn'
    adminNavSnapshot:  -> document.getElementById 'admin-nav-snapshot'
    snapshotExportSchemaBtn: -> document.getElementById 'snapshot-export-schema-btn'
    snapshotExportFullBtn:   -> document.getElementById 'snapshot-export-full-btn'
    snapshotFileInput:       -> document.getElementById 'snapshot-file-input'
    snapshotFileName:        -> document.getElementById 'snapshot-file-name'
    snapshotDiffBox:         -> document.getElementById 'snapshot-diff-box'
    snapshotDiffContent:     -> document.getElementById 'snapshot-diff-content'
    snapshotImportError:     -> document.getElementById 'snapshot-import-error'
    snapshotImportConfirmBtn: -> document.getElementById 'snapshot-import-confirm-btn'
    snapshotImportResult:    -> document.getElementById 'snapshot-import-result'
    defaultPasswordWarning: -> document.getElementById 'default-password-warning'
    warningChangePasswordBtn: -> document.getElementById 'warning-change-password-btn'
    # Dialog: changement de mot de passe
    changePasswordDialog: -> document.getElementById 'change-password-dialog'
    cpCurrent:         -> document.getElementById 'cp-current'
    cpNew:             -> document.getElementById 'cp-new'
    cpConfirm:         -> document.getElementById 'cp-confirm'
    cpError:           -> document.getElementById 'cp-error'
    cpSubmitBtn:       -> document.getElementById 'cp-submit-btn'
    cpCancelBtn:       -> document.getElementById 'cp-cancel-btn'
    # Dialog: créer utilisateur
    createUserDialog:  -> document.getElementById 'create-user-dialog'
    cuUsername:        -> document.getElementById 'cu-username'
    cuEmail:           -> document.getElementById 'cu-email'
    cuPassword:        -> document.getElementById 'cu-password'
    cuError:           -> document.getElementById 'cu-error'
    cuSubmitBtn:       -> document.getElementById 'cu-submit-btn'
    cuCancelBtn:       -> document.getElementById 'cu-cancel-btn'
    # Dialog: créer groupe
    createGroupDialog: -> document.getElementById 'create-group-dialog'
    cgName:            -> document.getElementById 'cg-name'
    cgDescription:     -> document.getElementById 'cg-description'
    cgError:           -> document.getElementById 'cg-error'
    cgSubmitBtn:       -> document.getElementById 'cg-submit-btn'
    cgCancelBtn:       -> document.getElementById 'cg-cancel-btn'

  # ── Bootstrap ───────────────────────────────────────────────────────────────
  init: ->
    window.I18N?.init?()
    @_bindLocaleChange()
    @_bindLogin()
    @_bindSidebar()
    @_bindDataToolbar()
    @_bindFieldsPanel()
    @_bindYamlEditor()
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
    else
      @el.adminSidebarSection().classList.add 'hidden'
    # Bandeau avertissement si admin avec mot de passe par défaut
    if user.username == 'admin' and not localStorage.getItem('tdb_password_changed')
      @el.defaultPasswordWarning().classList.remove 'hidden'
    else
      @el.defaultPasswordWarning().classList.add 'hidden'

  # ── Sidebar ─────────────────────────────────────────────────────────────────
  _bindSidebar: ->
    window.AppSidebarHelpers.bindSidebar @

  # ── Load everything ─────────────────────────────────────────────────────────
  _loadAll: ->
    window.AppDataHelpers.loadAll @

  # ── Panel administration ─────────────────────────────────────────────────────
  _showAdminPanel: (section = 'users') ->
    window.AppSidebarHelpers.showAdminPanel @, section

  _hideAdminPanel: ->
    window.AppSidebarHelpers.hideAdminPanel @

  _loadAdminUsers: ->
    window.AppSidebarHelpers.loadAdminUsers @

  _loadAdminGroups: ->
    window.AppSidebarHelpers.loadAdminGroups @

  # ── Dialog: changement de mot de passe ──────────────────────────────────────
  _openChangePasswordDialog: ->
    window.AppSidebarHelpers.openChangePasswordDialog @

  _bindChangePasswordDialog: ->
    window.AppSidebarHelpers.bindChangePasswordDialog @

  # ── Dialog: créer utilisateur ─────────────────────────────────────────────
  _bindCreateUserDialog: ->
    window.AppSidebarHelpers.bindCreateUserDialog @

  # ── Dialog: créer groupe ──────────────────────────────────────────────────
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

  # ── Spaces (Données section) ─────────────────────────────────────────────────
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

  # ── Custom views (Vues section) ──────────────────────────────────────────────
  loadCustomViews: ->
    window.AppViewHelpers.loadCustomViews @

  renderCustomViewList: (views) ->
    window.AppViewHelpers.renderCustomViewList @, views

  selectCustomView: (cv) ->
    window.AppViewHelpers.selectCustomView @, cv

  _renderCustomViewPreview: (yamlText) ->
    window.AppViewHelpers.renderCustomViewPreview @, yamlText

  # ── YAML editor ─────────────────────────────────────────────────────────────
  _bindYamlEditor: ->
    window.AppViewHelpers.bindYamlEditor @

  _openYamlModal: ->
    window.AppViewHelpers.openYamlModal @

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
  # Le flash initial est évité par le script inline dans index.moon.
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
