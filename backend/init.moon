-- Tarantool entry point for tdb
-- MoonScript modules are compiled to .lua alongside their .moon sources.

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
