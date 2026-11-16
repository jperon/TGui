# drag_drop_manager.coffee
# Drag & Drop functionality for widgets in Pages

class DragDropManager
  constructor: (@container, @options = {}) ->
    @sortable = null
    @onReorder = @options.onReorder or ->
    @onDataViewDrop = @options.onDataViewDrop or ->
    @currentPageId = @options.pageId or null
    @widgets = []
    @isDragging = false
    @zones = []  # Nouveau: gestion des zones
    @dropZones = []  # Zones de drop disponibles

    @init()

   init: ->
     return unless @container and @currentPageId

     # Scanner les zones existantes
     @scanZones()

     # Initialiser SortableJS avec support multi-conteneurs
     @sortable = new Sortable @container,
       animation: 150
       ghostClass: 'widget-ghost'
       chosenClass: 'widget-chosen'
       dragClass: 'widget-dragging'
       handle: @options.handle or '.widget-header'
       filter: @options.filter or '.no-drag'
       # SortableJS appelle preventDefault() au mousedown sur un élément filtré
       # (preventOnFilter vaut true par défaut) : le champ de filtre λ d'un
       # widget (classe no-drag) ne prendrait jamais le focus. On le désactive.
       preventOnFilter: false
       group: 'widgets'  # Permet le drag entre conteneurs

       onStart: (evt) =>
         @isDragging = true
         @onDragStart evt
         @highlightDropZones true

       onEnd: (evt) =>
         @isDragging = false
         @highlightDropZones false
         @onDragEnd evt
         @handleReorder evt

     # Gestion du drop externe pour les data views
     @container.addEventListener 'dragover', (evt) => @onContainerDragOver(evt)
     @container.addEventListener 'drop', (evt) => @onContainerDrop(evt)

  onDragStart: (evt) ->
    # Ajouter des classes visuelles
    document.body.classList.add 'dragging-active'

    # Notifier le début du drag
    if @options.onDragStart
      @options.onDragStart evt

  onDragEnd: (evt) ->
    # Retirer les classes visuelles
    document.body.classList.remove 'dragging-active'

    # Notifier la fin du drag
    if @options.onDragEnd
      @options.onDragEnd evt

  handleReorder: (evt) ->
    return unless evt.oldIndex != evt.newIndex

    # Extraire les nouvelles positions
    positions = @extractWidgetPositions()

    # Appeler le callback avec les nouvelles positions
    @onReorder positions

  extractWidgetPositions: ->
    positions = []
    widgets = @container.querySelectorAll '[data-widget-id]'

    for widget, index in widgets
      widgetId = widget.getAttribute 'data-widget-id'
      if widgetId
        # Déterminer le parent (zone ou racine)
        parentElement = widget.parentElement
        parentId = null

        # Vérifier si le widget est dans une zone
        zoneElement = parentElement.closest '[data-zone-id]'
        if zoneElement
          parentId = zoneElement.getAttribute 'data-zone-id'

        positions.push {
          widgetId: widgetId
          index: index + 1  # 1-based index
          parentId: parentId
        }

    positions

  # Nouvelles méthodes pour la gestion des zones
  scanZones: ->
    @zones = []
    @dropZones = []

    # Scanner toutes les zones dans le conteneur
    zoneElements = @container.querySelectorAll '[data-zone-id]'

    for zoneElement in zoneElements
      zoneId = zoneElement.getAttribute 'data-zone-id'
      @zones.push {
        id: zoneId
        element: zoneElement
        title: zoneElement.getAttribute 'data-zone-title' or "Zone #{zoneId}"
      }

      # Configurer SortableJS pour chaque zone
      @setupZoneSortable zoneElement

  setupZoneSortable: (zoneElement) ->
    new Sortable zoneElement,
      animation: 150
      ghostClass: 'widget-ghost'
      chosenClass: 'widget-chosen'
      dragClass: 'widget-dragging'
      handle: @options.handle or '.widget-header'
      filter: @options.filter or '.no-drag'
      preventOnFilter: false
      group: 'widgets'
      put: (to, from, item) ->
        # Autoriser le drop dans les zones
        true

      onEnd: (evt) =>
        @handleReorder evt

  highlightDropZones: (highlight) ->
    for zone in @zones
      if highlight
        zone.element.classList.add 'drop-zone-active'
      else
        zone.element.classList.remove 'drop-zone-active'

  createZone: (zoneData) ->
    # Appeler le callback pour créer une zone
    if @options.onCreateZone
      @options.onCreateZone zoneData

  resizeZone: (zoneId, factor) ->
    # Appeler le callback pour redimensionner une zone
    if @options.onResizeZone
      @options.onResizeZone zoneId, factor

  getZoneById: (zoneId) ->
    for zone in @zones
      return zone if zone.id == zoneId
    null

  updatePageId: (pageId) ->
    @currentPageId = pageId

  destroy: ->
    if @sortable
      @sortable.destroy()
      @sortable = null

  # Méthodes utilitaires
  enable: ->
    if @sortable
      @sortable.option 'disabled', false

  disable: ->
    if @sortable
      @sortable.option 'disabled', true

   getWidgetOrder: ->
     @extractWidgetPositions()

    # Gestion du drop externe pour les data views
    onContainerDragOver: (evt) ->
      evt.preventDefault()
      @highlightDropZones true

    onContainerDrop: (evt) ->
      evt.preventDefault()
      evt.stopPropagation()
      dataType = 'application/vnd.tdb.dataview'
      if evt.dataTransfer.types.includes dataType
        data = evt.dataTransfer.getData dataType
        try
          parsed = JSON.parse data
          dataViewId = parsed.id
        catch
          dataViewId = data
        @onDataViewDrop dataViewId, evt
      @highlightDropZones false

# Exporter la classe
window.DragDropManager = DragDropManager
