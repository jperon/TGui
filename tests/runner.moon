-- tests/runner.moon
-- Micro-framework de test autonome (aucune dépendance externe).
-- Usage :
--   R = require 'tests.runner'
--   R.describe "Mon module", ->
--     R.it "fait quelque chose", ->
--       R.eq maValeur, 42
--   R.summary!   -- affiche le bilan et quitte avec code 1 si échec

_state =
  passed:  0
  failed:  0
  errors:  0
  current: ''

-- Formatage de valeur pour l'affichage des échecs
fmt = (v) ->
  t = type v
  if t == 'string'  then string.format('%q', v)
  elseif t == 'nil' then 'nil'
  elseif t == 'table'
    pairs_str = {}
    for k, val in pairs v
      table.insert pairs_str, "#{tostring k}=#{fmt val}"
    "{#{table.concat pairs_str, ', '}}"
  else tostring v

-- Source location helper (2 levels up from assert)
loc = (depth) ->
  info = debug.getinfo (depth or 3), 'Sl'
  if info and info.currentline > 0
    src = info.short_src\gsub '.+/', ''
    "#{src}:#{info.currentline}"
  else '?'

_fail = (msg, depth) ->
  _state.failed += 1
  print "  ✗ [#{loc (depth or 3) + 1}] #{msg}"

_pass = ->
  _state.passed += 1

-- ── Assertions ───────────────────────────────────────────────────────────────

-- Égalité stricte
eq = (actual, expected, label) ->
  if actual == expected
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}attendu #{fmt expected}, reçu #{fmt actual}", 3

-- Différence
ne = (actual, expected, label) ->
  if actual != expected
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}attendu une valeur différente de #{fmt expected}", 3

-- Vrai (truthy)
ok = (v, label) ->
  if v
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}attendu une valeur vraie, reçu #{fmt v}", 3

-- Faux (falsy)
nok = (v, label) ->
  if not v
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}attendu une valeur fausse, reçu #{fmt v}", 3

-- Nil
is_nil = (v, label) ->
  eq v, nil, label

-- Correspond à un pattern Lua
matches = (s, pattern, label) ->
  if type(s) == 'string' and s\match pattern
    _pass!
  else
    _fail "#{label and label .. ': ' or ''}'#{tostring s}' ne correspond pas au pattern '#{pattern}'", 3

-- Lève une erreur (optionnellement vérifie le message)
raises = (fn, pattern, label) ->
  success, err = pcall fn
  if success
    _fail "#{label and label .. ': ' or ''}aucune erreur levée", 3
  elseif pattern and not tostring(err)\match pattern
    _fail "#{label and label .. ': ' or ''}erreur '#{err}' ne correspond pas à '#{pattern}'", 3
  else
    _pass!

-- ── Structure ─────────────────────────────────────────────────────────────────

describe = (name, fn) ->
  _state.current = name
  print "\n#{name}"
  fn!

it = (desc, fn) ->
  before = _state.failed + _state.errors
  success, err = pcall fn
  if not success
    _state.errors += 1
    print "  ✗ ERREUR #{desc}"
    print "    #{err}"
  elseif _state.failed + _state.errors == before
    -- all assertions in this 'it' passed
    print "  ✓ #{desc}"

-- ── Bilan ─────────────────────────────────────────────────────────────────────

summary = ->
  total = _state.passed + _state.failed + _state.errors
  print "\n══════════════════════════════════════"
  print "#{total} assertions — #{_state.passed} ✓  #{_state.failed} ✗  #{_state.errors} erreurs"
  if _state.failed > 0 or _state.errors > 0
    print "RÉSULTAT: ÉCHEC"
    return 1
  print "RÉSULTAT: SUCCÈS"
  return 0

{ :describe, :it, :eq, :ne, :ok, :nok, :is_nil, :matches, :raises, :summary }
