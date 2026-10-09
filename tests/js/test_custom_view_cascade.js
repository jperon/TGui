(function() {
  // tests/js/test_custom_view_cascade.coffee — cascade selection of dependent widgets.

  // Three data widgets A -> B -> C (B depends_on A, C depends_on B). The real
  // DataView filtering / active-row logic (data_view.js + data_view_helpers.js) is
  // reused through a small subclass that injects seeded rows and a fake tui.Grid,
  // so the CustomView cascade is what is under test.
  var CV, DEFAULT_ROWS, FakeGrid, RealDataView, SEED_ROWS, TestDataView, abcLayout, assert, deepEq, describe, eq, flush, it, makeContainer, makeSpaces, mountCascade, summary, yamlJSON;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

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

  // --- load the real DataView, then subclass it for the test -------------------
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
      this._testRows = (SEED_ROWS[space.name] || []).slice();
    }

    mount() {
      this._rows = this._testRows;
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

  // --- helpers ----------------------------------------------------------------
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

  makeSpaces = function() {
    return [
      {
        id: 'a',
        name: 'A',
        fields: [
          {
            id: 'af',
            name: 'id',
            fieldType: 'Int'
          },
          {
            id: 'an',
            name: 'nom',
            fieldType: 'String'
          }
        ]
      },
      {
        id: 'b',
        name: 'B',
        fields: [
          {
            id: 'bf',
            name: 'id',
            fieldType: 'Int'
          },
          {
            id: 'ba',
            name: 'a_id',
            fieldType: 'Int'
          },
          {
            id: 'bn',
            name: 'nom',
            fieldType: 'String'
          }
        ]
      },
      {
        id: 'c',
        name: 'C',
        fields: [
          {
            id: 'cf',
            name: 'id',
            fieldType: 'Int'
          },
          {
            id: 'cb',
            name: 'b_id',
            fieldType: 'Int'
          },
          {
            id: 'cn',
            name: 'nom',
            fieldType: 'String'
          }
        ]
      }
    ];
  };

  abcLayout = function() {
    return {
      layout: {
        direction: 'vertical',
        children: [
          {
            widget: {
              id: 'A',
              space: 'A'
            }
          },
          {
            widget: {
              id: 'B',
              space: 'B',
              depends_on: {
                widget: 'A',
                field: 'a_id',
                from_field: 'id'
              }
            }
          },
          {
            widget: {
              id: 'C',
              space: 'C',
              depends_on: {
                widget: 'B',
                field: 'b_id',
                from_field: 'id'
              }
            }
          }
        ]
      }
    };
  };

  DEFAULT_ROWS = {
    A: [
      {
        id: 1,
        nom: 'A1'
      },
      {
        id: 2,
        nom: 'A2'
      }
    ],
    B: [
      {
        id: 10,
        a_id: 1,
        nom: 'B1'
      },
      {
        id: 11,
        a_id: 1,
        nom: 'B2'
      },
      {
        id: 12,
        a_id: 2,
        nom: 'B3'
      }
    ],
    C: [
      {
        id: 100,
        b_id: 10,
        nom: 'C1'
      },
      {
        id: 101,
        b_id: 11,
        nom: 'C2'
      },
      {
        id: 102,
        b_id: 12,
        nom: 'C3'
      }
    ]
  };

  mountCascade = function(rows, layout) {
    var cv;
    SEED_ROWS.A = rows.A || [];
    SEED_ROWS.B = rows.B || [];
    SEED_ROWS.C = rows.C || [];
    cv = new CV(makeContainer(), yamlJSON(layout || abcLayout()), makeSpaces());
    cv.mount();
    return flush().then(function() {
      return cv;
    });
  };

  // ---------------------------------------------------------------------------
  describe('CustomView — cascade depends_on', function() {
    it('a) selecting a row in A filters B and cascades to C', function() {
      return mountCascade(DEFAULT_ROWS).then(function(cv) {
        var A, B, C;
        A = cv._widgetsById['A'];
        B = cv._widgetsById['B'];
        C = cv._widgetsById['C'];
        A.dataView._grid.emit('click', {
          rowKey: 1 // A id = 2
        });
        eq(B.dataView.filter.field, 'a_id');
        eq(B.dataView.filter.value, '2');
        eq(B.dataView._currentData.length, 2); // B3 + sentinel
        assert(B.dataView._activeRowKey === 0, 'B first row must be active');
        eq(C.dataView.filter.field, 'b_id');
        eq(C.dataView.filter.value, '12');
        return assert(C.dataView._activeRowKey === 0, 'C first row must be active');
      });
    });
    it('b) empty dependent grid -> no active row, descendants show zero rows', function() {
      var rows;
      rows = {
        A: [
          {
            id: 1,
            nom: 'A1'
          },
          {
            id: 3,
            nom: 'A3'
          }
        ],
        B: [
          {
            id: 10,
            a_id: 1,
            nom: 'B1'
          }
        ],
        C: [
          {
            id: 100,
            b_id: 10,
            nom: 'C1'
          }
        ]
      };
      return mountCascade(rows).then(function(cv) {
        var A, B, C;
        A = cv._widgetsById['A'];
        B = cv._widgetsById['B'];
        C = cv._widgetsById['C'];
        A.dataView._grid.emit('click', {
          rowKey: 1 // A id = 3 -> no B
        });
        eq(B.dataView.filter.value, '3');
        assert(B.dataView._activeRowKey == null, 'B must have no active row');
        eq(C.dataView.filter.none, true);
        eq(C.dataView._currentData.length, 0);
        return assert(C.dataView._activeRowKey == null, 'C must have no active row');
      });
    });
    it('c) mount activates the first row of A and cascades down', function() {
      return mountCascade(DEFAULT_ROWS).then(function(cv) {
        var A, B, C;
        A = cv._widgetsById['A'];
        B = cv._widgetsById['B'];
        C = cv._widgetsById['C'];
        assert(A.dataView._activeRowKey === 0, 'A first row must be active');
        eq(B.dataView.filter.value, '1');
        assert(B.dataView._activeRowKey === 0, 'B first row must be active');
        eq(C.dataView.filter.value, '10');
        return assert(C.dataView._activeRowKey === 0, 'C first row must be active');
      });
    });
    it('c2) empty root -> dependents show zero rows', function() {
      return mountCascade({
        A: []
      }).then(function(cv) {
        var B, C;
        B = cv._widgetsById['B'];
        C = cv._widgetsById['C'];
        eq(B.dataView._currentData.length, 0);
        eq(C.dataView._currentData.length, 0);
        assert(B.dataView._activeRowKey == null, 'B must have no active row');
        return assert(C.dataView._activeRowKey == null, 'C must have no active row');
      });
    });
    it('d) clicking B changes C but never A', function() {
      return mountCascade(DEFAULT_ROWS).then(function(cv) {
        var A, B, C;
        A = cv._widgetsById['A'];
        B = cv._widgetsById['B'];
        C = cv._widgetsById['C'];
        B.dataView._grid.emit('click', {
          rowKey: 1 // B2 (id 11)
        });
        eq(A.dataView.filter, null);
        assert(A.dataView._activeRowKey === 0, 'A must be untouched');
        eq(B.dataView._activeRowKey, 1);
        eq(C.dataView.filter.value, '11');
        return assert(C.dataView._activeRowKey === 0);
      });
    });
    it('e) a depends_on cycle does not loop and warns', function() {
      var layout, oldWarn, rows, warns;
      rows = {
        A: [
          {
            id: 1,
            nom: 'A1'
          }
        ],
        B: [
          {
            id: 10,
            nom: 'B1'
          }
        ],
        C: []
      };
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              widget: {
                id: 'A',
                space: 'A',
                depends_on: {
                  widget: 'B',
                  field: 'x',
                  from_field: 'id'
                }
              }
            },
            {
              widget: {
                id: 'B',
                space: 'B',
                depends_on: {
                  widget: 'A',
                  field: 'a_id',
                  from_field: 'id'
                }
              }
            }
          ]
        }
      };
      warns = [];
      oldWarn = console.warn;
      console.warn = function(m) {
        return warns.push(m);
      };
      return mountCascade(rows, layout).then(function(cv) {
        var B;
        B = cv._widgetsById['B'];
        B.dataView._grid.emit('click', {
          rowKey: 0
        });
        console.warn = oldWarn;
        return assert(warns.some(function(w) {
          return /cycle/.test(String(w));
        }), 'expected a cycle warning');
      });
    });
    it('f) only one row is active per grid', function() {
      return mountCascade(DEFAULT_ROWS).then(function(cv) {
        var A;
        A = cv._widgetsById['A'];
        A.dataView._grid.emit('click', {
          rowKey: 1
        });
        eq(A.dataView._grid.countRowsWithClass('tdb-selected-row'), 1);
        assert(A.dataView._grid.hasRowClass(1, 'tdb-selected-row'), 'new active row');
        return assert(!A.dataView._grid.hasRowClass(0, 'tdb-selected-row'), 'old row cleared');
      });
    });
    it('g) the sentinel row is never activated nor propagated', function() {
      return mountCascade(DEFAULT_ROWS).then(function(cv) {
        var A, C, sentinel, sentinelKey;
        A = cv._widgetsById['A'];
        C = cv._widgetsById['C'];
        sentinel = A.dataView._currentData[A.dataView._currentData.length - 1];
        assert(sentinel.__isNew, 'last row must be the sentinel');
        sentinelKey = A.dataView._grid.getRowAt(A.dataView._currentData.length - 1).rowKey;
        cv._selectRow(A, sentinelKey);
        assert(!A.dataView._grid.hasRowClass(sentinelKey, 'tdb-selected-row'), 'sentinel must not be active');
        return assert(C.dataView._activeRowKey === 0, 'C unchanged');
      });
    });
    return it('i) setFilter without none behaves as before', function() {
      return mountCascade(DEFAULT_ROWS).then(function(cv) {
        var B;
        B = cv._widgetsById['B'];
        B.dataView.setFilter({
          field: 'a_id',
          value: '2'
        });
        eq(B.dataView._currentData.length, 2); // B3 + sentinel
        eq(B.dataView._currentData[0].nom, 'B3');
        return assert(B.dataView._currentData[1].__isNew);
      });
    });
  });

  describe('CustomView — plugin dependents are not auto-filled', function() {
    return it('h) a plugin widget depending on A receives no automatic selection', function() {
      var cv, layout, oldCreate, sent;
      global.window.CoffeeScript = {
        compile: function() {
          return "module.exports = function(api){}";
        }
      };
      global.window.pug = {
        compile: function() {
          return function() {
            return "<div>tpl</div>";
          };
        }
      };
      global.WidgetPlugins = {
        getByName: function() {
          var plugin, thenable;
          plugin = {
            id: 'p',
            name: 'sample_plugin',
            scriptLanguage: 'coffeescript',
            templateLanguage: 'pug',
            scriptCode: '',
            templateCode: ''
          };
          thenable = {
            then: function(cb) {
              var e, err;
              err = null;
              try {
                cb(plugin);
              } catch (error) {
                e = error;
                err = e;
              }
              return {
                catch: function(onErr) {
                  if (err) {
                    return onErr(err);
                  }
                }
              };
            }
          };
          return thenable;
        }
      };
      global.window.addEventListener = function() {};
      global.window.removeEventListener = function() {};
      oldCreate = global.document.createElement;
      global.document.createElement = function(tag) {
        var el;
        el = oldCreate(tag);
        if (tag === 'iframe') {
          if (el.setAttribute == null) {
            el.setAttribute = function() {};
          }
          el.contentWindow = {
            postMessage: function() {}
          };
        }
        return el;
      };
      layout = {
        layout: {
          direction: 'horizontal',
          children: [
            {
              widget: {
                id: 'A',
                space: 'A'
              }
            },
            {
              widget: {
                id: 'P',
                type: 'sample_plugin',
                depends_on: {
                  widget: 'A',
                  field: 'a_id',
                  from_field: 'id'
                }
              }
            }
          ]
        }
      };
      SEED_ROWS.A = DEFAULT_ROWS.A.slice();
      SEED_ROWS.B = [];
      SEED_ROWS.C = [];
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      sent = [];
      cv._sendPluginMessage = function(id, msg) {
        return sent.push({id, msg});
      };
      cv.mount();
      return flush().then(function() {
        var A, ref;
        A = cv._widgetsById['A'];
        if ((A != null ? (ref = A.dataView) != null ? ref._grid : void 0 : void 0) != null) {
          A.dataView._grid.emit('click', {
            rowKey: 1
          });
        }
        eq(sent.length, 0);
        return global.document.createElement = oldCreate;
      });
    });
  });

  summary();

}).call(this);
