(function() {
  // frontend/src/yaml_builder.coffee
  // Visual YAML builder — schema browser panel for the custom view editor.
  // Exposed as window.YamlBuilder (no module system, loaded via <script>).
  var YamlBuilder,
    indexOf = [].indexOf;

  YamlBuilder = class YamlBuilder {
    constructor({container, allSpaces, allRelations, onChange}) {
      var f, i, j, k, len, len1, len2, ref, ref1, ref2, sp;
      this.container = container;
      this.allSpaces = allSpaces;
      this.allRelations = allRelations;
      this.onChange = onChange;
      this._widgets = []; // { id, spaceId, spaceName, columns: [], dependsOn: null|{widgetId,field,from_field} }
      this._idCounter = 1;
      this._expanded = {};
      // Build lookup maps
      this._spaceById = {};
      this._fieldById = {}; // [spaceId][fieldId] → field obj
      ref = this.allSpaces || [];
      for (i = 0, len = ref.length; i < len; i++) {
        sp = ref[i];
        this._spaceById[sp.id] = sp;
        this._fieldById[sp.id] = {};
        ref1 = sp.fields || [];
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          f = ref1[j];
          this._fieldById[sp.id][f.id] = f;
        }
      }
      ref2 = this.allSpaces || [];
      for (k = 0, len2 = ref2.length; k < len2; k++) {
        sp = ref2[k];
        // Start with all spaces expanded
        this._expanded[sp.id] = true;
      }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────
    _widgetForSpace(spaceId) {
      return this._widgets.find(function(w) {
        return w.spaceId === spaceId;
      });
    }

    _needsId(widget) {
      return this._widgets.some(function(w) {
        var ref;
        return ((ref = w.dependsOn) != null ? ref.widgetId : void 0) === widget.id;
      });
    }

    _makeId(spaceName) {
      return ((spaceName || 'widget').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')) || `w${this._idCounter}`;
    }

    // ── State mutation ───────────────────────────────────────────────────────────
    _onFieldClick(spaceId, fieldName) {
      var dependsOn, existing, existingSpaceIds, fromField, i, id, len, ref, ref1, ref2, rel, sp, targetWidget, toField;
      existing = this._widgetForSpace(spaceId);
      if (existing) {
        // Toggle field membership
        if (indexOf.call(existing.columns, fieldName) >= 0) {
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
        // Detect relation from this space to an already-added space (S → T)
        existingSpaceIds = this._widgets.map(function(w) {
          return w.spaceId;
        });
        dependsOn = null;
        ref = this.allRelations || [];
        for (i = 0, len = ref.length; i < len; i++) {
          rel = ref[i];
          if (rel.fromSpaceId === spaceId && existingSpaceIds.indexOf(rel.toSpaceId) !== -1) {
            targetWidget = this._widgets.find(function(w) {
              return w.spaceId === rel.toSpaceId;
            });
            fromField = (ref1 = this._fieldById[spaceId]) != null ? ref1[rel.fromFieldId] : void 0;
            toField = (ref2 = this._fieldById[rel.toSpaceId]) != null ? ref2[rel.toFieldId] : void 0;
            if (fromField && toField && targetWidget) {
              dependsOn = {
                widgetId: targetWidget.id,
                field: fromField.name,
                from_field: toField.name
              };
              break;
            }
          }
        }
        sp = this._spaceById[spaceId];
        id = this._makeId(sp != null ? sp.name : void 0);
        this._idCounter++;
        this._widgets.push({
          id,
          spaceId,
          spaceName: (sp != null ? sp.name : void 0) || spaceId,
          columns: [fieldName],
          dependsOn
        });
      }
      this._notify();
      return this._render();
    }

    _notify() {
      return typeof this.onChange === "function" ? this.onChange(this.toYaml()) : void 0;
    }

    // ── YAML generation ──────────────────────────────────────────────────────────
    toYaml() {
      var children, dep, w, wObj;
      if (this._widgets.length === 0) {
        return "layout:\n  direction: vertical\n  children: []\n";
      }
      children = (function() {
        var i, len, ref, results;
        ref = this._widgets;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          w = ref[i];
          wObj = {
            space: w.spaceName
          };
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

    // ── Rendering ────────────────────────────────────────────────────────────────
    mount() {
      return this._render();
    }

    _render() {
      var btn, c, hdr, hint, i, lbl, len, ref, results, sp;
      c = this.container;
      c.innerHTML = '';
      // Header
      hdr = document.createElement('div');
      hdr.className = 'sb-header';
      lbl = document.createElement('span');
      lbl.className = 'sb-header-label';
      lbl.textContent = 'Espaces';
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
      hint.textContent = 'Cliquer sur un champ pour l\'ajouter au YAML.';
      c.appendChild(hint);
      ref = this.allSpaces || [];
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        sp = ref[i];
        results.push(c.appendChild(this._renderSpace(sp)));
      }
      return results;
    }

    _renderSpace(sp) {
      var arrow, badge, expanded, f, fields, i, isActive, len, name, note, titleRow, widget, wrap;
      widget = this._widgetForSpace(sp.id);
      isActive = !!widget;
      expanded = this._expanded[sp.id];
      wrap = document.createElement('div');
      wrap.className = 'sb-space';
      titleRow = document.createElement('div');
      titleRow.className = 'sb-space-title' + (isActive ? ' sb-space-active' : '');
      arrow = document.createElement('span');
      arrow.className = 'sb-arrow';
      arrow.textContent = expanded ? '▾' : '▸';
      titleRow.appendChild(arrow);
      name = document.createElement('span');
      name.textContent = sp.name;
      titleRow.appendChild(name);
      if (isActive) {
        badge = document.createElement('span');
        badge.className = 'sb-widget-badge';
        badge.textContent = `${widget.columns.length} col.`;
        titleRow.appendChild(badge);
      }
      titleRow.addEventListener('click', () => {
        this._expanded[sp.id] = !this._expanded[sp.id];
        return this._render();
      });
      wrap.appendChild(titleRow);
      if (expanded) {
        fields = sp.fields || [];
        if (fields.length === 0) {
          note = document.createElement('div');
          note.className = 'sb-no-fields';
          note.textContent = '(aucun champ)';
          wrap.appendChild(note);
        } else {
          for (i = 0, len = fields.length; i < len; i++) {
            f = fields[i];
            wrap.appendChild(this._renderField(sp, f, widget));
          }
        }
      }
      return wrap;
    }

    _renderField(sp, field, widget) {
      var div, inWidget, nameSpan, ref, typeSpan;
      inWidget = widget && (ref = field.name, indexOf.call(widget.columns, ref) >= 0);
      div = document.createElement('div');
      div.className = 'sb-field' + (inWidget ? ' sb-field-active' : '');
      nameSpan = document.createElement('span');
      nameSpan.className = 'sb-field-name';
      nameSpan.textContent = field.name;
      div.appendChild(nameSpan);
      typeSpan = document.createElement('span');
      typeSpan.className = 'sb-field-type';
      typeSpan.textContent = field.fieldType;
      div.appendChild(typeSpan);
      div.addEventListener('click', (e) => {
        e.stopPropagation();
        return this._onFieldClick(sp.id, field.name);
      });
      return div;
    }

  };

  window.YamlBuilder = YamlBuilder;

}).call(this);
