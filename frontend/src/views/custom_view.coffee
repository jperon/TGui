# custom_view.coffee
# YAML-driven layout renderer.
#
# YAML format example:
#
#   layout:
#     direction: vertical
#     children:
#       - factor: 2                         # prend 2/3 de la place (optionnel, défaut: 1)
#         direction: horizontal
#         children:
#           - widget:
#               id: liste-chorales          # identifiant unique du widget (obligatoire si référencé)
#               title: Chorales
#               space: chorale
#               columns: [annee, pupitre]   # colonnes à afficher (optionnel, défaut: toutes)
#           - widget:
#               title: Choristes
#               space: choristes
#               depends_on:
#                 widget: liste-chorales    # id du widget source
#                 field: chorale_id         # FK field in this space
#                 from_field: id            # referenced field in the source widget's space (défaut: id)
#       - factor: 1
#         widget:
#           title: Personnes
#           space: personnes

window.CustomView = class CustomView
  constructor: (@container, @yamlText, @allSpaces) ->
    @_widgets   = []   # list of { dataView, node, el }
    @_widgetsById = {} # id -> entry

  mount: ->
    @container.innerHTML = ''
    @_widgets     = []
    @_widgetsById = {}
    try
      parsed = jsyaml.load @yamlText
    catch e
      @container.innerHTML = "<p style='color:red;padding:1rem'>YAML invalide : #{e.message}</p>"
      return

    root = parsed?.layout
    unless root
      @container.innerHTML = "<p style='color:#888;padding:1rem'>Pas de section <code>layout</code> dans le YAML.</p>"
      return

    el = @_renderZoneOrWidget root
    @container.style.cssText = 'display:flex;flex-direction:column;height:100%;'
    @container.appendChild el

    # Wire depends_on after all widgets are mounted
    @_wireDepends()

    # Refresh grid layouts now that elements are in the live DOM
    setTimeout =>
      for entry in @_widgets
        entry.dataView?._grid?.refreshLayout()
    , 0

  # Renders either a zone (direction+children) or a widget node.
  # Applies `factor` (flex proportion) when specified (default: 1).
  _renderZoneOrWidget: (node) ->
    if node.widget
      el = @_renderWidget node.widget
    else
      el = document.createElement 'div'
      el.className = "cv-zone #{node.direction or 'vertical'}"
      for child in (node.children or [])
        el.appendChild @_renderZoneOrWidget child
    el.style.flex = if node.factor? then String(node.factor) else '1'
    el

  _renderWidget: (wNode) ->
    wrapper = document.createElement 'div'
    wrapper.className = 'cv-widget'

    # Title bar
    titleBar = document.createElement 'div'
    titleBar.className = 'cv-widget-title'
    titleText = document.createElement 'span'
    titleText.textContent = wNode.title or wNode.space or ''
    titleBar.appendChild titleText
    wrapper.appendChild titleBar

    body = document.createElement 'div'
    body.className = 'cv-widget-body'
    wrapper.appendChild body

    # Aggregate widget (read-only summary table)
    if wNode.type == 'aggregate'
      @_renderAggregate body, wNode
      entry = { dataView: null, node: wNode, el: wrapper }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    # Regular data widget
    sp = @_findSpace wNode.space
    delBtn = document.createElement 'button'
    delBtn.className = 'cv-widget-delete-btn'
    delBtn.title = 'Supprimer les enregistrements sélectionnés'
    delBtn.textContent = '🗑'
    titleBar.appendChild delBtn

    unless sp
      body.innerHTML = "<p style='color:#aaa;padding:.5rem'>Espace « #{wNode.space} » introuvable.</p>"
      entry = { dataView: null, node: wNode, el: wrapper }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    # Apply column filter/order if specified
    if wNode.columns and wNode.columns.length > 0
      fieldMap = {}
      fieldMap[f.name] = f for f in (sp.fields or [])
      sp = Object.assign {}, sp
      sp.fields = (fieldMap[col] for col in wNode.columns when fieldMap[col])

    dv = new DataView body, sp
    dv.mount()
    delBtn.addEventListener 'click', => dv.deleteSelected()
    entry = { dataView: dv, node: wNode, el: wrapper }
    @_widgets.push entry
    @_widgetsById[wNode.id] = entry if wNode.id
    wrapper

  # Render an aggregate (GROUP BY) widget as a read-only table.
  _renderAggregate: (container, wNode) ->
    groupBy   = wNode.groupBy   or []
    aggregate = wNode.aggregate or []
    spaceName = wNode.space
    unless spaceName
      container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Paramètre <code>space</code> manquant.</p>"
      return

    # Show loading state
    container.innerHTML = "<p style='color:#888;padding:.5rem'>Chargement…</p>"

    # Normalize aggregate: ensure each entry has fn and as
    makeAlias = (agg) ->
      return agg.as if agg.as
      if not agg.field then 'count' else "#{agg.fn}_#{agg.field}"

    aggInput = for agg in aggregate
      fn: agg.fn, field: (agg.field or null), as: makeAlias(agg)

    Spaces.aggregateSpace(spaceName, groupBy, aggInput).then (rows) =>
      container.innerHTML = ''
      unless rows and rows.length > 0
        container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Aucun résultat.</p>"
        return

      # Evaluate computed columns (client-side JS expressions on each row)
      computed = wNode.computed or []
      computedFns = []
      for col in computed
        do (col) ->
          try
            fn = new Function('row', "try { return (#{col.expr}); } catch(e) { return null; }")
            computedFns.push { as: col.as, fn }
          catch e
            computedFns.push { as: col.as, fn: -> null }

      # Augment rows with computed values
      if computedFns.length > 0
        for row in rows
          for c in computedFns
            row[c.as] = c.fn row

      # Build column list from first row keys (preserve groupBy order first)
      keys = groupBy.slice()
      for agg in aggInput
        keys.push agg.as unless agg.as in keys
      for col in computed
        keys.push col.as unless col.as in keys

      tbl = document.createElement 'table'
      tbl.className = 'agg-table'

      thead = document.createElement 'thead'
      tr = document.createElement 'tr'
      for k in keys
        th = document.createElement 'th'
        th.textContent = k
        tr.appendChild th
      thead.appendChild tr
      tbl.appendChild thead

      tbody = document.createElement 'tbody'
      for row in rows
        tr = document.createElement 'tr'
        for k in keys
          td = document.createElement 'td'
          v = row[k]
          td.textContent = if v? then String(v) else ''
          tr.appendChild td
        tbody.appendChild tr
      tbl.appendChild tbody
      container.appendChild tbl
    .catch (err) =>
      container.innerHTML = "<p style='color:#c55;padding:.5rem'>Erreur : #{err.message or err}</p>"

  _wireDepends: ->
    for entry in @_widgets
      dep = entry.node.depends_on
      continue unless dep
      src = @_widgetsById[dep.widget]
      unless src?.dataView
        console.warn "depends_on: widget id '#{dep.widget}' introuvable ou sans dataView"
        continue

      # When a row is clicked in the source grid, filter this widget and set FK default.
      # from_field defaults to 'id' when omitted.
      do (entry, dep, src) =>
        src.dataView._grid?.on 'click', (ev) =>
          rowKey = ev.rowKey
          return unless rowKey?
          rowData = src.dataView._currentData[rowKey]
          return unless rowData and not rowData.__isNew
          filterVal = String(rowData[dep.from_field or 'id'])
          defaults = {}
          defaults[dep.field] = filterVal
          entry.dataView?.setDefaultValues defaults
          entry.dataView?.setFilter { field: dep.field, value: filterVal }

  _findSpace: (nameOrId) ->
    return null unless nameOrId
    @allSpaces.find (sp) -> sp.name == nameOrId or sp.id == nameOrId

  unmount: ->
    for entry in @_widgets
      entry.dataView?.unmount?()
    @container.innerHTML = ''
    @_widgets     = []
    @_widgetsById = {}
