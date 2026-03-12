(function() {
  // tests/js/test_data_view.coffee — tests for DataView (data_view.js)
  // Tests pure logic (without mount/tui.Grid).
  var DV, assert, container, deepEq, describe, eq, it, makeSpace, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // Stubs required by data_view.js
  global.GQL = {
    query: function() {
      return Promise.resolve({});
    },
    mutate: function() {
      return Promise.resolve({});
    }
  };

  global.tui = {
    Grid: class {
      constructor(opts = {}) {
        this._data = [];
        this._columns = opts.columns || [];
      }

      resetData(d) {
        return this._data = d;
      }

      getData() {
        return this._data;
      }

      getColumns() {
        return this._columns;
      }

      getRowAt(i) {
        return this._data[i] || null;
      }

      addRowClassName() {}

      on() {}

      destroy() {}

      getIndexOfRow() {
        return 0;
      }

      getRowCount() {
        return this._data.length;
      }

      getFocusedCell() {
        return null;
      }

      getCheckedRowKeys() {
        return [];
      }

    }
  };

  require('../../frontend/src/views/data_view');

  DV = global.window.DataView;

  makeSpace = function(overrides = {}) {
    return {
      id: overrides.id || 'sp1',
      name: overrides.name || 'test_space',
      fields: overrides.fields || [
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
        },
        {
          id: 'f3',
          name: 'seq',
          fieldType: 'Sequence',
          formula: null,
          triggerFields: null
        }
      ]
    };
  };

  container = function() {
    return global.document.createElement('div');
  };

  // ---------------------------------------------------------------------------
  describe('DataView._sentinel', function() {
    it('produces a row with __isNew and all non-Sequence fields', function() {
      var dv, s;
      dv = new DV(container(), makeSpace());
      s = dv._sentinel();
      assert(s.__isNew, '__isNew missing');
      assert('nom' in s, 'nom missing');
      assert('age' in s, 'age missing');
      return assert(!('seq' in s), 'seq (Sequence) must not appear in sentinel');
    });
    it('uses defaultValues', function() {
      var dv, s;
      dv = new DV(container(), makeSpace());
      dv.setDefaultValues({
        nom: 'Alice'
      });
      s = dv._sentinel();
      eq(s.nom, 'Alice');
      return eq(s.age, ''); // not in defaults
    });
    return it('returns empty string for fields without default', function() {
      var dv, s;
      dv = new DV(container(), makeSpace());
      s = dv._sentinel();
      eq(s.nom, '');
      return eq(s.age, '');
    });
  });

  describe('DataView._lsKey', function() {
    return it('includes space id', function() {
      var dv;
      dv = new DV(container(), makeSpace({
        id: 'abc'
      }));
      return eq(dv._lsKey(), 'tdb_colwidths_abc');
    });
  });

  describe('DataView._loadColWidths', function() {
    it('returns {} when localStorage is empty', async function() {
      var dv, prefs;
      global.localStorage.clear();
      dv = new DV(container(), makeSpace());
      prefs = (await dv._loadColWidths());
      return deepEq(prefs, {});
    });
    it('parses JSON from localStorage', async function() {
      var dv, prefs;
      global.localStorage.setItem('tdb_colwidths_sp1', JSON.stringify({
        nom: 200
      }));
      dv = new DV(container(), makeSpace({
        id: 'sp1'
      }));
      prefs = (await dv._loadColWidths());
      return eq(prefs.nom, 200);
    });
    return it('returns {} on invalid JSON', async function() {
      var dv, prefs;
      global.localStorage.setItem('tdb_colwidths_sp1', 'not-json');
      dv = new DV(container(), makeSpace({
        id: 'sp1'
      }));
      prefs = (await dv._loadColWidths());
      return deepEq(prefs, {});
    });
  });

  describe('DataView.setDefaultValues', function() {
    it('stores values and reflects them in sentinel', function() {
      var dv;
      dv = new DV(container(), makeSpace());
      dv.setDefaultValues({
        age: '42'
      });
      return eq(dv._sentinel().age, '42');
    });
    return it('accepts null/undefined -> resets state', function() {
      var dv;
      dv = new DV(container(), makeSpace());
      dv.setDefaultValues({
        nom: 'Bob'
      });
      dv.setDefaultValues(null);
      return deepEq(dv._defaultValues, {});
    });
  });

  describe('DataView.setFilter + _applyData', function() {
    it('setFilter updates @filter', function() {
      var dv;
      dv = new DV(container(), makeSpace());
      dv.setFilter({
        field: 'age',
        value: '30'
      });
      eq(dv.filter.field, 'age');
      return eq(dv.filter.value, '30');
    });
    it('_applyData filters rows by field/value', function() {
      var dv, gridData, sp;
      sp = makeSpace();
      dv = new DV(container(), sp);
      // Mount a minimal mocked grid
      gridData = [];
      dv._grid = {
        resetData: function(d) {
          return gridData = d;
        },
        getRowAt: function(i) {
          return null;
        },
        addRowClassName: function() {}
      };
      dv._rows = [
        {
          __rowId: '1',
          nom: 'Alice',
          age: '30'
        },
        {
          __rowId: '2',
          nom: 'Bob',
          age: '25'
        },
        {
          __rowId: '3',
          nom: 'Carol',
          age: '30'
        }
      ];
      dv.filter = {
        field: 'age',
        value: '30'
      };
      dv._applyData();
      // sentinel excluded from assertion count, so total = 2 data + 1 sentinel
      eq(gridData.length, 3);
      assert(gridData[0].nom === 'Alice', 'first filtered row is incorrect');
      assert(gridData[1].nom === 'Carol', 'second filtered row is incorrect');
      return assert(gridData[2].__isNew, 'missing sentinel at end');
    });
    return it('_applyData without filter includes all rows', function() {
      var dv, gridData, sp;
      sp = makeSpace();
      dv = new DV(container(), sp);
      gridData = [];
      dv._grid = {
        resetData: function(d) {
          return gridData = d;
        },
        getRowAt: function() {
          return null;
        },
        addRowClassName: function() {}
      };
      dv._rows = [
        {
          __rowId: '1',
          nom: 'Alice'
        },
        {
          __rowId: '2',
          nom: 'Bob'
        }
      ];
      dv._applyData();
      return eq(gridData.length, 3); // 2 data + 1 sentinel
    });
  });

  describe('DataView formula error rendering state', function() {
    return it('_applyData marks cell when _repr_<field> contains an error', function() {
      var classes, dv, gridData, ref, ref1, ref2, row, sp;
      sp = makeSpace({
        fields: [
          {
            id: 'f1',
            name: 'nom',
            fieldType: 'String',
            formula: null,
            triggerFields: null
          }
        ]
      });
      dv = new DV(container(), sp);
      gridData = [];
      dv._grid = {
        resetData: function(d) {
          return gridData = d;
        },
        getRowAt: function() {
          return null;
        },
        addRowClassName: function() {}
      };
      dv._rows = [
        {
          __rowId: '1',
          nom: 'Hugo',
          _repr_nom: '[ERROR|Champ inconnu (nil)|attempt to index nil]'
        }
      ];
      dv._applyData();
      row = gridData[0];
      classes = ((ref = row._attributes) != null ? (ref1 = ref.className) != null ? (ref2 = ref1.column) != null ? ref2.nom : void 0 : void 0 : void 0) || [];
      return assert(classes.includes('cell-formula-error'), 'cell-formula-error missing');
    });
  });

  describe('DataView FK maps use _repr', function() {
    return it('_buildFkMaps prioritizes _repr for FK display', async function() {
      var dv, oldQuery, relations, sp;
      oldQuery = global.GQL.query;
      global.GQL.query = function(q, vars) {
        return Promise.resolve({
          records: {
            items: [
              {
                id: '1',
                data: JSON.stringify({
                  id: 1,
                  _repr: 'Hugo Victor'
                })
              },
              {
                id: '2',
                data: JSON.stringify({
                  id: 2,
                  _repr: 'Maupassant Guy'
                })
              }
            ]
          }
        });
      };
      sp = makeSpace({
        fields: [
          {
            id: 'bf1',
            name: 'auteur',
            fieldType: 'Relation',
            formula: null,
            triggerFields: null
          }
        ]
      });
      relations = [
        {
          fromFieldId: 'bf1',
          toSpaceId: 'authors-space',
          reprFormula: '@_repr'
        }
      ];
      dv = new DV(container(), sp, null, relations);
      await dv._buildFkMaps();
      eq(dv._fkMaps.auteur['1'], 'Hugo Victor');
      eq(dv._fkMaps.auteur['2'], 'Maupassant Guy');
      return global.GQL.query = oldQuery;
    });
  });

  describe('DataView editable columns formatter regression', function() {
    return it('FK and Boolean formatters do not return raw HTML', async function() {
      var boolCol, boolRenderedFalse, boolRenderedTrue, cols, dv, fkCol, fkRendered, ref, ref1, ref2, ref3, rels, sp;
      sp = makeSpace({
        fields: [
          {
            id: 'f1',
            name: 'auteur',
            fieldType: 'Relation',
            formula: null,
            triggerFields: null
          },
          {
            id: 'f2',
            name: 'disponible',
            fieldType: 'Boolean',
            formula: null,
            triggerFields: null
          }
        ]
      });
      rels = [
        {
          fromFieldId: 'f1',
          toSpaceId: 'authors-space',
          reprFormula: '@_repr'
        }
      ];
      dv = new DV(container(), sp, null, rels);
      dv._buildFkMaps = function() {
        this._fkMaps.auteur = {
          '1': 'Hugo Victor'
        };
        this._fkOptions.auteur = [
          {
            text: 'Hugo Victor',
            value: '1'
          }
        ];
        return Promise.resolve();
      };
      dv._loadColWidths = function() {
        return Promise.resolve({});
      };
      dv.load = function() {
        return Promise.resolve([]);
      };
      await dv.mount();
      cols = dv._grid.getColumns();
      fkCol = cols.find(function(c) {
        return c.name === 'auteur';
      });
      boolCol = cols.find(function(c) {
        return c.name === 'disponible';
      });
      assert(fkCol, 'missing FK column');
      assert(boolCol, 'missing Boolean column');
      assert(typeof ((ref = fkCol.editor) != null ? ref.type : void 0) === 'function', 'missing custom FK editor');
      eq((ref1 = fkCol.editor) != null ? (ref2 = ref1.type) != null ? ref2.name : void 0 : void 0, 'FkSearchEditor');
      eq((ref3 = boolCol.editor) != null ? ref3.type : void 0, 'checkbox');
      fkRendered = fkCol.formatter({
        value: 1,
        row: {
          auteur: 1
        }
      });
      boolRenderedTrue = boolCol.formatter({
        value: true,
        row: {
          disponible: true
        }
      });
      boolRenderedFalse = boolCol.formatter({
        value: false,
        row: {
          disponible: false
        }
      });
      assert(fkRendered === 'Hugo Victor', 'FK formatter must return plain text');
      assert(!String(fkRendered).includes('<'), 'FK formatter must not return HTML');
      eq(boolRenderedTrue, '☑');
      eq(boolRenderedFalse, '☐');
      assert(!String(boolRenderedTrue).includes('<'), 'Boolean formatter must not return HTML');
      assert(!String(boolRenderedFalse).includes('<'), 'Boolean formatter must not return HTML');
      return dv.unmount();
    });
  });

  describe('DataView FK fuzzy autocomplete editor', function() {
    return it('supports fuzzy search and maps label -> id', async function() {
      var Editor, dv, editor, el, fkCol, matches, ref, rels, sp;
      sp = makeSpace({
        fields: [
          {
            id: 'f1',
            name: 'auteur',
            fieldType: 'Relation',
            formula: null,
            triggerFields: null
          }
        ]
      });
      rels = [
        {
          fromFieldId: 'f1',
          toSpaceId: 'authors-space',
          reprFormula: '@_repr'
        }
      ];
      dv = new DV(container(), sp, null, rels);
      dv._buildFkMaps = function() {
        this._fkMaps.auteur = {
          '1': 'Hugo Victor',
          '2': 'Camus Albert'
        };
        this._fkOptions.auteur = [
          {
            text: 'Hugo Victor',
            value: '1'
          },
          {
            text: 'Camus Albert',
            value: '2'
          }
        ];
        return Promise.resolve();
      };
      dv._loadColWidths = function() {
        return Promise.resolve({});
      };
      dv.load = function() {
        return Promise.resolve([]);
      };
      await dv.mount();
      fkCol = dv._grid.getColumns().find(function(c) {
        return c.name === 'auteur';
      });
      Editor = (ref = fkCol.editor) != null ? ref.type : void 0;
      assert(typeof Editor === 'function', 'missing FK editor class');
      editor = new Editor({
        value: '',
        columnInfo: {
          editor: {
            options: {
              items: dv._fkOptions.auteur
            }
          }
        }
      });
      el = editor.getElement();
      assert(!('list' in el), 'FK editor must not use a native datalist');
      matches = editor._filterItems('hgo');
      assert(matches.length > 0, 'no fuzzy result');
      eq(matches[0].label, 'Hugo Victor');
      editor._renderMenu('hgo');
      eq(editor.visibleItems[0].label, 'Hugo Victor');
      editor._applySelection(0);
      eq(editor.getValue(), '1');
      return dv.unmount();
    });
  });

  describe('DataView.unmount', function() {
    return it('sets _mounted to false and clears arrays', function() {
      var dv;
      dv = new DV(container(), makeSpace());
      dv._mounted = true;
      dv._rows = [
        {
          __rowId: '1'
        }
      ];
      dv._currentData = [
        {
          __rowId: '1'
        }
      ];
      dv._pasteListener = null;
      dv._grid = null;
      dv.unmount();
      assert(!dv._mounted, '_mounted must be false');
      eq(dv._rows.length, 0);
      return eq(dv._currentData.length, 0);
    });
  });

  summary();

}).call(this);
