box.cfg({
  listen = '0.0.0.0:3301',
  log_level = 5,
  memtx_memory = 256 * 1024 * 1024
})
package.path = '/app/?.lua;/app/backend/?.lua;/app/backend/?/init.lua;' .. package.path
local system = require('core.spaces')
system.bootstrap()
system.migrate()
local resolvers = require('resolvers')
resolvers.init()
local fixtures_loaded = false
local setup_demo_data
setup_demo_data = function()
  if not fixtures_loaded then
    require('fixtures').setup_demo_data()
    fixtures_loaded = true
  end
end
setup_demo_data()
local exit_code = require('tests.run')
return os.exit(exit_code or 1)
