(function() {
  // plugin_runtimes.coffee — widget compilers loaded on demand.

  // Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7 (L6, L7).
  // The CoffeeScript/pug bundle is no longer a page script
  // (backend/ui/scripts.moon SCRIPT_SRCS): it is fetched the first time a widget
  // definition actually needs it, so a `javascript` + `html` widget — the common
  // case — loads nothing.

  // `ensure(langs)` inserts the missing <script src> tag(s) once and returns a
  // promise memoised per bundle, shared by every widget mounted concurrently. On
  // failure it rejects with an explicit message (custom_view_plugins.coffee shows
  // it in the widget, never swallows it) and drops the memo so a later widget may
  // retry after a transient network error.

  // Lua / MoonScript (wasmoon, §7 phase 2) only need new LANGUAGES entries.

  // lang -> { lang, src, runtime }. `runtime()` returns the global installed by
  // the bundle; a language absent from this table (javascript, html, unknown)
  // needs nothing. Lua / MoonScript (wasmoon, §7 phase 2) will add entries here.
  var LANGUAGES, _compileFn, _loadScript, _ready, compiler, ensure, loads,
    indexOf = [].indexOf;

  LANGUAGES = {
    coffeescript: {
      lang: 'coffeescript',
      src: '/vendor/plugin-runtime.bundle.js',
      runtime: function() {
        return window.CoffeeScript;
      }
    },
    pug: {
      lang: 'pug',
      src: '/vendor/plugin-runtime.bundle.js',
      runtime: function() {
        return window.pug;
      }
    }
  };

  // Le bundle expose le compilateur CoffeeScript sous `window.CoffeeScript.CoffeeScript`
  // (interop ESM/CJS de rollup) et pug directement sous `window.pug` ; `default`
  // couvre les autres formes d'export. Même résolution pour `ready`/`compiler`.
  _compileFn = function(runtime) {
    var ref, ref1;
    return (runtime != null ? runtime.compile : void 0) || (runtime != null ? (ref = runtime.default) != null ? ref.compile : void 0 : void 0) || (runtime != null ? (ref1 = runtime.CoffeeScript) != null ? ref1.compile : void 0 : void 0);
  };

  _ready = function(spec) {
    return typeof _compileFn(spec.runtime()) === 'function';
  };

  // src -> Promise. One entry per bundle: concurrent widgets share the same load.
  loads = {};

  _loadScript = function(src) {
    var doc, head, promise, script, state;
    if (loads[src]) {
      return loads[src];
    }
    // Les résolveurs sont capturés d'abord : l'insertion du <script> a lieu après
    // l'enregistrement dans `loads`, sinon un `onerror` synchrone (bundle absent)
    // ne pourrait pas retirer la promesse rejetée de la mémoire.
    state = {};
    promise = new Promise(function(resolve, reject) {
      state.resolve = resolve;
      return state.reject = reject;
    });
    loads[src] = promise;
    doc = document;
    head = doc.head || doc.body || doc.documentElement;
    if (!(head && typeof head.appendChild === 'function')) {
      delete loads[src];
      state.reject(new Error(`Chargement de ${src} impossible : document sans <head>`));
      return promise;
    }
    script = doc.createElement('script');
    script.setAttribute('src', src);
    script.setAttribute('data-plugin-runtime', src);
    script.onload = function() {
      return state.resolve(src);
    };
    script.onerror = function() {
      if (loads[src] === promise) {
        delete loads[src];
      }
      if (typeof head.removeChild === 'function' && script.parentNode) {
        head.removeChild(script);
      }
      return state.reject(new Error(`Échec du chargement de ${src} : compilateur de widget indisponible`));
    };
    head.appendChild(script);
    return promise;
  };

  // Resolve when every compiler needed by `langs` is usable. Languages needing no
  // runtime (javascript, html) resolve immediately without touching the DOM.
  ensure = function(langs) {
    var i, j, jobs, lang, len, len1, ref, ref1, s, spec, specs, src, srcs, users;
    specs = [];
    srcs = [];
    ref = langs || [];
    for (i = 0, len = ref.length; i < len; i++) {
      lang = ref[i];
      spec = LANGUAGES[String(lang || '').toLowerCase()];
      if (!spec) {
        continue;
      }
      specs.push(spec);
      if (ref1 = spec.src, indexOf.call(srcs, ref1) < 0) {
        srcs.push(spec.src);
      }
    }
    if (!(specs.length > 0)) {
      return Promise.resolve();
    }
    jobs = [];
    for (j = 0, len1 = srcs.length; j < len1; j++) {
      src = srcs[j];
      users = (function() {
        var k, len2, results;
        results = [];
        for (k = 0, len2 = specs.length; k < len2; k++) {
          s = specs[k];
          if (s.src === src) {
            results.push(s);
          }
        }
        return results;
      })();
      if (users.every(function(s) {
        return _ready(s);
      })) {
        continue;
      }
      jobs.push(_loadScript(src));
    }
    return Promise.all(jobs).then(function() {
      var missing;
      missing = (function() {
        var k, len2, results;
        results = [];
        for (k = 0, len2 = specs.length; k < len2; k++) {
          s = specs[k];
          if (!_ready(s)) {
            results.push(s.lang);
          }
        }
        return results;
      })();
      if (!(missing.length > 0)) {
        return;
      }
      throw new Error(`Compilateur(s) de widget indisponible(s) : ${missing.join(', ')}`);
    });
  };

  // Compilateur utilisable pour `lang`, ou null. Utilisé par _compilePluginCode :
  // une seule résolution, partagée avec `ensure`.
  compiler = function(lang) {
    var fn, spec;
    spec = LANGUAGES[String(lang || '').toLowerCase()];
    if (!spec) {
      return null;
    }
    fn = _compileFn(spec.runtime());
    if (typeof fn === 'function') {
      return fn;
    } else {
      return null;
    }
  };

  window.PluginRuntimes = {
    ensure: ensure,
    compiler: compiler,
    languages: LANGUAGES,
    // Tests only: forget memoised loads (the DOM and the globals stay as they are).
    _reset: function() {
      return loads = {};
    }
  };

}).call(this);
