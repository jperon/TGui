-- core/views.moon
-- Manage view definitions: named projections over a data space.

json = require 'json'
uuid_mod = require 'uuid'

-- View types
VIEW_TYPES = { 'grid', 'form', 'gallery' }

validate_view_yaml = (yaml) ->
  -- Validation stricte du format YAML pour les vues personnalisées
  error 'YAML de vue absent' unless yaml
  error 'Clé racine "layout" manquante' unless yaml.layout
  layout = yaml.layout
  error 'Clé "direction" manquante dans layout' unless layout.direction
  error 'Clé "children" manquante dans layout' unless layout.children
  error 'children doit être une table' unless type(layout.children) == 'table'
  for child in *layout.children
    if child.widget
      w = child.widget
      error 'Clé "space" manquante dans widget' unless w.space
      if w.depends_on
        d = w.depends_on
        error 'Clé "widget" manquante dans depends_on' unless d.widget
        error 'Clé "field" manquante dans depends_on' unless d.field
    else
      error 'Clé "direction" manquante dans zone imbriquée' unless child.direction
      error 'Clé "children" manquante dans zone imbriquée' unless child.children
      error 'children doit être une table (zone imbriquée)' unless type(child.children) == 'table'
  true

create_view = (space_id, name, view_type, config) ->
  validate_view_yaml config
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
  config_str = t[5]
  if patch.config
    validate_view_yaml patch.config
    config_str = json.encode(patch.config)
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

{ :create_view, :update_view, :delete_view, :list_views, :get_view, :VIEW_TYPES, :validate_view_yaml }
