local require_perm
require_perm = require('resolvers.utils').require_perm
local view_presets = require('core.view_presets')
local Query = {
  viewPresets = function(_, args, ctx)
    require_perm(ctx, 'space', args.spaceId, 'read')
    local out = { }
    local _list_0 = view_presets.list_presets(args.scope)
    for _index_0 = 1, #_list_0 do
      local _continue_0 = false
      repeat
        local preset = _list_0[_index_0]
        if not (preset.spaceId == args.spaceId) then
          _continue_0 = true
          break
        end
        table.insert(out, preset)
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    return out
  end
}
local Mutation = {
  saveViewPreset = function(_, args, ctx)
    require_perm(ctx, 'space', args.spaceId, 'write')
    return view_presets.save_preset(args.scope, args.spaceId, args.name, args.filter, args.sort)
  end,
  deleteViewPreset = function(_, args, ctx)
    local preset = view_presets.get_preset(args.id)
    if not (preset) then
      error("ViewPreset not found: " .. tostring(args.id))
    end
    require_perm(ctx, 'space', preset.spaceId, 'write')
    return view_presets.delete_preset(args.id)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
