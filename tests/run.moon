-- tests/run.moon
-- Point d'entrée de la suite de tests tdb.
-- Évalué dans l'instance Tarantool en cours via :
--   make test
-- (qui utilise `tt connect --eval` sur le socket de contrôle)
--
-- Le box est déjà initialisé par init.lua ; on ne refait pas box.cfg.
-- Le chemin Lua pointe sur /app/backend (défini par init.lua).

R = require 'tests.runner'

print "══════════════════════════════════════"
print "   tdb — suite de tests"
print "══════════════════════════════════════"

-- Tests purs (lexer, parser, schema, executor — pas de box)
require 'tests.test_lexer'
require 'tests.test_parser'
require 'tests.test_schema'
require 'tests.test_executor'

-- Tests avec Tarantool box (données temporaires avec suffixe aléatoire)
math.randomseed os.time!
require 'tests.test_spaces'
require 'tests.test_triggers'

-- Bilan (os.exit 1 si des tests échouent)
R.summary!

-- Restaurer le schéma de production (test_executor l'a remplacé par un schéma de test)
require('resolvers.init').reinit!
