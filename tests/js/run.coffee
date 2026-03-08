# tests/js/run.coffee — lance tous les fichiers test_*.coffee en séquence
# Usage : coffee tests/js/run.coffee

{ execFileSync } = require 'child_process'
path = require 'path'
fs   = require 'fs'

dir   = __dirname
files = fs.readdirSync(dir).filter (f) -> f.match /^test_.*\.coffee$/

failed = 0
for f in files
  console.log "\n─── #{f} ───"
  try
    execFileSync 'coffee', [path.join dir, f], stdio: 'inherit'
  catch
    failed++

if failed > 0
  console.log "\n#{failed} suite(s) en échec"
  process.exit 1
else
  console.log "\nToutes les suites JS : SUCCÈS"
