(function() {
  // tests/js/test_view_helpers_dedup.coffee
  // T11 refactor guard: AppViewHelpers must not define any key twice, and every
  // AppViewHelpers._xxx call site in frontend/src must have a definition.

  // Pre-existing gaps (called but never defined before T11 either — not invented here):
  //   _populateGroupByOptions, _confirmAddWidget, _closeAddWidgetModal
  // These were only reachable from dead/discarded code or from a missing resolver
  // in _initializeWidgetModal; the refactor keeps that runtime behaviour.
  var ALLOW_MISSING, HELPERS_PREFIX, SRC_DIR, assert, describe, eq, extractCallSites, extractDefinedKeys, fs, it, listHelperFiles, path, summary,
    indexOf = [].indexOf;

  fs = require('fs');

  path = require('path');

  ({describe, it, eq, assert, summary} = require('./runner'));

  SRC_DIR = path.join(__dirname, '../../frontend/src');

  HELPERS_PREFIX = 'app_view_helpers';

  // Pre-existing call sites without definitions (documented, not invented)
  ALLOW_MISSING = ['_populateGroupByOptions', '_confirmAddWidget', '_closeAddWidgetModal'];

  listHelperFiles = function() {
    var prefixRe;
    prefixRe = new RegExp(`^${HELPERS_PREFIX}.*\\.coffee$`);
    return fs.readdirSync(SRC_DIR).filter(function(f) {
      return prefixRe.test(f);
    }).sort().map(function(f) {
      return path.join(SRC_DIR, f);
    });
  };

  // Extract keys defined on window.AppViewHelpers in a helper source.
  // Matches:
  //   window.AppViewHelpers =\n  key: ...
  //   Object.assign window.AppViewHelpers,\n  key: ...
  //   window.AppViewHelpers.key = ...
  extractDefinedKeys = function(content, file) {
    var heredoc, i, keys, l, line, lines, m, quotes, tripleDouble, tripleSingle;
    keys = [];
    lines = content.split('\n');
    i = 0;
    while (i < lines.length) {
      line = lines[i];
      if (/^window\.AppViewHelpers\s*=\s*$/.test(line) || /^Object\.assign\s+window\.AppViewHelpers\s*,\s*$/.test(line)) {
        i++;
        heredoc = false;
        while (i < lines.length) {
          l = lines[i];
          // track """ / ''' heredocs: column-0 lines inside them must not end the object
          tripleDouble = (l.match(new RegExp('"""', 'g')) || []).length;
          tripleSingle = (l.match(new RegExp("'''", 'g')) || []).length;
          quotes = tripleDouble + tripleSingle;
          if (quotes % 2 === 1) {
            heredoc = !heredoc;
            m = l.match(/^  ([A-Za-z_][A-Za-z0-9_]*)\s*:/);
            if (m && !heredoc) {
              keys.push(m[1]);
            }
            i++;
            continue;
          }
          if (heredoc) {
            i++;
            continue;
          }
          if (l.trim() === '') {
            i++;
            continue;
          }
          if (l[0] !== ' ') {
            break;
          }
          m = l.match(/^  ([A-Za-z_][A-Za-z0-9_]*)\s*:/);
          if (m) {
            keys.push(m[1]);
          }
          i++;
        }
      } else {
        m = line.match(/^window\.AppViewHelpers\.([A-Za-z_][A-Za-z0-9_]*)\s*=/);
        if (m) {
          keys.push(m[1]);
        }
      }
      i++;
    }
    return {file, keys};
  };

  // Collect AppViewHelpers.<name> call sites in frontend/src (excluding compiled .js)
  extractCallSites = function() {
    var calls, walk;
    calls = [];
    walk = function(dir) {
      var content, entry, full, len, m, o, re, ref, results, st;
      ref = fs.readdirSync(dir);
      results = [];
      for (o = 0, len = ref.length; o < len; o++) {
        entry = ref[o];
        full = path.join(dir, entry);
        st = fs.statSync(full);
        if (st.isDirectory()) {
          results.push(walk(full));
        } else if (entry.match(/\.coffee$/)) {
          content = fs.readFileSync(full, 'utf8');
          re = /(?:window\.)?AppViewHelpers\.([A-Za-z_][A-Za-z0-9_]*)/g;
          results.push((function() {
            var results1;
            results1 = [];
            while ((m = re.exec(content))) {
              results1.push(calls.push({
                name: m[1],
                file: full
              }));
            }
            return results1;
          })());
        } else {
          results.push(void 0);
        }
      }
      return results;
    };
    walk(SRC_DIR);
    return calls;
  };

  describe('AppViewHelpers source integrity', function() {
    var allKeys, content, f, helpers, len, o;
    helpers = listHelperFiles();
    allKeys = [];
    for (o = 0, len = helpers.length; o < len; o++) {
      f = helpers[o];
      content = fs.readFileSync(f, 'utf8');
      allKeys.push(extractDefinedKeys(content, f));
    }
    it('trouve les fichiers app_view_helpers*.coffee', function() {
      return assert(helpers.length >= 2, `au moins 2 fichiers attendus, trouvé ${helpers.length}`);
    });
    it('n\'a aucune clé définie deux fois sur AppViewHelpers', function() {
      var dups, file, k, keys, len1, len2, p, q, seen;
      seen = {};
      dups = [];
      for (p = 0, len1 = allKeys.length; p < len1; p++) {
        ({file, keys} = allKeys[p]);
        for (q = 0, len2 = keys.length; q < len2; q++) {
          k = keys[q];
          if (seen[k]) {
            dups.push(`${k} (${seen[k]} et ${file})`);
          } else {
            seen[k] = file;
          }
        }
      }
      return eq(dups.length, 0, `clés dupliquées: ${dups.join(', ')}`);
    });
    it('n\'utilise pas de module.exports de fichier dans les helpers navigateur', function() {
      var idx, inHeredoc, j, len1, len2, line, lines, offenders, p, q, r, ref;
      offenders = [];
      for (p = 0, len1 = helpers.length; p < len1; p++) {
        f = helpers[p];
        content = fs.readFileSync(f, 'utf8');
        lines = content.split('\n');
        for (idx = q = 0, len2 = lines.length; q < len2; idx = ++q) {
          line = lines[idx];
          if (line.match(/^\s*module\.exports\s*=/)) {
            // ignore module.exports inside a plugin template string (scriptCode heredoc)
            continue;
          }
          // real file-level export would be at column 0 outside a string; after
          // CoffeeScript compile it never appears. In .coffee, a top-level
          // `module.exports =` at column 0 that is NOT inside """ is an offender.
          if (/^module\.exports\s*=/.test(line)) {
            // check if we are inside a """ heredoc by scanning upward
            inHeredoc = false;
            for (j = r = 0, ref = idx; (0 <= ref ? r < ref : r > ref); j = 0 <= ref ? ++r : --r) {
              if (lines[j].match(/"""\s*$/)) {
                inHeredoc = !inHeredoc;
              }
            }
            if (!inHeredoc) {
              offenders.push(`${f}:${idx + 1}`);
            }
          }
        }
      }
      return eq(offenders.length, 0, `module.exports hors heredoc: ${offenders.join(', ')}`);
    });
    it('définit chaque fonction appelée via AppViewHelpers (sauf lacunes préexistantes)', function() {
      var defined, file, k, keys, len1, len2, len3, missing, name, names, p, q, r, ref;
      defined = {};
      for (p = 0, len1 = allKeys.length; p < len1; p++) {
        ({keys} = allKeys[p]);
        for (q = 0, len2 = keys.length; q < len2; q++) {
          k = keys[q];
          defined[k] = true;
        }
      }
      missing = {};
      ref = extractCallSites();
      for (r = 0, len3 = ref.length; r < len3; r++) {
        ({name, file} = ref[r]);
        if (defined[name]) {
          continue;
        }
        if (indexOf.call(ALLOW_MISSING, name) >= 0) {
          continue;
        }
        if (missing[name] == null) {
          missing[name] = [];
        }
        missing[name].push(path.basename(file));
      }
      names = Object.keys(missing).sort();
      return eq(names.length, 0, `appels sans définition: ${names.map(function(n) {
        return n + ' (' + missing[n].join(',') + ')';
      }).join(', ')}`);
    });
    return it('garde les lacunes préexistantes documentées (pas de fuite silencieuse)', function() {
      // _populateGroupByOptions is called from _initializeWidgetModal but was
      // never defined before T11 either. Allowlist must stay explicit.
      assert(indexOf.call(ALLOW_MISSING, '_populateGroupByOptions') >= 0);
      assert(indexOf.call(ALLOW_MISSING, '_confirmAddWidget') >= 0);
      return assert(indexOf.call(ALLOW_MISSING, '_closeAddWidgetModal') >= 0);
    });
  });

  summary();

}).call(this);
