-- resolvers/custom_view_resolvers.moon
-- CRUD resolvers for custom YAML views (dashboard layouts).

yaml = require 'yaml'
uuid_mod = require 'uuid'
json = require 'json'
{ :require_auth, :require_perm, :perm_ok } = require 'resolvers.utils'

{ :reorder_widgets, :add_widget_to_view, :add_data_view_to_page, :encode_layout_yaml } = require 'resolvers.custom_view_widgets'

-- Forward declarations for functions used before definition
local create_zone
local resize_zone
local merge_zones
local split_zone
local export_layout
local import_layout
local create_layout_snapshot
local list_layout_snapshots
local restore_layout_snapshot
local create_auto_snapshot

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

delete_custom_view = (id) ->
  box.space._tdb_custom_views\delete id
  true

-- Create automatic snapshot before updating a custom view
create_auto_snapshot = (page_id) ->
  t = box.space._tdb_custom_views\get page_id
  return nil unless t
  -- Don't create snapshot if yaml is empty or hasn't changed
  return nil if not t[4] or t[4] == ''
  create_layout_snapshot page_id, t[4], "Auto-snapshot before update"

-- Create a layout snapshot
create_layout_snapshot = (page_id, yaml_content, description) ->
  id = tostring uuid_mod.new!
  now = require('clock').time!
  box.space._tdb_layout_snapshots\insert {
    id
    page_id
    yaml_content
    now
    description or ''
  }
  {
    id: id
    pageId: page_id
    yaml: yaml_content
    createdAt: now
    description: description or ''
  }

-- List all snapshots for a page
list_layout_snapshots = (page_id) ->
  result = {}
  for t in *box.space._tdb_layout_snapshots.index.by_page\select { page_id }
    table.insert result, {
      id: t[1]
      pageId: t[2]
      yaml: t[3]
      createdAt: t[4]
      description: t[5] or ''
    }
  -- Sort by created_at descending (newest first)
  table.sort result, (a, b) -> a.createdAt > b.createdAt
  result

-- Restore a layout snapshot
restore_layout_snapshot = (snapshot_id) ->
  snapshot = box.space._tdb_layout_snapshots\get snapshot_id
  error "Snapshot not found: #{snapshot_id}" unless snapshot
  page_id = snapshot[2]
  yaml_content = snapshot[3]
  -- Get the custom view
  t = box.space._tdb_custom_views\get page_id
  error "CustomView not found: #{page_id}" unless t
  -- Create a new snapshot for the current state before restoring
  create_auto_snapshot page_id
  -- Update the custom view with the snapshot's yaml
  now = require('clock').time!
  box.space._tdb_custom_views\replace { page_id, t[2], t[3], yaml_content, t[5], now }
  { id: page_id, name: t[2], description: t[3], yaml: yaml_content, createdAt: tostring(t[5]), updatedAt: tostring(now) }

-- Update a custom view with automatic snapshot
update_custom_view = (id, name, description, yaml) ->
  t = box.space._tdb_custom_views\get id
  error "CustomView not found: #{id}" unless t
  -- Create automatic snapshot if yaml is changing
  if yaml and yaml != t[4]
    create_auto_snapshot id
  now = require('clock').time!
  new_name = if name != nil then name else t[2]
  new_desc = if description != nil then description else t[3]
  new_yaml = if yaml != nil then yaml else t[4]
  box.space._tdb_custom_views\replace { id, new_name, new_desc, new_yaml, t[5], now }
  { id: id, name: new_name, description: new_desc, yaml: new_yaml, createdAt: tostring(t[5]), updatedAt: tostring(now) }

-- Export layout as YAML string
export_layout = (page_id) ->
  t = box.space._tdb_custom_views\get page_id
  error "CustomView not found: #{page_id}" unless t
  { id: t[1], name: t[2], yaml: t[4] }

-- Import layout YAML string
import_layout = (page_id, yaml) ->
  t = box.space._tdb_custom_views\get page_id
  error "CustomView not found: #{page_id}" unless t
  now = require('clock').time!
  box.space._tdb_custom_views\replace { page_id, t[2], t[3], yaml, t[5], now }
  { id: page_id, name: t[2], description: t[3], yaml: yaml, createdAt: tostring(t[5]), updatedAt: tostring(now) }

Query =
  customViews: (_, args, ctx) ->
    require_auth ctx
    out = {}
    for cv in *list_custom_views!
      table.insert out, cv if perm_ok ctx, 'view', cv.id, 'read'
    out
  customView:  (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'read'
    get_custom_view args.id
  exportLayout: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'read'
    export_layout args.pageId
  listLayoutSnapshots: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'read'
    list_layout_snapshots args.pageId

Mutation =
  createCustomView: (_, args, ctx) ->
    require_perm ctx, 'view', nil, 'write'
    i = args.input or args  -- accepter les deux formats
    error "name is required" unless i.name
    create_custom_view i.name, i.description, i.yaml
  updateCustomView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'write'
    i = args.input
    update_custom_view args.id, i.name, i.description, i.yaml
  deleteCustomView: (_, args, ctx) ->
    require_perm ctx, 'view', args.id, 'admin'
    delete_custom_view args.id
  addWidgetToView: (_, args, ctx) ->
    require_perm ctx, 'view', args.viewId, 'write'
    add_widget_to_view args.viewId, args.widget
  reorderWidgets: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    
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
    require_perm ctx, 'view', args.pageId, 'write'
    pageId = args.pageId
    zoneData = args.zoneData or {}
    
    error "pageId is required" unless pageId
    
    create_zone pageId, zoneData
  
  resizeZone: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
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
    require_perm ctx, 'view', args.pageId, 'write'
    add_data_view_to_page args.pageId, args.dataViewId

  importLayout: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    import_layout args.pageId, args.yaml

  createLayoutSnapshot: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    create_layout_snapshot args.pageId, args.yaml, args.description

  restoreLayoutSnapshot: (_, args, ctx) ->
    snap = box.space._tdb_layout_snapshots\get args.snapshotId
    require_perm ctx, 'view', snap and snap[2], 'write'
    restore_layout_snapshot args.snapshotId

  mergeZones: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    merge_zones args.pageId, args.zoneId1, args.zoneId2

  splitZone: (_, args, ctx) ->
    require_perm ctx, 'view', args.pageId, 'write'
    split_zone args.pageId, args.zoneId, args.direction

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

{ :Query, :Mutation }
