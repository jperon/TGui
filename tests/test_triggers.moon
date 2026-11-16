-- tests/test_triggers.moon
-- Tests trigger formulas (core/triggers.moon).
-- Requires Tarantool (box already initialized in run.moon).

R = require 'tests.runner'
json        = require 'json'
spaces_mod  = require 'core.spaces'
triggers    = require 'core.triggers'
config_mod  = require 'core.config'

-- Isolated space for these tests
SUFFIX  = tostring(math.random 100000, 999999)
SP_NAME = "test_triggers_#{SUFFIX}"
MS_SP   = "trig_moon_#{SUFFIX}"
SB_SP   = "trig_sb_#{SUFFIX}"

local space_id, data_space

-- Helper: insert a tuple directly
insert_raw = (data) ->
  id = tostring(os.time!) .. math.random(1000, 9999)
  data_space\insert { id, json.encode data }
  { id: id, data: data }

-- Helper: read tuple data
read_data = (id) ->
  t = data_space\get id
  return nil unless t
  json.decode t[2]

-- ── Sandbox test helpers ────────────────────────────────────────────────────

-- Watchdog: without an execution guard an infinite-loop formula would hang the
-- whole suite instead of failing it. The hook checks at a short interval and
-- disarms itself before raising (required for pcall to catch an error raised
-- from a count hook), so every sandbox case below stays bounded even before
-- the guard exists.
WATCHDOG_INTERVAL = 10000
WATCHDOG_INSTRUCTIONS = 20 * 1000 * 1000

watchdog_on = ->
  calls = 0
  hook = ->
    calls += 1
    if calls * WATCHDOG_INTERVAL > WATCHDOG_INSTRUCTIONS
      debug.sethook!
      error "watchdog: formula exceeded #{WATCHDOG_INSTRUCTIONS} instructions", 0
  debug.sethook hook, 'count', WATCHDOG_INTERVAL

watchdog_off = ->
  debug.sethook!

-- Asserts that a formula mutating <lib>.<key> leaves the real library intact
-- and does not break a second formula using it. The real library is restored
-- BEFORE asserting: pre-fix the library really is corrupted, and even the
-- runner's failure formatter (which uses string.format) would crash on the
-- first failing assertion and kill the rest of the suite.
check_lib_isolated = (lib_name, key, use_src, expected) ->
  real_lib = _G[lib_name]
  orig = real_lib[key]
  exists = (orig != nil)
  mutate_src = "(function() #{lib_name}.#{key} = nil return 1 end)()"
  fn_mutate = triggers.compile_formula mutate_src, "sandbox_mutate_#{lib_name}", 'lua'
  ok_m, val_m = false, 'formula not compiled'
  if fn_mutate
    ok_m, val_m = pcall fn_mutate, {}, nil
  survived = (real_lib[key] == orig)
  fn_use = triggers.compile_formula use_src, "sandbox_use_#{lib_name}", 'lua'
  ok_u, val_u = false, 'formula not compiled'
  if fn_use
    ok_u, val_u = pcall fn_use, {}, nil
  real_lib[key] = orig
  R.ok(exists, "#{lib_name}.#{key} must exist before the test")
  R.ok(fn_mutate != nil, "mutating formula for #{lib_name} must compile")
  R.ok(ok_m, "mutating formula must run: #{tostring val_m}")
  R.ok(survived, "real #{lib_name}.#{key} must survive a formula mutation")
  R.ok(fn_use != nil, "formula using #{lib_name} must compile")
  R.ok(ok_u, "formula using #{lib_name}.#{key} must still run: #{tostring val_u}")
  R.eq(val_u, expected, "formula using #{lib_name}.#{key} must return #{expected}")

R.describe "Triggers — setup", ->
  R.it "create test space", ->
    sp = spaces_mod.create_user_space SP_NAME
    space_id = sp.id
    data_space = box.space["data_#{SP_NAME}"]
    R.ok data_space

  R.it "add base fields", ->
    spaces_mod.add_field space_id, 'prenom', 'String'
    spaces_mod.add_field space_id, 'nom',    'String'
    -- Trigger formula: triggered on any first/last name change
    spaces_mod.add_field space_id, 'nom_complet', 'String', false, '',
      '(self.prenom or "") .. " " .. (self.nom or "")',
      {'prenom', 'nom'}
    -- Trigger formula: creation only
    spaces_mod.add_field space_id, 'cree_le', 'String', false, '',
      'os.date("%Y")',
      {}
    triggers.register_space_trigger SP_NAME
    R.ok data_space  -- trigger registered without error

R.describe "Triggers — fired on insert", ->
  R.it "full_name computed on insert", ->
    id = 'trig_insert_1'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    d = read_data id
    R.eq d.nom_complet, 'Jean Dupont'

  R.it "empty first or last name -> partial concatenation", ->
    id = 'trig_insert_2'
    data_space\insert { id, json.encode { prenom: 'Alice', nom: '' } }
    d = read_data id
    R.eq d.nom_complet, 'Alice '

  R.it "created_at field (creation-only) is computed on insert", ->
    id = 'trig_insert_3'
    data_space\insert { id, json.encode { prenom: 'Bob', nom: 'Martin' } }
    d = read_data id
    R.ok d.cree_le and d.cree_le != ''
    -- should be a year (4 digits)
    R.matches tostring(d.cree_le), '^%d%d%d%d$'

R.describe "Triggers — fired on update", ->
  R.it "updating first name -> full_name recomputed", ->
    id = 'trig_update_1'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    -- Change first name
    old = data_space\get id
    d = json.decode old[2]
    d.prenom = 'Pierre'
    data_space\replace { id, json.encode d }
    d2 = read_data id
    R.eq d2.nom_complet, 'Pierre Dupont'

  R.it "updating last name -> full_name recomputed", ->
    id = 'trig_update_2'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    old = data_space\get id
    d = json.decode old[2]
    d.nom = 'Martin'
    data_space\replace { id, json.encode d }
    d2 = read_data id
    R.eq d2.nom_complet, 'Jean Martin'

  R.it "created_at field (creation-only) is NOT recomputed on update", ->
    id = 'trig_update_3'
    data_space\insert { id, json.encode { prenom: 'X', nom: 'Y' } }
    d_before = read_data id
    old_val = d_before.cree_le
    -- Wait one second and modify
    old = data_space\get id
    d = json.decode old[2]
    d.prenom = 'Z'
    data_space\replace { id, json.encode d }
    d_after = read_data id
    -- created_at must not change
    R.eq d_after.cree_le, old_val

R.describe "Triggers — compile_formula", ->
  -- Internal test through loaded module
  R.it "valid formula -> function", ->
    -- Use pcall + load directly to test behavior
    fn_str = "return function(self, space) return self.a + self.b end"
    ok, compiled = pcall load, fn_str
    R.ok ok
    ok2, fn = pcall compiled
    R.ok ok2
    R.eq type(fn), 'function'
    proxy = { a: 3, b: 4 }
    setmetatable proxy, { __index: (t, k) -> rawget t, k }
    R.eq fn(proxy, nil), 7

  R.it "invalid formula -> Lua error", ->
    fn_str = "return function(self, space) return self.a +++++ end"
    fn, err = load fn_str
    R.nok fn
    R.ok err

  R.it "valid MoonScript formula -> compiled to Lua function", ->
    -- Verify moonscript.base is available and compiles correctly
    ok_ms, moon = pcall require, 'moonscript.base'
    R.ok ok_ms, "moonscript.base should be available"
    moon_src = "return (self, space) -> (self.a or 0) + (self.b or 0)"
    ok_c, lua_code = pcall moon.to_lua, moon_src
    R.ok ok_c, "MoonScript → Lua: #{tostring lua_code}"
    ok_l, compiled = pcall load, lua_code
    R.ok ok_l, "load Lua: #{tostring compiled}"
    ok2, fn = pcall compiled
    R.ok ok2
    R.eq type(fn), 'function'
    R.eq fn({ a: 10, b: 5 }, nil), 15

  R.it "invalid MoonScript formula -> parser message with line and column", ->
    -- MoonScript 0.8.0 : to_lua renvoie nil, message (sans lever d'erreur)
    ok_ms, moon = pcall require, 'moonscript.base'
    R.ok ok_ms, "moonscript.base should be available"
    ok_c, lua_code, compile_err = pcall moon.to_lua, 'return (self) -> self.a +'
    R.ok ok_c, "to_lua ne doit pas lever : #{tostring lua_code}"
    R.is_nil lua_code
    R.ok compile_err, "un message d'erreur doit être renvoyé"
    R.ok compile_err\find('at line 1', 1, true), "nouveau format d'erreur : #{compile_err}"
    R.ok compile_err\find('column', 1, true), "nouveau format d'erreur : #{compile_err}"

  R.it "invalid MoonScript formula -> compile_formula returns nil, does not raise", ->
    ok, fn = pcall triggers.compile_formula, 'self.a +', 'invalid_ms', 'moonscript'
    R.ok ok, "compile_formula ne doit pas lever : #{tostring fn}"
    R.is_nil fn

R.describe "Triggers — trigger formula MoonScript", ->
  local ms_space_id, ms_data_space

  R.it "create space with MoonScript trigger formula", ->
    sp = spaces_mod.create_user_space MS_SP
    ms_space_id = sp.id
    ms_data_space = box.space["data_#{MS_SP}"]
    R.ok ms_data_space
    spaces_mod.add_field ms_space_id, 'a', 'Int'
    spaces_mod.add_field ms_space_id, 'b', 'Int'
    -- MoonScript trigger formula: add a and b
    spaces_mod.add_field ms_space_id, 'somme', 'Int', false, '',
      '(self.a or 0) + (self.b or 0)',
      {'a', 'b'}, 'moonscript'
    triggers.register_space_trigger MS_SP
    R.ok ms_data_space

  R.it "MoonScript trigger computes value on insert", ->
    id = 'moon_insert_1'
    ms_data_space\insert { id, json.encode { a: 3, b: 7 } }
    d = json.decode (ms_data_space\get id)[2]
    R.eq d.somme, 10

  R.it "MoonScript trigger recomputes on update", ->
    id = 'moon_update_1'
    ms_data_space\insert { id, json.encode { a: 2, b: 4 } }
    t = ms_data_space\get id
    d = json.decode t[2]
    d.a = 10
    ms_data_space\replace { id, json.encode d }
    d2 = json.decode (ms_data_space\get id)[2]
    R.eq d2.somme, 14

R.describe "Triggers — register_space_trigger", ->
  R.it "multiple calls without error (idempotent)", ->
    ok, err = pcall triggers.register_space_trigger, SP_NAME
    R.ok ok, "register_space_trigger should be idempotent: #{tostring err}"

  R.it "non-existing space -> no error", ->
    ok, err = pcall triggers.register_space_trigger, 'space_that_does_not_exist'
    R.ok ok, "non-existing space should be handled silently: #{tostring err}"

R.describe "Triggers — init_all_triggers", ->
  R.it "init_all_triggers runs without error", ->
    ok, err = pcall triggers.init_all_triggers
    R.ok ok, "init_all_triggers: #{tostring err}"

R.describe "Triggers — sandbox: library isolation", ->
  R.it "string.format = nil in a formula does not affect another formula", ->
    check_lib_isolated 'string', 'format', 'string.format("%d-%s", 42, "x")', '42-x'

  R.it "table.insert = nil in a formula does not affect another formula", ->
    check_lib_isolated 'table', 'insert', 'table.concat({"a", "b"}, "-")', 'a-b'

  R.it "math.floor = nil in a formula does not affect another formula", ->
    check_lib_isolated 'math', 'floor', 'math.floor(2.9)', 2

  R.it "os.time = nil in a formula does not affect another formula", ->
    check_lib_isolated 'os', 'time', 'type(os.time())', 'number'

R.describe "Triggers — sandbox: instruction limit", ->
  R.it "infinite loop formula returns a bounded formula error", ->
    fn = triggers.compile_formula '(function() while true do end end)()', 'sandbox_loop', 'lua'
    R.ok(fn != nil, 'infinite loop formula must compile')
    watchdog_on!
    t0 = os.clock!
    val, err = config_mod.safe_formula_call(fn, 'infinite loop formula')
    watchdog_off!
    elapsed = os.clock! - t0
    R.ok(err != nil, "the infinite loop must be stopped with an error (took #{elapsed}s)")
    R.matches(tostring(err), 'instruction limit', "bounded formula error, got #{tostring err}")
    R.ok(elapsed < 10, "must return in bounded time (took #{elapsed}s)")

  R.it "infinite loop formula column -> bounded [ERROR|...] through the proxy", ->
    sp = spaces_mod.create_user_space SB_SP
    sb_data = box.space["data_#{SB_SP}"]
    spaces_mod.add_field sp.id, 'valeur', 'String'
    spaces_mod.add_field sp.id, 'boucle', 'String', false, '', '(function() while true do end end)()'
    sb_data\insert { 'sb_1', json.encode { valeur: 'x' } }
    proxy = triggers.make_self_proxy { valeur: 'x', _id: 'sb_1' }, nil, nil, SB_SP
    watchdog_on!
    t0 = os.clock!
    ok_p, v = pcall -> proxy.boucle
    watchdog_off!
    elapsed = os.clock! - t0
    spaces_mod.delete_user_space SB_SP
    R.ok(ok_p, "proxy read must not raise: #{tostring v}")
    R.ok(elapsed < 10, "proxy read must be bounded (took #{elapsed}s)")
    R.matches(tostring(v), 'instruction limit', "proxy must surface the formula error, got #{tostring v}")

R.describe "Triggers — sandbox: string.rep limit", ->
  R.it "small rep still works through both paths", ->
    fn_method = triggers.compile_formula '("ab"):rep(3)', 'rep_small_method', 'lua'
    R.ok(fn_method != nil, 'method rep formula must compile')
    ok_m, val_m = pcall fn_method, {}, nil
    R.ok(ok_m, "method rep must run: #{tostring val_m}")
    R.eq val_m, 'ababab'
    fn_explicit = triggers.compile_formula 'string.rep("ab", 3)', 'rep_small_explicit', 'lua'
    R.ok(fn_explicit != nil, 'explicit rep formula must compile')
    ok_e, val_e = pcall fn_explicit, {}, nil
    R.ok(ok_e, "explicit rep must run: #{tostring val_e}")
    R.eq val_e, 'ababab'

  R.it '("x"):rep(1e9) returns a bounded error', ->
    -- Precondition: without the bound, ("x"):rep(1e9) allocates 1 GiB
    -- (measured > 120 s with the stock string.rep on 2026-10-07), which would
    -- hang the suite instead of failing it. Assert the guards first and skip
    -- the huge allocation when they are missing.
    R.ok(triggers.MAX_STRING_REP_BYTES != nil, 'triggers.MAX_STRING_REP_BYTES must be defined')
    str_idx = rawget(getmetatable(""), '__index')
    R.nok(str_idx == string, 'string metatable __index must be rebound to the protected copy')
    return unless triggers.MAX_STRING_REP_BYTES != nil and str_idx != string

    fn_method = triggers.compile_formula '(("x"):rep(1e9))', 'rep_huge_method', 'lua'
    R.ok(fn_method != nil, 'huge method rep formula must compile')
    t0 = os.clock!
    ok_m, err_m = pcall fn_method, {}, nil
    elapsed_m = os.clock! - t0
    R.nok(ok_m, '("x"):rep(1e9) must raise an error')
    R.matches(tostring(err_m), 'string.rep result exceeds limit', "bounded rep error, got #{tostring err_m}")
    R.ok(elapsed_m < 5, "must fail fast (took #{elapsed_m}s)")

    fn_explicit = triggers.compile_formula 'string.rep("x", 1e9)', 'rep_huge_explicit', 'lua'
    R.ok(fn_explicit != nil, 'huge explicit rep formula must compile')
    ok_e, err_e = pcall fn_explicit, {}, nil
    R.nok(ok_e, 'string.rep("x", 1e9) must raise an error')
    R.matches(tostring(err_e), 'string.rep result exceeds limit', "bounded rep error, got #{tostring err_e}")

-- Cleanup: delete spaces created for these tests
spaces_mod.delete_user_space SP_NAME
spaces_mod.delete_user_space MS_SP
spaces_mod.delete_user_space SB_SP
