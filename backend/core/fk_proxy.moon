-- core/fk_proxy.moon
-- Foreign Key proxy resolution - module dédié pour simplifier triggers.moon
-- Gère la résolution des clés étrangères avec cache et optimisations

json = require 'json'
log  = require 'log'
{ :safe_call } = require 'core.config'

-- Debug flag pour troubleshooting FK
DEBUG_FK_PROXY = false

-- Cache global pour les espaces et relations FK
fk_cache = {
  spaces: {}      -- space_name -> { records, by_field }
  fk_maps: {}     -- space_id -> fk_def_map
}

-- ── Helper functions ────────────────────────────────────────────────────────

-- Décode un tuple Tarantool en objet Lua
decode_tuple = (tup) ->
  data = if type(tup[2]) == 'string' then json.decode(tup[2]) else tup[2]
  data._id = tostring(tup[1])
  data

-- Charge et met en cache les enregistrements d'un espace
ensure_space = (s_name, to_field_name) ->
  sc = fk_cache.spaces[s_name]
  unless sc
    sc = { records: {}, by_field: {} }
    tb = box.space["data_#{s_name}"]
    if tb
      if DEBUG_FK_PROXY
        print("DEBUG ensure_space: loading #{#tb} records from #{s_name}")
      for tup in *tb\select {}
        d = decode_tuple tup
        sc.records[d._id] = d
    fk_cache.spaces[s_name] = sc
  
  -- Toujours construire l'index _id pour recherche primaire
  unless sc.by_field['_id']
    idx = {}
    if DEBUG_FK_PROXY
      print("DEBUG ensure_space: building index for _id")
    for _, d in pairs sc.records
      if d._id ~= nil
        key = tostring(d._id)
        idx[key] = d
    sc.by_field['_id'] = idx
  
  -- Construire index spécifique si différent de _id
  if to_field_name != '_id' and not sc.by_field[to_field_name]
    idx = {}
    if DEBUG_FK_PROXY
      print("DEBUG ensure_space: building index for #{to_field_name}")
    for _, d in pairs sc.records
      if d[to_field_name] ~= nil
        key = tostring(d[to_field_name])
        idx[key] = d
    sc.by_field[to_field_name] = idx
  
  sc

-- Construit et met en cache la map des définitions FK pour un espace
ensure_fk_def_map = (space_id) ->
  return fk_cache.fk_maps[space_id] if fk_cache.fk_maps[space_id]
  
  -- Récupérer les relations pour cet espace
  rels = {}
  for t in *box.space._tdb_relations\select {}
    if t[2] == space_id
      rels[t[3]] = { toSpaceId: t[4], toFieldId: t[5] }
  
  -- Résoudre les noms d'espaces et de champs
  space_by_id = {}
  for t in *box.space._tdb_spaces\select {}
    space_by_id[t[1]] = { name: t[2] }
  
  field_by_id = {}
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    field_by_id[t[1]] = { name: t[3] }
  
  -- Construire les autres espaces aussi
  for _, rel in pairs rels
    for t in *box.space._tdb_fields.index.by_space\select { rel.toSpaceId }
      field_by_id[t[1]] = { name: t[3] }
  
  -- Construire la map finale
  fk_def_map = {}
  for field_name, rel in pairs rels
    to_space = space_by_id[rel.toSpaceId]
    to_field = field_by_id[rel.toFieldId]
    if to_space and to_field
      fk_def_map[field_name] = {
        toSpaceName: to_space.name
        toFieldName: to_field.name
      }
  
  fk_cache.fk_maps[space_id] = fk_def_map
  fk_def_map

-- ── API publique ────────────────────────────────────────────────────────────

-- Crée un proxy pour résoudre les FK d'un enregistrement
make_self_proxy = (record, space_id, cache = fk_cache, space_name) ->
  -- Si space_name n'est pas fourni, essayer de le déduire
  unless space_name
    space_meta = box.space._tdb_spaces\get space_id
    space_name = space_meta and space_meta[2]
  
  fk_def_map = ensure_fk_def_map space_id
  
  proxy = setmetatable {}, {
    __index: (t, k) ->
      cached = rawget t, k
      return cached if cached != nil
      
      v = record[k]
      
      -- Résolution FK si le champ est une relation
      fk = fk_def_map and fk_def_map[k]
      if fk
        sc = ensure_space fk.toSpaceName, '_id'
        d = sc.by_field['_id'] and sc.by_field['_id'][tostring v]
        
        -- Debug logs seulement si nécessaire
        if DEBUG_FK_PROXY or not d
          print("DEBUG FK lookup:")
          print("  - space: #{fk.toSpaceName}")
          print("  - toField: #{fk.toFieldName}")
          print("  - searching for value: #{tostring(v)}")
          print("  - found: #{tostring(d)}")
        
        if d
          nested = make_self_proxy d, nil, cache, fk.toSpaceName
          rawset t, k, nested
          return nested
        return nil
      v
  }
  proxy

-- Nettoie le cache (utile pour les tests)
clear_cache = ->
  fk_cache.spaces = {}
  fk_cache.fk_maps = {}

-- Export
{
  :make_self_proxy, :clear_cache, :DEBUG_FK_PROXY
  :ensure_space, :ensure_fk_def_map
}
