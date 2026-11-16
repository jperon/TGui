-- resolvers/custom_view_widgets.moon
-- Widget and layout-editing functions for custom YAML views.

yaml = require 'yaml'
uuid_mod = require 'uuid'

-- Valeur scalaire au format YAML. Guillemets simples systématiques : une chaîne
-- reste une chaîne (un UUID, un nombre ou « oui » écrit en paramètre ne change
-- pas de type à la relecture), et `'` se double.
yaml_quote = (value) ->
  escaped = tostring(value)\gsub "'", "''"
  "'" .. escaped .. "'"

-- Scalaire laissé nu quand c'est sans risque, entre guillemets simples sinon :
-- un titre contenant « : », « # » ou des guillemets casserait le YAML sans eux
-- (ex. « Data View: ma vue »).
yaml_scalar = (value) ->
  s = tostring value
  return yaml_quote s if s == ''
  return yaml_quote s if s\match '^%s' or s\match '%s$'
  return yaml_quote s if s\match '[:#%[%]{},&*!|>%%@`"\']'
  return yaml_quote s if s\match '^[-?]'
  return yaml_quote s if s\match '^[%d%.]+$'
  return yaml_quote s if s == 'true' or s == 'false' or s == 'null' or s == '~'
  s

-- Index de position écrit dans le YAML (nombre entier). Toute autre valeur — en
-- particulier la position de mise en page `{x, y, w, h}` envoyée par la fenêtre
-- « ＋ Widget » — est ignorée : la page est une liste ordonnée.
position_index = (value, fallback) ->
  return value if type(value) == 'number'
  fallback or 1

-- Ligne `type:` d'un widget : nom du widget personnalisé (plugin) quand il y en
-- a un, « aggregate », « table »… Vide sinon.
encode_widget_type = (widget, indent) ->
  return '' unless widget.type
  indent .. "type: " .. yaml_quote(widget.type) .. "\n"

-- Bloc `params:` d'un widget : mapping clé → valeur, clés triées pour un YAML
-- stable d'un enregistrement à l'autre. Valeurs non scalaires ignorées.
encode_widget_params = (params, indent) ->
  return '' unless params and type(params) == 'table'
  keys = {}
  for key in pairs params
    table.insert keys, key
  table.sort keys
  body = ''
  for _, key in ipairs(keys)
    value = params[key]
    continue if type(value) == 'table'
    body ..= indent .. "  " .. yaml_quote(key) .. ": " .. yaml_quote(value) .. "\n"
  return '' if body == ''
  indent .. "params:\n" .. body

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
          yaml_content ..= indent .. "    title: " .. yaml_scalar(child.widget.title or '') .. "\n"
          yaml_content ..= indent .. "    space: " .. yaml_scalar(child.widget.space or '') .. "\n"
          yaml_content ..= indent .. "    position: " .. tostring(position_index(child.widget.position, 1)) .. "\n"

          -- Type du widget (widget personnalisé : c'est le nom du plugin que
          -- `_renderWidget` lit dans `type`).
          yaml_content ..= encode_widget_type child.widget, indent .. "    "

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

          -- Paramètres du widget personnalisé (mapping, pas tostring)
          yaml_content ..= encode_widget_params child.widget.params, indent .. "    "

          -- Ajouter les autres propriétés
          for key, value in pairs(child.widget)
            if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' and key ~= 'dataViewId' and key ~= 'type' and key ~= 'params'
              yaml_content ..= indent .. "    " .. key .. ": " .. tostring(value) .. "\n"

       elseif child.zone
         yaml_content ..= indent .. "- zone:\n"
         yaml_content ..= indent .. "    id: " .. tostring(child.zone.id) .. "\n"
         yaml_content ..= indent .. "    title: " .. yaml_scalar(child.zone.title or '') .. "\n"
         yaml_content ..= indent .. "    factor: " .. tostring(child.zone.factor) .. "\n"
         yaml_content ..= indent .. "    direction: " .. (child.zone.direction or 'vertical') .. "\n"

         if child.zone.children and #child.zone.children > 0
           yaml_content ..= indent .. "    children:\n"
           encode_children(child.zone.children, indent .. "      ")

  encode_children(config.layout.children)
  return yaml_content

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
      yaml_content ..= "        title: " .. yaml_scalar(zone.title or '') .. "\n"
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
            yaml_content ..= "              title: " .. yaml_scalar(widget.title or '') .. "\n"
            yaml_content ..= "              space: " .. yaml_scalar(widget.space or '') .. "\n"
            yaml_content ..= "              position: " .. tostring(position_index(widget.position, 1)) .. "\n"
            yaml_content ..= encode_widget_type widget, "              "

            if widget.columns and #widget.columns > 0
              yaml_content ..= "              columns:\n"
              for _, col in ipairs(widget.columns)
                yaml_content ..= "                - " .. col .. "\n"

            if widget.groupBy
              yaml_content ..= "              groupBy: " .. tostring(widget.groupBy) .. "\n"

            yaml_content ..= encode_widget_params widget.params, "              "
    elseif child.widget
      yaml_content ..= "    - widget:\n"
      yaml_content ..= "        id: " .. tostring(child.widget.id) .. "\n"
      yaml_content ..= "        title: " .. yaml_scalar(child.widget.title or '') .. "\n"
      yaml_content ..= "        space: " .. yaml_scalar(child.widget.space or '') .. "\n"
      yaml_content ..= "        position: " .. tostring(position_index(child.widget.position, 1)) .. "\n"
      yaml_content ..= encode_widget_type child.widget, "        "

      -- Ajouter les colonnes si présentes
      if child.widget.columns and #child.widget.columns > 0
        yaml_content ..= "        columns:\n"
        for _, col in ipairs(child.widget.columns)
          yaml_content ..= "          - " .. col .. "\n"

      -- Ajouter le groupement si présent
      if child.widget.groupBy
        yaml_content ..= "        groupBy: " .. tostring(child.widget.groupBy) .. "\n"

      yaml_content ..= encode_widget_params child.widget.params, "        "

      -- Ajouter les autres propriétés
      for key, value in pairs(child.widget)
        if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'position' and key ~= 'columns' and key ~= 'groupBy' and key ~= 'type' and key ~= 'params'
          yaml_content ..= "        " .. key .. ": " .. tostring(value) .. "\n"

  -- Mettre à jour la vue dans la base de données
  box.space._tdb_custom_views\update pageId, {
    { '=', 4, yaml_content }
    { '=', 6, os.time() }
  }

  -- Retourner la vue mise à jour
  t = box.space._tdb_custom_views\get pageId
  {
    id: pageId
    name: t[2]
    description: t[3]
    yaml: yaml_content
    createdAt: tostring(t[5])
    updatedAt: tostring(t[6])
  }

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

-- Ajouter un widget à une vue personnalisée
add_widget_to_view = (viewId, widget) ->
  -- Récupérer la vue personnalisée
  t = box.space._tdb_custom_views\get viewId
  error "CustomView not found: #{viewId}" unless t

  -- Valider les données du widget
  error "widget must be a table" unless widget and type(widget) == 'table'
  error "widget.title is required" unless widget.title

  -- Récupérer le nom de l'espace à partir de spaceId si présent
  space_name = widget.space
  if widget.spaceId
    space = box.space._tdb_spaces\get widget.spaceId
    if space
      space_name = space[2]  -- space name

  error "widget.space or widget.spaceId is required" unless space_name

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

  -- Position dans le YAML = index dans la liste. La fenêtre « ＋ Widget » envoie
  -- une position de mise en page (`{x, y, w, h}`) qui n'a pas de sens ici et
  -- dont `tostring` casserait le YAML : on garde alors l'index calculé.
  yaml_position = position_index widget.position, position

  -- Préparer le widget avec toutes les propriétés
  new_widget = {
    id: widget.id or tostring(uuid_mod.new!)
    title: widget.title
    space: space_name
    position: yaml_position
  }

  -- Ajouter le type si présent
  if widget.type
    new_widget.type = widget.type

  -- Ajouter les colonnes (depuis fields ou columns)
  if widget.fields and type(widget.fields) == 'table' and #widget.fields > 0
    new_widget.columns = widget.fields
  elseif widget.columns and type(widget.columns) == 'table' and #widget.columns > 0
    new_widget.columns = widget.columns

  -- Ajouter le groupement si présent
  if widget.groupBy
    new_widget.groupBy = widget.groupBy

  -- Ajouter le dataViewId si présent
  if widget.dataViewId
    new_widget.dataViewId = widget.dataViewId

  -- Ajouter params si présent
  if widget.params and type(widget.params) == 'table'
    new_widget.params = widget.params

  -- Ajouter les autres propriétés dynamiques
  for key, value in pairs(widget)
    if key ~= 'id' and key ~= 'title' and key ~= 'space' and key ~= 'spaceId' and key ~= 'position' and key ~= 'columns' and key ~= 'fields' and key ~= 'groupBy' and key ~= 'dataViewId' and key ~= 'type' and key ~= 'params'
      new_widget[key] = value

  -- Ajouter le widget à la structure layout
  table.insert(config.layout.children, {
    widget: new_widget
  })

  -- Re-encoder le YAML avec un format propre
  updated_yaml = encode_layout_yaml(config)

  -- Mettre à jour la vue personnalisée dans la base de données
  box.space._tdb_custom_views\update viewId, {
    { '=', 4, updated_yaml }
    { '=', 6, os.time() }
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

{ :reorder_widgets, :add_widget_to_view, :add_data_view_to_page, :encode_layout_yaml }
