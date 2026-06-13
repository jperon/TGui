-- tests/test_index_html.moon
-- Garde-fou : le HTML de la SPA doit inclure tous les bundles vendor requis.
-- Un bundle oublié (cf. sortablejs.bundle.js absent) casse une fonctionnalité
-- silencieusement à l'exécution ; ce test l'attrape immédiatement.
R = require 'tests.runner'

render = require 'index'
html = render!

required_scripts = {
  '/vendor/tui-grid.bundle.js'
  '/vendor/jsyaml.bundle.js'
  '/vendor/codemirror.bundle.js'
  '/vendor/sortablejs.bundle.js'
  '/vendor/plugin-runtime.bundle.js'
}

R.describe "index.html — bundles vendor", ->
  for src in *required_scripts
    R.it "inclut #{src}", ->
      R.ok html\find(src, 1, true) != nil, "script manquant : #{src}"
