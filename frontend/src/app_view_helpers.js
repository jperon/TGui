(function() {
  // app_view_helpers.coffee — custom view preview and drag helpers

  // Creates window.AppViewHelpers. Other app_view_helpers_*.coffee files extend it
  // via Object.assign. Active versions only: dead overwritten definitions removed.
  window.AppViewHelpers = {
    renderCustomViewPreview: function(app, yamlText) {
      var container, cv, e, errDiv, ref, ref1, ref2, ref3, widgetsContainer, zoneToolbar;
      container = app.el.customViewContainer();
      container.classList.remove('hidden'); // le conteneur d'aperçu est masqué par défaut
      if ((ref = app._activeCustomView) != null) {
        if (typeof ref.unmount === "function") {
          ref.unmount();
        }
      }
      container.innerHTML = '';
      // Créer un conteneur pour les widgets draggables
      widgetsContainer = document.createElement('div');
      widgetsContainer.className = 'widgets-container';
      widgetsContainer.setAttribute('data-page-id', (ref1 = app._currentCustomView) != null ? ref1.id : void 0);
      container.appendChild(widgetsContainer);
      // Ajouter les boutons de gestion des zones (Phase 3)
      zoneToolbar = document.createElement('div');
      zoneToolbar.className = 'zone-toolbar';
      zoneToolbar.innerHTML = `<button id="create-zone-btn" class="toolbar-btn" title="Créer une nouvelle zone">
  ＋ Zone
</button>
<button id="zone-manage-btn" class="toolbar-btn" title="Gérer les zones">
  ⚙ Zones
</button>
<button id="grid-toggle-btn" class="toolbar-btn" title="Afficher/Masquer la grille">
  ▦ Grille
</button>`;
      container.insertBefore(zoneToolbar, widgetsContainer);
      // Bind grid toggle button
      zoneToolbar.querySelector('#grid-toggle-btn').addEventListener('click', function() {
        if (app._activeCustomView) {
          return app._activeCustomView.toggleGrid();
        }
      });
      try {
        cv = new CustomView(widgetsContainer, yamlText, app._allSpaces, app._allDataViews);
        app._activeCustomView = cv;
        cv.mount();
        // Initialiser le DragDropManager avec support des zones (Phase 3)
        if ((ref2 = app._currentCustomView) != null ? ref2.id : void 0) {
          if ((ref3 = app._dragDropManager) != null) {
            if (typeof ref3.destroy === "function") {
              ref3.destroy();
            }
          }
          // Vérifier si DragDropManager est disponible
          if (typeof DragDropManager !== 'undefined') {
            app._dragDropManager = new DragDropManager(widgetsContainer, {
              pageId: app._currentCustomView.id,
              handle: '.widget-header',
              filter: '.no-drag',
              onCreateZone: (zoneData) => {
                return window.AppViewHelpers._createZone(app, zoneData);
              },
              onResizeZone: (zoneId, factor) => {
                return window.AppViewHelpers._resizeZone(app, zoneId, factor);
              },
              onReorder: (positions) => {
                return window.AppViewHelpers.handleWidgetReorder(app, positions);
              }
            });
          } else {
            console.warn("DragDropManager not available, zone features disabled");
          }
        }
        // Lier les événements des zones (Phase 3)
        return window.AppViewHelpers._bindZoneEvents(app);
      } catch (error1) {
        e = error1;
        console.error('CustomView error:', e);
        container.innerHTML = '';
        errDiv = document.createElement('div');
        errDiv.className = 'error-message';
        errDiv.textContent = `Erreur YAML : ${e.message}`;
        return container.appendChild(errDiv);
      }
    },
    handleWidgetReorder: function(app, positions) {
      var mutation, ref;
      if (!((ref = app._currentCustomView) != null ? ref.id : void 0)) {
        return;
      }
      // Envoyer la mutation GraphQL pour réordonner les widgets
      mutation = `mutation ReorderWidgets($pageId: ID!, $widgetPositions: [WidgetPosition!]!) {
  reorderWidgets(pageId: $pageId, widgetPositions: $widgetPositions) {
    id
    yaml
  }
}`;
      return GQL.mutate(mutation, {
        pageId: app._currentCustomView.id,
        widgetPositions: positions
      }).then(function(result) {
        var updatedYaml;
        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          return tdbAlert('Erreur lors du réordonnancement: ' + result.errors[0].message, 'error');
        } else {
          // Mettre à jour le YAML et rafraîchir la vue
          updatedYaml = result.reorderWidgets.yaml;
          app._currentCustomView.yaml = updatedYaml;
          return this.renderCustomViewPreview(app, updatedYaml);
        }
      }).catch(function(error) {
        console.error('Network error:', error);
        return tdbAlert('Erreur réseau lors du réordonnancement: ' + error.message, 'error');
      });
    },
    onDragStart: function(app, evt) {
      // Désactiver temporairement d'autres interactions
      return document.body.classList.add('dragging-active');
    },
    onDragEnd: function(app, evt) {
      // Réactiver les interactions
      return document.body.classList.remove('dragging-active');
    },
    _closeWidgetModal: function(app) {
      var modal;
      modal = document.getElementById('add-widget-modal');
      if (!modal) {
        return;
      }
      modal.classList.add('hidden');
      return app._selectedWidget = null;
    },
    _renderCustomViewPreview: function(app, yaml) {
      // Utiliser la fonction renderCustomViewPreview existante
      return window.AppViewHelpers.renderCustomViewPreview(app, yaml);
    }
  };

}).call(this);
