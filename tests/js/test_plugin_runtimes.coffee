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

summary()
