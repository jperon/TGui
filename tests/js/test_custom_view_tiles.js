(function() {
  // tests/js/test_custom_view_tiles.coffee — page "tile" mode (T19).

  // Part 1: page zones must fill the whole surface (CSS) and grid layouts must be
  // refreshed when a tile is resized (ResizeObserver).
  // Part 2 (added later): splitter persistence helpers and splitter rendering.
  var CV, DataView, assert, collectByClass, deepEq, describe, eq, fs, it, makeContainer, makePageContainer, makeSpaces, path, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  fs = require('fs');

  path = require('path');

  // --- stubs ------------------------------------------------------------------
  // jsyaml.load/dump are backed by JSON: test fixtures are JSON documents and the
  // pure helpers (setChildFactors) only care about structure, not YAML syntax.
  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    },
    dump: function(obj) {
      return JSON.stringify(obj);
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

  require('../../frontend/src/views/custom_view_plugins');

  require('../../frontend/src/views/custom_view_aggregate');

  require('../../frontend/src/views/custom_view_resize');

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
          }
        ]
      }
    ];
  };

  makeContainer = function() {
    return global.document.createElement('div');
  };

  makePageContainer = function(pageId) {
    var c;
    c = global.document.createElement('div');
    if (pageId) {
      c.setAttribute('data-page-id', pageId);
    }
    return c;
  };

  // Depth-first collection of descendants whose className contains `cls`.
  collectByClass = function(root, cls) {
    var child, classes, i, len, out, ref;
    out = [];
    ref = root._children || [];
    for (i = 0, len = ref.length; i < len; i++) {
      child = ref[i];
      classes = (child.className || '').split(' ');
      if (classes.indexOf(cls) >= 0) {
        out.push(child);
      }
      out = out.concat(collectByClass(child, cls));
    }
    return out;
  };

  // ---------------------------------------------------------------------------
  // Part 1 — the page surface is filled by its tiles.
  // ---------------------------------------------------------------------------
  describe('app.css — page zones fill their surface (T19 part 1)', function() {
    var css;
    css = fs.readFileSync(path.join(__dirname, '../../frontend/css/app.css'), 'utf8');
    it('the .cv-zone rule stretches its cross axis', function() {
      var m;
      m = css.match(/\.cv-zone\s*\{([^}]*)\}/);
      assert(m, ".cv-zone rule not found in app.css");
      return assert(/align-items\s*:\s*stretch/.test(m[1]), `.cv-zone must set align-items: stretch; got: ${m[1]}`);
    });
    it('the .cv-zone rule aligns its content to flex-start', function() {
      var m;
      m = css.match(/\.cv-zone\s*\{([^}]*)\}/);
      assert(m, ".cv-zone rule not found in app.css");
      return assert(/justify-content\s*:\s*flex-start/.test(m[1]), `.cv-zone must set justify-content: flex-start; got: ${m[1]}`);
    });
    return it('tiles lose the 2px margin so they touch', function() {
      var m;
      m = css.match(/\.cv-zone\s+\.cv-widget\s*\{([^}]*)\}/);
      assert(m, ".cv-zone .cv-widget rule not found in app.css");
      return assert(/margin\s*:\s*0/.test(m[1]), `.cv-zone .cv-widget must set margin: 0; got: ${m[1]}`);
    });
  });

  describe('CustomView — ResizeObserver refreshes grid layouts', function() {
    return it('observes the container and refreshes grids when it resizes', function() {
      var FakeResizeObserver, calls, cv, layout, observed;
      observed = null;
      FakeResizeObserver = class FakeResizeObserver {
        constructor(cb) {
          this.cb = cb;
          observed = this;
        }

        observe(el) {
          return this.el = el;
        }

        disconnect() {}

      };
      global.ResizeObserver = FakeResizeObserver;
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              widget: {
                space: 'personnes'
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), JSON.stringify(layout), makeSpaces());
      cv.mount();
      calls = 0;
      return new Promise(function(resolve, reject) {
        return setTimeout(function() {
          var e;
          try {
            assert(observed != null, 'ResizeObserver must be constructed');
            eq(observed.el, cv.container);
            cv._widgets[0].dataView._grid = {
              refreshLayout: function() {
                return calls++;
              }
            };
            // Laisse passer le rafraîchissement initial du montage avant de mesurer.
            return setTimeout(function() {
              var baseline;
              baseline = calls;
              observed.cb([]);
              return setTimeout(function() {
                var e;
                try {
                  assert(calls > baseline, 'refreshLayout must be called (debounced)');
                  global.ResizeObserver = void 0;
                  return resolve();
                } catch (error) {
                  e = error;
                  global.ResizeObserver = void 0;
                  return reject(e);
                }
              }, 80);
            }, 10);
          } catch (error) {
            e = error;
            global.ResizeObserver = void 0;
            return reject(e);
          }
        }, 0);
      });
    });
  });

  summary();

}).call(this);
