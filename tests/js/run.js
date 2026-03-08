(function() {
  // tests/js/run.coffee — lance tous les fichiers test_*.coffee en séquence
  // Usage : coffee tests/js/run.coffee
  var dir, execFileSync, f, failed, files, fs, i, len, path;

  ({execFileSync} = require('child_process'));

  path = require('path');

  fs = require('fs');

  dir = __dirname;

  files = fs.readdirSync(dir).filter(function(f) {
    return f.match(/^test_.*\.coffee$/);
  });

  failed = 0;

  for (i = 0, len = files.length; i < len; i++) {
    f = files[i];
    console.log(`\n─── ${f} ───`);
    try {
      execFileSync('coffee', [path.join(dir, f)], {
        stdio: 'inherit'
      });
    } catch (error) {
      failed++;
    }
  }

  if (failed > 0) {
    console.log(`\n${failed} suite(s) en échec`);
    process.exit(1);
  } else {
    console.log("\nToutes les suites JS : SUCCÈS");
  }

}).call(this);
