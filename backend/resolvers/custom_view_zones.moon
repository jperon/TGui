-- resolvers/custom_view_zones.moon
-- Zone layout functions for custom YAML views.

yaml = require 'yaml'
uuid_mod = require 'uuid'
{ :encode_layout_yaml } = require 'resolvers.custom_view_widgets'

-- Trouver une zone et son parent dans la structure de layout
find_zone_with_parent = (children, zoneId, parent = nil) ->
  for i, child in ipairs(children)
    if child.zone and child.zone.id == zoneId
      return { zone: child.zone, parent: children, index: i, found: true }
    elseif child.zone and child.zone.children
      result = find_zone_with_parent(child.zone.children, zoneId, child.zone.children)
      return result if result and result.found
  return { found: false }

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

{ :create_zone, :resize_zone, :merge_zones, :split_zone, :find_zone_with_parent }
