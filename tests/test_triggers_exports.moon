-- tests/test_triggers_exports.moon
-- Freezes the exact public API of core.triggers so the T14 split into
-- formula_sandbox / relation_maps / formula_proxy cannot silently drop or
-- rename an export. These keys are consumed via `require 'core.triggers'` by
-- resolvers/*, graphql/dynamic and other backend modules, so renaming one of
-- them breaks the GraphQL API without any other test noticing.

R = require 'tests.runner'
triggers = require 'core.triggers'

EXPECTED = {
  build_fk_def_map:               'function'
  build_relation_map:             'function'
  build_single_and_multiple_maps: 'function'
  compile_formula:                'function'
  deregister_space_trigger:       'function'
  format_formula_error:           'function'
  init_all_triggers:              'function'
  invalidate_formula_cache:       'function'
  make_self_proxy:                'function'
  make_self_proxy_extended:       'function'
  MAX_STRING_REP_BYTES:           'number'
  register_space_trigger:         'function'
}

R.describe "core.triggers public API", ->
  R.it "exports exactly the documented keys with the right types", ->
    actual = {}
    for k, v in pairs triggers
      actual[k] = type v
    for k, expected_type in pairs EXPECTED
      R.ok actual[k] != nil, "missing export '#{k}'"
      R.eq actual[k], expected_type, "type of '#{k}'"
    for k in pairs actual
      R.ok EXPECTED[k] != nil, "unexpected extra export '#{k}'"
