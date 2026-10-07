-- Summary: Compose and initialize the executable GraphQL schema/resolver graph.
-- Responsibilities:
-- - Merge resolver modules (schema/data/auth/custom/aggregate/export/introspection).
-- - Build combined SDL (static + dynamic + introspection) and initialize executor.
-- - Provide safe `reinit` hook and background session purge.
-- Key Flows:
-- - init -> build -> executor.init -> executor.set_reinit_fn -> triggers.init_all_triggers.
-- - metadata mutation -> executor.reinit_schema -> resolvers.init.reinit (pcall-protected).
-- Depends on:
-- - resolvers.* modules, graphql.dynamic, graphql.schema, graphql.executor, core.triggers.
-- Used by:
-- - backend/init.moon bootstrap and any schema reinitialization path.

schema_r      = require 'resolvers.schema_resolvers'
data_r        = require 'resolvers.data_resolvers'
auth_r        = require 'resolvers.auth_resolvers'
custom_view_r = require 'resolvers.custom_view_resolvers'
data_view_r   = require 'resolvers.data_view_resolvers'
widget_plugin_r = require 'resolvers.widget_plugin_resolvers'
aggregate_r   = require 'resolvers.aggregate_resolvers'
export_r      = require 'resolvers.export_resolvers'
app_r         = require 'resolvers.app_resolvers'
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
  -- Pour les tests, toujours utiliser le schéma statique qui contient tous les types
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

  -- Build static resolvers base. Query merge order: schema, data, auth,
  -- custom_view, data_view, widget_plugin, aggregate, export, app.
  query_resolvers = schema_r.Query
  for mod in *{ data_r, auth_r, custom_view_r, data_view_r, widget_plugin_r, aggregate_r, export_r, app_r }
    query_resolvers = merge query_resolvers, mod.Query
  -- Mutation merge order: schema, data, auth, custom_view, data_view,
  -- widget_plugin, export, app (no aggregate).
  mutation_resolvers = schema_r.Mutation
  for mod in *{ data_r, auth_r, custom_view_r, data_view_r, widget_plugin_r, export_r, app_r }
    mutation_resolvers = merge mutation_resolvers, mod.Mutation
  static_resolvers = {
    Query:    query_resolvers
    Mutation: mutation_resolvers
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
  -- Purge expired sessions periodically
  auth_mod = require 'core.auth'
  fiber    = require 'fiber'
  fiber.create ->
    while true
      fiber.sleep 3600
      ok, err = pcall auth_mod.purge_expired_sessions
      require('log').warn "Session purge failed: #{err}" unless ok

{ :init, :reinit }
