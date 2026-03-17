local require_auth
require_auth = require('resolvers.utils').require_auth
local data_views = require('core.data_views')
local Query = {
  dataViews = function(_, args, ctx)
    require_auth(ctx)
    return data_views.list_views()
  end,
  dataView = function(_, args, ctx)
    require_auth(ctx)
    return data_views.get_view(args.id)
  end,
  executeDataView = function(_, args, ctx)
    require_auth(ctx)
    local executor = require('core.data_views_executor')
    local dv = data_views.get_view(args.id)
    if not (dv) then
      error("DataView not found: " .. tostring(args.id))
    end
    return executor.execute_view(dv.sourceSpace, dv.config, args)
  end
}
local Mutation = {
  createDataView = function(_, args, ctx)
    require_auth(ctx)
    local i = args.input
    return data_views.create_view(i.name, i.description, i.sourceSpace, i.config)
  end,
  updateDataView = function(_, args, ctx)
    require_auth(ctx)
    return data_views.update_view(args.id, args.input)
  end,
  deleteDataView = function(_, args, ctx)
    require_auth(ctx)
    return data_views.delete_view(args.id)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
