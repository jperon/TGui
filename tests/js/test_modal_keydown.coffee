# tests/js/test_modal_keydown.coffee — retrait du handler keydown des modales.
#
# Bug mesuré (frontend/src/modal.coffee, tdbAlert/tdbConfirm/tdbPrompt) :
# le handler `keydown` n'était retiré (document.removeEventListener) QUE dans
# le handler clavier lui-même. Fermer la modale en cliquant sur OK ou Annuler
# laissait le handler attaché : fuite d'écouteurs à chaque ouverture, et un
# Entrée/Échap ultérieur exécutait le handler périmé (cachait une modale
# ouverte plus tard).
#
# Le retrait est synchrone (dans le onclick) : les assertions de retrait sont
# donc posées juste après le clic, pas dans un .then (les tests suivants
# réinitialiseraient le compteur partagé avant l'exécution des callbacks).

stub = require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

# dom_stub ne fournit ni document.body ni el.focus(), alors que modal.coffee
# fait `document.body.appendChild _overlay` puis `_okBtn.focus()` dans _show.
global.document.body = stub.makeElement 'div' unless global.document.body?
origCreateElement = global.document.createElement
global.document.createElement = (tag) ->
  el = origCreateElement tag
  el.focus = -> el
  el

# Suivi des écouteurs keydown : dom_stub ne fait que des no-op, on enregistre
# ici les handlers ajoutés/retirés. Le retrait n'est compté que si c'est
# bien LE handler enregistré qui est passé à removeEventListener.
activeKeydown = []
removedKeydown = []
lastKeydownHandler = null
origAdd = global.document.addEventListener
origRemove = global.document.removeEventListener
global.document.addEventListener = (ev, fn) ->
  if ev == 'keydown'
    activeKeydown.push fn
    lastKeydownHandler = fn
  origAdd ev, fn
global.document.removeEventListener = (ev, fn) ->
  if ev == 'keydown'
    removedKeydown.push fn
    idx = activeKeydown.indexOf fn
    activeKeydown.splice idx, 1 if idx >= 0
  origRemove ev, fn

# Charge le module sous test (définit window.tdbAlert/tdbConfirm/tdbPrompt)
require '../../frontend/src/modal'

# Accès aux boutons créés par modal.coffee (_init) :
#   document.body.children[0]  = overlay
#   overlay.children[0]        = box
#   box.children               = [_msg, _input, btns]
#   btns.children              = [_cancelBtn, _okBtn]
buttons = ->
  overlay = global.document.body.children[0]
  box     = overlay.children[0]
  btns    = box.children[2]
  { cancel: btns.children[0], ok: btns.children[1] }

reset = ->
  activeKeydown.length = 0
  removedKeydown.length = 0
  lastKeydownHandler = null

describe 'modales : fermeture par clic → handler keydown retiré', ->
  it 'tdbAlert : le clic OK retire le handler keydown', ->
    reset()
    p = global.window.tdbAlert 'hello'
    eq activeKeydown.length, 1, 'pré-condition : 1 écouteur keydown après ouverture'
    handler = lastKeydownHandler
    buttons().ok.onclick()
    assert removedKeydown.indexOf(handler) >= 0, 'removeEventListener doit être appelé avec le handler keydown'
    eq activeKeydown.length, 0, 'tdbAlert : le handler keydown doit être retiré après clic OK'
    p.then (val) -> eq val, undefined, 'tdbAlert résout undefined'

  it 'tdbConfirm : le clic OK retire le handler keydown', ->
    reset()
    p = global.window.tdbConfirm 'delete?'
    eq activeKeydown.length, 1, 'pré-condition : 1 écouteur keydown après ouverture'
    handler = lastKeydownHandler
    buttons().ok.onclick()
    assert removedKeydown.indexOf(handler) >= 0, 'removeEventListener doit être appelé avec le handler keydown'
    eq activeKeydown.length, 0, 'tdbConfirm : le handler keydown doit être retiré après clic OK'
    p.then (val) -> eq val, true, 'tdbConfirm résout true sur OK'

  it 'tdbConfirm : le clic Annuler retire le handler keydown', ->
    reset()
    p = global.window.tdbConfirm 'delete?'
    eq activeKeydown.length, 1, 'pré-condition : 1 écouteur keydown après ouverture'
    handler = lastKeydownHandler
    buttons().cancel.onclick()
    assert removedKeydown.indexOf(handler) >= 0, 'removeEventListener doit être appelé avec le handler keydown'
    eq activeKeydown.length, 0, 'tdbConfirm : le handler keydown doit être retiré après clic Annuler'
    p.then (val) -> eq val, false, 'tdbConfirm résout false sur Annuler'

  it 'tdbPrompt : le clic OK retire le handler keydown', ->
    reset()
    p = global.window.tdbPrompt 'name:', 'default'
    eq activeKeydown.length, 1, 'pré-condition : 1 écouteur keydown après ouverture'
    handler = lastKeydownHandler
    buttons().ok.onclick()
    assert removedKeydown.indexOf(handler) >= 0, 'removeEventListener doit être appelé avec le handler keydown'
    eq activeKeydown.length, 0, 'tdbPrompt : le handler keydown doit être retiré après clic OK'
    p.then (val) -> eq val, 'default', 'tdbPrompt résout la saisie sur OK'

  it 'tdbPrompt : le clic Annuler retire le handler keydown', ->
    reset()
    p = global.window.tdbPrompt 'name:', 'default'
    eq activeKeydown.length, 1, 'pré-condition : 1 écouteur keydown après ouverture'
    handler = lastKeydownHandler
    buttons().cancel.onclick()
    assert removedKeydown.indexOf(handler) >= 0, 'removeEventListener doit être appelé avec le handler keydown'
    eq activeKeydown.length, 0, 'tdbPrompt : le handler keydown doit être retiré après clic Annuler'
    p.then (val) -> eq val, null, 'tdbPrompt résout null sur Annuler'

describe 'modales : comportement clavier inchangé (contrôles)', ->
  it 'tdbAlert : Échap résout undefined et retire le handler', ->
    reset()
    p = global.window.tdbAlert 'hello'
    eq activeKeydown.length, 1, 'pré-condition : 1 écouteur keydown après ouverture'
    handler = lastKeydownHandler
    handler { key: 'Escape' }
    assert removedKeydown.indexOf(handler) >= 0, 'Échap doit retirer le handler keydown'
    eq activeKeydown.length, 0, 'tdbAlert : Échap retire le handler'
    p.then (val) -> eq val, undefined, 'tdbAlert résout undefined'

  it 'tdbConfirm : Échap résout false et Entrée résout true', ->
    reset()
    p1 = global.window.tdbConfirm 'one?'
    h1 = lastKeydownHandler
    h1 { key: 'Escape' }
    eq activeKeydown.length, 0, 'tdbConfirm : Échap retire le handler'
    p2 = global.window.tdbConfirm 'two?'
    h2 = lastKeydownHandler
    h2 { key: 'Enter' }
    eq activeKeydown.length, 0, 'tdbConfirm : Entrée retire le handler'
    settled = Promise.all [p1, p2]
    settled.then (vals) ->
      eq vals[0], false, 'tdbConfirm : Échap → false'
      eq vals[1], true, 'tdbConfirm : Entrée → true'

  it 'tdbPrompt : Entrée résout la saisie, Échap résout null', ->
    reset()
    p1 = global.window.tdbPrompt 'a:', 'alpha'
    h1 = lastKeydownHandler
    h1 { key: 'Enter' }
    eq activeKeydown.length, 0, 'tdbPrompt : Entrée retire le handler'
    p2 = global.window.tdbPrompt 'b:', 'beta'
    h2 = lastKeydownHandler
    h2 { key: 'Escape' }
    eq activeKeydown.length, 0, 'tdbPrompt : Échap retire le handler'
    settled = Promise.all [p1, p2]
    settled.then (vals) ->
      eq vals[0], 'alpha', 'tdbPrompt : Entrée → saisie'
      eq vals[1], null, 'tdbPrompt : Échap → null'

summary()
