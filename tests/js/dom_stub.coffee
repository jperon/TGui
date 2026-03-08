# tests/js/dom_stub.coffee — stub DOM minimal pour Node.js
# Expose global.window, global.document (pas de dépendance jsdom)

makeElement = (tag) ->
  classes = new Set()
  el =
    tagName: tag.toUpperCase()
    style: {}
    className: ''
    textContent: ''
    innerHTML: ''
    title: ''
    dataset: {}
    _children: []
    _listeners: {}
    children: []           # alias synchronisé par appendChild
    classList:
      add: (c) ->
        classes.add c
        el.className = [...classes].join ' '
      remove: (c) ->
        classes.delete c
        el.className = [...classes].join ' '
      contains: (c) -> classes.has c
      toggle: (c, force) ->
        next = if force isnt undefined then force else not classes.has c
        if next then el.classList.add c else el.classList.remove c
    appendChild: (child) ->
      el._children.push child
      el.children.push child
      child
    addEventListener: (ev, fn) ->
      el._listeners[ev] ?= []
      el._listeners[ev].push fn
    querySelector:      -> null
    querySelectorAll:   -> []
    getBoundingClientRect: -> { top: 0, left: 0, width: 100, height: 100 }
  el

_elementsById = {}

global.window   = {}
global.document =
  createElement:   (tag) -> makeElement tag
  getElementById:  (id)  -> _elementsById[id] or null
  querySelector:         -> null
  querySelectorAll:      -> []
  _setById: (id, el) -> _elementsById[id] = el   # helper pour les tests

module.exports = { makeElement }
