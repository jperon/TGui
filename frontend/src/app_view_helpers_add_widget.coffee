# app_view_helpers_add_widget.coffee — add-widget modal helpers extracted from app_view_helpers.coffee
Object.assign window.AppViewHelpers,
  _openAddWidgetModal: (app) ->
    cv = app._currentCustomView
    return unless cv

    # Afficher la modale
    app.el.addWidgetModal().classList.remove 'hidden'

    # Corriger le HTML manquant dynamiquement
    window.AppViewHelpers._fixModalHTML()

    # Initialiser la modale avec les fonctions de base
    window.AppViewHelpers._initializeWidgetModal app

  _fixModalHTML: ->
    # Ajouter les sections manquantes si elles n'existent pas
    dataSourceConfig = document.querySelector '.data-source-config'
    return unless dataSourceConfig

    # Vérifier si les sections manquent
    fieldsContainer = document.getElementById 'widget-fields-container'

    unless fieldsContainer
      # Créer la section des champs
      fieldsSection = document.createElement 'div'
      fieldsSection.className = 'config-row'
      fieldsSection.innerHTML = '''
        <label>Colonnes à afficher:</label>
        <div id="widget-fields-container" class="fields-container">
          <div class="fields-header">
            <div class="field-group">Disponibles:</div>
            <div class="field-group">Sélectionnées:</div>
          </div>
          <div class="fields-lists">
            <div id="available-fields" class="fields-list"> </div>
            <div id="selected-fields" class="fields-list selected"> </div>
          </div>
        </div>
      '''
      dataSourceConfig.appendChild fieldsSection

  # Vide un conteneur : innerHTML (navigateur) et tableaux d'enfants (stub DOM
  # des tests JS, où innerHTML ne vide rien).
  _clearWidgetTypeContainer: (container) ->
    container.innerHTML = ''
    container._children.length = 0 if Array.isArray container._children
    container.children.length = 0 if Array.isArray container.children

  # Un admin peut ouvrir l'éditeur de plugins depuis la fenêtre « ＋ Widget ».
  # Information absente du frontend (Auth non chargé) → on laisse le lien
  # visible : le serveur refuse de toute façon.
  _canEditWidgetPlugins: ->
    return true unless window.Auth?.isAdmin
    window.Auth.isAdmin()

  # Option de type correspondant à un widget personnalisé (plugin). La valeur
  # du radio est le NOM du plugin : c'est ce que `_renderWidget` attend dans
  # `type` du nœud YAML.
  _makeWidgetTypePluginOption: (plugin) ->
    name = plugin.name
    option = document.createElement 'div'
    option.className = 'widget-type-option widget-type-option--plugin'
    option.title = plugin.description or name
    option.dataset.pluginName = name

    safeId = String(name).replace /[^a-zA-Z0-9_-]/g, '-'
    input = document.createElement 'input'
    input.type = 'radio'
    input.name = 'widget-type'
    input.value = name
    input.id = "widget-type-plugin-#{safeId}"

    label = document.createElement 'label'
    label.setAttribute 'for', input.id
    label.textContent = name

    if plugin.description
      desc = document.createElement 'span'
      desc.className = 'widget-type-option-desc'
      desc.textContent = plugin.description
      label.appendChild desc

    option.appendChild input
    option.appendChild label
    option

  _renderWidgetTypePlugins: (plugins) ->
    list = document.getElementById 'widget-type-plugin-list'
    return unless list
    window.AppViewHelpers._clearWidgetTypeContainer list

    unless plugins and plugins.length > 0
      empty = document.createElement 'div'
      empty.className = 'widget-type-hint'
      empty.textContent = 'Aucun widget personnalisé'
      list.appendChild empty
      return

    for plugin in plugins when plugin?.name
      list.appendChild window.AppViewHelpers._makeWidgetTypePluginOption plugin

  # Échec de chargement : message visible dans la fenêtre, jamais avalé.
  _renderWidgetTypePluginsError: (err) ->
    list = document.getElementById 'widget-type-plugin-list'
    return unless list
    window.AppViewHelpers._clearWidgetTypeContainer list
    message = document.createElement 'div'
    message.className = 'widget-type-hint widget-type-hint--error'
    message.textContent = "Erreur de chargement des widgets personnalisés : #{err?.message or err}"
    list.appendChild message

  _reloadWidgetTypePlugins: (app) ->
    api = window.WidgetPlugins
    unless api?.list
      window.AppViewHelpers._renderWidgetTypePluginsError 'API WidgetPlugins indisponible'
      return Promise.resolve []
    api.list()
      .then (plugins) ->
        window.AppViewHelpers._renderWidgetTypePlugins plugins or []
        plugins or []
      .catch (err) ->
        console.error 'load widget plugins for the add-widget modal failed', err
        window.AppViewHelpers._renderWidgetTypePluginsError err
        []

  # Sélection d'un type : une seule option marquée, radio coché. Appelée par
  # délégation, les options de plugins étant créées après le montage.
  _selectWidgetType: (option) ->
    return unless option
    scope = document.getElementById('widget-type-options') or option.parentNode
    for el in (scope?.querySelectorAll?('.widget-type-option') or [])
      el.classList.remove 'selected'
    option.classList.add 'selected'
    radio = option.querySelector 'input[type="radio"]'
    radio.checked = true if radio
    return option

  _populateSpaceSelect: (select, spaces, dataViews) ->
    console.log 'Populating space select with:', { spaces: spaces?.length, dataViews: dataViews?.length }

    # Vider le select
    select.innerHTML = '<option value="">Sélectionner une source...</option>'

    # Ajouter les espaces
    if spaces and Array.isArray(spaces) and spaces.length > 0
      spacesGroup = document.createElement 'optgroup'
      spacesGroup.label = 'Espaces (Tables)'
      for space in spaces
        option = document.createElement 'option'
        option.value = space.id
        option.textContent = space.name
        spacesGroup.appendChild option
      select.appendChild spacesGroup
      console.log "Added #{spaces.length} spaces"

    # Ajouter les vues
    if dataViews and Array.isArray(dataViews) and dataViews.length > 0
      viewsGroup = document.createElement 'optgroup'
      viewsGroup.label = 'Vues (Requêtes)'
      for view in dataViews
        option = document.createElement 'option'
        option.value = view.id
        option.dataset.isView = 'true'
        option.textContent = view.name
        viewsGroup.appendChild option
      select.appendChild viewsGroup
      console.log "Added #{dataViews.length} data views"

  _initializeWidgetModal: (app) ->
    console.log '_initializeWidgetModal called'

    # Forcer le token de test pour l'environnement de test
    unless window.GQL._token
      console.log 'Setting test token for widget modal...'
      window.GQL.setToken 'GRh5Nvb+qcRmGImY/yd/WhV+57IDoMBg/KSp+eQnK7I='

    # Charger les espaces disponibles
    window.AppViewHelpers._loadAvailableSources app

    # Remplir le groupe « Widgets personnalisés » (définitions courantes)
    window.AppViewHelpers._reloadWidgetTypePlugins app

    # Lier les événements de base
    window.AppViewHelpers._bindBasicWidgetEvents app

    # Charger la liste des espaces et des Data Views
    Promise.all([window.Spaces.list(), window.DataViews.list()])
      .then ([spaces, dataViews]) ->
        console.log 'spaces and dataViews loaded:', spaces, dataViews
        console.log 'spaces type:', typeof spaces, 'dataViews type:', typeof dataViews
        console.log 'spaces length:', spaces?.length, 'dataViews length:', dataViews?.length

        select = document.getElementById 'widget-space-select'
        return unless select

        select.innerHTML = '<option value="">Sélectionner une source...</option>'

        # Si pas authentifié, utiliser le token de test
        unless window.GQL._token
          console.log 'No token found, setting test token...'
          window.GQL.setToken 'GRh5Nvb+qcRmGImY/yd/WhV+57IDoMBg/KSp+eQnK7I='

          # Re-tenter avec le token
          Promise.all([window.Spaces.list(), window.DataViews.list()])
            .then ([spacesRetry, dataViewsRetry]) ->
              console.log 'Retry - spaces and dataViews loaded:', spacesRetry, dataViewsRetry
              window.AppViewHelpers._populateSpaceSelect select, spacesRetry, dataViewsRetry
            .catch (err) ->
              console.error 'Retry failed:', err
              window.AppViewHelpers._populateSpaceSelect select, [], []
          return

        # Vérifier si spaces est un tableau valide
        if spaces and Array.isArray(spaces) and spaces.length > 0
          window.AppViewHelpers._populateSpaceSelect select, spaces, dataViews
        else
          console.warn 'No valid spaces array found:', spaces

        # Stocker les données pour utilisation ultérieure
        app._spacesData = spaces
        app._dataViewsData = dataViews
        window._currentSpacesData = spaces
        window._currentDataViewsData = dataViews

        # Écouter les changements pour charger les champs
        select.addEventListener 'change', ->
          spaceId = @value
          return unless spaceId

          # Trouver la source correspondante
          spacesData = window._currentSpacesData or []
          dataViewsData = window._currentDataViewsData or []
          selectedSource = spacesData.find((s) -> s.id == spaceId) or dataViewsData.find((v) -> v.id == spaceId)

          if selectedSource?.config? # C'est une Data View (elle a une config)
            selectedSource.isView = true
            # Simuler l'objet space pour peupler les champs
            selectedSource.fields = selectedSource.config.columns?.map (c) -> { name: c, fieldType: 'String' }
            window.AppViewHelpers._populateFieldsLists selectedSource
            window.AppViewHelpers._populateGroupByOptions selectedSource
          else if selectedSource
            window.AppViewHelpers._loadSpaceFields selectedSource, ->
              window.AppViewHelpers._populateFieldsLists selectedSource
              window.AppViewHelpers._populateGroupByOptions selectedSource

  _loadSpaceFields: (space, callback) ->
    # Charger les champs d'un espace spécifique
    query = """
      query GetSpaceFields($spaceId: ID!) {
        space(id: $spaceId) {
          id name
          fields {
            id name fieldType notNull position description formula triggerFields language reprFormula
          }
        }
      }
    """
    window.GQL.query(query, {spaceId: space.id}).then (result) ->
      if result.space and result.space.fields
        space.fields = result.space.fields
        console.log 'fields loaded for space:', space.name, space.fields
      callback()
    .catch (error) ->
      console.error 'Error loading fields:', error
      # En cas d'erreur, continuer sans champs
      callback()

  _loadAvailableSources: (app) ->
    # Cette fonction est un wrapper pour charger les sources
    # Le vrai chargement se fait dans _initializeWidgetModal
    console.log '_loadAvailableSources called (wrapper function)'

  _toggleFieldSelection: (fieldItem) ->
    isSelected = fieldItem.classList.contains 'selected'
    availableContainer = document.getElementById 'available-fields'
    selectedContainer = document.getElementById 'selected-fields'

    if isSelected
      # Retirer de la sélection
      fieldItem.classList.remove 'selected'
      availableContainer.appendChild fieldItem
    else
      # Ajouter à la sélection
      fieldItem.classList.add 'selected'
      selectedContainer.appendChild fieldItem

  _populateFieldsLists: (space) ->
    console.log 'populateFieldsLists called with space:', space
    availableContainer = document.getElementById 'available-fields'
    selectedContainer = document.getElementById 'selected-fields'

    return unless availableContainer and selectedContainer and space

    console.log 'space fields:', space.fields

    # Vider les conteneurs
    availableContainer.innerHTML = ''
    selectedContainer.innerHTML = ''

    # Si pas de champs, afficher un message
    unless space.fields
      availableContainer.innerHTML = '<div class="field-item">Cet espace n\'a pas de champs configurés</div>'
      return

    # Ajouter les champs disponibles
    for field in space.fields or []
      console.log 'creating field item for:', field
      fieldItem = document.createElement 'div'
      fieldItem.className = 'field-item'
      fieldItem.textContent = "#{field.name} (#{field.fieldType})"
      fieldItem.dataset.fieldName = field.name
      fieldItem.dataset.fieldType = field.fieldType

      fieldItem.addEventListener 'click', ->
        window.AppViewHelpers._toggleFieldSelection @

      availableContainer.appendChild fieldItem

  _bindBasicWidgetEvents: (app) ->
    # Rouvrir la fenêtre repart du type par défaut (« Tableau simple »).
    tableRadio = document.getElementById 'widget-type-table'
    if tableRadio
      tableRadio.checked = true
      window.AppViewHelpers._selectWidgetType tableRadio.parentNode if tableRadio.parentNode

    # Sélection du type de widget : délégation sur le conteneur, car les
    # options des widgets personnalisés sont créées à chaque ouverture.
    typeOptionsRoot = document.getElementById 'widget-type-options'

    if typeOptionsRoot and not typeOptionsRoot._tdbTypeBound
      typeOptionsRoot._tdbTypeBound = true
      typeOptionsRoot.addEventListener 'click', (ev) ->
        option = ev.target?.closest? '.widget-type-option'
        return unless option
        window.AppViewHelpers._selectWidgetType option

    # Lien vers l'éditeur de plugins (admin uniquement, si l'info est connue).
    newPluginBtn = document.getElementById 'widget-type-new-plugin'
    if newPluginBtn
      if window.AppViewHelpers._canEditWidgetPlugins()
        newPluginBtn.classList.remove 'hidden'
        unless newPluginBtn._tdbBound
          newPluginBtn._tdbBound = true
          newPluginBtn.addEventListener 'click', (ev) ->
            ev.preventDefault?()
            app.el.addWidgetModal()?.classList.add 'hidden'
            window.AppViewHelpers.openWidgetPluginModal app
      else
        newPluginBtn.classList.add 'hidden'

    # Gérer les boutons de la modale
    confirmBtn = document.getElementById 'add-widget-confirm-btn'
    cancelBtn = document.getElementById 'add-widget-cancel-btn'

    if confirmBtn
      confirmBtn.addEventListener 'click', ->
        window.AppViewHelpers._submitWidget app

    if cancelBtn
      cancelBtn.addEventListener 'click', ->
        window.AppViewHelpers._closeWidgetModal app

    # Gérer les paramètres
    window.AppViewHelpers._bindParamsManagement app

  _bindParamsManagement: (app) ->
    addBtn = document.getElementById 'add-param-btn'
    paramsList = document.getElementById 'widget-params-list'

    return unless addBtn and paramsList

    addBtn.addEventListener 'click', ->
      window.AppViewHelpers._addParamRow paramsList

    # Gérer les boutons de suppression existants
    window.AppViewHelpers._bindParamRemoval paramsList

  _addParamRow: (paramsList) ->
    paramRow = document.createElement 'div'
    paramRow.className = 'param-row'
    paramRow.innerHTML = '''
      <input type="text" placeholder="Clé" class="param-key">
      <input type="text" placeholder="Valeur" class="param-value">
      <button type="button" class="param-remove-btn">✕</button>
    '''

    paramsList.appendChild paramRow
    window.AppViewHelpers._bindParamRemoval paramsList

  _bindParamRemoval: (paramsList) ->
    removeBtns = paramsList.querySelectorAll '.param-remove-btn'

    for btn in removeBtns
      # Éviter les doublons d'event listeners
      btn.removeEventListener 'click', arguments.callee
      btn.addEventListener 'click', ->
        @parentElement.remove()

  _validateWidgetForm: ->
    titleInput = document.getElementById 'widget-title-input'
    spaceSelect = document.getElementById 'widget-space-select'
    selectedFields = document.querySelectorAll '#selected-fields .field-item'
    selectedType = document.querySelector 'input[name="widget-type"]:checked'
    type = selectedType?.value or 'table'

    errors = []

    # Valider le titre
    unless titleInput and titleInput.value.trim()
      errors.push 'Le titre du widget est requis'

    # Valider l'espace
    unless spaceSelect and spaceSelect.value
      errors.push 'La sélection d\'un espace est requise'

    # Colonnes obligatoires pour le tableau simple seulement : un widget
    # personnalisé (plugin) lit ses données lui-même (spec §3 bis).
    if type == 'table' and selectedFields.length == 0
      errors.push 'Au moins un champ doit être sélectionné'

    return errors

  _collectWidgetData: ->
    titleInput = document.getElementById 'widget-title-input'
    spaceSelect = document.getElementById 'widget-space-select'
    selectedType = document.querySelector 'input[name="widget-type"]:checked'
    selectedFields = document.querySelectorAll '#selected-fields .field-item'
    paramRows = document.querySelectorAll '#widget-params-list .param-row'

    # Collecter les champs sélectionnés
    fields = []
    for field in selectedFields
      fields.push field.dataset.fieldName or field.textContent

    # Collecter les paramètres
    params = {}
    for paramRow in paramRows
      keyInput = paramRow.querySelector '.param-key'
      valueInput = paramRow.querySelector '.param-value'

      if keyInput and valueInput and keyInput.value.trim()
        params[keyInput.value.trim()] = valueInput.value.trim()

    return {
      title: titleInput.value.trim()
      spaceId: spaceSelect.value
      type: selectedType?.value or 'table'
      fields: fields
      params: params
    }

  # Identifiant de la page ouverte : celui de la vue personnalisée courante,
  # sinon celui du hash (`#page/<id>` pour une page, `#view/<id>` pour une data
  # view). L'ancienne version ne reconnaissait que `view/` et refusait donc tout
  # ajout de widget depuis une page.
  _resolveAddWidgetViewId: (app, hash) ->
    return app._currentCustomView.id if app?._currentCustomView?.id
    h = hash or ''
    return m[1] if m = h.match /^#page\/([^\/?#]+)/
    return m[1] if m = h.match /^#view\/([^\/?#]+)/
    null

  _submitWidget: (app) ->
    # Valider le formulaire
    errors = window.AppViewHelpers._validateWidgetForm()

    if errors.length > 0
      tdbAlert 'Erreurs de validation:\n' + errors.join('\n'), 'error'
      return

    # Collecter les données
    widgetData = window.AppViewHelpers._collectWidgetData()

    # Page ouverte (hash #page/… ou #view/…)
    viewId = window.AppViewHelpers._resolveAddWidgetViewId app, window.location.hash

    unless viewId
      tdbAlert 'Erreur: impossible de déterminer l\'ID de la vue actuelle', 'error'
      return

    # Préparer la mutation GraphQL
    mutation = '''
      mutation AddWidgetToView($viewId: ID!, $widget: WidgetInput!) {
        addWidgetToView(viewId: $viewId, widget: $widget) {
          id
          name
          yaml
        }
      }
    '''

    # Préparer les variables
    variables = {
      viewId: viewId
      widget: {
        title: widgetData.title
        type: widgetData.type
        spaceId: widgetData.spaceId
        fields: widgetData.fields
        groupBy: widgetData.groupBy
        params: widgetData.params
        position: {
          x: 0
          y: 0
          w: 6
          h: 4
        }
      }
    }

    # Exécuter la mutation
    window.GQL.mutate(mutation, variables)
      .then (result) ->
        if result.errors
          console.error 'GraphQL errors:', result.errors
          tdbAlert 'Erreur lors de la création du widget: ' + result.errors[0].message, 'error'
        else
          console.log 'Widget créé avec succès:', result.addWidgetToView
          window.AppViewHelpers._closeWidgetModal app
          # Rafraîchir la vue pour afficher le nouveau widget
          window.AppViewHelpers._renderCustomViewPreview app, result.addWidgetToView.yaml
      .catch (error) ->
        console.error 'Network error:', error
        tdbAlert 'Erreur réseau lors de la création du widget: ' + error.message, 'error'

  _bindAddWidgetModal: (app) ->
    # Bouton de confirmation
    app.el.addWidgetConfirmBtn().addEventListener 'click', ->
      window.AppViewHelpers._confirmAddWidget app

    # Bouton d'annulation
    app.el.addWidgetCancelBtn().addEventListener 'click', ->
      window.AppViewHelpers._closeAddWidgetModal app

