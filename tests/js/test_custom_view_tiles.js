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
        // Ne garde que la PREMIÈRE instance : les tests suivants montent d'autres
        // vues et ne doivent pas écraser la référence observée ici.
        constructor(cb) {
          this.cb = cb;
          if (observed == null) {
            observed = this;
          }
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

  // ---------------------------------------------------------------------------
  // Part 2 — draggable splitters between tiles.
  // ---------------------------------------------------------------------------
  describe('CustomView.redistribute (pure)', function() {
    it('moves space by a positive delta, keeping the sum', function() {
      var a, b;
      [a, b] = CV.redistribute(300, 200, 50, 80);
      eq(a, 350);
      return eq(b, 150);
    });
    it('moves space by a negative delta, keeping the sum', function() {
      var a, b;
      [a, b] = CV.redistribute(300, 200, -50, 80);
      eq(a, 250);
      return eq(b, 250);
    });
    it('clamps a positive overshoot to the minimum of the second tile', function() {
      var a, b;
      [a, b] = CV.redistribute(300, 200, 500, 80);
      eq(a, 420);
      return eq(b, 80);
    });
    it('clamps a negative overshoot to the minimum of the first tile', function() {
      var a, b;
      [a, b] = CV.redistribute(300, 200, -500, 80);
      eq(a, 80);
      return eq(b, 420);
    });
    return it('always preserves the total', function() {
      var a, b;
      [a, b] = CV.redistribute(123, 456, 33, 10);
      return eq(a + b, 579);
    });
  });

  describe('CustomView.setChildFactors (pure)', function() {
    it('updates the factor of the two wanted children and keeps everything else', function() {
      var out, parsed, yaml;
      yaml = JSON.stringify({
        layout: {
          direction: 'horizontal',
          children: [
            {
              widget: {
                id: 'a',
                space: 'x',
                title: 'A'
              }
            },
            {
              layout: {
                direction: 'vertical',
                children: [
                  {
                    widget: {
                      id: 'b',
                      space: 'y'
                    }
                  },
                  {
                    widget: {
                      id: 'c',
                      space: 'z'
                    }
                  }
                ]
              }
            }
          ]
        }
      });
      out = CV.setChildFactors(yaml, [], [
        {
          index: 0,
          factor: 2.5
        },
        {
          index: 1,
          factor: 0.5
        }
      ]);
      parsed = JSON.parse(out);
      eq(parsed.layout.children[0].widget.factor, 2.5);
      eq(parsed.layout.children[1].layout.factor, 0.5);
      // Le reste du YAML est conservé.
      eq(parsed.layout.direction, 'horizontal');
      eq(parsed.layout.children[0].widget.id, 'a');
      eq(parsed.layout.children[0].widget.title, 'A');
      eq(parsed.layout.children[1].layout.children[0].widget.id, 'b');
      eq(parsed.layout.children[1].layout.children[1].widget.id, 'c');
      return eq(parsed.layout.children[1].layout.children[0].widget.factor, void 0);
    });
    it('navigates a nested path and leaves siblings untouched', function() {
      var out, parsed, yaml;
      yaml = JSON.stringify({
        layout: {
          direction: 'vertical',
          children: [
            {
              layout: {
                direction: 'horizontal',
                children: [
                  {
                    widget: {
                      id: 'a',
                      space: 'x'
                    }
                  },
                  {
                    widget: {
                      id: 'b',
                      space: 'y'
                    }
                  }
                ]
              }
            }
          ]
        }
      });
      out = CV.setChildFactors(yaml, [0], [
        {
          index: 0,
          factor: 3
        }
      ]);
      parsed = JSON.parse(out);
      eq(parsed.layout.children[0].layout.children[0].widget.factor, 3);
      return eq(parsed.layout.children[0].layout.children[1].widget.factor, void 0);
    });
    it('writes factor on a bare zone child too', function() {
      var out, parsed, yaml;
      yaml = JSON.stringify({
        layout: {
          direction: 'horizontal',
          children: [
            {
              direction: 'vertical',
              children: [
                {
                  widget: {
                    id: 'a',
                    space: 'x'
                  }
                }
              ]
            },
            {
              widget: {
                id: 'b',
                space: 'y'
              }
            }
          ]
        }
      });
      out = CV.setChildFactors(yaml, [], [
        {
          index: 0,
          factor: 2
        }
      ]);
      parsed = JSON.parse(out);
      return eq(parsed.layout.children[0].factor, 2);
    });
    return it('rounds factors to two decimals', function() {
      var out, yaml;
      yaml = JSON.stringify({
        layout: {
          direction: 'horizontal',
          children: [
            {
              widget: {
                id: 'a',
                space: 'x'
              }
            },
            {
              widget: {
                id: 'b',
                space: 'y'
              }
            }
          ]
        }
      });
      out = CV.setChildFactors(yaml, [], [
        {
          index: 0,
          factor: 1.239
        }
      ]);
      return eq(JSON.parse(out).layout.children[0].widget.factor, 1.24);
    });
  });

  describe('CustomView — factor read from both locations', function() {
    it('reads factor on the entry (legacy)', function() {
      var cv, layout;
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
              widget: {
                space: 'groupes'
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), JSON.stringify(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets[0].el.style.flex, '3');
      return eq(cv._widgets[1].el.style.flex, '1');
    });
    it('reads factor inside the widget mapping (documented form)', function() {
      var cv, layout;
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              widget: {
                space: 'personnes',
                factor: 3
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
      cv = new CV(makeContainer(), JSON.stringify(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets[0].el.style.flex, '3');
      return eq(cv._widgets[1].el.style.flex, '1');
    });
    return it('reads factor inside a layout mapping', function() {
      var cv, layout, zones;
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              layout: {
                direction: 'horizontal',
                factor: 2,
                children: [
                  {
                    widget: {
                      id: 'a',
                      space: 'personnes'
                    }
                  }
                ]
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
      cv = new CV(makeContainer(), JSON.stringify(layout), makeSpaces());
      cv.mount();
      zones = collectByClass(cv.container, 'cv-zone');
      eq(zones.length, 2);
      return eq(zones[1].style.flex, '2');
    });
  });

  describe('CustomView — splitters between tiles', function() {
    var makeThreeTiles;
    makeThreeTiles = function() {
      var layout;
      return layout = {
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
            },
            {
              widget: {
                space: 'personnes'
              }
            }
          ]
        }
      };
    };
    it('a zone with three children renders two splitters', function() {
      var cv;
      cv = new CV(makePageContainer('p1'), JSON.stringify(makeThreeTiles()), makeSpaces());
      cv.mount();
      return eq(collectByClass(cv.container, 'cv-splitter').length, 2);
    });
    it('renders no splitter in presentation mode', function() {
      var cv;
      cv = new CV(makePageContainer('p1'), JSON.stringify(makeThreeTiles()), makeSpaces(), [], {
        presentationMode: true
      });
      cv.mount();
      return eq(collectByClass(cv.container, 'cv-splitter').length, 0);
    });
    it('renders no splitter without an editable page id', function() {
      var cv;
      cv = new CV(makePageContainer(null), JSON.stringify(makeThreeTiles()), makeSpaces());
      cv.mount();
      return eq(collectByClass(cv.container, 'cv-splitter').length, 0);
    });
    return it('splitters are oriented along their zone direction', function() {
      var cv, i, len, ref, results, sp;
      cv = new CV(makePageContainer('p1'), JSON.stringify(makeThreeTiles()), makeSpaces());
      cv.mount();
      ref = collectByClass(cv.container, 'cv-splitter');
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        sp = ref[i];
        results.push(assert(/cv-splitter--horizontal/.test(sp.className), `expected a horizontal splitter, got ${sp.className}`));
      }
      return results;
    });
  });

  summary();

}).call(this);
