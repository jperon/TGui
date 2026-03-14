(function() {
  // drag_drop_manager.coffee
  // Drag & Drop functionality for widgets in Pages
  var DragDropManager;

  DragDropManager = class DragDropManager {
    constructor(container, options = {}) {
      this.container = container;
      this.options = options;
      this.sortable = null;
      this.onReorder = this.options.onReorder || function() {};
      this.currentPageId = this.options.pageId || null;
      this.widgets = [];
      this.isDragging = false;
      this.init();
    }

    init() {
      if (!(this.container && this.currentPageId)) {
        return;
      }
      
      // Initialiser SortableJS
      return this.sortable = new Sortable(this.container, {
        animation: 150,
        ghostClass: 'widget-ghost',
        chosenClass: 'widget-chosen',
        dragClass: 'widget-dragging',
        handle: this.options.handle || '.widget-header',
        filter: this.options.filter || '.no-drag',
        onStart: (evt) => {
          this.isDragging = true;
          return this.onDragStart(evt);
        },
        onEnd: (evt) => {
          this.isDragging = false;
          this.onDragEnd(evt);
          return this.handleReorder(evt);
        }
      });
    }

    onDragStart(evt) {
      // Ajouter des classes visuelles
      document.body.classList.add('dragging-active');
      
      // Notifier le début du drag
      if (this.options.onDragStart) {
        return this.options.onDragStart(evt);
      }
    }

    onDragEnd(evt) {
      // Retirer les classes visuelles
      document.body.classList.remove('dragging-active');
      
      // Notifier la fin du drag
      if (this.options.onDragEnd) {
        return this.options.onDragEnd(evt);
      }
    }

    handleReorder(evt) {
      var positions;
      if (evt.oldIndex === evt.newIndex) {
        return;
      }
      
      // Extraire les nouvelles positions
      positions = this.extractWidgetPositions();
      
      // Appeler le callback avec les nouvelles positions
      return this.onReorder(positions);
    }

    extractWidgetPositions() {
      var i, index, len, positions, widget, widgetId, widgets;
      positions = [];
      widgets = this.container.querySelectorAll('[data-widget-id]');
      for (index = i = 0, len = widgets.length; i < len; index = ++i) {
        widget = widgets[index];
        widgetId = widget.getAttribute('data-widget-id');
        if (widgetId) {
          positions.push({
            widgetId: widgetId,
            index: index + 1 // 1-based index
          });
        }
      }
      return positions;
    }

    updatePageId(pageId) {
      return this.currentPageId = pageId;
    }

    destroy() {
      if (this.sortable) {
        this.sortable.destroy();
        return this.sortable = null;
      }
    }

    // Méthodes utilitaires
    enable() {
      if (this.sortable) {
        return this.sortable.option('disabled', false);
      }
    }

    disable() {
      if (this.sortable) {
        return this.sortable.option('disabled', true);
      }
    }

    getWidgetOrder() {
      return this.extractWidgetPositions();
    }

  };

  // Exporter la classe
  window.DragDropManager = DragDropManager;

}).call(this);
