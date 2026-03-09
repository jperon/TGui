-- tests/run.moon
-- Point d'entrée de la suite de tests TGui.
-- Évalué dans l'instance Tarantool en cours via :
--   make test
-- (qui utilise `tt connect --eval` sur le socket de contrôle)
--
-- Le box est déjà initialisé par init.lua ; on ne refait pas box.cfg.
-- Le chemin Lua pointe sur /app/backend (défini par init.lua).

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
      print "   [fixture] groupe admin recréé: #{new_grp.id}"
    -- Ensure admin is a member
    mems = box.space._tdb_memberships.index.by_user\select { admin_user.id }
    is_member = false
    for m in *mems
      is_member = true if m[2] == admin_grp[1]
    unless is_member
      box.space._tdb_memberships\insert { admin_user.id, admin_grp[1] }
      print "   [fixture] admin membership restauré"

-- Tests purs (lexer, parser, schema, executor — pas de box)
require 'tests.test_lexer'
require 'tests.test_parser'
require 'tests.test_schema'
require 'tests.test_executor'

-- Tests avec Tarantool box (données temporaires avec suffixe aléatoire)
math.randomseed os.time!
require 'tests.test_spaces'
require 'tests.test_batch_ops'
require 'tests.test_triggers'
require 'tests.test_custom_views'
require 'tests.test_relations'
require 'tests.test_snapshot'
require 'tests.test_permissions'
require 'tests.test_data_filters'
require 'tests.test_nesting'

-- Bilan (os.exit 1 si des tests échouent)
R.summary!

-- Restaurer le schéma de production (test_executor l'a remplacé par un schéma de test)
require('resolvers.init').reinit!
