(function() {
  // tests/js/test_plugin_runtimes.coffee — on-demand widget compiler loading
  // Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7 (L6):
  // `window.PluginRuntimes.ensure(langs)` inserts /vendor/plugin-runtime.bundle.js
  // only for the languages a widget actually uses, once per session, with the
  // promise shared by widgets mounted concurrently.
  var BUNDLE, R, WASMOON, WASMOON_WASM, _chain, assert, describe, eq, it, resetHead, serial, summary;

  require('./dom_stub');

  ({describe, it, assert, eq, summary} = require('./runner'));

  require('../../frontend/src/views/plugin_runtimes');

  R = global.window.PluginRuntimes;

  BUNDLE = '/vendor/plugin-runtime.bundle.js';

  WASMOON = '/vendor/wasmoon.bundle.js';

  WASMOON_WASM = '/vendor/wasmoon.bundle.wasm';

  // Le runner lance tous les `it` du fichier avant que les promesses ne se
  // résolvent, et ces tests partagent des globales (window.CoffeeScript, …) et le
  // <head> : on les sérialise explicitement.
  _chain = Promise.resolve();

  serial = function(fn) {
    var p;
    p = _chain.then(fn);
    _chain = p.then((function() {}), (function() {}));
    return p;
  };

  // Fresh registry + DOM state; returns the <head> stub.
  resetHead = function() {
    var head;
    R._reset();
    delete global.window.CoffeeScript;
    delete global.window.pug;
    delete global.window.wasmoon;
    head = global.document.head;
    head._children.length = 0;
    head.children.length = 0;
    return head;
  };

  describe('PluginRuntimes — langages sans runtime', function() {
    it('javascript + html ne chargent rien', function() {
      return serial(function() {
        var appended, head, oldAppend;
        head = resetHead();
        appended = [];
        oldAppend = head.appendChild;
        head.appendChild = function(el) {
          return appended.push(el);
        };
        return Promise.resolve().then(function() {
          return R.ensure(['javascript', 'html']);
        }).then(function() {
          return eq(appended.length, 0, 'aucun <script> ne doit être inséré');
        }).then(function() {
          return head.appendChild = oldAppend;
        }, function(e) {
          head.appendChild = oldAppend;
          throw e;
        });
      });
    });
    return it('un langage inconnu ne charge rien', function() {
      return serial(function() {
        var appended, head, oldAppend;
        head = resetHead();
        appended = [];
        oldAppend = head.appendChild;
        head.appendChild = function(el) {
          return appended.push(el);
        };
        return Promise.resolve().then(function() {
          return R.ensure(['ruby']);
        }).then(function() {
          return eq(appended.length, 0);
        }).then(function() {
          return head.appendChild = oldAppend;
        }, function(e) {
          head.appendChild = oldAppend;
          throw e;
        });
      });
    });
  });

  describe('PluginRuntimes — chargement à la demande', function() {
    it('coffeescript insère le bundle une seule fois pour deux appels concurrents', function() {
      return serial(function() {
        var appended, head, oldAppend;
        head = resetHead();
        appended = [];
        oldAppend = head.appendChild;
        // Chargement simulé : le bundle installe ses globales puis onload.
        head.appendChild = function(el) {
          appended.push(el);
          global.window.CoffeeScript = {
            compile: function() {
              return 'js';
            }
          };
          global.window.pug = {
            compile: function() {
              return function() {
                return '<div></div>';
              };
            }
          };
          Promise.resolve().then(function() {
            return typeof el.onload === "function" ? el.onload() : void 0;
          });
          return el;
        };
        return Promise.all([R.ensure(['coffeescript']), R.ensure(['pug'])]).then(function() {
          eq(appended.length, 1, 'un seul <script> pour les deux widgets');
          eq(appended[0].getAttribute('src'), BUNDLE);
          return R.ensure(['coffeescript']);
        }).then(function() {
          return eq(appended.length, 1, 'aucun rechargement une fois le runtime présent');
        }).then(function() {
          return head.appendChild = oldAppend;
        }, function(e) {
          head.appendChild = oldAppend;
          throw e;
        });
      });
    });
    it('un runtime déjà présent ne charge rien', function() {
      return serial(function() {
        var appended, head, oldAppend;
        head = resetHead();
        global.window.CoffeeScript = {
          compile: function() {
            return 'js';
          }
        };
        appended = [];
        oldAppend = head.appendChild;
        head.appendChild = function(el) {
          return appended.push(el);
        };
        return Promise.resolve().then(function() {
          return R.ensure(['coffeescript']);
        }).then(function() {
          return eq(appended.length, 0);
        }).then(function() {
          return head.appendChild = oldAppend;
        }, function(e) {
          head.appendChild = oldAppend;
          throw e;
        });
      });
    });
    return it('échec de chargement : rejet explicite, puis nouvelle tentative possible', function() {
      return serial(function() {
        var attempts, head, oldAppend, restore;
        head = resetHead();
        attempts = 0;
        oldAppend = head.appendChild;
        head.appendChild = function(el) {
          attempts++;
          if (typeof el.onerror === "function") {
            el.onerror();
          }
          return el;
        };
        restore = function() {
          return head.appendChild = oldAppend;
        };
        return R.ensure(['coffeescript']).then(function() {
          throw new Error('ensure devait rejeter');
        }, function(err) {
          assert(err.message.includes(BUNDLE), `le message doit nommer le bundle, vu : ${err.message}`);
          assert(err.message.includes('Échec du chargement'), `message attendu, vu : ${err.message}`);
          eq(attempts, 1);
          // La promesse rejetée n'est pas mémorisée : nouvel essai, nouveau <script>.
          return R.ensure(['coffeescript']);
        }).then(function() {
          throw new Error('ensure devait encore rejeter');
        }, function(err) {
          eq(attempts, 2);
          return restore();
        }).catch(function(e) {
          restore();
          throw e;
        });
      });
    });
  });

  describe('PluginRuntimes — résolution du compilateur', function() {
    it('reconnaît la forme du bundle (CoffeeScript.CoffeeScript.compile)', function() {
      return serial(function() {
        var fn;
        resetHead();
        fn = function() {
          return 'js';
        };
        // Forme réelle de /vendor/plugin-runtime.bundle.js (interop ESM de rollup).
        global.window.CoffeeScript = {
          CoffeeScript: {
            compile: fn
          }
        };
        eq(R.compiler('coffeescript'), fn, 'compilateur CoffeeScript non résolu');
        eq(R.compiler('javascript'), null, 'javascript ne doit pas avoir de compilateur');
        return R.ensure(['coffeescript']).then(function() {
          return eq(R.compiler('pug'), null, 'pug absent doit valoir null');
        }).catch(function(e) {
          throw e;
        });
      });
    });
    return it('reconnaît window.pug.compile et window.CoffeeScript.compile', function() {
      return serial(function() {
        var csCompile, pugCompile;
        resetHead();
        csCompile = function() {
          return 'js';
        };
        pugCompile = function() {
          return function() {
            return '<div></div>';
          };
        };
        global.window.CoffeeScript = {
          compile: csCompile
        };
        global.window.pug = {
          compile: pugCompile
        };
        eq(R.compiler('coffeescript'), csCompile);
        return eq(R.compiler('pug'), pugCompile);
      });
    });
  });

  describe('PluginRuntimes — Lua / MoonScript (wasmoon, spec §7)', function() {
    var installWasmoon;
    // Simulated wasmoon load: installs window.wasmoon then fires onload.
    installWasmoon = function(el) {
      global.window.wasmoon = {
        LuaFactory: function() {}
      };
      Promise.resolve().then(function() {
        return typeof el.onload === "function" ? el.onload() : void 0;
      });
      return el;
    };
    it('lua et moonscript chargent le même bundle wasmoon, une seule fois', function() {
      return serial(function() {
        var appended, head, oldAppend;
        head = resetHead();
        appended = [];
        oldAppend = head.appendChild;
        head.appendChild = function(el) {
          appended.push(el);
          return installWasmoon(el);
        };
        return Promise.all([R.ensure(['lua']), R.ensure(['moonscript'])]).then(function() {
          eq(appended.length, 1, 'un seul <script> pour lua et moonscript');
          eq(appended[0].getAttribute('src'), WASMOON);
          return R.ensure(['moonscript']);
        }).then(function() {
          return eq(appended.length, 1, 'aucun rechargement une fois le runtime présent');
        }).then(function() {
          return head.appendChild = oldAppend;
        }, function(e) {
          head.appendChild = oldAppend;
          throw e;
        });
      });
    });
    it('coffeescript et javascript ne chargent jamais wasmoon', function() {
      return serial(function() {
        var appended, head, oldAppend;
        head = resetHead();
        appended = [];
        oldAppend = head.appendChild;
        head.appendChild = function(el) {
          appended.push(el);
          global.window.CoffeeScript = {
            compile: function() {
              return 'js';
            }
          };
          Promise.resolve().then(function() {
            return typeof el.onload === "function" ? el.onload() : void 0;
          });
          return el;
        };
        return Promise.resolve().then(function() {
          return R.ensure(['javascript']);
        }).then(function() {
          eq(appended.length, 0, 'javascript ne charge rien');
          return R.ensure(['coffeescript']);
        }).then(function() {
          eq(appended.length, 1);
          return eq(appended[0].getAttribute('src'), BUNDLE, 'coffeescript charge plugin-runtime, pas wasmoon');
        }).then(function() {
          return head.appendChild = oldAppend;
        }, function(e) {
          head.appendChild = oldAppend;
          throw e;
        });
      });
    });
    it('déclare la compilation côté serveur pour lua et moonscript seulement', function() {
      eq(R.serverCompiled('lua'), true);
      eq(R.serverCompiled('moonscript'), true);
      eq(R.serverCompiled('coffeescript'), false);
      eq(R.serverCompiled('javascript'), false);
      return eq(R.serverCompiled('inconnu'), false);
    });
    it('expose le .wasm de wasmoon pour lua et moonscript', function() {
      eq(R.wasmSrc('lua'), WASMOON_WASM);
      eq(R.wasmSrc('moonscript'), WASMOON_WASM);
      eq(R.wasmSrc('coffeescript'), null);
      return eq(R.wasmSrc('javascript'), null);
    });
    return it('aucun compilateur JS pour lua/moonscript (compilés par Tarantool)', function() {
      resetHead();
      global.window.wasmoon = {
        LuaFactory: function() {}
      };
      eq(R.compiler('lua'), null);
      return eq(R.compiler('moonscript'), null);
    });
  });

  summary();

}).call(this);
