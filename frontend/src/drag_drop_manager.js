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
      this.zones = []; // Nouveau: gestion des zones
      this.dropZones = []; // Zones de drop disponibles
      this.init();
    }

    init() {
      if (!(this.container && this.currentPageId)) {
        return;
      }
      // Scanner les zones existantes
      this.scanZones();
      // Initialiser SortableJS avec support multi-conteneurs
      return this.sortable = new Sortable(this.container, {
        animation: 150,
        ghostClass: 'widget-ghost',
        chosenClass: 'widget-chosen',
        dragClass: 'widget-dragging',
        handle: this.options.handle || '.widget-header',
        filter: this.options.filter || '.no-drag',
        group: 'widgets', // Permet le drag entre conteneurs
        onStart: (evt) => {
          this.isDragging = true;
          this.onDragStart(evt);
          return this.highlightDropZones(true);
        },
        onEnd: (evt) => {
          this.isDragging = false;
          this.highlightDropZones(false);
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
      var i, index, len, parentElement, parentId, positions, widget, widgetId, widgets, zoneElement;
      positions = [];
      widgets = this.container.querySelectorAll('[data-widget-id]');
      for (index = i = 0, len = widgets.length; i < len; index = ++i) {
        widget = widgets[index];
        widgetId = widget.getAttribute('data-widget-id');
        if (widgetId) {
          // Déterminer le parent (zone ou racine)
          parentElement = widget.parentElement;
          parentId = null;
          // Vérifier si le widget est dans une zone
          zoneElement = parentElement.closest('[data-zone-id]');
          if (zoneElement) {
            parentId = zoneElement.getAttribute('data-zone-id');
          }
          positions.push({
            widgetId: widgetId,
            index: index + 1, // 1-based index
            parentId: parentId
          });
        }
      }
      return positions;
    }

    // Nouvelles méthodes pour la gestion des zones
    scanZones() {
      var i, len, results, zoneElement, zoneElements, zoneId;
      this.zones = [];
      this.dropZones = [];
      // Scanner toutes les zones dans le conteneur
      zoneElements = this.container.querySelectorAll('[data-zone-id]');
      results = [];
      for (i = 0, len = zoneElements.length; i < len; i++) {
        zoneElement = zoneElements[i];
        zoneId = zoneElement.getAttribute('data-zone-id');
        this.zones.push({
          id: zoneId,
          element: zoneElement,
          title: zoneElement.getAttribute('data-zone-title' || `Zone ${zoneId}`)
        });
        // Configurer SortableJS pour chaque zone
        results.push(this.setupZoneSortable(zoneElement));
      }
      return results;
    }

    setupZoneSortable(zoneElement) {
      return new Sortable(zoneElement, {
        animation: 150,
        ghostClass: 'widget-ghost',
        chosenClass: 'widget-chosen',
        dragClass: 'widget-dragging',
        handle: this.options.handle || '.widget-header',
        filter: this.options.filter || '.no-drag',
        group: 'widgets',
        put: function(to, from, item) {
          // Autoriser le drop dans les zones
          return true;
        },
        onEnd: (evt) => {
          return this.handleReorder(evt);
        }
      });
    }

    highlightDropZones(highlight) {
      var i, len, ref, results, zone;
      ref = this.zones;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        zone = ref[i];
        if (highlight) {
          results.push(zone.element.classList.add('drop-zone-active'));
        } else {
          results.push(zone.element.classList.remove('drop-zone-active'));
        }
      }
      return results;
    }

    createZone(zoneData) {
      // Appeler le callback pour créer une zone
      if (this.options.onCreateZone) {
        return this.options.onCreateZone(zoneData);
      }
    }

    resizeZone(zoneId, factor) {
      // Appeler le callback pour redimensionner une zone
      if (this.options.onResizeZone) {
        return this.options.onResizeZone(zoneId, factor);
      }
    }

    getZoneById(zoneId) {
      var i, len, ref, zone;
      ref = this.zones;
      for (i = 0, len = ref.length; i < len; i++) {
        zone = ref[i];
        if (zone.id === zoneId) {
          return zone;
        }
      }
      return null;
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
