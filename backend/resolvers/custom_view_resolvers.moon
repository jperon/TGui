-- resolvers/custom_view_resolvers.moon
-- Entry point: assembles Query and Mutation for custom YAML views (dashboard layouts).

{ :require_auth, :require_perm, :perm_ok } = require 'resolvers.utils'
{ :reorder_widgets, :add_widget_to_view, :add_data_view_to_page } = require 'resolvers.custom_view_widgets'
{ :create_zone, :resize_zone, :merge_zones, :split_zone } = require 'resolvers.custom_view_zones'
{ :list_custom_views, :get_custom_view, :create_custom_view, :delete_custom_view, :create_layout_snapshot, :list_layout_snapshots, :restore_layout_snapshot, :update_custom_view, :export_layout, :import_layout } = require 'resolvers.custom_view_crud'

Query =
  customViews: (_, args, ctx) ->
    require_auth ctx
    out = {}
    for cv in *list_custom_views!
      table.insert out, cv if perm_ok ctx, 'view', cv.id, 'read'
    out
  customView:  (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'read'
    get_custom_view args.id
  exportLayout: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'read'
    export_layout args.pageId
  listLayoutSnapshots: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'read'
    list_layout_snapshots args.pageId

Mutation =
  createCustomView: (_, args, ctx) ->
    require_perm ctx, 'view', nil, 'write'
    i = args.input or args  -- accepter les deux formats
    error "name is required" unless i.name
    create_custom_view i.name, i.description, i.yaml
  updateCustomView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'write'
    i = args.input
    update_custom_view args.id, i.name, i.description, i.yaml
  deleteCustomView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'admin'
    delete_custom_view args.id
  addWidgetToView: (_, args, ctx) ->
    require_perm ctx, 'view', args.viewId, 'write'
    add_widget_to_view args.viewId, args.widget
  reorderWidgets: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'

    -- Validation des arguments
    pageId = args.pageId
    widgetPositions = args.widgetPositions

    error "pageId is required" unless pageId

    -- Si widgetPositions est une string, retourner une erreur claire
    if type(widgetPositions) == 'string'
      error "widgetPositions must be a table, got string"

    -- Accepter les table vides
    unless widgetPositions and type(widgetPositions) == 'table'
      error "widgetPositions must be a table"

    reorder_widgets pageId, widgetPositions

  createZone: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    pageId = args.pageId
    zoneData = args.zoneData or {}

    error "pageId is required" unless pageId

    create_zone pageId, zoneData

  resizeZone: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    pageId = args.pageId
    zoneId = args.zoneId
    factor = args.factor

    error "pageId is required" unless pageId
    error "zoneId is required" unless zoneId
    error "factor is required" unless factor

    -- Validation du factor
    if factor < 0.1 or factor > 1.0
      error "factor must be between 0.1 and 1.0"

    resize_zone pageId, zoneId, factor

  addDataViewToPage: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    add_data_view_to_page args.pageId, args.dataViewId

  importLayout: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    import_layout args.pageId, args.yaml

  createLayoutSnapshot: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    create_layout_snapshot args.pageId, args.yaml, args.description

  restoreLayoutSnapshot: (_, args, ctx) ->
    snap = box.space._tdb_layout_snapshots\get args.snapshotId
    require_perm ctx, 'view', snap and snap[2], 'write'
    restore_layout_snapshot args.snapshotId

  mergeZones: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    merge_zones args.pageId, args.zoneId1, args.zoneId2

  splitZone: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    split_zone args.pageId, args.zoneId, args.direction

{ :Query, :Mutation }
