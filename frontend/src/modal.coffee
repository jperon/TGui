# modal.coffee — Promise-based async replacements for alert(), confirm(), prompt().
# Usage:
#   await tdbAlert "Error message", 'error'
#   if await tdbConfirm "Delete?"
#   name = await tdbPrompt "Name:", "default value"

_overlay = null
_box     = null
_msg     = null
_input   = null
_okBtn   = null
_cancelBtn = null

_t = (key, vars = {}) ->
  if window.I18N?.t then window.I18N.t key, vars else key

_init = ->
  return if _overlay
  _overlay = document.createElement 'div'
  _overlay.id = 'tdb-modal-overlay'
  _overlay.className = 'tdb-modal-overlay hidden'

  _box = document.createElement 'div'
  _box.className = 'tdb-modal-box'

  _msg = document.createElement 'p'
  _msg.className = 'tdb-modal-msg'

  _input = document.createElement 'input'
  _input.type = 'text'
  _input.className = 'tdb-modal-input hidden'

  btns = document.createElement 'div'
  btns.className = 'tdb-modal-actions'

  _cancelBtn = document.createElement 'button'
  _cancelBtn.className = 'toolbar-btn'
  _cancelBtn.textContent = _t 'common.cancel'

  _okBtn = document.createElement 'button'
  _okBtn.className = 'btn-primary'
  _okBtn.textContent = _t 'common.ok'

  btns.appendChild _cancelBtn
  btns.appendChild _okBtn
  _box.appendChild _msg
  _box.appendChild _input
  _box.appendChild btns
  _overlay.appendChild _box
  document.body.appendChild _overlay

_show = (msg, type = 'info', showInput = false, defaultVal = '', showCancel = false) ->
  _init()
  _okBtn.textContent = _t 'common.ok'
  _cancelBtn.textContent = _t 'common.cancel'
  _msg.textContent = msg
  _box.className = "tdb-modal-box tdb-modal-box--#{type}"
  if showInput
    _input.classList.remove 'hidden'
    _input.value = defaultVal
  else
    _input.classList.add 'hidden'
  if showCancel
    _cancelBtn.classList.remove 'hidden'
  else
    _cancelBtn.classList.add 'hidden'
  _overlay.classList.remove 'hidden'
  if showInput then _input.focus() else _okBtn.focus()

_hide = ->
  _overlay.classList.add 'hidden'
  _input.value = ''

# alert-like: shows a message and resolves when the user clicks OK.
window.tdbAlert = (msg, type = 'info') ->
  new Promise (resolve) ->
    _show msg, type, false, '', false
    _okBtn.onclick = ->
      _hide()
      resolve()
    # Also close on Escape.
    handler = (e) ->
      if e.key == 'Escape' or e.key == 'Enter'
        document.removeEventListener 'keydown', handler
        _hide()
        resolve()
    document.addEventListener 'keydown', handler

# confirm-like: resolves true/false.
window.tdbConfirm = (msg, type = 'warn') ->
  new Promise (resolve) ->
    _show msg, type, false, '', true
    _okBtn.onclick = ->
      _hide()
      resolve true
    _cancelBtn.onclick = ->
      _hide()
      resolve false
    handler = (e) ->
      if e.key == 'Escape'
        document.removeEventListener 'keydown', handler
        _hide()
        resolve false
      else if e.key == 'Enter'
        document.removeEventListener 'keydown', handler
        _hide()
        resolve true
    document.addEventListener 'keydown', handler

# prompt-like: resolves with input string or null if canceled.
window.tdbPrompt = (msg, defaultVal = '', type = 'info') ->
  new Promise (resolve) ->
    _show msg, type, true, defaultVal, true
    _okBtn.onclick = ->
      val = _input.value
      _hide()
      resolve if val.trim() then val else null
    _cancelBtn.onclick = ->
      _hide()
      resolve null
    handler = (e) ->
      if e.key == 'Escape'
        document.removeEventListener 'keydown', handler
        _hide()
        resolve null
      else if e.key == 'Enter'
        document.removeEventListener 'keydown', handler
        val = _input.value
        _hide()
        resolve if val.trim() then val else null
    document.addEventListener 'keydown', handler
