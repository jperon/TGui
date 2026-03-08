local schema_r = require('resolvers.schema_resolvers')
local data_r = require('resolvers.data_resolvers')
local auth_r = require('resolvers.auth_resolvers')
local custom_view_r = require('resolvers.custom_view_resolvers')
local aggregate_r = require('resolvers.aggregate_resolvers')
local dynamic = require('graphql.dynamic')
local introspection = require('graphql.introspection')
local triggers = require('core.triggers')
local build_schema
build_schema = require('graphql.schema').build_schema
local executor = require('graphql.executor')
local fio = require('fio')
local merge
merge = function(a, b)
  local out = { }
  for k, v in pairs(a) do
    out[k] = v
  end
  for k, v in pairs(b) do
    if out[k] then
      for fname, fn in pairs(v) do
        out[k][fname] = fn
      end
    else
      out[k] = v
    end
  end
  return out
end
local load_static_sdl
load_static_sdl = function()
  local sdl_path = '/app/schema/tdb.graphql'
  local f = fio.open(sdl_path, {
    'O_RDONLY'
  })
  if not (f) then
    error("Cannot open schema file: " .. tostring(sdl_path))
  end
  local sdl = f:read()
  f:close()
  return sdl
end
local build
build = function()
  local static_sdl = load_static_sdl()
  local dyn = dynamic.generate()
  local combined_sdl = static_sdl .. "\n\n" .. introspection.SDL .. "\n\n" .. dyn.sdl
  local static_resolvers = {
    Query = merge(schema_r.Query, merge(data_r.Query, merge(auth_r.Query, merge(custom_view_r.Query, aggregate_r.Query)))),
    Mutation = merge(schema_r.Mutation, merge(data_r.Mutation, merge(auth_r.Mutation, custom_view_r.Mutation))),
    Space = schema_r.Space,
    User = auth_r.User,
    Group = auth_r.Group,
    JSON = {
      coerce_input = function(v)
        return v
      end,
      coerce_output = function(v)
        return v
      end
    }
  }
  local all_resolvers = merge(static_resolvers, {
    Query = dyn.Query
  })
  all_resolvers = merge(all_resolvers, dyn.type_resolvers)
  all_resolvers = merge(all_resolvers, introspection.RESOLVERS)
  local schema = build_schema(combined_sdl, all_resolvers)
  return executor.init(schema)
end
local reinit
reinit = function()
  local ok, err = pcall(build)
  if not ok then
    return require('log').error("Schema reinit failed: " .. tostring(err))
  end
end
local init
init = function()
  build()
  executor.set_reinit_fn(reinit)
  return triggers.init_all_triggers()
end
return {
  init = init,
  reinit = reinit
}
