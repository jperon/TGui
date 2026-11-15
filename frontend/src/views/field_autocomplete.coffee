# field_autocomplete.coffee — field name autocomplete for the MoonScript
# formula filters ("λ"); `@a.b.pre` follows relations at any depth.
TOKEN_RE = /@((?:[A-Za-z_]\w*\.)*)([A-Za-z_]\w*)?$/
MAX_ITEMS = 12

_fieldCache = {}   # spaceId -> Promise([fields])
_relCache   = {}   # spaceId -> Promise([relations])

# Every space — the displayed one included — is fetched once, then cached.
# A DataView cannot be trusted for this: a page widget builds its own with no
# relations (`_relations: []`) and with `space.fields` reduced to the visible
# columns, so `@relation.` would propose nothing there.
_fieldsOf = (sid) ->
  _fieldCache[sid] ?= Promise.resolve(Spaces.getWithFields sid).then (s) -> s?.fields or []

_relsOf = (sid) ->
  _relCache[sid] ?= Promise.resolve(Spaces.listRelations sid).then (rels) -> rels or []
# `@a.b.pre` under the caret → { path: ['a', 'b'], prefix: 'pre' }, else null.
_token = (text) ->
  m = TOKEN_RE.exec String(text or '')
  return null unless m
  raw = m[1] or ''
  path = if raw == '' then [] else raw.slice(0, -1).split '.'
  { path, prefix: m[2] or '' }

# Resolve `path` from the DataView's start space (id only) → { fields,
# relations } of the space reached; an unknown or non-relation segment gives
# empty fields.
_resolve = (dv, path) ->
  empty = { fields: [], relations: [] }
  start = dv?.space?.id
  return Promise.resolve(empty) unless start
  step = (sid, rest) ->
    Promise.all([_fieldsOf(sid), _relsOf(sid)]).then ([fields, rels]) ->
      return { fields, relations: rels } if rest.length == 0
      f = fields.find (x) -> x.name == rest[0]
      return empty unless f
      rel = rels.find (r) -> r.fromFieldId == f.id
      return empty unless rel
      step rel.toSpaceId, rest[1..]
  step start, (path or [])
# Name-prefix filter (case-insensitive), alphabetical, at most MAX_ITEMS.
_filter = (fields, prefix) ->
  p = String(prefix or '').toLowerCase()
  out = (f for f in (fields or []) when String(f.name or '').toLowerCase().indexOf(p) == 0)
  out.sort (a, b) ->
    String(a.name).toLowerCase().localeCompare String(b.name).toLowerCase()
  out.slice 0, MAX_ITEMS

# Replace the prefix before `caret` with `field.name`; returns { value, caret }.
_insert = (text, caret, field) ->
  text = String text or ''
  m = TOKEN_RE.exec text.slice(0, caret)
  return null unless m
  prefix = m[2] or ''
  start  = caret - prefix.length
  name   = String field.name
  { value: text.slice(0, start) + name + text.slice(caret), caret: start + name.length }
attach = (input, getDataView) ->
  return unless input
  list     = null
  items    = []
  relIds   = new Set()
  sel      = 0
  reqId    = 0
  skipNext = false   # ignore the `input` event we dispatch ourselves

  detach = ->
    list.parentNode.removeChild list if list and list.parentNode
    list = null
  close = ->
    detach()
    items = []
    sel   = 0
  render = ->
    detach()
    list = document.createElement 'div'
    list.className = 'field-ac'
    for f, i in items
      item = document.createElement 'div'
      item.className = if i == sel then 'field-ac-item selected' else 'field-ac-item'
      name = document.createElement 'span'
      name.textContent = (if relIds.has(f.id) then '→ ' else '') + f.name
      type = document.createElement 'span'
      type.className = 'field-ac-type'
      type.textContent = f.fieldType or ''
      item.appendChild name
      item.appendChild type
      item.addEventListener 'mousedown', (ev) ->
        ev.preventDefault()
        pick f
      list.appendChild item
    document.body.appendChild list
    r = input.getBoundingClientRect?()
    return unless r
    list.style.position = 'fixed'
    list.style.top  = "#{r.bottom + 2}px"
    list.style.left = "#{r.left}px"
    list.style.minWidth = "#{r.width}px"
  pick = (field) ->
    return unless field
    caret = input.selectionStart ? input.value.length
    res = _insert input.value, caret, field
    return unless res
    input.value = res.value
    input.selectionStart = input.selectionEnd = res.caret
    close()
    skipNext = true
    input.dispatchEvent new Event 'input', { bubbles: true }
  update = ->
    if skipNext
      skipNext = false
      return close()
    caret = input.selectionStart ? input.value.length
    tok = _token input.value.slice(0, caret)
    return close() unless tok
    my = ++reqId
    _resolve(getDataView?(), tok.path).then (res) ->
      return unless my == reqId
      found = _filter res.fields, tok.prefix
      return close() if found.length == 0
      items  = found
      relIds = new Set (r.fromFieldId for r in res.relations)
      sel    = 0
      render()

  input.addEventListener 'input', update
  input.addEventListener 'click', update
  input.addEventListener 'blur', close
  input.addEventListener 'keydown', (ev) ->
    return unless list and items.length > 0
    switch ev.key
      when 'ArrowDown'
        ev.preventDefault()
        sel = (sel + 1) % items.length
        render()
      when 'ArrowUp'
        ev.preventDefault()
        sel = (sel - 1 + items.length) % items.length
        render()
      when 'Enter', 'Tab'
        ev.preventDefault()
        pick items[sel]
      when 'Escape'
        close()
window.FieldAutocomplete = {
  attach: attach
  _token: _token
  _resolve: _resolve
  _filter: _filter
  _insert: _insert
  _reset: -> _fieldCache = {}; _relCache = {}
}
