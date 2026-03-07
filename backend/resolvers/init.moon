-- resolvers/init.moon
-- Aggregates all resolver maps and builds the executable schema.

schema_r      = require 'resolvers.schema_resolvers'
data_r        = require 'resolvers.data_resolvers'
auth_r        = require 'resolvers.auth_resolvers'
custom_view_r = require 'resolvers.custom_view_resolvers'
dynamic       = require 'graphql.dynamic'
introspection = require 'graphql.introspection'
triggers      = require 'core.triggers'

{ :build_schema } = require 'graphql.schema'
executor         = require 'graphql.executor'
fio              = require 'fio'

-- Merge two resolver tables shallowly (type-level keys)
merge = (a, b) ->
  out = {}
  for k, v in pairs a do out[k] = v
  for k, v in pairs b
    if out[k]
      -- merge field-level resolvers
      for fname, fn in pairs v do out[k][fname] = fn
    else
      out[k] = v
  out

-- Load the static SDL text
load_static_sdl = ->
  sdl_path = '/app/schema/tdb.graphql'
  f = fio.open sdl_path, {'O_RDONLY'}
  error "Cannot open schema file: #{sdl_path}" unless f
  sdl = f\read!
  f\close!
  sdl

-- Build the full combined schema (static + dynamic)
build = ->
  static_sdl = load_static_sdl!

  -- Generate dynamic SDL and resolvers from space metadata
  dyn = dynamic.generate!

  -- Combine SDL strings: static + introspection types + dynamic space types
  combined_sdl = static_sdl .. "\n\n" .. introspection.SDL .. "\n\n" .. dyn.sdl

  -- Build static resolvers base
  static_resolvers = {
    Query:    merge(schema_r.Query,    merge(data_r.Query,    merge(auth_r.Query,    custom_view_r.Query)))
    Mutation: merge(schema_r.Mutation, merge(data_r.Mutation, merge(auth_r.Mutation, custom_view_r.Mutation)))
    Space:    schema_r.Space
    User:     auth_r.User
    Group:    auth_r.Group
    -- JSON scalar: pass through as-is
    JSON: {
      coerce_input:  (v) -> v
      coerce_output: (v) -> v
    }
  }

  -- Merge dynamic Query resolvers
  all_resolvers = merge static_resolvers, { Query: dyn.Query }
  -- Merge dynamic type resolvers (e.g. personnes_record, chorale_record, ...)
  all_resolvers = merge all_resolvers, dyn.type_resolvers
  -- Merge introspection resolvers (__Schema, __Type, __Field, Query.__schema, Query.__type)
  all_resolvers = merge all_resolvers, introspection.RESOLVERS

  schema = build_schema combined_sdl, all_resolvers
  executor.init schema

reinit = ->
  ok, err = pcall build
  if not ok
    require('log').error "Schema reinit failed: #{err}"

init = ->
  build!
  executor.set_reinit_fn reinit
  triggers.init_all_triggers!

{ :init, :reinit }
