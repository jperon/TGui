(function() {
  // tests/js/test_custom_view.coffee — tests for CustomView (custom_view.js)
  // Covers: YAML parsing, generated DOM structure, flex factor, columns filtering, depends_on.
  var CV, DataView, assert, deepEq, describe, eq, flush, it, makeContainer, makeSpaces, summary, syncPlugin, yamlJSON;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // --- stubs ------------------------------------------------------------------
  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src); // test YAML fixtures are valid JSON
    }
  };

  global.DataView = DataView = class DataView {
    constructor(container, space) {
      this.container = container;
      this.space = space;
      this._currentData = {};
      this.mounted = false;
    }

    mount() {
      return this.mounted = true;
    }

    refreshLayout() {}

    setFilter(f) {
      return this.lastFilter = f;
    }

    setDefaultValues(d) {
      return this.lastDefaults = d;
    }

    deleteSelected() {}

  };

  // Load module under test (exposes window.CustomView)
  require('../../frontend/src/views/custom_view');

  CV = global.window.CustomView;

  // --- helpers ----------------------------------------------------------------
  makeSpaces = function() {
    return [
      {
        id: '1',
        name: 'personnes',
        fields: [
          {
            id: 'f1',
            name: 'nom',
            fieldType: 'Str'
          },
          {
            id: 'f2',
            name: 'age',
            fieldType: 'Int'
          },
          {
            id: 'f3',
            name: 'ville',
            fieldType: 'Str'
          }
        ]
      },
      {
        id: '2',
        name: 'groupes',
        fields: [
          {
            id: 'g1',
            name: 'titre',
            fieldType: 'Str'
          },
          {
            id: 'g2',
            name: 'code',
            fieldType: 'Str'
          }
        ]
      }
    ];
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

  syncPlugin = function(plugin) {
    return {
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
  };

  // ---------------------------------------------------------------------------
  describe('CustomView — layout vertical simple', function() {
    it('mounts a widget without error', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            id: 'w1',
            title: 'Gens',
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets.length, 1);
      return assert(cv._widgets[0].dataView.mounted, 'DataView should be mounted');
    });
    it('_widgetsById indexed by id', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            id: 'mon_widget',
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return assert(cv._widgetsById['mon_widget'] != null, 'index by id');
    });
    return it('unknown space -> dataView null', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'unknown'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets[0].dataView, null);
    });
  });

  describe('CustomView — zone with children', function() {
    return it('creates one child per child widget', function() {
      var cv, layout;
      layout = {
        layout: {
          direction: 'horizontal',
          children: [
            {
              widget: {
                space: 'personnes'
              }
            },
            {
              widget: {
                space: 'groupes'
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets.length, 2);
    });
  });

  describe('CustomView — factor', function() {
    it('applies factor as flex', function() {
      var cv, entries, layout;
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              factor: 3,
              widget: {
                space: 'personnes'
              }
            },
            {
              factor: 1,
              widget: {
                space: 'groupes'
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      // Main container flex is set by _renderZoneOrWidget (root node)
      // Child nodes keep their own flex values
      entries = cv._widgets;
      eq(entries[0].el.style.flex, '3');
      return eq(entries[1].el.style.flex, '1');
    });
    return it('missing factor -> default flex "1"', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets[0].el.style.flex, '1');
    });
  });

  describe('CustomView — columns', function() {
    it('filters specified columns', function() {
      var cv, dv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes',
            columns: ['age', 'nom']
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      dv = cv._widgets[0].dataView;
      eq(dv.space.fields.length, 2);
      eq(dv.space.fields[0].name, 'age');
      return eq(dv.space.fields[1].name, 'nom');
    });
    it('silently ignores unknown columns', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes',
            columns: ['nom', 'inconnu']
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets[0].dataView.space.fields.length, 1);
      return eq(cv._widgets[0].dataView.space.fields[0].name, 'nom');
    });
    it('without columns -> all fields', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets[0].dataView.space.fields.length, 3);
    });
    return it('does not mutate original space object (clone)', function() {
      var cv, layout, spaces;
      spaces = makeSpaces();
      layout = {
        layout: {
          widget: {
            space: 'personnes',
            columns: ['nom']
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), spaces);
      cv.mount();
      return eq(spaces[0].fields.length, 3); // original unchanged
    });
  });

  describe('CustomView — invalid YAML', function() {
    return it('shows an error without throwing exception', function() {
      var badYaml, cv;
      badYaml = '{ not valid json !!!!';
      global.jsyaml.load = function(s) {
        throw new Error('YAML parse error');
      };
      cv = new CV(makeContainer(), badYaml, makeSpaces());
      cv.mount();
      eq(cv._widgets.length, 0);
      return global.jsyaml.load = function(s) {
        return JSON.parse(s); // restore
      };
    });
  });

  describe('CustomView — unmount', function() {
    return it('clears _widgets and _widgetsById', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            id: 'w',
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets.length, 1);
      cv.unmount();
      eq(cv._widgets.length, 0);
      return eq(Object.keys(cv._widgetsById).length, 0);
    });
  });

  describe('CustomView — plugin widgets', function() {
    it('mounts a plugin widget and initializes iframe state', function() {
      var cv, e, layout, oldCreate;
      global.window.CoffeeScript = {
        compile: function() {
          return "module.exports = function(api){ api.render('<div>ok</div>'); }";
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
          return syncPlugin({
            id: 'p1',
            name: 'sample_plugin',
            scriptLanguage: 'coffeescript',
            templateLanguage: 'pug',
            scriptCode: 'ignored by compile stub',
            templateCode: 'ignored by pug compile stub'
          });
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
          widget: {
            id: 'plug1',
            type: 'sample_plugin',
            title: 'Plugin'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      try {
        cv.mount();
        assert(cv._widgetsById['plug1'] != null, 'plugin indexed by id');
        assert(cv._widgetsById['plug1'].plugin === true, 'entry marked as plugin');
        assert(cv._pluginStateByWidgetId['plug1'] != null, 'iframe runtime state created');
      } catch (error) {
        e = error;
        global.document.createElement = oldCreate;
        throw e;
      }
      return global.document.createElement = oldCreate;
    });
    it('propagates depends_on from plugin selection to DataView target', function() {
      var cv, layout, oldCreate;
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
          return syncPlugin({
            id: 'p2',
            name: 'sample_plugin_2',
            scriptLanguage: 'coffeescript',
            templateLanguage: 'pug',
            scriptCode: '',
            templateCode: ''
          });
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
                id: 'src',
                type: 'sample_plugin_2'
              }
            },
            {
              widget: {
                id: 'dst',
                space: 'personnes',
                depends_on: {
                  widget: 'src',
                  field: 'age',
                  from_field: 'id'
                }
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return flush().then(function() {
        var dv;
        cv._emitPluginSelection('src', {
          rows: [
            {
              id: 7
            }
          ]
        });
        dv = cv._widgetsById['dst'].dataView;
        eq(dv.lastDefaults.age, '7');
        deepEq(dv.lastFilter, {
          field: 'age',
          value: '7'
        });
        return global.document.createElement = oldCreate;
      }).catch(function(e) {
        global.document.createElement = oldCreate;
        throw e;
      });
    });
    return it('shows a fallback error when CoffeeScript runtime is missing', function() {
      var body, cv, e, layout, oldCreate;
      delete global.window.CoffeeScript;
      global.window.pug = {
        compile: function() {
          return function() {
            return "<div>tpl</div>";
          };
        }
      };
      global.WidgetPlugins = {
        getByName: function() {
          return syncPlugin({
            id: 'p3',
            name: 'broken_plugin',
            scriptLanguage: 'coffeescript',
            templateLanguage: 'pug',
            scriptCode: 'x = 1',
            templateCode: 'div hi'
          });
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
          widget: {
            id: 'plug_err',
            type: 'broken_plugin'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      try {
        cv.mount();
        body = cv._widgets[0].el._children[1];
        assert(body.innerHTML.includes('Erreur plugin'), 'fallback error should be rendered');
      } catch (error) {
        e = error;
        global.document.createElement = oldCreate;
        throw e;
      }
      return global.document.createElement = oldCreate;
    });
  });

  summary();

}).call(this);
