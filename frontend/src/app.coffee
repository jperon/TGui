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
    if localStorage.getItem('tdb_menu_state') == 'collapsed'
      @el.main().classList.add 'sidebar-collapsed'
    else
      @el.main().classList.remove 'sidebar-collapsed'

    spList = @el.spaceList()
    spBtn  = document.getElementById 'spaces-toggle-btn'
    if localStorage.getItem('tdb_spaces_collapsed') == 'true'
      spList.classList.add 'hidden'
      spBtn?.classList.add 'collapsed'
    else
      spList.classList.remove 'hidden'
      spBtn?.classList.remove 'collapsed'

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
    @el.newSpaceBtn().addEventListener 'click', =>
      name = await tdbPrompt @_t('ui.prompts.newSpace')
      return unless name?.trim()
      Spaces.create(name.trim())
        .then => @_loadAll()
        .catch (err) => tdbAlert @_err(err), 'error'

    @el.newViewBtn().addEventListener 'click', =>
      name = await tdbPrompt @_t('ui.prompts.newView')
      return unless name?.trim()
      GQL.mutate(CREATE_CUSTOM_VIEW, { input: { name: name.trim(), yaml: "layout:\n  direction: vertical\n  children: []\n" } })
        .then (data) =>
          @loadCustomViews().then =>
            cv = data.createCustomView
            @selectCustomView cv
        .catch (err) => tdbAlert @_err(err), 'error'

    # Gestion de la sidebar repliable
    document.getElementById('sidebar-toggle')?.addEventListener 'click', =>
      mainEl = @el.main()
      isCollapsed = mainEl.classList.contains 'sidebar-collapsed'
      if isCollapsed
        mainEl.classList.remove 'sidebar-collapsed'
        localStorage.removeItem 'tdb_menu_state'
      else
        mainEl.classList.add 'sidebar-collapsed'
        localStorage.setItem 'tdb_menu_state', 'collapsed'

    # Gestion de la section Données (Espaces)
    document.getElementById('spaces-toggle-btn')?.addEventListener 'click', =>
      spList = @el.spaceList()
      spBtn  = document.getElementById('spaces-toggle-btn')
      isHidden = spList.classList.contains 'hidden'
      if isHidden
        spList.classList.remove 'hidden'
        spBtn.classList.remove 'collapsed'
        localStorage.setItem 'tdb_spaces_collapsed', 'false'
      else
        spList.classList.add 'hidden'
        spBtn.classList.add 'collapsed'
        localStorage.setItem 'tdb_spaces_collapsed', 'true'

    # Appliquer l'état par défaut au chargement
    @_applySidebarState()

    # Menu profil utilisateur
    @el.currentUserBtn().addEventListener 'click', =>
      menu = @el.userMenu()
      menu.classList.toggle 'hidden'
    document.addEventListener 'click', (e) =>
      unless @el.currentUserBtn().contains(e.target) or @el.userMenu().contains(e.target)
        @el.userMenu().classList.add 'hidden'

    @el.changePasswordBtn().addEventListener 'click', =>
      @el.userMenu().classList.add 'hidden'
      @_openChangePasswordDialog()

    @el.logoutBtn().addEventListener 'click', =>
      Auth.logout()
    @el.langFrBtn()?.addEventListener 'click', =>
      window.I18N?.setLocale 'fr'
    @el.langEnBtn()?.addEventListener 'click', =>
      window.I18N?.setLocale 'en'

    # Navigation admin
    @el.adminNavUsers().addEventListener 'click', =>
      @_showAdminPanel 'users'
    @el.adminNavGroups().addEventListener 'click', =>
      @_showAdminPanel 'groups'
    @el.adminNavSnapshot().addEventListener 'click', =>
      @_showAdminPanel 'snapshot'

    # Bandeau d'avertissement
    @el.warningChangePasswordBtn().addEventListener 'click', =>
      @_openChangePasswordDialog()

    @_bindChangePasswordDialog()
    @_bindCreateUserDialog()
    @_bindCreateGroupDialog()
    @_bindSnapshotPanel()

  # ── Load everything ─────────────────────────────────────────────────────────
  _loadAll: ->
    Promise.all([@loadSpaces(), @loadCustomViews()]).then => @_restoreFromHash()

  # ── Panel administration ─────────────────────────────────────────────────────
  _showAdminPanel: (section = 'users') ->
    @el.dataToolbar().classList.add 'hidden'
    @el.contentRow().classList.add 'hidden'
    @el.welcome().classList.add 'hidden'
    @el.yamlEditorPanel().classList.add 'hidden'
    @el.adminPanel().classList.remove 'hidden'
    @el.adminUsersSection().classList.add 'hidden'
    @el.adminGroupsSection().classList.add 'hidden'
    @el.adminSnapshotSection().classList.add 'hidden'
    if section == 'users'
      @el.adminUsersSection().classList.remove 'hidden'
      @_loadAdminUsers()
    else if section == 'groups'
      @el.adminGroupsSection().classList.remove 'hidden'
      @_loadAdminGroups()
    else
      @el.adminSnapshotSection().classList.remove 'hidden'

  _hideAdminPanel: ->
    @el.adminPanel().classList.add 'hidden'

  _loadAdminUsers: ->
    Auth.listUsers().then (users) =>
      ul = @el.adminUsersList()
      ul.innerHTML = ''
      for u in users
        li = document.createElement 'li'
        li.className = 'admin-list-item'
        groupNames = (u.groups or []).map((g) -> g.name).join(', ') or '—'
        li.innerHTML = "<span class='admin-item-name'>#{u.username}</span><span class='admin-item-meta'>#{groupNames}</span>"
        # Bouton changer mot de passe
        btnPwd = document.createElement 'button'
        btnPwd.className = 'toolbar-btn'
        btnPwd.textContent = '🔑'
        btnPwd.title = @_t('ui.admin.pwdBtnTitle')
        btnPwd.addEventListener 'click', =>
          uid = u.id
          newPwd = await tdbPrompt @_t('ui.prompts.newPasswordFor', { username: u.username })
          return unless newPwd?.trim()
          GQL.mutate('mutation SetPwd($uid: ID!, $pwd: String!) { adminSetPassword(userId: $uid, newPassword: $pwd) }', { uid, pwd: newPwd })
            .then => tdbAlert @_t('ui.alerts.passwordChanged'), 'info'
            .catch (err) => tdbAlert @_err(err), 'error'
        li.appendChild btnPwd
        ul.appendChild li
      # Bouton créer
      @el.adminCreateUserBtn().onclick = => @el.createUserDialog().classList.remove 'hidden'
    .catch (err) => tdbAlert @_err(err), 'error'

  _loadAdminGroups: ->
    Auth.listGroups().then (groups) =>
      ul = @el.adminGroupsList()
      ul.innerHTML = ''
      for g in groups
        li = document.createElement 'li'
        li.className = 'admin-list-item'
        memberNames = (g.members or []).map((m) -> m.username).join(', ') or '—'
        li.innerHTML = "<span class='admin-item-name'>#{g.name}</span><span class='admin-item-meta'>#{memberNames}</span>"
        # Bouton supprimer groupe
        unless g.name == 'admin'
          btnDel = document.createElement 'button'
          btnDel.className = 'toolbar-btn toolbar-btn--icon toolbar-btn--danger'
          btnDel.textContent = '🗑'
          btnDel.title = @_t('ui.admin.deleteGroupTitle')
          btnDel.addEventListener 'click', =>
            gid = g.id
            gname = g.name
            return unless await tdbConfirm @_t('ui.confirms.deleteGroup', { name: gname })
            Auth.deleteGroup(gid)
              .then => @_loadAdminGroups()
              .catch (err) => tdbAlert @_err(err), 'error'
          li.appendChild btnDel
        ul.appendChild li
      @el.adminCreateGroupBtn().onclick = => @el.createGroupDialog().classList.remove 'hidden'
    .catch (err) => tdbAlert @_err(err), 'error'

  # ── Dialog: changement de mot de passe ──────────────────────────────────────
  _openChangePasswordDialog: ->
    @el.cpCurrent().value = ''
    @el.cpNew().value = ''
    @el.cpConfirm().value = ''
    @el.cpError().textContent = ''
    @el.changePasswordDialog().classList.remove 'hidden'

  _bindChangePasswordDialog: ->
    @el.cpCancelBtn().addEventListener 'click', =>
      @el.changePasswordDialog().classList.add 'hidden'

    @el.changePasswordDialog().addEventListener 'keydown', (e) =>
      if e.key == 'Enter' then @el.cpSubmitBtn().click()
      if e.key == 'Escape' then @el.changePasswordDialog().classList.add 'hidden'

    @el.cpSubmitBtn().addEventListener 'click', =>
      current = @el.cpCurrent().value
      nw      = @el.cpNew().value
      confirm = @el.cpConfirm().value
      @el.cpError().textContent = ''
      unless current and nw
        @el.cpError().textContent = @_t('ui.validation.requiredAllFields')
        return
      unless nw == confirm
        @el.cpError().textContent = @_t('ui.validation.newPasswordsMismatch')
        return
      Auth.changePassword(current, nw)
        .then (ok) =>
          if ok
            localStorage.setItem 'tdb_password_changed', '1'
            @el.changePasswordDialog().classList.add 'hidden'
            @el.defaultPasswordWarning().classList.add 'hidden'
            tdbAlert @_t('ui.alerts.passwordChangedSuccess'), 'info'
          else
            @el.cpError().textContent = @_t('ui.validation.currentPasswordIncorrect')
        .catch (err) =>
          @el.cpError().textContent = @_err(err)

  # ── Dialog: créer utilisateur ─────────────────────────────────────────────
  _bindCreateUserDialog: ->
    @el.cuCancelBtn().addEventListener 'click', =>
      @el.createUserDialog().classList.add 'hidden'

    @el.cuSubmitBtn().addEventListener 'click', =>
      username = @el.cuUsername().value.trim()
      email    = @el.cuEmail().value.trim()
      password = @el.cuPassword().value
      @el.cuError().textContent = ''
      unless username and password
        @el.cuError().textContent = @_t('ui.validation.usernamePasswordRequired')
        return
      Auth.createUser(username, email or null, password)
        .then =>
          @el.createUserDialog().classList.add 'hidden'
          @el.cuUsername().value = ''
          @el.cuEmail().value = ''
          @el.cuPassword().value = ''
          @_loadAdminUsers()
        .catch (err) =>
          @el.cuError().textContent = @_err(err)

  # ── Dialog: créer groupe ──────────────────────────────────────────────────
  _bindCreateGroupDialog: ->
    @el.cgCancelBtn().addEventListener 'click', =>
      @el.createGroupDialog().classList.add 'hidden'

    @el.cgSubmitBtn().addEventListener 'click', =>
      name        = @el.cgName().value.trim()
      description = @el.cgDescription().value.trim()
      @el.cgError().textContent = ''
      unless name
        @el.cgError().textContent = @_t('ui.validation.groupNameRequired')
        return
      Auth.createGroup(name, description)
        .then =>
          @el.createGroupDialog().classList.add 'hidden'
          @el.cgName().value = ''
          @el.cgDescription().value = ''
          @_loadAdminGroups()
        .catch (err) =>
          @el.cgError().textContent = @_err(err)

  # ── Snapshot export / import ─────────────────────────────────────────────────
  _bindSnapshotPanel: ->
    @_snapshotYaml = null

    # ── Export ──────────────────────────────────────────────────────────────────
    _doExport = (includeData) =>
      GQL.query("""
        query($d: Boolean!) { exportSnapshot(includeData: $d) }
      """, { d: includeData }).then (data) ->
        yaml   = data.exportSnapshot
        fname  = if includeData then 'backup.tdb.yaml' else 'schema.tdb.yaml'
        blob   = new Blob [yaml], { type: 'text/yaml' }
        url    = URL.createObjectURL blob
        a      = document.createElement 'a'
        a.href = url
        a.download = fname
        a.click()
        URL.revokeObjectURL url
      .catch (err) => tdbAlert @_err(err), 'error'

    @el.snapshotExportSchemaBtn().addEventListener 'click', => _doExport false
    @el.snapshotExportFullBtn().addEventListener   'click', => _doExport true

    # ── Import — file selection → diff ──────────────────────────────────────────
    @el.snapshotFileInput().addEventListener 'change', (e) =>
      file = e.target.files[0]
      return unless file
      @el.snapshotFileName().textContent = file.name
      @el.snapshotDiffBox().classList.add 'hidden'
      @el.snapshotImportResult().classList.add 'hidden'
      @el.snapshotImportError().classList.add 'hidden'
      reader = new FileReader()
      reader.onload = (ev) =>
        @_snapshotYaml = ev.target.result
        GQL.query("""
          query($y: String!) { diffSnapshot(yaml: $y) {
            spacesToCreate spacesToDelete
            fieldsToCreate { space field oldType newType }
            fieldsToDelete { space field oldType newType }
            fieldsToChange { space field oldType newType }
            customViewsToCreate customViewsToUpdate
          } }
        """, { y: @_snapshotYaml })
        .then (data) =>
          diff = data.diffSnapshot
          @_renderSnapshotDiff diff
          @el.snapshotDiffBox().classList.remove 'hidden'
        .catch (err) =>
          @el.snapshotImportError().textContent = @_err(err)
          @el.snapshotImportError().classList.remove 'hidden'
      reader.readAsText file

    # ── Import — confirm ─────────────────────────────────────────────────────────
    @el.snapshotImportConfirmBtn().addEventListener 'click', =>
      return unless @_snapshotYaml
      mode = document.querySelector('input[name="snapshot-mode"]:checked')?.value or 'merge'
      if mode == 'replace'
        unless await tdbConfirm @_t('ui.confirms.replaceImport')
          return
      @el.snapshotImportConfirmBtn().disabled = true
      GQL.mutate("""
        mutation($y: String!, $m: ImportMode!) {
          importSnapshot(yaml: $y, mode: $m) { ok created skipped errors }
        }
      """, { y: @_snapshotYaml, m: mode })
      .then (data) =>
        r = data.importSnapshot
        @el.snapshotImportConfirmBtn().disabled = false
        @el.snapshotDiffBox().classList.add 'hidden'
        res = @el.snapshotImportResult()
        res.classList.remove 'hidden'
        if r.ok
          res.className = 'snapshot-import-result snapshot-result-ok'
          res.innerHTML = @_t('ui.snapshot.importOk', { created: r.created, skipped: r.skipped })
        else
          res.className = 'snapshot-import-result snapshot-result-err'
          res.innerHTML = @_t('ui.snapshot.importErr', { created: r.created, skipped: r.skipped }) + '<br>' +
            r.errors.map((e) -> "<code>#{e}</code>").join('<br>')
        # Reload spaces/views to reflect changes
        @_loadAll() if r.ok or r.created > 0
      .catch (err) =>
        @el.snapshotImportConfirmBtn().disabled = false
        @el.snapshotImportError().textContent = @_err(err)
        @el.snapshotImportError().classList.remove 'hidden'

  _renderSnapshotDiff: (diff) ->
    c = @el.snapshotDiffContent()
    c.innerHTML = ''
    _section = (title, items, cls) ->
      return unless items and items.length > 0
      h = document.createElement 'h5'
      h.textContent = title
      c.appendChild h
      ul = document.createElement 'ul'
      ul.className = cls
      for item in items
        li = document.createElement 'li'
        if typeof item == 'string'
          li.textContent = item
        else
          # FieldDiff
          if item.oldType and item.newType
            li.innerHTML = "<code>#{item.space}.#{item.field}</code> : <em>#{item.oldType}</em> → <strong>#{item.newType}</strong>"
          else if item.newType
            li.innerHTML = @_t('ui.snapshot.fieldToCreate', item)
          else
            li.innerHTML = @_t('ui.snapshot.fieldToDelete', item)
        ul.appendChild li
      c.appendChild ul

    noop = diff.spacesToCreate.length == 0 and diff.spacesToDelete.length == 0 and
           diff.fieldsToCreate.length == 0 and diff.fieldsToDelete.length == 0 and
           diff.fieldsToChange.length == 0 and diff.customViewsToCreate.length == 0 and
           diff.customViewsToUpdate.length == 0

    if noop
      p = document.createElement 'p'
      p.className = 'snapshot-diff-noop'
      p.textContent = @_t('ui.snapshot.noop')
      c.appendChild p
    else
      _section @_t('ui.snapshot.sectionSpacesDelete'), diff.spacesToDelete, 'diff-list diff-delete'
      _section @_t('ui.snapshot.sectionSpacesCreate'), diff.spacesToCreate, 'diff-list diff-create'
      _section @_t('ui.snapshot.sectionFieldsDelete'), diff.fieldsToDelete, 'diff-list diff-delete'
      _section @_t('ui.snapshot.sectionFieldsChange'), diff.fieldsToChange, 'diff-list diff-change'
      _section @_t('ui.snapshot.sectionFieldsCreate'), diff.fieldsToCreate, 'diff-list diff-create'
      _section @_t('ui.snapshot.sectionCustomViewsCreate'), diff.customViewsToCreate, 'diff-list diff-create'
      _section @_t('ui.snapshot.sectionCustomViewsUpdate'), diff.customViewsToUpdate, 'diff-list diff-change'

  # ── Hash-based navigation ────────────────────────────────────────────────────
  _restoreFromHash: ->
    hash = window.location.hash
    if m = hash.match /^#space\/(.+)$/
      spaceId = m[1]
      sp = (@_allSpaces or []).find (s) -> s.id == spaceId
      @selectSpace sp if sp
    else if m = hash.match /^#view\/(.+)$/
      viewId = m[1]
      ul = @el.customViewList()
      cvItems = ul.querySelectorAll 'li'
      for li in cvItems
        if li.dataset.id == viewId
          li.click()
          break

  # ── Spaces (Données section) ─────────────────────────────────────────────────
  loadSpaces: ->
    Spaces.list()
      .then (spaces) =>
        @_allSpaces = spaces
        @renderSpaceList spaces
      .catch (err) => tdbAlert @_err(err), 'error'

  renderSpaceList: (spaces) ->
    ul = @el.spaceList()
    ul.innerHTML = ''
    # Tri alphabétique insensible à la casse
    sortedSpaces = [spaces...].sort (a, b) ->
      a.name.toLowerCase().localeCompare b.name.toLowerCase()

    for sp in sortedSpaces
      li = document.createElement 'li'
      li.textContent = sp.name
      li.dataset.id  = sp.id
      do (sp) =>
        li.addEventListener 'click', => @selectSpace sp
      ul.appendChild li
      li.textContent = sp.name
      li.dataset.id  = sp.id
      do (sp) =>
        li.addEventListener 'click', => @selectSpace sp
      ul.appendChild li

  selectSpace: (sp) ->
    history.replaceState null, '', "#space/#{sp.id}"
    for li in @el.customViewList().querySelectorAll 'li'
      li.classList.remove 'active'
    # Highlight space item
    for li in @el.spaceList().querySelectorAll 'li'
      li.classList.toggle 'active', li.dataset.id == sp.id

    @_currentCustomView = null
    @_activeCustomView?.unmount?()
    @_activeCustomView = null

    # Close fields panel
    @el.fieldsPanel().classList.add 'hidden'
    @el.fieldsBtn().classList.remove 'active'

    # Hide admin panel
    @el.adminPanel().classList.add 'hidden'

    # Show data toolbar, hide YAML panel + custom view
    @el.dataToolbar().classList.remove 'hidden'
    @el.yamlEditorPanel().classList.add 'hidden'
    @el.customViewContainer().classList.add 'hidden'
    @el.gridContainer().classList.remove 'hidden'
    @el.welcome().classList.add 'hidden'
    @el.contentRow().classList.remove 'hidden'

    Spaces.getWithFields(sp.id)
      .then (full) =>
        @_currentSpace = full
        @el.dataTitle().textContent = full.name
        @_mountDataView full
      .catch (err) => tdbAlert @_err(err), 'error'

  # Keep @_allSpaces in sync after any field mutation on the current space.
  # If a custom view is active, rebuilds it so widgets get the fresh columns.
  _syncSpaceFields: (space) ->
    @_allSpaces = (@_allSpaces or []).map (s) => if s.id == space.id then space else s
    if @_activeCustomView and @_currentCustomView?.yaml?.trim()
      @_renderCustomViewPreview @_currentCustomView.yaml

  _mountDataView: (space) ->
    @_activeDataView?.unmount?()
    container = @el.gridContainer()
    relations = await Spaces.listRelations(space.id)
    @_activeDataView = new DataView container, space, null, relations
    @_activeDataView.mount()
    # Reset filter bar
    input = @el.formulaFilterInput()
    if input
      input.value = ''
      input.classList.remove 'active'

  # ── Custom views (Vues section) ──────────────────────────────────────────────
  loadCustomViews: ->
    GQL.query(LIST_CUSTOM_VIEWS)
      .then (data) => @renderCustomViewList data.customViews
      .catch (err) => tdbAlert @_err(err), 'error'

  renderCustomViewList: (views) ->
    ul = @el.customViewList()
    ul.innerHTML = ''

    # 1. Grouper en arbre
    tree = { items: [], folders: {} }
    for cv in (views or [])
      parts = cv.name.split '/'
      curr = tree
      # Dossiers intermédiaires
      for dictName in parts[0 ... -1]
        curr.folders[dictName] ?= { items: [], folders: {} }
        curr = curr.folders[dictName]
      # Insertion terminale (on garde cv original mais avec le nom court)
      curr.items.push { cv: cv, shortName: parts[parts.length - 1] }

    # 2. Fonction récursive de rendu
    renderTree = (node, containerEl, pathStr = "") =>
      # Trier les dossiers par ordre alphabétique
      folderNames = Object.keys(node.folders).sort (a, b) -> a.toLowerCase().localeCompare b.toLowerCase()
      for fName in folderNames
        fNode = node.folders[fName]
        fullPath = if pathStr then "#{pathStr}/#{fName}" else fName

        folderLi = document.createElement 'li'
        folderLi.className = 'folder-item'

        # Header du dossier
        header = document.createElement 'div'
        header.className = 'folder-header'
        icon = document.createElement 'span'
        icon.className = 'folder-toggle-icon'
        icon.textContent = '▾'
        header.appendChild icon
        header.appendChild document.createTextNode(" #{fName}")
        folderLi.appendChild header

        # Liste déroulante
        subUl = document.createElement 'ul'
        subUl.className = 'folder-children'
        folderLi.appendChild subUl

        # État du dossier dans le localStorage
        lsKey = "tdb_folder_view_#{fullPath}"
        if localStorage.getItem(lsKey) == 'true'
          folderLi.classList.add 'collapsed'

        header.addEventListener 'click', (e) ->
          e.stopPropagation()
          isCollapsed = folderLi.classList.toggle 'collapsed'
          localStorage.setItem lsKey, if isCollapsed then 'true' else 'false'

        renderTree fNode, subUl, fullPath
        containerEl.appendChild folderLi

      # Trier les items (vues)
      sortedItems = node.items.sort (a, b) -> a.shortName.toLowerCase().localeCompare b.shortName.toLowerCase()
      for item in sortedItems
        li = document.createElement 'li'
        li.className = 'leaf-item'
        li.textContent = item.shortName
        li.dataset.id  = item.cv.id
        li.title = item.cv.name  # Le vrai nom complet sur hover
        do (cv = item.cv) =>
           li.addEventListener 'click', (e) =>
             e.stopPropagation()
             @selectCustomView cv
        containerEl.appendChild li

    renderTree tree, ul

  selectCustomView: (cv) ->
    history.replaceState null, '', "#view/#{cv.id}"
    @_currentCustomView = cv
    # Deactivate space items
    for li in @el.spaceList().querySelectorAll 'li'
      li.classList.remove 'active'
    for li in @el.customViewList().querySelectorAll '.leaf-item'
      li.classList.toggle 'active', li.dataset.id == cv.id
      # Si active, on s'assure que les dossiers parents sont ouverts
      if li.dataset.id == cv.id
        parent = li.parentElement
        while parent and parent.id != 'custom-view-list'
          if parent.tagName == 'LI' and parent.classList.contains('folder-item')
            parent.classList.remove 'collapsed'
            # Sauvegarder l'état ouvert du parent dans le localStorage
            # (Peut être délicat de retrouver le nom exact du parent,
            # mais on a la classe 'collapsed' enlevée).
          parent = parent.parentElement

    @_currentSpace = null
    @_activeDataView?.unmount?()
    @_activeDataView = null

    # Hide data grid area and admin panel
    @el.dataToolbar().classList.add 'hidden'
    @el.fieldsPanel().classList.add 'hidden'
    @el.gridContainer().classList.add 'hidden'
    @el.welcome().classList.add 'hidden'
    @el.adminPanel().classList.add 'hidden'
    @el.contentRow().classList.remove 'hidden'

    panel = @el.yamlEditorPanel()
    panel.classList.remove 'hidden'
    @el.yamlViewName().textContent = cv.name

    # If YAML exists, render preview; otherwise open the editor modal directly
    if cv.yaml?.trim()
      @_renderCustomViewPreview cv.yaml
    else
      @_openYamlModal()

  _renderCustomViewPreview: (yamlText) ->
    container = @el.customViewContainer()
    @_activeCustomView?.unmount?()
    container.innerHTML = ''
    container.classList.remove 'hidden'
    @_activeCustomView = new CustomView container, yamlText, @_allSpaces
    @_activeCustomView.mount()

  # ── YAML editor ─────────────────────────────────────────────────────────────
  _bindYamlEditor: ->
    @el.yamlEditBtn().addEventListener 'click', =>
      @_openYamlModal()

    @el.yamlDeleteBtn().addEventListener 'click', =>
      cv = @_currentCustomView
      return unless cv
      return unless await tdbConfirm @_t('ui.confirms.deleteView', { name: cv.name })
      GQL.mutate(DELETE_CUSTOM_VIEW, { id: cv.id })
        .then =>
          @_currentCustomView = null
          @_activeCustomView?.unmount?()
          @_activeCustomView = null
          @el.yamlEditorPanel().classList.add 'hidden'
          @el.customViewContainer().classList.add 'hidden'
          @el.welcome().classList.remove 'hidden'
          @loadCustomViews()
        .catch (err) => tdbAlert @_err(err), 'error'

    @el.yamlModalSaveBtn().addEventListener 'click', =>
      cv = @_currentCustomView
      return unless cv
      yaml = @_cmYaml.getValue()
      GQL.mutate(UPDATE_CUSTOM_VIEW, { id: cv.id, input: { yaml } })
        .then (data) =>
          @_currentCustomView = data.updateCustomView
          @el.yamlModal().classList.add 'hidden'
          @_renderCustomViewPreview yaml
          @loadCustomViews()
        .catch (err) => tdbAlert @_err(err), 'error'

    @el.yamlModalCloseBtn().addEventListener 'click', =>
      @el.yamlModal().classList.add 'hidden'

    @el.yamlModalPreviewBtn().addEventListener 'click', =>
      return unless @_cmYaml
      @_renderCustomViewPreview @_cmYaml.getValue()

  _openYamlModal: ->
    cv = @_currentCustomView
    return unless cv
    @el.yamlModalTitle().textContent = cv.name
    @el.yamlModal().classList.remove 'hidden'
    unless @_cmYaml
      @_cmYaml = CodeMirror document.getElementById('yaml-cm-editor'),
        mode: 'yaml'
        theme: 'monokai'
        lineNumbers: true
        lineWrapping: true
        tabSize: 2
        indentWithTabs: false
      # When the user manually edits the YAML, re-sync the ERD builder and validate.
      # 'setValue' origin = programmatic; anything else = user input.
      @_cmYaml.on 'change', (cm, change) =>
        unless @_yamlValidMsg
          @_yamlValidMsg = document.getElementById 'yaml-validation-msg'
        # Programmatic setValue: clear any stale error and skip ERD sync
        if change.origin == 'setValue'
          @_yamlValidMsg?.classList.add 'hidden'
          return
        @_yamlBuilder?.reloadFromYaml cm.getValue()
        # Live YAML validation feedback while user types
        try
          jsyaml.load cm.getValue()
          @_yamlValidMsg?.classList.add 'hidden'
        catch e
          if @_yamlValidMsg
            @_yamlValidMsg.textContent = "YAML invalide : #{e.message}"
            @_yamlValidMsg.classList.remove 'hidden'
    @_cmYaml.setValue cv.yaml or ''
    setTimeout (=> @_cmYaml.refresh()), 10
    # Schema browser
    @_loadAllRelations().then (relations) =>
      @_yamlBuilder = new YamlBuilder
        container:    document.getElementById 'schema-browser'
        allSpaces:    @_allSpaces
        allRelations: relations
        initialYaml:  cv.yaml or ''
        onChange:     (yaml) => @_cmYaml?.setValue yaml
      @_yamlBuilder.mount()

  _loadAllRelations: ->
    return Promise.resolve @_allRelations if @_allRelations
    Promise.all(@_allSpaces.map (sp) -> Spaces.listRelations sp.id)
      .then (results) =>
        @_allRelations = results.reduce ((a, b) -> a.concat b), []
        @_allRelations

  # ── Data toolbar ─────────────────────────────────────────────────────────────
  _bindDataToolbar: ->
    @el.deleteRowsBtn().addEventListener 'click', =>
      @_activeDataView?.deleteSelected()

    # Formula filter input (debounced, sends to active DataView)
    @_formulaTimer = null
    @el.formulaFilterInput().addEventListener 'input', (e) =>
      clearTimeout @_formulaTimer
      val = e.target.value.trim()
      e.target.classList.toggle 'active', val != ''
      @_formulaTimer = setTimeout =>
        @_activeDataView?.setFormulaFilter val
      , 400

    @el.deleteSpaceBtn().addEventListener 'click', =>
      return unless @_currentSpace
      name = @_currentSpace.name
      return unless await tdbConfirm @_t('ui.confirms.deleteSpace', { name })
      Spaces.delete(@_currentSpace.id)
        .then =>
          @_currentSpace = null
          @_activeDataView?.unmount?()
          @_activeDataView = null
          @el.dataToolbar().classList.add 'hidden'
          @el.fieldsPanel().classList.add 'hidden'
          @el.fieldsBtn().classList.remove 'active'
          @el.welcome().classList.remove 'hidden'
          @_loadAll()
        .catch (err) => tdbAlert @_err(err), 'error'

    @el.renameSpaceBtn().addEventListener 'click', =>
      return unless @_currentSpace
      newName = await tdbPrompt @_t('ui.prompts.renameSpace'), @_currentSpace.name
      return unless newName?.trim() and newName.trim() != @_currentSpace.name
      Spaces.update(@_currentSpace.id, newName.trim())
        .then (updated) =>
          @_currentSpace.name = updated.name
          @el.dataTitle().textContent = updated.name
          # Update sidebar
          li = @el.spaceList().querySelector("li[data-id='#{updated.id}']")
          li.textContent = updated.name if li
        .catch (err) => tdbAlert @_err(err), 'error'

  # ── Fields panel ─────────────────────────────────────────────────────────────
  _bindFieldsPanel: ->
    @el.fieldsBtn().addEventListener 'click', =>
      panel = @el.fieldsPanel()
      btn   = @el.fieldsBtn()
      if panel.classList.contains 'hidden'
        panel.classList.remove 'hidden'
        btn.classList.add 'active'
        @renderFieldsList()
      else
        panel.classList.add 'hidden'
        btn.classList.remove 'active'

    @el.fieldsPanelClose().addEventListener 'click', =>
      @el.fieldsPanel().classList.add 'hidden'
      @el.fieldsBtn().classList.remove 'active'

    # Show/hide formula section and relation target based on type selection
    @el.fieldType().addEventListener 'change', =>
      @_onFieldTypeChange()

    # Show/hide formula textarea and trigger-fields row based on radio selection
    document.querySelectorAll('input[name="formula-type"]').forEach (radio) =>
      radio.addEventListener 'change', =>
        val = document.querySelector('input[name="formula-type"]:checked').value
        @el.formulaBody().classList.toggle 'hidden', val == 'none'
        @el.triggerFieldsRow().classList.toggle 'hidden', val != 'trigger'

    # CodeMirror formula modal
    document.getElementById('formula-expand-btn').addEventListener 'click', =>
      lang = @el.formulaLanguage()?.value or 'lua'
      @el.formulaModal().classList.remove 'hidden'
      unless @_cmFormula
        @_cmFormula = CodeMirror document.getElementById('formula-cm-editor'),
          mode: lang
          theme: 'monokai'
          lineNumbers: true
          lineWrapping: true
          tabSize: 2
          indentWithTabs: false
      else
        @_cmFormula.setOption 'mode', lang
      @_cmFormula.setValue @el.fieldFormula().value
      setTimeout (=> @_cmFormula.refresh()), 10

    @el.formulaModalApplyBtn().addEventListener 'click', =>
      @el.fieldFormula().value = @_cmFormula.getValue() if @_cmFormula
      @el.formulaModal().classList.add 'hidden'

    @el.formulaModalCloseBtn().addEventListener 'click', =>
      @el.formulaModal().classList.add 'hidden'

    # Sync CM mode when language selector changes
    @el.formulaLanguage()?.addEventListener 'change', =>
      @_cmFormula?.setOption 'mode', @el.formulaLanguage().value

    @el.fieldCancelBtn().addEventListener 'click', =>
      @_resetFieldForm()


    @el.fieldAddBtn().addEventListener 'click', =>
      return unless @_currentSpace
      name    = @el.fieldName().value.trim()
      type    = @el.fieldType().value
      notNull = @el.fieldNotNull().checked
      unless name
        @el.fieldName().classList.add 'input-error'
        @el.fieldName().placeholder = @_t('ui.validation.groupNameRequired')
        @el.fieldName().focus()
        return
      @el.fieldName().classList.remove 'input-error'
      @el.fieldName().placeholder = @_t('ui.fields.namePlaceholder')

      if @_editingFieldId
        # ── Update existing field (including type change) ────────────────────────
        originalField = (@_currentSpace?.fields or []).find (f) => f.id == @_editingFieldId
        originalType = originalField?.fieldType

        formulaType = document.querySelector('input[name="formula-type"]:checked').value
        opts = { name, notNull }

        # Handle type change
        if type != originalType
          # Type is changing - use the changeFieldType API
          conversionFormula = null
          conversionLang = 'lua'

          # If changing to/from formula types, preserve existing formula
          if formulaType != 'none'
            conversionFormula = @el.fieldFormula().value.trim() or null
            conversionLang = @el.formulaLanguage()?.value or 'lua'

          Spaces.changeFieldType(@_editingFieldId, type, conversionFormula, conversionLang)
            .then =>
              # If changing to Relation, create the relation
              if type == 'Relation'
                toSpaceId   = @el.relToSpace().value
                reprFormula = @el.relReprFormula().value.trim()
                return unless toSpaceId
                Spaces.getWithFields(toSpaceId).then (targetSpace) =>
                  idField = (targetSpace.fields or []).find (f) -> f.fieldType == 'Sequence'
                  unless idField
                    tdbAlert @_t('ui.alerts.targetNoSequence'), 'warn'
                    return

                  Spaces.createRelation(
                    "#{@_currentSpace.name}_#{@el.fieldName().value}_rel",
                    @_currentSpace.id,
                    @_editingFieldId,
                    toSpaceId,
                    idField.id,
                    reprFormula
                  )
              else
                # After type change, update other field properties
                @updateFieldProperties(@_editingFieldId, opts, formulaType)
            .catch (err) => tdbAlert @_err(err), 'error'
        else
          # Same type - just update properties
          @updateFieldProperties(@_editingFieldId, opts, formulaType)

      else if type == 'Relation'
        # ── Create relation field ──────────────────────────────────────────
        toSpaceId   = @el.relToSpace().value
        reprFormula = @el.relReprFormula().value.trim()
        return unless toSpaceId
        Spaces.getWithFields(toSpaceId).then (targetSpace) =>
          idField = (targetSpace.fields or []).find (f) -> f.fieldType == 'Sequence'
          unless idField
            tdbAlert @_t('ui.alerts.targetNoSequence'), 'warn'
            return
          Spaces.addField(@_currentSpace.id, name, 'Int', notNull, '')
            .then (newField) =>
              Spaces.createRelation(name, @_currentSpace.id, newField.id, toSpaceId, idField.id, reprFormula)
                .then =>
                  Spaces.getWithFields(@_currentSpace.id).then (full) =>
                    @_currentSpace = full
                    @_syncSpaceFields full
                    @renderFieldsList()
                    @_mountDataView full
                .catch (err) => tdbAlert @_err(err), 'error'
            .catch (err) => tdbAlert @_err(err), 'error'
        @_resetFieldForm()

      else
        # ── Add new regular field ──────────────────────────────────────────
        formulaType   = document.querySelector('input[name="formula-type"]:checked').value
        formula       = null
        triggerFields = null
        language      = @el.formulaLanguage()?.value or 'lua'
        if formulaType != 'none'
          formula = @el.fieldFormula().value.trim() or null
          if formulaType == 'trigger' and formula
            raw = @el.fieldTriggerFields().value.trim()
            if raw == '*'
              triggerFields = ['*']
            else if raw == ''
              triggerFields = []
            else
              triggerFields = (s.trim() for s in raw.split(',') when s.trim())
        reprFormula = @el.fieldReprFormula()?.value.trim() or null
        Spaces.addField(@_currentSpace.id, name, type, notNull, '', formula, triggerFields, language, reprFormula)
          .then =>
            Spaces.getWithFields(@_currentSpace.id).then (full) =>
              @_currentSpace = full
              @_syncSpaceFields full
              @renderFieldsList()
              @_mountDataView full
          .catch (err) => tdbAlert @_err(err), 'error'
        @_resetFieldForm()

  _onFieldTypeChange: ->
    type = @el.fieldType().value
    isRelation = type == 'Relation'
    @el.relTargetRow().classList.toggle 'hidden', !isRelation
    @el.relReprRow().classList.toggle 'hidden', !isRelation
    @el.fieldNotNull().closest('label')?.classList.toggle 'hidden', isRelation
    formulaSection = @el.formulaBody().closest('.formula-section')
    formulaSection?.classList.toggle 'hidden', isRelation
    document.getElementById('field-repr-section')?.classList.toggle 'hidden', isRelation
    if isRelation
      # Populate target space selector
      sel = @el.relToSpace()
      sel.innerHTML = '<option value="">Cible…</option>'
      for sp in (@_allSpaces or [])
        opt = document.createElement 'option'
        opt.value = sp.id
        opt.textContent = sp.name
        sel.appendChild opt

  _resetFieldForm: ->
    @_editingFieldId = null
    @_editingRelation = null
    @el.fieldName().value = ''
    @el.fieldType().value = 'String'
    @el.fieldType().disabled = false  # Always enable type selector
    @el.fieldNotNull().checked = false
    @el.fieldFormula().value = ''
    @el.fieldTriggerFields().value = ''
    if @el.formulaLanguage() then @el.formulaLanguage().value = 'lua'
    document.querySelector('input[name="formula-type"][value="none"]').checked = true
    @el.formulaBody().classList.add 'hidden'
    @el.triggerFieldsRow().classList.add 'hidden'
    @el.relTargetRow().classList.add 'hidden'
    @el.relReprRow().classList.add 'hidden'
    @el.relReprFormula().value = ''
    @el.fieldReprFormula().value = '' if @el.fieldReprFormula()
    @el.fieldNotNull().closest('label')?.classList.remove 'hidden'
    formulaSection = @el.formulaBody().closest('.formula-section')
    formulaSection?.classList.remove 'hidden'
    @el.formulaModal().classList.add 'hidden'
    @el.fieldAddBtn().textContent = @_t('ui.fields.add')
    @el.fieldCancelBtn().classList.add 'hidden'

  updateFieldProperties: (fieldId, opts, formulaType) ->
    # Update formula-related properties
    if formulaType != 'none'
      opts.formula  = @el.fieldFormula().value.trim() or null
      opts.language = @el.formulaLanguage()?.value or 'lua'
      if formulaType == 'trigger' and opts.formula
        raw = @el.fieldTriggerFields().value.trim()
        if raw == '*'
          opts.triggerFields = ['*']
        else if raw == ''
          opts.triggerFields = []
        else
          opts.triggerFields = (s.trim() for s in raw.split(',') when s.trim())
    else
      opts.formula       = ''
      opts.triggerFields = null
      opts.language      = 'lua'
    opts.reprFormula = @el.fieldReprFormula()?.value.trim() or ''

    editRelation = @_editingRelation
    relReprFormula  = @el.relReprFormula().value.trim()
    updatePromise = Spaces.updateField(fieldId, opts)
    if editRelation
      updatePromise = updatePromise.then =>
        Spaces.updateRelation(editRelation.id, relReprFormula)
    updatePromise
      .then =>
        Spaces.getWithFields(@_currentSpace.id).then (full) =>
          @_currentSpace = full
          @_syncSpaceFields full
          @renderFieldsList()
          @_mountDataView full
          @_resetFieldForm()
      .catch (err) => tdbAlert @_err(err), 'error'

  renderFieldsList: ->
    return unless @_currentSpace
    ul = @el.fieldsList()
    ul.innerHTML = ''
    fields = @_currentSpace.fields or []
    # Fetch relations and render everything in one shot
    Spaces.listRelations(@_currentSpace.id).then (relations) =>
      # Build a map: fromFieldId → relation (with target space name resolved)
      relMap = {}
      spaceMap = {}

      # Build space name map
      for sp in @_allSpaces
        spaceMap[sp.id] = sp.name

      for r in (relations or [])
        relMap[r.fromFieldId] = r

      if fields.length == 0
        li = document.createElement 'li'
        li.textContent = @_t('ui.fields.noneDefined')
        li.style.color = '#aaa'
        ul.appendChild li
        return

      dragSrc = null
      for f in fields
        li = document.createElement 'li'
        li.draggable = true
        li.dataset.fieldId = f.id
        li.style.cursor = 'grab'

        handle = document.createElement 'span'
        handle.textContent = '⠿'
        handle.title = @_t('ui.fields.dragToReorder')
        handle.style.cssText = 'margin-right:.4rem;color:#888;cursor:grab;user-select:none;'

        rel = relMap[f.id]
        badge = document.createElement 'span'
        badge.className = 'field-type-badge'
        if rel
          targetName = spaceMap[rel.toSpaceId] or rel.toSpaceId
          badge.textContent = "→ #{targetName}"
          badge.title = "Relation vers #{targetName}"
        else
          badge.textContent = f.fieldType

        name = document.createElement 'span'
        name.textContent = " #{f.name} "
        name.style.flex = '1'
        if f.notNull
          req = document.createElement 'span'
          req.className = 'field-required'
          req.title = 'Requis'
          req.textContent = '*'
          name.appendChild req
        if f.formula and f.formula != '' and not rel
          fb = document.createElement 'span'
          langLabel = if f.language == 'moonscript' then ' [moon]' else ''
          if f.triggerFields
            fb.className = 'field-trigger-badge'
            triggerDesc =
              if f.triggerFields.length == 0 then @_t('ui.fields.triggerCreation')
              else if f.triggerFields[0] == '*' then @_t('ui.fields.triggerAnyChange')
              else f.triggerFields.join(', ')
            fb.textContent = '⚡'
            fb.title = "Trigger formula#{langLabel} (#{triggerDesc}) : #{f.formula}"
          else
            fb.className = 'field-formula-badge'
            fb.textContent = 'λ'
            fb.title = "#{@_t('ui.fields.computedColumn')}#{langLabel} : #{f.formula}"
          name.appendChild fb

        # Edit button (not for Sequence fields)
        editBtn = document.createElement 'button'
        editBtn.textContent = '✎'
        editBtn.title = 'Modifier ce champ'
        editBtn.style.cssText = 'background:none;border:none;cursor:pointer;color:#888;font-size:.9rem;margin-left:.2rem;'
        do (field = f, relation = rel) =>
          editBtn.addEventListener 'click', =>
            @_editingFieldId = field.id
            @_editingRelation = relation or null
            @el.fieldAddBtn().textContent = @_t('ui.fields.update')
            @el.fieldCancelBtn().classList.remove 'hidden'
            # Ensure type selector is enabled for direct editing
            @el.fieldType().disabled = false
            @el.fieldName().value = field.name
            if relation
              # Editing a relation field: show Cible and repr formula
              @el.fieldType().value = 'Relation'
              @_onFieldTypeChange()
              @el.relReprFormula().value = relation.reprFormula or ''
              @el.relToSpace().value = relation.toSpaceId or ''
              @el.fieldReprFormula().value = '' if @el.fieldReprFormula()
            else
              @el.fieldType().value = field.fieldType
              @_onFieldTypeChange()
              @el.fieldNotNull().checked = field.notNull
              @el.fieldReprFormula().value = field.reprFormula or '' if @el.fieldReprFormula()
              if field.formula and field.formula != ''
                if field.triggerFields
                  document.querySelector('input[name="formula-type"][value="trigger"]').checked = true
                  @el.triggerFieldsRow().classList.remove 'hidden'
                  tf = field.triggerFields
                  @el.fieldTriggerFields().value =
                    if tf.length == 0 then ''
                    else if tf[0] == '*' then '*'
                    else tf.join(', ')
                else
                  document.querySelector('input[name="formula-type"][value="formula"]').checked = true
                @el.formulaBody().classList.remove 'hidden'
                @el.fieldFormula().value = field.formula
                if @el.formulaLanguage() then @el.formulaLanguage().value = field.language or 'lua'
              else
                document.querySelector('input[name="formula-type"][value="none"]').checked = true
                @el.formulaBody().classList.add 'hidden'
            @el.fieldName().focus()

        del = document.createElement 'button'
        del.textContent = '✕'
        del.title = 'Supprimer ce champ'
        del.style.cssText = 'margin-left:.2rem;background:none;border:none;cursor:pointer;color:#aaa;font-size:.9rem;'
        do (fieldId = f.id, fieldName = f.name, relation = rel) =>
          del.addEventListener 'click', =>
            return unless await tdbConfirm @_t('ui.confirms.deleteField', { name: fieldName })
            doDelete = =>
              GQL.mutate(REMOVE_FIELD, { fieldId })
                .then =>
                  Spaces.getWithFields(@_currentSpace.id).then (full) =>
                    @_currentSpace = full
                    @_syncSpaceFields full
                    @renderFieldsList()
                    @_mountDataView full
                .catch (err) => tdbAlert @_err(err), 'error'
            if relation
              Spaces.deleteRelation(relation.id).then(doDelete).catch (err) => tdbAlert @_err(err), 'error'
            else
              doDelete()

        li.appendChild handle
        li.appendChild badge
        li.appendChild name
        li.appendChild editBtn
        li.appendChild del

        # Drag events
        li.addEventListener 'dragstart', (e) ->
          dragSrc = @
          e.dataTransfer.effectAllowed = 'move'
          e.dataTransfer.setData 'text/plain', @dataset.fieldId
          setTimeout (=> @classList.add 'dragging'), 0
        li.addEventListener 'dragend', ->
          @classList.remove 'dragging'
          ul.querySelectorAll('li').forEach (el) -> el.classList.remove 'drag-over'
        li.addEventListener 'dragover', (e) ->
          e.preventDefault()
          e.dataTransfer.dropEffect = 'move'
          ul.querySelectorAll('li').forEach (el) -> el.classList.remove 'drag-over'
          @classList.add 'drag-over' unless @ == dragSrc
        li.addEventListener 'drop', (e) =>
          e.preventDefault()
          target = e.currentTarget
          return if dragSrc == target
          rect = target.getBoundingClientRect()
          insertBefore = e.clientY < rect.top + rect.height / 2
          if insertBefore
            ul.insertBefore dragSrc, target
          else
            target.after dragSrc
          newOrder = Array.from(ul.querySelectorAll('li')).map (el) -> el.dataset.fieldId
          GQL.mutate(REORDER_FIELDS, { spaceId: @_currentSpace.id, fieldIds: newOrder })
            .then (res) =>
              @_currentSpace.fields = res.reorderFields
              @_syncSpaceFields @_currentSpace
              @renderFieldsList()
              @_mountDataView @_currentSpace
            .catch (err) => tdbAlert @_err(err), 'error'
        ul.appendChild li

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
