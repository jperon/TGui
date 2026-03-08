# frontend/src/yaml_builder.coffee
# Visual YAML builder: ERD diagram + widget state for custom view editor.
# Exposed as window.YamlBuilder (no module system, loaded via <script>).

SVG_NS   = 'http://www.w3.org/2000/svg'
BOX_W    = 160   # box width in px
HEADER_H = 26    # space-name header height
FIELD_H  = 19    # height per field row
COL_GAP  = 64    # horizontal gap between columns (space for arrows)
ROW_GAP  = 20    # vertical gap between boxes in the same column
PAD      = 14    # SVG margin

svgEl = (tag, attrs = {}) ->
  el = document.createElementNS SVG_NS, tag
  el.setAttribute k, v for k, v of attrs
  el

class YamlBuilder

  constructor: ({@container, @allSpaces, @allRelations, @onChange}) ->
    @_widgets   = []
    @_idCounter = 1
    @_positions = {}   # spaceId -> { x, y, width, height }

    # Lookup maps
    @_spaceById = {}
    @_fieldById = {}   # [spaceId][fieldId] -> field obj
    for sp in (@allSpaces or [])
      @_spaceById[sp.id] = sp
      @_fieldById[sp.id] = {}
      for f in (sp.fields or [])
        @_fieldById[sp.id][f.id] = f

  # ── Helpers ─────────────────────────────────────────────────────────────────

  _widgetForSpace: (spaceId) -> @_widgets.find (w) -> w.spaceId == spaceId

  _needsId: (widget) -> @_widgets.some (w) -> w.dependsOn?.widgetId == widget.id

  _makeId: (spaceName) ->
    s = (spaceName or 'widget').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')
    s or "w#{@_idCounter}"

  # ── State mutation ───────────────────────────────────────────────────────────

  _onFieldClick: (spaceId, fieldName) ->
    existing = @_widgetForSpace spaceId
    if existing
      if fieldName in existing.columns
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
      @_widgets.push { id, spaceId, spaceName: (sp?.name or spaceId), columns: [fieldName], dependsOn }

    @_notify()
    @_render()

  _notify: -> @onChange? @toYaml()

  # ── YAML generation ──────────────────────────────────────────────────────────

  toYaml: ->
    return "layout:\n  direction: vertical\n  children: []\n" if @_widgets.length == 0
    children = for w in @_widgets
      wObj = { space: w.spaceName }
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

    # Compute pixel positions
    positions = {}
    for colStr, spList of byCol
      col = parseInt colStr
      cumY = PAD
      for sp in spList
        boxH = HEADER_H + (sp.fields?.length or 0) * FIELD_H
        positions[sp.id] =
          x:      PAD + col * (BOX_W + COL_GAP)
          y:      cumY
          width:  BOX_W
          height: boxH
        cumY += boxH + ROW_GAP
    positions

  # ── Rendering ────────────────────────────────────────────────────────────────

  mount: -> @_render()

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

    # SVG canvas dimensions
    totalW = PAD
    totalH = PAD
    for sp in spaces
      pos = positions[sp.id]
      continue unless pos
      totalW = Math.max totalW, pos.x + pos.width  + PAD
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
      continue if rel.fromSpaceId == rel.toSpaceId   # skip self-relations
      fp = positions[rel.fromSpaceId]
      tp = positions[rel.toSpaceId]
      continue unless fp and tp
      fromSp = @_spaceById[rel.fromSpaceId]
      toSp   = @_spaceById[rel.toSpaceId]
      continue unless fromSp and toSp
      fi = (fromSp.fields or []).findIndex (f) -> f.id == rel.fromFieldId
      ti = (toSp.fields   or []).findIndex (f) -> f.id == rel.toFieldId
      y1 = fp.y + HEADER_H + Math.max(0, fi) * FIELD_H + FIELD_H / 2
      y2 = tp.y + HEADER_H + Math.max(0, ti) * FIELD_H + FIELD_H / 2
      # Connect: from left edge of child to right edge of parent (child is to the right)
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

  _drawBox: (sp, pos) ->
    widget   = @_widgetForSpace sp.id
    isActive = !!widget
    fields   = sp.fields or []
    boxH     = HEADER_H + fields.length * FIELD_H

    g = svgEl 'g', { class: 'erd-space', transform: "translate(#{pos.x},#{pos.y})" }

    # Outer border
    g.appendChild svgEl 'rect',
      x: '0'; y: '0'; width: BOX_W; height: boxH; rx: '4'
      class: 'erd-box' + (if isActive then ' erd-box-active' else '')

    # Header background
    g.appendChild svgEl 'rect',
      x: '0'; y: '0'; width: BOX_W; height: HEADER_H; rx: '4'
      class: 'erd-header' + (if isActive then ' erd-header-active' else '')

    # Clip the bottom corners of header (so rx only applies at top)
    g.appendChild svgEl 'rect',
      x: '0'; y: HEADER_H / 2; width: BOX_W; height: HEADER_H / 2
      class: 'erd-header' + (if isActive then ' erd-header-active' else '')

    # Space name
    nameEl = svgEl 'text',
      x: BOX_W / 2; y: HEADER_H / 2 + 1
      'text-anchor': 'middle'; 'dominant-baseline': 'middle'
      class: 'erd-space-name'
    nameEl.textContent = sp.name
    g.appendChild nameEl

    # Badge showing column count
    if isActive
      badgeEl = svgEl 'text',
        x: BOX_W - 4; y: HEADER_H / 2 + 1
        'text-anchor': 'end'; 'dominant-baseline': 'middle'
        class: 'erd-badge'
      badgeEl.textContent = "#{widget.columns.length} \u2713"
      g.appendChild badgeEl

    # Separator between header and fields
    g.appendChild svgEl 'line',
      x1: '0'; y1: HEADER_H; x2: BOX_W; y2: HEADER_H
      class: 'erd-separator'

    # Field rows
    for field, i in fields
      do (spaceId = sp.id, fname = field.name) =>
        inWidget = isActive and fname in widget.columns
        fy = HEADER_H + i * FIELD_H

        bg = svgEl 'rect',
          x: '0'; y: fy; width: BOX_W; height: FIELD_H
          class: 'erd-field-bg' + (if inWidget then ' erd-field-active' else '')
        bg.addEventListener 'click', => @_onFieldClick spaceId, fname
        g.appendChild bg

        # Separator between field rows (subtle)
        if i > 0
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
