local R = require('tests.runner')
local log = require('log')
local json = require('json')
local auth = require('core.auth')
local spaces_mod = require('core.spaces')
local triggers = require('core.triggers')
local config_mod = require('core.config')
local executor = require('graphql.executor')
local dynamic = require('graphql.dynamic')
local SUFFIX = tostring(math.random(100000, 999999))
local FG_SP = "fg_guard_" .. tostring(SUFFIX)
local CV_SP = "fg_conv_" .. tostring(SUFFIX)
local LOOP_SRC = '(function() while true do end end)()'
local HEALTHY_SRC = '(function() local t = 0 for i = 1, 400 do t = t + i end return "sum=" .. tostring(t) .. "/" .. string.rep("x", 50) end)()'
local HEALTHY_VAL = "sum=80200/" .. string.rep('x', 50)
local WATCHDOG_INTERVAL = 10000
local WATCHDOG_INSTRUCTIONS = 20 * 1000 * 1000
local watchdog_on
watchdog_on = function()
  local calls = 0
  local hook
  hook = function()
    calls = calls + 1
    if calls == 1 or calls % 500 == 0 then
      log.info("[wd] hook call #" .. tostring(calls))
    end
    if calls * WATCHDOG_INTERVAL > WATCHDOG_INSTRUCTIONS then
      debug.sethook()
      log.info("[wd] RAISING at call #" .. tostring(calls))
      return error("watchdog: formula exceeded " .. tostring(WATCHDOG_INSTRUCTIONS) .. " instructions", 0)
    end
  end
  debug.sethook(hook, 'count', WATCHDOG_INTERVAL)
  local h, m, c = debug.gethook()
  return log.info("[wd] armed hook=" .. tostring(tostring(h)) .. " mask=" .. tostring(tostring(m)) .. " count=" .. tostring(tostring(c)))
end
local watchdog_off
watchdog_off = function()
  return debug.sethook()
end
local err_count
err_count = function(key)
  local m = config_mod.get_formula_metrics().error_details[key]
  if not (m) then
    return 0
  end
  return m.count
end
local admin_user = auth.get_user_by_username('admin')
local admin_sess = auth.create_session(admin_user.id)
local CTX = {
  user_id = admin_user.id,
  token = admin_sess.token
}
local run_q
run_q = function(query)
  return executor.execute({
    query = query,
    context = CTX
  })
end
local errs_json
errs_json = function(res)
  return res.errors and json.encode(res.errors) or 'no errors'
end
local fg_sp = spaces_mod.create_user_space(FG_SP, 'formula guard fixture')
spaces_mod.add_field(fg_sp.id, 'label', 'String')
spaces_mod.add_field(fg_sp.id, 'sain', 'String', false, '', HEALTHY_SRC, nil, 'lua')
spaces_mod.add_field(fg_sp.id, 'boucle', 'String', false, '', LOOP_SRC, nil, 'lua')
spaces_mod.add_field(fg_sp.id, 'affichage', 'String', false, '', nil, nil, 'lua', LOOP_SRC)
box.space["data_" .. tostring(FG_SP)]:insert({
  'fg_1',
  json.encode({
    label = 'row-1'
  })
})
local cv_sp = spaces_mod.create_user_space(CV_SP, 'formula guard conversion fixture')
local cv_field = spaces_mod.add_field(cv_sp.id, 'montant', 'String')
box.space["data_" .. tostring(CV_SP)]:insert({
  'cv_1',
  json.encode({
    montant = '10'
  })
})
require('resolvers.init').reinit()
local FG_T = dynamic.gql_name(FG_SP)
local page_of
page_of = function(res)
  return res.data and res.data[FG_T] or nil
end
R.describe("Formula guard — instruction limit", function()
  R.it("FORMULA_INSTRUCTION_LIMIT is 20 million", function()
    return R.eq(config_mod.FORMULA_INSTRUCTION_LIMIT, 20 * 1000 * 1000, "config.moon limit")
  end)
  R.it("infinite loop formula is interrupted in well under 2s", function()
    local fn = triggers.compile_formula(LOOP_SRC, 'fg_loop', 'lua')
    R.ok(fn ~= nil, 'infinite-loop formula must compile')
    watchdog_on()
    local t0 = os.clock()
    local val, err = config_mod.safe_formula_call(fn, 'fg infinite loop')
    watchdog_off()
    local elapsed = os.clock() - t0
    print("    [measure] infinite loop stopped in " .. tostring(elapsed) .. "s (limit " .. tostring(config_mod.FORMULA_INSTRUCTION_LIMIT) .. " instructions)")
    R.ok(err ~= nil, "the loop must be stopped with an error")
    R.matches(tostring(err), 'instruction limit', "bounded error, got " .. tostring(tostring(err)))
    return R.ok(elapsed < 2, "must return in <2s (took " .. tostring(elapsed) .. "s)")
  end)
  return R.it("healthy formula (concat + sum over 400 elements) is not interrupted", function()
    local fn = triggers.compile_formula(HEALTHY_SRC, 'fg_healthy', 'lua')
    R.ok(fn ~= nil, 'healthy formula must compile')
    local t0 = os.clock()
    local val, err = config_mod.safe_formula_call(fn, 'fg healthy formula')
    local elapsed = os.clock() - t0
    print("    [measure] healthy formula finished in " .. tostring(elapsed) .. "s")
    R.eq(err, nil, "healthy formula must not be interrupted: " .. tostring(tostring(err)))
    R.eq(val, HEALTHY_VAL, 'healthy formula return value')
    return R.ok(elapsed < 2, "healthy formula must run fast (took " .. tostring(elapsed) .. "s)")
  end)
end)
R.describe("Formula guard — typed GraphQL query", function()
  R.it("healthy formula column returns its value through the typed query", function()
    local t0 = os.clock()
    local res = run_q("{ " .. tostring(FG_T) .. " { items { label sain } } }")
    local elapsed = os.clock() - t0
    R.nok(res.errors, errs_json(res))
    local page = page_of(res)
    R.eq(page and page.items[1].label, 'row-1', 'stored field')
    R.eq(page and page.items[1].sain, HEALTHY_VAL, 'healthy formula column value')
    return R.ok(elapsed < 2, "healthy read must be bounded (took " .. tostring(elapsed) .. "s)")
  end)
  R.it("infinite-loop formula column -> rendered [ERROR|...] without blocking", function()
    watchdog_on()
    local t0 = os.clock()
    log.info("[wd] before run_q (boucle)")
    local res = run_q("{ " .. tostring(FG_T) .. " { items { boucle } } }")
    log.info("[wd] after run_q (boucle)")
    watchdog_off()
    local elapsed = os.clock() - t0
    print("    [measure] formula column site bounded in " .. tostring(elapsed) .. "s")
    R.nok(res.errors, errs_json(res))
    R.ok(elapsed < 2, "typed query must stay bounded (took " .. tostring(elapsed) .. "s)")
    local page = page_of(res)
    local v = page and page.items[1] and page.items[1].boucle
    R.matches(tostring(v), '^%[ERROR|', "rendered formula error, got " .. tostring(tostring(v)))
    return R.matches(tostring(v), 'instruction limit', "guard error message, got " .. tostring(tostring(v)))
  end)
  return R.it("infinite-loop reprFormula -> rendered [ERROR|...] without blocking", function()
    watchdog_on()
    local t0 = os.clock()
    local res = run_q("{ " .. tostring(FG_T) .. " { items { _repr_affichage } } }")
    watchdog_off()
    local elapsed = os.clock() - t0
    print("    [measure] reprFormula site bounded in " .. tostring(elapsed) .. "s")
    R.nok(res.errors, errs_json(res))
    R.ok(elapsed < 2, "typed query must stay bounded (took " .. tostring(elapsed) .. "s)")
    local page = page_of(res)
    local v = page and page.items[1] and page.items[1]._repr_affichage
    R.matches(tostring(v), '^%[ERROR|', "rendered repr error, got " .. tostring(tostring(v)))
    return R.matches(tostring(v), 'instruction limit', "guard error message, got " .. tostring(tostring(v)))
  end)
end)
R.describe("Formula guard — filter formula", function()
  return R.it("infinite-loop filter formula -> bounded, record excluded, error tracked", function()
    local q = "{ " .. tostring(FG_T) .. "(filter: { formula: \"" .. tostring(LOOP_SRC) .. "\", language: \"lua\" }) { total items { _id } } }"
    local before = err_count('filter formula evaluation')
    watchdog_on()
    local t0 = os.clock()
    local res = run_q(q)
    watchdog_off()
    local elapsed = os.clock() - t0
    local after = err_count('filter formula evaluation')
    print("    [measure] filter site bounded in " .. tostring(elapsed) .. "s")
    R.nok(res.errors, errs_json(res))
    R.ok(elapsed < 2, "typed query must stay bounded (took " .. tostring(elapsed) .. "s)")
    local page = page_of(res)
    R.ok(page ~= nil, "typed query must return a page")
    R.eq(page and page.total, 0, "infinite-loop filter must match nothing")
    return R.ok(after > before, "filter formula error must be tracked by safe_formula_call (" .. tostring(before) .. " -> " .. tostring(after) .. ")")
  end)
end)
R.describe("Formula guard — change_field_type conversion", function()
  return R.it("infinite-loop conversion formula is bounded and leaves data untouched", function()
    local ctx_key = "conversion " .. tostring(CV_SP) .. ".montant"
    local before = err_count(ctx_key)
    watchdog_on()
    local t0 = os.clock()
    local ok_c, res_or_err = pcall(spaces_mod.change_field_type, cv_field.id, 'Int', LOOP_SRC, 'lua')
    watchdog_off()
    local elapsed = os.clock() - t0
    local after = err_count(ctx_key)
    print("    [measure] conversion site bounded in " .. tostring(elapsed) .. "s")
    R.ok(ok_c, "change_field_type must not raise: " .. tostring(tostring(res_or_err)))
    R.ok(elapsed < 2, "conversion must stay bounded (took " .. tostring(elapsed) .. "s)")
    R.ok(after > before, "conversion formula error must be tracked by safe_formula_call (" .. tostring(before) .. " -> " .. tostring(after) .. ")")
    local t = box.space["data_" .. tostring(CV_SP)]:get('cv_1')
    local d = json.decode(t[2])
    return R.eq(d.montant, '10', "record keeps its value when the conversion formula fails")
  end)
end)
spaces_mod.delete_user_space(FG_SP)
spaces_mod.delete_user_space(CV_SP)
auth.delete_session(admin_sess.token)
return require('resolvers.init').reinit()
