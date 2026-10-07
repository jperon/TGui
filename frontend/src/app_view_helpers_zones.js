(function() {
  // app_view_helpers_zones.coffee — zone management helpers extracted from app_view_helpers.coffee
  Object.assign(window.AppViewHelpers, {
    _bindZoneEvents: function(app) {
      var createBtn, manageBtn;
      // Bouton créer une zone
      createBtn = document.getElementById('create-zone-btn');
      if (createBtn) {
        createBtn.addEventListener('click', () => {
          return window.AppViewHelpers._openCreateZoneModal(app);
        });
      }
      // Bouton gérer les zones
      manageBtn = document.getElementById('zone-manage-btn');
      if (manageBtn) {
        manageBtn.addEventListener('click', () => {
          return window.AppViewHelpers._openZoneManageModal(app);
        });
      }
      // Écouter les événements de redimensionnement
      return document.addEventListener('zone-resize', (evt) => {
        var factor, zoneId;
        ({zoneId, factor} = evt.detail);
        return window.AppViewHelpers._resizeZone(app, zoneId, factor);
      });
    },
    _openCreateZoneModal: function(app) {
      var cancelBtn, closeBtn, closeModal, modal, ref, saveBtn;
      if (!((ref = app._currentCustomView) != null ? ref.id : void 0)) {
        return;
      }
      // Créer la modale si elle n'existe pas
      modal = document.getElementById('zone-modal');
      if (!modal) {
        modal = document.createElement('div');
        modal.id = 'zone-modal';
        modal.className = 'modal hidden';
        modal.innerHTML = `<div class="modal-content">
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
</div>`;
        document.body.appendChild(modal);
      }
      // Afficher la modale
      modal.classList.remove('hidden');
      document.getElementById('zone-title').focus();
      // Lier les événements
      closeBtn = modal.querySelector('.modal-close');
      cancelBtn = document.getElementById('zone-cancel-btn');
      saveBtn = document.getElementById('zone-save-btn');
      closeModal = function() {
        modal.classList.add('hidden');
        // Réinitialiser le formulaire
        document.getElementById('zone-title').value = '';
        document.getElementById('zone-factor').value = '0.5';
        return document.getElementById('zone-direction').value = 'vertical';
      };
      closeBtn.addEventListener('click', closeModal);
      cancelBtn.addEventListener('click', closeModal);
      saveBtn.addEventListener('click', () => {
        var direction, factor, title, zoneData;
        title = document.getElementById('zone-title').value.trim();
        factor = parseFloat(document.getElementById('zone-factor').value);
        direction = document.getElementById('zone-direction').value;
        if (!title) {
          tdbAlert('Le titre de la zone est requis', 'error');
          return;
        }
        if (factor < 0.1 || factor > 1.0) {
          tdbAlert('La proportion doit être entre 0.1 et 1.0', 'error');
          return;
        }
        zoneData = {title, factor, direction};
        window.AppViewHelpers._createZone(app, zoneData);
        return closeModal();
      });
      // Fermer avec ESC
      return modal.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
          return closeModal();
        }
      });
    },
    _createZone: function(app, zoneData) {
      var mutation, ref;
      if (!((ref = app._currentCustomView) != null ? ref.id : void 0)) {
        return;
      }
      mutation = `mutation CreateZone($pageId: ID!, $zoneData: ZoneInput!) {
  createZone(pageId: $pageId, zoneData: $zoneData) {
    id
    title
    factor
    direction
  }
}`;
      return GQL.mutate(mutation, {
        pageId: app._currentCustomView.id,
        zoneData
      }).then(function(result) {
        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          return tdbAlert('Erreur lors de la création de la zone', 'error');
        } else {
          console.log('Zone créée:', result.createZone);
          // Recharger la page pour afficher la nouvelle zone
          return window.AppViewHelpers._refreshCurrentPage(app);
        }
      }).catch(function(error) {
        console.error('Network error:', error);
        return tdbAlert('Erreur réseau lors de la création de la zone: ' + error.message, 'error');
      });
    },
    _resizeZone: function(app, zoneId, factor) {
      var mutation, ref;
      if (!((ref = app._currentCustomView) != null ? ref.id : void 0)) {
        return;
      }
      mutation = `mutation ResizeZone($pageId: ID!, $zoneId: ID!, $factor: Float!) {
  resizeZone(pageId: $pageId, zoneId: $zoneId, factor: $factor) {
    id
    factor
  }
}`;
      return GQL.mutate(mutation, {
        pageId: app._currentCustomView.id,
        zoneId,
        factor
      }).then(function(result) {
        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          return tdbAlert('Erreur lors du redimensionnement', 'error');
        } else {
          return console.log('Zone redimensionnée:', result.resizeZone);
        }
      // Le redimensionnement visuel est déjà fait, juste confirmer
      }).catch(function(error) {
        console.error('Network error:', error);
        return tdbAlert('Erreur réseau lors du redimensionnement: ' + error.message, 'error');
      });
    },
    _refreshCurrentPage: function(app) {
      var query, ref;
      if (!((ref = app._currentCustomView) != null ? ref.id : void 0)) {
        return;
      }
      // Recharger la page depuis la base
      query = `query GetView($viewId: ID!) {
  customView(id: $viewId) {
    id
    name
    yaml
  }
}`;
      return GQL.query(query, {
        viewId: app._currentCustomView.id
      }).then(function(data) {
        if (data.customView) {
          app._currentCustomView = data.customView;
          return window.AppViewHelpers.renderCustomViewPreview(app, data.customView.yaml);
        }
      }).catch(function(error) {
        console.error('Error refreshing page:', error);
        return tdbAlert('Erreur lors du rafraîchissement de la page', 'error');
      });
    },
    _parseZonesFromYAML: function(yamlText) {
      var collectZones, e, parsed, zones;
      zones = [];
      try {
        parsed = jsyaml.load(yamlText);
        if (!(parsed && parsed.layout)) {
          return [];
        }
        
        // Recursive function to traverse the layout and collect zones
        collectZones = function(node, path = '') {
          var child, countWidgets, i, j, len, len1, ref, ref1, results, widgetCount, zone, zoneInfo;
          if (node == null) {
            return;
          }
          
          // Check if this node represents a zone (has layout properties or is a layout node)
          if (node.direction || node.layout) {
            // Determine the actual zone object
            zone = node.layout ? node.layout : node;
            
            // Only process if it's a zone (has direction and children, or is explicitly a layout)
            if (zone.direction || (node.layout && node !== zone)) {
              // Count widgets in this zone
              widgetCount = 0;
              countWidgets = function(children) {
                var child, count, i, len;
                if (!(children && Array.isArray(children))) {
                  return 0;
                }
                count = 0;
                for (i = 0, len = children.length; i < len; i++) {
                  child = children[i];
                  if (child.widget) {
                    count += 1;
                  } else if (child.layout || child.direction) {
                    // Recursively count widgets in nested zones
                    count += countWidgets(child.children);
                  }
                }
                return count;
              };
              if (zone.children) {
                widgetCount = countWidgets(zone.children);
              }
              
              // Create zone info
              zoneInfo = {
                id: zone.id || null,
                title: zone.title || `Zone ${zone.id || 'unknown'}`,
                widgetCount: widgetCount,
                direction: zone.direction || 'vertical',
                factor: zone.factor || 1
              };
              zones.push(zoneInfo);
              
              // Recursively process children
              if (zone.children && Array.isArray(zone.children)) {
                ref = zone.children;
                for (i = 0, len = ref.length; i < len; i++) {
                  child = ref[i];
                  collectZones(child, `${path}.${zones.length}`);
                }
              }
            }
          }
          
          // Also process children if this is a container node
          if (node.children && Array.isArray(node.children)) {
            ref1 = node.children;
            results = [];
            for (j = 0, len1 = ref1.length; j < len1; j++) {
              child = ref1[j];
              results.push(collectZones(child, path));
            }
            return results;
          }
        };
        
        // Start traversal from the layout root
        collectZones(parsed.layout);
        return zones;
      } catch (error1) {
        e = error1;
        console.warn('Error parsing zones from YAML:', e);
        return [];
      }
    },
    _openZoneManageModal: function(app) {
      var cv, query;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      
      // Fetch current view YAML to get latest data
      query = `query GetView($viewId: ID!) {
  customView(id: $viewId) {
    id
    name
    yaml
  }
}`;
      return window.GQL.query(query, {
        viewId: cv.id
      }).then(function(data) {
        var cancelBtn, cb, checkboxes, closeBtn, directionSelect, freshCv, i, item, j, len, len1, mergeBtn, modal, splitBtn, updateZoneManagementButtons, yamlText, zone, zoneListEl, zones;
        if (!data.customView) {
          tdbAlert('Impossible de charger la vue', 'error');
          return;
        }
        freshCv = data.customView;
        yamlText = freshCv.yaml || '';
        
        // Parse zones from YAML
        zones = window.AppViewHelpers._parseZonesFromYAML(yamlText);
        
        // Create modal
        modal = document.createElement('div');
        modal.className = 'modal';
        modal.innerHTML = `<div class="modal-content">
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
</div>`;
        document.body.appendChild(modal);
        
        // Populate zone list
        zoneListEl = modal.querySelector('#zone-items-list');
        zoneListEl.innerHTML = '';
        for (i = 0, len = zones.length; i < len; i++) {
          zone = zones[i];
          item = document.createElement('label');
          item.className = 'zone-item';
          item.innerHTML = `<input type="checkbox" value="` + zone.id + `">
<span class="zone-title">` + zone.title + `</span>
<span class="zone-info">(` + zone.widgetCount + ` widgets)</span>`;
          zoneListEl.appendChild(item);
        }
        
        // Get elements
        mergeBtn = modal.querySelector('#merge-zones-btn');
        splitBtn = modal.querySelector('#split-zone-btn');
        directionSelect = modal.querySelector('#split-direction');
        cancelBtn = modal.querySelector('#zone-manage-cancel');
        closeBtn = modal.querySelector('.modal-close-btn');
        checkboxes = modal.querySelectorAll('.zone-item input[type="checkbox"]');
        
        // Update button states based on selection
        updateZoneManagementButtons = function() {
          var cb, j, len1, selectedCount, selectedIds;
          selectedCount = 0;
          selectedIds = [];
          for (j = 0, len1 = checkboxes.length; j < len1; j++) {
            cb = checkboxes[j];
            if (cb.checked) {
              selectedCount += 1;
              selectedIds.push(cb.value);
            }
          }
          
          // Merge enabled when exactly 2 zones selected
          mergeBtn.disabled = selectedCount !== 2;
          
          // Split enabled when exactly 1 zone selected
          splitBtn.disabled = selectedCount !== 1;
          
          // Store selected IDs for later use
          return modal._selectedZoneIds = selectedIds;
        };

        // Event listeners
        for (j = 0, len1 = checkboxes.length; j < len1; j++) {
          cb = checkboxes[j];
          cb.addEventListener('change', updateZoneManagementButtons);
        }
        cancelBtn.addEventListener('click', function() {
          return modal.remove();
        });
        closeBtn.addEventListener('click', function() {
          return modal.remove();
        });
        mergeBtn.addEventListener('click', function() {
          var mutation, variables;
          if (modal._selectedZoneIds.length !== 2) {
            tdbAlert('Veuillez sélectionner exactement 2 zones pour la fusion', 'warning');
            return;
          }
          mutation = `mutation MergeZones($pageId: ID!, $zoneId1: ID!, $zoneId2: ID!) {
  mergeZones(pageId: $pageId, zoneId1: $zoneId1, zoneId2: $zoneId2) {
    id
    yaml
  }
}`;
          variables = {
            pageId: freshCv.id,
            zoneId1: modal._selectedZoneIds[0],
            zoneId2: modal._selectedZoneIds[1]
          };
          return window.GQL.mutate(mutation, variables).then(function(result) {
            var updatedYaml;
            if (result.errors) {
              return tdbAlert('Erreur lors de la fusion: ' + result.errors[0].message, 'error');
            } else {
              updatedYaml = result.mergeZones.yaml;
              app._currentCustomView.yaml = updatedYaml;
              window.AppViewHelpers.renderCustomViewPreview(app, updatedYaml);
              return modal.remove();
            }
          }).catch(function(error) {
            return tdbAlert('Erreur réseau lors de la fusion: ' + error.message, 'error');
          });
        });
        splitBtn.addEventListener('click', function() {
          var direction, mutation, variables;
          if (modal._selectedZoneIds.length !== 1) {
            tdbAlert('Veuillez sélectionner exactement 1 zone pour la séparation', 'warning');
            return;
          }
          direction = directionSelect.value;
          mutation = `mutation SplitZone($pageId: ID!, $zoneId: ID!, $direction: String!) {
  splitZone(pageId: $pageId, zoneId: $zoneId, direction: $direction) {
    id
    yaml
  }
}`;
          variables = {
            pageId: freshCv.id,
            zoneId: modal._selectedZoneIds[0],
            direction: direction
          };
          return window.GQL.mutate(mutation, variables).then(function(result) {
            var updatedYaml;
            if (result.errors) {
              return tdbAlert('Erreur lors de la séparation: ' + result.errors[0].message, 'error');
            } else {
              updatedYaml = result.splitZone.yaml;
              app._currentCustomView.yaml = updatedYaml;
              window.AppViewHelpers.renderCustomViewPreview(app, updatedYaml);
              return modal.remove();
            }
          }).catch(function(error) {
            return tdbAlert('Erreur réseau lors de la séparation: ' + error.message, 'error');
          });
        });
        
        // Initialize button states
        return updateZoneManagementButtons();
      }).catch(function(error) {
        return tdbAlert('Erreur lors du chargement de la vue: ' + error.message, 'error');
      });
    }
  });

}).call(this);
