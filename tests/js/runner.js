(function() {
  // tests/js/runner.coffee — minimal test runner (aucune dépendance)
  var assert, currentSuite, deepEq, describe, eq, failed, it, passed, raises, summary;

  passed = 0;

  failed = 0;

  currentSuite = '';

  describe = function(name, fn) {
    currentSuite = name;
    return fn();
  };

  it = function(desc, fn) {
    var e;
    try {
      fn();
      return passed++;
    } catch (error) {
      e = error;
      failed++;
      console.error(`  ✗  ${currentSuite} — ${desc}`);
      return console.error(`     ${e.message}`);
    }
  };

  assert = function(cond, msg) {
    if (!cond) {
      throw new Error(msg || 'assertion échouée');
    }
  };

  eq = function(a, b, msg) {
    if (a !== b) {
      throw new Error(msg || `attendu ${JSON.stringify(b)}, obtenu ${JSON.stringify(a)}`);
    }
  };

  deepEq = function(a, b, msg) {
    var sa, sb;
    sa = JSON.stringify(a);
    sb = JSON.stringify(b);
    if (sa !== sb) {
      throw new Error(msg || `attendu ${sb}, obtenu ${sa}`);
    }
  };

  raises = function(fn, pattern) {
    var e, ok, threw;
    threw = false;
    try {
      fn();
    } catch (error) {
      e = error;
      threw = true;
      if (pattern) {
        ok = pattern instanceof RegExp ? pattern.test(e.message) : e.message.includes(pattern);
        if (!ok) {
          throw new Error(`erreur attendue contenant \"${pattern}\", obtenu: ${e.message}`);
        }
      }
    }
    if (!threw) {
      throw new Error('une erreur était attendue mais aucune levée');
    }
  };

  summary = function() {
    var total;
    total = passed + failed;
    console.log(`${total} assertions — ${passed} ✓  ${failed} ✗`);
    if (failed > 0) {
      console.log('RÉSULTAT: ÉCHEC');
      return process.exit(1);
    } else {
      return console.log('RÉSULTAT: SUCCÈS');
    }
  };

  module.exports = {describe, it, assert, eq, deepEq, raises, summary};

}).call(this);
