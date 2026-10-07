# app_view_helpers.coffee — custom view preview and drag helpers
#
# Creates window.AppViewHelpers. Other app_view_helpers_*.coffee files extend it
# via Object.assign. Active versions only: dead overwritten definitions removed.

window.AppViewHelpers =
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
      container.innerHTML = ''
      errDiv = document.createElement 'div'
      errDiv.className = 'error-message'
      errDiv.textContent = "Erreur YAML : #{e.message}"
      container.appendChild errDiv

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

  _closeWidgetModal: (app) ->
    modal = document.getElementById 'add-widget-modal'
    return unless modal
    modal.classList.add 'hidden'
    app._selectedWidget = null

  _renderCustomViewPreview: (app, yaml) ->
    # Utiliser la fonction renderCustomViewPreview existante
    window.AppViewHelpers.renderCustomViewPreview app, yaml

