(function() {
  // app_view_helpers_add_widget.coffee — add-widget modal helpers extracted from app_view_helpers.coffee
  Object.assign(window.AppViewHelpers, {
    // État de la fenêtre (définitions connues, manifest et mappage du type
    // choisi). Déclaré ici pour que les appels internes aient une définition
    // visible, même si ce ne sont pas des fonctions.
    _widgetPluginsByName: {},
    _currentWidgetManifest: null,
    _currentWidgetColumns: null,
    _openAddWidgetModal: function(app) {
      var cv;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      // Afficher la modale
      app.el.addWidgetModal().classList.remove('hidden');
      // Corriger le HTML manquant dynamiquement
      window.AppViewHelpers._fixModalHTML();
      // Initialiser la modale avec les fonctions de base
      return window.AppViewHelpers._initializeWidgetModal(app);
    },
    _fixModalHTML: function() {
      var dataSourceConfig, fieldsContainer, fieldsSection, manifestForm, paramsConfig;
      // Ajouter les sections manquantes si elles n'existent pas
      dataSourceConfig = document.querySelector('.data-source-config');
      if (!dataSourceConfig) {
        return;
      }
      // Vérifier si les sections manquent
      fieldsContainer = document.getElementById('widget-fields-container');
      if (!fieldsContainer) {
        // Créer la section des champs
        fieldsSection = document.createElement('div');
        fieldsSection.className = 'config-row';
        fieldsSection.innerHTML = `<label>Colonnes à afficher:</label>
<div id="widget-fields-container" class="fields-container">
  <div class="fields-header">
    <div class="field-group">Disponibles:</div>
    <div class="field-group">Sélectionnées:</div>
  </div>
  <div class="fields-lists">
    <div id="available-fields" class="fields-list"> </div>
    <div id="selected-fields" class="fields-list selected"> </div>
  </div>
</div>`;
        dataSourceConfig.appendChild(fieldsSection);
      }
      // Formulaire de manifest (widgets personnalisés) : conteneur des paires et
      // conteneur du formulaire déclaré, si le HTML servi est ancien.
      paramsConfig = document.querySelector('.widget-params-config');
      if (paramsConfig && !document.getElementById('widget-manifest-form')) {
        manifestForm = document.createElement('div');
        manifestForm.id = 'widget-manifest-form';
        manifestForm.className = 'widget-manifest-form hidden';
        return paramsConfig.appendChild(manifestForm);
      }
    },
    // Vide un conteneur : innerHTML (navigateur) et tableaux d'enfants (stub DOM
    // des tests JS, où innerHTML ne vide rien).
    _clearWidgetTypeContainer: function(container) {
      container.innerHTML = '';
      if (Array.isArray(container._children)) {
        container._children.length = 0;
      }
      if (Array.isArray(container.children)) {
        return container.children.length = 0;
      }
    },
    // Un admin peut ouvrir l'éditeur de plugins depuis la fenêtre « ＋ Widget ».
    // Information absente du frontend (Auth non chargé) → on laisse le lien
    // visible : le serveur refuse de toute façon.
    _canEditWidgetPlugins: function() {
      var ref;
      if (!((ref = window.Auth) != null ? ref.isAdmin : void 0)) {
        return true;
      }
      return window.Auth.isAdmin();
    },
    // Option de type correspondant à un widget personnalisé (plugin). La valeur
    // du radio est le NOM du plugin : c'est ce que `_renderWidget` attend dans
    // `type` du nœud YAML.
    _makeWidgetTypePluginOption: function(plugin) {
      var desc, input, label, name, option, ref, safeId, scope, scopeEl;
      name = plugin.name;
      option = document.createElement('div');
      option.className = 'widget-type-option widget-type-option--plugin';
      option.title = plugin.description || name;
      option.dataset.pluginName = name;
      safeId = String(name).replace(/[^a-zA-Z0-9_-]/g, '-');
      input = document.createElement('input');
      input.type = 'radio';
      input.name = 'widget-type';
      input.value = name;
      input.id = `widget-type-plugin-${safeId}`;
      label = document.createElement('label');
      label.setAttribute('for', input.id);
      label.textContent = name;
      // Portée de la définition (spec widgets personnalisés §5) : la page voit la
      // définition de son app en priorité, puis celle de la bibliothèque.
      scope = (ref = window.WidgetPlugins) != null ? typeof ref.scopeLabel === "function" ? ref.scopeLabel(plugin) : void 0 : void 0;
      if (scope) {
        scopeEl = document.createElement('span');
        scopeEl.className = 'widget-type-option-scope';
        scopeEl.textContent = ` (${scope})`;
        label.appendChild(scopeEl);
      }
      if (plugin.description) {
        desc = document.createElement('span');
        desc.className = 'widget-type-option-desc';
        desc.textContent = plugin.description;
        label.appendChild(desc);
      }
      option.appendChild(input);
      option.appendChild(label);
      return option;
    },
    _renderWidgetTypePlugins: function(plugins) {
      var empty, i, j, len, len1, list, plugin, ref, results;
      list = document.getElementById('widget-type-plugin-list');
      if (!list) {
        return;
      }
      window.AppViewHelpers._clearWidgetTypeContainer(list);
      // Définitions courantes, indexées par nom : la fenêtre en tire le manifest
      // (colonnes déclarées, options, access) quand l'utilisateur choisit le type.
      window.AppViewHelpers._widgetPluginsByName = {};
      ref = plugins || [];
      for (i = 0, len = ref.length; i < len; i++) {
        plugin = ref[i];
        if (plugin != null ? plugin.name : void 0) {
          window.AppViewHelpers._widgetPluginsByName[plugin.name] = plugin;
        }
      }
      if (!(plugins && plugins.length > 0)) {
        empty = document.createElement('div');
        empty.className = 'widget-type-hint';
        empty.textContent = 'Aucun widget personnalisé';
        list.appendChild(empty);
        return;
      }
      results = [];
      for (j = 0, len1 = plugins.length; j < len1; j++) {
        plugin = plugins[j];
        if (plugin != null ? plugin.name : void 0) {
          results.push(list.appendChild(window.AppViewHelpers._makeWidgetTypePluginOption(plugin)));
        }
      }
      return results;
    },
    // Échec de chargement : message visible dans la fenêtre, jamais avalé.
    _renderWidgetTypePluginsError: function(err) {
      var list, message;
      list = document.getElementById('widget-type-plugin-list');
      if (!list) {
        return;
      }
      window.AppViewHelpers._clearWidgetTypeContainer(list);
      message = document.createElement('div');
      message.className = 'widget-type-hint widget-type-hint--error';
      message.textContent = `Erreur de chargement des widgets personnalisés : ${(err != null ? err.message : void 0) || err}`;
      return list.appendChild(message);
    },
    _reloadWidgetTypePlugins: function(app) {
      var api, pageId;
      api = window.WidgetPlugins;
      if (!(api != null ? api.list : void 0)) {
        window.AppViewHelpers._renderWidgetTypePluginsError('API WidgetPlugins indisponible');
        return Promise.resolve([]);
      }
      // Les définitions listées sont celles que voit la page ouverte : sa portée
      // d'abord, puis la bibliothèque.
      pageId = window.AppViewHelpers._resolveAddWidgetViewId(app, window.location.hash);
      return api.list(pageId ? {pageId} : {}).then(function(plugins) {
        window.AppViewHelpers._renderWidgetTypePlugins(plugins || []);
        return plugins || [];
      }).catch(function(err) {
        console.error('load widget plugins for the add-widget modal failed', err);
        window.AppViewHelpers._renderWidgetTypePluginsError(err);
        return [];
      });
    },
    // ── Formulaire tiré du manifest (spec §3 bis) ─────────────────────────────
    // Manifest analysé côté fenêtre. Le serveur l'a validé à l'enregistrement ;
    // un manifest illisible (import direct) est ignoré : paires clé/valeur, comme
    // avant. Une définition sans manifest garde le formulaire libre.
    _parseWidgetManifest: function(text) {
      var e, parsed, parser;
      if (!(text && String(text).trim() !== '')) {
        return null;
      }
      parser = window.jsyaml;
      if (!(parser && typeof parser.load === 'function')) {
        return null;
      }
      try {
        parsed = parser.load(String(text));
      } catch (error1) {
        e = error1;
        console.warn('widget manifest: YAML invalide', e);
        return null;
      }
      if (!(parsed && typeof parsed === 'object')) {
        return null;
      }
      return {
        access: parsed.access,
        columns: Array.isArray(parsed.columns) ? parsed.columns : [],
        options: Array.isArray(parsed.options) ? parsed.options : []
      };
    },
    _manifestTypeKind: function(type) {
      var t;
      t = String(type || '').toLowerCase();
      if (t === 'date' || t === 'datetime') {
        return 'date';
      }
      if (t === 'int' || t === 'float' || t === 'number' || t === 'decimal') {
        return 'number';
      }
      if (t === 'boolean') {
        return 'boolean';
      }
      if (t === 'string' || t === 'id' || t === 'uuid' || t === 'sequence') {
        return 'string';
      }
      return 'any';
    },
    // Type compatible pour un sélecteur de colonne : type déclaré identique,
    // `Any` (ou type de champ inconnu), ou même famille (Date/Datetime,
    // Int/Float, String/ID/UUID/Sequence).
    _manifestFieldCompatible: function(declaredType, field) {
      var actual, actualKind, declared, declaredKind;
      declared = String(declaredType || '');
      actual = String((field != null ? field.fieldType : void 0) || '');
      if (declared === '' || actual === '') {
        return true;
      }
      if (declared.toLowerCase() === actual.toLowerCase()) {
        return true;
      }
      if (actual.toLowerCase() === 'any') {
        return true;
      }
      declaredKind = window.AppViewHelpers._manifestTypeKind(declared);
      actualKind = window.AppViewHelpers._manifestTypeKind(actual);
      if (declaredKind === 'any') {
        return true;
      }
      return declaredKind === actualKind;
    },
    // Champs de la source choisie dans la fenêtre (espace ou Data View).
    _fieldsForSourceId: function(spaceId) {
      var ref, space, spaces, view, views;
      if (!spaceId) {
        return [];
      }
      spaces = window._currentSpacesData || [];
      views = window._currentDataViewsData || [];
      space = spaces.find(function(s) {
        return s.id === spaceId;
      });
      if (space) {
        return space.fields || [];
      }
      view = views.find(function(v) {
        return v.id === spaceId;
      });
      if (!view) {
        return [];
      }
      return view.fields || (((ref = view.config) != null ? ref.columns : void 0) || []).map(function(c) {
        return {
          name: c,
          fieldType: 'String'
        };
      });
    },
    _clearWidgetManifestForm: function() {
      var form;
      form = document.getElementById('widget-manifest-form');
      if (!form) {
        return;
      }
      window.AppViewHelpers._clearWidgetTypeContainer(form);
      return form;
    },
    // Rend le formulaire du manifest : un sélecteur de champ par colonne déclarée
    // (filtré par type, « — » pour une optionnelle) et un champ par option, avec
    // la valeur par défaut. Aucun manifest : on ne touche pas aux paires.
    _renderWidgetManifestForm: function(manifest) {
      var col, empty, fields, form, hint, i, j, len, len1, opt, ref, ref1, spaceSelect;
      form = window.AppViewHelpers._clearWidgetManifestForm();
      if (!form) {
        return;
      }
      hint = document.getElementById('widget-manifest-hint');
      if (hint != null) {
        hint.classList.add('hidden');
      }
      spaceSelect = document.getElementById('widget-space-select');
      fields = window.AppViewHelpers._fieldsForSourceId(spaceSelect != null ? spaceSelect.value : void 0);
      ref = manifest.columns || [];
      for (i = 0, len = ref.length; i < len; i++) {
        col = ref[i];
        if (col && col.name) {
          form.appendChild(window.AppViewHelpers._makeManifestColumnRow(col, fields));
        }
      }
      ref1 = manifest.options || [];
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        opt = ref1[j];
        if (opt && opt.name) {
          form.appendChild(window.AppViewHelpers._makeManifestOptionRow(opt));
        }
      }
      if ((manifest.columns || []).length === 0 && (manifest.options || []).length === 0) {
        empty = document.createElement('div');
        empty.className = 'widget-type-hint';
        empty.textContent = 'Ce manifest ne déclare ni colonne ni option.';
        form.appendChild(empty);
      }
      return form;
    },
    _makeManifestColumnRow: function(col, fields) {
      var field, i, label, len, mapping, none, opt, ref, row, select;
      row = document.createElement('div');
      row.className = 'manifest-form-row';
      label = document.createElement('label');
      label.textContent = `${col.name} (${col.type || 'Any'})`;
      if (col.optional !== true) {
        label.textContent += ' *';
      }
      select = document.createElement('select');
      select.className = 'manifest-column-select';
      select.dataset.declared = col.name;
      select.dataset.required = col.optional === true ? '0' : '1';
      none = document.createElement('option');
      none.value = '';
      none.textContent = '—';
      select.appendChild(none);
      mapping = window.AppViewHelpers._currentWidgetColumns || {};
      ref = fields || [];
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        if (!(field != null ? field.name : void 0)) {
          continue;
        }
        if (!window.AppViewHelpers._manifestFieldCompatible(col.type, field)) {
          continue;
        }
        opt = document.createElement('option');
        opt.value = field.name;
        opt.textContent = `${field.name} (${field.fieldType || 'String'})`;
        select.appendChild(opt);
      }
      select.value = mapping[col.name] || '';
      row.appendChild(label);
      row.appendChild(select);
      return row;
    },
    _makeManifestOptionRow: function(opt) {
      var input, label, row, type;
      row = document.createElement('div');
      row.className = 'manifest-form-row';
      label = document.createElement('label');
      label.textContent = opt.name;
      row.appendChild(label);
      type = String(opt.type || 'text').toLowerCase();
      input = document.createElement('input');
      input.dataset.option = opt.name;
      input.dataset.optionType = type;
      switch (type) {
        case 'color':
          input.type = 'color';
          input.value = opt.default ? String(opt.default) : '#000000';
          break;
        case 'number':
          input.type = 'number';
          input.value = opt.default != null ? String(opt.default) : '';
          break;
        case 'boolean':
          input.type = 'checkbox';
          input.checked = opt.default === true;
          break;
        default:
          input.type = 'text';
          input.value = opt.default != null ? String(opt.default) : '';
      }
      row.appendChild(input);
      return row;
    },
    // Choix du type : un plugin avec manifest remplace les paires clé/valeur par
    // le formulaire déclaré. `pluginName` vide (ou « table ») = paires.
    _updateWidgetParamsForm: function(pluginName) {
      var form, hint, manifest, pairs, plugin, ref;
      plugin = (ref = window.AppViewHelpers._widgetPluginsByName) != null ? ref[pluginName] : void 0;
      manifest = plugin ? window.AppViewHelpers._parseWidgetManifest(plugin.manifest) : null;
      window.AppViewHelpers._currentWidgetManifest = manifest;
      window.AppViewHelpers._currentWidgetColumns = null;
      form = document.getElementById('widget-manifest-form');
      pairs = document.getElementById('widget-params-pairs');
      hint = document.getElementById('widget-manifest-hint');
      if (!form) {
        return manifest;
      }
      if (manifest) {
        if (pairs != null) {
          pairs.classList.add('hidden');
        }
        form.classList.remove('hidden');
        window.AppViewHelpers._renderWidgetManifestForm(manifest);
        if (hint != null) {
          hint.classList.add('hidden');
        }
      } else {
        form.classList.add('hidden');
        if (pairs != null) {
          pairs.classList.remove('hidden');
        }
        window.AppViewHelpers._clearWidgetTypeContainer(form);
        if (hint != null) {
          hint.classList.add('hidden');
        }
      }
      return manifest;
    },
    // Le changement de source change les champs proposés : on redessine les
    // sélecteurs du manifest. Les valeurs déjà choisies sont conservées.
    _refreshWidgetManifestForm: function() {
      var form, i, len, manifest, ref, ref1, ref2, sel, selected;
      manifest = window.AppViewHelpers._currentWidgetManifest;
      if (!manifest) {
        return;
      }
      form = document.getElementById('widget-manifest-form');
      if (!form) {
        return;
      }
      selected = {};
      ref = document.querySelectorAll('#widget-manifest-form .manifest-column-select' || []);
      for (i = 0, len = ref.length; i < len; i++) {
        sel = ref[i];
        if ((ref1 = sel.dataset) != null ? ref1.declared : void 0) {
          selected[(ref2 = sel.dataset) != null ? ref2.declared : void 0] = sel.value;
        }
      }
      window.AppViewHelpers._currentWidgetColumns = selected;
      return window.AppViewHelpers._renderWidgetManifestForm(manifest);
    },
    // Sélection d'un type : une seule option marquée, radio coché. Appelée par
    // délégation, les options de plugins étant créées après le montage.
    _selectWidgetType: function(option) {
      var el, i, len, radio, ref, scope;
      if (!option) {
        return;
      }
      scope = document.getElementById('widget-type-options') || option.parentNode;
      ref = (scope != null ? typeof scope.querySelectorAll === "function" ? scope.querySelectorAll('.widget-type-option') : void 0 : void 0) || [];
      for (i = 0, len = ref.length; i < len; i++) {
        el = ref[i];
        el.classList.remove('selected');
      }
      option.classList.add('selected');
      radio = option.querySelector('input[type="radio"]');
      if (radio) {
        radio.checked = true;
      }
      return option;
    },
    _populateSpaceSelect: function(select, spaces, dataViews) {
      var i, j, len, len1, option, space, spacesGroup, view, viewsGroup;
      console.log('Populating space select with:', {
        spaces: spaces != null ? spaces.length : void 0,
        dataViews: dataViews != null ? dataViews.length : void 0
      });
      // Vider le select
      select.innerHTML = '<option value="">Sélectionner une source...</option>';
      // Ajouter les espaces
      if (spaces && Array.isArray(spaces) && spaces.length > 0) {
        spacesGroup = document.createElement('optgroup');
        spacesGroup.label = 'Espaces (Tables)';
        for (i = 0, len = spaces.length; i < len; i++) {
          space = spaces[i];
          option = document.createElement('option');
          option.value = space.id;
          option.textContent = space.name;
          spacesGroup.appendChild(option);
        }
        select.appendChild(spacesGroup);
        console.log(`Added ${spaces.length} spaces`);
      }
      // Ajouter les vues
      if (dataViews && Array.isArray(dataViews) && dataViews.length > 0) {
        viewsGroup = document.createElement('optgroup');
        viewsGroup.label = 'Vues (Requêtes)';
        for (j = 0, len1 = dataViews.length; j < len1; j++) {
          view = dataViews[j];
          option = document.createElement('option');
          option.value = view.id;
          option.dataset.isView = 'true';
          option.textContent = view.name;
          viewsGroup.appendChild(option);
        }
        select.appendChild(viewsGroup);
        return console.log(`Added ${dataViews.length} data views`);
      }
    },
    _initializeWidgetModal: function(app) {
      console.log('_initializeWidgetModal called');
      // Forcer le token de test pour l'environnement de test
      if (!window.GQL._token) {
        console.log('Setting test token for widget modal...');
        window.GQL.setToken('GRh5Nvb+qcRmGImY/yd/WhV+57IDoMBg/KSp+eQnK7I=');
      }
      // Charger les espaces disponibles
      window.AppViewHelpers._loadAvailableSources(app);
      // Remplir le groupe « Widgets personnalisés » (définitions courantes)
      window.AppViewHelpers._reloadWidgetTypePlugins(app);
      // Lier les événements de base
      window.AppViewHelpers._bindBasicWidgetEvents(app);
      // Charger la liste des espaces et des Data Views
      return Promise.all([window.Spaces.list(), window.DataViews.list()]).then(function([spaces, dataViews]) {
        var select;
        console.log('spaces and dataViews loaded:', spaces, dataViews);
        console.log('spaces type:', typeof spaces, 'dataViews type:', typeof dataViews);
        console.log('spaces length:', spaces != null ? spaces.length : void 0, 'dataViews length:', dataViews != null ? dataViews.length : void 0);
        select = document.getElementById('widget-space-select');
        if (!select) {
          return;
        }
        select.innerHTML = '<option value="">Sélectionner une source...</option>';
        // Si pas authentifié, utiliser le token de test
        if (!window.GQL._token) {
          console.log('No token found, setting test token...');
          window.GQL.setToken('GRh5Nvb+qcRmGImY/yd/WhV+57IDoMBg/KSp+eQnK7I=');
          // Re-tenter avec le token
          Promise.all([window.Spaces.list(), window.DataViews.list()]).then(function([spacesRetry, dataViewsRetry]) {
            console.log('Retry - spaces and dataViews loaded:', spacesRetry, dataViewsRetry);
            return window.AppViewHelpers._populateSpaceSelect(select, spacesRetry, dataViewsRetry);
          }).catch(function(err) {
            console.error('Retry failed:', err);
            return window.AppViewHelpers._populateSpaceSelect(select, [], []);
          });
          return;
        }
        // Vérifier si spaces est un tableau valide
        if (spaces && Array.isArray(spaces) && spaces.length > 0) {
          window.AppViewHelpers._populateSpaceSelect(select, spaces, dataViews);
        } else {
          console.warn('No valid spaces array found:', spaces);
        }
        // Stocker les données pour utilisation ultérieure
        app._spacesData = spaces;
        app._dataViewsData = dataViews;
        window._currentSpacesData = spaces;
        window._currentDataViewsData = dataViews;
        // Écouter les changements pour charger les champs
        return select.addEventListener('change', function() {
          var base, base1, dataViewsData, ref, selectedSource, spaceId, spacesData;
          spaceId = this.value;
          if (!spaceId) {
            return;
          }
          // Trouver la source correspondante
          spacesData = window._currentSpacesData || [];
          dataViewsData = window._currentDataViewsData || [];
          selectedSource = spacesData.find(function(s) {
            return s.id === spaceId;
          }) || dataViewsData.find(function(v) {
            return v.id === spaceId;
          });
          if ((selectedSource != null ? selectedSource.config : void 0) != null) {
            selectedSource.isView = true;
            // Simuler l'objet space pour peupler les champs
            selectedSource.fields = (ref = selectedSource.config.columns) != null ? ref.map(function(c) {
              return {
                name: c,
                fieldType: 'String'
              };
            }) : void 0;
            // Les sélecteurs du manifest dépendent des champs de la source.
            window.AppViewHelpers._refreshWidgetManifestForm();
            if (typeof (base = window.AppViewHelpers)._populateFieldsLists === "function") {
              base._populateFieldsLists(selectedSource);
            }
            return typeof (base1 = window.AppViewHelpers)._populateGroupByOptions === "function" ? base1._populateGroupByOptions(selectedSource) : void 0;
          } else if (selectedSource) {
            return window.AppViewHelpers._loadSpaceFields(selectedSource, function() {
              var base2, base3;
              window.AppViewHelpers._refreshWidgetManifestForm();
              if (typeof (base2 = window.AppViewHelpers)._populateFieldsLists === "function") {
                base2._populateFieldsLists(selectedSource);
              }
              return typeof (base3 = window.AppViewHelpers)._populateGroupByOptions === "function" ? base3._populateGroupByOptions(selectedSource) : void 0;
            }); // C'est une Data View (elle a une config)
          }
        });
      });
    },
    _loadSpaceFields: function(space, callback) {
      var query;
      // Charger les champs d'un espace spécifique
      query = `query GetSpaceFields($spaceId: ID!) {
  space(id: $spaceId) {
    id name
    fields {
      id name fieldType notNull position description formula triggerFields language reprFormula
    }
  }
}`;
      return window.GQL.query(query, {
        spaceId: space.id
      }).then(function(result) {
        if (result.space && result.space.fields) {
          space.fields = result.space.fields;
          console.log('fields loaded for space:', space.name, space.fields);
        }
        return callback();
      }).catch(function(error) {
        console.error('Error loading fields:', error);
        // En cas d'erreur, continuer sans champs
        return callback();
      });
    },
    _loadAvailableSources: function(app) {
      // Cette fonction est un wrapper pour charger les sources
      // Le vrai chargement se fait dans _initializeWidgetModal
      return console.log('_loadAvailableSources called (wrapper function)');
    },
    _toggleFieldSelection: function(fieldItem) {
      var availableContainer, isSelected, selectedContainer;
      isSelected = fieldItem.classList.contains('selected');
      availableContainer = document.getElementById('available-fields');
      selectedContainer = document.getElementById('selected-fields');
      if (isSelected) {
        // Retirer de la sélection
        fieldItem.classList.remove('selected');
        return availableContainer.appendChild(fieldItem);
      } else {
        // Ajouter à la sélection
        fieldItem.classList.add('selected');
        return selectedContainer.appendChild(fieldItem);
      }
    },
    _populateFieldsLists: function(space) {
      var availableContainer, field, fieldItem, i, len, ref, results, selectedContainer;
      console.log('populateFieldsLists called with space:', space);
      availableContainer = document.getElementById('available-fields');
      selectedContainer = document.getElementById('selected-fields');
      if (!(availableContainer && selectedContainer && space)) {
        return;
      }
      console.log('space fields:', space.fields);
      // Vider les conteneurs
      availableContainer.innerHTML = '';
      selectedContainer.innerHTML = '';
      // Si pas de champs, afficher un message
      if (!space.fields) {
        availableContainer.innerHTML = '<div class="field-item">Cet espace n\'a pas de champs configurés</div>';
        return;
      }
      ref = space.fields || [];
      // Ajouter les champs disponibles
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        console.log('creating field item for:', field);
        fieldItem = document.createElement('div');
        fieldItem.className = 'field-item';
        fieldItem.textContent = `${field.name} (${field.fieldType})`;
        fieldItem.dataset.fieldName = field.name;
        fieldItem.dataset.fieldType = field.fieldType;
        fieldItem.addEventListener('click', function() {
          return window.AppViewHelpers._toggleFieldSelection(this);
        });
        results.push(availableContainer.appendChild(fieldItem));
      }
      return results;
    },
    _bindBasicWidgetEvents: function(app) {
      var cancelBtn, confirmBtn, newPluginBtn, tableRadio, typeOptionsRoot;
      // Rouvrir la fenêtre repart du type par défaut (« Tableau simple »).
      tableRadio = document.getElementById('widget-type-table');
      if (tableRadio) {
        tableRadio.checked = true;
        if (tableRadio.parentNode) {
          window.AppViewHelpers._selectWidgetType(tableRadio.parentNode);
        }
      }
      // ... et donc du formulaire de paramètres par défaut (paires clé/valeur).
      window.AppViewHelpers._updateWidgetParamsForm('table');
      // Sélection du type de widget : délégation sur le conteneur, car les
      // options des widgets personnalisés sont créées à chaque ouverture.
      typeOptionsRoot = document.getElementById('widget-type-options');
      if (typeOptionsRoot && !typeOptionsRoot._tdbTypeBound) {
        typeOptionsRoot._tdbTypeBound = true;
        typeOptionsRoot.addEventListener('click', function(ev) {
          var option, pluginName, ref, ref1, ref2;
          option = (ref = ev.target) != null ? typeof ref.closest === "function" ? ref.closest('.widget-type-option') : void 0 : void 0;
          if (!option) {
            return;
          }
          window.AppViewHelpers._selectWidgetType(option);
          pluginName = (ref1 = option.dataset) != null ? ref1.pluginName : void 0;
          if (pluginName == null) {
            pluginName = typeof option.querySelector === "function" ? (ref2 = option.querySelector('input[type="radio"]')) != null ? ref2.value : void 0 : void 0;
          }
          return window.AppViewHelpers._updateWidgetParamsForm(pluginName);
        });
      }
      // Lien vers l'éditeur de plugins (admin uniquement, si l'info est connue).
      newPluginBtn = document.getElementById('widget-type-new-plugin');
      if (newPluginBtn) {
        if (window.AppViewHelpers._canEditWidgetPlugins()) {
          newPluginBtn.classList.remove('hidden');
          if (!newPluginBtn._tdbBound) {
            newPluginBtn._tdbBound = true;
            newPluginBtn.addEventListener('click', function(ev) {
              var ref;
              if (typeof ev.preventDefault === "function") {
                ev.preventDefault();
              }
              if ((ref = app.el.addWidgetModal()) != null) {
                ref.classList.add('hidden');
              }
              return window.AppViewHelpers.openWidgetPluginModal(app);
            });
          }
        } else {
          newPluginBtn.classList.add('hidden');
        }
      }
      // Gérer les boutons de la modale
      confirmBtn = document.getElementById('add-widget-confirm-btn');
      cancelBtn = document.getElementById('add-widget-cancel-btn');
      if (confirmBtn) {
        confirmBtn.addEventListener('click', function() {
          return window.AppViewHelpers._submitWidget(app);
        });
      }
      if (cancelBtn) {
        cancelBtn.addEventListener('click', function() {
          return window.AppViewHelpers._closeWidgetModal(app);
        });
      }
      // Gérer les paramètres
      return window.AppViewHelpers._bindParamsManagement(app);
    },
    _bindParamsManagement: function(app) {
      var addBtn, paramsList;
      addBtn = document.getElementById('add-param-btn');
      paramsList = document.getElementById('widget-params-list');
      if (!(addBtn && paramsList)) {
        return;
      }
      addBtn.addEventListener('click', function() {
        return window.AppViewHelpers._addParamRow(paramsList);
      });
      // Gérer les boutons de suppression existants
      return window.AppViewHelpers._bindParamRemoval(paramsList);
    },
    _addParamRow: function(paramsList) {
      var paramRow;
      paramRow = document.createElement('div');
      paramRow.className = 'param-row';
      paramRow.innerHTML = `<input type="text" placeholder="Clé" class="param-key">
<input type="text" placeholder="Valeur" class="param-value">
<button type="button" class="param-remove-btn">✕</button>`;
      paramsList.appendChild(paramRow);
      return window.AppViewHelpers._bindParamRemoval(paramsList);
    },
    _bindParamRemoval: function(paramsList) {
      var btn, i, len, removeBtns, results;
      removeBtns = paramsList.querySelectorAll('.param-remove-btn');
      results = [];
      for (i = 0, len = removeBtns.length; i < len; i++) {
        btn = removeBtns[i];
        // Éviter les doublons d'event listeners
        btn.removeEventListener('click', arguments.callee);
        results.push(btn.addEventListener('click', function() {
          return this.parentElement.remove();
        }));
      }
      return results;
    },
    // Colonnes obligatoires du manifest : chaque `<select>` doit avoir un champ.
    _validateWidgetManifestForm: function() {
      var declared, errors, i, len, ref, ref1, ref2, sel;
      errors = [];
      ref = document.querySelectorAll('#widget-manifest-form .manifest-column-select' || []);
      for (i = 0, len = ref.length; i < len; i++) {
        sel = ref[i];
        declared = (ref1 = sel.dataset) != null ? ref1.declared : void 0;
        if (!declared) {
          continue;
        }
        if (((ref2 = sel.dataset) != null ? ref2.required : void 0) !== '1') {
          continue;
        }
        if (sel.value) {
          continue;
        }
        errors.push(`Colonne obligatoire non mappée : ${declared}`);
      }
      return errors;
    },
    _collectWidgetManifestData: function() {
      var columns, declared, i, input, j, len, len1, name, params, ref, ref1, ref2, ref3, ref4, sel, type;
      columns = {};
      ref = document.querySelectorAll('#widget-manifest-form .manifest-column-select' || []);
      for (i = 0, len = ref.length; i < len; i++) {
        sel = ref[i];
        declared = (ref1 = sel.dataset) != null ? ref1.declared : void 0;
        if (!(declared && sel.value)) {
          continue;
        }
        columns[declared] = sel.value;
      }
      params = {};
      ref2 = document.querySelectorAll('#widget-manifest-form [data-option]' || []);
      for (j = 0, len1 = ref2.length; j < len1; j++) {
        input = ref2[j];
        name = (ref3 = input.dataset) != null ? ref3.option : void 0;
        if (!name) {
          continue;
        }
        type = String(((ref4 = input.dataset) != null ? ref4.optionType : void 0) || 'text');
        params[name] = (function() {
          switch (type) {
            case 'boolean':
              return input.checked === true;
            case 'number':
              if (input.value === '' || input.value === null) {
                return '';
              } else {
                return Number(input.value);
              }
              break;
            default:
              return String(input.value || '');
          }
        })();
      }
      return {columns, params};
    },
    _validateWidgetForm: function() {
      var errors, selectedFields, selectedType, spaceSelect, titleInput, type;
      titleInput = document.getElementById('widget-title-input');
      spaceSelect = document.getElementById('widget-space-select');
      selectedFields = document.querySelectorAll('#selected-fields .field-item');
      selectedType = document.querySelector('input[name="widget-type"]:checked');
      type = (selectedType != null ? selectedType.value : void 0) || 'table';
      errors = [];
      // Valider le titre
      if (!(titleInput && titleInput.value.trim())) {
        errors.push('Le titre du widget est requis');
      }
      // Valider l'espace
      if (!(spaceSelect && spaceSelect.value)) {
        errors.push('La sélection d\'un espace est requise');
      }
      // Colonnes obligatoires pour le tableau simple seulement : un widget
      // personnalisé (plugin) lit ses données lui-même (spec §3 bis).
      if (type === 'table' && selectedFields.length === 0) {
        errors.push('Au moins un champ doit être sélectionné');
      }
      // Widget personnalisé avec manifest : ses colonnes obligatoires doivent
      // être mappées sur un champ de la source.
      if (window.AppViewHelpers._currentWidgetManifest) {
        errors = errors.concat(window.AppViewHelpers._validateWidgetManifestForm());
      }
      return errors;
    },
    _collectWidgetData: function() {
      var field, fields, i, j, keyInput, len, len1, manifestData, paramRow, paramRows, params, selectedFields, selectedType, spaceSelect, titleInput, valueInput;
      titleInput = document.getElementById('widget-title-input');
      spaceSelect = document.getElementById('widget-space-select');
      selectedType = document.querySelector('input[name="widget-type"]:checked');
      selectedFields = document.querySelectorAll('#selected-fields .field-item');
      paramRows = document.querySelectorAll('#widget-params-list .param-row');
      // Collecter les champs sélectionnés
      fields = [];
      for (i = 0, len = selectedFields.length; i < len; i++) {
        field = selectedFields[i];
        fields.push(field.dataset.fieldName || field.textContent);
      }
      // Widget personnalisé avec manifest : mappage déclaré → champ + options.
      manifestData = null;
      if (window.AppViewHelpers._currentWidgetManifest) {
        manifestData = window.AppViewHelpers._collectWidgetManifestData();
      }
      // Collecter les paramètres (paires clé/valeur, ou options du manifest)
      params = manifestData ? manifestData.params : {};
      if (!manifestData) {
        for (j = 0, len1 = paramRows.length; j < len1; j++) {
          paramRow = paramRows[j];
          keyInput = paramRow.querySelector('.param-key');
          valueInput = paramRow.querySelector('.param-value');
          if (keyInput && valueInput && keyInput.value.trim()) {
            params[keyInput.value.trim()] = valueInput.value.trim();
          }
        }
      }
      return {
        title: titleInput.value.trim(),
        spaceId: spaceSelect.value,
        type: (selectedType != null ? selectedType.value : void 0) || 'table',
        fields: fields,
        columns: manifestData != null ? manifestData.columns : void 0,
        params: params
      };
    },
    // Identifiant de la page ouverte : celui de la vue personnalisée courante,
    // sinon celui du hash (`#page/<id>` pour une page, `#view/<id>` pour une data
    // view). L'ancienne version ne reconnaissait que `view/` et refusait donc tout
    // ajout de widget depuis une page.
    _resolveAddWidgetViewId: function(app, hash) {
      var h, m, ref;
      if (app != null ? (ref = app._currentCustomView) != null ? ref.id : void 0 : void 0) {
        return app._currentCustomView.id;
      }
      h = hash || '';
      if (m = h.match(/^#page\/([^\/?#]+)/)) {
        return m[1];
      }
      if (m = h.match(/^#view\/([^\/?#]+)/)) {
        return m[1];
      }
      return null;
    },
    _submitWidget: function(app) {
      var errors, mutation, variables, viewId, widgetData;
      // Valider le formulaire
      errors = window.AppViewHelpers._validateWidgetForm();
      if (errors.length > 0) {
        tdbAlert('Erreurs de validation:\n' + errors.join('\n'), 'error');
        return;
      }
      // Collecter les données
      widgetData = window.AppViewHelpers._collectWidgetData();
      // Page ouverte (hash #page/… ou #view/…)
      viewId = window.AppViewHelpers._resolveAddWidgetViewId(app, window.location.hash);
      if (!viewId) {
        tdbAlert('Erreur: impossible de déterminer l\'ID de la vue actuelle', 'error');
        return;
      }
      // Préparer la mutation GraphQL
      mutation = `mutation AddWidgetToView($viewId: ID!, $widget: WidgetInput!) {
  addWidgetToView(viewId: $viewId, widget: $widget) {
    id
    name
    yaml
  }
}`;
      // Préparer les variables
      variables = {
        viewId: viewId,
        widget: {
          title: widgetData.title,
          type: widgetData.type,
          spaceId: widgetData.spaceId,
          fields: widgetData.fields,
          columns: widgetData.columns,
          groupBy: widgetData.groupBy,
          params: widgetData.params,
          position: {
            x: 0,
            y: 0,
            w: 6,
            h: 4
          }
        }
      };
      // Exécuter la mutation
      return window.GQL.mutate(mutation, variables).then(function(result) {
        if (result.errors) {
          console.error('GraphQL errors:', result.errors);
          return tdbAlert('Erreur lors de la création du widget: ' + result.errors[0].message, 'error');
        } else {
          console.log('Widget créé avec succès:', result.addWidgetToView);
          window.AppViewHelpers._closeWidgetModal(app);
          // Rafraîchir la vue pour afficher le nouveau widget
          return window.AppViewHelpers._renderCustomViewPreview(app, result.addWidgetToView.yaml);
        }
      }).catch(function(error) {
        console.error('Network error:', error);
        return tdbAlert('Erreur réseau lors de la création du widget: ' + error.message, 'error');
      });
    },
    _bindAddWidgetModal: function(app) {
      // Bouton de confirmation
      app.el.addWidgetConfirmBtn().addEventListener('click', function() {
        return window.AppViewHelpers._confirmAddWidget(app);
      });
      // Bouton d'annulation
      return app.el.addWidgetCancelBtn().addEventListener('click', function() {
        return window.AppViewHelpers._closeAddWidgetModal(app);
      });
    }
  });

}).call(this);
