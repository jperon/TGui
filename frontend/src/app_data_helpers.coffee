# app_data_helpers.coffee — space/data toolbar/hash helpers extracted from app.coffee

window.AppDataHelpers =
  loadAll: (app) ->
    Promise.all([app.loadSpaces(), app.loadCustomViews()]).then -> app._restoreFromHash()

  restoreFromHash: (app) ->
    hash = window.location.hash
    if m = hash.match /^#space\/(.+)$/
      spaceId = m[1]
      sp = (app._allSpaces or []).find (s) -> s.id == spaceId
      app.selectSpace sp if sp
    else if m = hash.match /^#view\/(.+)$/
      viewId = m[1]
      ul = app.el.customViewList()
      cvItems = ul.querySelectorAll 'li'
      for li in cvItems
        if li.dataset.id == viewId
          li.click()
          break

  loadSpaces: (app) ->
    Spaces.list()
      .then (spaces) ->
        app._allSpaces = spaces
        app.renderSpaceList spaces
      .catch (err) -> tdbAlert app._err(err), 'error'

  renderSpaceList: (app, spaces) ->
    ul = app.el.spaceList()
    ul.innerHTML = ''
    sortedSpaces = [spaces...].sort (a, b) ->
      a.name.toLowerCase().localeCompare b.name.toLowerCase()

    for sp in sortedSpaces
      li = document.createElement 'li'
      li.textContent = sp.name
      li.dataset.id  = sp.id
      do (sp) ->
        li.addEventListener 'click', -> app.selectSpace sp
      ul.appendChild li
      li.textContent = sp.name
      li.dataset.id  = sp.id
      do (sp) ->
        li.addEventListener 'click', -> app.selectSpace sp
      ul.appendChild li

  selectSpace: (app, sp) ->
    history.replaceState null, '', "#space/#{sp.id}"
    for li in app.el.customViewList().querySelectorAll 'li'
      li.classList.remove 'active'
    for li in app.el.spaceList().querySelectorAll 'li'
      li.classList.toggle 'active', li.dataset.id == sp.id

    app._currentCustomView = null
    app._activeCustomView?.unmount?()
    app._activeCustomView = null

    app.el.fieldsPanel().classList.add 'hidden'
    app.el.fieldsBtn().classList.remove 'active'

    app.el.adminPanel().classList.add 'hidden'

    app.el.dataToolbar().classList.remove 'hidden'
    app.el.yamlEditorPanel().classList.add 'hidden'
    app.el.customViewContainer().classList.add 'hidden'
    app.el.gridContainer().classList.remove 'hidden'
    app.el.welcome().classList.add 'hidden'
    app.el.contentRow().classList.remove 'hidden'

    Spaces.getWithFields(sp.id)
      .then (full) ->
        app._currentSpace = full
        app.el.dataTitle().textContent = full.name
        app._mountDataView full
      .catch (err) -> tdbAlert app._err(err), 'error'

  syncSpaceFields: (app, space) ->
    app._allSpaces = (app._allSpaces or []).map (s) -> if s.id == space.id then space else s
    if app._activeCustomView and app._currentCustomView?.yaml?.trim()
      app._renderCustomViewPreview app._currentCustomView.yaml

  mountDataView: (app, space) ->
    app._activeDataView?.unmount?()
    container = app.el.gridContainer()
    relations = await Spaces.listRelations(space.id)
    app._activeDataView = new DataView container, space, null, relations,
      onColumnFocus: (colName) -> app._onGridColumnFocused colName
    app._activeDataView.mount()
    input = app.el.formulaFilterInput()
    if input
      input.value = ''
      input.classList.remove 'active'

  bindDataToolbar: (app) ->
    app.el.deleteRowsBtn().addEventListener 'click', ->
      app._activeDataView?.deleteSelected()

    window.AppFieldsHelpers.bindFormulaFilter app

    app.el.deleteSpaceBtn().addEventListener 'click', ->
      return unless app._currentSpace
      name = app._currentSpace.name
      return unless await tdbConfirm app._t('ui.confirms.deleteSpace', { name })
      Spaces.delete(app._currentSpace.id)
        .then ->
          app._currentSpace = null
          app._activeDataView?.unmount?()
          app._activeDataView = null
          app.el.dataToolbar().classList.add 'hidden'
          app.el.fieldsPanel().classList.add 'hidden'
          app.el.fieldsBtn().classList.remove 'active'
          app.el.welcome().classList.remove 'hidden'
          app._loadAll()
        .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.renameSpaceBtn().addEventListener 'click', ->
      return unless app._currentSpace
      newName = await tdbPrompt app._t('ui.prompts.renameSpace'), app._currentSpace.name
      return unless newName?.trim() and newName.trim() != app._currentSpace.name
      Spaces.update(app._currentSpace.id, newName.trim())
        .then (updated) ->
          app._currentSpace.name = updated.name
          app.el.dataTitle().textContent = updated.name
          li = app.el.spaceList().querySelector("li[data-id='#{updated.id}']")
          li.textContent = updated.name if li
        .catch (err) -> tdbAlert app._err(err), 'error'
