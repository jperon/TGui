# custom_view_resize.coffee — zone resize helpers extracted from custom_view.coffee
# Extends the CustomView class (defined in custom_view.js) via its prototype.
# Loaded after views/custom_view.js.

Object.assign window.CustomView::,
  # Ajouter les poignées de redimensionnement pour les zones (Phase 3)
  _addResizeHandle: (zoneElement, zone) ->
    return unless zone.factor and zone.id

    SNAP_POINTS = [0.25, 0.33, 0.5, 0.66, 0.75]
    SNAP_THRESHOLD = 0.05

    # Créer la poignée de redimensionnement
    resizeHandle = document.createElement 'div'
    resizeHandle.className = 'resize-handle'
    resizeHandle.setAttribute 'data-zone-id', zone.id
    resizeHandle.innerHTML = '⋮'

    # Positionner la poignée
    if zone.direction == 'horizontal'
      resizeHandle.style.position = 'absolute'
      resizeHandle.style.right = '0'
      resizeHandle.style.top = '50%'
      resizeHandle.style.transform = 'translateY(-50%)'
    else
      resizeHandle.style.position = 'absolute'
      resizeHandle.style.bottom = '0'
      resizeHandle.style.left = '50%'
      resizeHandle.style.transform = 'translateX(-50%)'

    # Ajouter les événements de drag
    isDragging = false
    startX = 0
    startY = 0
    startFactor = zone.factor

    resizeHandle.addEventListener 'mousedown', (evt) =>
      isDragging = true
      startX = evt.clientX
      startY = evt.clientY
      startFactor = parseFloat(zoneElement.getAttribute('data-zone-factor'))
      document.body.style.cursor = 'ew-resize'
      evt.preventDefault()

    document.addEventListener 'mousemove', (evt) =>
      return unless isDragging

      # Calculer le nouveau factor
      deltaX = evt.clientX - startX
      deltaY = evt.clientY - startY

      if zone.direction == 'horizontal'
        newFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaX / 200))
      else
        newFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaY / 200))

      # Mettre à jour visuellement
      zoneElement.style.flex = String(newFactor)
      zoneElement.setAttribute 'data-zone-factor', String(newFactor)

      # Afficher le tooltip
      @_showResizeTooltip zoneElement, newFactor

    document.addEventListener 'mouseup', (evt) =>
      return unless isDragging

      isDragging = false
      document.body.style.cursor = ''

      # Calculer le factor final
      deltaX = evt.clientX - startX
      deltaY = evt.clientY - startY

      if zone.direction == 'horizontal'
        finalFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaX / 200))
      else
        finalFactor = Math.max(0.1, Math.min(1.0, startFactor + deltaY / 200))

      # Snap to predefined proportions
      for snapPoint in SNAP_POINTS
        if Math.abs(finalFactor - snapPoint) < SNAP_THRESHOLD
          finalFactor = snapPoint
          break

      # Déclencher la mutation GraphQL
      @_onZoneResize zone.id, finalFactor

      # Cacher le tooltip
      @_hideResizeTooltip()

    zoneElement.appendChild resizeHandle
    zoneElement.style.position = 'relative'  # Nécessaire pour le positionnement absolu

  # Afficher le tooltip de redimensionnement
  _showResizeTooltip: (zoneElement, factor) ->
    tooltip = document.createElement 'div'
    tooltip.className = 'resize-tooltip'
    tooltip.textContent = "#{Math.round(factor * 100)}%"
    tooltip.style.position = 'absolute'
    tooltip.style.top = '-30px'
    tooltip.style.left = '50%'
    tooltip.style.transform = 'translateX(-50%)'
    tooltip.style.background = '#333'
    tooltip.style.color = 'white'
    tooltip.style.padding = '4px 8px'
    tooltip.style.borderRadius = '4px'
    tooltip.style.fontSize = '12px'
    tooltip.style.zIndex = '1000'

    # Supprimer l'ancien tooltip s'il existe
    oldTooltip = zoneElement.querySelector('.resize-tooltip')
    oldTooltip?.remove()

    zoneElement.appendChild tooltip

  # Cacher le tooltip de redimensionnement
  _hideResizeTooltip: ->
    tooltips = document.querySelectorAll '.resize-tooltip'
    for tooltip in tooltips
      tooltip.remove()

  # Callback pour le redimensionnement de zone
  _onZoneResize: (zoneId, factor) ->
    # Émettre un événement personnalisé pour que l'application parente puisse gérer
    event = new CustomEvent 'zone-resize', {
      detail: { zoneId, factor }
    }
    document.dispatchEvent event
