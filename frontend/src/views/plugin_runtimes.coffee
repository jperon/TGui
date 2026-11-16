# plugin_runtimes.coffee — widget compilers loaded on demand.
#
# Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7 (L6, L7).
# The CoffeeScript/pug bundle is no longer a page script
# (backend/ui/scripts.moon SCRIPT_SRCS): it is fetched the first time a widget
# definition actually needs it, so a `javascript` + `html` widget — the common
# case — loads nothing.
#
# `ensure(langs)` inserts the missing <script src> tag(s) once and returns a
# promise memoised per bundle, shared by every widget mounted concurrently. On
# failure it rejects with an explicit message (custom_view_plugins.coffee shows
# it in the widget, never swallows it) and drops the memo so a later widget may
# retry after a transient network error.
#
# Lua / MoonScript (wasmoon, §7 phase 2) only need new LANGUAGES entries.

# lang -> { lang, src, runtime }. `runtime()` returns the global installed by
# the bundle; a language absent from this table (javascript, html, unknown)
# needs nothing. Lua / MoonScript (wasmoon, §7 phase 2) will add entries here.
LANGUAGES =
  coffeescript:
    lang: 'coffeescript'
    src: '/vendor/plugin-runtime.bundle.js'
    runtime: -> window.CoffeeScript
  pug:
    lang: 'pug'
    src: '/vendor/plugin-runtime.bundle.js'
    runtime: -> window.pug

# Le bundle expose le compilateur CoffeeScript sous `window.CoffeeScript.CoffeeScript`
# (interop ESM/CJS de rollup) et pug directement sous `window.pug` ; `default`
# couvre les autres formes d'export. Même résolution pour `ready`/`compiler`.
_compileFn = (runtime) ->
  runtime?.compile or runtime?.default?.compile or runtime?.CoffeeScript?.compile

_ready = (spec) -> typeof _compileFn(spec.runtime()) == 'function'

# src -> Promise. One entry per bundle: concurrent widgets share the same load.
loads = {}

_loadScript = (src) ->
  return loads[src] if loads[src]
  # Les résolveurs sont capturés d'abord : l'insertion du <script> a lieu après
  # l'enregistrement dans `loads`, sinon un `onerror` synchrone (bundle absent)
  # ne pourrait pas retirer la promesse rejetée de la mémoire.
  state = {}
  promise = new Promise (resolve, reject) ->
    state.resolve = resolve
    state.reject = reject
  loads[src] = promise
  doc = document
  head = doc.head or doc.body or doc.documentElement
  unless head and typeof head.appendChild == 'function'
    delete loads[src]
    state.reject new Error "Chargement de #{src} impossible : document sans <head>"
    return promise
  script = doc.createElement 'script'
  script.setAttribute 'src', src
  script.setAttribute 'data-plugin-runtime', src
  script.onload = -> state.resolve src
  script.onerror = ->
    delete loads[src] if loads[src] == promise
    if typeof head.removeChild == 'function' and script.parentNode
      head.removeChild script
    state.reject new Error "Échec du chargement de #{src} : compilateur de widget indisponible"
  head.appendChild script
  promise

# Resolve when every compiler needed by `langs` is usable. Languages needing no
# runtime (javascript, html) resolve immediately without touching the DOM.
ensure = (langs) ->
  specs = []
  srcs = []
  for lang in (langs or [])
    spec = LANGUAGES[String(lang or '').toLowerCase()]
    continue unless spec
    specs.push spec
    srcs.push spec.src unless spec.src in srcs
  return Promise.resolve() unless specs.length > 0
  jobs = []
  for src in srcs
    users = (s for s in specs when s.src == src)
    continue if users.every (s) -> _ready s
    jobs.push _loadScript src
  Promise.all(jobs).then ->
    missing = (s.lang for s in specs when not _ready s)
    return unless missing.length > 0
    throw new Error "Compilateur(s) de widget indisponible(s) : #{missing.join ', '}"

# Compilateur utilisable pour `lang`, ou null. Utilisé par _compilePluginCode :
# une seule résolution, partagée avec `ensure`.
compiler = (lang) ->
  spec = LANGUAGES[String(lang or '').toLowerCase()]
  return null unless spec
  fn = _compileFn spec.runtime()
  if typeof fn == 'function' then fn else null

window.PluginRuntimes =
  ensure: ensure
  compiler: compiler
  languages: LANGUAGES
  # Tests only: forget memoised loads (the DOM and the globals stay as they are).
  _reset: -> loads = {}
