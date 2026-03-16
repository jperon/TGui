-- resolvers/custom_view_resolvers.moon
-- CRUD resolvers for custom YAML views (dashboard layouts).

yaml = require 'yaml'
uuid_mod = require 'uuid'
json = require 'json'
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

-- Réordonner les widgets dans une vue avec support de changement de parent
reorder_widgets = (pageId, widgetPositions) ->
  -- Récupérer la vue existante
  t = box.space._tdb_custom_views\get pageId
  error "Page not found: #{pageId}" unless t

  -- Parser le YAML existant
  yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  config = yaml.decode yaml_content

  -- Gérer le cas où le YAML est mal formaté
  if not config or type(config) != 'table'
    config = { layout: { direction: 'vertical', children: {} } }
  elseif not config.layout
    config.layout = { direction: 'vertical', children: {} }
  elseif not config.layout.children or type(config.layout.children) != 'table'
    config.layout.children = {}

  -- Créer une map des widgets par ID pour retrouver leurs données
  widget_map = {}
  zones_map = {}

  -- Fonction récursive pour collecter tous les widgets et zones
  collect_widgets_and_zones = (children, parent_id = null) ->
    for _, child in ipairs(children)
      if child.widget
        widget_map[child.widget.id] = {
          widget: child.widget
          parent_id: parent_id
        }
      elseif child.zone
        zone_id = child.zone.id or "zone_#{#zones_map + 1}"
        zones_map[zone_id] = {
          zone: child.zone
          parent_id: parent_id
        }
        -- Récursivement collecter les widgets dans la zone
        if child.zone.children and type(child.zone.children) == 'table'
          collect_widgets_and_zones(child.zone.children, zone_id)

  -- Collecter tous les widgets et zones existants
  collect_widgets_and_zones(config.layout.children)

  -- Reconstruire la structure avec les nouvelles positions et parents
  new_children = {}
  processed_zones = {}

  if widgetPositions and type(widgetPositions) == 'table' and #widgetPositions > 0
    for i = 1, #widgetPositions
      pos = widgetPositions[i]
      if type(pos) == 'table' and pos.widgetId
        widget_data = widget_map[pos.widgetId]
        if widget_data
          widget = widget_data.widget
          -- Mettre à jour la position
          widget.position = pos.index or i

          -- Déterminer le parent
          parent_id = pos.parentId or null

          -- Si le parent est une zone, ajouter le widget à cette zone
          if parent_id and zones_map[parent_id]
            zone = zones_map[parent_id].zone
            if not zone.children
              zone.children = {}

            -- Ajouter le widget à la zone
            table.insert(zone.children, { widget: widget })

            -- Marquer la zone comme traitée
            processed_zones[parent_id] = true
          else
            -- Ajouter à la racine
            table.insert(new_children, { widget: widget })
        else
          -- Si le widget n'existe pas, le créer avec les données de base
          new_widget = {
            id: pos.widgetId
            position: pos.index or i
            space: 'unknown'
            title: "Widget #{pos.widgetId}"
          }
          table.insert(new_children, { widget: new_widget })
  else
    -- Si pas de positions, garder l'ordre existant
    for _, child in ipairs(config.layout.children)
      table.insert(new_children, child)

  -- Ajouter les zones qui n'ont pas été traitées (zones vides)
  for zone_id, zone_data in pairs(zones_map)
    if not processed_zones[zone_id]
      -- Ajouter la zone avec son contenu original
      table.insert(new_children, { zone: zone_data.zone })

  -- Mettre à jour la structure
  config.layout.children = new_children

  -- Re-encoder le YAML
  yaml_content = "layout:\n"
  yaml_content ..= "  direction: " .. (config.layout.direction or 'vertical') .. "\n"
  yaml_content ..= "  children:\n"

  -- Ajouter chaque widget au format YAML correct
  for _, child in ipairs(config.layout.children)
    if child.widget
      yaml_content ..= "    - widget:\n"
      yaml_content ..= "        id: " .. tostring(child.widget.id) .. "\n"
      yaml_content ..= "        title: " .. child.widget.title .. "\n"
      yaml_content ..= "        space: " .. tostring(child.widget.space) .. "\n"
      yaml_content ..= "        position: " .. tostring(child.widget.position) .. "\n"

      -- Ajouter les colonnes si présentes
      if child.widget.columns and #child.widget.columns > 0
        yaml_content ..= "        columns:\n"
        for _, col in ipairs(child.widget.columns)
          yaml_content ..= "          - " .. col .. "\n"

      -- Ajouter le groupement si présent
      if child.widget.groupBy
        yaml_content ..= "        groupBy: " .. tostring(child.widget.groupBy) .. "\n"

      -- Ajouter les autres propriétés
      for key, value in pairs(child.widget)
        if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy'
          yaml_content ..= "        " .. key .. ": " .. tostring(value) .. "\n"

  updated_yaml = yaml_content

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, updated_yaml }  -- Mettre à jour le champ yaml
    { '=', 6, os.time() }     -- Mettre à jour updatedAt
  }

  -- Retourner la vue mise à jour
  {
    id: pageId
    yaml: updated_yaml
  }

add_widget_to_view = (viewId, widget) ->
  -- Récupérer la vue existante
  t = box.space._tdb_custom_views\get viewId
  error "CustomView not found: #{viewId}" unless t

  -- Parser le YAML existant
  yaml_raw = t[4]
  if not yaml_raw or yaml_raw == ''
    yaml_raw = 'layout:\n  direction: vertical\n  children: []'

  config = yaml.decode(yaml_raw)
  if not config or type(config) != 'table'
    config = { layout: { direction: 'vertical', children: {} } }
  elseif not config.layout
    config.layout = { direction: 'vertical', children: {} }
  elseif not config.layout.children
    config.layout.children = {}

  -- Générer un ID unique pour le widget
  widget_id = uuid_mod()

  -- Créer le widget avec les données fournies au format CustomView
  -- Récupérer le nom de la source (espace ou vue)
  source_name = widget.spaceId
  space_record = box.space._tdb_spaces\get widget.spaceId
  if space_record
    source_name = space_record[2]
  else
    -- Essayer de trouver une Data View
    dv_record = box.space._tdb_data_views\get widget.spaceId
    if dv_record
      source_name = dv_record[2]

  -- Calculer la position (à la fin de la liste)
  position = #config.layout.children + 1

  new_widget =
    id: widget_id
    title: widget.title
    space: source_name
    position: position  -- Ajouter la position automatique

  -- Ajouter les colonnes si spécifiées
  if widget.fields and #widget.fields > 0
    new_widget.columns = widget.fields

  -- Ajouter le groupement si spécifié
  if widget.groupBy
    new_widget.groupBy = widget.groupBy

  -- Ajouter les paramètres si spécifiés
  if widget.params and next(widget.params)
    for key, value in pairs(widget.params)
      new_widget[key] = value

  -- Ajouter le widget à la structure layout
  table.insert(config.layout.children, {
    widget: new_widget
  })

  -- Re-encoder le YAML avec un format propre
  yaml_content = "layout:\n"
  yaml_content ..= "  direction: " .. (config.layout.direction or 'vertical') .. "\n"
  yaml_content ..= "  children:\n"

  -- Ajouter chaque widget au format YAML correct
  for _, child in ipairs(config.layout.children)
    if child.widget
      yaml_content ..= "    - widget:\n"
      yaml_content ..= "        id: " .. tostring(child.widget.id) .. "\n"
      yaml_content ..= "        title: " .. child.widget.title .. "\n"
      yaml_content ..= "        space: " .. tostring(child.widget.space) .. "\n"
      yaml_content ..= "        position: " .. tostring(child.widget.position) .. "\n"

      -- Ajouter les colonnes si présentes
      if child.widget.columns and #child.widget.columns > 0
        yaml_content ..= "        columns:\n"
        for _, col in ipairs(child.widget.columns)
          yaml_content ..= "          - " .. col .. "\n"

      -- Ajouter le groupement si présent
      if child.widget.groupBy
        yaml_content ..= "        groupBy: " .. tostring(child.widget.groupBy) .. "\n"

      -- Ajouter les autres propriétés
      for key, value in pairs(child.widget)
        if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy'
          yaml_content ..= "        " .. key .. ": " .. tostring(value) .. "\n"

  updated_yaml = yaml_content

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
    i = args.input or args  -- accepter les deux formats
    error "name is required" unless i.name
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
  reorderWidgets: (_, args, ctx) ->
    require_auth ctx

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
    require_auth ctx
    pageId = args.pageId
    zoneData = args.zoneData or {}

    error "pageId is required" unless pageId

    create_zone pageId, zoneData
  resizeZone: (_, args, ctx) ->
    require_auth ctx
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

-- Créer une nouvelle zone dans une vue
create_zone = (pageId, zoneData) ->
  -- Récupérer la vue existante
  t = box.space._tdb_custom_views\get pageId
  error "Page not found: #{pageId}" unless t

  -- Parser le YAML existant
  yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  config = yaml.decode yaml_content

  -- Gérer le cas où le YAML est mal formaté
  if not config or type(config) != 'table'
    config = { layout: { direction: 'vertical', children: {} } }
  elseif not config.layout
    config.layout = { direction: 'vertical', children: {} }
  elseif not config.layout.children or type(config.layout.children) != 'table'
    config.layout.children = {}

  -- Générer un ID unique pour la zone
  zone_id = tostring(uuid_mod.new!)

  -- Créer la nouvelle zone
  new_zone = {
    id: zone_id
    title: zoneData.title or "Zone #{zone_id}"
    factor: zoneData.factor or 0.5
    direction: zoneData.direction or 'vertical'
    children: {}
  }

  -- Ajouter la zone à la fin de la liste
  table.insert(config.layout.children, {
    zone: new_zone
  })

  -- Re-encoder le YAML
  updated_yaml = encode_layout_yaml(config)

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, updated_yaml }
    { '=', 6, os.time() }
  }

  -- Retourner la zone créée
  {
    id: zone_id
    title: new_zone.title
    factor: new_zone.factor
    direction: new_zone.direction
  }

-- Redimensionner une zone
resize_zone = (pageId, zoneId, factor) ->
  -- Récupérer la vue existante
  t = box.space._tdb_custom_views\get pageId
  error "Page not found: #{pageId}" unless t

  -- Parser le YAML existant
  yaml_content = t[4] or 'layout:\n  direction: vertical\n  children: []'
  config = yaml.decode yaml_content

  -- Gérer le cas où le YAML est mal formaté
  if not config or type(config) != 'table'
    config = { layout: { direction: 'vertical', children: {} } }
  elseif not config.layout
    config.layout = { direction: 'vertical', children: {} }
  elseif not config.layout.children or type(config.layout.children) != 'table'
    config.layout.children = {}

  -- Fonction récursive pour trouver et mettre à jour la zone
  update_zone_factor = (children) ->
    for _, child in ipairs(children)
      if child.zone and child.zone.id == zoneId
        child.zone.factor = factor
        return true
      elseif child.zone and child.zone.children
        if update_zone_factor(child.zone.children)
          return true
    return false

  -- Mettre à jour le factor de la zone
  found = update_zone_factor(config.layout.children)
  error "Zone not found: #{zoneId}" unless found

  -- Re-encoder le YAML
  updated_yaml = encode_layout_yaml(config)

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, updated_yaml }
    { '=', 6, os.time() }
  }

  -- Retourner la zone mise à jour
  {
    id: zoneId
    factor: factor
  }

-- Fonction utilitaire pour encoder le YAML
encode_layout_yaml = (config) ->
  yaml_content = "layout:\n"
  yaml_content ..= "  direction: " .. (config.layout.direction or 'vertical') .. "\n"
  yaml_content ..= "  children:\n"

  -- Fonction récursive pour encoder les enfants
  encode_children = (children, indent = "    ")
    for _, child in ipairs(children)
      if child.widget
        yaml_content ..= indent .. "- widget:\n"
        yaml_content ..= indent .. "    id: " .. tostring(child.widget.id) .. "\n"
        yaml_content ..= indent .. "    title: " .. child.widget.title .. "\n"
        yaml_content ..= indent .. "    space: " .. tostring(child.widget.space) .. "\n"
        yaml_content ..= indent .. "    position: " .. tostring(child.widget.position) .. "\n"

        -- Ajouter les colonnes si présentes
        if child.widget.columns and #child.widget.columns > 0
          yaml_content ..= indent .. "    columns:\n"
          for _, col in ipairs(child.widget.columns)
            yaml_content ..= indent .. "      - " .. col .. "\n"

        -- Ajouter le groupement si présent
        if child.widget.groupBy
          yaml_content ..= indent .. "    groupBy: " .. tostring(child.widget.groupBy) .. "\n"

        -- Ajouter les autres propriétés
        for key, value in pairs(child.widget)
          if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy'
            yaml_content ..= indent .. "    " .. key .. ": " .. tostring(value) .. "\n"

      elseif child.zone
        yaml_content ..= indent .. "- zone:\n"
        yaml_content ..= indent .. "    id: " .. tostring(child.zone.id) .. "\n"
        yaml_content ..= indent .. "    title: " .. child.zone.title .. "\n"
        yaml_content ..= indent .. "    factor: " .. tostring(child.zone.factor) .. "\n"
        yaml_content ..= indent .. "    direction: " .. (child.zone.direction or 'vertical') .. "\n"

        if child.zone.children and #child.zone.children > 0
          yaml_content ..= indent .. "    children:\n"
          encode_children(child.zone.children, indent .. "      ")

  encode_children(config.layout.children)
  return yaml_content

{ :Query, :Mutation }
