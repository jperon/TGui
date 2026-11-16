# app_view_helpers_widget_plugins.coffee — widget plugin helpers extracted from app_view_helpers.coffee
Object.assign window.AppViewHelpers,
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
      app._cmWidgetPluginManifest?.setValue defaults.manifest

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
        manifest: if app._cmWidgetPluginManifest then app._cmWidgetPluginManifest.getValue() else ''
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
      app._cmWidgetPluginManifest?.setValue plugin.manifest or ''

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
    manifest: """
# Manifest facultatif : accès aux données et colonnes/options déclarées.
# Sans manifest, le widget garde l'accès complet (full) et reçoit `gql` brut.
# access: none | read | full   (défaut : read dès qu'un manifest existe)
# columns:
#   - {name: titre, type: String}
#   - {name: debut, type: Date}
#   - {name: fin, type: Date, optional: true}
# options:
#   - {name: couleur, type: color, default: '#36c'}
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
          app._cmWidgetPluginManifest?.setValue p.manifest or ''

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
          app._cmWidgetPluginManifest?.setValue defaults.manifest
      .catch (err) -> tdbAlert app._err(err), 'error'

  _ensureWidgetPluginEditorsSplit: (app) ->
    root = app.el.widgetPluginModal?()
    return unless root
    tplEl = app.el.widgetPluginTemplateEditor?()
    scriptEl = app.el.widgetPluginScriptEditor?()
    manifestEl = app.el.widgetPluginManifestEditor?()
    return unless tplEl and scriptEl and manifestEl
    tplLangSel = app.el.widgetPluginTemplateLanguage?()
    scriptLangSel = app.el.widgetPluginScriptLanguage?()

    row = root.querySelector '.widget-plugin-editors-row'
    tplColCurrent = tplEl.closest '.widget-plugin-editor-col'
    scriptColCurrent = scriptEl.closest '.widget-plugin-editor-col'
    manifestColCurrent = manifestEl.closest '.widget-plugin-editor-col'
    if row and row.contains(tplEl) and row.contains(scriptEl) and row.contains(manifestEl) and
       tplColCurrent and scriptColCurrent and manifestColCurrent and
       tplColCurrent != scriptColCurrent and scriptColCurrent != manifestColCurrent and
       tplColCurrent != manifestColCurrent and
       tplColCurrent.parentElement == row and scriptColCurrent.parentElement == row and
       manifestColCurrent.parentElement == row
      return

    pane = tplEl.closest('.yaml-editor-pane') or scriptEl.closest('.yaml-editor-pane')
    return unless pane
    for oldRow in pane.querySelectorAll '.widget-plugin-editors-row'
      oldRow.remove()

    tplLabel = tplEl.previousElementSibling
    scriptLabel = scriptEl.previousElementSibling
    manifestLabel = manifestEl.previousElementSibling
    tplLangLabel = root.querySelector("label[for='widget-plugin-template-language']")
    scriptLangLabel = root.querySelector("label[for='widget-plugin-script-language']")
    manifestLabel = manifestLabel or root.querySelector("label[for='widget-plugin-manifest-editor']")
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
    unless manifestLabel
      manifestLabel = document.createElement 'label'
      manifestLabel.className = 'formula-hint'
      manifestLabel.textContent = 'Manifest (YAML)'
    tplEl.style.height = ''
    scriptEl.style.height = ''
    manifestEl.style.height = ''
    tplEl.style.flex = '1'
    scriptEl.style.flex = '1'
    manifestEl.style.flex = '1'

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

    manifestCol = document.createElement 'div'
    manifestCol.className = 'widget-plugin-editor-col'
    manifestCol.appendChild manifestLabel if manifestLabel
    manifestCol.appendChild manifestEl

    row.appendChild tplCol
    row.appendChild scriptCol
    row.appendChild manifestCol
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
    unless app._cmWidgetPluginManifest
      app._cmWidgetPluginManifest = CodeMirror app.el.widgetPluginManifestEditor(),
        mode: 'yaml'
        theme: 'monokai'
        lineNumbers: true
        lineWrapping: true
        tabSize: 2
        indentWithTabs: false

    setTimeout (-> app._cmWidgetPluginScript?.refresh()), 10
    setTimeout (-> app._cmWidgetPluginTemplate?.refresh()), 10
    setTimeout (-> app._cmWidgetPluginManifest?.refresh()), 10
    window.AppViewHelpers._loadWidgetPlugins app

