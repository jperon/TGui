package.path = "/app/backend/?.lua;/app/backend/?/init.lua;" .. package.path
local gen = require('graphql.sdl_generator')
local out_path = (arg and arg[1]) or 'schema/tdb.generated.graphql'
if out_path == '-' then
  io.write(gen.generate())
else
  local written = gen.write_file(out_path)
  print("Generated SDL: " .. tostring(written))
end
return 0
