# tests/js/test_plugin_runtimes.coffee — on-demand widget compiler loading
# Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7 (L6):
# `window.PluginRuntimes.ensure(langs)` inserts /vendor/plugin-runtime.bundle.js
# only for the languages a widget actually uses, once per session, with the
# promise shared by widgets mounted concurrently.

require './dom_stub'
{ describe, it, assert, eq, summary } = require './runner'

require '../../frontend/src/views/plugin_runtimes'
R = global.window.PluginRuntimes

BUNDLE = '/vendor/plugin-runtime.bundle.js'
WASMOON = '/vendor/wasmoon.bundle.js'
WASMOON_WASM = '/vendor/wasmoon.bundle.wasm'

# Le runner lance tous les `it` du fichier avant que les promesses ne se
# résolvent, et ces tests partagent des globales (window.CoffeeScript, …) et le
# <head> : on les sérialise explicitement.
_chain = Promise.resolve()
serial = (fn) ->
  p = _chain.then fn
  _chain = p.then (->), (->)
  p

# Fresh registry + DOM state; returns the <head> stub.
resetHead = ->
  R._reset()
  delete global.window.CoffeeScript
  delete global.window.pug
  delete global.window.wasmoon
  head = global.document.head
  head._children.length = 0
  head.children.length = 0
  head

describe 'PluginRuntimes — langages sans runtime', ->
  it 'javascript + html ne chargent rien', -> serial ->
    head = resetHead()
    appended = []
    oldAppend = head.appendChild
    head.appendChild = (el) -> appended.push el
    Promise.resolve()
      .then -> R.ensure ['javascript', 'html']
      .then ->
        eq appended.length, 0, 'aucun <script> ne doit être inséré'
      .then(
        -> head.appendChild = oldAppend
        (e) ->
          head.appendChild = oldAppend
          throw e
      )

  it 'un langage inconnu ne charge rien', -> serial ->
    head = resetHead()
    appended = []
    oldAppend = head.appendChild
    head.appendChild = (el) -> appended.push el
    Promise.resolve()
      .then -> R.ensure ['ruby']
      .then ->
        eq appended.length, 0
      .then(
        -> head.appendChild = oldAppend
        (e) ->
          head.appendChild = oldAppend
          throw e
      )

describe 'PluginRuntimes — chargement à la demande', ->
  it 'coffeescript insère le bundle une seule fois pour deux appels concurrents', -> serial ->
    head = resetHead()
    appended = []
    oldAppend = head.appendChild
    # Chargement simulé : le bundle installe ses globales puis onload.
    head.appendChild = (el) ->
      appended.push el
      global.window.CoffeeScript = { compile: -> 'js' }
      global.window.pug = { compile: -> -> '<div></div>' }
      Promise.resolve().then -> el.onload?()
      el
    Promise.all([R.ensure(['coffeescript']), R.ensure(['pug'])])
      .then ->
        eq appended.length, 1, 'un seul <script> pour les deux widgets'
        eq appended[0].getAttribute('src'), BUNDLE
        R.ensure ['coffeescript']
      .then ->
        eq appended.length, 1, 'aucun rechargement une fois le runtime présent'
      .then(
        -> head.appendChild = oldAppend
        (e) ->
          head.appendChild = oldAppend
          throw e
      )

  it 'un runtime déjà présent ne charge rien', -> serial ->
    head = resetHead()
    global.window.CoffeeScript = { compile: -> 'js' }
    appended = []
    oldAppend = head.appendChild
    head.appendChild = (el) -> appended.push el
    Promise.resolve()
      .then -> R.ensure ['coffeescript']
      .then ->
        eq appended.length, 0
      .then(
        -> head.appendChild = oldAppend
        (e) ->
          head.appendChild = oldAppend
          throw e
      )

  it 'échec de chargement : rejet explicite, puis nouvelle tentative possible', -> serial ->
    head = resetHead()
    attempts = 0
    oldAppend = head.appendChild
    head.appendChild = (el) ->
      attempts++
      el.onerror?()
      el
    restore = -> head.appendChild = oldAppend
    R.ensure ['coffeescript']
      .then(
        -> throw new Error 'ensure devait rejeter'
        (err) ->
          assert err.message.includes(BUNDLE),
            "le message doit nommer le bundle, vu : #{err.message}"
          assert err.message.includes('Échec du chargement'),
            "message attendu, vu : #{err.message}"
          eq attempts, 1
          # La promesse rejetée n'est pas mémorisée : nouvel essai, nouveau <script>.
          R.ensure ['coffeescript']
      )
      .then(
        -> throw new Error 'ensure devait encore rejeter'
        (err) ->
          eq attempts, 2
          restore()
      )
      .catch (e) ->
        restore()
        throw e

describe 'PluginRuntimes — résolution du compilateur', ->
  it 'reconnaît la forme du bundle (CoffeeScript.CoffeeScript.compile)', -> serial ->
    resetHead()
    fn = -> 'js'
    # Forme réelle de /vendor/plugin-runtime.bundle.js (interop ESM de rollup).
    global.window.CoffeeScript = { CoffeeScript: { compile: fn } }
    eq R.compiler('coffeescript'), fn, 'compilateur CoffeeScript non résolu'
    eq R.compiler('javascript'), null, 'javascript ne doit pas avoir de compilateur'
    R.ensure ['coffeescript']
      .then ->
        eq R.compiler('pug'), null, 'pug absent doit valoir null'
      .catch (e) -> throw e

  it 'reconnaît window.pug.compile et window.CoffeeScript.compile', -> serial ->
    resetHead()
    csCompile = -> 'js'
    pugCompile = -> -> '<div></div>'
    global.window.CoffeeScript = { compile: csCompile }
    global.window.pug = { compile: pugCompile }
    eq R.compiler('coffeescript'), csCompile
    eq R.compiler('pug'), pugCompile

describe 'PluginRuntimes — Lua / MoonScript (wasmoon, spec §7)', ->
  # Simulated wasmoon load: installs window.wasmoon then fires onload.
  installWasmoon = (el) ->
    global.window.wasmoon = { LuaFactory: -> }
    Promise.resolve().then -> el.onload?()
    el

  it 'lua et moonscript chargent le même bundle wasmoon, une seule fois', -> serial ->
    head = resetHead()
    appended = []
    oldAppend = head.appendChild
    head.appendChild = (el) ->
      appended.push el
      installWasmoon el
    Promise.all([R.ensure(['lua']), R.ensure(['moonscript'])])
      .then ->
        eq appended.length, 1, 'un seul <script> pour lua et moonscript'
        eq appended[0].getAttribute('src'), WASMOON
        R.ensure ['moonscript']
      .then ->
        eq appended.length, 1, 'aucun rechargement une fois le runtime présent'
      .then(
        -> head.appendChild = oldAppend
        (e) ->
          head.appendChild = oldAppend
          throw e
      )

  it 'coffeescript et javascript ne chargent jamais wasmoon', -> serial ->
    head = resetHead()
    appended = []
    oldAppend = head.appendChild
    head.appendChild = (el) ->
      appended.push el
      global.window.CoffeeScript = { compile: -> 'js' }
      Promise.resolve().then -> el.onload?()
      el
    Promise.resolve()
      .then -> R.ensure ['javascript']
      .then ->
        eq appended.length, 0, 'javascript ne charge rien'
        R.ensure ['coffeescript']
      .then ->
        eq appended.length, 1
        eq appended[0].getAttribute('src'), BUNDLE,
          'coffeescript charge plugin-runtime, pas wasmoon'
      .then(
        -> head.appendChild = oldAppend
        (e) ->
          head.appendChild = oldAppend
          throw e
      )

  it 'déclare la compilation côté serveur pour lua et moonscript seulement', ->
    eq R.serverCompiled('lua'), true
    eq R.serverCompiled('moonscript'), true
    eq R.serverCompiled('coffeescript'), false
    eq R.serverCompiled('javascript'), false
    eq R.serverCompiled('inconnu'), false

  it 'expose le .wasm de wasmoon pour lua et moonscript', ->
    eq R.wasmSrc('lua'), WASMOON_WASM
    eq R.wasmSrc('moonscript'), WASMOON_WASM
    eq R.wasmSrc('coffeescript'), null
    eq R.wasmSrc('javascript'), null

  it 'aucun compilateur JS pour lua/moonscript (compilés par Tarantool)', ->
    resetHead()
    global.window.wasmoon = { LuaFactory: -> }
    eq R.compiler('lua'), null
    eq R.compiler('moonscript'), null

summary()
