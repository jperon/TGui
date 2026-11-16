(function() {
  // tests/js/test_custom_view_dataview_widget.coffee — T18 regression tests.

  // A page widget whose `space` names a Data View must expose the view's output
  // columns, otherwise the grid mounts with an empty space and renders blank.
  // The Data View `config` arrives from the list GraphQL query as a JSON string.
  // Also guards the sidebar CSS for #page-list / #data-view-list.
  var CV, DataView, SOURCE, assert, deepEq, describe, eq, fs, it, makeCV, makeContainer, path, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  fs = require('fs');

  path = require('path');

  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    }
  };

  global.DataView = DataView = class DataView {
    constructor(container, space) {
      this.container = container;
      this.space = space;
      this.mounted = false;
    }

    mount() {
      return this.mounted = true;
    }

    refreshLayout() {}

    unmount() {}

  };

  require('../../frontend/src/views/custom_view');

  CV = global.window.CustomView;

  makeContainer = function() {
    return global.document.createElement('div');
  };

  // Build a CustomView whose only purpose is to expose _findSpace. `spaces` and
  // `views` mimic what the SPA holds in _allSpaces / _allDataViews.
  makeCV = function(spaces, views) {
    return new CV(makeContainer(), '{}', spaces, views);
  };

  SOURCE = {
    id: 'sp-1',
    name: 'Emprunts',
    fields: [
      {
        name: 'lecteur',
        fieldType: 'Str'
      },
      {
        name: 'ouvrage',
        fieldType: 'Str'
      },
      {
        name: 'montant',
        fieldType: 'Int'
      }
    ]
  };

  describe('CustomView._findSpace — data view widgets', function() {
    it('parses a JSON-string config and maps its columns', function() {
      var dv, f, sp;
      dv = {
        id: 'dv1',
        name: 'Ma vue',
        sourceSpace: 'sp-1',
        config: JSON.stringify({
          columns: ['lecteur', 'ouvrage']
        })
      };
      sp = makeCV([SOURCE], [dv])._findSpace('Ma vue');
      assert(sp != null, 'view should resolve');
      eq(sp.isView, true);
      deepEq((function() {
        var i, len, ref, results;
        ref = sp.fields;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          results.push(f.name);
        }
        return results;
      })(), ['lecteur', 'ouvrage']);
      eq(sp.fields[0].fieldType, 'Str');
      return eq(sp.fields[1].fieldType, 'Str');
    });
    it('aggregated view: groupBy names then aggregate aliases', function() {
      var config, dv, f, sp;
      config = {
        groupBy: ['lecteur'],
        aggregates: [
          {
            fn: 'count',
            as: 'nb_livres'
          }
        ]
      };
      dv = {
        id: 'dv2',
        name: 'Agrégée',
        sourceSpace: 'sp-1',
        config: JSON.stringify(config)
      };
      sp = makeCV([SOURCE], [dv])._findSpace('Agrégée');
      return deepEq((function() {
        var i, len, ref, results;
        ref = sp.fields;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          results.push(f.name);
        }
        return results;
      })(), ['lecteur', 'nb_livres']);
    });
    it('aggregate alias falls back to fn_field then count', function() {
      var config, dv, f, sp;
      config = {
        groupBy: ['lecteur'],
        aggregates: [
          {
            fn: 'sum',
            field: 'montant'
          },
          {
            fn: 'count'
          }
        ]
      };
      dv = {
        id: 'dv3',
        name: 'Alias',
        sourceSpace: 'sp-1',
        config: JSON.stringify(config)
      };
      sp = makeCV([SOURCE], [dv])._findSpace('Alias');
      return deepEq((function() {
        var i, len, ref, results;
        ref = sp.fields;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          results.push(f.name);
        }
        return results;
      })(), ['lecteur', 'sum_montant', 'count']);
    });
    it('view without columns nor groupBy falls back to source space fields', function() {
      var dv, f, sp;
      dv = {
        id: 'dv4',
        name: 'Brute',
        sourceSpace: 'sp-1',
        config: '{}'
      };
      sp = makeCV([SOURCE], [dv])._findSpace('Brute');
      return deepEq((function() {
        var i, len, ref, results;
        ref = sp.fields;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          results.push(f.name);
        }
        return results;
      })(), ['lecteur', 'ouvrage', 'montant']);
    });
    it('invalid JSON config -> no exception, empty fields', function() {
      var dv, e, sp;
      dv = {
        id: 'dv5',
        name: 'Cassée',
        sourceSpace: 'sp-1',
        config: '{ not json'
      };
      sp = null;
      try {
        sp = makeCV([SOURCE], [dv])._findSpace('Cassée');
      } catch (error) {
        e = error;
        assert(false, `should not throw: ${e.message}`);
      }
      return deepEq(sp.fields, []);
    });
    it('unknown source space without columns -> empty fields', function() {
      var dv, sp;
      dv = {
        id: 'dv6',
        name: 'Orpheline',
        sourceSpace: 'missing',
        config: '{}'
      };
      sp = makeCV([SOURCE], [dv])._findSpace('Orpheline');
      return deepEq(sp.fields, []);
    });
    return it('a real space is unchanged', function() {
      var sp;
      sp = makeCV([SOURCE], [])._findSpace('Emprunts');
      eq(sp.fields.length, 3);
      return eq(sp.isView, void 0);
    });
  });

  describe('CustomView — widget on a data view filters columns', function() {
    return it('keeps only the requested columns of the view', function() {
      var cv, dv, f, fields, layout;
      dv = {
        id: 'dv7',
        name: 'Trois',
        sourceSpace: 'sp-1',
        config: JSON.stringify({
          columns: ['a', 'b', 'c']
        })
      };
      layout = {
        layout: {
          widget: {
            space: 'Trois',
            columns: ['b']
          }
        }
      };
      cv = new CV(makeContainer(), JSON.stringify(layout), [SOURCE], [dv]);
      cv.mount();
      eq(cv._widgets.length, 1);
      fields = cv._widgets[0].dataView.space.fields;
      return deepEq((function() {
        var i, len, results;
        results = [];
        for (i = 0, len = fields.length; i < len; i++) {
          f = fields[i];
          results.push(f.name);
        }
        return results;
      })(), ['b']);
    });
  });

  describe('app.css — pages / data views sidebar items', function() {
    var css;
    css = fs.readFileSync(path.join(__dirname, '../../frontend/css/app.css'), 'utf8');
    it('styles #page-list and #data-view-list with the same base rule as #space-list', function() {
      return assert(/#space-list li[^{]*#page-list[^{]*#data-view-list[^{]*\{/.test(css), 'expected one rule to style #space-list li, #page-list and #data-view-list together');
    });
    return it('shares the hover/active rule', function() {
      return assert(/#space-list li:hover[^{]*#data-view-list[^{]*\{/.test(css), 'expected #page-list and #data-view-list to share the hover/active rule with #space-list');
    });
  });

  summary();

}).call(this);
