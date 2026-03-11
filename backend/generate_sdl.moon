-- backend/generate_sdl.moon
-- CLI entrypoint to generate passive SDL artifact.

package.path = "/app/backend/?.lua;/app/backend/?/init.lua;" .. package.path

gen = require 'graphql.sdl_generator'

out_path = (arg and arg[1]) or 'schema/tdb.generated.graphql'
if out_path == '-'
  io.write gen.generate!
else
  written = gen.write_file out_path
  print "Generated SDL: #{written}"

0
