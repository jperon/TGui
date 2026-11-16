# tests/js/test_widget_lua_runtime.coffee
# Widgets Lua / MoonScript (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7) :
#   - le parent ne charge jamais wasmoon pour compiler : le code est déjà
#     compilé par Tarantool (`compiled`) ;
#   - l'iframe d'un widget lua/moonscript charge le registre de langages et
#     wasmoon, expose l'API comme global `widget` et exécute le chunk compilé ;
#   - une définition javascript ne mentionne ni wasmoon ni le registre.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

global.window.CustomView = -> null
global.GQL =
  query: -> Promise.resolve {}
  queryWidget: -> Promise.resolve { data: {} }
require '../../frontend/src/views/custom_view_plugins'
CV = global.window.CustomView.prototype

# Éditeur de plugins : mapping langage -> mode CodeMirror.
global.window.AppViewHelpers = {}
require '../../frontend/src/app_view_helpers_widget_plugins'
AVH = global.window.AppViewHelpers

# Registre réel côté navigateur, réduit à ce que _compilePlugin utilise.
state = calls: []
global.window.PluginRuntimes =
  serverCompiled: (lang) -> lang in ['lua', 'moonscript']
  wasmSrc: (lang) -> if lang in ['lua', 'moonscript'] then '/vendor/wasmoon.bundle.wasm' else null
  ensure: (langs) ->
    state.calls.push langs
    Promise.resolve()

# Les `it` asynchrones se résolvent après le lancement des suivants : on les
# sérialise pour que `state.calls` reste propre à chaque test.
_chain = Promise.resolve()
serial = (fn) ->
  p = _chain.then fn
  _chain = p.then (->), (->)
  p

LUA_SCRIPT = 'widget.render("<p>" .. tostring(widget.params.titre) .. "</p>")'
LUA_COMPILED = 'widget.render("<p>" .. tostring(widget.params.titre) .. "</p>")'
# Lua produit par moonscript.base.to_lua (forme réelle : parenthèses, retour).
MOON_COMPILED = 'return widget.render("bonjour")\n'

luaPlugin = (over = {}) ->
  Object.assign {
    name: 'widget_lua'
    scriptLanguage: 'lua'
    templateLanguage: 'html'
    scriptCode: LUA_SCRIPT
    templateCode: '<div class="plugin-root"></div>'
    compiled: LUA_COMPILED
  }, over

describe 'Widgets Lua/MoonScript — compilation côté parent', ->
  it 'ne charge aucun runtime pour lua (serveur) ni pour html', -> serial ->
    state.calls = []
    CV._compilePlugin.call CV, luaPlugin(), { titre: 'T' }
      .then (compiled) ->
        eq compiled.luaSource, LUA_COMPILED
        eq compiled.luaLanguage, 'lua'
        eq compiled.jsScript, ''
        calls = JSON.stringify state.calls
        eq calls, '[["html"]]',
          "seul le gabarit doit être demandé au registre, vu : #{calls}"

  it 'moonscript sans code compilé : erreur explicite, pas d’exécution', -> serial ->
    plugin = luaPlugin { scriptLanguage: 'moonscript', compiled: '' }
    CV._compilePlugin.call CV, plugin, {}
      .then(
        -> throw new Error 'la compilation devait échouer'
        (err) ->
          assert err.message.includes('MoonScript non compilé'),
            "message attendu, vu : #{err.message}"
      )

  it 'lua sans compiled : repli sur le source (déjà vérifié par le serveur)', -> serial ->
    CV._compilePlugin.call CV, luaPlugin({ compiled: '' }), {}
      .then (compiled) ->
        eq compiled.luaSource, LUA_SCRIPT

describe 'Widgets Lua/MoonScript — document de l’iframe', ->
  docFor = (compiled, plugin, ctx) ->
    CV._buildPluginIframeDoc 'w1', { titre: 'T' }, compiled, plugin, ctx

  it 'charge le registre de langages et wasmoon dans l’iframe', ->
    doc = docFor { luaSource: LUA_COMPILED, luaLanguage: 'lua', htmlTemplate: '<div>x</div>' },
      luaPlugin(), { access: 'read' }
    assert doc.includes("/src/views/plugin_runtimes.js"),
      'le registre de langages doit être chargé dans l’iframe'
    assert doc.includes('PluginRuntimes.ensure'),
      'l’iframe doit charger wasmoon via le registre'
    assert doc.includes("engine.global.set('widget', api)"),
      'l’API doit être exposée à Lua comme global widget'
    assert doc.includes('LuaFactory'), 'wasmoon (LuaFactory) doit être utilisé'
    assert doc.includes('unpack = table.unpack'),
      'unpack doit être fourni en alias de table.unpack'
    assert doc.includes('wasm_request'), 'l’iframe doit demander le binaire au parent'

  it 'lua : n’appelle pas module.exports, mais rend les erreurs Lua', ->
    doc = docFor { luaSource: LUA_COMPILED, luaLanguage: 'lua', htmlTemplate: '' },
      luaPlugin(), { access: 'full' }
    assert not doc.includes('module.exports === \'function\''),
      'un widget Lua ne doit pas passer par le contrat module.exports'
    assert doc.includes('renderLuaError'), 'les erreurs Lua doivent s’afficher dans le widget'

  it 'moonscript : le Lua compilé est exécuté, pas le source MoonScript', ->
    moonSource = 'widget.render "bonjour"'
    doc = docFor { luaSource: MOON_COMPILED, luaLanguage: 'moonscript', htmlTemplate: '' },
      luaPlugin({ scriptLanguage: 'moonscript', scriptCode: moonSource, compiled: MOON_COMPILED }),
      { access: 'read' }
    assert doc.includes('var luaSource ='), 'le chunk compilé doit être présent'
    assert doc.includes('"moonscript"'), 'le langage doit être transmis pour le registre'
    assert not doc.includes('widget.render \\"bonjour\\"'),
      'le source MoonScript ne doit pas être exécuté par le navigateur'

  it 'javascript ne charge ni wasmoon ni le registre de langages', ->
    doc = docFor { jsScript: 'widget.render("ok")', htmlTemplate: '' },
      { name: 'wb', scriptLanguage: 'javascript', templateLanguage: 'html' }, { access: 'full' }
    assert not doc.includes('wasmoon'), 'aucun wasmoon pour un widget javascript'
    assert not doc.includes('/src/views/plugin_runtimes.js'),
      'aucun registre de langages pour un widget javascript'
    assert doc.includes('module.exports === \'function\''), 'contrat JS conservé'

  it 'access none : ni gql ni API de données, seulement le rendu', ->
    doc = docFor { luaSource: LUA_COMPILED, luaLanguage: 'lua', htmlTemplate: '' },
      luaPlugin(), { access: 'none' }
    assert not doc.includes('api.gql = gql'), 'gql doit être absent avec access none'
    assert not doc.includes('api.onRecords'), 'onRecords doit être absent avec access none'
    assert doc.includes('render: render'), 'render reste disponible'

describe 'Widgets Lua/MoonScript — éditeur de plugins', ->
  it 'colore Lua, édite MoonScript en texte brut', ->
    eq AVH._widgetScriptEditorMode('lua'), 'lua'
    eq AVH._widgetScriptEditorMode('Lua'), 'lua'
    eq AVH._widgetScriptEditorMode('moonscript'), null
    eq AVH._widgetScriptEditorMode('coffeescript'), 'coffeescript'
    eq AVH._widgetScriptEditorMode(undefined), 'coffeescript'

summary()
