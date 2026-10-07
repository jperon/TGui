# app_view_helpers_zones.coffee — zone management helpers extracted from app_view_helpers.coffee
Object.assign window.AppViewHelpers,
  _renderZoneItem: (zone) ->
    item = document.createElement 'label'
    item.className = 'zone-item'
    input = document.createElement 'input'
    input.type = 'checkbox'
    input.value = String(zone.id ? '')
    titleSpan = document.createElement 'span'
    titleSpan.className = 'zone-title'
    titleSpan.textContent = String(zone.title ? '')
    infoSpan = document.createElement 'span'
    infoSpan.className = 'zone-info'
    infoSpan.textContent = "(#{zone.widgetCount ? 0} widgets)"
    item.appendChild input
    item.appendChild titleSpan
    item.appendChild infoSpan
    item

  _bindZoneEvents: (app) ->
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

  _openCreateZoneModal: (app) ->
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

  _createZone: (app, zoneData) ->
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

  _resizeZone: (app, zoneId, factor) ->
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

  _refreshCurrentPage: (app) ->
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

  _parseZonesFromYAML: (yamlText) ->
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

  _openZoneManageModal: (app) ->
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
        zoneListEl.appendChild window.AppViewHelpers._renderZoneItem zone
    
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

