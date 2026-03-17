(function() {
  // tests/js/test_data_view_opts.coffee — tests for DataView options (readOnly)
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
        }
      ]
    };
  };

  container = function() {
    return global.document.createElement('div');
  };

  describe('DataView options', function() {
    it('stores opts object in constructor', function() {
      var dv;
      dv = new DV(container(), makeSpace(), null, [], {
        foo: 'bar'
      });
      assert(dv.opts != null, 'opts must exist');
      return eq(dv.opts.foo, 'bar');
    });
    it('stores empty opts object when not provided', function() {
      var dv;
      dv = new DV(container(), makeSpace());
      assert(dv.opts != null, 'opts must exist');
      return deepEq(dv.opts, {});
    });
    it('readOnly option is accessible', function() {
      var dv;
      dv = new DV(container(), makeSpace(), null, [], {
        readOnly: true
      });
      return eq(dv.opts.readOnly, true);
    });
    it('readOnly option defaults to undefined when not provided', function() {
      var dv;
      dv = new DV(container(), makeSpace());
      return eq(dv.opts.readOnly, void 0);
    });
    it('opts.onColumnFocus is stored when provided', function() {
      var cb, dv;
      cb = function() {
        return console.log('focus');
      };
      dv = new DV(container(), makeSpace(), null, [], {
        onColumnFocus: cb
      });
      return eq(dv.opts.onColumnFocus, cb);
    });
    return it('opts is preserved after multiple operations', function() {
      var dv;
      dv = new DV(container(), makeSpace(), null, [], {
        readOnly: true,
        custom: 'value'
      });
      dv._mounted = true;
      dv._rows = [];
      dv._currentData = [];
      eq(dv.opts.readOnly, true);
      return eq(dv.opts.custom, 'value');
    });
  });

  summary();

}).call(this);
