# app_view_helpers.coffee — custom views and YAML editor helpers extracted from app.coffee

window.AppViewHelpers =
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

  renderCustomViewPreview: (app, yamlText) ->
    container = app.el.customViewContainer()
    container.classList.remove 'hidden'   # le conteneur d'aperçu est masqué par défaut
    app._activeCustomView?.unmount?()
    container.innerHTML = ''

    # Créer un conteneur pour les widgets draggables
    widgetsContainer = document.createElement 'div'
    widgetsContainer.className = 'widgets-container'
    widgetsContainer.setAttribute 'data-page-id', app._currentCustomView?.id
    container.appendChild widgetsContainer

    # Ajouter les boutons de gestion des zones (Phase 3)
    zoneToolbar = document.createElement 'div'
    zoneToolbar.className = 'zone-toolbar'
    zoneToolbar.innerHTML = """
      <button id="create-zone-btn" class="toolbar-btn" title="Créer une nouvelle zone">
        ＋ Zone
      </button>
      <button id="zone-manage-btn" class="toolbar-btn" title="Gérer les zones">
        ⚙ Zones
      </button>
      <button id="grid-toggle-btn" class="toolbar-btn" title="Afficher/Masquer la grille">
        ▦ Grille
      </button>
    """
    container.insertBefore zoneToolbar, widgetsContainer

    # Bind grid toggle button
    zoneToolbar.querySelector('#grid-toggle-btn').addEventListener 'click', ->
      if app._activeCustomView
        app._activeCustomView.toggleGrid()

    try
      cv = new CustomView widgetsContainer, yamlText, app._allSpaces, app._allDataViews
      app._activeCustomView = cv
      cv.mount()

      # Initialiser le DragDropManager avec support des zones (Phase 3)
      if app._currentCustomView?.id
        app._dragDropManager?.destroy?()

        # Vérifier si DragDropManager est disponible
        if typeof DragDropManager != 'undefined'
          app._dragDropManager = new DragDropManager widgetsContainer,
            pageId: app._currentCustomView.id
            handle: '.widget-header'
            filter: '.no-drag'
            onCreateZone: (zoneData) =>
              window.AppViewHelpers._createZone app, zoneData
            onResizeZone: (zoneId, factor) =>
              window.AppViewHelpers._resizeZone app, zoneId, factor
            onReorder: (positions) =>
              window.AppViewHelpers.handleWidgetReorder app, positions
        else
          console.warn "DragDropManager not available, zone features disabled"

      # Lier les événements des zones (Phase 3)
      window.AppViewHelpers._bindZoneEvents app

    catch e
      console.error 'CustomView error:', e
      container.innerHTML = "<div class='error-message'>Erreur YAML : #{e.message}</div>"

  handleWidgetReorder: (app, positions) ->
    return unless app._currentCustomView?.id

    # Envoyer la mutation GraphQL pour réordonner les widgets
    mutation = """
      mutation ReorderWidgets($pageId: ID!, $widgetPositions: [WidgetPosition!]!) {
        reorderWidgets(pageId: $pageId, widgetPositions: $widgetPositions) {
          id
          yaml
        }
      }
    """

    GQL.mutate mutation, { pageId: app._currentCustomView.id, widgetPositions: positions }
      .then (result) ->
        if result.errors
          console.error 'GraphQL errors:', result.errors
          tdbAlert 'Erreur lors du réordonnancement: ' + result.errors[0].message, 'error'
        else
          # Mettre à jour le YAML et rafraîchir la vue
          updatedYaml = result.reorderWidgets.yaml
          app._currentCustomView.yaml = updatedYaml
          @renderCustomViewPreview app, updatedYaml
      .catch (error) ->
        console.error 'Network error:', error
        tdbAlert 'Erreur réseau lors du réordonnancement: ' + error.message, 'error'

  onDragStart: (app, evt) ->
    # Désactiver temporairement d'autres interactions
    document.body.classList.add 'dragging-active'

  onDragEnd: (app, evt) ->
    # Réactiver les interactions
    document.body.classList.remove 'dragging-active'

  bindYamlEditor: (app) ->
    app.el.yamlEditBtn().addEventListener 'click', ->
      app._openYamlModal()

    app.el.yamlAddWidgetBtn().addEventListener 'click', ->
      window.AppViewHelpers._openAddWidgetModal app

    app.el.yamlDeleteBtn().addEventListener 'click', ->
      cv = app._currentCustomView
      return unless cv
      return unless await tdbConfirm app._t('ui.confirms.deletePage', { name: cv.name })
      GQL.mutate(app._deleteCustomViewMutation, { id: cv.id })
        .then ->
          app._currentCustomView = null
          app._activeCustomView?.unmount?()
          app._activeCustomView = null
          app.el.yamlEditorPanel().classList.add 'hidden'
          app.el.customViewContainer().classList.add 'hidden'
          app.el.welcome().classList.remove 'hidden'
          app.loadPages()
        .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.yamlModalSaveBtn().addEventListener 'click', ->
      cv = app._currentCustomView
      return unless cv
      yaml = app._cmYaml.getValue()
      GQL.mutate(app._updateCustomViewMutation, { id: cv.id, input: { yaml } })
        .then (data) ->
          app._currentCustomView = data.updateCustomView
          app.el.yamlModal().classList.add 'hidden'
          app._renderCustomViewPreview yaml
          app.loadPages()
        .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.yamlModalCloseBtn().addEventListener 'click', ->
      app.el.yamlModal().classList.add 'hidden'

    app.el.yamlModalPreviewBtn().addEventListener 'click', ->
      return unless app._cmYaml
      app._renderCustomViewPreview app._cmYaml.getValue()

  openYamlModal: (app) ->
    cv = app._currentCustomView
    return unless cv

    # Recharger la vue depuis la base pour avoir le YAML à jour
    query = """
      query GetView($viewId: ID!) {
        customView(id: $viewId) {
          id
          name
          yaml
        }
      }
    """

    window.GQL.query(query, {viewId: cv.id}).then (data) ->
      if data.customView
        # Mettre à jour la vue courante avec les données fraîches
        app._currentCustomView = data.customView
        cv = data.customView

        app.el.yamlModalTitle().textContent = cv.name
        app.el.yamlModal().classList.remove 'hidden'

        # Ajouter la palette d'insertion de layouts dans le header de la modale YAML
        window.AppViewHelpers.setupLayoutPalette app

        # Configurer le listener global d'insertion de layouts
        window.CustomView?.setupLayoutInsertion?()

        yamlPane = document.querySelector '.yaml-editor-pane'
        applyValidationLayout = ->
          return unless yamlPane and app._yamlValidMsg
          hasError = !app._yamlValidMsg.classList.contains 'hidden'
          yamlPane.classList.toggle 'has-validation-error', hasError
        unless app._cmYaml
          app._cmYaml = CodeMirror document.getElementById('yaml-cm-editor'),
            mode: 'yaml'
            theme: 'monokai'
            lineNumbers: true
            lineWrapping: true
            tabSize: 2
            indentWithTabs: false
          app._cmYaml.on 'change', (cm, change) ->
            unless app._yamlValidMsg
              app._yamlValidMsg = document.getElementById 'yaml-validation-msg'
            if change.origin == 'setValue'
              app._yamlValidMsg?.classList.add 'hidden'
              applyValidationLayout()
              return
            app._yamlBuilder?.reloadFromYaml cm.getValue()
            try
              jsyaml.load cm.getValue()
              app._yamlValidMsg?.classList.add 'hidden'
              applyValidationLayout()
            catch e
              if app._yamlValidMsg
                app._yamlValidMsg.textContent = "YAML invalide : #{e.message}"
                app._yamlValidMsg.classList.remove 'hidden'
                applyValidationLayout()
        else
          app._yamlValidMsg ?= document.getElementById 'yaml-validation-msg'
          applyValidationLayout()

        # Recharger le YAML depuis la base pour avoir la version à jour
        window.GQL.query("""
          query GetView($viewId: ID!) {
            customView(id: $viewId) {
              id
              name
              yaml
            }
          }
        """, {viewId: cv.id}).then (data) ->
          if data.customView
            freshYaml = data.customView.yaml
            app._currentCustomView.yaml = freshYaml
            app._cmYaml.setValue freshYaml or ''
            setTimeout (-> app._cmYaml.refresh()), 10
        .catch (error) ->
          console.error 'Erreur lors du rechargement du YAML:', error
          # Utiliser le YAML existant en cas d'erreur
          app._cmYaml.setValue cv.yaml or ''
          setTimeout (-> app._cmYaml.refresh()), 10
        app._loadAllRelations().then (relations) ->
          app._yamlBuilder = new YamlBuilder
            container:    document.getElementById 'schema-browser'
            allSpaces:    app._allSpaces
            allRelations: relations
            initialYaml:  cv.yaml or ''
            onChange:     (yaml) -> app._cmYaml?.setValue yaml
          app._yamlBuilder.mount()
    .catch (error) ->
      console.error 'Erreur lors du chargement de la vue:', error

  loadAllRelations: (app) ->
    return Promise.resolve app._allRelations if app._allRelations
    Promise.all(app._allSpaces.map (sp) -> Spaces.listRelations sp.id)
      .then (results) ->
        app._allRelations = results.reduce ((a, b) -> a.concat b), []
        app._allRelations

  _pulseModalButton: (btn) ->
    return unless btn
    btn.classList.remove 'is-pressed'
    btn.classList.add 'is-pressed'
    setTimeout (-> btn.classList.remove 'is-pressed'), 120

  _markWidgetPluginDirty: (app, pluginName) ->
    return unless pluginName
    app._widgetPluginDirty = true
    app._widgetPluginDirtyNames ?= {}
    app._widgetPluginDirtyNames[pluginName] = true

  _collectWidgetTypesFromYaml: (yamlText) ->
    types = {}
    walk = (node) ->
      return unless node?
      if Array.isArray node
        walk child for child in node
        return
      if typeof node == 'object'
        nodeType = node.type
        if typeof nodeType == 'string' and nodeType and nodeType != 'aggregate'
          types[nodeType] = true
        walk val for own _, val of node
    try
      parsed = jsyaml.load yamlText or ''
      walk parsed
    catch e
      console.warn 'collect plugin dependencies from yaml failed', e
    types

  _refreshViewsDependingOnDirtyPlugins: (app) ->
    return unless app._widgetPluginDirty
    return unless app._activeCustomView and app._currentCustomView?.yaml
    dirtyNames = Object.keys app._widgetPluginDirtyNames or {}
    return unless dirtyNames.length > 0
    usedTypes = window.AppViewHelpers._collectWidgetTypesFromYaml app._currentCustomView.yaml
    needsRefresh = false
    for name in dirtyNames when usedTypes[name]
      needsRefresh = true
      break
    app._renderCustomViewPreview app._currentCustomView.yaml if needsRefresh

  _closeWidgetPluginModal: (app) ->
    app.el.widgetPluginModal()?.classList.add 'hidden'
    window.AppViewHelpers._refreshViewsDependingOnDirtyPlugins app
    app._widgetPluginDirty = false
    app._widgetPluginDirtyNames = {}

  bindWidgetPlugins: (app) ->
    app.el.widgetPluginModalCloseBtn()?.addEventListener 'click', (ev) ->
      window.AppViewHelpers._pulseModalButton ev.currentTarget
      window.AppViewHelpers._closeWidgetPluginModal app

    app.el.widgetPluginNewBtn()?.addEventListener 'click', (ev) ->
      window.AppViewHelpers._pulseModalButton ev.currentTarget
      defaults = window.AppViewHelpers._defaultWidgetPlugin()
      app._selectedWidgetPlugin = null
      app.el.widgetPluginSelect()?.value = ''
      app.el.widgetPluginName().value = defaults.name
      app.el.widgetPluginDescription().value = defaults.description
      app.el.widgetPluginScriptLanguage().value = defaults.scriptLanguage
      app.el.widgetPluginTemplateLanguage().value = defaults.templateLanguage
      app._cmWidgetPluginScript?.setOption 'mode', defaults.scriptLanguage
      app._cmWidgetPluginTemplate?.setOption 'mode', defaults.templateLanguage
      app._cmWidgetPluginScript?.setValue defaults.scriptCode
      app._cmWidgetPluginTemplate?.setValue defaults.templateCode

    app.el.widgetPluginSaveBtn()?.addEventListener 'click', (ev) ->
      window.AppViewHelpers._pulseModalButton ev.currentTarget
      name = app.el.widgetPluginName().value.trim()
      return tdbAlert('Nom du plugin requis', 'error') unless name
      previousName = app._selectedWidgetPlugin?.name
      input =
        name: name
        description: app.el.widgetPluginDescription().value.trim()
        scriptLanguage: app.el.widgetPluginScriptLanguage().value or 'coffeescript'
        templateLanguage: app.el.widgetPluginTemplateLanguage().value or 'pug'
        scriptCode: if app._cmWidgetPluginScript then app._cmWidgetPluginScript.getValue() else ''
        templateCode: if app._cmWidgetPluginTemplate then app._cmWidgetPluginTemplate.getValue() else ''
      mutation = if app._selectedWidgetPlugin then app._updateWidgetPluginMutation else app._createWidgetPluginMutation
      vars = if app._selectedWidgetPlugin then { id: app._selectedWidgetPlugin.id, input } else { input }
      GQL.mutate(mutation, vars)
        .then (data) ->
          saved = data.updateWidgetPlugin or data.createWidgetPlugin or null
          window.AppViewHelpers._markWidgetPluginDirty app, previousName
          window.AppViewHelpers._markWidgetPluginDirty app, saved?.name
          app._selectedWidgetPlugin = saved if saved
          window.AppViewHelpers._loadWidgetPlugins app, saved?.id
        .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.widgetPluginDeleteBtn()?.addEventListener 'click', (ev) ->
      window.AppViewHelpers._pulseModalButton ev.currentTarget
      plugin = app._selectedWidgetPlugin
      return tdbAlert('Sélectionnez un plugin à supprimer', 'error') unless plugin
      return unless await tdbConfirm "Supprimer le plugin « #{plugin.name} » ?"
      GQL.mutate(app._deleteWidgetPluginMutation, { id: plugin.id })
        .then ->
          window.AppViewHelpers._markWidgetPluginDirty app, plugin.name
          app._selectedWidgetPlugin = null
          window.AppViewHelpers._loadWidgetPlugins app
        .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.widgetPluginScriptLanguage()?.addEventListener 'change', ->
      mode = app.el.widgetPluginScriptLanguage().value or 'coffeescript'
      app._cmWidgetPluginScript?.setOption 'mode', mode

    app.el.widgetPluginTemplateLanguage()?.addEventListener 'change', ->
      mode = app.el.widgetPluginTemplateLanguage().value or 'pug'
      app._cmWidgetPluginTemplate?.setOption 'mode', mode

    app.el.widgetPluginSelect()?.addEventListener 'change', ->
      id = app.el.widgetPluginSelect().value
      return unless id
      plugin = (app._widgetPluginCache or []).find (p) -> p.id == id
      return unless plugin
      app._selectedWidgetPlugin = plugin
      app.el.widgetPluginName().value = plugin.name or ''
      app.el.widgetPluginDescription().value = plugin.description or ''
      app.el.widgetPluginScriptLanguage().value = plugin.scriptLanguage or 'coffeescript'
      app.el.widgetPluginTemplateLanguage().value = plugin.templateLanguage or 'pug'
      app._cmWidgetPluginScript?.setOption 'mode', app.el.widgetPluginScriptLanguage().value
      app._cmWidgetPluginTemplate?.setOption 'mode', app.el.widgetPluginTemplateLanguage().value
      app._cmWidgetPluginScript?.setValue plugin.scriptCode or ''
      app._cmWidgetPluginTemplate?.setValue plugin.templateCode or ''

  _defaultWidgetPlugin: ->
    name: ''
    description: ''
    scriptLanguage: 'coffeescript'
    templateLanguage: 'pug'
    templateCode: """
div.plugin-root
  h3= params.title || 'Widget'
  .content Chargement…
"""
    scriptCode: """
module.exports = ({ gql, emitSelection, onInputSelection, render, params }) ->
  rows = []
  onInputSelection (selection) ->
    rows = selection?.rows or []
    emitSelection { rows }
  title = if params?.title then params.title else 'sans titre'
  render \"<div class='plugin-info'>Plugin prêt : \#{title}</div>\"
"""

  _loadWidgetPlugins: (app, preferredId = null) ->
    GQL.query(app._listWidgetPluginsQuery)
      .then (data) ->
        plugins = data.widgetPlugins or []
        app._widgetPluginCache = plugins
        sel = app.el.widgetPluginSelect()
        unless sel
          tdbAlert 'UI plugins indisponible dans cette page. Rechargez la page (Ctrl+F5).', 'error'
          return
        sel.innerHTML = ''
        selectPlugin = (p) ->
          app._selectedWidgetPlugin = p
          sel.value = p.id if p?.id
          app.el.widgetPluginName().value = p.name or ''
          app.el.widgetPluginDescription().value = p.description or ''
          app.el.widgetPluginScriptLanguage().value = p.scriptLanguage or 'coffeescript'
          app.el.widgetPluginTemplateLanguage().value = p.templateLanguage or 'pug'
          app._cmWidgetPluginScript?.setOption 'mode', app.el.widgetPluginScriptLanguage().value
          app._cmWidgetPluginTemplate?.setOption 'mode', app.el.widgetPluginTemplateLanguage().value
          app._cmWidgetPluginScript?.setValue p.scriptCode or ''
          app._cmWidgetPluginTemplate?.setValue p.templateCode or ''

        wantedId = preferredId or app._selectedWidgetPlugin?.id
        firstPlugin = null
        for p in plugins
          firstPlugin ?= p
          opt = document.createElement 'option'
          opt.value = p.id
          opt.textContent = p.name
          opt.title = p.description or p.name
          sel.appendChild opt

        if plugins.length > 0
          selected = plugins.find((p) -> p.id == wantedId) or firstPlugin
          selectPlugin selected if selected
        else
          app._selectedWidgetPlugin = null
          emptyOpt = document.createElement 'option'
          emptyOpt.value = ''
          emptyOpt.textContent = '— Aucun plugin —'
          sel.appendChild emptyOpt
          sel.value = ''
          defaults = window.AppViewHelpers._defaultWidgetPlugin()
          app.el.widgetPluginName().value = defaults.name
          app.el.widgetPluginDescription().value = defaults.description
          app.el.widgetPluginScriptLanguage().value = defaults.scriptLanguage
          app.el.widgetPluginTemplateLanguage().value = defaults.templateLanguage
          app._cmWidgetPluginScript?.setOption 'mode', defaults.scriptLanguage
          app._cmWidgetPluginTemplate?.setOption 'mode', defaults.templateLanguage
          app._cmWidgetPluginScript?.setValue defaults.scriptCode
          app._cmWidgetPluginTemplate?.setValue defaults.templateCode
      .catch (err) -> tdbAlert app._err(err), 'error'

  _ensureWidgetPluginEditorsSplit: (app) ->
    root = app.el.widgetPluginModal?()
    return unless root
    tplEl = app.el.widgetPluginTemplateEditor?()
    scriptEl = app.el.widgetPluginScriptEditor?()
    return unless tplEl and scriptEl
    tplLangSel = app.el.widgetPluginTemplateLanguage?()
    scriptLangSel = app.el.widgetPluginScriptLanguage?()

    row = root.querySelector '.widget-plugin-editors-row'
    tplColCurrent = tplEl.closest '.widget-plugin-editor-col'
    scriptColCurrent = scriptEl.closest '.widget-plugin-editor-col'
    if row and row.contains(tplEl) and row.contains(scriptEl) and tplColCurrent and scriptColCurrent and tplColCurrent != scriptColCurrent and tplColCurrent.parentElement == row and scriptColCurrent.parentElement == row
      return

    pane = tplEl.closest('.yaml-editor-pane') or scriptEl.closest('.yaml-editor-pane')
    return unless pane
    for oldRow in pane.querySelectorAll '.widget-plugin-editors-row'
      oldRow.remove()

    tplLabel = tplEl.previousElementSibling
    scriptLabel = scriptEl.previousElementSibling
    tplLangLabel = root.querySelector("label[for='widget-plugin-template-language']")
    scriptLangLabel = root.querySelector("label[for='widget-plugin-script-language']")
    ensureLabel = (lbl, txt, forId) ->
      return lbl if lbl
      n = document.createElement 'label'
      n.className = 'formula-hint'
      n.htmlFor = forId
      n.textContent = txt
      n
    tplLangLabel = ensureLabel tplLangLabel, 'Template language', 'widget-plugin-template-language'
    scriptLangLabel = ensureLabel scriptLangLabel, 'Script language', 'widget-plugin-script-language'
    unless tplLabel
      tplLabel = document.createElement 'label'
      tplLabel.className = 'formula-hint'
      tplLabel.textContent = 'Template'
    unless scriptLabel
      scriptLabel = document.createElement 'label'
      scriptLabel.className = 'formula-hint'
      scriptLabel.textContent = 'Script'
    tplEl.style.height = ''
    scriptEl.style.height = ''
    tplEl.style.flex = '1'
    scriptEl.style.flex = '1'

    row = document.createElement 'div'
    row.className = 'widget-plugin-editors-row'

    tplCol = document.createElement 'div'
    tplCol.className = 'widget-plugin-editor-col'
    tplCol.appendChild tplLangLabel if tplLangSel and tplLangLabel
    tplCol.appendChild tplLangSel if tplLangSel
    tplCol.appendChild tplLabel if tplLabel
    tplCol.appendChild tplEl

    scriptCol = document.createElement 'div'
    scriptCol.className = 'widget-plugin-editor-col'
    scriptCol.appendChild scriptLangLabel if scriptLangSel and scriptLangLabel
    scriptCol.appendChild scriptLangSel if scriptLangSel
    scriptCol.appendChild scriptLabel if scriptLabel
    scriptCol.appendChild scriptEl

    row.appendChild tplCol
    row.appendChild scriptCol
    pane.appendChild row
    for langRow in pane.querySelectorAll '.formula-lang-row'
      langRow.remove()

  _ensureWidgetPluginMetaRow: (app) ->
    root = app.el.widgetPluginModal?()
    return unless root
    selEl = app.el.widgetPluginSelect?()
    nameEl = app.el.widgetPluginName?()
    descEl = app.el.widgetPluginDescription?()
    return unless selEl and nameEl and descEl

    pane = selEl.closest('.yaml-editor-pane') or nameEl.closest('.yaml-editor-pane') or descEl.closest('.yaml-editor-pane')
    return unless pane
    row = pane.querySelector '.widget-plugin-meta-row'
    selCol = selEl.closest '.widget-plugin-meta-col'
    nameCol = nameEl.closest '.widget-plugin-meta-col'
    descCol = descEl.closest '.widget-plugin-meta-col'
    if row and selCol and nameCol and descCol and selCol != nameCol and nameCol != descCol and selCol.parentElement == row and nameCol.parentElement == row and descCol.parentElement == row
      return

    for oldRow in pane.querySelectorAll '.widget-plugin-meta-row'
      oldRow.remove()

    selLabel = root.querySelector("label[for='widget-plugin-select']") or selEl.previousElementSibling
    nameLabel = root.querySelector("label[for='widget-plugin-name']") or nameEl.previousElementSibling
    descLabel = root.querySelector("label[for='widget-plugin-description']") or descEl.previousElementSibling

    ensureLabel = (lbl, txt, forId) ->
      return lbl if lbl
      n = document.createElement 'label'
      n.className = 'formula-hint'
      n.htmlFor = forId
      n.textContent = txt
      n

    selLabel = ensureLabel selLabel, 'Plugins existants', 'widget-plugin-select'
    nameLabel = ensureLabel nameLabel, 'Nom', 'widget-plugin-name'
    descLabel = ensureLabel descLabel, 'Description', 'widget-plugin-description'

    row = document.createElement 'div'
    row.className = 'widget-plugin-meta-row'

    makeCol = (lbl, inputEl) ->
      col = document.createElement 'div'
      col.className = 'widget-plugin-meta-col'
      col.appendChild lbl if lbl
      col.appendChild inputEl if inputEl
      col

    row.appendChild makeCol selLabel, selEl
    row.appendChild makeCol nameLabel, nameEl
    row.appendChild makeCol descLabel, descEl

    anchor = pane.querySelector('.widget-plugin-editors-row') or pane.querySelector('.formula-lang-row')
    if anchor
      pane.insertBefore row, anchor
    else
      pane.appendChild row

  openWidgetPluginModal: (app) ->
    app.el.widgetPluginModal()?.classList.remove 'hidden'
    app._widgetPluginDirty = false
    app._widgetPluginDirtyNames = {}
    window.AppViewHelpers._ensureWidgetPluginMetaRow app
    window.AppViewHelpers._ensureWidgetPluginEditorsSplit app

    unless app._cmWidgetPluginScript
      app._cmWidgetPluginScript = CodeMirror app.el.widgetPluginScriptEditor(),
        mode: (app.el.widgetPluginScriptLanguage().value or 'coffeescript')
        theme: 'monokai'
        lineNumbers: true
        lineWrapping: true
        tabSize: 2
        indentWithTabs: false
    unless app._cmWidgetPluginTemplate
      app._cmWidgetPluginTemplate = CodeMirror app.el.widgetPluginTemplateEditor(),
        mode: (app.el.widgetPluginTemplateLanguage().value or 'pug')
        theme: 'monokai'
        lineNumbers: true
        lineWrapping: true
        tabSize: 2
        indentWithTabs: false

    setTimeout (-> app._cmWidgetPluginScript?.refresh()), 10
    setTimeout (-> app._cmWidgetPluginTemplate?.refresh()), 10
    window.AppViewHelpers._loadWidgetPlugins app

  setupLayoutPalette: (app) ->
    # Vérifier si la palette existe déjà pour éviter les doublons
    existingPalette = document.querySelector '.cv-layout-palette'
    return if existingPalette

    # Créer la palette d'insertion de layouts
    palette = document.createElement 'div'
    palette.className = 'cv-layout-palette'

    btnVert = document.createElement 'button'
    btnVert.textContent = 'Ajouter layout vertical'
    btnVert.className = 'cv-layout-btn'
    btnVert.title = 'Insérer un layout vertical'

    btnHoriz = document.createElement 'button'
    btnHoriz.textContent = 'Ajouter layout horizontal'
    btnHoriz.className = 'cv-layout-btn'
    btnHoriz.title = 'Insérer un layout horizontal'

    palette.appendChild btnVert
    palette.appendChild btnHoriz

    # Insérer la palette dans le header de la modale YAML
    actionsContainer = document.querySelector '.modal-editor-actions'
    if actionsContainer
      actionsContainer.insertBefore palette, actionsContainer.firstChild

      # Gestion des clics sur la palette
      btnVert.addEventListener 'click', ->
        window.dispatchEvent new CustomEvent('cv-insert-layout', { detail: { direction: 'vertical' } })

      btnHoriz.addEventListener 'click', ->
        window.dispatchEvent new CustomEvent('cv-insert-layout', { detail: { direction: 'horizontal' } })

  _openAddWidgetModal: (app) ->
    cv = app._currentCustomView
    return unless cv

    # Afficher la modale
    app.el.addWidgetModal().classList.remove 'hidden'

    # Corriger le HTML manquant dynamiquement
    window.AppViewHelpers._fixModalHTML()

    # Initialiser la modale avec les fonctions de base
    window.AppViewHelpers._initializeWidgetModal app

  _fixModalHTML: ->
    # Ajouter les sections manquantes si elles n'existent pas
    dataSourceConfig = document.querySelector '.data-source-config'
    return unless dataSourceConfig

    # Vérifier si les sections manquent
    fieldsContainer = document.getElementById 'widget-fields-container'

    unless fieldsContainer
      # Créer la section des champs
      fieldsSection = document.createElement 'div'
      fieldsSection.className = 'config-row'
      fieldsSection.innerHTML = '''
        <label>Colonnes à afficher:</label>
        <div id="widget-fields-container" class="fields-container">
          <div class="fields-header">
            <div class="field-group">Disponibles:</div>
            <div class="field-group">Sélectionnées:</div>
          </div>
          <div class="fields-lists">
            <div id="available-fields" class="fields-list"> </div>
            <div id="selected-fields" class="fields-list selected"> </div>
          </div>
        </div>
      '''
      dataSourceConfig.appendChild fieldsSection

  _populateSpaceSelect: (select, spaces, dataViews) ->
    console.log 'Populating space select with:', { spaces: spaces?.length, dataViews: dataViews?.length }

    # Vider le select
    select.innerHTML = '<option value="">Sélectionner une source...</option>'

    # Ajouter les espaces
    if spaces and Array.isArray(spaces) and spaces.length > 0
      spacesGroup = document.createElement 'optgroup'
      spacesGroup.label = 'Espaces (Tables)'
      for space in spaces
        option = document.createElement 'option'
        option.value = space.id
        option.textContent = space.name
        spacesGroup.appendChild option
      select.appendChild spacesGroup
      console.log "Added #{spaces.length} spaces"

    # Ajouter les vues
    if dataViews and Array.isArray(dataViews) and dataViews.length > 0
      viewsGroup = document.createElement 'optgroup'
      viewsGroup.label = 'Vues (Requêtes)'
      for view in dataViews
        option = document.createElement 'option'
        option.value = view.id
        option.dataset.isView = 'true'
        option.textContent = view.name
        viewsGroup.appendChild option
      select.appendChild viewsGroup
      console.log "Added #{dataViews.length} data views"

  _initializeWidgetModal: (app) ->
    console.log '_initializeWidgetModal called'

    # Forcer le token de test pour l'environnement de test
    unless window.GQL._token
      console.log 'Setting test token for widget modal...'
      window.GQL.setToken 'GRh5Nvb+qcRmGImY/yd/WhV+57IDoMBg/KSp+eQnK7I='

    # Charger les espaces disponibles
    window.AppViewHelpers._loadAvailableSources app

    # Lier les événements de base
    window.AppViewHelpers._bindBasicWidgetEvents app

    # Charger la liste des espaces et des Data Views
    Promise.all([window.Spaces.list(), window.DataViews.list()])
      .then ([spaces, dataViews]) ->
        console.log 'spaces and dataViews loaded:', spaces, dataViews
        console.log 'spaces type:', typeof spaces, 'dataViews type:', typeof dataViews
        console.log 'spaces length:', spaces?.length, 'dataViews length:', dataViews?.length

        select = document.getElementById 'widget-space-select'
        return unless select

        select.innerHTML = '<option value="">Sélectionner une source...</option>'

        # Si pas authentifié, utiliser le token de test
        unless window.GQL._token
          console.log 'No token found, setting test token...'
          window.GQL.setToken 'GRh5Nvb+qcRmGImY/yd/WhV+57IDoMBg/KSp+eQnK7I='

          # Re-tenter avec le token
          Promise.all([window.Spaces.list(), window.DataViews.list()])
            .then ([spacesRetry, dataViewsRetry]) ->
              console.log 'Retry - spaces and dataViews loaded:', spacesRetry, dataViewsRetry
              window.AppViewHelpers._populateSpaceSelect select, spacesRetry, dataViewsRetry
            .catch (err) ->
              console.error 'Retry failed:', err
              window.AppViewHelpers._populateSpaceSelect select, [], []
          return

        # Vérifier si spaces est un tableau valide
        if spaces and Array.isArray(spaces) and spaces.length > 0
          window.AppViewHelpers._populateSpaceSelect select, spaces, dataViews
        else
          console.warn 'No valid spaces array found:', spaces

        # Stocker les données pour utilisation ultérieure
        app._spacesData = spaces
        app._dataViewsData = dataViews
        window._currentSpacesData = spaces
        window._currentDataViewsData = dataViews

        # Écouter les changements pour charger les champs
        select.addEventListener 'change', ->
          spaceId = @value
          return unless spaceId

          # Trouver la source correspondante
          spacesData = window._currentSpacesData or []
          dataViewsData = window._currentDataViewsData or []
          selectedSource = spacesData.find((s) -> s.id == spaceId) or dataViewsData.find((v) -> v.id == spaceId)

          if selectedSource?.config? # C'est une Data View (elle a une config)
            selectedSource.isView = true
            # Simuler l'objet space pour peupler les champs
            selectedSource.fields = selectedSource.config.columns?.map (c) -> { name: c, fieldType: 'String' }
            window.AppViewHelpers._populateFieldsLists selectedSource
            window.AppViewHelpers._populateGroupByOptions selectedSource
          else if selectedSource
            window.AppViewHelpers._loadSpaceFields selectedSource, ->
              window.AppViewHelpers._populateFieldsLists selectedSource
              window.AppViewHelpers._populateGroupByOptions selectedSource

  _loadSpaceFields: (space, callback) ->
    # Charger les champs d'un espace spécifique
    query = """
      query GetSpaceFields($spaceId: ID!) {
        space(id: $spaceId) {
          id name
          fields {
            id name fieldType notNull position description formula triggerFields language reprFormula
          }
        }
      }
    """
    window.GQL.query(query, {spaceId: space.id}).then (result) ->
      if result.space and result.space.fields
        space.fields = result.space.fields
        console.log 'fields loaded for space:', space.name, space.fields
      callback()
    .catch (error) ->
      console.error 'Error loading fields:', error
      # En cas d'erreur, continuer sans champs
      callback()

  _loadAvailableSources: (app) ->
    # Cette fonction est un wrapper pour charger les sources
    # Le vrai chargement se fait dans _initializeWidgetModal
    console.log '_loadAvailableSources called (wrapper function)'

  _toggleFieldSelection: (fieldItem) ->
    isSelected = fieldItem.classList.contains 'selected'
    availableContainer = document.getElementById 'available-fields'
    selectedContainer = document.getElementById 'selected-fields'

    if isSelected
      # Retirer de la sélection
      fieldItem.classList.remove 'selected'
      availableContainer.appendChild fieldItem
    else
      # Ajouter à la sélection
      fieldItem.classList.add 'selected'
      selectedContainer.appendChild fieldItem

  _populateFieldsLists: (space) ->
    console.log 'populateFieldsLists called with space:', space
    availableContainer = document.getElementById 'available-fields'
    selectedContainer = document.getElementById 'selected-fields'

    return unless availableContainer and selectedContainer and space

    console.log 'space fields:', space.fields

    # Vider les conteneurs
    availableContainer.innerHTML = ''
    selectedContainer.innerHTML = ''

    # Si pas de champs, afficher un message
    unless space.fields
      availableContainer.innerHTML = '<div class="field-item">Cet espace n\'a pas de champs configurés</div>'
      return

    # Ajouter les champs disponibles
    for field in space.fields or []
      console.log 'creating field item for:', field
      fieldItem = document.createElement 'div'
      fieldItem.className = 'field-item'
      fieldItem.textContent = "#{field.name} (#{field.fieldType})"
      fieldItem.dataset.fieldName = field.name
      fieldItem.dataset.fieldType = field.fieldType

      fieldItem.addEventListener 'click', ->
        window.AppViewHelpers._toggleFieldSelection @

      availableContainer.appendChild fieldItem

  _bindBasicWidgetEvents: (app) ->
    # Gérer la sélection du type de widget
    typeOptions = document.querySelectorAll '.widget-type-option'

    for option in typeOptions
      option.addEventListener 'click', ->
        # Désélectionner les autres
        for opt in typeOptions
          opt.classList.remove 'selected'

        # Sélectionner celui-ci
        @classList.add 'selected'
        @querySelector('input[type="radio"]').checked = true

    # Gérer les boutons de la modale
    confirmBtn = document.getElementById 'add-widget-confirm-btn'
    cancelBtn = document.getElementById 'add-widget-cancel-btn'

    if confirmBtn
      confirmBtn.addEventListener 'click', ->
        window.AppViewHelpers._submitWidget app

    if cancelBtn
      cancelBtn.addEventListener 'click', ->
        window.AppViewHelpers._closeWidgetModal app

    # Gérer les paramètres
    window.AppViewHelpers._bindParamsManagement app

  _bindParamsManagement: (app) ->
    addBtn = document.getElementById 'add-param-btn'
    paramsList = document.getElementById 'widget-params-list'

    return unless addBtn and paramsList

    addBtn.addEventListener 'click', ->
      window.AppViewHelpers._addParamRow paramsList

    # Gérer les boutons de suppression existants
    window.AppViewHelpers._bindParamRemoval paramsList

  _addParamRow: (paramsList) ->
    paramRow = document.createElement 'div'
    paramRow.className = 'param-row'
    paramRow.innerHTML = '''
      <input type="text" placeholder="Clé" class="param-key">
      <input type="text" placeholder="Valeur" class="param-value">
      <button type="button" class="param-remove-btn">✕</button>
    '''

    paramsList.appendChild paramRow
    window.AppViewHelpers._bindParamRemoval paramsList

  _bindParamRemoval: (paramsList) ->
    removeBtns = paramsList.querySelectorAll '.param-remove-btn'

    for btn in removeBtns
      # Éviter les doublons d'event listeners
      btn.removeEventListener 'click', arguments.callee
      btn.addEventListener 'click', ->
        @parentElement.remove()

  _validateWidgetForm: ->
    titleInput = document.getElementById 'widget-title-input'
    spaceSelect = document.getElementById 'widget-space-select'
    selectedFields = document.querySelectorAll '#selected-fields .field-item'

    errors = []

    # Valider le titre
    unless titleInput and titleInput.value.trim()
      errors.push 'Le titre du widget est requis'

    # Valider l'espace
    unless spaceSelect and spaceSelect.value
      errors.push 'La sélection d\'un espace est requise'

    # Valider les champs (au moins un champ sélectionné)
    unless selectedFields.length > 0
      errors.push 'Au moins un champ doit être sélectionné'

    return errors

  _collectWidgetData: ->
    titleInput = document.getElementById 'widget-title-input'
    spaceSelect = document.getElementById 'widget-space-select'
    selectedType = document.querySelector 'input[name="widget-type"]:checked'
    selectedFields = document.querySelectorAll '#selected-fields .field-item'
    paramRows = document.querySelectorAll '#widget-params-list .param-row'

    # Collecter les champs sélectionnés
    fields = []
    for field in selectedFields
      fields.push field.dataset.fieldName or field.textContent

    # Collecter les paramètres
    params = {}
    for paramRow in paramRows
      keyInput = paramRow.querySelector '.param-key'
      valueInput = paramRow.querySelector '.param-value'

      if keyInput and valueInput and keyInput.value.trim()
        params[keyInput.value.trim()] = valueInput.value.trim()

    return {
      title: titleInput.value.trim()
      spaceId: spaceSelect.value
      type: selectedType.value or 'table'
      fields: fields
      params: params
    }

  _submitWidget: (app) ->
    # Valider le formulaire
    errors = window.AppViewHelpers._validateWidgetForm()

    if errors.length > 0
      tdbAlert 'Erreurs de validation:\n' + errors.join('\n'), 'error'
      return

    # Collecter les données
    widgetData = window.AppViewHelpers._collectWidgetData()

    # Récupérer l'ID de la vue actuelle depuis l'URL
    viewId = window.location.hash.match(/view\/([a-f0-9-]+)/)?[1]

    unless viewId
      tdbAlert 'Erreur: impossible de déterminer l\'ID de la vue actuelle', 'error'
      return

    # Préparer la mutation GraphQL
    mutation = '''
      mutation AddWidgetToView($viewId: ID!, $widget: WidgetInput!) {
        addWidgetToView(viewId: $viewId, widget: $widget) {
          id
          name
          yaml
        }
      }
    '''

    # Préparer les variables
    variables = {
      viewId: viewId
      widget: {
        title: widgetData.title
        type: widgetData.type
        spaceId: widgetData.spaceId
        fields: widgetData.fields
        groupBy: widgetData.groupBy
        params: widgetData.params
        position: {
          x: 0
          y: 0
          w: 6
          h: 4
        }
      }
    }

    # Exécuter la mutation
    window.GQL.mutate(mutation, variables)
      .then (result) ->
        if result.errors
          console.error 'GraphQL errors:', result.errors
          tdbAlert 'Erreur lors de la création du widget: ' + result.errors[0].message, 'error'
        else
          console.log 'Widget créé avec succès:', result.addWidgetToView
          window.AppViewHelpers._closeWidgetModal app
          # Rafraîchir la vue pour afficher le nouveau widget
          window.AppViewHelpers._renderCustomViewPreview app, result.addWidgetToView.yaml
      .catch (error) ->
        console.error 'Network error:', error
        tdbAlert 'Erreur réseau lors de la création du widget: ' + error.message, 'error'

_getWidgetConfig: (app) ->
  # Récupérer la configuration complète du widget
  titleInput = document.getElementById 'widget-title-input'
  spaceSelect = document.getElementById 'widget-space-select'
  selectedFields = document.querySelectorAll '#selected-fields .field-item'
  widgetTypeRadio = document.querySelector 'input[name="widget-type"]:checked'
  paramRows = document.querySelectorAll '#widget-params-list .param-row'

  config = {
    title: titleInput?.value or 'Widget sans titre'
    space: spaceSelect?.value or ''
    spaceName: spaceSelect?.options[spaceSelect?.selectedIndex]?.textContent or ''
    widgetType: widgetTypeRadio?.value or 'table'
    fields: []
    params: {}
  }

  # Ajouter les champs sélectionnés
  for field in selectedFields
    config.fields.push {
      id: field.dataset.fieldId
      name: field.dataset.fieldName
      type: field.dataset.fieldType
    }

  config

  _closeWidgetModal: (app) ->
    modal = document.getElementById 'add-widget-modal'
    return unless modal

    # Masquer la modale
    modal.classList.add 'hidden'

    # Réinitialiser le formulaire
    window.AppViewHelpers._resetWidgetForm()

  _resetWidgetForm: ->
    titleInput = document.getElementById 'widget-title-input'
    spaceSelect = document.getElementById 'widget-space-select'

    # Réinitialiser les champs
    if titleInput then titleInput.value = 'Mon widget'
    if spaceSelect then spaceSelect.value = ''

    # Réinitialiser les champs sélectionnés
    availableContainer = document.getElementById 'available-fields'
    selectedContainer = document.getElementById 'selected-fields'

    if availableContainer and selectedContainer
      # Remettre les champs sélectionnés dans disponibles
      selectedFields = selectedContainer.querySelectorAll '.field-item'
      for field in selectedFields
        field.classList.remove 'selected'
        availableContainer.appendChild field

    # Réinitialiser le type de widget
    tableType = document.getElementById 'widget-type-table'
    if tableType then tableType.checked = true

    # Réinitialiser les paramètres
    paramsList = document.getElementById 'widget-params-list'
    if paramsList
      # Garder seulement la première ligne de paramètres
      while paramsList.children.length > 1
        paramsList.removeChild paramsList.lastChild

      # Vider les champs de la première ligne
      firstRow = paramsList.querySelector '.param-row'
      if firstRow
        keyInput = firstRow.querySelector '.param-key'
        valueInput = firstRow.querySelector '.param-value'
        if keyInput then keyInput.value = ''
        if valueInput then valueInput.value = ''

  _getWidgetConfig: (app) ->
    # Récupérer la configuration complète du widget
    titleInput = document.getElementById 'widget-title-input'
    spaceSelect = document.getElementById 'widget-space-select'
    selectedFields = document.querySelectorAll '#selected-fields .field-item'
    widgetTypeRadio = document.querySelector 'input[name="widget-type"]:checked'
    paramRows = document.querySelectorAll '#widget-params-list .param-row'

    config = {
      title: titleInput?.value or 'Widget sans titre'
      space: spaceSelect?.value or ''
      spaceName: spaceSelect?.options[spaceSelect?.selectedIndex]?.textContent or ''
      widgetType: widgetTypeRadio?.value or 'table'
      fields: []
      params: {}
    }

    # Ajouter les champs sélectionnés
    for field in selectedFields
      config.fields.push {
        id: field.dataset.fieldId
        name: field.dataset.fieldName
        type: field.dataset.fieldType
      }

    # Ajouter les paramètres
    for paramRow in paramRows
      keyInput = paramRow.querySelector '.param-key'
      valueInput = paramRow.querySelector '.param-value'

      if keyInput?.value and valueInput?.value
        config.params[keyInput.value] = valueInput.value

    return config

  _showWidgetConfig: (app, type, data) ->
    container = app.el.widgetConfigForm()
    container.innerHTML = ''
    if type == 'table'
      config = document.createElement 'div'
      config.innerHTML = """
        <div class="config-field">
          <label>Titre:</label>
          <input type="text" id="widget-title" value="#{data.name}" />
        </div>
        <div class="config-field">
          <label>Espace:</label>
          <span>#{data.name}</span>
        </div>
        <div class="config-field">
          <label>Type de widget:</label>
          <div class="widget-type-options">
            <div class="widget-type-option">
              <input type="radio" name="widget-type" value="table" checked>
              <span>Table</span>
            </div>
            <div class="widget-type-option">
              <input type="radio" name="widget-type" value="chart">
              <span>Graphique</span>
            </div>
          </div>
        </div>
        <div class="config-field">
          <label>Espace:</label>
          <select id="widget-space-select">
            <option value="">Sélectionner un espace...</option>
          </select>
        </div>
        <div class="config-field">
          <label>Champs:</label>
          <div id="available-fields"></div>
          <div id="selected-fields"></div>
        </div>
        <div class="config-field">
          <label>Paramètres:</label>
          <button type="button" id="add-param-btn">Ajouter un paramètre</button>
          <div id="widget-params-list"></div>
        </div>
      """
      container.appendChild config
    else if type == 'plugin'
      config = document.createElement 'div'
      config.innerHTML = """
        <div class="config-field">
          <label>Titre:</label>
          <input type="text" id="widget-title" value="#{data.name}" />
        </div>
        <div class="config-field">
          <label>Type:</label>
          <span>#{data.type}</span>
        </div>
      """
      container.appendChild config

  _bindAddWidgetModal: (app) ->
    # Lier les événements pour la nouvelle structure
    window.AppViewHelpers._bindWidgetTypeSelection app
    window.AppViewHelpers._bindParamsManagement app

  _confirmAddWidget: (app) ->
    cv = app._currentCustomView
    return unless cv

    # Récupérer la configuration complète
    widgetConfig = window.AppViewHelpers._getWidgetConfig app

    # Validation
    unless widgetConfig.space
      tdbAlert "Veuillez sélectionner un espace", 'error'
      return

    unless widgetConfig.fields.length > 0
      tdbAlert "Veuillez sélectionner au moins un champ", 'error'
      return

    try
      # Parser le YAML existant
      parsed = jsyaml.load cv.yaml

      # Créer le widget YAML selon le type
      widgetYaml = window.AppViewHelpers._createWidgetYaml widgetConfig

      # Ajouter le widget comme enfant du layout racine
      parsed.layout.children.push jsyaml.load(widgetYaml)[0]

      # Mettre à jour le YAML
      newYaml = jsyaml.dump parsed

      # Sauvegarder
      GQL.mutate(app._updateCustomViewMutation, { id: cv.id, input: { yaml: newYaml } })
        .then (data) ->
          app._currentCustomView = data.updateCustomView
          window.AppViewHelpers._closeAddWidgetModal app
          window.AppViewHelpers._renderCustomViewPreview app, newYaml
        .catch (err) -> tdbAlert app._err(err), 'error'
    catch e
      tdbAlert "Erreur YAML : #{e.message}", 'error'

  _createWidgetYaml: (config) ->
    # Créer le YAML du widget selon la configuration
    widget = {
      title: config.title
      type: config.widgetType
      space: config.space
    }

    # Ajouter les champs
    if config.fields.length > 0
      widget.fields = config.fields.map (field) -> field.name

    # Ajouter le groupement si spécifié
    if config.groupBy
      widget.groupBy = config.groupBy

    # Ajouter les paramètres personnalisés
    if Object.keys(config.params).length > 0
      for key, value of config.params
        widget[key] = value

    # Convertir en YAML
    return jsyaml.dump([widget])

  _renderCustomViewPreview: (app, yaml) ->
    # Utiliser la fonction renderCustomViewPreview existante
    window.AppViewHelpers.renderCustomViewPreview app, yaml

    # Mettre à jour le YAML dans la vue courante pour que l'éditeur soit synchronisé
    if app._currentCustomView
      app._currentCustomView.yaml = yaml

  _closeWidgetModal: (app) ->
    modal = document.getElementById 'add-widget-modal'
    return unless modal
    modal.classList.add 'hidden'
    app._selectedWidget = null

  _closeAddWidgetModal: (app) ->
    app.el.addWidgetModal().classList.add 'hidden'
    app._selectedWidget = null

# Gestionnaires d'événements principaux pour la modale
window.AppViewHelpers._bindAddWidgetModal = (app) ->
  # Bouton de confirmation
  app.el.addWidgetConfirmBtn().addEventListener 'click', ->
    window.AppViewHelpers._confirmAddWidget app

  # Bouton d'annulation
  app.el.addWidgetCancelBtn().addEventListener 'click', ->
    window.AppViewHelpers._closeAddWidgetModal app

# Ajouter les fonctions manquantes à window.AppViewHelpers
window.AppViewHelpers._closeWidgetModal = (app) ->
  modal = document.getElementById 'add-widget-modal'
  return unless modal
  modal.classList.add 'hidden'
  app._selectedWidget = null

window.AppViewHelpers._renderCustomViewPreview = (app, yaml) ->
  # Utiliser la fonction renderCustomViewPreview existante
  window.AppViewHelpers.renderCustomViewPreview app, yaml

# ── Zone Management (Phase 3) ────────────────────────────────────────────

window.AppViewHelpers._bindZoneEvents = (app) ->
  # Bouton créer une zone
  createBtn = document.getElementById 'create-zone-btn'
  if createBtn
    createBtn.addEventListener 'click', =>
      window.AppViewHelpers._openCreateZoneModal app

  # Bouton gérer les zones
  manageBtn = document.getElementById 'zone-manage-btn'
  if manageBtn
    manageBtn.addEventListener 'click', =>
      window.AppViewHelpers._openZoneManageModal app

  # Écouter les événements de redimensionnement
  document.addEventListener 'zone-resize', (evt) =>
    { zoneId, factor } = evt.detail
    window.AppViewHelpers._resizeZone app, zoneId, factor

window.AppViewHelpers._openCreateZoneModal = (app) ->
  return unless app._currentCustomView?.id

  # Créer la modale si elle n'existe pas
  modal = document.getElementById 'zone-modal'
  unless modal
    modal = document.createElement 'div'
    modal.id = 'zone-modal'
    modal.className = 'modal hidden'
    modal.innerHTML = """
      <div class="modal-content">
        <div class="modal-header">
          <h3>Créer une nouvelle zone</h3>
          <button class="modal-close">&times;</button>
        </div>
        <div class="modal-body">
          <div class="form-group">
            <label for="zone-title">Titre de la zone:</label>
            <input type="text" id="zone-title" class="form-input" placeholder="Ma zone">
          </div>
          <div class="form-group">
            <label for="zone-factor">Proportion (0.1 - 1.0):</label>
            <input type="number" id="zone-factor" class="form-input" min="0.1" max="1.0" step="0.1" value="0.5">
          </div>
          <div class="form-group">
            <label for="zone-direction">Direction:</label>
            <select id="zone-direction" class="form-select">
              <option value="vertical">Vertical</option>
              <option value="horizontal">Horizontal</option>
            </select>
          </div>
        </div>
        <div class="modal-footer">
          <button id="zone-cancel-btn" class="btn btn-secondary">Annuler</button>
          <button id="zone-save-btn" class="btn btn-primary">Créer</button>
        </div>
      </div>
    """
    document.body.appendChild modal

  # Afficher la modale
  modal.classList.remove 'hidden'
  document.getElementById('zone-title').focus()

  # Lier les événements
  closeBtn = modal.querySelector '.modal-close'
  cancelBtn = document.getElementById 'zone-cancel-btn'
  saveBtn = document.getElementById 'zone-save-btn'

  closeModal = ->
    modal.classList.add 'hidden'
    # Réinitialiser le formulaire
    document.getElementById('zone-title').value = ''
    document.getElementById('zone-factor').value = '0.5'
    document.getElementById('zone-direction').value = 'vertical'

  closeBtn.addEventListener 'click', closeModal
  cancelBtn.addEventListener 'click', closeModal

  saveBtn.addEventListener 'click', =>
    title = document.getElementById('zone-title').value.trim()
    factor = parseFloat(document.getElementById('zone-factor').value)
    direction = document.getElementById('zone-direction').value

    unless title
      tdbAlert 'Le titre de la zone est requis', 'error'
      return

    if factor < 0.1 or factor > 1.0
      tdbAlert 'La proportion doit être entre 0.1 et 1.0', 'error'
      return

    zoneData = { title, factor, direction }
    window.AppViewHelpers._createZone app, zoneData
    closeModal()

  # Fermer avec ESC
  modal.addEventListener 'keydown', (e) ->
    if e.key == 'Escape'
      closeModal()

window.AppViewHelpers._createZone = (app, zoneData) ->
  return unless app._currentCustomView?.id

  mutation = """
    mutation CreateZone($pageId: ID!, $zoneData: ZoneInput!) {
      createZone(pageId: $pageId, zoneData: $zoneData) {
        id
        title
        factor
        direction
      }
    }
  """

  GQL.mutate mutation, { pageId: app._currentCustomView.id, zoneData }
    .then (result) ->
      if result.errors
        console.error 'GraphQL errors:', result.errors
        tdbAlert 'Erreur lors de la création de la zone', 'error'
      else
        console.log 'Zone créée:', result.createZone
        # Recharger la page pour afficher la nouvelle zone
        window.AppViewHelpers._refreshCurrentPage app
    .catch (error) ->
      console.error 'Network error:', error
      tdbAlert 'Erreur réseau lors de la création de la zone: ' + error.message, 'error'

window.AppViewHelpers._resizeZone = (app, zoneId, factor) ->
  return unless app._currentCustomView?.id

  mutation = """
    mutation ResizeZone($pageId: ID!, $zoneId: ID!, $factor: Float!) {
      resizeZone(pageId: $pageId, zoneId: $zoneId, factor: $factor) {
        id
        factor
      }
    }
  """

  GQL.mutate mutation, {
    pageId: app._currentCustomView.id,
    zoneId,
    factor
  }
    .then (result) ->
      if result.errors
        console.error 'GraphQL errors:', result.errors
        tdbAlert 'Erreur lors du redimensionnement', 'error'
      else
        console.log 'Zone redimensionnée:', result.resizeZone
        # Le redimensionnement visuel est déjà fait, juste confirmer
    .catch (error) ->
      console.error 'Network error:', error
      tdbAlert 'Erreur réseau lors du redimensionnement: ' + error.message, 'error'

window.AppViewHelpers._refreshCurrentPage = (app) ->
  return unless app._currentCustomView?.id

  # Recharger la page depuis la base
  query = """
    query GetView($viewId: ID!) {
      customView(id: $viewId) {
        id
        name
        yaml
      }
    }
  """

  GQL.query(query, { viewId: app._currentCustomView.id }).then (data) ->
    if data.customView
      app._currentCustomView = data.customView
      window.AppViewHelpers.renderCustomViewPreview app, data.customView.yaml
  .catch (error) ->
    console.error 'Error refreshing page:', error
    tdbAlert 'Erreur lors du rafraîchissement de la page', 'error'

window.AppViewHelpers._parseZonesFromYAML = (yamlText) ->
  zones = []
  try
    parsed = jsyaml.load yamlText
    return [] unless parsed and parsed.layout
    
    # Recursive function to traverse the layout and collect zones
    collectZones = (node, path = '') ->
      return unless node?
      
      # Check if this node represents a zone (has layout properties or is a layout node)
      if node.direction or node.layout
        # Determine the actual zone object
        zone = if node.layout then node.layout else node
        
        # Only process if it's a zone (has direction and children, or is explicitly a layout)
        if zone.direction or (node.layout and node isnt zone)
          # Count widgets in this zone
          widgetCount = 0
          countWidgets = (children) ->
            return 0 unless children and Array.isArray(children)
            count = 0
            for child in children
              if child.widget
                count += 1
              else if child.layout or child.direction
                # Recursively count widgets in nested zones
                count += countWidgets(child.children)
            count
          
          if zone.children
            widgetCount = countWidgets(zone.children)
          
          # Create zone info
          zoneInfo =
            id: zone.id or null
            title: zone.title or "Zone #{zone.id or 'unknown'}"
            widgetCount: widgetCount
            direction: zone.direction or 'vertical'
            factor: zone.factor or 1
            
          zones.push zoneInfo
          
          # Recursively process children
          if zone.children and Array.isArray(zone.children)
            for child in zone.children
              collectZones(child, "#{path}.#{zones.length}")
      
      # Also process children if this is a container node
      if node.children and Array.isArray(node.children)
        for child in node.children
          collectZones(child, path)
    
    # Start traversal from the layout root
    collectZones parsed.layout
    
    return zones
  catch e
    console.warn 'Error parsing zones from YAML:', e
    return []

window.AppViewHelpers._openZoneManageModal = (app) ->
  cv = app._currentCustomView
  return unless cv
  
  # Fetch current view YAML to get latest data
  query = """
    query GetView($viewId: ID!) {
      customView(id: $viewId) {
        id
        name
        yaml
      }
    }
  """
  
  window.GQL.query(query, {viewId: cv.id}).then (data) ->
    unless data.customView
      tdbAlert 'Impossible de charger la vue', 'error'
      return
    
    freshCv = data.customView
    yamlText = freshCv.yaml or ''
    
    # Parse zones from YAML
    zones = window.AppViewHelpers._parseZonesFromYAML(yamlText)
    
    # Create modal
    modal = document.createElement 'div'
    modal.className = 'modal'
    modal.innerHTML = '''
      <div class="modal-content">
        <div class="modal-header">
          <h3>Gestion des zones</h3>
          <button class="modal-close-btn">&times;</button>
        </div>
        <div class="modal-body">
          <div class="zone-list">
            <h4>Zones disponibles</h4>
            <div class="zone-items" id="zone-items-list">
              <!-- Zone items will be inserted here -->
            </div>
          </div>
          
          <div class="zone-actions">
            <div class="action-group">
              <label for="split-direction">Direction de séparation:</label>
              <select id="split-direction">
                <option value="vertical">Verticale</option>
                <option value="horizontal">Horizontale</option>
              </select>
            </div>
            
            <button id="merge-zones-btn" class="action-btn" disabled>Fusionner les zones</button>
            <button id="split-zone-btn" class="action-btn" disabled>Séparer la zone</button>
          </div>
        </div>
        <div class="modal-footer">
          <button id="zone-manage-cancel" class="btn">Annuler</button>
        </div>
      </div>
    '''
    
    document.body.appendChild modal
    
    # Populate zone list
    zoneListEl = modal.querySelector('#zone-items-list')
    zoneListEl.innerHTML = ''
    
    for zone in zones
      item = document.createElement 'label'
      item.className = 'zone-item'
      item.innerHTML = '''
        <input type="checkbox" value="''' + zone.id + '''">
        <span class="zone-title">''' + zone.title + '''</span>
        <span class="zone-info">(''' + zone.widgetCount + ''' widgets)</span>
      '''
      zoneListEl.appendChild item
    
    # Get elements
    mergeBtn = modal.querySelector('#merge-zones-btn')
    splitBtn = modal.querySelector('#split-zone-btn')
    directionSelect = modal.querySelector('#split-direction')
    cancelBtn = modal.querySelector('#zone-manage-cancel')
    closeBtn = modal.querySelector('.modal-close-btn')
    checkboxes = modal.querySelectorAll('.zone-item input[type="checkbox"]')
    
    # Update button states based on selection
    updateZoneManagementButtons = ->
      selectedCount = 0
      selectedIds = []
      for cb in checkboxes
        if cb.checked
          selectedCount += 1
          selectedIds.push cb.value
      
      # Merge enabled when exactly 2 zones selected
      mergeBtn.disabled = selectedCount != 2
      
      # Split enabled when exactly 1 zone selected
      splitBtn.disabled = selectedCount != 1
      
      # Store selected IDs for later use
      modal._selectedZoneIds = selectedIds
    
    # Event listeners
    for cb in checkboxes
      cb.addEventListener 'change', updateZoneManagementButtons
    
    cancelBtn.addEventListener 'click', ->
      modal.remove()
    
    closeBtn.addEventListener 'click', ->
      modal.remove()
    
    mergeBtn.addEventListener 'click', ->
      if modal._selectedZoneIds.length != 2
        tdbAlert 'Veuillez sélectionner exactement 2 zones pour la fusion', 'warning'
        return
      
      mutation = """
        mutation MergeZones($pageId: ID!, $zoneId1: ID!, $zoneId2: ID!) {
          mergeZones(pageId: $pageId, zoneId1: $zoneId1, zoneId2: $zoneId2) {
            id
            yaml
          }
        }
      """
      
      variables = {
        pageId: freshCv.id
        zoneId1: modal._selectedZoneIds[0]
        zoneId2: modal._selectedZoneIds[1]
      }
      
      window.GQL.mutate(mutation, variables).then (result) ->
        if result.errors
          tdbAlert 'Erreur lors de la fusion: ' + result.errors[0].message, 'error'
        else
          updatedYaml = result.mergeZones.yaml
          app._currentCustomView.yaml = updatedYaml
          window.AppViewHelpers.renderCustomViewPreview app, updatedYaml
          modal.remove()
      .catch (error) ->
        tdbAlert 'Erreur réseau lors de la fusion: ' + error.message, 'error'
    
    splitBtn.addEventListener 'click', ->
      if modal._selectedZoneIds.length != 1
        tdbAlert 'Veuillez sélectionner exactement 1 zone pour la séparation', 'warning'
        return
      
      direction = directionSelect.value
      mutation = """
        mutation SplitZone($pageId: ID!, $zoneId: ID!, $direction: String!) {
          splitZone(pageId: $pageId, zoneId: $zoneId, direction: $direction) {
            id
            yaml
          }
        }
      """
      
      variables = {
        pageId: freshCv.id
        zoneId: modal._selectedZoneIds[0]
        direction: direction
      }
      
      window.GQL.mutate(mutation, variables).then (result) ->
        if result.errors
          tdbAlert 'Erreur lors de la séparation: ' + result.errors[0].message, 'error'
        else
          updatedYaml = result.splitZone.yaml
          app._currentCustomView.yaml = updatedYaml
          window.AppViewHelpers.renderCustomViewPreview app, updatedYaml
          modal.remove()
      .catch (error) ->
        tdbAlert 'Erreur réseau lors de la séparation: ' + error.message, 'error'
    
    # Initialize button states
    updateZoneManagementButtons()
  .catch (error) ->
    tdbAlert 'Erreur lors du chargement de la vue: ' + error.message, 'error'
