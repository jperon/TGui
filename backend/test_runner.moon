-- backend/test_runner.moon
-- Point d'entrée pour exécuter les tests dans un conteneur Docker
-- Retourne le code de sortie approprié (0 si succès, 1 si échec)

box.cfg {
    listen: '0.0.0.0:3301',
    log_level: 5,
    memtx_memory: 256 * 1024 * 1024
}

-- Add /app/backend to the Lua path so all backend modules are reachable
package.path = '/app/?.lua;/app/backend/?.lua;/app/backend/?/init.lua;' .. package.path

-- Bootstrap system
system = require('core.spaces')
system.bootstrap!
system.migrate!

-- Build and initialize the GraphQL schema with all resolvers
resolvers = require('resolvers')
resolvers.init!

-- Load demo data for tests
fixtures_loaded = false
setup_demo_data = ->
    if not fixtures_loaded
        require('fixtures').setup_demo_data!
        fixtures_loaded = true

setup_demo_data!

-- Load and run tests
exit_code = require 'tests.run'

-- Exit with the appropriate code
os.exit(exit_code or 1)
