(function() {
  // tests/js/runner.coffee — minimal test runner (no dependencies)
  var _pending, assert, currentSuite, deepEq, describe, eq, failed, it, passed, raises, summary;

  passed = 0;

  failed = 0;

  _pending = []; // pending promises (async it())

  currentSuite = '';

  describe = function(name, fn) {
    currentSuite = name;
    return fn();
  };

  it = function(desc, fn) {
    var e, result;
    result = void 0;
    try {
      result = fn();
    } catch (error) {
      e = error;
      failed++;
      console.error(`  ✗  ${currentSuite} — ${desc}`);
      console.error(`     ${e.message}`);
      return;
    }
    if (result && typeof result.then === 'function') {
      // async it(): track the promise
      return _pending.push(result.then(function() {
        return passed++;
      }, function(e) {
        failed++;
        console.error(`  ✗  ${currentSuite} — ${desc}`);
        return console.error(`     ${e.message}`);
      }));
    } else {
      return passed++;
    }
  };

  assert = function(cond, msg) {
    if (!cond) {
      throw new Error(msg || 'assertion failed');
    }
  };

  eq = function(a, b, msg) {
    if (a !== b) {
      throw new Error(msg || `expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
    }
  };

  deepEq = function(a, b, msg) {
    var sa, sb;
    sa = JSON.stringify(a);
    sb = JSON.stringify(b);
    if (sa !== sb) {
      throw new Error(msg || `expected ${sb}, got ${sa}`);
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
          throw new Error(`expected error containing \"${pattern}\", got: ${e.message}`);
        }
      }
    }
    if (!threw) {
      throw new Error('an error was expected but none was raised');
    }
  };

  summary = function() {
    var finish;
    finish = function() {
      var total;
      total = passed + failed;
      console.log(`${total} assertions — ${passed} ✓  ${failed} ✗`);
      if (failed > 0) {
        console.log('RESULT: FAILURE');
        return process.exit(1);
      } else {
        return console.log('RESULT: SUCCESS');
      }
    };
    if (_pending.length > 0) {
      return Promise.all(_pending).then(finish);
    } else {
      return finish();
    }
  };

  module.exports = {describe, it, assert, eq, deepEq, raises, summary};

}).call(this);
