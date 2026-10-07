(function() {
  // fk_search_editor.coffee — fuzzy-search editor for foreign-key cells.
  // Extracted from frontend/src/views/data_view.coffee (no functional change).
  // Exposed on window because DataView (data_view.js) references it.
  var FkSearchEditor, _fkSearchEditorSeq;

  _fkSearchEditorSeq = 0;

  window.FkSearchEditor = FkSearchEditor = class FkSearchEditor {
    constructor(props) {
      var current, item, j, label, len, listItems, onKeyDown, raw, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, val, value;
      listItems = (props != null ? (ref = props.columnInfo) != null ? (ref1 = ref.editor) != null ? (ref2 = ref1.options) != null ? ref2.items : void 0 : void 0 : void 0 : void 0) || (props != null ? (ref3 = props.columnInfo) != null ? (ref4 = ref3.editor) != null ? (ref5 = ref4.options) != null ? ref5.listItems : void 0 : void 0 : void 0 : void 0) || [];
      value = props != null ? props.value : void 0;
      this.el = document.createElement('input');
      this.el.type = 'text';
      this.el.className = 'tui-grid-content-text';
      this.el.style.width = '100%';
      this.el.style.boxSizing = 'border-box';
      this.el.autocomplete = 'off';
      this.el.spellcheck = false;
      this.labelToValue = {};
      this.valueToLabel = {};
      this.items = [];
      for (j = 0, len = listItems.length; j < len; j++) {
        item = listItems[j];
        label = String((ref6 = item != null ? item.text : void 0) != null ? ref6 : '');
        raw = item != null ? item.value : void 0;
        val = raw != null ? String(raw) : '';
        this.labelToValue[label] = val;
        if (this.valueToLabel[val] == null) {
          this.valueToLabel[val] = label;
        }
        this.items.push({
          label: label,
          value: val,
          norm: this._normalize(label)
        });
      }
      current = value != null ? String(value) : '';
      this.initialValue = current;
      this.el.value = (ref7 = this.valueToLabel[current]) != null ? ref7 : current;
      this.selectedIndex = 0;
      this.visibleItems = [];
      this.menuVisible = false;
      this.menu = document.createElement('div');
      _fkSearchEditorSeq += 1;
      this.menu.id = `fk-editor-menu-${_fkSearchEditorSeq}`;
      this.menu.className = 'fk-editor-menu';
      this.menu.style.cssText = ['position:fixed', 'z-index:9999', 'display:none', 'max-height:220px', 'overflow:auto', 'background:#fff', 'color:#1f2937', 'border:1px solid #d1d5db', 'border-radius:6px', 'box-shadow:0 8px 20px rgba(0,0,0,0.12)'].join(';');
      onKeyDown = (ev) => {
        var ref8;
        if (ev.key === 'Escape') {
          this.el.value = (ref8 = this.valueToLabel[this.initialValue]) != null ? ref8 : this.initialValue;
          this._hideMenu();
          ev.preventDefault();
          return ev.stopPropagation();
        } else if (ev.key === 'ArrowDown') {
          this._moveSelection(1);
          ev.preventDefault();
          return ev.stopPropagation();
        } else if (ev.key === 'ArrowUp') {
          this._moveSelection(-1);
          ev.preventDefault();
          return ev.stopPropagation();
        } else if (ev.key === 'Enter') {
          if (this.menuVisible && this.visibleItems.length > 0) {
            this._applySelection(this.selectedIndex);
          }
          this._hideMenu();
          ev.preventDefault();
          return ev.stopPropagation();
        }
      };
      this.onKeyDown = onKeyDown;
      this.onInput = () => {
        return this._renderMenu(this.el.value);
      };
      this.onFocus = () => {
        return this._renderMenu(this.el.value);
      };
      this.onBlur = () => {
        return setTimeout((() => {
          return this._hideMenu();
        }), 120);
      };
      this.onWindowChange = () => {
        if (this.menuVisible) {
          return this._positionMenu();
        }
      };
      this.el.addEventListener('keydown', this.onKeyDown);
      this.el.addEventListener('input', this.onInput);
      this.el.addEventListener('focus', this.onFocus);
      this.el.addEventListener('blur', this.onBlur);
    }

    getElement() {
      return this.el;
    }

    mounted() {
      if (this.menu && !this.menu.parentNode) {
        document.body.appendChild(this.menu);
      }
      window.addEventListener('resize', this.onWindowChange);
      window.addEventListener('scroll', this.onWindowChange, true);
      setTimeout((() => {
        var ref;
        return (ref = this.el) != null ? ref.focus() : void 0;
      }), 0);
      setTimeout((() => {
        var ref;
        return (ref = this.el) != null ? ref.select() : void 0;
      }), 0);
      return setTimeout((() => {
        var ref;
        return this._renderMenu((ref = this.el) != null ? ref.value : void 0);
      }), 0);
    }

    getValue() {
      var best, chosen, ref, ref1, ref2, ref3, typed;
      typed = String((ref = (ref1 = this.el) != null ? ref1.value : void 0) != null ? ref : '').trim();
      if (typed === '') {
        return '';
      }
      if (this.labelToValue[typed] != null) {
        return this.labelToValue[typed];
      }
      if (this.menuVisible && this.visibleItems.length > 0) {
        chosen = this.visibleItems[this.selectedIndex];
        if (chosen != null) {
          return String((ref2 = chosen != null ? chosen.value : void 0) != null ? ref2 : '');
        }
      }
      if (/^\d+$/.test(typed)) {
        return typed;
      }
      best = this._filterItems(typed)[0];
      return String((ref3 = best != null ? best.value : void 0) != null ? ref3 : '');
    }

    beforeDestroy() {
      var ref, ref1, ref2, ref3, ref4;
      if (this.onKeyDown) {
        if ((ref = this.el) != null) {
          ref.removeEventListener('keydown', this.onKeyDown);
        }
      }
      if (this.onInput) {
        if ((ref1 = this.el) != null) {
          ref1.removeEventListener('input', this.onInput);
        }
      }
      if (this.onFocus) {
        if ((ref2 = this.el) != null) {
          ref2.removeEventListener('focus', this.onFocus);
        }
      }
      if (this.onBlur) {
        if ((ref3 = this.el) != null) {
          ref3.removeEventListener('blur', this.onBlur);
        }
      }
      if (this.onWindowChange) {
        window.removeEventListener('resize', this.onWindowChange);
      }
      if (this.onWindowChange) {
        window.removeEventListener('scroll', this.onWindowChange, true);
      }
      if ((ref4 = this.menu) != null ? ref4.parentNode : void 0) {
        return this.menu.parentNode.removeChild(this.menu);
      }
    }

    _normalize(s) {
      return String(s != null ? s : '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    }

    _fuzzyScore(query, target) {
      var i, idx, prev, q, score;
      if (query === '') {
        return 0;
      }
      idx = target.indexOf(query);
      if (idx >= 0) {
        return 200 - idx * 4 - (target.length - query.length);
      }
      q = 0;
      score = 0;
      prev = -1;
      i = 0;
      while (i < target.length && q < query.length) {
        if (target[i] === query[q]) {
          score += 4;
          if (prev >= 0 && i === prev + 1) {
            score += 3;
          }
          if (i === q) {
            score += 2;
          }
          prev = i;
          q += 1;
        }
        i += 1;
      }
      if (q !== query.length) {
        return null;
      }
      return score - (target.length - query.length);
    }

    _filterItems(query) {
      var item, j, len, q, ref, s, scored;
      q = this._normalize(String(query != null ? query : '').trim());
      if (q === '') {
        return this.items.slice(0, 25);
      }
      scored = [];
      ref = this.items;
      for (j = 0, len = ref.length; j < len; j++) {
        item = ref[j];
        s = this._fuzzyScore(q, item.norm);
        if (s == null) {
          continue;
        }
        scored.push({
          item,
          score: s
        });
      }
      scored.sort(function(a, b) {
        if (b.score !== a.score) {
          return b.score - a.score;
        } else {
          return a.item.label.localeCompare(b.item.label);
        }
      });
      return scored.slice(0, 25).map(function(x) {
        return x.item;
      });
    }

    _renderMenu(query) {
      var idx, item, j, len, ref, row;
      this.visibleItems = this._filterItems(query);
      if (this.visibleItems.length === 0) {
        this._hideMenu();
        return;
      }
      this.selectedIndex = Math.min(this.selectedIndex, this.visibleItems.length - 1);
      if (this.selectedIndex < 0) {
        this.selectedIndex = 0;
      }
      this.menu.innerHTML = '';
      ref = this.visibleItems;
      for (idx = j = 0, len = ref.length; j < len; idx = ++j) {
        item = ref[idx];
        row = document.createElement('div');
        row.textContent = item.label;
        row.dataset.idx = String(idx);
        row.style.cssText = ['padding:6px 10px', 'cursor:pointer', 'white-space:nowrap', idx === this.selectedIndex ? 'background:#eef2ff' : ''].join(';');
        row.addEventListener('mouseenter', ((idx) => {
          return () => {
            return this.selectedIndex = idx;
          };
        })(idx));
        row.addEventListener('mousedown', ((idx) => {
          return (ev) => {
            ev.preventDefault();
            return this._applySelection(idx);
          };
        })(idx));
        this.menu.appendChild(row);
      }
      this._positionMenu();
      return this._showMenu();
    }

    _positionMenu() {
      var rect;
      if (!(this.el && this.menu)) {
        return;
      }
      rect = this.el.getBoundingClientRect();
      this.menu.style.left = `${Math.round(rect.left)}px`;
      this.menu.style.top = `${Math.round(rect.bottom + 2)}px`;
      return this.menu.style.minWidth = `${Math.max(220, Math.round(rect.width))}px`;
    }

    _showMenu() {
      if (!this.menu) {
        return;
      }
      this.menu.style.display = 'block';
      return this.menuVisible = true;
    }

    _hideMenu() {
      if (!this.menu) {
        return;
      }
      this.menu.style.display = 'none';
      return this.menuVisible = false;
    }

    _moveSelection(delta) {
      var ref, ref1, row;
      if (!(this.visibleItems.length > 0)) {
        return;
      }
      this.selectedIndex = (this.selectedIndex + delta + this.visibleItems.length) % this.visibleItems.length;
      this._renderMenu((ref = this.el) != null ? ref.value : void 0);
      row = (ref1 = this.menu) != null ? typeof ref1.querySelector === "function" ? ref1.querySelector(`[data-idx='${this.selectedIndex}']`) : void 0 : void 0;
      return row != null ? typeof row.scrollIntoView === "function" ? row.scrollIntoView({
        block: 'nearest'
      }) : void 0 : void 0;
    }

    _applySelection(idx) {
      var item;
      item = this.visibleItems[idx];
      if (!item) {
        return;
      }
      this.selectedIndex = idx;
      this.el.value = item.label;
      return this._hideMenu();
    }

  };

}).call(this);
