# app_view_helpers_yaml.coffee — YAML editor helpers extracted from app_view_helpers.coffee
Object.assign window.AppViewHelpers,
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

