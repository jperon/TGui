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

-- Auto-discover test files from tests/ folder
-- Excludes files containing "_disabled" in their name
math.randomseed os.time!

fio = require 'fio'

test_files = {}
paths = {}
-- Mirrors the former `ls /app/tests/... || ls tests/...` fallback: prefer the
-- container path, otherwise the repository-relative one.
for pattern in *{'/app/tests/test_*.moon', 'tests/test_*.moon'}
  paths = fio.glob pattern
  break if paths and #paths > 0
paths = {} unless paths

for path in *paths
  filename = path\match '([^/]+)%.moon$'
  if filename and not filename\match '_disabled'
    modname = filename\gsub '%.moon$', ''
    table.insert test_files, modname

table.sort test_files

print "   Discovered #{#test_files} test files"
for modname in *test_files
  print "      - #{modname}"
  require "tests.#{modname}"

-- Summary (os.exit 1 if tests fail)
exit_code = R.summary!

-- Restore production schema (test_executor replaced it with a test schema)
require('resolvers.init').reinit!

-- Assert the production schema is usable again after the last test suite.
executor = require 'graphql.executor'
res = executor.execute { query: '{ __type(name: "Query") { fields { name } } }' }
spaces_ok = false
if res and type(res.data) == 'table' and res.data['__type'] and res.data['__type'].fields
  for f in *res.data['__type'].fields
    spaces_ok = true if f.name == 'spaces'
unless spaces_ok
  print '   [FAIL] production schema not restored: Query.spaces is missing'
  exit_code = 1
else
  print '   [ok] production schema restored (Query.spaces present)'

exit_code
