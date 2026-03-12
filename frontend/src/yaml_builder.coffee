# frontend/src/yaml_builder.coffee
# Visual YAML builder: ERD diagram + widget state for custom view editor.
# Exposed as window.YamlBuilder (no module system, loaded via <script>).

SVG_NS      = 'http://www.w3.org/2000/svg'
BOX_W       = 160   # box width in px
HEADER_H    = 26    # space-name header height
FIELD_H     = 19    # height per field row
COL_GAP     = 64    # horizontal gap between columns (space for arrows)
ROW_GAP     = 20    # vertical gap between boxes in the same column
PAD         = 14    # SVG margin
SELF_LOOP_R = 28    # self-loop horizontal extent past the right edge

svgEl = (tag, attrs = {}) ->
  el = document.createElementNS SVG_NS, tag
  el.setAttribute k, v for k, v of attrs
  el

class YamlBuilder

  constructor: ({@container, @allSpaces, @allRelations, @onChange, initialYaml}) ->
    @_widgets   = []
    @_idCounter = 1
    @_positions = {}   # spaceId -> { x, y, width, height }
    @_panCleanup = null
    @_suppressNextClick = false

    # Lookup maps
    @_spaceById  = {}
    @_fieldById  = {}   # [spaceId][fieldId] -> field obj
    @_nameToSpId = {}   # spaceName -> spaceId
    for sp in (@allSpaces or [])
      @_spaceById[sp.id]   = sp
      @_nameToSpId[sp.name] = sp.id
      @_fieldById[sp.id]   = {}
      for f in (sp.fields or [])
        @_fieldById[sp.id][f.id] = f

    @_loadFromYaml initialYaml if initialYaml

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # Returns fields sorted alphabetically by name
  _sortedFields: (sp) ->
    (sp.fields or []).slice().sort (a, b) -> a.name.localeCompare b.name

  _widgetForSpace: (spaceId) -> @_widgets.find (w) -> w.spaceId == spaceId and w.type != 'aggregate'

  _aggWidgetForSpace: (spaceId) -> @_widgets.find (w) -> w.spaceId == spaceId and w.type == 'aggregate'

  _needsId: (widget) -> @_widgets.some (w) -> w.dependsOn?.widgetId == widget.id

  _makeId: (spaceName) ->
    s = (spaceName or 'widget').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')
    s or "w#{@_idCounter}"

  # ── YAML hydration ───────────────────────────────────────────────────────────
  # Parse an existing YAML string and populate @_widgets so ERD reflects
  # what is already defined. Called once in the constructor with initialYaml.

  _loadFromYaml: (yaml) ->
    return unless yaml and yaml.trim().length > 0
    try
      parsed = jsyaml.load yaml
    catch
      return
    return unless parsed

    # Collect all widget nodes recursively from the layout tree
    collectWidgets = (node) ->
      return [] unless node
      if node.widget                         then [node.widget]
      else if node.layout?.children         then node.layout.children.reduce ((acc, c) -> acc.concat collectWidgets c), []
      else                                       []

    widgetDefs = collectWidgets parsed

    KNOWN_REG = ['type', 'space', 'id', 'columns', 'depends_on']
    KNOWN_AGG = ['type', 'space', 'groupBy']
    for w in widgetDefs
      continue unless w.space
      spaceId = @_nameToSpId[w.space]
      continue unless spaceId    # unknown space → skip

      if w.type == 'aggregate'
        unless @_aggWidgetForSpace spaceId
          extra = {}
          extra[k] = v for k, v of w when k not in KNOWN_AGG
          @_widgets.push { type: 'aggregate', spaceId, spaceName: w.space, groupBy: (w.groupBy or []).slice(), _extra: extra }
      else
        unless @_widgetForSpace spaceId
          id = w.id or @_makeId(w.space)
          @_idCounter++
          dependsOn = null
          if w.depends_on
            dependsOn =
              widgetId:   w.depends_on.widget
              field:      w.depends_on.field
              from_field: w.depends_on.from_field or 'id'
          columns = (w.columns or []).slice()
          extra = {}
          extra[k] = v for k, v of w when k not in KNOWN_REG
          @_widgets.push { id, spaceId, spaceName: w.space, columns, dependsOn, _extra: extra }

  # ── State mutation ───────────────────────────────────────────────────────────

  _onHeaderClick: (spaceId) ->
    existing = @_aggWidgetForSpace spaceId
    if existing
      @_widgets = @_widgets.filter (w) -> !(w.spaceId == spaceId and w.type == 'aggregate')
    else
      sp = @_spaceById[spaceId]
      # Exclude FK fields from groupBy (fields used as FK origin in relations)
      fkFieldIds = {}
      for rel in (@allRelations or [])
        fkFieldIds[rel.fromFieldId] = true if rel.fromSpaceId == spaceId
      groupBy = @_sortedFields(sp).filter((f) -> !fkFieldIds[f.id]).map (f) -> f.name
      @_widgets.push { type: 'aggregate', spaceId, spaceName: (sp?.name or spaceId), groupBy }
    @_notify()
    @_render()

  _onFieldClick: (spaceId, fieldName) ->
    existing = @_widgetForSpace spaceId
    if existing
      if fieldName == '*'
        # Toggle: if already "all columns" mode (empty), remove widget; else switch to all
        if existing.columns.length == 0
          @_widgets = @_widgets.filter (w) -> w.spaceId != spaceId
        else
          existing.columns = []
      else if fieldName in existing.columns
        existing.columns = existing.columns.filter (c) -> c != fieldName
        @_widgets = @_widgets.filter (w) -> w.spaceId != spaceId if existing.columns.length == 0
      else
        existing.columns.push fieldName
    else
      existingSpaceIds = @_widgets.map (w) -> w.spaceId
      dependsOn = null
      for rel in (@allRelations or [])
        if rel.fromSpaceId == spaceId and existingSpaceIds.indexOf(rel.toSpaceId) != -1
          tw = @_widgets.find (w) -> w.spaceId == rel.toSpaceId
          ff = @_fieldById[spaceId]?[rel.fromFieldId]
          tf = @_fieldById[rel.toSpaceId]?[rel.toFieldId]
          if ff and tf and tw
            dependsOn = { widgetId: tw.id, field: ff.name, from_field: tf.name }
            break
      sp = @_spaceById[spaceId]
      id = @_makeId sp?.name
      @_idCounter++
      initialColumns = if fieldName == '*' then [] else [fieldName]
      @_widgets.push { id, spaceId, spaceName: (sp?.name or spaceId), columns: initialColumns, dependsOn }

    @_notify()
    @_render()

  _notify: -> @onChange? @toYaml()

  # Re-synchronise ERD state from an updated YAML string (called when the
  # CodeMirror editor changes externally, i.e. the user typed manually).
  # Only updates the ERD state; does NOT trigger onChange (to avoid loop).
  reloadFromYaml: (yaml) ->
    @_widgets   = []
    @_idCounter = 1
    @_loadFromYaml yaml
    @_render()

  # ── YAML generation ──────────────────────────────────────────────────────────

  toYaml: ->
    return "layout:\n  direction: vertical\n  children: []\n" if @_widgets.length == 0
    children = for w in @_widgets
      if w.type == 'aggregate'
        # Put structural keys first, then pass-through (_extra: title, computed, etc.)
        wObj = { type: 'aggregate', space: w.spaceName }
        Object.assign wObj, (w._extra or {})
        wObj.groupBy   = w.groupBy.slice() if w.groupBy?.length > 0
        wObj.aggregate ?= [{ fn: 'count', as: 'nb' }]
        { widget: wObj }
      else
        # Put structural keys first, then pass-through (_extra: title, etc.)
        wObj = { space: w.spaceName }
        Object.assign wObj, (w._extra or {})
        wObj.id      = w.id              if @_needsId w
        wObj.columns = w.columns.slice() if w.columns.length > 0
        if w.dependsOn
          dep = { widget: w.dependsOn.widgetId, field: w.dependsOn.field }
          dep.from_field = w.dependsOn.from_field if w.dependsOn.from_field and w.dependsOn.from_field != 'id'
          wObj.depends_on = dep
        { widget: wObj }
    jsyaml.dump({ layout: { direction: 'vertical', children } }, { indent: 2, lineWidth: -1 })

  # ── Layout ───────────────────────────────────────────────────────────────────
  # Topological column assignment: spaces with FKs to level-N spaces get level N+1.
  # Parents (no outgoing FKs, or unknown targets) sit at level 0 on the left.
  # Children (have FKs) sit to the right of their parents.

  _computeLayout: ->
    spaces = @allSpaces or []
    rels   = @allRelations or []
    return {} if spaces.length == 0

    # Build outgoing FK map: spaceId -> [toSpaceId, ...]
    # Self-relations are excluded from level assignment (they don't affect column placement)
    outgoing = {}
    outgoing[sp.id] = [] for sp in spaces
    for rel in rels
      outgoing[rel.fromSpaceId]?.push rel.toSpaceId if rel.fromSpaceId != rel.toSpaceId

    # Assign levels: BFS-like relaxation (handles acyclic graphs correctly)
    level = {}
    level[sp.id] = 0 for sp in spaces
    changed = true
    passes  = 0
    while changed and passes < spaces.length
      changed = false
      passes++
      for sp in spaces
        for toId in (outgoing[sp.id] or [])
          if level[toId]? and level[sp.id] <= level[toId]
            level[sp.id] = level[toId] + 1
            changed = true

    # Group spaces by column (level)
    byCol = {}
    for sp in spaces
      col = level[sp.id] or 0
      byCol[col] ?= []
      byCol[col].push sp

    # Compute pixel positions (+1 row for * pseudo-field)
    positions = {}
    for colStr, spList of byCol
      col = parseInt colStr
      cumY = PAD
      for sp in spList
        nFields = (sp.fields?.length or 0) + 1  # +1 for * pseudo-field row
        boxH = HEADER_H + nFields * FIELD_H
        positions[sp.id] =
          x:      PAD + col * (BOX_W + COL_GAP)
          y:      cumY
          width:  BOX_W
          height: boxH
        cumY += boxH + ROW_GAP
    positions

  # ── Rendering ────────────────────────────────────────────────────────────────

  mount: -> @_render()

  _bindPan: (container) ->
    return unless container
    @_panCleanup?()
    container.classList.add 'schema-browser--pannable'

    dragging = false
    moved    = false
    startX   = 0
    startY   = 0
    startLeft = 0
    startTop  = 0

    onPointerDown = (e) =>
      return unless e.button == 0
      dragging = true
      moved = false
      startX = e.clientX
      startY = e.clientY
      startLeft = container.scrollLeft
      startTop  = container.scrollTop
      container.classList.add 'is-panning'

    onPointerMove = (e) =>
      return unless dragging
      dx = e.clientX - startX
      dy = e.clientY - startY
      if !moved and (Math.abs(dx) > 3 or Math.abs(dy) > 3)
        moved = true
      return unless moved
      container.scrollLeft = startLeft - dx
      container.scrollTop  = startTop  - dy
      e.preventDefault()

    onPointerUp = (e) =>
      return unless dragging
      dragging = false
      container.classList.remove 'is-panning'
      @_suppressNextClick = moved

    onClickCapture = (e) =>
      return unless @_suppressNextClick
      @_suppressNextClick = false
      e.preventDefault()
      e.stopPropagation()

    container.addEventListener 'pointerdown', onPointerDown
    container.addEventListener 'pointermove', onPointerMove
    container.addEventListener 'pointerup', onPointerUp
    container.addEventListener 'pointercancel', onPointerUp
    container.addEventListener 'click', onClickCapture, true

    @_panCleanup = =>
      container.removeEventListener 'pointerdown', onPointerDown
      container.removeEventListener 'pointermove', onPointerMove
      container.removeEventListener 'pointerup', onPointerUp
      container.removeEventListener 'pointercancel', onPointerUp
      container.removeEventListener 'click', onClickCapture, true
      container.classList.remove 'is-panning'

  _render: ->
    c = @container
    c.innerHTML = ''

    # Sticky header
    hdr = document.createElement 'div'
    hdr.className = 'sb-header'
    lbl = document.createElement 'span'
    lbl.className = 'sb-header-label'
    lbl.textContent = 'Schéma ERD'
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
    hint.textContent = 'Cliquer un champ pour l\'ajouter au YAML.'
    c.appendChild hint

    spaces = @allSpaces or []
    rels   = @allRelations or []
    if spaces.length == 0
      msg = document.createElement 'p'
      msg.className = 'sb-hint'
      msg.textContent = 'Aucun espace.'
      c.appendChild msg
      return

    positions = @_computeLayout()
    @_positions = positions

    # SVG canvas dimensions (include extra right margin for self-loop arrows)
    totalW = PAD
    totalH = PAD
    for sp in spaces
      pos = positions[sp.id]
      continue unless pos
      totalW = Math.max totalW, pos.x + pos.width + SELF_LOOP_R + PAD
      totalH = Math.max totalH, pos.y + pos.height + PAD

    svg = svgEl 'svg',
      width:   totalW
      height:  totalH
      viewBox: "0 0 #{totalW} #{totalH}"
      class:   'erd-svg'

    # Arrowhead marker
    defs   = svgEl 'defs'
    marker = svgEl 'marker',
      id:           'erd-arrow'
      markerWidth:  '7'
      markerHeight: '6'
      refX:         '7'
      refY:         '3'
      orient:       'auto'
    marker.appendChild svgEl 'polygon', { points: '0 0, 7 3, 0 6', fill: '#7878a8' }
    defs.appendChild marker
    svg.appendChild defs

    # Arrows (drawn behind boxes)
    arrowsG = svgEl 'g', { class: 'erd-arrows' }
    for rel in rels
      fp = positions[rel.fromSpaceId]
      tp = positions[rel.toSpaceId]
      continue unless fp and tp
      fromSp = @_spaceById[rel.fromSpaceId]
      toSp   = @_spaceById[rel.toSpaceId]
      continue unless fromSp and toSp
      sortedFrom = @_sortedFields fromSp
      sortedTo   = @_sortedFields toSp
      fi = sortedFrom.findIndex (f) -> f.id == rel.fromFieldId
      ti = sortedTo.findIndex   (f) -> f.id == rel.toFieldId
      # +1 offset: row 0 is the * pseudo-field; real fields start at row 1
      y1 = fp.y + HEADER_H + (Math.max(0, fi) + 1) * FIELD_H + FIELD_H / 2
      y2 = tp.y + HEADER_H + (Math.max(0, ti) + 1) * FIELD_H + FIELD_H / 2
      if rel.fromSpaceId == rel.toSpaceId
        # Self-loop: bezier arc on the right side of the box
        x  = fp.x + fp.width
        lx = x + SELF_LOOP_R
        arrowsG.appendChild svgEl 'path',
          d:              "M #{x} #{y1} C #{lx} #{y1} #{lx} #{y2} #{x} #{y2}"
          fill:           'none'
          stroke:         '#7878a8'
          'stroke-width': '1.5'
          'marker-end':   'url(#erd-arrow)'
          class:          'erd-arrow-path'
      else
        if fp.x >= tp.x
          x1 = fp.x;           x2 = tp.x + tp.width
        else
          x1 = fp.x + fp.width; x2 = tp.x
        cx = (x1 + x2) / 2
        arrowsG.appendChild svgEl 'path',
          d:              "M #{x1} #{y1} C #{cx} #{y1} #{cx} #{y2} #{x2} #{y2}"
          fill:           'none'
          stroke:         '#7878a8'
          'stroke-width': '1.5'
          'marker-end':   'url(#erd-arrow)'
          class:          'erd-arrow-path'
    svg.appendChild arrowsG

    # Boxes (drawn on top of arrows)
    boxesG = svgEl 'g', { class: 'erd-boxes' }
    boxesG.appendChild @_drawBox(sp, positions[sp.id]) for sp in spaces when positions[sp.id]
    svg.appendChild boxesG

    c.appendChild svg
    @_bindPan c

  _drawBox: (sp, pos) ->
    widget   = @_widgetForSpace sp.id
    isActive = !!widget
    aggWidget = @_aggWidgetForSpace sp.id
    isAgg    = !!aggWidget
    fields   = @_sortedFields sp
    allCols  = isActive and widget.columns.length == 0  # * mode: all columns
    nRows    = fields.length + 1   # +1 for * pseudo-field
    boxH     = HEADER_H + nRows * FIELD_H

    g = svgEl 'g', { class: 'erd-space', transform: "translate(#{pos.x},#{pos.y})" }

    # Outer border
    g.appendChild svgEl 'rect',
      x: '0'; y: '0'; width: BOX_W; height: boxH; rx: '4'
      class: 'erd-box' + (if isActive or isAgg then ' erd-box-active' else '')

    # Header background
    headerClass = 'erd-header' +
      (if isAgg then ' erd-header-agg' else if isActive then ' erd-header-active' else '')
    g.appendChild svgEl 'rect',
      x: '0'; y: '0'; width: BOX_W; height: HEADER_H; rx: '4'
      class: headerClass

    # Clip the bottom corners of header (so rx only applies at top)
    g.appendChild svgEl 'rect',
      x: '0'; y: HEADER_H / 2; width: BOX_W; height: HEADER_H / 2
      class: headerClass

    # Clickable overlay on header to toggle aggregate widget
    do (spaceId = sp.id) =>
      hdrClick = svgEl 'rect',
        x: '0'; y: '0'; width: BOX_W; height: HEADER_H
        fill: 'transparent'; style: 'cursor: pointer'
      hdrClick.addEventListener 'click', => @_onHeaderClick spaceId
      g.appendChild hdrClick

    # Space name
    nameEl = svgEl 'text',
      x: BOX_W / 2; y: HEADER_H / 2 + 1
      'text-anchor': 'middle'; 'dominant-baseline': 'middle'
      class: 'erd-space-name'
      style: 'pointer-events: none'
    nameEl.textContent = sp.name
    g.appendChild nameEl

    # Badge: ∑ for aggregate, * or count for regular widget
    if isAgg
      badgeEl = svgEl 'text',
        x: BOX_W - 4; y: HEADER_H / 2 + 1
        'text-anchor': 'end'; 'dominant-baseline': 'middle'
        class: 'erd-badge'
        style: 'pointer-events: none'
      badgeEl.textContent = '\u2211 \u2713'   # ∑ ✓
      g.appendChild badgeEl
    else if isActive
      badgeEl = svgEl 'text',
        x: BOX_W - 4; y: HEADER_H / 2 + 1
        'text-anchor': 'end'; 'dominant-baseline': 'middle'
        class: 'erd-badge'
        style: 'pointer-events: none'
      badgeEl.textContent = if allCols then '* \u2713' else "#{widget.columns.length} \u2713"
      g.appendChild badgeEl

    # Separator between header and fields
    g.appendChild svgEl 'line',
      x1: '0'; y1: HEADER_H; x2: BOX_W; y2: HEADER_H
      class: 'erd-separator'

    # * pseudo-field at row 0 (adds all columns / no restriction)
    do (spaceId = sp.id) =>
      fy = HEADER_H
      bg = svgEl 'rect',
        x: '0'; y: fy; width: BOX_W; height: FIELD_H
        class: 'erd-field-bg' + (if allCols then ' erd-field-active' else '')
      bg.addEventListener 'click', => @_onFieldClick spaceId, '*'
      g.appendChild bg

      nm = svgEl 'text',
        x: '5'; y: fy + FIELD_H / 2 + 1
        'dominant-baseline': 'middle'
        class: 'erd-field-name' + (if allCols then ' erd-field-name-active' else '')
      nm.textContent = '*'
      nm.style.pointerEvents = 'none'
      nm.style.fontStyle = 'italic'
      g.appendChild nm

      tp = svgEl 'text',
        x: BOX_W - 4; y: fy + FIELD_H / 2 + 1
        'text-anchor': 'end'; 'dominant-baseline': 'middle'
        class: 'erd-field-type'
      tp.textContent = 'tous'
      tp.style.pointerEvents = 'none'
      g.appendChild tp

    # Real field rows (sorted alphabetically, starting at row index 1)
    for field, i in fields
      do (spaceId = sp.id, fname = field.name) =>
        inWidget = isActive and fname in widget.columns
        fy = HEADER_H + (i + 1) * FIELD_H

        bg = svgEl 'rect',
          x: '0'; y: fy; width: BOX_W; height: FIELD_H
          class: 'erd-field-bg' + (if inWidget then ' erd-field-active' else '')
        bg.addEventListener 'click', => @_onFieldClick spaceId, fname
        g.appendChild bg

        # Separator above every real field row (separates * from first, then real from real)
        g.appendChild svgEl 'line',
          x1: '0'; y1: fy; x2: BOX_W; y2: fy
          class: 'erd-field-sep'

        nm = svgEl 'text',
          x: '5'; y: fy + FIELD_H / 2 + 1
          'dominant-baseline': 'middle'
          class: 'erd-field-name' + (if inWidget then ' erd-field-name-active' else '')
        nm.textContent = fname
        nm.style.pointerEvents = 'none'
        g.appendChild nm

        tp = svgEl 'text',
          x: BOX_W - 4; y: fy + FIELD_H / 2 + 1
          'text-anchor': 'end'; 'dominant-baseline': 'middle'
          class: 'erd-field-type'
        tp.textContent = field.fieldType
        tp.style.pointerEvents = 'none'
        g.appendChild tp
    g

window.YamlBuilder = YamlBuilder
