# app_data_helpers.coffee — space/data toolbar/hash helpers extracted from app.coffee

window.AppDataHelpers =
  loadAll: (app) ->
    Promise.all([app.loadSpaces(), app.loadPages(), app.loadDataViews()]).then -> app._restoreFromHash()

  restoreFromHash: (app) ->
    hash = window.location.hash
    if m = hash.match /^#space\/(.+)$/
      spaceId = m[1]
      sp = (app._allSpaces or []).find (s) -> s.id == spaceId
      app.selectSpace sp if sp
    else if m = hash.match /^#page\/(.+)$/
      viewId = m[1]
      ul = app.el.pageList()
      cvItems = ul.querySelectorAll 'li'
      for li in cvItems
        if li.dataset.id == viewId
          li.click()
          break
    else if m = hash.match /^#view\/(.+)$/
      viewId = m[1]
      ul = app.el.dataViewList()
      dvItems = ul.querySelectorAll 'li'
      for li in dvItems
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

  selectSpace: (app, sp) ->
    history.replaceState null, '', "#space/#{sp.id}"
    for li in app.el.pageList().querySelectorAll 'li'
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

    # Toolbar visibility for Spaces
    app.el.fieldsBtn().classList.remove 'hidden'
    app.el.deleteRowsBtn().classList.remove 'hidden'
    app.el.undoBtn().classList.remove 'hidden'
    app.el.redoBtn().classList.remove 'hidden'
    app.el.formulaFilterInput().classList.remove 'hidden'
    app.el.renameSpaceBtn().title = app._t('ui.toolbar.renameSpace')
    app.el.deleteSpaceBtn().title = app._t('ui.toolbar.deleteSpace')

    Spaces.getWithFields(sp.id)
      .then (full) ->
        app._currentSpace = full
        app.el.dataTitle().textContent = full.name
        app._mountDataView full
        window.AppUndoHelpers?.refreshUI? app
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
    window.AppUndoHelpers?.refreshUI? app

  bindDataToolbar: (app) ->
    window.AppUndoHelpers?.bindGlobalShortcuts? app

    app.el.undoBtn()?.addEventListener 'click', ->
      window.AppUndoHelpers?.undo? app

    app.el.redoBtn()?.addEventListener 'click', ->
      window.AppUndoHelpers?.redo? app

    app.el.deleteRowsBtn().addEventListener 'click', ->
      app._activeDataView?.deleteSelected()
      window.AppUndoHelpers?.refreshUI? app

    window.AppFieldsHelpers.bindFormulaFilter app

    window.AppUndoHelpers?.refreshUI? app

    app.el.renameSpaceBtn().addEventListener 'click', ->
      if app._currentSpace
        newName = await tdbPrompt app._t('ui.prompts.renameSpace'), app._currentSpace.name
        return unless newName?.trim() and newName.trim() != app._currentSpace.name
        Spaces.update(app._currentSpace.id, newName.trim())
          .then (updated) ->
            app._currentSpace.name = updated.name
            app.el.dataTitle().textContent = updated.name
            li = app.el.spaceList().querySelector("li[data-id='#{updated.id}']")
            li.textContent = updated.name if li
          .catch (err) -> tdbAlert app._err(err), 'error'
      else
        # Handle Data View config
        # We find currently active data view in sidebar
        activeLi = app.el.dataViewList().querySelector('li.active')
        if activeLi
          viewId = activeLi.dataset.id
          view = (app._allDataViews or []).find (v) -> v.id == viewId
          app._openDataViewConfigModal view if view

    app.el.deleteSpaceBtn().addEventListener 'click', ->
      if app._currentSpace
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
            window.AppUndoHelpers?.refreshUI? app
          .catch (err) -> tdbAlert app._err(err), 'error'
      else
        # Handle Data View deletion
        activeLi = app.el.dataViewList().querySelector('li.active')
        if activeLi
          viewId = activeLi.dataset.id
          view = (app._allDataViews or []).find (v) -> v.id == viewId
          return unless view
          return unless await tdbConfirm "Supprimer la vue '#{view.name}' ?"
          DataViews.delete(viewId)
            .then ->
              app.el.dataToolbar().classList.add 'hidden'
              app.el.welcome().classList.remove 'hidden'
              app._loadAll()
            .catch (err) -> tdbAlert app._err(err), 'error'


    window.AppUndoHelpers?.refreshUI? app
  loadDataViews: (app) ->
    DataViews.list()
      .then (views) ->
        app._allDataViews = views
        app.renderDataViewList views
      .catch (err) -> tdbAlert app._err(err), 'error'

  renderDataViewList: (app, views) ->
    ul = app.el.dataViewList()
    ul.innerHTML = ''
    sorted = [views...].sort (a, b) ->
      a.name.toLowerCase().localeCompare b.name.toLowerCase()

    for view in sorted
      li = document.createElement 'li'
      li.textContent = view.name
      li.dataset.id  = view.id
      do (view) ->
        li.addEventListener 'click', -> app.selectDataView view
      ul.appendChild li

  selectDataView: (app, view) ->
    history.replaceState null, '', "#view/#{view.id}"
    # Deactivate other sections
    for li in app.el.pageList().querySelectorAll 'li'
      li.classList.remove 'active'
    for li in app.el.spaceList().querySelectorAll 'li'
      li.classList.remove 'active'
    for li in app.el.dataViewList().querySelectorAll 'li'
      li.classList.toggle 'active', li.dataset.id == view.id

    app._currentSpace = null
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

    # Toolbar visibility for Data Views
    app.el.fieldsBtn().classList.add 'hidden'
    app.el.deleteRowsBtn().classList.add 'hidden'
    app.el.undoBtn().classList.add 'hidden'
    app.el.redoBtn().classList.add 'hidden'
    app.el.formulaFilterInput().classList.add 'hidden'
    app.el.renameSpaceBtn().title = "Configurer la vue"
    app.el.deleteSpaceBtn().title = "Supprimer la vue"

    app.el.dataTitle().textContent = view.name
    app._mountDataViewFromView view

  mountDataViewFromView: (app, view) ->
    app._activeDataView?.unmount?()
    container = app.el.gridContainer()
    
    # We need to build fake fields from the execution result or config
    # For now, we'll execute a dry run or use the config to get columns
    DataViews.execute(view.id, 1, 0)
      .then (data) =>
        return unless data.length > 0
        keys = Object.keys(data[0]).filter (k) -> k != 'id'
        cols = keys.map (k) -> { name: k, fieldType: 'String' } # fallback to String
        
        # Fake space object for DataView class
        fakeSpace = {
          id: "view_#{view.id}"
          name: view.name
          fields: cols
          isView: true
          viewId: view.id
        }
        
        app._activeDataView = new DataView container, fakeSpace, null, [], 
          readOnly: true
        app._activeDataView.mount()
      .catch (err) -> tdbAlert app._err(err), 'error'
