-- resolvers/data_view_resolvers.moon
-- CRUD resolvers for data views (persisted queries).

{ :require_auth } = require 'resolvers.utils'
data_views = require 'core.data_views'

Query =
  dataViews: (_, args, ctx) ->
    require_auth ctx
    data_views.list_views!
  dataView:  (_, args, ctx) ->
    require_auth ctx
    data_views.get_view args.id
  executeDataView: (_, args, ctx) ->
    require_auth ctx
    executor = require 'core.data_views_executor'
    dv = data_views.get_view args.id
    error "DataView not found: #{args.id}" unless dv
    executor.execute_view dv.sourceSpace, dv.config, args

Mutation =
  createDataView: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    data_views.create_view i.name, i.description, i.sourceSpace, i.config
  updateDataView: (_, args, ctx) ->
    require_auth ctx
    data_views.update_view args.id, args.input
  deleteDataView: (_, args, ctx) ->
    require_auth ctx
    data_views.delete_view args.id

{ :Query, :Mutation }
