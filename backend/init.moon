-- Summary: Tarantool bootstrap entrypoint for TGui backend runtime.
-- Responsibilities:
-- - Configure box and Lua module path for backend modules.
-- - Bootstrap/migrate system spaces before serving requests.
-- - Initialize GraphQL schema/resolvers and start HTTP server.
-- Key Flows:
-- - box.cfg -> core.spaces.bootstrap/migrate -> resolvers.init -> http_server.start.
-- - Optional fixtures load in test environment (TGUI_TEST_ENV=true).
-- Depends on:
-- - core.spaces, resolvers, http_server, fixtures, fiber.
-- Used by:
-- - Docker service entrypoint (backend/init.lua requiring this compiled module).

box.cfg {
    listen: '0.0.0.0:3301',
    log_level: 5,
    memtx_memory: 256 * 1024 * 1024
}

-- Add /app/backend to the Lua path so all backend modules are reachable
package.path = '/app/backend/?.lua;/app/backend/?/init.lua;' .. package.path

system = require('core.spaces')
system.bootstrap!
system.migrate!

-- Load demo data for test environment (will be executed after GraphQL init)
fixtures_loaded = false
setup_demo_data = ->
    if not fixtures_loaded and os.getenv("TGUI_TEST_ENV") == "true"
        require('fixtures').setup_demo_data!
        fixtures_loaded = true

-- Build and initialize the GraphQL schema with all resolvers
resolvers = require('resolvers')
resolvers.init!

-- Setup demo data after GraphQL is ready
setup_demo_data!

-- Middleware: extract session token from Authorization header
-- (injected into context by http_server before calling executor)

http_server = require('http_server')
http_server.start { host: '0.0.0.0', port: 8080 }

-- Keep the fiber alive
require('fiber').sleep(math.huge)
