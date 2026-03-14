# drag_drop_manager.coffee
# Drag & Drop functionality for widgets in Pages

class DragDropManager
  constructor: (@container, @options = {}) ->
    @sortable = null
    @onReorder = @options.onReorder or ->
    @currentPageId = @options.pageId or null
    @widgets = []
    @isDragging = false
    
    @init()

  init: ->
    return unless @container and @currentPageId
    
    # Initialiser SortableJS
    @sortable = new Sortable @container,
      animation: 150
      ghostClass: 'widget-ghost'
      chosenClass: 'widget-chosen'
      dragClass: 'widget-dragging'
      handle: @options.handle or '.widget-header'
      filter: @options.filter or '.no-drag'
      
      onStart: (evt) =>
        @isDragging = true
        @onDragStart evt
        
      onEnd: (evt) =>
        @isDragging = false
        @onDragEnd evt
        @handleReorder evt

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
        positions.push {
          widgetId: widgetId
          index: index + 1  # 1-based index
        }
    
    positions

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

# Exporter la classe
window.DragDropManager = DragDropManager
