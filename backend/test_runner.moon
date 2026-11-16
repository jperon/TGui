-- backend/test_runner.moon
-- Entrypoint to run tests in a Docker container.
-- Returns the appropriate exit code (0 on success, 1 on failure).

box.cfg {
    listen: '0.0.0.0:3301',
    log_level: 5,
    memtx_memory: 256 * 1024 * 1024
}

-- Add /app/backend to the Lua path so all backend modules are reachable
package.path = '/app/?.lua;/app/backend/?.lua;/app/backend/?/init.lua;' .. package.path

-- Raise the default fiber slice before the tests run: the whole suite executes
-- in the single main fiber and accumulates seconds of formula/grid work without
-- yielding, so the Tarantool default ({warn = 0.5, err = 1}) aborts a legitimate
-- read with "fiber slice is exceeded". The server itself keeps the default and
-- raises the slice per request (core.config.REQUEST_SLICE): a test-only raise.
require('fiber').set_max_slice { warn: 2, err: 20 }

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
