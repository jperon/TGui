# tests/js/runner.coffee — minimal test runner (no dependencies)

passed  = 0
failed  = 0
_pending = []   # pending promises (async it())
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
    # async it(): track the promise
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
  throw new Error(msg or 'assertion failed') unless cond

eq = (a, b, msg) ->
  unless a is b
    throw new Error msg or "expected #{JSON.stringify b}, got #{JSON.stringify a}"

deepEq = (a, b, msg) ->
  sa = JSON.stringify a
  sb = JSON.stringify b
  unless sa is sb
    throw new Error msg or "expected #{sb}, got #{sa}"

raises = (fn, pattern) ->
  threw = false
  try
    fn()
  catch e
    threw = true
    if pattern
      ok = if pattern instanceof RegExp then pattern.test e.message else e.message.includes pattern
      throw new Error "expected error containing \"#{pattern}\", got: #{e.message}" unless ok
  throw new Error 'an error was expected but none was raised' unless threw

summary = ->
  finish = ->
    total = passed + failed
    console.log "#{total} assertions — #{passed} ✓  #{failed} ✗"
    if failed > 0
      console.log 'RESULT: FAILURE'
      process.exit 1
    else
      console.log 'RESULT: SUCCESS'

  if _pending.length > 0
    Promise.all(_pending).then finish
  else
    finish()

module.exports = { describe, it, assert, eq, deepEq, raises, summary }
