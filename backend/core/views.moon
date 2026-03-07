-- core/views.moon
-- Manage view definitions: named projections over a data space.

json = require 'json'
uuid_mod = require 'uuid'

-- View types
VIEW_TYPES = { 'grid', 'form', 'gallery' }

create_view = (space_id, name, view_type, config) ->
  now = os.time!
  vid = tostring uuid_mod.new!
  config_str = json.encode config or {}
  box.space._tdb_views\insert { vid, space_id, name, view_type, config_str, now, now }
  { id: vid, spaceId: space_id, name: name, viewType: view_type, config: config_str, createdAt: now, updatedAt: now }

update_view = (view_id, patch) ->
  t = box.space._tdb_views\get view_id
  error "View not found: #{view_id}" unless t
  now  = os.time!
  name = patch.name or t[3]
  vtype = patch.viewType or t[4]
  config_str = if patch.config then json.encode(patch.config) else t[5]
  box.space._tdb_views\replace { view_id, t[2], name, vtype, config_str, t[6], now }

delete_view = (view_id) ->
  box.space._tdb_views\delete view_id

list_views = (space_id) ->
  result = {}
  for t in *box.space._tdb_views.index.by_space\select { space_id }
    table.insert result, {
      id:         t[1]
      spaceId:    t[2]
      name:       t[3]
      viewType:   t[4]
      config:     t[5]
      createdAt:  t[6]
      updatedAt:  t[7]
    }
  result

get_view = (view_id) ->
  t = box.space._tdb_views\get view_id
  return nil unless t
  { id: t[1], spaceId: t[2], name: t[3], viewType: t[4], config: t[5], createdAt: t[6], updatedAt: t[7] }

{ :create_view, :update_view, :delete_view, :list_views, :get_view, :VIEW_TYPES }
