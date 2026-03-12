# tests/js/dom_stub.coffee — minimal DOM stub for Node.js
# Expose global.window, global.document, global.localStorage, global.fetch
# (no jsdom dependency)

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
    children: []           # alias synchronized by appendChild
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

# --- localStorage stub -------------------------------------------------------
_lsStore = {}
localStorageStub =
  getItem:    (k)    -> _lsStore[k] ? null
  setItem:    (k, v) -> _lsStore[k] = String v
  removeItem: (k)    -> delete _lsStore[k]
  clear:             -> _lsStore = {}
  _store:            -> _lsStore   # helper for tests

# --- fetch stub (configurable par test) -------------------------------------
# By default returns {} (no errors). Replace global.fetch in tests as needed.
fetchStub = (url, opts) ->
  Promise.resolve
    json: -> Promise.resolve {}

global.window        = {}
global.localStorage  = localStorageStub
global.fetch         = fetchStub
global.history       = { replaceState: -> }
global.navigator     = { clipboard: { readText: -> Promise.resolve '' } }
global.document =
  createElement:   (tag) -> makeElement tag
  getElementById:  (id)  -> _elementsById[id] or null
  querySelector:         -> null
  querySelectorAll:      -> []
  addEventListener:      ->
  removeEventListener:   ->
  _setById: (id, el) -> _elementsById[id] = el   # helper for tests

module.exports = { makeElement, localStorageStub }
