(function() {
  // custom_view.coffee
  // YAML-driven layout renderer.

  // YAML format example:

  //   layout:
  //     direction: vertical
  //     children:
  //       - factor: 2                         # takes 2/3 of available space (optional, default: 1)
  //         direction: horizontal
  //         children:
  //           - widget:
  //               id: choir-list               # unique widget identifier (required when referenced)
  //               title: Chorales
  //               space: chorale
  //               columns: [annee, pupitre]   # columns to display (optional, default: all)
  //           - widget:
  //               title: Choristes
  //               space: choristes
  //               depends_on:
  //                 widget: choir-list        # source widget id
  //                 field: chorale_id         # FK field in this space
  //                 from_field: id            # referenced field in source widget space (default: id)
  //       - factor: 1
  //         widget:
  //           title: Personnes
  //           space: personnes
  var CustomView,
    hasProp = {}.hasOwnProperty;

  window.CustomView = CustomView = class CustomView {
    constructor(container1, yamlText, allSpaces, allDataViews = [], options = {}) {
      this.container = container1;
      this.yamlText = yamlText;
      this.allSpaces = allSpaces;
      this.allDataViews = allDataViews;
      this.options = options;
      this._widgets = []; // list of { dataView, node, el }
      this._widgetsById = {}; // id -> entry
      this._pluginStateByWidgetId = {};
      this._pluginSelectionListenersByWidgetId = {};
      this.pageId = this.container.getAttribute('data-page-id') || null;
      this.presentationMode = this.options.presentationMode || false;
    }

    // Fonction globale pour gérer l'insertion de layouts pendant l'édition YAML
    static setupLayoutInsertion() {
      // Éviter les doublons de listeners
      if (window._cvLayoutListenerActive) {
        return;
      }
      window.addEventListener('cv-insert-layout', (ev) => {
        var cm, currentYaml, direction, e, newLayout, newYaml, parsed, ref;
        direction = (ref = ev.detail) != null ? ref.direction : void 0;
        if (!direction) {
          return;
        }
        // Récupérer l'instance CodeMirror active
        cm = document.querySelector('.CodeMirror');
        if (!(cm != null ? cm.CodeMirror : void 0)) {
          return;
        }
        currentYaml = cm.CodeMirror.getValue();
        parsed = null;
        try {
          parsed = jsyaml.load(currentYaml);
          if (!parsed) {
            // Si le YAML est vide, jsyaml.load retourne null
            parsed = {};
          }
        } catch (error1) {
          e = error1;
          parsed = {};
        }
        newLayout = {
          direction: direction,
          children: []
        };
        // Logique d'insertion intelligente
        if (!parsed.layout) {
          // Créer un layout racine
          parsed.layout = newLayout;
          this.showNotification('Layout racine créé', 'success');
        } else if (parsed.layout && parsed.layout.children) {
          // Ajouter comme enfant du layout existant
          parsed.layout.children.push(newLayout);
          this.showNotification(`Layout ${direction} ajouté`, 'success');
        } else {
          // Remplacer ou créer le layout
          parsed.layout = newLayout;
          this.showNotification('Layout remplacé', 'success');
        }
        newYaml = jsyaml.dump(parsed);
        try {
          // Valider le YAML généré
          jsyaml.load(newYaml);
          cm.CodeMirror.setValue(newYaml);
          return this.showNotification('Layout inséré avec succès', 'success');
        } catch (error1) {
          e = error1;
          this.showNotification(`Erreur YAML : ${e.message}`, 'error');
          // Restaurer le YAML précédent en cas d'erreur
          return cm.CodeMirror.setValue(currentYaml);
        }
      });
      return window._cvLayoutListenerActive = true;
    }

    static showNotification(message, type = 'info') {
      var colors, notification;
      // Créer une notification temporaire
      notification = document.createElement('div');
      notification.className = `cv-notification cv-notification--${type}`;
      notification.textContent = message;
      notification.style.cssText = `position: fixed;
top: 20px;
right: 20px;
padding: 12px 16px;
border-radius: 4px;
color: white;
font-weight: 500;
z-index: 10000;
opacity: 0;
transform: translateX(100%);
transition: all 0.3s ease;`;
      // Couleurs selon le type
      colors = {
        success: '#28a745',
        error: '#dc3545',
        info: '#17a2b8'
      };
      notification.style.backgroundColor = colors[type] || colors.info;
      // Ajouter au DOM
      document.body.appendChild(notification);
      // Animer l'entrée
      setTimeout(function() {
        notification.style.opacity = '1';
        return notification.style.transform = 'translateX(0)';
      }, 10);
      // Auto-suppression après 3 secondes
      return setTimeout(function() {
        notification.style.opacity = '0';
        notification.style.transform = 'translateX(100%)';
        return setTimeout(function() {
          return document.body.removeChild(notification);
        }, 300);
      }, 3000);
    }

    // Rend un message simple dans un conteneur (textContent, jamais innerHTML).
    _setMessage(container, text, style = 'color:#888;padding:.5rem') {
      var p;
      container.innerHTML = '';
      // Le stub DOM des tests ne vide pas _children via innerHTML : on vide aussi
      // les tableaux quand ils existent (HTMLCollection en navigateur → ignoré).
      if (Array.isArray(container._children)) {
        container._children.length = 0;
      }
      if (Array.isArray(container.children)) {
        container.children.length = 0;
      }
      p = document.createElement('p');
      p.style.cssText = style;
      p.textContent = String(text != null ? text : '');
      return container.appendChild(p);
    }

    mount() {
      var e, el, parsed, ref, root;
      this.container.innerHTML = '';
      this._widgets = [];
      this._widgetsById = {};
      this._mountPromises = [];
      // Apply presentation mode class
      if (this.presentationMode) {
        this.container.classList.add('presentation-mode');
      } else {
        this.container.classList.remove('presentation-mode');
      }
      // Configurer le listener global d'insertion de layouts
      CustomView.setupLayoutInsertion();
      try {
        parsed = jsyaml.load(this.yamlText);
      } catch (error1) {
        e = error1;
        this._setMessage(this.container, `YAML invalide : ${e.message}`, 'color:red;padding:1rem');
        return;
      }
      root = parsed != null ? parsed.layout : void 0;
      if (!root) {
        this.container.innerHTML = "<p style='color:#888;padding:1rem'>Pas de section <code>layout</code> dans le YAML.</p>";
        return;
      }
      el = this._renderZoneOrWidget(root);
      this.container.style.cssText = 'display:flex;flex-direction:column;height:100%;';
      this.container.appendChild(el);
      // Wire depends_on after all DataView grids are ready (mount is async)
      Promise.all(this._mountPromises).then(() => {
        this._wireDepends();
        // Refresh grid layouts now that elements are in the live DOM
        return setTimeout(() => {
          var entry, i, len, ref, ref1, ref2, results;
          ref = this._widgets;
          results = [];
          for (i = 0, len = ref.length; i < len; i++) {
            entry = ref[i];
            results.push((ref1 = entry.dataView) != null ? (ref2 = ref1._grid) != null ? ref2.refreshLayout() : void 0 : void 0);
          }
          return results;
        }, 0);
      });
      // Initialiser le DragDropManager avec support des zones (Phase 3)
      // Disabled in presentation mode
      if (this.pageId && !this.presentationMode) {
        if ((ref = this._dragDropManager) != null) {
          if (typeof ref.destroy === "function") {
            ref.destroy();
          }
        }
        // Vérifier si DragDropManager est disponible
        if (typeof DragDropManager !== 'undefined') {
          return this._dragDropManager = new DragDropManager(this.container, {
            pageId: this.pageId,
            handle: '.widget-header',
            filter: '.no-drag',
            onCreateZone: (zoneData) => {
              // TODO: Implement zone creation if needed
              return console.log('Zone creation not implemented in CustomView', zoneData);
            },
            onResizeZone: (zoneId, factor) => {
              return this._onZoneResize(zoneId, factor);
            },
            onReorder: (positions) => {
              return window.AppViewHelpers.handleWidgetReorder(this, positions);
            },
            onDataViewDrop: (dataViewId, evt) => {
              var mutation;
              mutation = `mutation AddDataViewToPage($pageId: ID!, $dataViewId: ID!) {
  addDataViewToPage(pageId: $pageId, dataViewId: $dataViewId) {
    id
    yaml
  }
}`;
              return GQL.mutate(mutation, {
                pageId: this.pageId,
                dataViewId: dataViewId
              }).then((result) => {
                if (result.errors) {
                  console.error('GraphQL errors:', result.errors);
                  return this.showNotification(`Erreur lors de l'ajout de la vue de données: ${result.errors[0].message}`, 'error');
                } else {
                  this.showNotification('Vue de données ajoutée avec succès', 'success');
                  this.yamlText = result.addDataViewToPage.yaml;
                  this.unmount();
                  return this.mount();
                }
              }).catch((error) => {
                console.error('Network error:', error);
                return this.showNotification('Erreur réseau lors de l\'ajout de la vue de données: ' + error.message, 'error');
              });
            }
          });
        }
      } else {
        return console.warn("DragDropManager not available, drag & drop features disabled");
      }
    }

    // Renders either a zone (direction+children) or a widget node.
    // Applies `factor` (flex proportion) when specified (default: 1).
    // Supports both inline zone keys (direction/children) and wrapped "- layout:" syntax.
    _renderZoneOrWidget(node) {
      var child, el, i, len, ref, zone, zoneContent, zoneHeader;
      zone = node.layout ? node.layout : node;
      if (zone.widget) {
        el = this._renderWidget(zone.widget);
      } else {
        el = document.createElement('div');
        el.className = `cv-zone ${zone.direction || 'vertical'} drop-zone`;
        // Ajouter les attributs pour la gestion des zones (Phase 3)
        if (zone.id) {
          el.setAttribute('data-zone-id', zone.id);
          el.setAttribute('data-zone-title', zone.title || `Zone ${zone.id}`);
          el.setAttribute('data-zone-factor', String(zone.factor || 1));
          el.setAttribute('data-zone-direction', zone.direction || 'vertical');
        }
        // Ajouter un header de zone pour l'identification
        if (zone.title || zone.id) {
          zoneHeader = document.createElement('div');
          zoneHeader.className = 'cv-zone-header';
          zoneHeader.textContent = zone.title || `Zone ${zone.id}`;
          el.appendChild(zoneHeader);
        }
        // Container pour les widgets de la zone
        zoneContent = document.createElement('div');
        zoneContent.className = 'cv-zone-content';
        ref = zone.children || [];
        for (i = 0, len = ref.length; i < len; i++) {
          child = ref[i];
          zoneContent.appendChild(this._renderZoneOrWidget(child));
        }
        el.appendChild(zoneContent);
        // Ajouter les poignées de redimensionnement si factor est défini
        if (zone.factor) {
          this._addResizeHandle(el, zone);
        }
      }
      el.style.flex = node.factor != null ? String(node.factor) : '1';
      return el;
    }

    _renderWidget(wNode) {
      var body, col, delBtn, dv, entry, f, fieldMap, filterFormula, filterInput, filterLabel, filterTimer, filterWrap, i, lang, len, ref, runtimeWidgetId, sp, titleBar, titleText, wrapper;
      wrapper = document.createElement('div');
      wrapper.className = 'cv-widget';
      // Ajouter les attributs pour le drag & drop
      if (wNode.id) {
        wrapper.setAttribute('data-widget-id', wNode.id);
      }
      wrapper.setAttribute('data-widget-type', wNode.type || 'data');
      // Title bar avec classe pour le drag handle
      titleBar = document.createElement('div');
      titleBar.className = 'cv-widget-title widget-header';
      titleText = document.createElement('span');
      titleText.textContent = wNode.title || wNode.space || '';
      titleBar.appendChild(titleText);
      wrapper.appendChild(titleBar);
      body = document.createElement('div');
      body.className = 'cv-widget-body';
      wrapper.appendChild(body);
      // Aggregate widget (read-only summary table)
      if (wNode.type === 'aggregate') {
        this._renderAggregate(body, wNode);
        entry = {
          dataView: null,
          node: wNode,
          el: wrapper
        };
        this._widgets.push(entry);
        if (wNode.id) {
          this._widgetsById[wNode.id] = entry;
        }
        return wrapper;
      }
      // Custom plugin widget (type = plugin name)
      if (wNode.type) {
        runtimeWidgetId = wNode.id || `plugin_${Math.random().toString(36).slice(2)}`;
        this._renderPluginWidget(body, wNode, runtimeWidgetId);
        entry = {
          dataView: null,
          node: wNode,
          el: wrapper,
          plugin: true,
          runtimeWidgetId
        };
        this._widgets.push(entry);
        if (wNode.id) {
          this._widgetsById[wNode.id] = entry;
        }
        return wrapper;
      }
      // Regular data widget
      sp = this._findSpace(wNode.space);
      delBtn = document.createElement('button');
      delBtn.className = 'cv-widget-delete-btn';
      delBtn.title = 'Supprimer les enregistrements sélectionnés';
      delBtn.textContent = '🗑';
      if (!sp) {
        this._setMessage(body, `Espace « ${wNode.space} » introuvable.`, 'color:#aaa;padding:.5rem');
        entry = {
          dataView: null,
          node: wNode,
          el: wrapper
        };
        this._widgets.push(entry);
        if (wNode.id) {
          this._widgetsById[wNode.id] = entry;
        }
        return wrapper;
      }
      // Apply column filter/order if specified
      if (wNode.columns && wNode.columns.length > 0) {
        fieldMap = {};
        ref = sp.fields || [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          fieldMap[f.name] = f;
        }
        sp = Object.assign({}, sp);
        sp.fields = (function() {
          var j, len1, ref1, results;
          ref1 = wNode.columns;
          results = [];
          for (j = 0, len1 = ref1.length; j < len1; j++) {
            col = ref1[j];
            if (fieldMap[col]) {
              results.push(fieldMap[col]);
            }
          }
          return results;
        })();
      }
      dv = new DataView(body, sp);
      filterFormula = '';
      // Apply formula filter from YAML widget config
      if (wNode.filter) {
        filterFormula = typeof wNode.filter === 'string' ? wNode.filter : wNode.filter.formula || '';
        lang = typeof wNode.filter === 'object' ? wNode.filter.language || 'moonscript' : 'moonscript';
        if (filterFormula) {
          dv._formulaFilter = filterFormula;
        }
      }
      filterWrap = document.createElement('div');
      filterWrap.className = 'cv-widget-filter toolbar-filter';
      filterLabel = document.createElement('span');
      filterLabel.className = 'toolbar-filter-label';
      filterLabel.textContent = 'λ';
      filterInput = document.createElement('input');
      filterInput.type = 'text';
      filterInput.className = 'toolbar-filter-input';
      filterInput.placeholder = 'Filtre (MoonScript)';
      filterInput.value = filterFormula;
      filterInput.classList.toggle('active', filterFormula !== '');
      filterWrap.appendChild(filterLabel);
      filterWrap.appendChild(filterInput);
      titleBar.appendChild(filterWrap);
      titleBar.appendChild(delBtn);
      filterTimer = null;
      filterInput.addEventListener('input', (ev) => {
        var val;
        val = ev.target.value.trim();
        ev.target.classList.toggle('active', val !== '');
        clearTimeout(filterTimer);
        return filterTimer = setTimeout((() => {
          return dv.setFormulaFilter(val);
        }), 400);
      });
      dv._formulaInputEl = filterInput;
      this._mountPromises.push(dv.mount());
      delBtn.addEventListener('click', () => {
        return dv.deleteSelected();
      });
      entry = {
        dataView: dv,
        node: wNode,
        el: wrapper
      };
      this._widgets.push(entry);
      if (wNode.id) {
        this._widgetsById[wNode.id] = entry;
      }
      return wrapper;
    }

    _wireDepends() {
      var dep, entry, i, len, ref, results, src;
      ref = this._widgets;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        entry = ref[i];
        dep = entry.node.depends_on;
        if (!dep) {
          continue;
        }
        src = this._widgetsById[dep.widget];
        if (!src) {
          console.warn(`depends_on: widget id '${dep.widget}' introuvable`);
          continue;
        }
        // When a row selection is emitted by source widget, propagate to target.
        // from_field defaults to 'id' when omitted.
        results.push(((entry, dep, src) => {
          var ref1;
          if (((ref1 = src.dataView) != null ? ref1._grid : void 0) != null) {
            return src.dataView._grid.on('click', (ev) => {
              var ref2, rowData, rowKey;
              if ((ev != null ? (ref2 = ev.nativeEvent) != null ? ref2.detail : void 0 : void 0) && ev.nativeEvent.detail > 1) {
                return;
              }
              rowKey = ev.rowKey;
              if (rowKey == null) {
                return;
              }
              rowData = src.dataView._grid.getRow(rowKey);
              if (!(rowData && !rowData.__isNew)) {
                return;
              }
              return this._applyDependencySelection(entry, dep, rowData);
            });
          } else if (src.plugin && dep.widget) {
            return this._setPluginSelectionListener(dep.widget, (selection) => {
              var rows;
              rows = (selection != null ? selection.rows : void 0) || [];
              if (!(rows.length > 0)) {
                return;
              }
              return this._applyDependencySelection(entry, dep, rows[0]);
            });
          }
        })(entry, dep, src));
      }
      return results;
    }

    _applyDependencySelection(entry, dep, rowData) {
      var defaults, filterVal, targetWidgetId;
      filterVal = String(rowData[dep.from_field || 'id']);
      defaults = {};
      defaults[dep.field] = filterVal;
      if (entry.dataView != null) {
        entry.dataView.setDefaultValues(defaults);
        return entry.dataView.setFilter({
          field: dep.field,
          value: filterVal
        });
      } else if (entry.plugin) {
        targetWidgetId = entry.runtimeWidgetId || entry.node.id;
        if (!targetWidgetId) {
          return;
        }
        return this._sendPluginMessage(targetWidgetId, {
          type: 'updateInputSelection',
          selection: {
            rows: [rowData],
            byField: defaults
          }
        });
      }
    }

    _findSpace(nameOrId) {
      var dv, ref, ref1, sp;
      if (!nameOrId) {
        return null;
      }
      sp = this.allSpaces.find(function(s) {
        return s.name === nameOrId || s.id === nameOrId;
      });
      if (sp) {
        return sp;
      }
      // Search in Data Views if not found in regular spaces
      dv = this.allDataViews.find(function(v) {
        return v.name === nameOrId || v.id === nameOrId;
      });
      if (dv) {
        return {
          // Create a virtual space object for DataView class compatibility
          id: dv.id,
          name: dv.name,
          isView: true,
          viewId: dv.id,
          fields: (ref = dv.config) != null ? (ref1 = ref.columns) != null ? ref1.map(function(c) {
            return {
              name: c,
              fieldType: 'String'
            } || [];
          }) : void 0 : void 0
        };
      }
      return null;
    }

    unmount() {
      var entry, i, id, len, ref, ref1, ref2, st;
      ref = this._pluginStateByWidgetId;
      for (id in ref) {
        if (!hasProp.call(ref, id)) continue;
        st = ref[id];
        if (st.onMessage) {
          window.removeEventListener('message', st.onMessage);
        }
      }
      ref1 = this._widgets;
      for (i = 0, len = ref1.length; i < len; i++) {
        entry = ref1[i];
        if ((ref2 = entry.dataView) != null) {
          if (typeof ref2.unmount === "function") {
            ref2.unmount();
          }
        }
      }
      this.container.innerHTML = '';
      this._widgets = [];
      this._pluginStateByWidgetId = {};
      this._pluginSelectionListenersByWidgetId = {};
      return this._widgetsById = {};
    }

    // Toggle grid overlay visibility
    toggleGrid() {
      var existing, overlay;
      this._gridVisible = !this._gridVisible;
      existing = this.container.querySelector('.grid-overlay');
      if (this._gridVisible) {
        if (!existing) {
          overlay = document.createElement('div');
          overlay.className = 'grid-overlay';
          return this.container.appendChild(overlay);
        }
      } else {
        return existing != null ? existing.remove() : void 0;
      }
    }

    // Get current grid visibility state
    isGridVisible() {
      return this._gridVisible || false;
    }

    // Toggle presentation mode (read-only, no drag & drop)
    togglePresentationMode() {
      var ref;
      this.presentationMode = !this.presentationMode;
      if (this.presentationMode) {
        this.container.classList.add('presentation-mode');
        if ((ref = this._dragDropManager) != null) {
          if (typeof ref.destroy === "function") {
            ref.destroy();
          }
        }
        this._dragDropManager = null;
      } else {
        this.container.classList.remove('presentation-mode');
        // Reinitialize drag drop if pageId exists
        if (this.pageId && typeof DragDropManager !== 'undefined') {
          this._dragDropManager = new DragDropManager(this.container, {
            pageId: this.pageId,
            handle: '.widget-header',
            filter: '.no-drag',
            onResizeZone: (zoneId, factor) => {
              return this._onZoneResize(zoneId, factor);
            },
            onReorder: (positions) => {
              return window.AppViewHelpers.handleWidgetReorder(this, positions);
            }
          });
        }
      }
      return this.presentationMode;
    }

    // Get presentation mode state
    isPresentationMode() {
      return this.presentationMode;
    }

  };

}).call(this);
