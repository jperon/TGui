# app_sidebar_helpers.coffee — sidebar/admin/dialog helpers extracted from app.coffee

window.AppSidebarHelpers =
  applySidebarState: (app) ->
    if localStorage.getItem('tdb_menu_state') == 'collapsed'
      app.el.main().classList.add 'sidebar-collapsed'
    else
      app.el.main().classList.remove 'sidebar-collapsed'

    spList = app.el.spaceList()
    spBtn  = document.getElementById 'spaces-toggle-btn'
    if localStorage.getItem('tdb_spaces_collapsed') == 'true'
      spList.classList.add 'hidden'
      spBtn?.classList.add 'collapsed'
    else
      spList.classList.remove 'hidden'
      spBtn?.classList.remove 'collapsed'

  bindSidebar: (app) ->
    app.el.newSpaceBtn().addEventListener 'click', ->
      name = await tdbPrompt app._t('ui.prompts.newSpace')
      return unless name?.trim()
      Spaces.create(name.trim())
        .then -> app._loadAll()
        .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.newViewBtn().addEventListener 'click', ->
      name = await tdbPrompt app._t('ui.prompts.newView')
      return unless name?.trim()
      GQL.mutate(app._createCustomViewMutation, { input: { name: name.trim(), yaml: "layout:\n  direction: vertical\n  children: []\n" } })
        .then (data) ->
          app.loadCustomViews().then ->
            cv = data.createCustomView
            app.selectCustomView cv
        .catch (err) -> tdbAlert app._err(err), 'error'

    document.getElementById('sidebar-toggle')?.addEventListener 'click', ->
      mainEl = app.el.main()
      isCollapsed = mainEl.classList.contains 'sidebar-collapsed'
      if isCollapsed
        mainEl.classList.remove 'sidebar-collapsed'
        localStorage.removeItem 'tdb_menu_state'
      else
        mainEl.classList.add 'sidebar-collapsed'
        localStorage.setItem 'tdb_menu_state', 'collapsed'

    document.getElementById('spaces-toggle-btn')?.addEventListener 'click', ->
      spList = app.el.spaceList()
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

    app._applySidebarState()

    app.el.currentUserBtn().addEventListener 'click', ->
      menu = app.el.userMenu()
      menu.classList.toggle 'hidden'
    document.addEventListener 'click', (e) ->
      unless app.el.currentUserBtn().contains(e.target) or app.el.userMenu().contains(e.target)
        app.el.userMenu().classList.add 'hidden'

    app.el.changePasswordBtn().addEventListener 'click', ->
      app.el.userMenu().classList.add 'hidden'
      app._openChangePasswordDialog()

    app.el.logoutBtn().addEventListener 'click', ->
      Auth.logout()
    app.el.langFrBtn()?.addEventListener 'click', ->
      window.I18N?.setLocale 'fr'
    app.el.langEnBtn()?.addEventListener 'click', ->
      window.I18N?.setLocale 'en'

    app.el.adminNavUsers().addEventListener 'click', ->
      app._showAdminPanel 'users'
    app.el.adminNavGroups().addEventListener 'click', ->
      app._showAdminPanel 'groups'
    app.el.adminNavSnapshot().addEventListener 'click', ->
      app._showAdminPanel 'snapshot'

    app.el.warningChangePasswordBtn().addEventListener 'click', ->
      app._openChangePasswordDialog()

    app._bindChangePasswordDialog()
    app._bindCreateUserDialog()
    app._bindCreateGroupDialog()
    app._bindSnapshotPanel()

  showAdminPanel: (app, section = 'users') ->
    app.el.dataToolbar().classList.add 'hidden'
    app.el.contentRow().classList.add 'hidden'
    app.el.welcome().classList.add 'hidden'
    app.el.yamlEditorPanel().classList.add 'hidden'
    app.el.adminPanel().classList.remove 'hidden'
    app.el.adminUsersSection().classList.add 'hidden'
    app.el.adminGroupsSection().classList.add 'hidden'
    app.el.adminSnapshotSection().classList.add 'hidden'
    if section == 'users'
      app.el.adminUsersSection().classList.remove 'hidden'
      app._loadAdminUsers()
    else if section == 'groups'
      app.el.adminGroupsSection().classList.remove 'hidden'
      app._loadAdminGroups()
    else
      app.el.adminSnapshotSection().classList.remove 'hidden'

  hideAdminPanel: (app) ->
    app.el.adminPanel().classList.add 'hidden'

  loadAdminUsers: (app) ->
    Auth.listUsers().then (users) ->
      ul = app.el.adminUsersList()
      ul.innerHTML = ''
      for u in users
        li = document.createElement 'li'
        li.className = 'admin-list-item'
        groupNames = (u.groups or []).map((g) -> g.name).join(', ') or '—'
        spanName = document.createElement 'span'
        spanName.className = 'admin-item-name'
        spanName.textContent = u.username
        spanMeta = document.createElement 'span'
        spanMeta.className = 'admin-item-meta'
        spanMeta.textContent = groupNames
        li.appendChild spanName
        li.appendChild spanMeta
        btnPwd = document.createElement 'button'
        btnPwd.className = 'toolbar-btn'
        btnPwd.textContent = '🔑'
        btnPwd.title = app._t('ui.admin.pwdBtnTitle')
        btnPwd.addEventListener 'click', ->
          uid = u.id
          newPwd = await tdbPrompt app._t('ui.prompts.newPasswordFor', { username: u.username })
          return unless newPwd?.trim()
          GQL.mutate('mutation SetPwd($uid: ID!, $pwd: String!) { adminSetPassword(userId: $uid, newPassword: $pwd) }', { uid, pwd: newPwd })
            .then -> tdbAlert app._t('ui.alerts.passwordChanged'), 'info'
            .catch (err) -> tdbAlert app._err(err), 'error'
        li.appendChild btnPwd
        ul.appendChild li
      app.el.adminCreateUserBtn().onclick = -> app.el.createUserDialog().classList.remove 'hidden'
    .catch (err) -> tdbAlert app._err(err), 'error'

  loadAdminGroups: (app) ->
    Auth.listGroups().then (groups) ->
      ul = app.el.adminGroupsList()
      ul.innerHTML = ''
      for g in groups
        li = document.createElement 'li'
        li.className = 'admin-list-item'
        memberNames = (g.members or []).map((m) -> m.username).join(', ') or '—'
        spanName = document.createElement 'span'
        spanName.className = 'admin-item-name'
        spanName.textContent = g.name
        spanMeta = document.createElement 'span'
        spanMeta.className = 'admin-item-meta'
        spanMeta.textContent = memberNames
        li.appendChild spanName
        li.appendChild spanMeta
        unless g.name == 'admin'
          btnDel = document.createElement 'button'
          btnDel.className = 'toolbar-btn toolbar-btn--icon toolbar-btn--danger'
          btnDel.textContent = '🗑'
          btnDel.title = app._t('ui.admin.deleteGroupTitle')
          btnDel.addEventListener 'click', ->
            gid = g.id
            gname = g.name
            return unless await tdbConfirm app._t('ui.confirms.deleteGroup', { name: gname })
            Auth.deleteGroup(gid)
              .then -> app._loadAdminGroups()
              .catch (err) -> tdbAlert app._err(err), 'error'
          li.appendChild btnDel
        ul.appendChild li
      app.el.adminCreateGroupBtn().onclick = -> app.el.createGroupDialog().classList.remove 'hidden'
    .catch (err) -> tdbAlert app._err(err), 'error'

  openChangePasswordDialog: (app) ->
    app.el.cpCurrent().value = ''
    app.el.cpNew().value = ''
    app.el.cpConfirm().value = ''
    app.el.cpError().textContent = ''
    app.el.changePasswordDialog().classList.remove 'hidden'

  bindChangePasswordDialog: (app) ->
    app.el.cpCancelBtn().addEventListener 'click', ->
      app.el.changePasswordDialog().classList.add 'hidden'

    app.el.changePasswordDialog().addEventListener 'keydown', (e) ->
      if e.key == 'Enter' then app.el.cpSubmitBtn().click()
      if e.key == 'Escape' then app.el.changePasswordDialog().classList.add 'hidden'

    app.el.cpSubmitBtn().addEventListener 'click', ->
      current = app.el.cpCurrent().value
      nw      = app.el.cpNew().value
      confirm = app.el.cpConfirm().value
      app.el.cpError().textContent = ''
      unless current and nw
        app.el.cpError().textContent = app._t('ui.validation.requiredAllFields')
        return
      unless nw == confirm
        app.el.cpError().textContent = app._t('ui.validation.newPasswordsMismatch')
        return
      Auth.changePassword(current, nw)
        .then (ok) ->
          if ok
            localStorage.setItem 'tdb_password_changed', '1'
            app.el.changePasswordDialog().classList.add 'hidden'
            app.el.defaultPasswordWarning().classList.add 'hidden'
            tdbAlert app._t('ui.alerts.passwordChangedSuccess'), 'info'
          else
            app.el.cpError().textContent = app._t('ui.validation.currentPasswordIncorrect')
        .catch (err) ->
          app.el.cpError().textContent = app._err(err)

  bindCreateUserDialog: (app) ->
    app.el.cuCancelBtn().addEventListener 'click', ->
      app.el.createUserDialog().classList.add 'hidden'

    app.el.cuSubmitBtn().addEventListener 'click', ->
      username = app.el.cuUsername().value.trim()
      email    = app.el.cuEmail().value.trim()
      password = app.el.cuPassword().value
      app.el.cuError().textContent = ''
      unless username and password
        app.el.cuError().textContent = app._t('ui.validation.usernamePasswordRequired')
        return
      Auth.createUser(username, email or null, password)
        .then ->
          app.el.createUserDialog().classList.add 'hidden'
          app.el.cuUsername().value = ''
          app.el.cuEmail().value = ''
          app.el.cuPassword().value = ''
          app._loadAdminUsers()
        .catch (err) ->
          app.el.cuError().textContent = app._err(err)

  bindCreateGroupDialog: (app) ->
    app.el.cgCancelBtn().addEventListener 'click', ->
      app.el.createGroupDialog().classList.add 'hidden'

    app.el.cgSubmitBtn().addEventListener 'click', ->
      name        = app.el.cgName().value.trim()
      description = app.el.cgDescription().value.trim()
      app.el.cgError().textContent = ''
      unless name
        app.el.cgError().textContent = app._t('ui.validation.groupNameRequired')
        return
      Auth.createGroup(name, description)
        .then ->
          app.el.createGroupDialog().classList.add 'hidden'
          app.el.cgName().value = ''
          app.el.cgDescription().value = ''
          app._loadAdminGroups()
        .catch (err) ->
          app.el.cgError().textContent = app._err(err)
