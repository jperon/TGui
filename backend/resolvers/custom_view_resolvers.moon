-- resolvers/custom_view_resolvers.moon
-- CRUD resolvers for custom YAML views (dashboard layouts).

uuid_mod = require 'uuid'

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

Query =
  customViews: (_, args, ctx) -> list_custom_views!
  customView:  (_, args, ctx) -> get_custom_view args.id

Mutation =
  createCustomView: (_, args, ctx) ->
    i = args.input
    create_custom_view i.name, i.description, i.yaml
  updateCustomView: (_, args, ctx) ->
    i = args.input
    update_custom_view args.id, i.name, i.description, i.yaml
  deleteCustomView: (_, args, ctx) ->
    delete_custom_view args.id

{ :Query, :Mutation }
