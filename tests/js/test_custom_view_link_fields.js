(function() {
  // tests/js/test_custom_view_link_fields.coffee — T21

  // Link fields of a dependent widget must always be loaded, even when absent
  // from `columns`: the DataView query is built from `sp.fields`, so a widget
  // whose columns omit `id` (source side) or its `depends_on.field` (target side)
  // would otherwise load rows without the values the filter compares.

  // The DataView double below mirrors the real query behaviour: rows only contain
  // the fields listed in `@space.fields` (plus __rowId). So a missing link field
  // genuinely disappears from the loaded rows, exactly like in the browser.
  var CV, DEFAULT_ROWS, FakeGrid, RealDataView, SEED_ROWS, TestDataView, assert, describe, eq, flush, it, makeContainer, makeSpaces, mountPage, names, pageLayout, summary, yamlJSON;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    }
  };

  // --- fake tui.Grid ----------------------------------------------------------
  FakeGrid = class FakeGrid {
    constructor() {
      this._data = [];
      this._listeners = {};
      this._classes = {};
    }

    resetData(rows) {
      var i, j, len, results, row;
      this._data = rows;
      results = [];
      for (i = j = 0, len = rows.length; j < len; i = ++j) {
        row = rows[i];
        results.push(row.rowKey = i);
      }
      return results;
    }

    getData() {
      return this._data;
    }

    getRowAt(i) {
      return this._data[i] || null;
    }

    getRow(key) {
      return this._data[Number(key)] || null;
    }

    addRowClassName(key, cls) {
      var base, k;
      k = String(key);
      if ((base = this._classes)[k] == null) {
        base[k] = {};
      }
      return this._classes[k][cls] = true;
    }

    removeRowClassName(key, cls) {
      var ref;
      return (ref = this._classes[String(key)]) != null ? delete ref[cls] : void 0;
    }

    hasRowClass(key, cls) {
      var ref;
      return !!((ref = this._classes[String(key)]) != null ? ref[cls] : void 0);
    }

    countRowsWithClass(cls) {
      var _k, c, ref, v;
      c = 0;
      ref = this._classes;
      for (_k in ref) {
        v = ref[_k];
        if (v[cls]) {
          c += 1;
        }
      }
      return c;
    }

    on(ev, fn) {
      var base;
      if ((base = this._listeners)[ev] == null) {
        base[ev] = [];
      }
      return this._listeners[ev].push(fn);
    }

    emit(ev, payload) {
      var fn, j, len, ref, results;
      ref = this._listeners[ev] || [];
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        fn = ref[j];
        results.push(fn(payload));
      }
      return results;
    }

    getCheckedRowKeys() {
      return [];
    }

    getFocusedCell() {
      return null;
    }

    destroy() {}

    refreshLayout() {}

  };

  // --- load the real DataView, then subclass for the test ---------------------
  require('../../frontend/src/views/fk_search_editor');

  require('../../frontend/src/views/data_view');

  require('../../frontend/src/views/data_view_helpers');

  RealDataView = global.window.DataView;

  SEED_ROWS = {};

  global.DataView = TestDataView = class TestDataView extends RealDataView {
    constructor(container, space) {
      super(container, space);
      this._grid = new FakeGrid();
      this._mounted = true;
    }

    mount() {
      var f, full, n, names, o, r;
      names = (function() {
        var j, len, ref, results;
        ref = this.space.fields || [];
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          results.push(f.name);
        }
        return results;
      }).call(this);
      full = SEED_ROWS[this.space.name] || [];
      this._rows = (function() {
        var j, l, len, len1, results;
        results = [];
        for (j = 0, len = full.length; j < len; j++) {
          r = full[j];
          o = {};
          for (l = 0, len1 = names.length; l < len1; l++) {
            n = names[l];
            if (Object.prototype.hasOwnProperty.call(r, n)) {
              o[n] = r[n];
            }
          }
          o.__rowId = r.id;
          results.push(o);
        }
        return results;
      })();
      this._applyData();
      this._grid.on('click', (ev) => {
        if ((ev != null ? ev.rowKey : void 0) != null) {
          return this.setActiveRow(ev.rowKey);
        }
      });
      return Promise.resolve();
    }

  };

  require('../../frontend/src/views/custom_view');

  require('../../frontend/src/views/custom_view_plugins');

  require('../../frontend/src/views/custom_view_aggregate');

  require('../../frontend/src/views/custom_view_resize');

  CV = global.window.CustomView;

  // --- fixtures ---------------------------------------------------------------
  makeSpaces = function() {
    return [
      {
        id: 'sp-livres',
        name: 'livres',
        fields: [
          {
            id: 'l1',
            name: 'id',
            fieldType: 'Int'
          },
          {
            id: 'l2',
            name: 'titre',
            fieldType: 'String'
          },
          {
            id: 'l3',
            name: 'auteur_nom',
            fieldType: 'String',
            formula: 'a'
          }
        ]
      },
      {
        id: 'sp-ex',
        name: 'exemplaires',
        fields: [
          {
            id: 'e1',
            name: 'id',
            fieldType: 'Int'
          },
          {
            id: 'e2',
            name: 'livre',
            fieldType: 'Int'
          },
          {
            id: 'e3',
            name: 'cote',
            fieldType: 'String'
          },
          {
            id: 'e4',
            name: 'emprunteur',
            fieldType: 'String',
            formula: 'a'
          }
        ]
      },
      {
        id: 'sp-em',
        name: 'emprunts',
        fields: [
          {
            id: 'm1',
            name: 'id',
            fieldType: 'Int'
          },
          {
            id: 'm2',
            name: 'exemplaire',
            fieldType: 'Int'
          },
          {
            id: 'm3',
            name: 'lecteur',
            fieldType: 'String'
          }
        ]
      }
    ];
  };

  pageLayout = function() {
    return {
      layout: {
        direction: 'vertical',
        children: [
          {
            widget: {
              id: 'livres',
              space: 'livres',
              columns: ['titre',
          'auteur_nom']
            }
          },
          {
            widget: {
              id: 'ex',
              space: 'exemplaires',
              columns: ['cote',
          'emprunteur'],
              depends_on: {
                widget: 'livres',
                field: 'livre',
                from_field: 'id'
              }
            }
          },
          {
            widget: {
              id: 'em',
              space: 'emprunts',
              columns: ['lecteur'],
              depends_on: {
                widget: 'ex',
                field: 'exemplaire',
                from_field: 'id'
              }
            }
          }
        ]
      }
    };
  };

  DEFAULT_ROWS = {
    livres: [
      {
        id: 1,
        titre: 'L1',
        auteur_nom: 'A'
      },
      {
        id: 2,
        titre: 'L2',
        auteur_nom: 'B'
      }
    ],
    exemplaires: [
      {
        id: 10,
        livre: 1,
        cote: 'C1',
        emprunteur: 'X'
      },
      {
        id: 11,
        livre: 1,
        cote: 'C2',
        emprunteur: 'Y'
      },
      {
        id: 12,
        livre: 2,
        cote: 'C3',
        emprunteur: 'Z'
      }
    ],
    emprunts: [
      {
        id: 100,
        exemplaire: 10,
        lecteur: 'U'
      },
      {
        id: 101,
        exemplaire: 11,
        lecteur: 'V'
      },
      {
        id: 102,
        exemplaire: 12,
        lecteur: 'W'
      }
    ]
  };

  makeContainer = function() {
    return global.document.createElement('div');
  };

  yamlJSON = function(obj) {
    return JSON.stringify(obj);
  };

  flush = function() {
    return new Promise(function(resolve) {
      return setTimeout(resolve, 0);
    });
  };

  mountPage = function(rows, layout) {
    var cv;
    SEED_ROWS.livres = rows.livres || [];
    SEED_ROWS.exemplaires = rows.exemplaires || [];
    SEED_ROWS.emprunts = rows.emprunts || [];
    cv = new CV(makeContainer(), yamlJSON(layout || pageLayout()), makeSpaces());
    cv.mount();
    return flush().then(function() {
      return cv;
    });
  };

  names = function(dv) {
    return dv.space.fields.map(function(f) {
      return f.name;
    });
  };

  // ---------------------------------------------------------------------------
  describe('T21 — link fields are always loaded', function() {
    it('(a) source widget loads the dependent from_field as a hidden field', function() {
      return mountPage(DEFAULT_ROWS).then(function(cv) {
        var dv, idField, titre;
        dv = cv._widgetsById['livres'].dataView;
        assert(names(dv).indexOf('id') >= 0, 'id must be loaded into the source rows');
        idField = dv.space.fields.find(function(f) {
          return f.name === 'id';
        });
        assert(idField.hidden === true, 'id must be marked hidden');
        titre = dv.space.fields.find(function(f) {
          return f.name === 'titre';
        });
        return assert(!titre.hidden, 'titre (in columns) must stay visible');
      });
    });
    it('(b) dependent widget loads its own depends_on.field as a hidden field', function() {
      return mountPage(DEFAULT_ROWS).then(function(cv) {
        var dv, idf, lf;
        dv = cv._widgetsById['ex'].dataView;
        assert(names(dv).indexOf('livre') >= 0, 'livre must be loaded');
        lf = dv.space.fields.find(function(f) {
          return f.name === 'livre';
        });
        assert(lf.hidden === true, 'livre must be hidden');
        idf = dv.space.fields.find(function(f) {
          return f.name === 'id';
        });
        return assert(idf && idf.hidden === true, 'id (from_field of em) must be hidden');
      });
    });
    it('(c) a link field already in columns stays visible and is not duplicated', function() {
      var layout;
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              widget: {
                id: 'livres',
                space: 'livres',
                columns: ['titre']
              }
            },
            {
              widget: {
                id: 'ex',
                space: 'exemplaires',
                columns: ['livre',
            'cote'],
                depends_on: {
                  widget: 'livres',
                  field: 'livre',
                  from_field: 'id'
                }
              }
            }
          ]
        }
      };
      return mountPage(DEFAULT_ROWS, layout).then(function(cv) {
        var dv, livres;
        dv = cv._widgetsById['ex'].dataView;
        livres = dv.space.fields.filter(function(f) {
          return f.name === 'livre';
        });
        eq(livres.length, 1);
        return assert(!livres[0].hidden, 'livre in columns must stay visible');
      });
    });
    it('(d) realistic rows (only sp.fields) cascade-filter correctly', function() {
      return mountPage(DEFAULT_ROWS).then(function(cv) {
        var em, ex;
        ex = cv._widgetsById['ex'].dataView;
        eq(ex.filter.field, 'livre');
        eq(ex.filter.value, '1');
        eq(ex._currentData.length, 3); // rows 10, 11 + sentinel
        em = cv._widgetsById['em'].dataView;
        eq(em.filter.value, '10');
        return eq(em._currentData.length, 2); // row 100 + sentinel
      });
    });
    it('(e) a link field missing from the space warns and does not crash', function() {
      var layout, oldWarn, warns;
      warns = [];
      oldWarn = console.warn;
      console.warn = function(m) {
        return warns.push(String(m));
      };
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              widget: {
                id: 'livres',
                space: 'livres',
                columns: ['titre']
              }
            },
            {
              widget: {
                id: 'ex',
                space: 'exemplaires',
                columns: ['cote'],
                depends_on: {
                  widget: 'livres',
                  field: 'inexistant',
                  from_field: 'id'
                }
              }
            }
          ]
        }
      };
      return mountPage(DEFAULT_ROWS, layout).then(function(cv) {
        console.warn = oldWarn;
        assert(cv._widgetsById['ex'].dataView != null, 'dependent must still mount');
        return assert(warns.some(function(w) {
          return w.indexOf('inexistant') >= 0;
        }), 'expected a warning naming the field');
      });
    });
    it('(f) an undefined link value yields none, never the string undefined', function() {
      var oldWarn, warns;
      warns = [];
      oldWarn = console.warn;
      console.warn = function(m) {
        return warns.push(String(m));
      };
      return mountPage(DEFAULT_ROWS).then(function(cv) {
        var entry;
        entry = cv._widgetsById['ex'];
        console.warn = oldWarn;
        cv._applyDependencySelection(entry, entry.node.depends_on, {
          titre: 'no id'
        });
        assert(entry.dataView.filter.none === true, 'filter must be none');
        assert(entry.dataView.filter.value !== 'undefined', 'never the string undefined');
        eq(entry.dataView._currentData.length, 0);
        return assert(warns.some(function(w) {
          return w.indexOf('undefined') < 0 && w.indexOf("'id'") >= 0;
        }), 'expected a warning naming the missing field');
      });
    });
    return it('(g) a widget without columns or dependency is unchanged', function() {
      var layout;
      layout = {
        layout: {
          widget: {
            id: 'plain',
            space: 'emprunts'
          }
        }
      };
      return mountPage(DEFAULT_ROWS, layout).then(function(cv) {
        var dv;
        dv = cv._widgetsById['plain'].dataView;
        eq(dv.space.fields.length, 3);
        return assert(!(dv.space.fields.some(function(f) {
          return f.hidden;
        })), 'no field must be hidden');
      });
    });
  });

  summary();

}).call(this);
