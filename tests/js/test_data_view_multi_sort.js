(function() {
  // tests/js/test_data_view_multi_sort.coffee
  // Tri multicritère du DataView : hiérarchie réelle sur les données (le premier
  // critère décide, les égalités sont départagées par le suivant), persistance
  // après resetData, et Maj+clic sur un en-tête (ajout/inversion sans effacer).

  // La grille factice reproduit le comparateur et l'état de tri de Toast UI Grid :
  // `sort(col, asc, multiple)` ajoute un critère quand `multiple` est vrai.
  var DV, MultiSortGrid, ROWS, assert, compare, deepEq, describe, eq, it, makeSpace, makeView, pairs, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // TdbHtml.escape is required by data_view._escapeHtml / _formatFormulaError
  require('../../frontend/src/html_escape');

  global.GQL = {
    query: function() {
      return Promise.resolve({});
    },
    mutate: function() {
      return Promise.resolve({});
    }
  };

  compare = function(a, b) {
    var ca, cb, isBlank;
    isBlank = function(v) {
      return (v == null) || v === '';
    };
    ca = isBlank(a) ? null : (isNaN(Number(a)) ? String(a) : Number(a));
    cb = isBlank(b) ? null : (isNaN(Number(b)) ? String(b) : Number(b));
    if (ca === null && cb !== null) {
      return -1;
    }
    if (ca !== null && cb === null) {
      return 1;
    }
    if (ca === cb) {
      return 0;
    }
    if (ca < cb) {
      return -1;
    } else {
      return 1;
    }
  };

  MultiSortGrid = class MultiSortGrid {
    constructor() {
      this._compare = this._compare.bind(this);
      this._data = [];
      this._classes = {};
      this._sortState = {
        columns: [
          {
            columnName: 'sortKey',
            ascending: true
          }
        ]
      };
    }

    resetData(rows, options = {}) {
      var state;
      rows = rows || [];
      rows.forEach(function(row, i) {
        if (row.rowKey == null) {
          return row.rowKey = i;
        }
      });
      this._data = rows;
      state = options.sortState;
      // resetData remet le tri à zéro, sauf `sortState` explicite : comme Toast UI
      // Grid, il ne fait alors que réafficher les flèches (aucun réordonnancement).
      if (state) {
        if (state.multiple && this._sortState.columns[0].columnName !== 'sortKey') {
          return this._sortState.columns[0].ascending = state.ascending;
        } else {
          return this._sortState = {
            columns: [
              {
                columnName: state.columnName,
                ascending: state.ascending
              }
            ]
          };
        }
      } else {
        return this._sortState = {
          columns: [
            {
              columnName: 'sortKey',
              ascending: true
            }
          ]
        };
      }
    }

    unsort() {
      return this._sortState = {
        columns: [
          {
            columnName: 'sortKey',
            ascending: true
          }
        ]
      };
    }

    sort(columnName, ascending, multiple) {
      var c, column, initial, kept;
      column = {
        columnName: columnName,
        ascending: ascending
      };
      initial = this._sortState.columns[0].columnName === 'sortKey';
      if (multiple && !initial) {
        kept = (function() {
          var j, len, ref, results;
          ref = this._sortState.columns;
          results = [];
          for (j = 0, len = ref.length; j < len; j++) {
            c = ref[j];
            if (c.columnName !== columnName) {
              results.push(c);
            }
          }
          return results;
        }).call(this);
        kept.push(column);
        this._sortState = {
          columns: kept
        };
      } else {
        this._sortState = {
          columns: [column]
        };
      }
      return this._data = this._data.slice().sort(this._compare);
    }

    _compare(a, b) {
      var column, j, len, ref, result;
      ref = this._sortState.columns;
      for (j = 0, len = ref.length; j < len; j++) {
        column = ref[j];
        if (!(column.columnName !== 'sortKey')) {
          continue;
        }
        result = compare(a[column.columnName], b[column.columnName]);
        if (result === 0) {
          continue;
        }
        if (column.ascending) {
          return result;
        } else {
          return -result;
        }
      }
      return 0;
    }

    getSortState() {
      var c;
      return {
        columns: (function() {
          var j, len, ref, results;
          ref = this._sortState.columns;
          results = [];
          for (j = 0, len = ref.length; j < len; j++) {
            c = ref[j];
            results.push(Object.assign({}, c));
          }
          return results;
        }).call(this)
      };
    }

    getData() {
      return this._data;
    }

    getRowAt(i) {
      return this._data[i] || null;
    }

    getRow(key) {
      return this._data.find(function(row) {
        return row.rowKey === Number(key);
      }) || null;
    }

    getColumns() {
      return [];
    }

    addRowClassName(key, cls) {
      var base, name;
      return ((base = this._classes)[name = String(key)] != null ? base[name] : base[name] = {})[cls] = true;
    }

    removeRowClassName(key, cls) {
      var ref;
      return (ref = this._classes[String(key)]) != null ? delete ref[cls] : void 0;
    }

    getCheckedRowKeys() {
      return [];
    }

    getFocusedCell() {
      return null;
    }

    destroy() {}

  };

  global.tui = {
    Grid: MultiSortGrid
  };

  require('../../frontend/src/views/fk_search_editor');

  require('../../frontend/src/views/data_view');

  require('../../frontend/src/views/data_view_helpers');

  DV = global.window.DataView;

  makeSpace = function() {
    return {
      id: 'sp1',
      name: 'multi_sort',
      fields: [
        {
          id: 'f1',
          name: 'groupe',
          fieldType: 'Str',
          formula: null,
          triggerFields: null
        },
        {
          id: 'f2',
          name: 'nom',
          fieldType: 'Str',
          formula: null,
          triggerFields: null
        }
      ]
    };
  };

  ROWS = [
    {
      __rowId: 'r1',
      groupe: 'B',
      nom: 'a'
    },
    {
      __rowId: 'r2',
      groupe: 'A',
      nom: 'b'
    },
    {
      __rowId: 'r3',
      groupe: 'B',
      nom: 'b'
    },
    {
      __rowId: 'r4',
      groupe: 'A',
      nom: 'a'
    }
  ];

  // Ordonnées (groupe, nom), sentinelle exclue.
  pairs = function(grid) {
    var j, len, ref, results, row;
    ref = grid.getData();
    results = [];
    for (j = 0, len = ref.length; j < len; j++) {
      row = ref[j];
      if (!row.__isNew) {
        results.push([row.groupe, row.nom]);
      }
    }
    return results;
  };

  makeView = function(rows = ROWS) {
    var dv, grid;
    dv = new DV(global.document.createElement('div'), makeSpace());
    grid = new MultiSortGrid();
    dv._grid = grid;
    dv._rows = rows;
    // Grille déjà peuplée (données chargées), comme en production avant un tri.
    dv._applyData();
    return {dv, grid};
  };

  describe('DataView — tri multicritère hiérarchique', function() {
    it('applique les critères dans l’ordre : le 1er décide, le 2e départage', function() {
      var dv, grid;
      ({dv, grid} = makeView());
      dv._sortState = [
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: true
        }
      ];
      dv._applyData();
      return deepEq(pairs(grid), [['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]);
    });
    it('un autre ordre de priorité change réellement l’ordre des lignes', function() {
      var dv, grid;
      ({dv, grid} = makeView());
      dv._sortState = [
        {
          column: 'nom',
          ascending: true
        },
        {
          column: 'groupe',
          ascending: true
        }
      ];
      dv._applyData();
      return deepEq(pairs(grid), [['A', 'a'], ['B', 'a'], ['A', 'b'], ['B', 'b']]);
    });
    it('conserve les deux critères après un resetData (rechargement)', function() {
      var c, dv, grid, names, state;
      ({dv, grid} = makeView());
      dv.applySortEntries([
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: false
        }
      ]);
      dv._applyData();
      deepEq(dv.getSortEntries(), [
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: false
        }
      ]);
      state = grid.getSortState();
      names = (function() {
        var j, len, ref, results;
        ref = state.columns;
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          c = ref[j];
          if (c.columnName !== 'sortKey') {
            results.push(c.columnName);
          }
        }
        return results;
      })();
      deepEq(names, ['groupe', 'nom']);
      return deepEq(pairs(grid), [['A', 'b'], ['A', 'a'], ['B', 'b'], ['B', 'a']]);
    });
    return it('garde la sentinelle en dernier malgré le tri multiple', function() {
      var data, dv, grid, ref;
      ({dv, grid} = makeView());
      dv.applySortEntries([
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: true
        }
      ]);
      data = grid.getData();
      assert((ref = data[data.length - 1]) != null ? ref.__isNew : void 0, 'la sentinelle doit rester la dernière ligne');
      return eq(data.length, 5);
    });
  });

  describe('DataView — Maj+clic sur un en-tête', function() {
    it('ajoute un critère secondaire sans effacer le premier', function() {
      var changes, dv, entries, grid;
      ({dv, grid} = makeView());
      dv.applySortEntries([
        {
          column: 'groupe',
          ascending: true
        }
      ]);
      changes = 0;
      dv._onSortChanged = function() {
        return changes++;
      };
      entries = dv.sortWithShiftClick('nom');
      deepEq(entries, [
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: true
        }
      ]);
      deepEq(dv.getSortEntries(), entries);
      eq(changes, 1);
      return deepEq(pairs(grid), [['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]);
    });
    it('inverse le sens d’un critère existant sans changer sa priorité', function() {
      var dv, entries, grid;
      ({dv, grid} = makeView());
      dv.applySortEntries([
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: true
        }
      ]);
      entries = dv.sortWithShiftClick('nom');
      deepEq(entries, [
        {
          column: 'groupe',
          ascending: true
        },
        {
          column: 'nom',
          ascending: false
        }
      ]);
      return deepEq(pairs(grid), [['A', 'b'], ['A', 'a'], ['B', 'b'], ['B', 'a']]);
    });
    return it('ignore un nom de colonne vide', function() {
      var dv;
      ({dv} = makeView());
      dv.applySortEntries([
        {
          column: 'groupe',
          ascending: true
        }
      ]);
      return deepEq(dv.sortWithShiftClick(null), [
        {
          column: 'groupe',
          ascending: true
        }
      ]);
    });
  });

  summary();

}).call(this);
