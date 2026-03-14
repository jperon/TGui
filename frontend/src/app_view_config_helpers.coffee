# app_view_config_helpers.coffee — Data View configuration modal logic

window.AppViewConfigHelpers =
  _currentViewId: null

  bindDataViewModal: (app) ->
    app.el.dataViewModalCloseBtn().addEventListener 'click', ->
      app.el.dataViewModal().classList.add 'hidden'

    app.el.dataViewSaveBtn().addEventListener 'click', =>
      @saveDataView app

    # Tabs logic
    tabs = app.el.dataViewModal().querySelectorAll '.tab-btn'
    tabs.forEach (btn) ->
      btn.addEventListener 'click', ->
        tabs.forEach (b) -> b.classList.remove 'active'
        btn.classList.add 'active'
        target = btn.dataset.tab
        ['columns', 'filter', 'group'].forEach (t) ->
          document.getElementById("dv-tab-#{t}").classList.toggle 'hidden', t != target

    app.el.dvAddColBtn().addEventListener 'click', =>
      @_addColumnRow app

    app.el.dvAddAggBtn().addEventListener 'click', =>
      @_addAggregateRow app

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
    app.el.dvColumnsList().innerHTML = ''
    app.el.dvAggregatesList().innerHTML = ''
    app.el.dvFilterFormula().value = view?.config?.filter?.formula or ''
    app.el.dvGroupBy().value = (view?.config?.groupBy or []).join ', '

    if view?.config?.columns
      for col in view.config.columns
        @_addColumnRow app, col.name, col.label
    else if not view
      @_addColumnRow app # Start with one empty col for new view

    if view?.config?.aggregates
      for agg in view.config.aggregates
        @_addAggregateRow app, agg.field, agg.func, agg.alias

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

    # Gather columns
    columns = []
    app.el.dvColumnsList().querySelectorAll('.dv-row').forEach (row) ->
      cName = row.querySelector('.dv-col-name').value.trim()
      cLabel = row.querySelector('.dv-col-label').value.trim()
      if cName
        columns.push { name: cName, label: cLabel or cName }

    # Gather aggregates
    aggregates = []
    app.el.dvAggregatesList().querySelectorAll('.dv-row').forEach (row) ->
      aField = row.querySelector('.dv-agg-field').value.trim()
      aFunc = row.querySelector('.dv-agg-func').value
      aAlias = row.querySelector('.dv-agg-alias').value.trim()
      if aField
        aggregates.push { field: aField, func: aFunc, alias: aAlias or "#{aFunc.toLowerCase()}_#{aField}" }

    groupByRaw = app.el.dvGroupBy().value.trim()
    groupBy = if groupByRaw then groupByRaw.split(',').map((s) -> s.trim()).filter((s) -> s) else []
    
    filterFormula = app.el.dvFilterFormula().value.trim()
    filter = if filterFormula then { formula: filterFormula, language: 'moonscript' } else null

    config = {
      columns: if columns.length > 0 then columns else null
      filter: filter
      groupBy: if groupBy.length > 0 then groupBy else null
      aggregates: if aggregates.length > 0 then aggregates else null
    }

    input = {
      name: name
      sourceSpace: sourceSpace
      config: JSON.stringify config
    }

    promise = if @_currentViewId
      DataViews.update(@_currentViewId, input)
    else
      DataViews.create(input)

    promise.then (view) =>
      app.el.dataViewModal().classList.add 'hidden'
      app.loadDataViews().then =>
        app.selectDataView view
    .catch (err) -> tdbAlert app._err(err), 'error'
