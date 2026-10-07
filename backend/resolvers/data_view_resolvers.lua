local require_auth, require_perm, perm_ok
do
  local _obj_0 = require('resolvers.utils')
  require_auth, require_perm, perm_ok = _obj_0.require_auth, _obj_0.require_perm, _obj_0.perm_ok
end
local data_views = require('core.data_views')
local dv_source_id
dv_source_id = function(dv)
  if not (dv and dv.sourceSpace) then
    return nil
  end
  local t = box.space._tdb_spaces:get(dv.sourceSpace)
  if not (t) then
    t = box.space._tdb_spaces.index.by_name:get(dv.sourceSpace)
  end
  return t and t[1]
end
local Query = {
  dataViews = function(_, args, ctx)
    require_auth(ctx)
    local out = { }
    local _list_0 = data_views.list_views()
    for _index_0 = 1, #_list_0 do
      local _continue_0 = false
      repeat
        local dv = _list_0[_index_0]
        if not (perm_ok(ctx, 'space', dv_source_id(dv), 'read')) then
          _continue_0 = true
          break
        end
        table.insert(out, dv)
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    return out
  end,
  dataView = function(_, args, ctx)
    local dv = data_views.get_view(args.id)
    if not (dv) then
      return nil
    end
    require_perm(ctx, 'space', dv_source_id(dv), 'read')
    return dv
  end,
  executeDataView = function(_, args, ctx)
    require_auth(ctx)
    local executor = require('core.data_views_executor')
    local dv = data_views.get_view(args.id)
    if not (dv) then
      error("DataView not found: " .. tostring(args.id))
    end
    require_perm(ctx, 'space', dv_source_id(dv), 'read')
    return executor.execute_view(dv.sourceSpace, dv.config, args)
  end
}
local Mutation = {
  createDataView = function(_, args, ctx)
    require_perm(ctx, 'view', nil, 'write')
    local i = args.input
    return data_views.create_view(i.name, i.description, i.sourceSpace, i.config)
  end,
  updateDataView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'write')
    return data_views.update_view(args.id, args.input)
  end,
  deleteDataView = function(_, args, ctx)
    require_perm(ctx, 'view', args.id, 'admin')
    return data_views.delete_view(args.id)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
