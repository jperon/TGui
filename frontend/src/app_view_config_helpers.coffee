# app_view_config_helpers.coffee — Data View configuration modal logic

window.AppViewConfigHelpers =
  _currentViewId: null

  bindDataViewModal: (app) ->
    app.el.dataViewModalCloseBtn().addEventListener 'click', =>
      app.el.dataViewModal().classList.add 'hidden'

    app.el.dataViewSaveBtn().addEventListener 'click', =>
      @saveDataView app

    # YAML Editor buttons
    app.el.dvFormatYamlBtn().addEventListener 'click', =>
      @formatYaml app

    app.el.dvApplyYamlBtn().addEventListener 'click', =>
      @applyYamlToVisual app

    # Tabs logic
    tabs = app.el.dataViewModal().querySelectorAll '.tab-btn'
    tabs.forEach (btn) ->
      btn.addEventListener 'click', ->
        tabs.forEach (b) -> b.classList.remove 'active'
        btn.classList.add 'active'
        target = btn.dataset.tab
        ['fields', 'filter', 'group'].forEach (t) ->
          document.getElementById("dv-tab-#{t}").classList.toggle 'hidden', t != target

    # Note: dv-add-col-btn removed - now using field selection interface
    app.el.dvAddAggBtn().addEventListener 'click', =>
      @_addAggregateRow app

    # YAML editor change detection
    app.el.dvYamlContent().addEventListener 'input', =>
      @markYamlAsChanged app

  openDataViewConfigModal: (app, view = null) ->
    @_currentViewId = view?.id or null
    app.el.dataViewModalTitle().textContent = if view then "Modifier la vue : #{view.name}" else "Nouvelle vue"
    app.el.dvName().value = view?.name or ''

    # Populate source select
    select = app.el.dvSource()
    select.innerHTML = '<option value="">Sélectionner un espace...</option>'
    for sp in (app._allSpaces or [])
      option = document.createElement 'option'
      option.value = sp.id
      option.textContent = sp.name
      option.selected = sp.id == view?.sourceSpace
      select.appendChild option

    # Reset dynamic lists
    @resetDataViewFields app
    app.el.dvAggregatesList().innerHTML = ''
    app.el.dvFilterFormula().value = view?.config?.filter?.formula or ''

    # Initialize YAML editor
    @initializeYamlEditor app, view

    # Initialize fields tab with ERD graph
    @initializeFieldsTab app

    # Load existing data
    if view?.config?.columns
      @loadExistingColumns app, view.config.columns
    else if not view
      @resetDataViewFields app # Start with empty fields for new view

    if view?.config?.aggregates
      for agg in view.config.aggregates
        @_addAggregateRow app, agg.field, agg.func, agg.alias

    # Setup field selection when source changes
    app.el.dvSource().addEventListener 'change', =>
      @loadSourceFields app
      # Reinitialize fields graph with new source
      @initializeFieldsGraph app

    # Load initial fields if source is selected
    if view?.sourceSpace
      @loadSourceFields app, view.sourceSpace

    app.el.dataViewModal().classList.remove 'hidden'

  _addColumnRow: (app, name = '', label = '') ->
    container = app.el.dvColumnsList()
    row = document.createElement 'div'
    row.className = 'dv-row'

    inputName = document.createElement 'input'
    inputName.type = 'text'
    inputName.placeholder = 'Nom du champ (ex: name)'
    inputName.value = name
    inputName.className = 'dv-col-name'

    inputLabel = document.createElement 'input'
    inputLabel.type = 'text'
    inputLabel.placeholder = 'Libellé (ex: Nom)'
    inputLabel.value = label
    inputLabel.className = 'dv-col-label'

    removeBtn = document.createElement 'button'
    removeBtn.className = 'remove-btn'
    removeBtn.textContent = '🗑'
    removeBtn.onclick = -> row.remove()

    row.appendChild inputName
    row.appendChild inputLabel
    row.appendChild removeBtn
    container.appendChild row

  _addAggregateRow: (app, field = '', func = 'SUM', alias = '') ->
    container = app.el.dvAggregatesList()
    row = document.createElement 'div'
    row.className = 'dv-row'

    inputField = document.createElement 'input'
    inputField.type = 'text'
    inputField.placeholder = 'Champ'
    inputField.value = field
    inputField.className = 'dv-agg-field'

    selectFunc = document.createElement 'select'
    selectFunc.className = 'dv-agg-func'
    ['SUM', 'AVG', 'COUNT', 'MIN', 'MAX'].forEach (f) ->
      opt = document.createElement 'option'
      opt.value = f
      opt.textContent = f
      opt.selected = f == func
      selectFunc.appendChild opt

    inputAlias = document.createElement 'input'
    inputAlias.type = 'text'
    inputAlias.placeholder = 'Alias'
    inputAlias.value = alias
    inputAlias.className = 'dv-agg-alias'

    removeBtn = document.createElement 'button'
    removeBtn.className = 'remove-btn'
    removeBtn.textContent = '🗑'
    removeBtn.onclick = -> row.remove()

    row.appendChild inputField
    row.appendChild selectFunc
    row.appendChild inputAlias
    row.appendChild removeBtn
    container.appendChild row

  saveDataView: (app) ->
    name = app.el.dvName().value.trim()
    sourceSpace = app.el.dvSource().value
    unless name and sourceSpace
      return tdbAlert "Le nom et l'espace source sont obligatoires", 'error'

    # Gather columns from new unified interface
    columns = []
    selectedContainer = document.getElementById 'dv-selected-fields'
    if selectedContainer
      selectedContainer.querySelectorAll('.selected-field-item').forEach (fieldItem) ->
        columns.push {
          name: fieldItem.dataset.fieldName
          label: fieldItem.dataset.fieldName
          spaceId: fieldItem.dataset.spaceId
        }

    # Gather groupBy from new interface
    groupBy = []
    groupByContainer = document.getElementById 'dv-groupby-selected'
    if groupByContainer
      groupByContainer.querySelectorAll('.field-item').forEach (fieldItem) ->
        groupBy.push fieldItem.dataset.fieldName

    # Gather aggregates
    aggregates = []
    app.el.dvAggregatesList().querySelectorAll('.dv-row').forEach (row) ->
      aField = row.querySelector('.dv-agg-field').value.trim()
      aFunc = row.querySelector('.dv-agg-func').value
      aAlias = row.querySelector('.dv-agg-alias').value.trim()
      if aField
        aggregates.push { field: aField, func: aFunc, alias: aAlias or "#{aFunc.toLowerCase()}_#{aField}" }

    filterFormula = app.el.dvFilterFormula().value.trim()
    filter = if filterFormula then { formula: filterFormula, language: 'moonscript' } else { formula: '', language: 'moonscript' }

    # Gather selected joins
    joins = []
    selectedRelations = @_joinsYamlBuilder?.getSelectedRelations() or []
    for relation in selectedRelations
      joins.push {
        fromSpace: relation.fromSpaceId
        toSpace: relation.toSpaceId
        fromField: relation.fromFieldId
        toField: relation.toFieldId
        relationType: relation.type or 'foreign_key'
      }

    config = {
      columns: if columns.length > 0 then columns else []
      filter: filter or { formula: '', language: 'moonscript' }
      groupBy: if groupBy.length > 0 then groupBy else []
      aggregates: if aggregates.length > 0 then aggregates else []
      joins: if joins.length > 0 then joins else []
    }

    input = {
      name: name
      sourceSpace: sourceSpace
      config: JSON.stringify config
    }

    console.log('Data view creation/update input:', input)
    promise = if @_currentViewId
      DataViews.update(@_currentViewId, input)
    else
      DataViews.create(input)

    promise.then (view) =>
      app.el.dataViewModal().classList.add 'hidden'
      app.loadDataViews().then =>
        app.selectDataView view
    .catch (err) ->
      console.error('Data view creation/update error:', err)
      tdbAlert app._err(err), 'error'

  # Nouvelles fonctions pour l'interface unifiée de champs et jointures
  resetDataViewFields: (app) ->
    selectedContainer = document.getElementById 'dv-selected-fields'

    if selectedContainer
      selectedContainer.innerHTML = '<div class="field-placeholder">Aucun champ sélectionné</div>'

  loadSourceFields: (app, spaceId = null) ->
    spaceId = app.el.dvSource().value unless spaceId
    return unless spaceId

    # Find space data
    space = (app._allSpaces or []).find (sp) -> sp.id == spaceId
    return unless space

    # Initialize YamlBuilder with field selection integration
    @initializeFieldsGraph app, spaceId

  initializeFieldsTab: (app) ->
    # Initialize fields tab with placeholder
    joinsContainer = document.getElementById 'dv-joins-graph-container'
    selectedContainer = document.getElementById 'dv-selected-fields'

    if joinsContainer
      joinsContainer.innerHTML = '<div class="joins-placeholder">Sélectionnez un espace source pour voir les relations...</div>'
    if selectedContainer
      selectedContainer.innerHTML = '<div class="field-placeholder">Aucun champ sélectionné</div>'

  initializeFieldsGraph: (app, spaceId) ->
    joinsContainer = document.getElementById 'dv-joins-graph-container'
    return unless joinsContainer and spaceId

    # Load all relations and initialize YamlBuilder
    window.AppViewHelpers.loadAllRelations(app).then (relations) =>
      # Create a YamlBuilder for field selection and automatic joins
      @_fieldsYamlBuilder = new YamlBuilder
        container: joinsContainer
        allSpaces: app._allSpaces
        allRelations: relations
        onChange: (yaml) => # Handle field selection changes
          @updateSelectedFields app
        mode: 'field-selection' # Special mode for field selection
        focusSpaceId: spaceId # Focus on the source space
        onFieldClick: (fieldInfo) => # Handle field clicks
          @toggleFieldSelection app, fieldInfo

      @_fieldsYamlBuilder.mount()

      # Store current space for reference
      @_currentSourceSpaceId = spaceId

      console.log 'Fields graph initialized for space:', spaceId

  toggleFieldSelection: (app, fieldInfo) ->
    selectedContainer = document.getElementById 'dv-selected-fields'
    return unless selectedContainer

    # Check if field is already selected
    existingField = selectedContainer.querySelector "[data-field-id='#{fieldInfo.id}']"

    if existingField
      # Remove field from selection
      existingField.remove()
      console.log 'Field removed from selection:', fieldInfo.name
    else
      # Add field to selection
      fieldItem = document.createElement 'div'
      fieldItem.className = 'selected-field-item'
      fieldItem.dataset.fieldId = fieldInfo.id
      fieldItem.dataset.spaceId = fieldInfo.spaceId
      fieldItem.dataset.fieldName = fieldInfo.name
      fieldItem.dataset.fieldType = fieldInfo.type

      info = document.createElement 'div'
      info.className = 'field-info'
      strong = document.createElement 'strong'
      strong.textContent = String(fieldInfo.spaceName ? '')
      info.appendChild strong
      info.appendChild document.createTextNode(".#{fieldInfo.name ? ''}")
      info.appendChild document.createElement 'br'
      small = document.createElement 'small'
      small.textContent = "Type: #{fieldInfo.type ? ''}"
      info.appendChild small
      fieldItem.appendChild info

      removeBtn = document.createElement 'button'
      removeBtn.className = 'remove-field-btn'
      removeBtn.setAttribute 'data-field-id', fieldInfo.id
      removeBtn.textContent = '✕'
      removeBtn.addEventListener 'click', =>
        @toggleFieldSelection app, fieldInfo
      fieldItem.appendChild removeBtn

      selectedContainer.appendChild fieldItem
      console.log 'Field added to selection:', fieldInfo.name

  updateSelectedFields: (app) ->
    # This will be called when YamlBuilder detects changes
    # For now, the field selection is handled by toggleFieldSelection
    console.log 'Field selection updated'

  loadExistingColumns: (app, columns) ->
    selectedContainer = document.getElementById 'dv-selected-fields'
    return unless selectedContainer

    # Load existing columns as selected fields
    for col in columns
      # Find the corresponding field in all spaces
      fieldInfo = @findFieldInfo app, col.name
      if fieldInfo
        @toggleFieldSelection app, fieldInfo

  findFieldInfo: (app, fieldName) ->
    # Search through all spaces to find field info
    for space in (app._allSpaces or [])
      for field in space.fields or []
        if field.name == fieldName
          return {
            id: field.id
            name: field.name
            type: field.fieldType
            spaceId: space.id
            spaceName: space.name
          }
    return null

  # ── Fields Tab Functions ─────────────────────────────────────────────────────
  initializeFieldsTab: (app) ->
    # Initialize the ERD graph container
    @initializeFieldsGraph app

  initializeFieldsGraph: (app) ->
    container = document.getElementById 'dv-joins-graph-container'
    return unless container

    # Check if YamlBuilder is available
    if typeof window.YamlBuilder == 'undefined'
      container.innerHTML = '<div class="joins-placeholder">YamlBuilder non disponible</div>'
      return

    # Initialize YamlBuilder for field selection
    try
      @_fieldsYamlBuilder = new YamlBuilder container, {
        mode: 'field-selection'
        onFieldClick: (fieldData) =>
          @toggleFieldSelection app, fieldData
        onRelationClick: (relationData) =>
          @handleRelationClick app, relationData
      }

      # Load relations if source is selected
      sourceId = app.el.dvSource().value
      if sourceId
        @loadRelationsForSpace app, sourceId
      else
        container.innerHTML = '<div class="joins-placeholder">Sélectionnez un espace source pour voir les relations...</div>'
    catch error
      console.error 'Error initializing fields graph:', error
      container.innerHTML = '<div class="joins-placeholder">Erreur lors du chargement du graphe</div>'

  loadRelationsForSpace: (app, spaceId) ->
    return unless @_fieldsYamlBuilder

    # Load all relations for the selected space
    window.GQL.query """
      query {
        spaces {
          id
          name
          fields {
            id
            name
            fieldType
          }
          relations {
            id
            name
            sourceSpace {
              id
              name
            }
            targetSpace {
              id
              name
            }
            sourceField {
              id
              name
            }
            targetField {
              id
              name
            }
          }
        }
      }
    """, (data) =>
      if data?.spaces
        @_fieldsYamlBuilder.loadRelations data.spaces
        console.log "Fields graph initialized for space: #{spaceId}"
      else
        console.error 'Failed to load relations'

  toggleFieldSelection: (app, fieldData) ->
    selectedContainer = document.getElementById 'dv-selected-fields'
    return unless selectedContainer

    # Check if field is already selected
    existingItem = selectedContainer.querySelector "[data-field-id=\"#{fieldData.id}\"]"
    if existingItem
      # Remove field from selection
      existingItem.remove()
    else
      # Add field to selection
      fieldItem = document.createElement 'div'
      fieldItem.className = 'selected-field-item'
      fieldItem.dataset.fieldId = fieldData.id
      fieldItem.dataset.fieldName = fieldData.name
      fieldItem.dataset.spaceId = fieldData.spaceId
      fieldItem.dataset.spaceName = fieldData.spaceName
      fieldItem.dataset.fieldType = fieldData.type

      info = document.createElement 'div'
      info.className = 'field-info'
      strong = document.createElement 'strong'
      strong.textContent = String(fieldData.name ? '')
      info.appendChild strong
      small = document.createElement 'small'
      small.textContent = "#{fieldData.spaceName ? ''}.#{fieldData.name ? ''} (#{fieldData.type ? ''})"
      info.appendChild small
      fieldItem.appendChild info

      removeBtn = document.createElement 'button'
      removeBtn.className = 'remove-field-btn'
      removeBtn.textContent = '✕'
      removeBtn.onclick = -> window.AppViewConfigHelpers.removeField @
      fieldItem.appendChild removeBtn

      selectedContainer.appendChild fieldItem

    # Update YAML editor
    @syncVisualToYaml app

  removeField: (button) ->
    fieldItem = button.closest '.selected-field-item'
    fieldItem?.remove()
    @syncVisualToYaml window.App

  handleRelationClick: (app, relationData) ->
    # Handle relation click for automatic joins
    console.log 'Relation clicked:', relationData
    # For now, just log - automatic join logic can be added later
  initializeYamlEditor: (app, view = null) ->
    yamlContent = app.el.dvYamlContent()

    if view?.config
      # Load existing configuration as YAML
      config = view.config
      yaml = @configToYaml config
      yamlContent.value = yaml
    else
      # Default template
      yamlContent.value = @getDefaultYamlTemplate()

    @_yamlChanged = false

  getDefaultYamlTemplate: ->
    return """# Configuration de la vue
# Modifiez ce YAML ou utilisez les onglets visuels à droite

columns: []
  # Exemple:
  # - name: id
  # - name: titre
  # - name: prix

filter:
  formula: ""
  # Exemple:
  # formula: "@prix > 20 and @disponible == true"

groupBy: []
  # Exemple:
  # - genre
  # - annee_publication

aggregates: []
  # Exemple:
  # - field: prix
  #   func: AVG
  #   alias: prix_moyen
"""

  configToYaml: (config) ->
    lines = ['columns:']

    # Add columns
    if config?.columns?.length > 0
      for col in config.columns
        lines.push "  - name: #{col.name}"
        lines.push "    label: #{col.label or col.name}" if col.label and col.label != col.name
    else
      lines.push '  []'

    lines.push ''

    # Add filter
    if config?.filter?.formula
      lines.push 'filter:'
      lines.push "  formula: \"#{config.filter.formula}\""
      lines.push "  language: #{config.filter.language or 'moonscript'}" if config.filter.language
    else
      lines.push 'filter:'
      lines.push '  formula: ""'

    lines.push ''

    # Add groupBy
    if config?.groupBy?.length > 0
      lines.push 'groupBy:'
      for field in config.groupBy
        lines.push "  - #{field}"
    else
      lines.push 'groupBy: []'

    lines.push ''

    # Add aggregates
    if config?.aggregates?.length > 0
      lines.push 'aggregates:'
      for agg in config.aggregates
        lines.push "  - field: #{agg.field}"
        lines.push "    func: #{agg.func}"
        lines.push "    alias: #{agg.alias}" if agg.alias
    else
      lines.push 'aggregates: []'

    return lines.join('\n')

  formatYaml: (app) ->
    yamlContent = app.el.dvYamlContent()
    try
      # Basic YAML formatting (could be enhanced with a proper YAML library)
      yaml = yamlContent.value
      # Simple formatting - in a real implementation, use js-yaml
      lines = yaml.split('\n')
      formatted = []

      for line in lines
        if line.trim() == ''
          formatted.push ''
        else if line.startsWith('#')
          formatted.push line
        else
          # Basic indentation fix
          indent = line.match(/^(\s*)/)[1]
          content = line.trim()
          if content.includes(':') and not content.startsWith('-')
            formatted.push "#{indent}#{content}"
          else
            formatted.push line

      yamlContent.value = formatted.join('\n')
      tdbAlert 'YAML formaté avec succès', 'success'
    catch error
      tdbAlert 'Erreur lors du formatage YAML', 'error'

  applyYamlToVisual: (app) ->
    yamlContent = app.el.dvYamlContent()
    try
      config = @yamlToConfig yamlContent.value
      @updateVisualFromConfig app, config
      @_yamlChanged = false
      tdbAlert 'YAML appliqué à l\'interface visuelle', 'success'
    catch error
      tdbAlert 'Erreur dans le YAML: ' + error.message, 'error'

  yamlToConfig: (yaml) ->
    # Simple YAML parsing (in production, use js-yaml library)
    config = {
      columns: []
      filter: null
      groupBy: []
      aggregates: []
    }

    lines = yaml.split('\n')
    currentSection = null
    currentArray = null

    for line in lines
      trimmed = line.trim()
      continue if trimmed == '' or trimmed.startsWith('#')

      if trimmed.startsWith('columns:')
        currentSection = 'columns'
        currentArray = config.columns
      else if trimmed.startsWith('filter:')
        currentSection = 'filter'
        config.filter = { formula: '', language: 'moonscript' }
      else if trimmed.startsWith('groupBy:')
        currentSection = 'groupBy'
        currentArray = config.groupBy
      else if trimmed.startsWith('aggregates:')
        currentSection = 'aggregates'
        currentArray = config.aggregates
      else if currentSection and trimmed.startsWith('-')
        item = trimmed.substring(1).trim()
        if currentSection == 'columns' and item.includes('name:')
          name = item.match(/name:\s*(.+)/)?[1]?.trim()
          config.columns.push { name: name, label: name }
        else if currentSection == 'groupBy'
          config.groupBy.push item
        else if currentSection == 'aggregates' and item.includes('field:')
          field = item.match(/field:\s*(.+)/)?[1]?.trim()
          config.aggregates.push { field: field, func: 'SUM', alias: "#{field.toLowerCase()}_sum" }
      else if currentSection == 'filter' and trimmed.includes('formula:')
        formula = trimmed.match(/formula:\s*"(.+)"/)?[1]?.trim()
        config.filter.formula = formula if formula

    return config

  updateVisualFromConfig: (app, config) ->
    # Update fields tab
    @resetDataViewFields app
    if config.columns?.length > 0
      @loadExistingColumns app, config.columns

    # Update filter tab
    app.el.dvFilterFormula().value = config.filter?.formula or ''

    # Update aggregates
    app.el.dvAggregatesList().innerHTML = ''
    if config.aggregates?.length > 0
      for agg in config.aggregates
        @_addAggregateRow app, agg.field, agg.func, agg.alias

    # Update groupBy (would need implementation)
    # This would update the groupby fields

  markYamlAsChanged: (app) ->
    @_yamlChanged = true

  syncVisualToYaml: (app) ->
    return unless @_yamlChanged

    # Gather current visual state
    config = @gatherVisualConfig app
    yaml = @configToYaml config
    app.el.dvYamlContent().value = yaml
    @_yamlChanged = false

  gatherVisualConfig: (app) ->
    # Gather columns
    columns = []
    selectedContainer = document.getElementById 'dv-selected-fields'
    if selectedContainer
      selectedContainer.querySelectorAll('.field-item').forEach (fieldItem) ->
        columns.push {
          name: fieldItem.dataset.fieldName
          label: fieldItem.dataset.fieldName
        }

    # Gather filter
    filterFormula = app.el.dvFilterFormula().value.trim()
    filter = if filterFormula then { formula: filterFormula, language: 'moonscript' } else { formula: '', language: 'moonscript' }

    # Gather aggregates
    aggregates = []
    app.el.dvAggregatesList().querySelectorAll('.dv-row').forEach (row) ->
      aField = row.querySelector('.dv-agg-field').value.trim()
      aFunc = row.querySelector('.dv-agg-func').value
      aAlias = row.querySelector('.dv-agg-alias').value.trim()
      if aField
        aggregates.push { field: aField, func: aFunc, alias: aAlias or "#{aFunc.toLowerCase()}_#{aField}" }

    return {
      columns: if columns.length > 0 then columns else null
      filter: filter
      groupBy: [] # Would need implementation
      aggregates: if aggregates.length > 0 then aggregates else null
    }
