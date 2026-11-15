-- resolvers/view_preset_resolvers.moon
-- Summary: GraphQL resolvers for named view presets (filter + sort per widget
-- or space grid), with space-level read/write permission checks.
-- Inputs/outputs:
-- - Input : scope, spaceId, name, filter and sort arguments from the request.
-- - Output: ViewPreset records, or Booleans for delete.
-- Used by: resolvers/init (Query/Mutation merge), frontend (later task).
{ :require_perm } = require 'resolvers.utils'
view_presets = require 'core.view_presets'

Query =
  -- Only expose presets of this scope whose space_id is the requested space:
  -- a scope is caller-supplied, so trusting it alone would leak the presets of
  -- a space the caller may not read through a spaceId they can read.
  viewPresets: (_, args, ctx) ->
    require_perm ctx, 'space', args.spaceId, 'read'
    out = {}
    for preset in *view_presets.list_presets args.scope
      continue unless preset.spaceId == args.spaceId
      table.insert out, preset
    out

Mutation =
  saveViewPreset: (_, args, ctx) ->
    require_perm ctx, 'space', args.spaceId, 'write'
    view_presets.save_preset args.scope, args.spaceId, args.name, args.filter, args.sort
  deleteViewPreset: (_, args, ctx) ->
    preset = view_presets.get_preset args.id
    error "ViewPreset not found: #{args.id}" unless preset
    require_perm ctx, 'space', preset.spaceId, 'write'
    view_presets.delete_preset args.id

{ :Query, :Mutation }
