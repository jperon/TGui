(function() {
  // frontend/src/yaml_builder.coffee
  // Visual YAML builder: ERD diagram + widget state for custom view editor.
  // Exposed as window.YamlBuilder (no module system, loaded via <script>).
  var BOX_W, COL_GAP, FIELD_H, HEADER_H, PAD, ROW_GAP, SELF_LOOP_R, SVG_NS, YamlBuilder, svgEl,
    indexOf = [].indexOf;

  SVG_NS = 'http://www.w3.org/2000/svg';

  BOX_W = 160; // box width in px

  HEADER_H = 26; // space-name header height

  FIELD_H = 19; // height per field row

  COL_GAP = 64; // horizontal gap between columns (space for arrows)

  ROW_GAP = 20; // vertical gap between boxes in the same column

  PAD = 14; // SVG margin

  SELF_LOOP_R = 28; // self-loop horizontal extent past the right edge

  svgEl = function(tag, attrs = {}) {
    var el, k, v;
    el = document.createElementNS(SVG_NS, tag);
    for (k in attrs) {
      v = attrs[k];
      el.setAttribute(k, v);
    }
    return el;
  };

  YamlBuilder = class YamlBuilder {
    constructor({
        container: container1,
        allSpaces,
        allRelations,
        onChange,
        initialYaml
      }) {
      var f, j, l, len, len1, ref, ref1, sp;
      this.container = container1;
      this.allSpaces = allSpaces;
      this.allRelations = allRelations;
      this.onChange = onChange;
      this._widgets = [];
      this._idCounter = 1;
      this._positions = {}; // spaceId -> { x, y, width, height }
      this._panCleanup = null;
      this._suppressNextClick = false;
      // Lookup maps
      this._spaceById = {};
      this._fieldById = {}; // [spaceId][fieldId] -> field obj
      this._nameToSpId = {}; // spaceName -> spaceId
      ref = this.allSpaces || [];
      for (j = 0, len = ref.length; j < len; j++) {
        sp = ref[j];
        this._spaceById[sp.id] = sp;
        this._nameToSpId[sp.name] = sp.id;
        this._fieldById[sp.id] = {};
        ref1 = sp.fields || [];
        for (l = 0, len1 = ref1.length; l < len1; l++) {
          f = ref1[l];
          this._fieldById[sp.id][f.id] = f;
        }
      }
      if (initialYaml) {
        this._loadFromYaml(initialYaml);
      }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────

      // Returns fields sorted alphabetically by name
    _sortedFields(sp) {
      return (sp.fields || []).slice().sort(function(a, b) {
        return a.name.localeCompare(b.name);
      });
    }

    _widgetForSpace(spaceId) {
      return this._widgets.find(function(w) {
        return w.spaceId === spaceId && w.type !== 'aggregate';
      });
    }

    _aggWidgetForSpace(spaceId) {
      return this._widgets.find(function(w) {
        return w.spaceId === spaceId && w.type === 'aggregate';
      });
    }

    _needsId(widget) {
      return this._widgets.some(function(w) {
        var ref;
        return ((ref = w.dependsOn) != null ? ref.widgetId : void 0) === widget.id;
      });
    }

    _makeId(spaceName) {
      var s;
      s = (spaceName || 'widget').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
      return s || `w${this._idCounter}`;
    }

    // ── YAML hydration ───────────────────────────────────────────────────────────
    // Parse an existing YAML string and populate @_widgets so ERD reflects
    // what is already defined. Called once in the constructor with initialYaml.
    _loadFromYaml(yaml) {
      var KNOWN_AGG, KNOWN_REG, collectWidgets, columns, dependsOn, extra, id, j, k, len, parsed, results, spaceId, v, w, widgetDefs;
      if (!(yaml && yaml.trim().length > 0)) {
        return;
      }
      try {
        parsed = jsyaml.load(yaml);
      } catch (error) {
        return;
      }
      if (!parsed) {
        return;
      }
      // Collect all widget nodes recursively from the layout tree
      collectWidgets = function(node) {
        var ref;
        if (!node) {
          return [];
        }
        if (node.widget) {
          return [node.widget];
        } else if ((ref = node.layout) != null ? ref.children : void 0) {
          return node.layout.children.reduce((function(acc, c) {
            return acc.concat(collectWidgets(c));
          }), []);
        } else {
          return [];
        }
      };
      widgetDefs = collectWidgets(parsed);
      KNOWN_REG = ['type', 'space', 'id', 'columns', 'depends_on'];
      KNOWN_AGG = ['type', 'space', 'groupBy'];
      results = [];
      for (j = 0, len = widgetDefs.length; j < len; j++) {
        w = widgetDefs[j];
        if (!w.space) {
          continue;
        }
        spaceId = this._nameToSpId[w.space];
        if (!spaceId) { // unknown space → skip
          continue;
        }
        if (w.type === 'aggregate') {
          if (!this._aggWidgetForSpace(spaceId)) {
            extra = {};
            for (k in w) {
              v = w[k];
              if (indexOf.call(KNOWN_AGG, k) < 0) {
                extra[k] = v;
              }
            }
            results.push(this._widgets.push({
              type: 'aggregate',
              spaceId,
              spaceName: w.space,
              groupBy: (w.groupBy || []).slice(),
              _extra: extra
            }));
          } else {
            results.push(void 0);
          }
        } else {
          if (!this._widgetForSpace(spaceId)) {
            id = w.id || this._makeId(w.space);
            this._idCounter++;
            dependsOn = null;
            if (w.depends_on) {
              dependsOn = {
                widgetId: w.depends_on.widget,
                field: w.depends_on.field,
                from_field: w.depends_on.from_field || 'id'
              };
            }
            columns = (w.columns || []).slice();
            extra = {};
            for (k in w) {
              v = w[k];
              if (indexOf.call(KNOWN_REG, k) < 0) {
                extra[k] = v;
              }
            }
            results.push(this._widgets.push({
              id,
              spaceId,
              spaceName: w.space,
              columns,
              dependsOn,
              _extra: extra
            }));
          } else {
            results.push(void 0);
          }
        }
      }
      return results;
    }

    // ── State mutation ───────────────────────────────────────────────────────────
    _onHeaderClick(spaceId) {
      var existing, fkFieldIds, groupBy, j, len, ref, rel, sp;
      existing = this._aggWidgetForSpace(spaceId);
      if (existing) {
        this._widgets = this._widgets.filter(function(w) {
          return !(w.spaceId === spaceId && w.type === 'aggregate');
        });
      } else {
        sp = this._spaceById[spaceId];
        // Exclude FK fields from groupBy (fields used as FK origin in relations)
        fkFieldIds = {};
        ref = this.allRelations || [];
        for (j = 0, len = ref.length; j < len; j++) {
          rel = ref[j];
          if (rel.fromSpaceId === spaceId) {
            fkFieldIds[rel.fromFieldId] = true;
          }
        }
        groupBy = this._sortedFields(sp).filter(function(f) {
          return !fkFieldIds[f.id];
        }).map(function(f) {
          return f.name;
        });
        this._widgets.push({
          type: 'aggregate',
          spaceId,
          spaceName: (sp != null ? sp.name : void 0) || spaceId,
          groupBy
        });
      }
      this._notify();
      return this._render();
    }

    _onFieldClick(spaceId, fieldName) {
      var dependsOn, existing, existingSpaceIds, ff, id, initialColumns, j, len, ref, ref1, ref2, rel, sp, tf, tw;
      existing = this._widgetForSpace(spaceId);
      if (existing) {
        if (fieldName === '*') {
          // Toggle: if already "all columns" mode (empty), remove widget; else switch to all
          if (existing.columns.length === 0) {
            this._widgets = this._widgets.filter(function(w) {
              return w.spaceId !== spaceId;
            });
          } else {
            existing.columns = [];
          }
        } else if (indexOf.call(existing.columns, fieldName) >= 0) {
          existing.columns = existing.columns.filter(function(c) {
            return c !== fieldName;
          });
          this._widgets = this._widgets.filter(function(w) {
            if (existing.columns.length === 0) {
              return w.spaceId !== spaceId;
            }
          });
        } else {
          existing.columns.push(fieldName);
        }
      } else {
        existingSpaceIds = this._widgets.map(function(w) {
          return w.spaceId;
        });
        dependsOn = null;
        ref = this.allRelations || [];
        for (j = 0, len = ref.length; j < len; j++) {
          rel = ref[j];
          if (rel.fromSpaceId === spaceId && existingSpaceIds.indexOf(rel.toSpaceId) !== -1) {
            tw = this._widgets.find(function(w) {
              return w.spaceId === rel.toSpaceId;
            });
            ff = (ref1 = this._fieldById[spaceId]) != null ? ref1[rel.fromFieldId] : void 0;
            tf = (ref2 = this._fieldById[rel.toSpaceId]) != null ? ref2[rel.toFieldId] : void 0;
            if (ff && tf && tw) {
              dependsOn = {
                widgetId: tw.id,
                field: ff.name,
                from_field: tf.name
              };
              break;
            }
          }
        }
        sp = this._spaceById[spaceId];
        id = this._makeId(sp != null ? sp.name : void 0);
        this._idCounter++;
        initialColumns = fieldName === '*' ? [] : [fieldName];
        this._widgets.push({
          id,
          spaceId,
          spaceName: (sp != null ? sp.name : void 0) || spaceId,
          columns: initialColumns,
          dependsOn
        });
      }
      this._notify();
      return this._render();
    }

    _notify() {
      return typeof this.onChange === "function" ? this.onChange(this.toYaml()) : void 0;
    }

    // Re-synchronise ERD state from an updated YAML string (called when the
    // CodeMirror editor changes externally, i.e. the user typed manually).
    // Only updates the ERD state; does NOT trigger onChange (to avoid loop).
    reloadFromYaml(yaml) {
      this._widgets = [];
      this._idCounter = 1;
      this._loadFromYaml(yaml);
      return this._render();
    }

    // ── YAML generation ──────────────────────────────────────────────────────────
    toYaml() {
      var children, dep, w, wObj;
      if (this._widgets.length === 0) {
        return "layout:\n  direction: vertical\n  children: []\n";
      }
      children = (function() {
        var j, len, ref, ref1, results;
        ref = this._widgets;
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          w = ref[j];
          if (w.type === 'aggregate') {
            // Put structural keys first, then pass-through (_extra: title, computed, etc.)
            wObj = {
              type: 'aggregate',
              space: w.spaceName
            };
            Object.assign(wObj, w._extra || {});
            if (((ref1 = w.groupBy) != null ? ref1.length : void 0) > 0) {
              wObj.groupBy = w.groupBy.slice();
            }
            if (wObj.aggregate == null) {
              wObj.aggregate = [
                {
                  fn: 'count',
                  as: 'nb'
                }
              ];
            }
            results.push({
              widget: wObj
            });
          } else {
            // Put structural keys first, then pass-through (_extra: title, etc.)
            wObj = {
              space: w.spaceName
            };
            Object.assign(wObj, w._extra || {});
            if (this._needsId(w)) {
              wObj.id = w.id;
            }
            if (w.columns.length > 0) {
              wObj.columns = w.columns.slice();
            }
            if (w.dependsOn) {
              dep = {
                widget: w.dependsOn.widgetId,
                field: w.dependsOn.field
              };
              if (w.dependsOn.from_field && w.dependsOn.from_field !== 'id') {
                dep.from_field = w.dependsOn.from_field;
              }
              wObj.depends_on = dep;
            }
            results.push({
              widget: wObj
            });
          }
        }
        return results;
      }).call(this);
      return jsyaml.dump({
        layout: {
          direction: 'vertical',
          children
        }
      }, {
        indent: 2,
        lineWidth: -1
      });
    }

    // ── Layout ───────────────────────────────────────────────────────────────────
    // Topological column assignment: spaces with FKs to level-N spaces get level N+1.
    // Parents (no outgoing FKs, or unknown targets) sit at level 0 on the left.
    // Children (have FKs) sit to the right of their parents.
    _computeLayout() {
      var boxH, byCol, changed, col, colStr, cumY, j, l, len, len1, len2, len3, len4, len5, len6, level, m, n, nFields, o, outgoing, p, passes, positions, q, ref, ref1, ref2, rel, rels, sp, spList, spaces, toId;
      spaces = this.allSpaces || [];
      rels = this.allRelations || [];
      if (spaces.length === 0) {
        return {};
      }
      // Build outgoing FK map: spaceId -> [toSpaceId, ...]
      // Self-relations are excluded from level assignment (they don't affect column placement)
      outgoing = {};
      for (j = 0, len = spaces.length; j < len; j++) {
        sp = spaces[j];
        outgoing[sp.id] = [];
      }
      for (l = 0, len1 = rels.length; l < len1; l++) {
        rel = rels[l];
        if (rel.fromSpaceId !== rel.toSpaceId) {
          if ((ref = outgoing[rel.fromSpaceId]) != null) {
            ref.push(rel.toSpaceId);
          }
        }
      }
      // Assign levels: BFS-like relaxation (handles acyclic graphs correctly)
      level = {};
      for (m = 0, len2 = spaces.length; m < len2; m++) {
        sp = spaces[m];
        level[sp.id] = 0;
      }
      changed = true;
      passes = 0;
      while (changed && passes < spaces.length) {
        changed = false;
        passes++;
        for (n = 0, len3 = spaces.length; n < len3; n++) {
          sp = spaces[n];
          ref1 = outgoing[sp.id] || [];
          for (o = 0, len4 = ref1.length; o < len4; o++) {
            toId = ref1[o];
            if ((level[toId] != null) && level[sp.id] <= level[toId]) {
              level[sp.id] = level[toId] + 1;
              changed = true;
            }
          }
        }
      }
      // Group spaces by column (level)
      byCol = {};
      for (p = 0, len5 = spaces.length; p < len5; p++) {
        sp = spaces[p];
        col = level[sp.id] || 0;
        if (byCol[col] == null) {
          byCol[col] = [];
        }
        byCol[col].push(sp);
      }
      // Compute pixel positions (+1 row for * pseudo-field)
      positions = {};
      for (colStr in byCol) {
        spList = byCol[colStr];
        col = parseInt(colStr);
        cumY = PAD;
        for (q = 0, len6 = spList.length; q < len6; q++) {
          sp = spList[q];
          nFields = (((ref2 = sp.fields) != null ? ref2.length : void 0) || 0) + 1; // +1 for * pseudo-field row
          boxH = HEADER_H + nFields * FIELD_H;
          positions[sp.id] = {
            x: PAD + col * (BOX_W + COL_GAP),
            y: cumY,
            width: BOX_W,
            height: boxH
          };
          cumY += boxH + ROW_GAP;
        }
      }
      return positions;
    }

    // ── Rendering ────────────────────────────────────────────────────────────────
    mount() {
      return this._render();
    }

    _bindPan(container) {
      var dragging, moved, onClickCapture, onPointerDown, onPointerMove, onPointerUp, startLeft, startTop, startX, startY;
      if (!container) {
        return;
      }
      if (typeof this._panCleanup === "function") {
        this._panCleanup();
      }
      container.classList.add('schema-browser--pannable');
      dragging = false;
      moved = false;
      startX = 0;
      startY = 0;
      startLeft = 0;
      startTop = 0;
      onPointerDown = (e) => {
        if (e.button !== 0) {
          return;
        }
        dragging = true;
        moved = false;
        startX = e.clientX;
        startY = e.clientY;
        startLeft = container.scrollLeft;
        startTop = container.scrollTop;
        container.classList.add('is-panning');
        return typeof container.setPointerCapture === "function" ? container.setPointerCapture(e.pointerId) : void 0;
      };
      onPointerMove = (e) => {
        var dx, dy;
        if (!dragging) {
          return;
        }
        dx = e.clientX - startX;
        dy = e.clientY - startY;
        if (!moved && (Math.abs(dx) > 3 || Math.abs(dy) > 3)) {
          moved = true;
        }
        if (!moved) {
          return;
        }
        container.scrollLeft = startLeft - dx;
        container.scrollTop = startTop - dy;
        return e.preventDefault();
      };
      onPointerUp = (e) => {
        if (!dragging) {
          return;
        }
        dragging = false;
        container.classList.remove('is-panning');
        if (typeof container.releasePointerCapture === "function") {
          container.releasePointerCapture(e.pointerId);
        }
        return this._suppressNextClick = moved;
      };
      onClickCapture = (e) => {
        if (!this._suppressNextClick) {
          return;
        }
        this._suppressNextClick = false;
        e.preventDefault();
        return e.stopPropagation();
      };
      container.addEventListener('pointerdown', onPointerDown);
      container.addEventListener('pointermove', onPointerMove);
      container.addEventListener('pointerup', onPointerUp);
      container.addEventListener('pointercancel', onPointerUp);
      container.addEventListener('click', onClickCapture, true);
      return this._panCleanup = () => {
        container.removeEventListener('pointerdown', onPointerDown);
        container.removeEventListener('pointermove', onPointerMove);
        container.removeEventListener('pointerup', onPointerUp);
        container.removeEventListener('pointercancel', onPointerUp);
        container.removeEventListener('click', onClickCapture, true);
        return container.classList.remove('is-panning');
      };
    }

    _render() {
      var arrowsG, boxesG, btn, c, cx, defs, fi, fp, fromSp, hdr, hint, j, l, lbl, len, len1, len2, lx, m, marker, msg, pos, positions, rel, rels, sortedFrom, sortedTo, sp, spaces, svg, ti, toSp, totalH, totalW, tp, x, x1, x2, y1, y2;
      c = this.container;
      c.innerHTML = '';
      // Sticky header
      hdr = document.createElement('div');
      hdr.className = 'sb-header';
      lbl = document.createElement('span');
      lbl.className = 'sb-header-label';
      lbl.textContent = 'Schéma ERD';
      hdr.appendChild(lbl);
      if (this._widgets.length > 0) {
        btn = document.createElement('button');
        btn.className = 'sb-clear-btn';
        btn.textContent = 'Effacer';
        btn.addEventListener('click', () => {
          this._widgets = [];
          this._idCounter = 1;
          this._notify();
          return this._render();
        });
        hdr.appendChild(btn);
      }
      c.appendChild(hdr);
      hint = document.createElement('p');
      hint.className = 'sb-hint';
      hint.textContent = 'Cliquer un champ pour l\'ajouter au YAML.';
      c.appendChild(hint);
      spaces = this.allSpaces || [];
      rels = this.allRelations || [];
      if (spaces.length === 0) {
        msg = document.createElement('p');
        msg.className = 'sb-hint';
        msg.textContent = 'Aucun espace.';
        c.appendChild(msg);
        return;
      }
      positions = this._computeLayout();
      this._positions = positions;
      // SVG canvas dimensions (include extra right margin for self-loop arrows)
      totalW = PAD;
      totalH = PAD;
      for (j = 0, len = spaces.length; j < len; j++) {
        sp = spaces[j];
        pos = positions[sp.id];
        if (!pos) {
          continue;
        }
        totalW = Math.max(totalW, pos.x + pos.width + SELF_LOOP_R + PAD);
        totalH = Math.max(totalH, pos.y + pos.height + PAD);
      }
      svg = svgEl('svg', {
        width: totalW,
        height: totalH,
        viewBox: `0 0 ${totalW} ${totalH}`,
        class: 'erd-svg'
      });
      // Arrowhead marker
      defs = svgEl('defs');
      marker = svgEl('marker', {
        id: 'erd-arrow',
        markerWidth: '7',
        markerHeight: '6',
        refX: '7',
        refY: '3',
        orient: 'auto'
      });
      marker.appendChild(svgEl('polygon', {
        points: '0 0, 7 3, 0 6',
        fill: '#7878a8'
      }));
      defs.appendChild(marker);
      svg.appendChild(defs);
      // Arrows (drawn behind boxes)
      arrowsG = svgEl('g', {
        class: 'erd-arrows'
      });
      for (l = 0, len1 = rels.length; l < len1; l++) {
        rel = rels[l];
        fp = positions[rel.fromSpaceId];
        tp = positions[rel.toSpaceId];
        if (!(fp && tp)) {
          continue;
        }
        fromSp = this._spaceById[rel.fromSpaceId];
        toSp = this._spaceById[rel.toSpaceId];
        if (!(fromSp && toSp)) {
          continue;
        }
        sortedFrom = this._sortedFields(fromSp);
        sortedTo = this._sortedFields(toSp);
        fi = sortedFrom.findIndex(function(f) {
          return f.id === rel.fromFieldId;
        });
        ti = sortedTo.findIndex(function(f) {
          return f.id === rel.toFieldId;
        });
        // +1 offset: row 0 is the * pseudo-field; real fields start at row 1
        y1 = fp.y + HEADER_H + (Math.max(0, fi) + 1) * FIELD_H + FIELD_H / 2;
        y2 = tp.y + HEADER_H + (Math.max(0, ti) + 1) * FIELD_H + FIELD_H / 2;
        if (rel.fromSpaceId === rel.toSpaceId) {
          // Self-loop: bezier arc on the right side of the box
          x = fp.x + fp.width;
          lx = x + SELF_LOOP_R;
          arrowsG.appendChild(svgEl('path', {
            d: `M ${x} ${y1} C ${lx} ${y1} ${lx} ${y2} ${x} ${y2}`,
            fill: 'none',
            stroke: '#7878a8',
            'stroke-width': '1.5',
            'marker-end': 'url(#erd-arrow)',
            class: 'erd-arrow-path'
          }));
        } else {
          if (fp.x >= tp.x) {
            x1 = fp.x;
            x2 = tp.x + tp.width;
          } else {
            x1 = fp.x + fp.width;
            x2 = tp.x;
          }
          cx = (x1 + x2) / 2;
          arrowsG.appendChild(svgEl('path', {
            d: `M ${x1} ${y1} C ${cx} ${y1} ${cx} ${y2} ${x2} ${y2}`,
            fill: 'none',
            stroke: '#7878a8',
            'stroke-width': '1.5',
            'marker-end': 'url(#erd-arrow)',
            class: 'erd-arrow-path'
          }));
        }
      }
      svg.appendChild(arrowsG);
      // Boxes (drawn on top of arrows)
      boxesG = svgEl('g', {
        class: 'erd-boxes'
      });
      for (m = 0, len2 = spaces.length; m < len2; m++) {
        sp = spaces[m];
        if (positions[sp.id]) {
          boxesG.appendChild(this._drawBox(sp, positions[sp.id]));
        }
      }
      svg.appendChild(boxesG);
      c.appendChild(svg);
      return this._bindPan(c);
    }

    _drawBox(sp, pos) {
      var aggWidget, allCols, badgeEl, boxH, field, fields, g, headerClass, i, isActive, isAgg, j, len, nRows, nameEl, widget;
      widget = this._widgetForSpace(sp.id);
      isActive = !!widget;
      aggWidget = this._aggWidgetForSpace(sp.id);
      isAgg = !!aggWidget;
      fields = this._sortedFields(sp);
      allCols = isActive && widget.columns.length === 0; // * mode: all columns
      nRows = fields.length + 1; // +1 for * pseudo-field
      boxH = HEADER_H + nRows * FIELD_H;
      g = svgEl('g', {
        class: 'erd-space',
        transform: `translate(${pos.x},${pos.y})`
      });
      // Outer border
      g.appendChild(svgEl('rect', {
        x: '0',
        y: '0',
        width: BOX_W,
        height: boxH,
        rx: '4',
        class: 'erd-box' + (isActive || isAgg ? ' erd-box-active' : '')
      }));
      // Header background
      headerClass = 'erd-header' + (isAgg ? ' erd-header-agg' : isActive ? ' erd-header-active' : '');
      g.appendChild(svgEl('rect', {
        x: '0',
        y: '0',
        width: BOX_W,
        height: HEADER_H,
        rx: '4',
        class: headerClass
      }));
      // Clip the bottom corners of header (so rx only applies at top)
      g.appendChild(svgEl('rect', {
        x: '0',
        y: HEADER_H / 2,
        width: BOX_W,
        height: HEADER_H / 2,
        class: headerClass
      }));
      // Clickable overlay on header to toggle aggregate widget
      ((spaceId) => {
        var hdrClick;
        hdrClick = svgEl('rect', {
          x: '0',
          y: '0',
          width: BOX_W,
          height: HEADER_H,
          fill: 'transparent',
          style: 'cursor: pointer'
        });
        hdrClick.addEventListener('click', () => {
          return this._onHeaderClick(spaceId);
        });
        return g.appendChild(hdrClick);
      })(sp.id);
      // Space name
      nameEl = svgEl('text', {
        x: BOX_W / 2,
        y: HEADER_H / 2 + 1,
        'text-anchor': 'middle',
        'dominant-baseline': 'middle',
        class: 'erd-space-name',
        style: 'pointer-events: none'
      });
      nameEl.textContent = sp.name;
      g.appendChild(nameEl);
      // Badge: ∑ for aggregate, * or count for regular widget
      if (isAgg) {
        badgeEl = svgEl('text', {
          x: BOX_W - 4,
          y: HEADER_H / 2 + 1,
          'text-anchor': 'end',
          'dominant-baseline': 'middle',
          class: 'erd-badge',
          style: 'pointer-events: none'
        });
        badgeEl.textContent = '\u2211 \u2713'; // ∑ ✓
        g.appendChild(badgeEl);
      } else if (isActive) {
        badgeEl = svgEl('text', {
          x: BOX_W - 4,
          y: HEADER_H / 2 + 1,
          'text-anchor': 'end',
          'dominant-baseline': 'middle',
          class: 'erd-badge',
          style: 'pointer-events: none'
        });
        badgeEl.textContent = allCols ? '* \u2713' : `${widget.columns.length} \u2713`;
        g.appendChild(badgeEl);
      }
      // Separator between header and fields
      g.appendChild(svgEl('line', {
        x1: '0',
        y1: HEADER_H,
        x2: BOX_W,
        y2: HEADER_H,
        class: 'erd-separator'
      }));
      // * pseudo-field at row 0 (adds all columns / no restriction)
      ((spaceId) => {
        var bg, fy, nm, tp;
        fy = HEADER_H;
        bg = svgEl('rect', {
          x: '0',
          y: fy,
          width: BOX_W,
          height: FIELD_H,
          class: 'erd-field-bg' + (allCols ? ' erd-field-active' : '')
        });
        bg.addEventListener('click', () => {
          return this._onFieldClick(spaceId, '*');
        });
        g.appendChild(bg);
        nm = svgEl('text', {
          x: '5',
          y: fy + FIELD_H / 2 + 1,
          'dominant-baseline': 'middle',
          class: 'erd-field-name' + (allCols ? ' erd-field-name-active' : '')
        });
        nm.textContent = '*';
        nm.style.pointerEvents = 'none';
        nm.style.fontStyle = 'italic';
        g.appendChild(nm);
        tp = svgEl('text', {
          x: BOX_W - 4,
          y: fy + FIELD_H / 2 + 1,
          'text-anchor': 'end',
          'dominant-baseline': 'middle',
          class: 'erd-field-type'
        });
        tp.textContent = 'tous';
        tp.style.pointerEvents = 'none';
        return g.appendChild(tp);
      })(sp.id);
// Real field rows (sorted alphabetically, starting at row index 1)
      for (i = j = 0, len = fields.length; j < len; i = ++j) {
        field = fields[i];
        ((spaceId, fname) => {
          var bg, fy, inWidget, nm, tp;
          inWidget = isActive && indexOf.call(widget.columns, fname) >= 0;
          fy = HEADER_H + (i + 1) * FIELD_H;
          bg = svgEl('rect', {
            x: '0',
            y: fy,
            width: BOX_W,
            height: FIELD_H,
            class: 'erd-field-bg' + (inWidget ? ' erd-field-active' : '')
          });
          bg.addEventListener('click', () => {
            return this._onFieldClick(spaceId, fname);
          });
          g.appendChild(bg);
          // Separator above every real field row (separates * from first, then real from real)
          g.appendChild(svgEl('line', {
            x1: '0',
            y1: fy,
            x2: BOX_W,
            y2: fy,
            class: 'erd-field-sep'
          }));
          nm = svgEl('text', {
            x: '5',
            y: fy + FIELD_H / 2 + 1,
            'dominant-baseline': 'middle',
            class: 'erd-field-name' + (inWidget ? ' erd-field-name-active' : '')
          });
          nm.textContent = fname;
          nm.style.pointerEvents = 'none';
          g.appendChild(nm);
          tp = svgEl('text', {
            x: BOX_W - 4,
            y: fy + FIELD_H / 2 + 1,
            'text-anchor': 'end',
            'dominant-baseline': 'middle',
            class: 'erd-field-type'
          });
          tp.textContent = field.fieldType;
          tp.style.pointerEvents = 'none';
          return g.appendChild(tp);
        })(sp.id, field.name);
      }
      return g;
    }

  };

  window.YamlBuilder = YamlBuilder;

}).call(this);
