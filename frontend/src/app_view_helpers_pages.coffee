# app_view_helpers_pages.coffee — page list helpers extracted from app_view_helpers.coffee
Object.assign window.AppViewHelpers,
  loadPages: (app) ->
    GQL.query(app._listCustomViewsQuery)
      .then (data) -> app.renderPageList data.customViews
      .catch (err) -> tdbAlert app._err(err), 'error'

  renderPageList: (app, views) ->
    ul = app.el.pageList()
    ul.innerHTML = ''

    tree = { items: [], folders: {} }
    for cv in (views or [])
      parts = cv.name.split '/'
      curr = tree
      for dictName in parts[0 ... -1]
        curr.folders[dictName] ?= { items: [], folders: {} }
        curr = curr.folders[dictName]
      curr.items.push { cv: cv, shortName: parts[parts.length - 1] }

    renderTree = (node, containerEl, pathStr = "") ->
      folderNames = Object.keys(node.folders).sort (a, b) -> a.toLowerCase().localeCompare b.toLowerCase()
      for fName in folderNames
        fNode = node.folders[fName]
        fullPath = if pathStr then "#{pathStr}/#{fName}" else fName

        folderLi = document.createElement 'li'
        folderLi.className = 'folder-item'

        header = document.createElement 'div'
        header.className = 'folder-header'
        icon = document.createElement 'span'
        icon.className = 'folder-toggle-icon'
        icon.textContent = '▾'
        header.appendChild icon
        header.appendChild document.createTextNode(" #{fName}")
        folderLi.appendChild header

        subUl = document.createElement 'ul'
        subUl.className = 'folder-children'
        folderLi.appendChild subUl

        lsKey = "tdb_folder_page_#{fullPath}"
        if localStorage.getItem(lsKey) == 'true'
          folderLi.classList.add 'collapsed'

        header.addEventListener 'click', (e) ->
          e.stopPropagation()
          isCollapsed = folderLi.classList.toggle 'collapsed'
          localStorage.setItem lsKey, if isCollapsed then 'true' else 'false'

        renderTree fNode, subUl, fullPath
        containerEl.appendChild folderLi

      sortedItems = node.items.sort (a, b) -> a.shortName.toLowerCase().localeCompare b.shortName.toLowerCase()
      for item in sortedItems
        li = document.createElement 'li'
        li.className = 'leaf-item'
        li.dataset.id  = item.cv.id
        li.title = item.cv.name

        spanName = document.createElement 'span'
        spanName.className = 'leaf-item-name'
        spanName.textContent = item.shortName
        li.appendChild spanName

        btnGroup = document.createElement 'span'
        btnGroup.className = 'leaf-item-actions'

        btnExport = document.createElement 'button'
        btnExport.className = 'toolbar-btn toolbar-btn--icon page-action-btn'
        btnExport.title = 'Exporter le layout'
        btnExport.textContent = '↓'
        btnExport.addEventListener 'click', (e) ->
          e.stopPropagation()
          GQL.query('query ExportLayout($pageId: ID!) { exportLayout(pageId: $pageId) }', { pageId: item.cv.id })
            .then (data) ->
              blob = new Blob([data.exportLayout], { type: 'text/yaml' })
              url = URL.createObjectURL(blob)
              a = document.createElement('a')
              a.href = url
              a.download = "#{item.cv.name.replace(/[^a-z0-9]/gi, '_')}.yaml"
              a.click()
              URL.revokeObjectURL(url)
            .catch (err) -> tdbAlert app._err(err), 'error'
        btnGroup.appendChild btnExport

        btnImport = document.createElement 'button'
        btnImport.className = 'toolbar-btn toolbar-btn--icon page-action-btn'
        btnImport.title = 'Importer un layout'
        btnImport.textContent = '↑'
        inputFile = null
        btnImport.addEventListener 'click', (e) ->
          e.stopPropagation()
          inputFile = document.createElement 'input'
          inputFile.type = 'file'
          inputFile.accept = '.yaml,.yml'
          inputFile.onchange = (evt) ->
            file = evt.target.files[0]
            return unless file
            reader = new FileReader()
            reader.onload = (e) ->
              yaml = e.target.result
              GQL.mutate('mutation ImportLayout($pageId: ID!, $yaml: String!) { importLayout(pageId: $pageId, yaml: $yaml) { id name yaml } }', { pageId: item.cv.id, yaml })
                .then ->
                  app.loadPages()
                .catch (err) -> tdbAlert app._err(err), 'error'
            reader.readAsText(file)
          inputFile.click()
        btnGroup.appendChild btnImport

        li.appendChild btnGroup

        do (cv = item.cv) ->
          li.addEventListener 'click', (e) ->
            e.stopPropagation()
            app.selectPage cv
        containerEl.appendChild li

    renderTree tree, ul

  selectPage: (app, cv) ->
    history.replaceState null, '', "#page/#{cv.id}"
    app._currentCustomView = cv

    for li in app.el.spaceList().querySelectorAll 'li'
      li.classList.remove 'active'
    for li in app.el.pageList().querySelectorAll '.leaf-item'
      li.classList.toggle 'active', li.dataset.id == cv.id
      if li.dataset.id == cv.id
        parent = li.parentElement
        while parent and parent.id != 'page-list'
          if parent.tagName == 'LI' and parent.classList.contains('folder-item')
            parent.classList.remove 'collapsed'
          parent = parent.parentElement

    app._currentSpace = null
    app._activeDataView?.unmount?()
    app._activeDataView = null

    app.el.dataToolbar().classList.add 'hidden'
    app.el.fieldsPanel().classList.add 'hidden'
    app.el.gridContainer().classList.add 'hidden'
    app.el.welcome().classList.add 'hidden'
    app.el.adminPanel().classList.add 'hidden'
    app.el.contentRow().classList.remove 'hidden'

    panel = app.el.yamlEditorPanel()
    panel.classList.remove 'hidden'
    app.el.yamlPageName().textContent = cv.name

    if cv.yaml?.trim()
      app._renderCustomViewPreview cv.yaml
    else
      app._openYamlModal()
    window.AppUndoHelpers?.refreshUI? app

