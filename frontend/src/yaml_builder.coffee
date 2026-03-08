# frontend/src/yaml_builder.coffee
# Visual YAML builder — schema browser panel for the custom view editor.
# Exposed as window.YamlBuilder (no module system, loaded via <script>).

class YamlBuilder

  constructor: ({@container, @allSpaces, @allRelations, @onChange}) ->
    @_widgets  = []    # { id, spaceId, spaceName, columns: [], dependsOn: null|{widgetId,field,from_field} }
    @_idCounter = 1
    @_expanded  = {}

    # Build lookup maps
    @_spaceById = {}
    @_fieldById = {}  # [spaceId][fieldId] → field obj
    for sp in (@allSpaces or [])
      @_spaceById[sp.id] = sp
      @_fieldById[sp.id] = {}
      for f in (sp.fields or [])
        @_fieldById[sp.id][f.id] = f

    # Start with all spaces expanded
    @_expanded[sp.id] = true for sp in (@allSpaces or [])

  # ── Helpers ─────────────────────────────────────────────────────────────────

  _widgetForSpace: (spaceId) ->
    @_widgets.find (w) -> w.spaceId == spaceId

  _needsId: (widget) ->
    @_widgets.some (w) -> w.dependsOn?.widgetId == widget.id

  _makeId: (spaceName) ->
    ((spaceName or 'widget').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')) or
      "w#{@_idCounter}"

  # ── State mutation ───────────────────────────────────────────────────────────

  _onFieldClick: (spaceId, fieldName) ->
    existing = @_widgetForSpace spaceId

    if existing
      # Toggle field membership
      if fieldName in existing.columns
        existing.columns = existing.columns.filter (c) -> c != fieldName
        @_widgets = @_widgets.filter (w) -> w.spaceId != spaceId if existing.columns.length == 0
      else
        existing.columns.push fieldName
    else
      # Detect relation from this space to an already-added space (S → T)
      existingSpaceIds = @_widgets.map (w) -> w.spaceId
      dependsOn = null
      for rel in (@allRelations or [])
        if rel.fromSpaceId == spaceId and existingSpaceIds.indexOf(rel.toSpaceId) != -1
          targetWidget = @_widgets.find (w) -> w.spaceId == rel.toSpaceId
          fromField    = @_fieldById[spaceId]?[rel.fromFieldId]
          toField      = @_fieldById[rel.toSpaceId]?[rel.toFieldId]
          if fromField and toField and targetWidget
            dependsOn = { widgetId: targetWidget.id, field: fromField.name, from_field: toField.name }
            break

      sp  = @_spaceById[spaceId]
      id  = @_makeId sp?.name
      @_idCounter++
      @_widgets.push { id, spaceId, spaceName: (sp?.name or spaceId), columns: [fieldName], dependsOn }

    @_notify()
    @_render()

  _notify: ->
    @onChange? @toYaml()

  # ── YAML generation ──────────────────────────────────────────────────────────

  toYaml: ->
    return "layout:\n  direction: vertical\n  children: []\n" if @_widgets.length == 0
    children = for w in @_widgets
      wObj = { space: w.spaceName }
      wObj.id      = w.id             if @_needsId w
      wObj.columns = w.columns.slice() if w.columns.length > 0
      if w.dependsOn
        dep = { widget: w.dependsOn.widgetId, field: w.dependsOn.field }
        dep.from_field = w.dependsOn.from_field if w.dependsOn.from_field and w.dependsOn.from_field != 'id'
        wObj.depends_on = dep
      { widget: wObj }
    jsyaml.dump({ layout: { direction: 'vertical', children } }, { indent: 2, lineWidth: -1 })

  # ── Rendering ────────────────────────────────────────────────────────────────

  mount: -> @_render()

  _render: ->
    c = @container
    c.innerHTML = ''

    # Header
    hdr = document.createElement 'div'
    hdr.className = 'sb-header'
    lbl = document.createElement 'span'
    lbl.className = 'sb-header-label'
    lbl.textContent = 'Espaces'
    hdr.appendChild lbl
    if @_widgets.length > 0
      btn = document.createElement 'button'
      btn.className = 'sb-clear-btn'
      btn.textContent = 'Effacer'
      btn.addEventListener 'click', =>
        @_widgets   = []
        @_idCounter = 1
        @_notify()
        @_render()
      hdr.appendChild btn
    c.appendChild hdr

    hint = document.createElement 'p'
    hint.className = 'sb-hint'
    hint.textContent = 'Cliquer sur un champ pour l\'ajouter au YAML.'
    c.appendChild hint

    c.appendChild @_renderSpace(sp) for sp in (@allSpaces or [])

  _renderSpace: (sp) ->
    widget   = @_widgetForSpace sp.id
    isActive = !!widget
    expanded = @_expanded[sp.id]

    wrap = document.createElement 'div'
    wrap.className = 'sb-space'

    titleRow = document.createElement 'div'
    titleRow.className = 'sb-space-title' + (if isActive then ' sb-space-active' else '')

    arrow = document.createElement 'span'
    arrow.className = 'sb-arrow'
    arrow.textContent = if expanded then '▾' else '▸'
    titleRow.appendChild arrow

    name = document.createElement 'span'
    name.textContent = sp.name
    titleRow.appendChild name

    if isActive
      badge = document.createElement 'span'
      badge.className = 'sb-widget-badge'
      badge.textContent = "#{widget.columns.length} col."
      titleRow.appendChild badge

    titleRow.addEventListener 'click', =>
      @_expanded[sp.id] = !@_expanded[sp.id]
      @_render()
    wrap.appendChild titleRow

    if expanded
      fields = sp.fields or []
      if fields.length == 0
        note = document.createElement 'div'
        note.className = 'sb-no-fields'
        note.textContent = '(aucun champ)'
        wrap.appendChild note
      else
        wrap.appendChild @_renderField(sp, f, widget) for f in fields
    wrap

  _renderField: (sp, field, widget) ->
    inWidget = widget and field.name in widget.columns
    div = document.createElement 'div'
    div.className = 'sb-field' + (if inWidget then ' sb-field-active' else '')

    nameSpan = document.createElement 'span'
    nameSpan.className = 'sb-field-name'
    nameSpan.textContent = field.name
    div.appendChild nameSpan

    typeSpan = document.createElement 'span'
    typeSpan.className = 'sb-field-type'
    typeSpan.textContent = field.fieldType
    div.appendChild typeSpan

    div.addEventListener 'click', (e) =>
      e.stopPropagation()
      @_onFieldClick sp.id, field.name
    div

window.YamlBuilder = YamlBuilder
