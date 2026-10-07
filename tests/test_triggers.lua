local R = require('tests.runner')
local json = require('json')
local spaces_mod = require('core.spaces')
local triggers = require('core.triggers')
local config_mod = require('core.config')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "test_triggers_" .. tostring(SUFFIX)
local MS_SP = "trig_moon_" .. tostring(SUFFIX)
local SB_SP = "trig_sb_" .. tostring(SUFFIX)
local space_id, data_space
local insert_raw
insert_raw = function(data)
  local id = tostring(os.time()) .. math.random(1000, 9999)
  data_space:insert({
    id,
    json.encode(data)
  })
  return {
    id = id,
    data = data
  }
end
local read_data
read_data = function(id)
  local t = data_space:get(id)
  if not (t) then
    return nil
  end
  return json.decode(t[2])
end
local WATCHDOG_INTERVAL = 10000
local WATCHDOG_INSTRUCTIONS = 20 * 1000 * 1000
local watchdog_on
watchdog_on = function()
  local calls = 0
  local hook
  hook = function()
    calls = calls + 1
    if calls * WATCHDOG_INTERVAL > WATCHDOG_INSTRUCTIONS then
      debug.sethook()
      return error("watchdog: formula exceeded " .. tostring(WATCHDOG_INSTRUCTIONS) .. " instructions", 0)
    end
  end
  return debug.sethook(hook, 'count', WATCHDOG_INTERVAL)
end
local watchdog_off
watchdog_off = function()
  return debug.sethook()
end
local check_lib_isolated
check_lib_isolated = function(lib_name, key, use_src, expected)
  local real_lib = _G[lib_name]
  local orig = real_lib[key]
  local exists = (orig ~= nil)
  local mutate_src = "(function() " .. tostring(lib_name) .. "." .. tostring(key) .. " = nil return 1 end)()"
  local fn_mutate = triggers.compile_formula(mutate_src, "sandbox_mutate_" .. tostring(lib_name), 'lua')
  local ok_m, val_m = false, 'formula not compiled'
  if fn_mutate then
    ok_m, val_m = pcall(fn_mutate, { }, nil)
  end
  local survived = (real_lib[key] == orig)
  local fn_use = triggers.compile_formula(use_src, "sandbox_use_" .. tostring(lib_name), 'lua')
  local ok_u, val_u = false, 'formula not compiled'
  if fn_use then
    ok_u, val_u = pcall(fn_use, { }, nil)
  end
  real_lib[key] = orig
  R.ok(exists, tostring(lib_name) .. "." .. tostring(key) .. " must exist before the test")
  R.ok(fn_mutate ~= nil, "mutating formula for " .. tostring(lib_name) .. " must compile")
  R.ok(ok_m, "mutating formula must run: " .. tostring(tostring(val_m)))
  R.ok(survived, "real " .. tostring(lib_name) .. "." .. tostring(key) .. " must survive a formula mutation")
  R.ok(fn_use ~= nil, "formula using " .. tostring(lib_name) .. " must compile")
  R.ok(ok_u, "formula using " .. tostring(lib_name) .. "." .. tostring(key) .. " must still run: " .. tostring(tostring(val_u)))
  return R.eq(val_u, expected, "formula using " .. tostring(lib_name) .. "." .. tostring(key) .. " must return " .. tostring(expected))
end
R.describe("Triggers — setup", function()
  R.it("create test space", function()
    local sp = spaces_mod.create_user_space(SP_NAME)
    space_id = sp.id
    data_space = box.space["data_" .. tostring(SP_NAME)]
    return R.ok(data_space)
  end)
  return R.it("add base fields", function()
    spaces_mod.add_field(space_id, 'prenom', 'String')
    spaces_mod.add_field(space_id, 'nom', 'String')
    spaces_mod.add_field(space_id, 'nom_complet', 'String', false, '', '(self.prenom or "") .. " " .. (self.nom or "")', {
      'prenom',
      'nom'
    })
    spaces_mod.add_field(space_id, 'cree_le', 'String', false, '', 'os.date("%Y")', { })
    triggers.register_space_trigger(SP_NAME)
    return R.ok(data_space)
  end)
end)
R.describe("Triggers — fired on insert", function()
  R.it("full_name computed on insert", function()
    local id = 'trig_insert_1'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Jean',
        nom = 'Dupont'
      })
    })
    local d = read_data(id)
    return R.eq(d.nom_complet, 'Jean Dupont')
  end)
  R.it("empty first or last name -> partial concatenation", function()
    local id = 'trig_insert_2'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Alice',
        nom = ''
      })
    })
    local d = read_data(id)
    return R.eq(d.nom_complet, 'Alice ')
  end)
  return R.it("created_at field (creation-only) is computed on insert", function()
    local id = 'trig_insert_3'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Bob',
        nom = 'Martin'
      })
    })
    local d = read_data(id)
    R.ok(d.cree_le and d.cree_le ~= '')
    return R.matches(tostring(d.cree_le), '^%d%d%d%d$')
  end)
end)
R.describe("Triggers — fired on update", function()
  R.it("updating first name -> full_name recomputed", function()
    local id = 'trig_update_1'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Jean',
        nom = 'Dupont'
      })
    })
    local old = data_space:get(id)
    local d = json.decode(old[2])
    d.prenom = 'Pierre'
    data_space:replace({
      id,
      json.encode(d)
    })
    local d2 = read_data(id)
    return R.eq(d2.nom_complet, 'Pierre Dupont')
  end)
  R.it("updating last name -> full_name recomputed", function()
    local id = 'trig_update_2'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Jean',
        nom = 'Dupont'
      })
    })
    local old = data_space:get(id)
    local d = json.decode(old[2])
    d.nom = 'Martin'
    data_space:replace({
      id,
      json.encode(d)
    })
    local d2 = read_data(id)
    return R.eq(d2.nom_complet, 'Jean Martin')
  end)
  return R.it("created_at field (creation-only) is NOT recomputed on update", function()
    local id = 'trig_update_3'
    data_space:insert({
      id,
      json.encode({
        prenom = 'X',
        nom = 'Y'
      })
    })
    local d_before = read_data(id)
    local old_val = d_before.cree_le
    local old = data_space:get(id)
    local d = json.decode(old[2])
    d.prenom = 'Z'
    data_space:replace({
      id,
      json.encode(d)
    })
    local d_after = read_data(id)
    return R.eq(d_after.cree_le, old_val)
  end)
end)
R.describe("Triggers — compile_formula", function()
  R.it("valid formula -> function", function()
    local fn_str = "return function(self, space) return self.a + self.b end"
    local ok, compiled = pcall(load, fn_str)
    R.ok(ok)
    local ok2, fn = pcall(compiled)
    R.ok(ok2)
    R.eq(type(fn), 'function')
    local proxy = {
      a = 3,
      b = 4
    }
    setmetatable(proxy, {
      __index = function(t, k)
        return rawget(t, k)
      end
    })
    return R.eq(fn(proxy, nil), 7)
  end)
  R.it("invalid formula -> Lua error", function()
    local fn_str = "return function(self, space) return self.a +++++ end"
    local fn, err = load(fn_str)
    R.nok(fn)
    return R.ok(err)
  end)
  return R.it("valid MoonScript formula -> compiled to Lua function", function()
    local ok_ms, moon = pcall(require, 'moonscript.base')
    R.ok(ok_ms, "moonscript.base should be available")
    local moon_src = "return (self, space) -> (self.a or 0) + (self.b or 0)"
    local ok_c, lua_code = pcall(moon.to_lua, moon_src)
    R.ok(ok_c, "MoonScript → Lua: " .. tostring(tostring(lua_code)))
    local ok_l, compiled = pcall(load, lua_code)
    R.ok(ok_l, "load Lua: " .. tostring(tostring(compiled)))
    local ok2, fn = pcall(compiled)
    R.ok(ok2)
    R.eq(type(fn), 'function')
    return R.eq(fn({
      a = 10,
      b = 5
    }, nil), 15)
  end)
end)
R.describe("Triggers — trigger formula MoonScript", function()
  local ms_space_id, ms_data_space
  R.it("create space with MoonScript trigger formula", function()
    local sp = spaces_mod.create_user_space(MS_SP)
    ms_space_id = sp.id
    ms_data_space = box.space["data_" .. tostring(MS_SP)]
    R.ok(ms_data_space)
    spaces_mod.add_field(ms_space_id, 'a', 'Int')
    spaces_mod.add_field(ms_space_id, 'b', 'Int')
    spaces_mod.add_field(ms_space_id, 'somme', 'Int', false, '', '(self.a or 0) + (self.b or 0)', {
      'a',
      'b'
    }, 'moonscript')
    triggers.register_space_trigger(MS_SP)
    return R.ok(ms_data_space)
  end)
  R.it("MoonScript trigger computes value on insert", function()
    local id = 'moon_insert_1'
    ms_data_space:insert({
      id,
      json.encode({
        a = 3,
        b = 7
      })
    })
    local d = json.decode((ms_data_space:get(id))[2])
    return R.eq(d.somme, 10)
  end)
  return R.it("MoonScript trigger recomputes on update", function()
    local id = 'moon_update_1'
    ms_data_space:insert({
      id,
      json.encode({
        a = 2,
        b = 4
      })
    })
    local t = ms_data_space:get(id)
    local d = json.decode(t[2])
    d.a = 10
    ms_data_space:replace({
      id,
      json.encode(d)
    })
    local d2 = json.decode((ms_data_space:get(id))[2])
    return R.eq(d2.somme, 14)
  end)
end)
R.describe("Triggers — register_space_trigger", function()
  R.it("multiple calls without error (idempotent)", function()
    local ok, err = pcall(triggers.register_space_trigger, SP_NAME)
    return R.ok(ok, "register_space_trigger should be idempotent: " .. tostring(tostring(err)))
  end)
  return R.it("non-existing space -> no error", function()
    local ok, err = pcall(triggers.register_space_trigger, 'space_that_does_not_exist')
    return R.ok(ok, "non-existing space should be handled silently: " .. tostring(tostring(err)))
  end)
end)
R.describe("Triggers — init_all_triggers", function()
  return R.it("init_all_triggers runs without error", function()
    local ok, err = pcall(triggers.init_all_triggers)
    return R.ok(ok, "init_all_triggers: " .. tostring(tostring(err)))
  end)
end)
R.describe("Triggers — sandbox: library isolation", function()
  R.it("string.format = nil in a formula does not affect another formula", function()
    return check_lib_isolated('string', 'format', 'string.format("%d-%s", 42, "x")', '42-x')
  end)
  R.it("table.insert = nil in a formula does not affect another formula", function()
    return check_lib_isolated('table', 'insert', 'table.concat({"a", "b"}, "-")', 'a-b')
  end)
  R.it("math.floor = nil in a formula does not affect another formula", function()
    return check_lib_isolated('math', 'floor', 'math.floor(2.9)', 2)
  end)
  return R.it("os.time = nil in a formula does not affect another formula", function()
    return check_lib_isolated('os', 'time', 'type(os.time())', 'number')
  end)
end)
R.describe("Triggers — sandbox: instruction limit", function()
  R.it("infinite loop formula returns a bounded formula error", function()
    local fn = triggers.compile_formula('(function() while true do end end)()', 'sandbox_loop', 'lua')
    R.ok(fn ~= nil, 'infinite loop formula must compile')
    watchdog_on()
    local t0 = os.clock()
    local val, err = config_mod.safe_formula_call(fn, 'infinite loop formula')
    watchdog_off()
    local elapsed = os.clock() - t0
    R.ok(err ~= nil, "the infinite loop must be stopped with an error (took " .. tostring(elapsed) .. "s)")
    R.matches(tostring(err), 'instruction limit', "bounded formula error, got " .. tostring(tostring(err)))
    return R.ok(elapsed < 10, "must return in bounded time (took " .. tostring(elapsed) .. "s)")
  end)
  return R.it("infinite loop formula column -> bounded [ERROR|...] through the proxy", function()
    local sp = spaces_mod.create_user_space(SB_SP)
    local sb_data = box.space["data_" .. tostring(SB_SP)]
    spaces_mod.add_field(sp.id, 'valeur', 'String')
    spaces_mod.add_field(sp.id, 'boucle', 'String', false, '', '(function() while true do end end)()')
    sb_data:insert({
      'sb_1',
      json.encode({
        valeur = 'x'
      })
    })
    local proxy = triggers.make_self_proxy({
      valeur = 'x',
      _id = 'sb_1'
    }, nil, nil, SB_SP)
    watchdog_on()
    local t0 = os.clock()
    local ok_p, v = pcall(function()
      return proxy.boucle
    end)
    watchdog_off()
    local elapsed = os.clock() - t0
    spaces_mod.delete_user_space(SB_SP)
    R.ok(ok_p, "proxy read must not raise: " .. tostring(tostring(v)))
    R.ok(elapsed < 10, "proxy read must be bounded (took " .. tostring(elapsed) .. "s)")
    return R.matches(tostring(v), 'instruction limit', "proxy must surface the formula error, got " .. tostring(tostring(v)))
  end)
end)
R.describe("Triggers — sandbox: string.rep limit", function()
  R.it("small rep still works through both paths", function()
    local fn_method = triggers.compile_formula('("ab"):rep(3)', 'rep_small_method', 'lua')
    R.ok(fn_method ~= nil, 'method rep formula must compile')
    local ok_m, val_m = pcall(fn_method, { }, nil)
    R.ok(ok_m, "method rep must run: " .. tostring(tostring(val_m)))
    R.eq(val_m, 'ababab')
    local fn_explicit = triggers.compile_formula('string.rep("ab", 3)', 'rep_small_explicit', 'lua')
    R.ok(fn_explicit ~= nil, 'explicit rep formula must compile')
    local ok_e, val_e = pcall(fn_explicit, { }, nil)
    R.ok(ok_e, "explicit rep must run: " .. tostring(tostring(val_e)))
    return R.eq(val_e, 'ababab')
  end)
  return R.it('("x"):rep(1e9) returns a bounded error', function()
    R.ok(triggers.MAX_STRING_REP_BYTES ~= nil, 'triggers.MAX_STRING_REP_BYTES must be defined')
    local str_idx = rawget(getmetatable(""), '__index')
    R.nok(str_idx == string, 'string metatable __index must be rebound to the protected copy')
    if not (triggers.MAX_STRING_REP_BYTES ~= nil and str_idx ~= string) then
      return 
    end
    local fn_method = triggers.compile_formula('(("x"):rep(1e9))', 'rep_huge_method', 'lua')
    R.ok(fn_method ~= nil, 'huge method rep formula must compile')
    local t0 = os.clock()
    local ok_m, err_m = pcall(fn_method, { }, nil)
    local elapsed_m = os.clock() - t0
    R.nok(ok_m, '("x"):rep(1e9) must raise an error')
    R.matches(tostring(err_m), 'string.rep result exceeds limit', "bounded rep error, got " .. tostring(tostring(err_m)))
    R.ok(elapsed_m < 5, "must fail fast (took " .. tostring(elapsed_m) .. "s)")
    local fn_explicit = triggers.compile_formula('string.rep("x", 1e9)', 'rep_huge_explicit', 'lua')
    R.ok(fn_explicit ~= nil, 'huge explicit rep formula must compile')
    local ok_e, err_e = pcall(fn_explicit, { }, nil)
    R.nok(ok_e, 'string.rep("x", 1e9) must raise an error')
    return R.matches(tostring(err_e), 'string.rep result exceeds limit', "bounded rep error, got " .. tostring(tostring(err_e)))
  end)
end)
spaces_mod.delete_user_space(SP_NAME)
spaces_mod.delete_user_space(MS_SP)
return spaces_mod.delete_user_space(SB_SP)
