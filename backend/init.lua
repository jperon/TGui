box.cfg({
  listen = '0.0.0.0:3301',
  log_level = 5,
  memtx_memory = 256 * 1024 * 1024
})
package.path = '/app/backend/?.lua;/app/backend/?/init.lua;' .. package.path
local system = require('core.spaces')
system.bootstrap()
system.migrate()
local fixtures_loaded = false
local setup_demo_data
setup_demo_data = function()
  if not fixtures_loaded and os.getenv("TGUI_TEST_ENV") == "true" then
    require('fixtures').setup_demo_data()
    fixtures_loaded = true
  end
end
local resolvers = require('resolvers')
resolvers.init()
setup_demo_data()
local http_server = require('http_server')
http_server.start({
  host = '0.0.0.0',
  port = 8080
})
return require('fiber').sleep(math.huge)
