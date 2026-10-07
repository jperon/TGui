local require_auth, require_perm, perm_ok
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_perm, perm_ok = _obj_0.require_auth, _obj_0.require_perm, _obj_0.perm_ok
end
local reorder_widgets, add_widget_to_view, add_data_view_to_page
do
  local _obj_0 = require('resolvers.custom_view_widgets')
  reorder_widgets, add_widget_to_view, add_data_view_to_page = _obj_0.reorder_widgets, _obj_0.add_widget_to_view, _obj_0.add_data_view_to_page
end
local create_zone, resize_zone, merge_zones, split_zone
do
  local _obj_0 = require('resolvers.custom_view_zones')
  create_zone, resize_zone, merge_zones, split_zone = _obj_0.create_zone, _obj_0.resize_zone, _obj_0.merge_zones, _obj_0.split_zone
end
local list_custom_views, get_custom_view, create_custom_view, delete_custom_view, create_layout_snapshot, list_layout_snapshots, restore_layout_snapshot, update_custom_view, export_layout, import_layout
do
  local _obj_0 = require('resolvers.custom_view_crud')
  list_custom_views, get_custom_view, create_custom_view, delete_custom_view, create_layout_snapshot, list_layout_snapshots, restore_layout_snapshot, update_custom_view, export_layout, import_layout = _obj_0.list_custom_views, _obj_0.get_custom_view, _obj_0.create_custom_view, _obj_0.delete_custom_view, _obj_0.create_layout_snapshot, _obj_0.list_layout_snapshots, _obj_0.restore_layout_snapshot, _obj_0.update_custom_view, _obj_0.export_layout, _obj_0.import_layout
end
local Query = {
  customViews = function(_, args, ctx)
    require_auth(ctx)
    local out = { }
    local _list_0 = list_custom_views()
    for _index_0 = 1, #_list_0 do
      local cv = _list_0[_index_0]
      if perm_ok(ctx, 'view', cv.id, 'read') then
        table.insert(out, cv)
      end
    end
    return out
  end,
  customView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'read')
    return get_custom_view(args.id)
  end,
  exportLayout = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'read')
    return export_layout(args.pageId)
  end,
  listLayoutSnapshots = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'read')
    return list_layout_snapshots(args.pageId)
  end
}
local Mutation = {
  createCustomView = function(_, args, ctx)
    require_perm(ctx, 'view', nil, 'write')
    local i = args.input or args
    if not (i.name) then
      error("name is required")
    end
    return create_custom_view(i.name, i.description, i.yaml)
  end,
  updateCustomView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'write')
    local i = args.input
    return update_custom_view(args.id, i.name, i.description, i.yaml)
  end,
  deleteCustomView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'admin')
    return delete_custom_view(args.id)
  end,
  addWidgetToView = function(_, args, ctx)
    require_perm(ctx, 'view', args.viewId, 'write')
    return add_widget_to_view(args.viewId, args.widget)
  end,
  reorderWidgets = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    local pageId = args.pageId
    local widgetPositions = args.widgetPositions
    if not (pageId) then
      error("pageId is required")
    end
    if type(widgetPositions) == 'string' then
      error("widgetPositions must be a table, got string")
    end
    if not (widgetPositions and type(widgetPositions) == 'table') then
      error("widgetPositions must be a table")
    end
    return reorder_widgets(pageId, widgetPositions)
  end,
  createZone = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    local pageId = args.pageId
    local zoneData = args.zoneData or { }
    if not (pageId) then
      error("pageId is required")
    end
    return create_zone(pageId, zoneData)
  end,
  resizeZone = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    local pageId = args.pageId
    local zoneId = args.zoneId
    local factor = args.factor
    if not (pageId) then
      error("pageId is required")
    end
    if not (zoneId) then
      error("zoneId is required")
    end
    if not (factor) then
      error("factor is required")
    end
    if factor < 0.1 or factor > 1.0 then
      error("factor must be between 0.1 and 1.0")
    end
    return resize_zone(pageId, zoneId, factor)
  end,
  addDataViewToPage = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return add_data_view_to_page(args.pageId, args.dataViewId)
  end,
  importLayout = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return import_layout(args.pageId, args.yaml)
  end,
  createLayoutSnapshot = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return create_layout_snapshot(args.pageId, args.yaml, args.description)
  end,
  restoreLayoutSnapshot = function(_, args, ctx)
    local snap = box.space._tdb_layout_snapshots:get(args.snapshotId)
    require_perm(ctx, 'view', snap and snap[2], 'write')
    return restore_layout_snapshot(args.snapshotId)
  end,
  mergeZones = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return merge_zones(args.pageId, args.zoneId1, args.zoneId2)
  end,
  splitZone = function(_, args, ctx)
    require_perm(ctx, 'view', args.pageId, 'write')
    return split_zone(args.pageId, args.zoneId, args.direction)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
