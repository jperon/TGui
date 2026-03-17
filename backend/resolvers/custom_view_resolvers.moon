-- resolvers/custom_view_resolvers.moon
-- CRUD resolvers for custom YAML views (dashboard layouts).

yaml = require 'yaml'
uuid_mod = require 'uuid'
json = require 'json'
{ :require_auth } = require 'resolvers.utils'

-- Forward declarations for functions used before definition
local add_data_view_to_page
local encode_layout_yaml
local create_zone
local resize_zone
local merge_zones

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

  -- Stocker les enfants originaux de chaque zone (copie pour éviter les modifications en place)
  original_zone_children = {}
  for _, child in ipairs(config.layout.children)
    if child.zone and child.zone.id
      original_zone_children[child.zone.id] = {}
      if child.zone.children
        for _, zchild in ipairs(child.zone.children)
          table.insert(original_zone_children[child.zone.id], zchild)

  -- Reconstruire la structure avec les nouvelles positions et parents
  new_children = {}
  processed_zones = {}

  -- Stocker les widgets à ajouter à chaque zone (et racine)
  zone_widgets = {}  -- zone_id -> list of widgets
  root_widgets = {}  -- list of widgets

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
            if not zone_widgets[parent_id]
              zone_widgets[parent_id] = {}
            table.insert(zone_widgets[parent_id], { widget: widget })
            processed_zones[parent_id] = true
          else
            -- Ajouter à la racine
            table.insert(root_widgets, { widget: widget })
        else
          -- Si le widget n'existe pas, le créer avec les données de base
          new_widget = {
            id: pos.widgetId
            position: pos.index or i
            space: 'unknown'
            title: "Widget #{pos.widgetId}"
          }
          if parent_id and zones_map[parent_id]
            if not zone_widgets[parent_id]
              zone_widgets[parent_id] = {}
            table.insert(zone_widgets[parent_id], { widget: new_widget })
            processed_zones[parent_id] = true
          else
            table.insert(root_widgets, { widget: new_widget })
  else
    -- Si pas de positions, garder l'ordre existant
    for _, child in ipairs(config.layout.children)
      table.insert(new_children, child)

  -- Ajouter les widgets à la racine
  for _, w in ipairs(root_widgets)
    table.insert(new_children, w)

  -- Ajouter les zones (traitées ou non) avec leurs widgets
  for zone_id, zone_data in pairs(zones_map)
    zone = zone_data.zone
    zone_entry = { zone: zone, children: {} }
    
    -- Ajouter les widgets originaux + nouveaux widgets pour cette zone
    if original_zone_children[zone_id]
      for _, child in ipairs(original_zone_children[zone_id])
        table.insert(zone_entry.zone.children, child)
    
    if zone_widgets[zone_id]
      for _, w in ipairs(zone_widgets[zone_id])
        table.insert(zone_entry.zone.children, w)
    
    table.insert(new_children, zone_entry)

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

  -- Ajouter chaque widget/zone au format YAML correct
  for _, child in ipairs(config.layout.children)
    if child.zone
      -- Générer le YAML pour une zone
      zone = child.zone
      yaml_content ..= "    - zone:\n"
      yaml_content ..= "        id: " .. tostring(zone.id) .. "\n"
      yaml_content ..= "        title: " .. tostring(zone.title or '') .. "\n"
      yaml_content ..= "        factor: " .. tostring(zone.factor or 1) .. "\n"
      yaml_content ..= "        direction: " .. tostring(zone.direction or 'vertical') .. "\n"

      -- Ajouter les enfants de la zone (widgets)
      if zone.children and #zone.children > 0
        yaml_content ..= "        children:\n"
        for _, zone_child in ipairs(zone.children)
          if zone_child.widget
            widget = zone_child.widget
            yaml_content ..= "          - widget:\n"
            yaml_content ..= "              id: " .. tostring(widget.id) .. "\n"
            yaml_content ..= "              title: " .. tostring(widget.title or '') .. "\n"
            yaml_content ..= "              space: " .. tostring(widget.space or '') .. "\n"
            yaml_content ..= "              position: " .. tostring(widget.position or 1) .. "\n"

            if widget.columns and #widget.columns > 0
              yaml_content ..= "              columns:\n"
              for _, col in ipairs(widget.columns)
                yaml_content ..= "                - " .. col .. "\n"

            if widget.groupBy
              yaml_content ..= "              groupBy: " .. tostring(widget.groupBy) .. "\n"
    elseif child.widget
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
  
  addDataViewToPage: (_, args, ctx) ->
    require_auth ctx
    add_data_view_to_page args.pageId, args.dataViewId

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

  -- Fonction pour trouver la zone et son parent
  find_and_update_zone = (children, parent = nil) ->
    for i, child in ipairs(children)
      if child.zone and child.zone.id == zoneId
        child.zone.factor = factor
        return { zone: child.zone, parent: children, index: i, found: true }
      elseif child.zone and child.zone.children
        result = find_and_update_zone(child.zone.children, child.zone.children)
        return result if result and result.found
    return { found: false }

  -- Trouver et mettre à jour la zone
  result = find_and_update_zone(config.layout.children)
  error "Zone not found: #{zoneId}" unless result and result.found

  -- Recalculer les facteurs des zones voisines
  if result.parent
    remaining = 1.0 - factor
    sibling_sum = 0
    for i, child in ipairs(result.parent)
      if i ~= result.index and child.zone
        sibling_sum += child.zone.factor

    if sibling_sum > 0
      for i, child in ipairs(result.parent)
        if i ~= result.index and child.zone
          child.zone.factor = (child.zone.factor / sibling_sum) * remaining

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

-- Trouver une zone et son parent dans la structure de layout
find_zone_with_parent = (children, zoneId, parent = nil) ->
  for i, child in ipairs(children)
    if child.zone and child.zone.id == zoneId
      return { zone: child.zone, parent: children, index: i, found: true }
    elseif child.zone and child.zone.children
      result = find_zone_with_parent(child.zone.children, zoneId, child.zone.children)
      return result if result and result.found
  return { found: false }

-- Fusionner deux zones adjacentes ayant le même parent
merge_zones = (pageId, zoneId1, zoneId2) ->
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

  -- Trouver les deux zones avec leurs parents
  result1 = find_zone_with_parent(config.layout.children, zoneId1)
  result2 = find_zone_with_parent(config.layout.children, zoneId2)

  error "Zone not found: #{zoneId1}" unless result1 and result1.found
  error "Zone not found: #{zoneId2}" unless result2 and result2.found

  -- Vérifier qu'elles ont le même parent (sont des sœurs)
  error "Zones must have the same parent to be merged" unless result1.parent == result2.parent

  -- S'assurer que zoneId1 est avant zoneId2 dans la liste pour simplifier la logique
  if result1.index > result2.index
    -- Échanger les résultats pour que zone1 soit toujours avant zone2
    result1, result2 = result2, result1

  zone1 = result1.zone
  zone2 = result2.zone
  parent = result1.parent

  -- Déplacer tous les enfants de zone2 vers zone1
  if zone2.children and #zone2.children > 0
    if not zone1.children
      zone1.children = {}
    for _, child in ipairs(zone2.children)
      table.insert(zone1.children, child)

  -- Mettre à jour le facteur de zone1 (sans dépasser 1.0)
  zone1.factor = math.min(1.0, zone1.factor + zone2.factor)

  -- Supprimer zone2 de la liste des enfants du parent
  table.remove(parent, result2.index)

  -- Re-encoder le YAML
  updated_yaml = encode_layout_yaml(config)

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, updated_yaml }
    { '=', 6, os.time() }
  }

  -- Retourner la vue mise à jour
  {
    id: pageId
    yaml: updated_yaml
  }

-- Diviser une zone en deux zones selon une direction
split_zone = (pageId, zoneId, direction) ->
  -- Valider la direction
  error "Direction must be 'vertical' or 'horizontal'" unless direction == 'vertical' or direction == 'horizontal'

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

  -- Trouver la zone à diviser avec son parent
  result = find_zone_with_parent(config.layout.children, zoneId)
  error "Zone not found: #{zoneId}" unless result and result.found

  zone = result.zone
  parent = result.parent
  index = result.index

  -- Calculer le nouveau facteur pour chaque zone (moitié de l'original)
  new_factor = zone.factor / 2

  -- Créer les deux nouvelles zones
  zone_id1 = tostring(uuid_mod.new!)
  zone_id2 = tostring(uuid_mod.new!)

  new_zone1 = {
    id: zone_id1
    title: zone.title .. " Part 1"
    factor: new_factor
    direction: direction
    children: {}
  }

  new_zone2 = {
    id: zone_id2
    title: zone.title .. " Part 2"
    factor: new_factor
    direction: direction
    children: {}
  }

  -- Distribuer les enfants de la zone originale entre les deux nouvelles zones
  if zone.children and #zone.children > 0
    -- Diviser les enfants aussi équitablement que possible
    mid = math.ceil(#zone.children / 2)
    for i = 1, mid
      table.insert(new_zone1.children, zone.children[i])
    for i = mid + 1, #zone.children
      table.insert(new_zone2.children, zone.children[i])

  -- Remplacer la zone originale par les deux nouvelles zones
  table.remove(parent, index)  -- Supprimer la zone originale
  table.insert(parent, index, { zone: new_zone1 })  -- Insérer la première nouvelle zone
  table.insert(parent, index + 1, { zone: new_zone2 })  -- Insérer la seconde nouvelle zone

  -- Re-encoder le YAML
  updated_yaml = encode_layout_yaml(config)

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, updated_yaml }
    { '=', 6, os.time() }
  }

  -- Retourner la vue mise à jour
  {
    id: pageId
    yaml: updated_yaml
  }

-- Fonction utilitaire pour encoder le YAML
encode_layout_yaml = (config) ->
  yaml_content = "layout:\n"
  yaml_content ..= "  direction: " .. (config.layout.direction or 'vertical') .. "\n"
  yaml_content ..= "  children:\n"

  -- Fonction récursive pour encoder les enfants
  encode_children = (children, indent) ->
    indent = indent or "    "
    for _, child in ipairs(children)
       if child.widget
          yaml_content ..= indent .. "- widget:\n"
          yaml_content ..= indent .. "    id: " .. tostring(child.widget.id) .. "\n"
          yaml_content ..= indent .. "    title: " .. child.widget.title .. "\n"
          yaml_content ..= indent .. "    space: " .. tostring(child.widget.space) .. "\n"
          yaml_content ..= indent .. "    position: " .. tostring(child.widget.position) .. "\n"

          -- Ajouter le dataViewId si présent
          if child.widget.dataViewId
            yaml_content ..= indent .. "    dataViewId: " .. tostring(child.widget.dataViewId) .. "\n"

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
            if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' and key ~= 'dataViewId'
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


-- Ajouter une Data View à une page (vue personnalisée)
add_data_view_to_page = (pageId, dataViewId) ->
  -- Récupérer la vue personnalisée (page) par pageId
  t = box.space._tdb_custom_views\get pageId
  error "CustomView not found: #{pageId}" unless t

  -- Récupérer la data view par dataViewId
  dv = box.space._tdb_data_views\get dataViewId
  error "DataView not found: #{dataViewId}" unless dv

  -- Générer un ID unique pour le widget
  widget_id = tostring(uuid_mod.new!)

  -- Créer le widget avec les données de la data view
  new_widget = {
    id: widget_id
    title: "Data View: " .. dv[2]  -- dv[2] est le nom
    space: dv[2]                   -- dv[2] est le nom de la data view
    dataViewId: dv[1]              -- dv[1] est l'ID
    position: 0                    -- Sera mis à jour après insertion
  }

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

  -- Calculer la position (à la fin de la liste)
  position = #config.layout.children + 1
  new_widget.position = position

  -- Ajouter le widget à la structure layout
  table.insert(config.layout.children, {
    widget: new_widget
  })

  -- Re-encoder le YAML avec un format propre
  updated_yaml = encode_layout_yaml(config)

  -- Mettre à jour la vue personnalisée dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, updated_yaml }  -- Mettre à jour le champ yaml
    { '=', 6, os.time() }     -- Mettre à jour updatedAt
  }

  -- Retourner la vue personnalisée mise à jour
  {
    id: t[1]
    name: t[2]
    description: t[3]
    yaml: updated_yaml
    createdAt: tostring(t[5])
    updatedAt: tostring(os.time())
  }

-- Fusionner deux zones adjacentes ayant le même parent
mergeZones: (_, args, ctx) ->
  require_auth ctx
  merge_zones args.pageId, args.zoneId1, args.zoneId2

-- Diviser une zone en deux zones selon une direction
splitZone: (_, args, ctx) ->
  require_auth ctx
  split_zone args.pageId, args.zoneId, args.direction

{ :Query, :Mutation }
