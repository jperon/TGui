(function() {
  // tests/js/test_data_view_sentinel_sort.coffee
  // La ligne sentinelle `__isNew` (saisie d'un nouvel enregistrement) doit rester
  // la dernière ligne VISUELLE, même quand un tri est réappliqué après resetData
  // (préréglage de vue, tri manuel mémorisé). Toast UI Grid trie toutes les lignes,
  // sentinelle comprise : sans correctif, la sentinelle remonte au milieu et la
  // classe `tdb-new-row` atterrit sur un vrai enregistrement.
  var DV, SortGrid, VISUAL_ORDER, assert, compare, container, describe, eq, fs, it, makeSpace, makeView, path, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  fs = require('fs');

  path = require('path');

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

  // Grille factice qui trie réellement : reproduit le comparateur par défaut de
  // Toast UI Grid (les valeurs vides passent avant les autres en ordre croissant).
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

  SortGrid = class SortGrid {
    constructor() {
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
      rows = rows || [];
      rows.forEach(function(row, i) {
        if (row.rowKey == null) {
          return row.rowKey = i;
        }
      });
      this._data = rows;
      // resetData remet le tri à son état initial, sauf `sortState` explicite.
      if (options.sortState) {
        return this._sortState = {
          columns: [options.sortState]
        };
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

    sort(columnName, ascending) {
      this._sortState = {
        columns: [{columnName, ascending}]
      };
      return this._data = this._data.slice().sort(function(a, b) {
        var res;
        res = compare(a[columnName], b[columnName]);
        if (ascending) {
          return res;
        } else {
          return -res;
        }
      });
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

    // helpers de test
    hasClass(key, cls) {
      var ref;
      return !!((ref = this._classes[String(key)]) != null ? ref[cls] : void 0);
    }

    keyFor(predicate) {
      var row;
      row = this._data.find(predicate);
      return row != null ? row.rowKey : void 0;
    }

    resetCalls() {
      return this._resetCalls || [];
    }

  };

  global.tui = {
    Grid: SortGrid
  };

  require('../../frontend/src/views/fk_search_editor');

  require('../../frontend/src/views/data_view');

  require('../../frontend/src/views/data_view_helpers');

  DV = global.window.DataView;

  makeSpace = function() {
    return {
      id: 'sp1',
      name: 'test_space',
      fields: [
        {
          id: 'f1',
          name: 'nom',
          fieldType: 'Str',
          formula: null,
          triggerFields: null
        },
        {
          id: 'f2',
          name: 'age',
          fieldType: 'Int',
          formula: null,
          triggerFields: null
        }
      ]
    };
  };

  container = function() {
    return global.document.createElement('div');
  };

  // DataView prête à afficher, sans mount() (grille fournie par le test).
  makeView = function(rows) {
    var dv, grid;
    dv = new DV(container(), makeSpace());
    grid = new SortGrid();
    dv._grid = grid;
    dv._rows = rows;
    return {dv, grid};
  };

  VISUAL_ORDER = function(grid) {
    var j, len, ref, results, row;
    ref = grid.getData();
    results = [];
    for (j = 0, len = ref.length; j < len; j++) {
      row = ref[j];
      results.push(row.__rowId || 'sentinel');
    }
    return results;
  };

  describe('DataView — sentinelle et tri', function() {
    it('reste la dernière ligne visuelle après réapplication du tri ascendant', function() {
      var dv, grid, order;
      ({dv, grid} = makeView([
        {
          __rowId: 'r1',
          nom: 'Zoe',
          age: 40
        },
        {
          __rowId: 'r2',
          nom: 'Alice',
          age: 20
        }
      ]));
      dv._sortState = [
        {
          column: 'nom',
          ascending: true
        }
      ];
      dv._applyData();
      order = VISUAL_ORDER(grid);
      eq(order[order.length - 1], 'sentinel');
      // Tri effectif des vraies lignes (contrôle : le correctif ne casse pas le tri).
      eq(order[0], 'r2'); // Alice
      return eq(order[1], 'r1'); // Zoe
    });
    it('marque la sentinelle (et elle seule) avec tdb-new-row', function() {
      var dv, grid, j, len, ref, results, row, sentinelKey;
      ({dv, grid} = makeView([
        {
          __rowId: 'r1',
          nom: 'Zoe'
        },
        {
          __rowId: 'r2',
          nom: 'Alice'
        }
      ]));
      dv._sortState = [
        {
          column: 'nom',
          ascending: true
        }
      ];
      dv._applyData();
      sentinelKey = grid.keyFor(function(r) {
        return r.__isNew;
      });
      assert(sentinelKey != null, 'la sentinelle doit être présente dans la grille');
      assert(grid.hasClass(sentinelKey, 'tdb-new-row'), 'la sentinelle doit porter tdb-new-row');
      ref = grid.getData();
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        row = ref[j];
        if (!row.__isNew) {
          results.push(assert(!grid.hasClass(row.rowKey, 'tdb-new-row'), `la ligne ${row.__rowId} ne doit pas porter tdb-new-row`));
        }
      }
      return results;
    });
    it('reste en bas après un rechargement du filtre, tri inchangé', function() {
      var dv, grid, order;
      ({dv, grid} = makeView([
        {
          __rowId: 'r1',
          nom: 'Zoe'
        },
        {
          __rowId: 'r2',
          nom: 'Alice'
        }
      ]));
      dv._sortState = [
        {
          column: 'nom',
          ascending: true
        }
      ];
      dv._applyData();
      // Filtre modifié : _applyData repart de zéro puis réapplique le tri.
      dv.filter = {
        field: 'nom',
        value: 'Alice'
      };
      dv._applyData();
      order = VISUAL_ORDER(grid);
      eq(order.length, 2); // Alice + sentinelle
      eq(order[order.length - 1], 'sentinel');
      return eq(order[0], 'r2');
    });
    it('sans tri, la sentinelle reste la dernière ligne', function() {
      var dv, grid, order;
      ({dv, grid} = makeView([
        {
          __rowId: 'r1',
          nom: 'Zoe'
        },
        {
          __rowId: 'r2',
          nom: 'Alice'
        }
      ]));
      dv._applyData();
      order = VISUAL_ORDER(grid);
      return eq(order[order.length - 1], 'sentinel');
    });
    return it('conserve la ligne active après un tri manuel', function() {
      var active, dv, grid, order;
      ({dv, grid} = makeView([
        {
          __rowId: 'r1',
          nom: 'Zoe'
        },
        {
          __rowId: 'r2',
          nom: 'Alice'
        }
      ]));
      dv._applyData();
      dv.setActiveRow(1); // Alice
      grid.sort('nom', true); // clic sur l'en-tête : la grille trie
      dv._onGridSortChanged(); // afterSort -> mémorise puis remet la sentinelle en bas
      assert(dv._activeRowKey != null, 'une ligne doit rester active');
      active = grid.getRow(dv._activeRowKey);
      eq(active.__rowId, 'r2');
      assert(!active.__isNew);
      assert(grid.hasClass(dv._activeRowKey, 'tdb-selected-row'));
      order = VISUAL_ORDER(grid);
      return eq(order[order.length - 1], 'sentinel');
    });
  });

  describe('app.css — style de la sentinelle', function() {
    var css;
    css = fs.readFileSync(path.join(__dirname, '../../frontend/css/app.css'), 'utf8');
    return it('stylise .tdb-new-row posé sur une cellule (Toast UI Grid) et sur la ligne', function() {
      var m, selectors;
      m = css.match(/(\.tdb-new-row[^{]*)\{([^}]*)\}/);
      assert(m, 'règle .tdb-new-row absente de app.css');
      selectors = m[1];
      assert(selectors.indexOf('.tdb-new-row,') !== -1 || /^\s*\.tdb-new-row\s*$/.test(selectors), `le sélecteur doit viser la cellule elle-même, got: ${selectors}`);
      assert(selectors.indexOf('.tdb-new-row td') !== -1, `le sélecteur descendant doit rester supporté, got: ${selectors}`);
      return assert(m[2].indexOf('opacity') !== -1, 'opacity absente de la règle');
    });
  });

  summary();

}).call(this);
