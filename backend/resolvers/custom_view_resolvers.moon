-- resolvers/custom_view_resolvers.moon
-- CRUD resolvers for custom YAML views (dashboard layouts).

yaml = require 'yaml'
uuid_mod = require 'uuid'
{ :require_auth } = require 'resolvers.utils'

list_custom_views = ->
  result = {}
  for t in *box.space._tdb_custom_views\select {}
    table.insert result, {
      id:          t[1]
      name:        t[2]
      description: t[3]
      yaml:        t[4]
      createdAt:   tostring t[5]
      updatedAt:   tostring t[6]
    }
  result

get_custom_view = (id) ->
  t = box.space._tdb_custom_views\get id
  return nil unless t
  { id: t[1], name: t[2], description: t[3], yaml: t[4],
    createdAt: tostring(t[5]), updatedAt: tostring(t[6]) }

create_custom_view = (name, description, yaml) ->
  id  = tostring uuid_mod.new!
  now = require('clock').time!
  box.space._tdb_custom_views\insert { id, name, description or '', yaml or '', now, now }
  { id: id, name: name, description: description or '', yaml: yaml or '',
    createdAt: tostring(now), updatedAt: tostring(now) }

update_custom_view = (id, name, description, yaml) ->
  t = box.space._tdb_custom_views\get id
  error "CustomView not found: #{id}" unless t
  now = require('clock').time!
  new_name = name or t[2]
  new_desc = if description != nil then description else t[3]
  new_yaml = if yaml != nil then yaml else t[4]
  box.space._tdb_custom_views\replace { id, new_name, new_desc, new_yaml, t[5], now }
  { id: id, name: new_name, description: new_desc, yaml: new_yaml,
    createdAt: tostring(t[5]), updatedAt: tostring(now) }

delete_custom_view = (id) ->
  box.space._tdb_custom_views\delete id
  true

add_widget_to_view = (viewId, widget) ->
  -- Récupérer la vue existante
  t = box.space._tdb_custom_views\get viewId
  error "CustomView not found: #{viewId}" unless t

  -- Parser le YAML existant
  yaml_content = t[4] or 'widgets: {}'
  config = yaml.decode(yaml_content)

  -- Initialiser la section widgets si elle n'existe pas
  config.widgets = {} unless config.widgets

  -- Générer un ID unique pour le widget
  widget_id = uuid_mod()

  -- Créer le widget avec les données fournies
  new_widget = {
    id: widget_id
    title: widget.title
    type: widget.type
    spaceId: widget.spaceId
    fields: widget.fields or {}
    groupBy: widget.groupBy
    params: widget.params or {}
    position: widget.position or {
      x: 0
      y: 0
      w: 6
      h: 4
    }
  }

  -- Ajouter le widget à la configuration
  config.widgets[widget_id] = new_widget

  -- Re-encoder le YAML
  updated_yaml = yaml.encode(config)

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update viewId, {
    { '=', 4, updated_yaml }  -- Mettre à jour le champ yaml
    { '=', 6, os.time() }     -- Mettre à jour updatedAt
  }

  -- Retourner la vue mise à jour
  {
    id: viewId
    name: t[2]
    description: t[3]
    yaml: updated_yaml
    createdAt: tostring(t[5])
    updatedAt: tostring(os.time())
  }

Query =
  customViews: (_, args, ctx) ->
    require_auth ctx
    list_custom_views!
  customView:  (_, args, ctx) ->
    require_auth ctx
    get_custom_view args.id

Mutation =
  createCustomView: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    create_custom_view i.name, i.description, i.yaml
  updateCustomView: (_, args, ctx) ->
    require_auth ctx
    i = args.input
    update_custom_view args.id, i.name, i.description, i.yaml
  deleteCustomView: (_, args, ctx) ->
    require_auth ctx
    delete_custom_view args.id
  addWidgetToView: (_, args, ctx) ->
    require_auth ctx
    add_widget_to_view args.viewId, args.widget

{ :Query, :Mutation }
