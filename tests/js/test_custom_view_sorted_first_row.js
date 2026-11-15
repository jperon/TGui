(function() {
  // tests/js/test_custom_view_sorted_first_row.coffee
  // `_firstRow` sert à la cascade depends_on initiale (widget racine → premier
  // widget dépendant). L'index venait de `_currentData` (ordre de chargement) alors
  // que la grille peut être triée : il pouvait désigner la sentinelle `__isNew` et
  // interrompre la cascade. On exige la première ligne VISUELLE non sentinelle.
  var CV, DEFAULT_ROWS, FakeGrid, RealDataView, SEED_ROWS, TestDataView, assert, describe, eq, flush, it, layout, makeContainer, makeSpaces, mountSorted, summary, yamlJSON;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    }
  };

  FakeGrid = class FakeGrid {
    constructor() {
      this._data = [];
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
      var base, name;
      return ((base = this._classes)[name = String(key)] != null ? base[name] : base[name] = {})[cls] = true;
    }

    removeRowClassName(key, cls) {
      var ref;
      return (ref = this._classes[String(key)]) != null ? delete ref[cls] : void 0;
    }

    on() {}

    getCheckedRowKeys() {
      return [];
    }

    getFocusedCell() {
      return null;
    }

    destroy() {}

    refreshLayout() {}

  };

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
      return Promise.resolve();
    }

  };

  require('../../frontend/src/views/custom_view');

  require('../../frontend/src/views/custom_view_plugins');

  require('../../frontend/src/views/custom_view_aggregate');

  require('../../frontend/src/views/custom_view_resize');

  CV = global.window.CustomView;

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
      }
    ];
  };

  layout = function() {
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
          }
        ]
      }
    };
  };

  // Monte la page puis simule un tri visuel : la sentinelle remonte en tête et
  // l'ordre d'affichage n'est plus celui de `_currentData`.
  mountSorted = function(rows) {
    var cv;
    SEED_ROWS.A = rows.A;
    SEED_ROWS.B = rows.B;
    cv = new CV(makeContainer(), yamlJSON(layout()), makeSpaces());
    cv.mount();
    return flush().then(function() {
      var A, data, others, r, reversed, rows0, sentinel;
      A = cv._widgetsById['A'];
      data = A.dataView._grid.getData();
      sentinel = data.find(function(r) {
        return r.__isNew;
      });
      others = (function() {
        var j, len, results;
        results = [];
        for (j = 0, len = data.length; j < len; j++) {
          r = data[j];
          if (!r.__isNew) {
            results.push(r);
          }
        }
        return results;
      })();
      reversed = others.slice().reverse();
      // rowKey recalculé comme le ferait un resetData trié.
      rows0 = [sentinel].concat(reversed);
      rows0.forEach(function(r, i) {
        return r.rowKey = i;
      });
      A.dataView._grid._data = rows0;
      A.dataView._currentData = others.concat([sentinel]); // ordre de chargement
      return cv;
    });
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
        id: 20,
        a_id: 2,
        nom: 'B2'
      }
    ]
  };

  describe('CustomView._firstRow — tri', function() {
    it('ignore la sentinelle et prend la première ligne visuelle triée', function() {
      return mountSorted(DEFAULT_ROWS).then(function(cv) {
        var A, first, row;
        A = cv._widgetsById['A'];
        first = cv._firstRow(A);
        assert(first != null, 'une première ligne est attendue');
        row = A.dataView._grid.getRow(first.rowKey);
        assert(row != null, 'rowKey résolue');
        assert(!row.__isNew, 'la sentinelle ne doit jamais être la première ligne');
        return eq(row.nom, 'A2'); // première ligne visuelle (ordre inversé)
      });
    });
    return it('la cascade initiale repart de cette première ligne visuelle', function() {
      return mountSorted(DEFAULT_ROWS).then(function(cv) {
        var A, B;
        A = cv._widgetsById['A'];
        B = cv._widgetsById['B'];
        cv._initializeCascade();
        assert(A.dataView._activeRowKey != null, 'A doit avoir une ligne active');
        return eq(B.dataView.filter.value, '2'); // dépend de A2, pas de la sentinelle
      });
    });
  });

  summary();

}).call(this);
