-- tests/run.moon
-- Entrypoint for the TGui test suite.
-- Evaluated in the running Tarantool instance via:
--   make test
-- (qui utilise `tt connect --eval` sur le socket de contrôle)
--
-- box is already initialized by init.lua; box.cfg is not repeated here.
-- Lua path already points to /app/backend (defined by init.lua).

R = require 'tests.runner'

print "══════════════════════════════════════"
print "   TGui — suite de tests"
print "══════════════════════════════════════"

-- Ensure admin group and admin membership exist (may have been wiped by a broken test run)
do
  auth  = require 'core.auth'
  perms = require 'core.permissions'
  admin_user = auth.get_user_by_username 'admin'
  if admin_user
    -- Find or recreate admin group
    admin_grp = nil
    for g in *box.space._tdb_groups\select {}
      admin_grp = g if g[2] == 'admin'
    unless admin_grp
      -- Clear any stale memberships referencing deleted groups
      for m in *box.space._tdb_memberships.index.by_user\select { admin_user.id }
        box.space._tdb_memberships\delete { m[1], m[2] }
      new_grp = perms.create_group 'admin', 'Administrators with full access'
      -- get raw record for the new group
      admin_grp = box.space._tdb_groups\get new_grp.id
      print "   [fixture] admin group recreated: #{new_grp.id}"
    -- Ensure admin is a member
    mems = box.space._tdb_memberships.index.by_user\select { admin_user.id }
    is_member = false
    for m in *mems
      is_member = true if m[2] == admin_grp[1]
    unless is_member
      box.space._tdb_memberships\insert { admin_user.id, admin_grp[1] }
      print "   [fixture] admin membership restored"

-- Pure tests (lexer, parser, schema, executor — no box dependency)
require 'tests.test_lexer'
require 'tests.test_parser'
require 'tests.test_schema'
require 'tests.test_executor'

-- Tests with Tarantool box (temporary data with random suffix)
math.randomseed os.time!
require 'tests.test_spaces'
require 'tests.test_batch_ops'
require 'tests.test_triggers'
require 'tests.test_custom_views'
require 'tests.test_widget_plugins'
require 'tests.test_relations'
require 'tests.test_relation_type_regression'
require 'tests.test_snapshot'
require 'tests.test_permissions'
require 'tests.test_data_filters'
require 'tests.test_nesting'

-- Summary (os.exit 1 if tests fail)
exit_code = R.summary!

-- Restore production schema (test_executor replaced it with a test schema)
require('resolvers.init').reinit!

exit_code
