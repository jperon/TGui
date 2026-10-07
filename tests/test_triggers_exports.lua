local R = require('tests.runner')
local triggers = require('core.triggers')
local EXPECTED = {
  build_fk_def_map = 'function',
  build_relation_map = 'function',
  build_single_and_multiple_maps = 'function',
  compile_formula = 'function',
  deregister_space_trigger = 'function',
  format_formula_error = 'function',
  init_all_triggers = 'function',
  invalidate_formula_cache = 'function',
  make_self_proxy = 'function',
  make_self_proxy_extended = 'function',
  MAX_STRING_REP_BYTES = 'number',
  register_space_trigger = 'function'
}
return R.describe("core.triggers public API", function()
  return R.it("exports exactly the documented keys with the right types", function()
    local actual = { }
    for k, v in pairs(triggers) do
      actual[k] = type(v)
    end
    for k, expected_type in pairs(EXPECTED) do
      R.ok(actual[k] ~= nil, "missing export '" .. tostring(k) .. "'")
      R.eq(actual[k], expected_type, "type of '" .. tostring(k) .. "'")
    end
    for k in pairs(actual) do
      R.ok(EXPECTED[k] ~= nil, "unexpected extra export '" .. tostring(k) .. "'")
    end
  end)
end)
