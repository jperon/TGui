(function() {
  // tests/js/test_yaml_builder.coffee — tests for YamlBuilder (yaml_builder.js)
  // Covers YAML generation, field click, header click (aggregate), badges, dependencies.
  var YB, assert, deepEq, describe, eq, it, makeContainer, makeRelations, makeSpaces, makeYB, summary, yamlFromObj,
    indexOf = [].indexOf;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // --- stubs ------------------------------------------------------------------
  global.jsyaml = {
    dump: function(obj) {
      return JSON.stringify(obj); // simplifies comparisons
    },
    load: function(src) {
      var e;
      try {
        // Minimal YAML-as-JSON stub: supports JSON and simple key: value
        return JSON.parse(src);
      } catch (error) {
        e = error;
        return {};
      }
    }
  };

  // Load module under test (exposes window.YamlBuilder)
  require('../../frontend/src/yaml_builder');

  YB = global.window.YamlBuilder;

  // --- helpers ----------------------------------------------------------------
  makeSpaces = function() {
    return [
      {
        id: 'sp1',
        name: 'personnes',
        fields: [
          {
            id: 'f_nom',
            name: 'nom',
            fieldType: 'String'
          },
          {
            id: 'f_prenom',
            name: 'prenom',
            fieldType: 'String'
          },
          {
            id: 'f_age',
            name: 'age',
            fieldType: 'Int'
          }
        ]
      },
      {
        id: 'sp2',
        name: 'commandes',
        fields: [
          {
            id: 'f_client',
            name: 'client_id',
            fieldType: 'Int'
          },
          {
            id: 'f_total',
            name: 'total',
            fieldType: 'Int'
          }
        ]
      }
    ];
  };

  makeRelations = function() {
    return [
      {
        id: 'r1',
        fromSpaceId: 'sp2',
        fromFieldId: 'f_client',
        toSpaceId: 'sp1',
        toFieldId: 'f_nom'
      }
    ];
  };

  makeContainer = function() {
    return global.document.createElement('div');
  };

  makeYB = function(opts = {}) {
    var yb;
    yb = new YB({
      container: makeContainer(),
      allSpaces: opts.spaces || makeSpaces(),
      allRelations: opts.relations || [],
      initialYaml: opts.initialYaml || null,
      onChange: opts.onChange || function() {}
    });
    yb._render = function() {}; // no-op: state-only tests, no SVG DOM assertions
    return yb;
  };

  // --- YamlBuilder: initial state ----------------------------------------------
  describe('YamlBuilder — initial', function() {
    it('no widgets on startup', function() {
      var yb;
      yb = makeYB();
      return eq(yb._widgets.length, 0);
    });
    return it('empty toYaml() returns skeleton', function() {
      var yaml, yb;
      yb = makeYB();
      yaml = yb.toYaml();
      assert(yaml.indexOf('layout') !== -1, 'contains layout');
      return assert(yaml.indexOf('children') !== -1, 'contains children');
    });
  });

  // --- YamlBuilder: field click ------------------------------------------------
  describe('YamlBuilder — field click', function() {
    it('adding a field creates a regular widget', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      eq(yb._widgets.length, 1);
      eq(yb._widgets[0].spaceName, 'personnes');
      eq(yb._widgets[0].columns.length, 1);
      return eq(yb._widgets[0].columns[0], 'nom');
    });
    it('clicking * creates a widget without column restriction', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', '*');
      eq(yb._widgets[0].columns.length, 0);
      return assert(yb._widgets[0].type !== 'aggregate', 'regular widget, not aggregate');
    });
    it('clicking * again in all-columns mode removes widget', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', '*');
      yb._onFieldClick('sp1', '*');
      return eq(yb._widgets.length, 0);
    });
    it('clicking same field again removes it', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      yb._onFieldClick('sp1', 'nom');
      return eq(yb._widgets.length, 0);
    });
    return it('multiple fields in same widget', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      yb._onFieldClick('sp1', 'age');
      eq(yb._widgets.length, 1);
      return eq(yb._widgets[0].columns.length, 2);
    });
  });

  // --- YamlBuilder: header click (aggregate) -----------------------------------
  describe('YamlBuilder — header click (aggregate)', function() {
    it('creates an aggregate widget', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      eq(yb._widgets.length, 1);
      eq(yb._widgets[0].type, 'aggregate');
      return eq(yb._widgets[0].spaceName, 'personnes');
    });
    it('groupBy contains all fields (no FK for sp1)', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      return deepEq(yb._widgets[0].groupBy, [
        'age',
        'nom',
        'prenom' // alphabetical
      ]);
    });
    it('groupBy excludes FK fields', function() {
      var yb;
      yb = makeYB({
        spaces: makeSpaces(),
        relations: makeRelations()
      });
      yb._onHeaderClick('sp2');
      // client_id is FK -> excluded; only total remains
      return deepEq(yb._widgets[0].groupBy, ['total']);
    });
    it('second header click removes aggregate widget', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      yb._onHeaderClick('sp1');
      return eq(yb._widgets.length, 0);
    });
    it('aggregate and regular widgets can coexist', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1'); // aggregate
      yb._onFieldClick('sp2', 'total'); // regular
      eq(yb._widgets.length, 2);
      eq((yb._widgets.filter(function(w) {
        return w.type === 'aggregate';
      })).length, 1);
      return eq((yb._widgets.filter(function(w) {
        return w.type !== 'aggregate';
      })).length, 1);
    });
    return it('_widgetForSpace ignores aggregate widgets', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      assert(!yb._widgetForSpace('sp1'), 'no regular widget for sp1');
      return assert(yb._aggWidgetForSpace('sp1'), 'aggregate widget present');
    });
  });

  // --- YamlBuilder: toYaml with aggregate --------------------------------------
  describe('YamlBuilder — toYaml aggregate', function() {
    it('generates type:aggregate with groupBy', function() {
      var parsed, ref, wObj, yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      parsed = JSON.parse(yb.toYaml());
      wObj = parsed.layout.children[0].widget;
      eq(wObj.type, 'aggregate');
      eq(wObj.space, 'personnes');
      assert(Array.isArray(wObj.groupBy), 'groupBy is an array');
      assert(((ref = wObj.aggregate) != null ? ref.length : void 0) > 0, 'aggregate has at least one entry');
      return eq(wObj.aggregate[0].fn, 'count');
    });
    return it('generates regular widget correctly when aggregate is present', function() {
      var parsed, types, yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      yb._onFieldClick('sp2', 'total');
      parsed = JSON.parse(yb.toYaml());
      eq(parsed.layout.children.length, 2);
      types = parsed.layout.children.map(function(c) {
        return c.widget.type;
      });
      return assert(indexOf.call(types, 'aggregate') >= 0, 'aggregate present');
    });
  });

  // --- YamlBuilder: automatic depends_on ---------------------------------------
  describe('YamlBuilder — depends_on', function() {
    return it('detects FK and generates depends_on', function() {
      var child, yb;
      yb = makeYB({
        spaces: makeSpaces(),
        relations: makeRelations()
      });
      yb._onFieldClick('sp1', 'nom'); // parent
      yb._onFieldClick('sp2', 'total'); // child (has FK to sp1)
      child = yb._widgets[1];
      assert(child.dependsOn != null, 'depends_on detected');
      return eq(child.dependsOn.field, 'client_id');
    });
  });

  // Helper: build a JSON-YAML string (our stub parses JSON)
  yamlFromObj = function(obj) {
    return JSON.stringify(obj);
  };

  // --- YamlBuilder: hydration from existing YAML -------------------------------
  describe('YamlBuilder — _loadFromYaml (initialYaml)', function() {
    it('loads a regular widget', function() {
      var yaml, yb;
      yaml = yamlFromObj({
        layout: {
          children: [
            {
              widget: {
                id: 'w1',
                space: 'personnes',
                columns: ['nom']
              }
            }
          ]
        }
      });
      yb = makeYB({
        initialYaml: yaml
      });
      eq(yb._widgets.length, 1);
      eq(yb._widgets[0].spaceName, 'personnes');
      deepEq(yb._widgets[0].columns, ['nom']);
      return eq(yb._widgets[0].id, 'w1');
    });
    it('loads an aggregate widget', function() {
      var yaml, yb;
      yaml = yamlFromObj({
        layout: {
          children: [
            {
              widget: {
                type: 'aggregate',
                space: 'commandes',
                groupBy: ['total']
              }
            }
          ]
        }
      });
      yb = makeYB({
        initialYaml: yaml
      });
      eq(yb._widgets.length, 1);
      eq(yb._widgets[0].type, 'aggregate');
      eq(yb._widgets[0].spaceName, 'commandes');
      return deepEq(yb._widgets[0].groupBy, ['total']);
    });
    it('loads depends_on', function() {
      var dep, yaml, yb;
      yaml = yamlFromObj({
        layout: {
          children: [
            {
              widget: {
                id: 'p',
                space: 'personnes',
                columns: ['nom']
              }
            },
            {
              widget: {
                space: 'commandes',
                depends_on: {
                  widget: 'p',
                  field: 'client_id',
                  from_field: 'id'
                }
              }
            }
          ]
        }
      });
      yb = makeYB({
        initialYaml: yaml
      });
      eq(yb._widgets.length, 2);
      dep = yb._widgets[1].dependsOn;
      assert(dep != null, 'depends_on present');
      eq(dep.widgetId, 'p');
      return eq(dep.field, 'client_id');
    });
    it('ignores unknown spaces', function() {
      var yaml, yb;
      yaml = yamlFromObj({
        layout: {
          children: [
            {
              widget: {
                space: 'unknown'
              }
            }
          ]
        }
      });
      yb = makeYB({
        initialYaml: yaml
      });
      return eq(yb._widgets.length, 0);
    });
    it('does not duplicate when clicking already-loaded space', function() {
      var yaml, yb;
      yaml = yamlFromObj({
        layout: {
          children: [
            {
              widget: {
                space: 'personnes',
                columns: ['nom']
              }
            }
          ]
        }
      });
      yb = makeYB({
        initialYaml: yaml
      });
      // Clicking another field should ADD to existing widget, not create a new one
      yb._onFieldClick('sp1', 'age');
      eq(yb._widgets.length, 1);
      return assert(indexOf.call(yb._widgets[0].columns, 'age') >= 0, 'age added');
    });
    return it('reloadFromYaml resets and re-hydrates state', function() {
      var newYaml, yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      eq(yb._widgets.length, 1);
      // Now reload with a different YAML
      newYaml = yamlFromObj({
        layout: {
          children: [
            {
              widget: {
                type: 'aggregate',
                space: 'commandes',
                groupBy: ['total']
              }
            }
          ]
        }
      });
      yb.reloadFromYaml(newYaml);
      eq(yb._widgets.length, 1);
      return eq(yb._widgets[0].type, 'aggregate');
    });
  });

  summary();

}).call(this);
