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

  // Parse a Data View `config`: the list GraphQL query returns the raw serialized
  // JSON string (data_views.coffee), while the detail query decodes it. Accept both.
  var CustomView, _dataViewColumns, _nodeFactor, _parseDataViewConfig,
    indexOf = [].indexOf,
    hasProp = {}.hasOwnProperty;

  _parseDataViewConfig = function(raw) {
    var e;
    if (!raw) {
      return {};
    }
    if (typeof raw === 'object') {
      return raw;
    }
    try {
      return JSON.parse(raw);
    } catch (error1) {
      e = error1;
      return null;
    }
  };

  // Output columns of a Data View, mirroring backend/core/data_views_executor.moon:
  // groupBy names then aggregate aliases; explicit `columns`; otherwise the source
  // space fields. Each entry is `{ name, fieldType }`, the type reused from the
  // source space when it declares the column.
  _dataViewColumns = function(config, dv, allSpaces) {
    var agg, col, f, fields, j, k, l, len, len1, len2, len3, len4, m, n, name, names, ref, ref1, ref2, ref3, seen, source, typeFor;
    source = null;
    if (dv.sourceSpace && allSpaces) {
      source = allSpaces.find(function(s) {
        return s.id === dv.sourceSpace || s.name === dv.sourceSpace;
      });
    }
    typeFor = function(name) {
      var f;
      if (source) {
        f = (source.fields || []).find(function(sf) {
          return sf.name === name;
        });
        if (f != null ? f.fieldType : void 0) {
          return f.fieldType;
        }
      }
      return 'String';
    };
    names = [];
    if ((config.groupBy && config.groupBy.length > 0) || (config.aggregates && config.aggregates.length > 0)) {
      ref = config.groupBy || [];
      for (j = 0, len = ref.length; j < len; j++) {
        name = ref[j];
        names.push(name);
      }
      ref1 = config.aggregates || [];
      for (k = 0, len1 = ref1.length; k < len1; k++) {
        agg = ref1[k];
        names.push(agg.as || (agg.field ? `${agg.fn}_${agg.field}` : 'count'));
      }
    } else if (config.columns && config.columns.length > 0) {
      ref2 = config.columns;
      for (l = 0, len2 = ref2.length; l < len2; l++) {
        col = ref2[l];
        names.push((typeof col === 'string' ? col : col.as || col.field));
      }
    } else if (source) {
      ref3 = source.fields || [];
      for (m = 0, len3 = ref3.length; m < len3; m++) {
        f = ref3[m];
        names.push(f.name);
      }
    }
    fields = [];
    seen = {};
    for (n = 0, len4 = names.length; n < len4; n++) {
      name = names[n];
      if (!name) {
        continue;
      }
      if (seen[name]) {
        continue;
      }
      seen[name] = true;
      fields.push({
        name: name,
        fieldType: typeFor(name)
      });
    }
    return fields;
  };

  // Facteur de répartition d'un nœud. Lu sur le mapping `widget`/`layout` (forme
  // documentée de doc/fr/get-started.md), puis sur l'entrée elle-même (ancienne
  // forme). Défaut : 1. L'écriture (setChildFactors) vise le mapping.
  _nodeFactor = function(node) {
    if (node.widget && (node.widget.factor != null)) {
      return node.widget.factor;
    }
    if (node.layout && (node.layout.factor != null)) {
      return node.layout.factor;
    }
    if (node.factor != null) {
      return node.factor;
    }
    return 1;
  };

  window.CustomView = CustomView = class CustomView {
    constructor(container1, yamlText1, allSpaces1, allDataViews = [], options = {}) {
      this.container = container1;
      this.yamlText = yamlText1;
      this.allSpaces = allSpaces1;
      this.allDataViews = allDataViews;
      this.options = options;
      this._widgets = []; // list of { dataView, node, el }
      this._widgetsById = {}; // id -> entry
      this._pluginStateByWidgetId = {};
      this._pluginSelectionListenersByWidgetId = {};
      this._resizeObserver = null;
      this._resizeTimer = null;
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

    // Répartit `sizeA + sizeB` px entre deux tuiles voisines après un glisser de
    // `delta` px, en respectant un minimum `min` pour chacune. Fonction pure.
    static redistribute(sizeA, sizeB, delta, min) {
      var a, total;
      total = sizeA + sizeB;
      if (total < 2 * min) {
        return [sizeA, sizeB];
      }
      a = Math.max(min, Math.min(total - min, sizeA + delta));
      return [a, total - a];
    }

    // Réécrit le YAML d'une page en mettant à jour le `factor` des enfants voulus.
    // `path` = indices d'enfants depuis `layout` jusqu'à la zone parente.
    // `factors` = liste de `{ index, factor }` (index dans les enfants de la zone).
    // Le facteur est écrit dans le mapping `widget`/`layout` de l'enfant.
    static setChildFactors(yamlText, path, factors) {
      var child, entry, f, idx, j, k, len, len1, mapping, parent, parsed, ref, ref1, ref2;
      parsed = jsyaml.load(yamlText);
      if (!(parsed != null ? parsed.layout : void 0)) {
        return yamlText;
      }
      parent = parsed.layout;
      ref = path || [];
      for (j = 0, len = ref.length; j < len; j++) {
        idx = ref[j];
        entry = parent != null ? (ref1 = parent.children) != null ? ref1[idx] : void 0 : void 0;
        if (!entry) {
          return yamlText;
        }
        parent = entry.layout ? entry.layout : entry;
      }
      if ((parent != null ? parent.children : void 0) == null) {
        return yamlText;
      }
      ref2 = factors || [];
      for (k = 0, len1 = ref2.length; k < len1; k++) {
        f = ref2[k];
        child = parent.children[f.index];
        if (!child) {
          continue;
        }
        mapping = child.widget ? child.widget : child.layout ? child.layout : child;
        mapping.factor = Math.round(f.factor * 100) / 100;
        if (child.widget || child.layout) {
          delete child.factor;
        }
      }
      return jsyaml.dump(parsed);
    }

    // Anti-rebond : une seule passe de rafraîchissement par salve de changements.
    _refreshGridLayouts() {
      var entry, j, len, ref, ref1, ref2, results;
      ref = this._widgets;
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        entry = ref[j];
        results.push((ref1 = entry.dataView) != null ? (ref2 = ref1._grid) != null ? ref2.refreshLayout() : void 0 : void 0);
      }
      return results;
    }

    // Recalcule la taille des grilles quand la surface d'une tuile change
    // (séparateurs, réouverture de la page, redimensionnement de la fenêtre).
    _setupResizeObserver() {
      var ref;
      if (typeof ResizeObserver === 'undefined') {
        return;
      }
      if ((ref = this._resizeObserver) != null) {
        if (typeof ref.disconnect === "function") {
          ref.disconnect();
        }
      }
      this._resizeObserver = new ResizeObserver((entries) => {
        clearTimeout(this._resizeTimer);
        return this._resizeTimer = setTimeout((() => {
          return this._refreshGridLayouts();
        }), 50);
      });
      return this._resizeObserver.observe(this.container);
    }

    mount() {
      var base, dep, e, el, ff, j, len, name1, parsed, ref, ref1, root, w;
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
      // Index des `from_field` requis par chaque widget source, pour que les
      // champs de liaison soient chargés même s'ils sont absents de `columns`.
      this._linkFieldsByWidgetId = {};
      ref = this._collectWidgetNodes(root);
      for (j = 0, len = ref.length; j < len; j++) {
        w = ref[j];
        dep = w.depends_on;
        if (!(dep != null ? dep.widget : void 0)) {
          continue;
        }
        ff = dep.from_field || 'id';
        ((base = this._linkFieldsByWidgetId)[name1 = dep.widget] != null ? base[name1] : base[name1] = []).push(ff);
      }
      el = this._renderZoneOrWidget(root);
      this.container.style.cssText = 'display:flex;flex-direction:column;height:100%;';
      this.container.appendChild(el);
      // Wire depends_on after all DataView grids are ready (mount is async)
      Promise.all(this._mountPromises).then(() => {
        this._wireDepends();
        // Initial cascade: activate the first row of each root widget and
        // propagate down the depends_on chain (once per mount).
        this._initializeCascade();
        // Refresh grid layouts now that elements are in the live DOM
        setTimeout((() => {
          return this._refreshGridLayouts();
        }), 0);
        // Une tuile redimensionnée change la taille de sa grille : on rafraîchit
        // les layouts (avec anti-rebond) à chaque changement de taille.
        return this._setupResizeObserver();
      });
      // Initialiser le DragDropManager avec support des zones (Phase 3)
      // Disabled in presentation mode
      if (this.pageId && !this.presentationMode) {
        if ((ref1 = this._dragDropManager) != null) {
          if (typeof ref1.destroy === "function") {
            ref1.destroy();
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
    // `path` = indices des enfants depuis `layout` (racine) jusqu'à la zone parente ;
    // sert à réécrire le bon emplacement du YAML lors d'un glisser de séparateur.
    _renderZoneOrWidget(node, path = []) {
      var canSplit, child, childEl, childEls, children, el, i, j, k, len, len1, zone, zoneContent, zoneHeader;
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
        children = zone.children || [];
        childEls = [];
        for (i = j = 0, len = children.length; j < len; i = ++j) {
          child = children[i];
          childEls.push(this._renderZoneOrWidget(child, path.concat([i])));
        }
        // Séparateurs glissables : uniquement sur une page éditable, hors mode
        // présentation, et pas dans une zone qui a déjà sa poignée (id+factor).
        canSplit = children.length > 1 && this.pageId && !this.presentationMode;
        canSplit = canSplit && !(zone.id && zone.factor);
        for (i = k = 0, len1 = childEls.length; k < len1; i = ++k) {
          childEl = childEls[i];
          zoneContent.appendChild(childEl);
          if (canSplit && i < childEls.length - 1) {
            zoneContent.appendChild(this._createSplitter(zone.direction, childEl, childEls[i + 1], path, i));
          }
        }
        el.appendChild(zoneContent);
        // Ajouter les poignées de redimensionnement si factor est défini
        if (zone.factor) {
          this._addResizeHandle(el, zone);
        }
      }
      el.style.flex = String(_nodeFactor(node));
      return el;
    }

    // Séparateur glissable entre deux enfants consécutifs d'une zone. Le glisser
    // redistribue l'espace des DEUX voisins (minimum 80 px chacun) ; un double-clic
    // les remet à parts égales.
    _createSplitter(direction, a, b, path, index) {
      var axis, dir, dragging, horizontal, sp, startA, startB, startPos;
      horizontal = direction === 'horizontal';
      dir = horizontal ? 'horizontal' : 'vertical';
      axis = horizontal ? 'width' : 'height';
      sp = document.createElement('div');
      sp.className = `cv-splitter cv-splitter--${dir}`;
      dragging = false;
      startPos = 0;
      startA = 0;
      startB = 0;
      sp.addEventListener('mousedown', (ev) => {
        var ra, rb;
        dragging = true;
        startPos = horizontal ? ev.clientX : ev.clientY;
        ra = a.getBoundingClientRect();
        rb = b.getBoundingClientRect();
        startA = ra[axis] || 0;
        startB = rb[axis] || 0;
        document.body.style.cursor = horizontal ? 'col-resize' : 'row-resize';
        return typeof ev.preventDefault === "function" ? ev.preventDefault() : void 0;
      });
      document.addEventListener('mousemove', (ev) => {
        var na, nb, pos;
        if (!dragging) {
          return;
        }
        pos = horizontal ? ev.clientX : ev.clientY;
        [na, nb] = CustomView.redistribute(startA, startB, pos - startPos, 80);
        a.style.flex = String(na);
        return b.style.flex = String(nb);
      });
      document.addEventListener('mouseup', (ev) => {
        var fa, fb, na, nb, total;
        if (!dragging) {
          return;
        }
        dragging = false;
        document.body.style.cursor = '';
        na = parseFloat(a.style.flex);
        nb = parseFloat(b.style.flex);
        total = na + nb;
        if (total <= 0) {
          return;
        }
        fa = Math.round((2 * na / total) * 100) / 100;
        fb = Math.round((2 * nb / total) * 100) / 100;
        return this._saveChildFactors(path, [
          {
            index: index,
            factor: fa
          },
          {
            index: index + 1,
            factor: fb
          }
        ]);
      });
      sp.addEventListener('dblclick', () => {
        a.style.flex = '1';
        b.style.flex = '1';
        return this._saveChildFactors(path, [
          {
            index: index,
            factor: 1
          },
          {
            index: index + 1,
            factor: 1
          }
        ]);
      });
      return sp;
    }

    // Persiste les facteurs d'une paire de voisins dans le YAML de la page, puis
    // recharge le rendu. Réutilise la mutation existante updateCustomView.
    _saveChildFactors(path, factors) {
      var app, e, newYaml;
      if (!this.pageId) {
        return;
      }
      newYaml = null;
      try {
        newYaml = CustomView.setChildFactors(this.yamlText, path, factors);
      } catch (error1) {
        e = error1;
        return;
      }
      if (!newYaml) {
        return;
      }
      this.yamlText = newYaml;
      app = window.App;
      if (!(app && typeof GQL !== 'undefined')) {
        return;
      }
      return GQL.mutate(app._updateCustomViewMutation, {
        id: this.pageId,
        input: {
          yaml: newYaml
        }
      }).then((data) => {
        var ref;
        if ((data != null ? data.updateCustomView : void 0) != null) {
          app._currentCustomView = data.updateCustomView;
        }
        return (ref = window.AppViewHelpers) != null ? typeof ref._renderCustomViewPreview === "function" ? ref._renderCustomViewPreview(app, newYaml) : void 0 : void 0;
      }).catch(function(err) {
        if (typeof tdbAlert !== 'undefined') {
          return tdbAlert(app._err(err), 'error');
        }
      });
    }

    _renderWidget(wNode) {
      var body, col, delBtn, dv, entry, extras, f, fieldMap, filterFormula, filterInput, filterLabel, filterTimer, filterWrap, j, k, l, lang, len, len1, len2, lf, present, ref, ref1, ref2, runtimeWidgetId, sp, srcField, titleBar, titleText, visible, wrapper;
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
      // Apply column filter/order if specified. Les champs de liaison requis par
      // la chaîne depends_on (le `depends_on.field` du widget, et le `from_field`
      // de chaque widget qui dépend de lui) sont ajoutés en COPIE marquée
      // `hidden: true` : ils doivent être chargés (la requête GraphQL se construit
      // depuis sp.fields) mais pas affichés.
      if (wNode.columns && wNode.columns.length > 0) {
        fieldMap = {};
        ref = sp.fields || [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          fieldMap[f.name] = f;
        }
        sp = Object.assign({}, sp);
        visible = (function() {
          var k, len1, ref1, results;
          ref1 = wNode.columns;
          results = [];
          for (k = 0, len1 = ref1.length; k < len1; k++) {
            col = ref1[k];
            if (fieldMap[col]) {
              results.push(fieldMap[col]);
            }
          }
          return results;
        })();
        present = {};
        for (k = 0, len1 = visible.length; k < len1; k++) {
          f = visible[k];
          present[f.name] = true;
        }
        extras = [];
        ref1 = this._widgetLinkFields(wNode);
        for (l = 0, len2 = ref1.length; l < len2; l++) {
          lf = ref1[l];
          if (!(!present[lf])) {
            continue;
          }
          srcField = fieldMap[lf];
          if (!srcField) {
            console.warn(`depends_on: champ de liaison '${lf}' absent de l'espace/vue '${wNode.space}' (widget '${wNode.id}')`);
            continue;
          }
          extras.push(Object.assign({}, srcField, {
            hidden: true
          }));
          present[lf] = true;
        }
        sp.fields = visible.concat(extras);
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
      if ((ref2 = window.FieldAutocomplete) != null) {
        ref2.attach(filterInput, function() {
          return dv;
        });
      }
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

    // Liste à plat des mappings `widget` d'un arbre de layout, dans l'ordre de
    // rendu. Sert à connaître les dépendances avant de rendre les widgets.
    _collectWidgetNodes(node, out = []) {
      var child, j, len, ref, zone;
      zone = node.layout ? node.layout : node;
      if (zone.widget) {
        out.push(zone.widget);
      } else {
        ref = zone.children || [];
        for (j = 0, len = ref.length; j < len; j++) {
          child = ref[j];
          this._collectWidgetNodes(child, out);
        }
      }
      return out;
    }

    // Champs de liaison obligatoires d'un widget : son propre `depends_on.field`,
    // puis le `from_field` (défaut `id`) de chaque widget qui dépend de lui.
    // Dédoublonnés, dans cet ordre.
    _widgetLinkFields(wNode) {
      var add, ff, j, len, out, ref, ref1, ref2;
      out = [];
      add = function(name) {
        if (!name) {
          return;
        }
        if (indexOf.call(out, name) < 0) {
          return out.push(name);
        }
      };
      add((ref = wNode.depends_on) != null ? ref.field : void 0);
      ref2 = ((ref1 = this._linkFieldsByWidgetId) != null ? ref1[wNode.id] : void 0) || [];
      for (j = 0, len = ref2.length; j < len; j++) {
        ff = ref2[j];
        add(ff);
      }
      return out;
    }

    _wireDepends() {
      var dep, entry, j, len, ref, results, src;
      ref = this._widgets;
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        entry = ref[j];
        dep = entry.node.depends_on;
        if (!dep) {
          continue;
        }
        if (entry.plugin) {
          // Un widget plugin dépendant n'est pas rempli automatiquement.
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

    _applyDependencySelection(entry, dep, rowData, seen = new WeakSet()) {
      var defaults, filterVal, first, key, raw, ref, targetWidgetId;
      key = dep.from_field || 'id';
      raw = rowData != null ? rowData[key] : void 0;
      // Garde-fou : le champ de liaison est absent de la ligne source (widget
      // source dépourvu de ce champ, vue agrégée, …). Ne jamais filtrer sur la
      // chaîne "undefined" (qui laisserait tout passer) : aucun résultat.
      if (raw === void 0 || raw === null || raw === '') {
        console.warn(`depends_on: champ de liaison '${key}' absent de la ligne source du widget '${dep.widget}' (widget cible '${(ref = entry.node) != null ? ref.id : void 0}')`);
        if (entry.dataView != null) {
          entry.dataView.setDefaultValues({});
          entry.dataView.setFilter({
            field: dep.field,
            value: null,
            none: true
          });
          this._cascadeNone(entry, seen);
        }
        return;
      }
      filterVal = String(raw);
      defaults = {};
      defaults[dep.field] = filterVal;
      if (entry.dataView != null) {
        entry.dataView.setDefaultValues(defaults);
        entry.dataView.setFilter({
          field: dep.field,
          value: filterVal
        });
        // Cascade : activer la première ligne affichée de ce widget et propager à
        // ses propres dépendants, ou passer en « aucun résultat » si vide.
        seen.add(entry);
        first = this._firstRow(entry);
        if (first != null) {
          return this._selectRow(entry, first.rowKey, seen);
        } else {
          return this._cascadeNone(entry, seen);
        }
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

    // ── Sélection en cascade des widgets dépendants ─────────────────────────────

      // Entrées widgets dépendant directement de `entry` (via depends_on.widget).
    _dependentEntries(entry) {
      var depId, e, j, len, ref, ref1, ref2, ref3, results;
      depId = entry != null ? (ref = entry.node) != null ? ref.id : void 0 : void 0;
      if (!depId) {
        return [];
      }
      ref1 = this._widgets;
      results = [];
      for (j = 0, len = ref1.length; j < len; j++) {
        e = ref1[j];
        if (((ref2 = e.node) != null ? (ref3 = ref2.depends_on) != null ? ref3.widget : void 0 : void 0) === depId) {
          results.push(e);
        }
      }
      return results;
    }

    // Première ligne affichée (hors sentinelle __isNew) d'une entrée, ou null.
    _firstRow(entry) {
      var data, grid, i, j, len, ref, row;
      grid = entry != null ? (ref = entry.dataView) != null ? ref._grid : void 0 : void 0;
      if (!grid) {
        return null;
      }
      data = entry.dataView._currentData || [];
      for (i = j = 0, len = data.length; j < len; i = ++j) {
        row = data[i];
        if (row.__isNew) {
          continue;
        }
        return grid.getRowAt(i) || row;
      }
      return null;
    }

    // Marque `rowKey` active sur un widget dataView, puis propage la ligne à ses
    // dépendants (récursion). Ne vole pas le focus ni n'ouvre l'édition.
    _selectRow(entry, rowKey, seen = new WeakSet()) {
      var ref, rowData;
      if ((entry != null ? entry.dataView : void 0) == null) {
        return;
      }
      rowData = (ref = entry.dataView._grid) != null ? ref.getRow(rowKey) : void 0;
      if (!((rowData != null) && !rowData.__isNew)) {
        return;
      }
      entry.dataView.setActiveRow(rowKey);
      seen.add(entry);
      return this._cascadeToDependents(entry, rowData, seen);
    }

    // Propage `rowData` de `entry` à ses dépendants dataView. Les widgets plugin
    // dépendants ne sont pas remplis automatiquement.
    _cascadeToDependents(entry, rowData, seen = new WeakSet()) {
      var child, j, len, ref, ref1, results;
      ref = this._dependentEntries(entry);
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        child = ref[j];
        if (child.plugin) {
          continue;
        }
        if (seen.has(child)) {
          console.warn(`depends_on: cycle détecté autour du widget '${(ref1 = child.node) != null ? ref1.id : void 0}'`);
          continue;
        }
        results.push(this._applyDependencySelection(child, child.node.depends_on, rowData, seen));
      }
      return results;
    }

    // Aucune ligne disponible : les dépendants (et descendants) passent en
    // « aucun résultat », sans reliquat de l'ancienne sélection.
    _cascadeNone(entry, seen = new WeakSet()) {
      var child, j, len, ref, ref1, ref2, ref3, results;
      seen.add(entry);
      ref = this._dependentEntries(entry);
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        child = ref[j];
        if (child.plugin) {
          continue;
        }
        if (seen.has(child)) {
          console.warn(`depends_on: cycle détecté autour du widget '${(ref1 = child.node) != null ? ref1.id : void 0}'`);
          continue;
        }
        seen.add(child);
        if ((ref2 = child.dataView) != null) {
          ref2.setFilter({
            field: (ref3 = child.node.depends_on) != null ? ref3.field : void 0,
            value: null,
            none: true
          });
        }
        results.push(this._cascadeNone(child, seen));
      }
      return results;
    }

    // Au montage : chaque widget racine pourvu de dépendants active sa première
    // ligne et lance la cascade. Les widgets sans dépendants ne sont pas modifiés.
    _initializeCascade() {
      var entry, first, j, len, ref, ref1, results;
      ref = this._widgets;
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        entry = ref[j];
        if (entry.plugin) {
          continue;
        }
        if ((ref1 = entry.node) != null ? ref1.depends_on : void 0) {
          continue;
        }
        if (entry.dataView == null) {
          continue;
        }
        if (!(this._dependentEntries(entry).length > 0)) {
          continue;
        }
        first = this._firstRow(entry);
        if (first != null) {
          results.push(this._selectRow(entry, first.rowKey));
        } else {
          results.push(this._cascadeNone(entry));
        }
      }
      return results;
    }

    _findSpace(nameOrId) {
      var config, dv, fields, sp;
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
        config = _parseDataViewConfig(dv.config);
        fields = config ? _dataViewColumns(config, dv, this.allSpaces) : [];
        return {
          // Create a virtual space object for DataView class compatibility
          id: dv.id,
          name: dv.name,
          isView: true,
          viewId: dv.id,
          fields: fields
        };
      }
      return null;
    }

    unmount() {
      var entry, id, j, len, ref, ref1, ref2, ref3, st;
      ref = this._pluginStateByWidgetId;
      for (id in ref) {
        if (!hasProp.call(ref, id)) continue;
        st = ref[id];
        if (st.onMessage) {
          window.removeEventListener('message', st.onMessage);
        }
      }
      if ((ref1 = this._resizeObserver) != null) {
        if (typeof ref1.disconnect === "function") {
          ref1.disconnect();
        }
      }
      this._resizeObserver = null;
      clearTimeout(this._resizeTimer);
      ref2 = this._widgets;
      for (j = 0, len = ref2.length; j < len; j++) {
        entry = ref2[j];
        if ((ref3 = entry.dataView) != null) {
          if (typeof ref3.unmount === "function") {
            ref3.unmount();
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
