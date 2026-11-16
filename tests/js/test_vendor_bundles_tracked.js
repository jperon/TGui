(function() {
  // tests/js/test_vendor_bundles_tracked.coffee — guard against 404 vendor bundles
  // Every /vendor/... path referenced by the page must be a git-tracked file.
  // Otherwise a fresh clone (CI, new install) serves it as 404 and the page breaks
  // silently (e.g. "SortableJS is not defined on window").
  // See AGENTS.md, "Vendor frontend".
  var PAGE_SOURCES, ROOT, VENDOR_PATH_RE, assert, describe, execFileSync, extractVendorPaths, fs, isTracked, it, path, summary;

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
          var filePath;
          filePath = path.posix.join('frontend', vendorPath);
          return assert(isTracked(filePath), `le bundle ${vendorPath} est chargé par la page mais ${filePath} ` + "n'est pas suivi par git : un clone neuf le recevra en 404. " + `Committer ${filePath} et l'autoriser dans .gitignore ` + '(voir AGENTS.md, « Vendor frontend »).');
        });
      })(vendorPath));
    }
    return results;
  });

  summary();

}).call(this);
