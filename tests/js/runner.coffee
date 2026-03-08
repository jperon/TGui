# tests/js/runner.coffee — minimal test runner (aucune dépendance)

passed  = 0
failed  = 0
_pending = []   # promesses en attente (it() async)
currentSuite = ''

describe = (name, fn) ->
  currentSuite = name
  fn()

it = (desc, fn) ->
  result = undefined
  try
    result = fn()
  catch e
    failed++
    console.error "  ✗  #{currentSuite} — #{desc}"
    console.error "     #{e.message}"
    return

  if result and typeof result.then is 'function'
    # it() asynchrone : on suit la promesse
    _pending.push result.then(
      -> passed++
      (e) ->
        failed++
        console.error "  ✗  #{currentSuite} — #{desc}"
        console.error "     #{e.message}"
    )
  else
    passed++

assert = (cond, msg) ->
  throw new Error(msg or 'assertion échouée') unless cond

eq = (a, b, msg) ->
  unless a is b
    throw new Error msg or "attendu #{JSON.stringify b}, obtenu #{JSON.stringify a}"

deepEq = (a, b, msg) ->
  sa = JSON.stringify a
  sb = JSON.stringify b
  unless sa is sb
    throw new Error msg or "attendu #{sb}, obtenu #{sa}"

raises = (fn, pattern) ->
  threw = false
  try
    fn()
  catch e
    threw = true
    if pattern
      ok = if pattern instanceof RegExp then pattern.test e.message else e.message.includes pattern
      throw new Error "erreur attendue contenant \"#{pattern}\", obtenu: #{e.message}" unless ok
  throw new Error 'une erreur était attendue mais aucune levée' unless threw

summary = ->
  finish = ->
    total = passed + failed
    console.log "#{total} assertions — #{passed} ✓  #{failed} ✗"
    if failed > 0
      console.log 'RÉSULTAT: ÉCHEC'
      process.exit 1
    else
      console.log 'RÉSULTAT: SUCCÈS'

  if _pending.length > 0
    Promise.all(_pending).then finish
  else
    finish()

module.exports = { describe, it, assert, eq, deepEq, raises, summary }
