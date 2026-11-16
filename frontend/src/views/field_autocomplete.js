(function() {
  // field_autocomplete.coffee — field name autocomplete for the MoonScript
  // formula filters ("λ"); `@a.b.pre` follows relations at any depth.
  var MAX_ITEMS, TOKEN_RE, _cached, _fieldCache, _fieldsOf, _filter, _insert, _relCache, _relsOf, _resolve, _token, attach;

  TOKEN_RE = /@((?:[A-Za-z_]\w*\.)*)([A-Za-z_]\w*)?$/;

  MAX_ITEMS = 12;

  _fieldCache = {}; // spaceId -> Promise([fields])

  _relCache = {}; // spaceId -> Promise([relations])

  
  // Every space — the displayed one included — is fetched once, then cached.
  // A DataView cannot be trusted for this: a page widget builds its own with no
  // relations (`_relations: []`) and with `space.fields` reduced to the visible
  // columns, so `@relation.` would propose nothing there.

  // Un échec de chargement ne reste jamais en cache : sans cela, une promesse
  // rejetée figerait l'autocomplétion jusqu'au rechargement de la page.
  _cached = function(cache, sid, load) {
    var promise;
    if (cache[sid]) {
      return cache[sid];
    }
    promise = Promise.resolve().then(function() {
      return load();
    }).catch(function(err) {
      delete cache[sid];
      throw err;
    });
    cache[sid] = promise;
    return promise;
  };

  _fieldsOf = function(sid) {
    return _cached(_fieldCache, sid, function() {
      return (Spaces.getWithFields(sid)).then(function(s) {
        return (s != null ? s.fields : void 0) || [];
      });
    });
  };

  _relsOf = function(sid) {
    return _cached(_relCache, sid, function() {
      return (Spaces.listRelations(sid)).then(function(rels) {
        return rels || [];
      });
    });
  };

  // `@a.b.pre` under the caret → { path: ['a', 'b'], prefix: 'pre' }, else null.
  _token = function(text) {
    var m, path, raw;
    m = TOKEN_RE.exec(String(text || ''));
    if (!m) {
      return null;
    }
    raw = m[1] || '';
    path = raw === '' ? [] : raw.slice(0, -1).split('.');
    return {
      path,
      prefix: m[2] || ''
    };
  };

  // Resolve `path` from the DataView's start space (id only) → { fields,
  // relations } of the space reached; an unknown or non-relation segment gives
  // empty fields.
  _resolve = function(dv, path) {
    var empty, ref, start, step;
    empty = {
      fields: [],
      relations: []
    };
    start = dv != null ? (ref = dv.space) != null ? ref.id : void 0 : void 0;
    if (!start) {
      return Promise.resolve(empty);
    }
    step = function(sid, rest) {
      return Promise.all([_fieldsOf(sid), _relsOf(sid)]).then(function([fields, rels]) {
        var f, rel;
        if (rest.length === 0) {
          return {
            fields,
            relations: rels
          };
        }
        f = fields.find(function(x) {
          return x.name === rest[0];
        });
        if (!f) {
          return empty;
        }
        rel = rels.find(function(r) {
          return r.fromFieldId === f.id;
        });
        if (!rel) {
          return empty;
        }
        return step(rel.toSpaceId, rest.slice(1));
      });
    };
    return step(start, path || []);
  };

  // Name-prefix filter (case-insensitive), alphabetical, at most MAX_ITEMS.
  _filter = function(fields, prefix) {
    var f, out, p;
    p = String(prefix || '').toLowerCase();
    out = (function() {
      var j, len, ref, results;
      ref = fields || [];
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        f = ref[j];
        if (String(f.name || '').toLowerCase().indexOf(p) === 0) {
          results.push(f);
        }
      }
      return results;
    })();
    out.sort(function(a, b) {
      return String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase());
    });
    return out.slice(0, MAX_ITEMS);
  };

  // Replace the prefix before `caret` with `field.name`; returns { value, caret }.
  _insert = function(text, caret, field) {
    var m, name, prefix, start;
    text = String(text || '');
    m = TOKEN_RE.exec(text.slice(0, caret));
    if (!m) {
      return null;
    }
    prefix = m[2] || '';
    start = caret - prefix.length;
    name = String(field.name);
    return {
      value: text.slice(0, start) + name + text.slice(caret),
      caret: start + name.length
    };
  };

  attach = function(input, getDataView) {
    var close, detach, items, list, pick, relIds, render, reqId, sel, skipNext, update;
    if (!input) {
      return;
    }
    list = null;
    items = [];
    relIds = new Set();
    sel = 0;
    reqId = 0;
    skipNext = false; // ignore the `input` event we dispatch ourselves
    detach = function() {
      if (list && list.parentNode) {
        list.parentNode.removeChild(list);
      }
      return list = null;
    };
    close = function() {
      detach();
      items = [];
      return sel = 0;
    };
    render = function() {
      var f, i, item, j, len, name, r, type;
      detach();
      list = document.createElement('div');
      list.className = 'field-ac';
      for (i = j = 0, len = items.length; j < len; i = ++j) {
        f = items[i];
        item = document.createElement('div');
        item.className = i === sel ? 'field-ac-item selected' : 'field-ac-item';
        name = document.createElement('span');
        name.textContent = (relIds.has(f.id) ? '→ ' : '') + f.name;
        type = document.createElement('span');
        type.className = 'field-ac-type';
        type.textContent = f.fieldType || '';
        item.appendChild(name);
        item.appendChild(type);
        item.addEventListener('mousedown', function(ev) {
          ev.preventDefault();
          return pick(f);
        });
        list.appendChild(item);
      }
      document.body.appendChild(list);
      r = typeof input.getBoundingClientRect === "function" ? input.getBoundingClientRect() : void 0;
      if (!r) {
        return;
      }
      list.style.position = 'fixed';
      list.style.top = `${r.bottom + 2}px`;
      list.style.left = `${r.left}px`;
      return list.style.minWidth = `${r.width}px`;
    };
    pick = function(field) {
      var caret, ref, res;
      if (!field) {
        return;
      }
      caret = (ref = input.selectionStart) != null ? ref : input.value.length;
      res = _insert(input.value, caret, field);
      if (!res) {
        return;
      }
      input.value = res.value;
      input.selectionStart = input.selectionEnd = res.caret;
      close();
      skipNext = true;
      return input.dispatchEvent(new Event('input', {
        bubbles: true
      }));
    };
    update = function() {
      var caret, my, ref, tok;
      if (skipNext) {
        skipNext = false;
        return close();
      }
      caret = (ref = input.selectionStart) != null ? ref : input.value.length;
      tok = _token(input.value.slice(0, caret));
      if (!tok) {
        return close();
      }
      my = ++reqId;
      return _resolve(typeof getDataView === "function" ? getDataView() : void 0, tok.path).then(function(res) {
        var found, r;
        if (my !== reqId) {
          return;
        }
        found = _filter(res.fields, tok.prefix);
        if (found.length === 0) {
          return close();
        }
        items = found;
        relIds = new Set((function() {
          var j, len, ref1, results;
          ref1 = res.relations;
          results = [];
          for (j = 0, len = ref1.length; j < len; j++) {
            r = ref1[j];
            results.push(r.fromFieldId);
          }
          return results;
        })());
        sel = 0;
        return render();
      }).catch(function(err) {
        // Un chargement en échec ne doit pas laisser de rejet non géré (ni de
        // liste fantôme) : on ferme simplement les suggestions.
        console.warn('FieldAutocomplete: chargement des champs impossible', err);
        if (my === reqId) {
          return close();
        }
      });
    };
    input.addEventListener('input', update);
    input.addEventListener('click', update);
    input.addEventListener('blur', close);
    return input.addEventListener('keydown', function(ev) {
      if (!(list && items.length > 0)) {
        return;
      }
      switch (ev.key) {
        case 'ArrowDown':
          ev.preventDefault();
          sel = (sel + 1) % items.length;
          return render();
        case 'ArrowUp':
          ev.preventDefault();
          sel = (sel - 1 + items.length) % items.length;
          return render();
        case 'Enter':
        case 'Tab':
          ev.preventDefault();
          return pick(items[sel]);
        case 'Escape':
          return close();
      }
    });
  };

  window.FieldAutocomplete = {
    attach: attach,
    _token: _token,
    _resolve: _resolve,
    _filter: _filter,
    _insert: _insert,
    _reset: function() {
      _fieldCache = {};
      return _relCache = {};
    }
  };

}).call(this);
