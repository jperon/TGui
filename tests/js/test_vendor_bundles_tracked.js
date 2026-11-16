(function() {
  // tests/js/test_vendor_bundles_tracked.coffee — guard against 404 vendor bundles
  // Every /vendor/... path referenced by the page must be a git-tracked file.
  // Otherwise a fresh clone (CI, new install) serves it as 404 and the page breaks
  // silently (e.g. "SortableJS is not defined on window").
  // See AGENTS.md, "Vendor frontend".

  // Bundle chargés à la demande (spec widgets personnalisés §7) : ils ne sont pas
  // dans la page, mais frontend/src/views/plugin_runtimes.js les insère plus tard ;
  // ils doivent donc être committés tout autant. La liste LAZY_SCRIPT_SRCS de
  // backend/ui/scripts.moon est contrôlée séparément.
  var PAGE_SOURCES, ROOT, VENDOR_PATH_RE, assert, assertTracked, describe, execFileSync, extractLazyVendorPaths, extractVendorPaths, extractWasmVendorPaths, fs, isTracked, it, path, summary,
    indexOf = [].indexOf;

  ({execFileSync} = require('child_process'));

  path = require('path');

  fs = require('fs');

  ({describe, it, assert, summary} = require('./runner'));

  ROOT = path.resolve(__dirname, '..', '..');

  // Sources that reference the static vendor assets: the <script src> list and
  // the <link rel="stylesheet"> tags of the SPA shell.
  PAGE_SOURCES = ['backend/ui/scripts.moon', 'backend/index.moon'];

  VENDOR_PATH_RE = /\/vendor\/[A-Za-z0-9_.-]+/g;

  // Union of the /vendor/... paths found in the page sources, sorted.
  extractVendorPaths = function() {
    var found, i, j, len, len1, ref, rel, seen, src;
    seen = {};
    for (i = 0, len = PAGE_SOURCES.length; i < len; i++) {
      rel = PAGE_SOURCES[i];
      src = fs.readFileSync(path.join(ROOT, rel), 'utf8');
      ref = (src.match(VENDOR_PATH_RE)) || [];
      for (j = 0, len1 = ref.length; j < len1; j++) {
        found = ref[j];
        seen[found] = true;
      }
    }
    return Object.keys(seen).sort();
  };

  // /vendor/... paths declared in LAZY_SCRIPT_SRCS (on-demand bundles).
  extractLazyVendorPaths = function() {
    var block, found, src;
    src = fs.readFileSync(path.join(ROOT, 'backend/ui/scripts.moon'), 'utf8');
    block = src.match(/LAZY_SCRIPT_SRCS\s*=\s*\{([\s\S]*?)\}/);
    assert(block, 'LAZY_SCRIPT_SRCS introuvable dans backend/ui/scripts.moon');
    found = block[1].match(VENDOR_PATH_RE || []);
    return found.sort();
  };

  // /vendor/... WebAssembly binaries declared by the language registry
  // (`wasm:` entries of frontend/src/views/plugin_runtimes.coffee). A missing
  // .wasm makes every Lua/MoonScript widget fail at runtime, never at page load.
  extractWasmVendorPaths = function() {
    var found, m, pattern, src;
    src = fs.readFileSync(path.join(ROOT, 'frontend/src/views/plugin_runtimes.coffee'), 'utf8');
    found = [];
    pattern = /wasm:\s*'(\/vendor\/[A-Za-z0-9_.-]+)'/g;
    while ((m = pattern.exec(src))) {
      found.push(m[1]);
    }
    return found.sort();
  };

  // True when git tracks +filePath+ in this checkout.
  isTracked = function(filePath) {
    var e;
    try {
      execFileSync('git', ['ls-files', '--error-unmatch', '--', filePath], {
        cwd: ROOT,
        stdio: 'pipe'
      });
      return true;
    } catch (error) {
      e = error;
      return false;
    }
  };

  assertTracked = function(vendorPath, why) {
    var filePath;
    filePath = path.posix.join('frontend', vendorPath);
    return assert(isTracked(filePath), `le bundle ${vendorPath} ${why} mais ${filePath} ` + "n'est pas suivi par git : un clone neuf le recevra en 404. " + `Committer ${filePath} et l'autoriser dans .gitignore ` + '(voir AGENTS.md, « Vendor frontend »).');
  };

  describe('Vendor bundles loaded by the page', function() {
    var i, len, results, vendorPath, vendorPaths;
    vendorPaths = extractVendorPaths();
    it('extrait des chemins /vendor/ depuis les sources de la page', function() {
      return assert(vendorPaths.length > 0, `aucun chemin /vendor/ extrait de ${PAGE_SOURCES.join(', ')} : ` + 'le motif VENDOR_PATH_RE du test est cassé');
    });
    results = [];
    for (i = 0, len = vendorPaths.length; i < len; i++) {
      vendorPath = vendorPaths[i];
      results.push((function(vendorPath) {
        return it(`${vendorPath} est suivi par git`, function() {
          return assertTracked(vendorPath, 'est référencé par la page');
        });
      })(vendorPath));
    }
    return results;
  });

  describe('Vendor bundles loaded on demand (LAZY_SCRIPT_SRCS)', function() {
    var i, lazyPaths, len, results, vendorPath;
    lazyPaths = extractLazyVendorPaths();
    it('LAZY_SCRIPT_SRCS déclare les bundles des compilateurs de widgets', function() {
      assert(lazyPaths.length > 0, 'LAZY_SCRIPT_SRCS est vide : les compilateurs de widgets ne seraient ' + 'plus chargeables à la demande');
      assert(indexOf.call(lazyPaths, '/vendor/plugin-runtime.bundle.js') >= 0, `plugin-runtime.bundle.js absent de LAZY_SCRIPT_SRCS (${lazyPaths.join(', ')})`);
      return assert(indexOf.call(lazyPaths, '/vendor/wasmoon.bundle.js') >= 0, `wasmoon.bundle.js absent de LAZY_SCRIPT_SRCS (${lazyPaths.join(', ')})`);
    });
    results = [];
    for (i = 0, len = lazyPaths.length; i < len; i++) {
      vendorPath = lazyPaths[i];
      results.push((function(vendorPath) {
        return it(`${vendorPath} est suivi par git`, function() {
          return assertTracked(vendorPath, 'est chargé à la demande');
        });
      })(vendorPath));
    }
    return results;
  });

  describe('Binaires WebAssembly des runtimes de widgets', function() {
    var i, len, results, vendorPath, wasmPaths;
    wasmPaths = extractWasmVendorPaths();
    it('le registre de langages déclare le .wasm de wasmoon', function() {
      assert(wasmPaths.length > 0, 'aucun chemin wasm: extrait de frontend/src/views/plugin_runtimes.coffee');
      return assert(indexOf.call(wasmPaths, '/vendor/wasmoon.bundle.wasm') >= 0, `wasmoon.bundle.wasm absent du registre (${wasmPaths.join(', ')})`);
    });
    results = [];
    for (i = 0, len = wasmPaths.length; i < len; i++) {
      vendorPath = wasmPaths[i];
      results.push((function(vendorPath) {
        return it(`${vendorPath} est suivi par git`, function() {
          return assertTracked(vendorPath, 'est chargé à la demande');
        });
      })(vendorPath));
    }
    return results;
  });

  summary();

}).call(this);
