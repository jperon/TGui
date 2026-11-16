(function() {
  // app_view_helpers_add_widget.coffee — add-widget modal helpers extracted from app_view_helpers.coffee
  Object.assign(window.AppViewHelpers, {
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
      var dataSourceConfig, fieldsContainer, fieldsSection;
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
        return dataSourceConfig.appendChild(fieldsSection);
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
      var desc, input, label, name, option, safeId;
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
      var empty, i, len, list, plugin, results;
      list = document.getElementById('widget-type-plugin-list');
      if (!list) {
        return;
      }
      window.AppViewHelpers._clearWidgetTypeContainer(list);
      if (!(plugins && plugins.length > 0)) {
        empty = document.createElement('div');
        empty.className = 'widget-type-hint';
        empty.textContent = 'Aucun widget personnalisé';
        list.appendChild(empty);
        return;
      }
      results = [];
      for (i = 0, len = plugins.length; i < len; i++) {
        plugin = plugins[i];
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
      var api;
      api = window.WidgetPlugins;
      if (!(api != null ? api.list : void 0)) {
        window.AppViewHelpers._renderWidgetTypePluginsError('API WidgetPlugins indisponible');
        return Promise.resolve([]);
      }
      return api.list().then(function(plugins) {
        window.AppViewHelpers._renderWidgetTypePlugins(plugins || []);
        return plugins || [];
      }).catch(function(err) {
        console.error('load widget plugins for the add-widget modal failed', err);
        window.AppViewHelpers._renderWidgetTypePluginsError(err);
        return [];
      });
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
          var dataViewsData, ref, selectedSource, spaceId, spacesData;
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
            window.AppViewHelpers._populateFieldsLists(selectedSource);
            return window.AppViewHelpers._populateGroupByOptions(selectedSource);
          } else if (selectedSource) {
            return window.AppViewHelpers._loadSpaceFields(selectedSource, function() {
              window.AppViewHelpers._populateFieldsLists(selectedSource);
              return window.AppViewHelpers._populateGroupByOptions(selectedSource);
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
      // Sélection du type de widget : délégation sur le conteneur, car les
      // options des widgets personnalisés sont créées à chaque ouverture.
      typeOptionsRoot = document.getElementById('widget-type-options');
      if (typeOptionsRoot && !typeOptionsRoot._tdbTypeBound) {
        typeOptionsRoot._tdbTypeBound = true;
        typeOptionsRoot.addEventListener('click', function(ev) {
          var option, ref;
          option = (ref = ev.target) != null ? typeof ref.closest === "function" ? ref.closest('.widget-type-option') : void 0 : void 0;
          if (!option) {
            return;
          }
          return window.AppViewHelpers._selectWidgetType(option);
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
      return errors;
    },
    _collectWidgetData: function() {
      var field, fields, i, j, keyInput, len, len1, paramRow, paramRows, params, selectedFields, selectedType, spaceSelect, titleInput, valueInput;
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
      // Collecter les paramètres
      params = {};
      for (j = 0, len1 = paramRows.length; j < len1; j++) {
        paramRow = paramRows[j];
        keyInput = paramRow.querySelector('.param-key');
        valueInput = paramRow.querySelector('.param-value');
        if (keyInput && valueInput && keyInput.value.trim()) {
          params[keyInput.value.trim()] = valueInput.value.trim();
        }
      }
      return {
        title: titleInput.value.trim(),
        spaceId: spaceSelect.value,
        type: (selectedType != null ? selectedType.value : void 0) || 'table',
        fields: fields,
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
