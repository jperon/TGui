-- tests/test_index_html.moon
-- Garde-fou : le HTML de la SPA doit inclure tous les bundles vendor requis.
-- Un bundle oublié (cf. sortablejs.bundle.js absent) casse une fonctionnalité
-- silencieusement à l'exécution ; ce test l'attrape immédiatement.
-- Les bundles LAZY (compilateurs de widgets, spec widgets personnalisés §7) ne
-- doivent PAS figurer dans la page : ils sont chargés à la demande par
-- frontend/src/views/plugin_runtimes.js, seulement si un widget en a besoin.
R = require 'tests.runner'

render = require 'index'
html = render!
scripts = require 'ui.scripts'

required_scripts = {
  '/vendor/tui-grid.bundle.js'
  '/vendor/jsyaml.bundle.js'
  '/vendor/codemirror.bundle.js'
  '/vendor/sortablejs.bundle.js'
}

R.describe "index.html — bundles vendor", ->
  for src in *required_scripts
    R.it "inclut #{src}", ->
      R.ok html\find(src, 1, true) != nil, "script manquant : #{src}"

R.describe "index.html — bundles chargés à la demande", ->
  R.it "ui.scripts exporte LAZY_SCRIPT_SRCS", ->
    R.eq type(scripts.LAZY_SCRIPT_SRCS), 'table', 'LAZY_SCRIPT_SRCS'

  R.it "le bundle des compilateurs de widgets n'est pas dans la page", ->
    for src in *(scripts.LAZY_SCRIPT_SRCS or {})
      R.ok html\find(src, 1, true) == nil,
        "bundle chargé à la demande présent dans la page : #{src}"

  R.it "le bundle des compilateurs est déclaré en lazy", ->
    found = false
    for src in *(scripts.LAZY_SCRIPT_SRCS or {})
      found = true if src == '/vendor/plugin-runtime.bundle.js'
    R.ok found, 'plugin-runtime.bundle.js absent de LAZY_SCRIPT_SRCS'
