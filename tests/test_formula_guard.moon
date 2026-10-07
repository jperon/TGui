-- tests/test_formula_guard.moon
-- Every formula call site must run through core.config.safe_formula_call
-- (spec §7 — sandbox des formules). A plain pcall does NOT bound an
-- infinite-loop formula: only the instruction-count guard inside
-- safe_formula_call stops it in a bounded time.
--
-- Sites covered here:
--   1. graphql/dynamic.moon matches_filter  (filter formula, typed query)
--   2. graphql/dynamic.moon formula column  (_record field resolver)
--   3. graphql/dynamic.moon reprFormula     (_repr_* field resolver)
--   4. core/spaces.moon change_field_type   (conversion formula)
--   5. config.FORMULA_INSTRUCTION_LIMIT     (bounded interruption + control)

R          = require 'tests.runner'
log        = require 'log'
json       = require 'json'
auth       = require 'core.auth'
spaces_mod = require 'core.spaces'
triggers   = require 'core.triggers'
config_mod = require 'core.config'
executor   = require 'graphql.executor'
dynamic    = require 'graphql.dynamic'

SUFFIX = tostring math.random 100000, 999999
FG_SP  = "fg_guard_#{SUFFIX}"
CV_SP  = "fg_conv_#{SUFFIX}"

LOOP_SRC = '(function() while true do end end)()'
-- Control formula: concatenation + sum over 400 elements. Must NOT be cut.
HEALTHY_SRC = '(function() local t = 0 for i = 1, 400 do t = t + i end return "sum=" .. tostring(t) .. "/" .. string.rep("x", 50) end)()'
HEALTHY_VAL = "sum=80200/" .. string.rep('x', 50)

-- Watchdog: without it an infinite-loop formula hangs the whole suite instead
-- of failing it. It is disarmed before raising, so pcall can catch an error
-- raised from a count hook (LuaJIT requirement).
WATCHDOG_INTERVAL     = 10000
WATCHDOG_INSTRUCTIONS = 20 * 1000 * 1000

watchdog_on = ->
  calls = 0
  hook = ->
    calls += 1
    if calls == 1 or calls % 500 == 0
      log.info "[wd] hook call ##{calls}"
    if calls * WATCHDOG_INTERVAL > WATCHDOG_INSTRUCTIONS
      debug.sethook!
      log.info "[wd] RAISING at call ##{calls}"
      error "watchdog: formula exceeded #{WATCHDOG_INSTRUCTIONS} instructions", 0
  debug.sethook hook, 'count', WATCHDOG_INTERVAL
  h, m, c = debug.gethook!
  log.info "[wd] armed hook=#{tostring h} mask=#{tostring m} count=#{tostring c}"

watchdog_off = ->
  debug.sethook!

err_count = (key) ->
  m = config_mod.get_formula_metrics!.error_details[key]
  return 0 unless m
  m.count

-- ── Fixture ─────────────────────────────────────────────────────────────────

admin_user = auth.get_user_by_username 'admin'
admin_sess = auth.create_session admin_user.id
CTX = { user_id: admin_user.id, token: admin_sess.token }

run_q = (query) -> executor.execute { query: query, context: CTX }
errs_json = (res) -> res.errors and json.encode(res.errors) or 'no errors'

fg_sp = spaces_mod.create_user_space FG_SP, 'formula guard fixture'
spaces_mod.add_field fg_sp.id, 'label', 'String'
spaces_mod.add_field fg_sp.id, 'sain', 'String', false, '', HEALTHY_SRC, nil, 'lua'
spaces_mod.add_field fg_sp.id, 'boucle', 'String', false, '', LOOP_SRC, nil, 'lua'
spaces_mod.add_field fg_sp.id, 'affichage', 'String', false, '', nil, nil, 'lua', LOOP_SRC
box.space["data_#{FG_SP}"]\insert { 'fg_1', json.encode { label: 'row-1' } }

cv_sp    = spaces_mod.create_user_space CV_SP, 'formula guard conversion fixture'
cv_field = spaces_mod.add_field cv_sp.id, 'montant', 'String'
box.space["data_#{CV_SP}"]\insert { 'cv_1', json.encode { montant: '10' } }

require('resolvers.init').reinit!
FG_T = dynamic.gql_name FG_SP
page_of = (res) -> res.data and res.data[FG_T] or nil

-- ── 5. Instruction limit ────────────────────────────────────────────────────

R.describe "Formula guard — instruction limit", ->
  R.it "FORMULA_INSTRUCTION_LIMIT is 20 million", ->
    R.eq config_mod.FORMULA_INSTRUCTION_LIMIT, 20 * 1000 * 1000, "config.moon limit"

  R.it "infinite loop formula is interrupted in well under 2s", ->
    fn = triggers.compile_formula LOOP_SRC, 'fg_loop', 'lua'
    R.ok fn != nil, 'infinite-loop formula must compile'
    watchdog_on!
    t0 = os.clock!
    val, err = config_mod.safe_formula_call fn, 'fg infinite loop'
    watchdog_off!
    elapsed = os.clock! - t0
    print "    [measure] infinite loop stopped in #{elapsed}s (limit #{config_mod.FORMULA_INSTRUCTION_LIMIT} instructions)"
    R.ok err != nil, "the loop must be stopped with an error"
    R.matches tostring(err), 'instruction limit', "bounded error, got #{tostring err}"
    R.ok elapsed < 2, "must return in <2s (took #{elapsed}s)"

  R.it "healthy formula (concat + sum over 400 elements) is not interrupted", ->
    fn = triggers.compile_formula HEALTHY_SRC, 'fg_healthy', 'lua'
    R.ok fn != nil, 'healthy formula must compile'
    t0 = os.clock!
    val, err = config_mod.safe_formula_call fn, 'fg healthy formula'
    elapsed = os.clock! - t0
    print "    [measure] healthy formula finished in #{elapsed}s"
    R.eq err, nil, "healthy formula must not be interrupted: #{tostring err}"
    R.eq val, HEALTHY_VAL, 'healthy formula return value'
    R.ok elapsed < 2, "healthy formula must run fast (took #{elapsed}s)"

-- ── 2/3. Typed GraphQL query: formula column + reprFormula ──────────────────

R.describe "Formula guard — typed GraphQL query", ->
  R.it "healthy formula column returns its value through the typed query", ->
    t0 = os.clock!
    res = run_q "{ #{FG_T} { items { label sain } } }"
    elapsed = os.clock! - t0
    R.nok res.errors, errs_json res
    page = page_of res
    R.eq(page and page.items[1].label, 'row-1', 'stored field')
    R.eq(page and page.items[1].sain, HEALTHY_VAL, 'healthy formula column value')
    R.ok elapsed < 2, "healthy read must be bounded (took #{elapsed}s)"

  R.it "infinite-loop formula column -> rendered [ERROR|...] without blocking", ->
    watchdog_on!
    t0 = os.clock!
    log.info "[wd] before run_q (boucle)"
    res = run_q "{ #{FG_T} { items { boucle } } }"
    log.info "[wd] after run_q (boucle)"
    watchdog_off!
    elapsed = os.clock! - t0
    print "    [measure] formula column site bounded in #{elapsed}s"
    R.nok res.errors, errs_json res
    R.ok elapsed < 2, "typed query must stay bounded (took #{elapsed}s)"
    page = page_of res
    v = page and page.items[1] and page.items[1].boucle
    R.matches tostring(v), '^%[ERROR|', "rendered formula error, got #{tostring v}"
    R.matches tostring(v), 'instruction limit', "guard error message, got #{tostring v}"

  R.it "infinite-loop reprFormula -> rendered [ERROR|...] without blocking", ->
    watchdog_on!
    t0 = os.clock!
    res = run_q "{ #{FG_T} { items { _repr_affichage } } }"
    watchdog_off!
    elapsed = os.clock! - t0
    print "    [measure] reprFormula site bounded in #{elapsed}s"
    R.nok res.errors, errs_json res
    R.ok elapsed < 2, "typed query must stay bounded (took #{elapsed}s)"
    page = page_of res
    v = page and page.items[1] and page.items[1]._repr_affichage
    R.matches tostring(v), '^%[ERROR|', "rendered repr error, got #{tostring v}"
    R.matches tostring(v), 'instruction limit', "guard error message, got #{tostring v}"

-- ── 1. Typed GraphQL query: filter formula ──────────────────────────────────

R.describe "Formula guard — filter formula", ->
  R.it "infinite-loop filter formula -> bounded, record excluded, error tracked", ->
    q = "{ #{FG_T}(filter: { formula: \"#{LOOP_SRC}\", language: \"lua\" }) { total items { _id } } }"
    before = err_count 'filter formula evaluation'
    watchdog_on!
    t0 = os.clock!
    res = run_q q
    watchdog_off!
    elapsed = os.clock! - t0
    after = err_count 'filter formula evaluation'
    print "    [measure] filter site bounded in #{elapsed}s"
    R.nok res.errors, errs_json res
    R.ok elapsed < 2, "typed query must stay bounded (took #{elapsed}s)"
    page = page_of res
    R.ok page != nil, "typed query must return a page"
    R.eq(page and page.total, 0, "infinite-loop filter must match nothing")
    R.ok after > before, "filter formula error must be tracked by safe_formula_call (#{before} -> #{after})"

-- ── 4. change_field_type conversion formula ─────────────────────────────────

R.describe "Formula guard — change_field_type conversion", ->
  R.it "infinite-loop conversion formula is bounded and leaves data untouched", ->
    ctx_key = "conversion #{CV_SP}.montant"
    before = err_count ctx_key
    watchdog_on!
    t0 = os.clock!
    ok_c, res_or_err = pcall spaces_mod.change_field_type, cv_field.id, 'Int', LOOP_SRC, 'lua'
    watchdog_off!
    elapsed = os.clock! - t0
    after = err_count ctx_key
    print "    [measure] conversion site bounded in #{elapsed}s"
    R.ok ok_c, "change_field_type must not raise: #{tostring res_or_err}"
    R.ok elapsed < 2, "conversion must stay bounded (took #{elapsed}s)"
    R.ok after > before, "conversion formula error must be tracked by safe_formula_call (#{before} -> #{after})"
    t = box.space["data_#{CV_SP}"]\get 'cv_1'
    d = json.decode t[2]
    R.eq d.montant, '10', "record keeps its value when the conversion formula fails"

-- ── Cleanup ─────────────────────────────────────────────────────────────────

spaces_mod.delete_user_space FG_SP
spaces_mod.delete_user_space CV_SP
auth.delete_session admin_sess.token
require('resolvers.init').reinit!
