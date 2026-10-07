-- resolvers/data_view_resolvers.moon
-- CRUD resolvers for data views (persisted queries).

{ :require_auth, :require_perm, :perm_ok } = require 'resolvers.utils'
data_views = require 'core.data_views'

-- Source space of a data view, stored either as a space id or as a space name.
dv_source_id = (dv) ->
  return nil unless dv and dv.sourceSpace
  t = box.space._tdb_spaces\get dv.sourceSpace
  t = box.space._tdb_spaces.index.by_name\get dv.sourceSpace unless t
  t and t[1]

Query =
  dataViews: (_, args, ctx) ->
    require_auth ctx
    out = {}
    for dv in *data_views.list_views!
      continue unless perm_ok ctx, 'space', dv_source_id(dv), 'read'
      table.insert out, dv
    out
  dataView:  (_, args, ctx) ->
    dv = data_views.get_view args.id
    return nil unless dv
    require_perm ctx, 'space', dv_source_id(dv), 'read'
    dv
  executeDataView: (_, args, ctx) ->
    require_auth ctx
    executor = require 'core.data_views_executor'
    dv = data_views.get_view args.id
    error "DataView not found: #{args.id}" unless dv
    require_perm ctx, 'space', dv_source_id(dv), 'read'
    executor.execute_view dv.sourceSpace, dv.config, args

Mutation =
  createDataView: (_, args, ctx) ->
    require_perm ctx, 'view', nil, 'write'
    i = args.input
    data_views.create_view i.name, i.description, i.sourceSpace, i.config
  updateDataView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'write'
    data_views.update_view args.id, args.input
  deleteDataView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'admin'
    data_views.delete_view args.id

{ :Query, :Mutation }
