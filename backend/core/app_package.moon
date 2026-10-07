-- core/app_package.moon
-- App versioning foundation (task V1): stable item identity, canonical JSON
-- serialization, fingerprints, local state lookup and package building.
-- Spec: docs/superpowers/specs/2026-10-07-app-versioning-design.md §1.
-- Interfaces (plan « Étape 4 », contractuelles pour V2/V3):
--   canonical(value) -> string
--   fingerprint(content) -> string
--   describe_local(item_type, key) -> table|nil
--   build_package(meta, opts) -> { app, items, seed_keys }
--
-- Reading code mirrors build_snapshot in resolvers/export_resolvers.moon
-- (read-only, never modified here): record blob decoding lines 85-92, id →
-- name helpers lines 66-74, spaces/fields/views lines 109-131, relations
-- lines 132-147, custom views lines 150-153, data views lines 155-159, widget
-- plugins lines 161-171, groups/permissions lines 173-188. Group and
-- permission reads come from core/permissions.moon (list_groups lines 39-43,
-- list_permissions lines 87-97), views from core/views.moon (list_views lines
-- 55-67), space/field reads from core/spaces.moon (list_spaces lines 397-407,
-- list_fields lines 422-447, get_space_by_name lines 416-419).

json       = require 'json'
digest     = require 'digest'
spaces_mod = require 'core.spaces'
views_mod  = require 'core.views'
perms_mod  = require 'core.permissions'

-- ────────────────────────────────────────────────────────────────────────────
-- Item types and ordering
-- ────────────────────────────────────────────────────────────────────────────

ITEM_TYPES = {
  space: 'space'
  field: 'field'
  relation: 'relation'
  view: 'view'
  page: 'page'
  dataview: 'dataview'
  plugin: 'plugin'
  group: 'group'
  perm: 'perm'
  seed: 'seed'
}

-- Emission order of the buckets inside build_package.
TYPE_ORDER = { 'space', 'field', 'relation', 'view', 'page', 'dataview', 'plugin', 'group', 'perm', 'seed' }

-- The built-in admin group is never delivered by a package (spec §1).
BUILTIN_GROUPS = { admin: true }

-- ────────────────────────────────────────────────────────────────────────────
-- Canonical JSON and fingerprints
-- ────────────────────────────────────────────────────────────────────────────

-- Length of t as a Lua array (contiguous integer keys 1..n), nil otherwise.
-- An empty table counts as the empty array so that {} and [] agree.
array_len = (t) ->
  count = 0
  max = 0
  for k, _ in pairs t
    return nil unless type(k) == 'number' and k == math.floor(k) and k >= 1
    count += 1
    max = k if k > max
  return nil if max != count
  count

-- Scalars go through Tarantool's json.encode; a value json refuses to encode
-- falls back to a deterministic quoted form instead of raising.
encode_scalar = (v) ->
  ok, encoded = pcall json.encode, v
  return encoded if ok
  return string.format '%q', v if type(v) == 'string'
  'null'

canonical = nil

canonical_array = (t, len) ->
  parts = {}
  for i = 1, len
    table.insert parts, canonical t[i]
  "[#{table.concat parts, ','}]"

canonical_object = (t) ->
  keys = [k for k, _ in pairs t]
  table.sort keys, (a, b) -> tostring(a) < tostring(b)
  parts = {}
  for k in *keys
    table.insert parts, "#{encode_scalar tostring k}:#{canonical t[k]}"
  "{#{table.concat parts, ','}}"

-- Deterministic JSON: object keys sorted recursively, arrays kept in order,
-- scalars encoded by json.encode. Two tables equal up to key order give the
-- same string.
canonical = (value) ->
  t = type value
  if t == 'table'
    len = array_len value
    if len != nil
      canonical_array value, len
    else
      canonical_object value
  elseif t == 'nil'
    'null'
  else
    encode_scalar value

fingerprint = (content) -> digest.sha256_hex canonical(content)

-- ────────────────────────────────────────────────────────────────────────────
-- Normalization helpers
-- ────────────────────────────────────────────────────────────────────────────

-- A stored record is { id, json.encode(data) } (export_resolvers.moon:85-92).
decode_record = (blob) ->
  return blob if type(blob) == 'table'
  return {} unless type(blob) == 'string'
  ok, decoded = pcall json.decode, blob
  if ok and type(decoded) == 'table'
    decoded
  else
    {}

-- Stored JSON configs become tables before canonicalization: two equivalent
-- encodings of the same config then give the same fingerprint. Anything that
-- does not decode to a table (page YAML, plugin code) is kept as text.
decode_config = (raw) ->
  return raw unless type(raw) == 'string'
  trimmed = raw\match '^%s*(.-)%s*$'
  first = trimmed\sub 1, 1
  return raw unless first == '{' or first == '['
  ok, decoded = pcall json.decode, raw
  if ok and type(decoded) == 'table'
    decoded
  else
    raw

-- export_resolvers.moon:66-74
space_name_by_id = (sid) ->
  t = box.space._tdb_spaces\get sid
  t and t[2] or nil

field_name_by_id = (fid) ->
  t = box.space._tdb_fields\get fid
  t and t[3] or nil

-- A source space or a permission resource may be stored as an id or as a
-- name: resolve to the space name, fall back to the stored value.
resolve_space_name = (value) ->
  return '' if value == nil or value == ''
  by_id = space_name_by_id value
  return by_id if by_id
  return value if spaces_mod.get_space_by_name value
  value

-- export_resolvers.moon:182-184: the wildcard permission keeps '*', an
-- unknown resource falls back to the stored id.
resource_name = (rid) ->
  return '*' if rid == nil or rid == perms_mod.WILDCARD_ID
  resolve_space_name rid

-- Natural keys must be scalars: a table would stringify to a memory address
-- and make the seed key unstable.
stable_key = (v) ->
  t = type v
  v if t == 'string' or t == 'number' or t == 'boolean'

-- ────────────────────────────────────────────────────────────────────────────
-- Content builders — shared by build_package and describe_local so that both
-- always describe an element the same way.
-- Empty values are normalized (nil → '', nil → {}) so that one reality always
-- yields one fingerprint.
-- ────────────────────────────────────────────────────────────────────────────

space_content = (sp) ->
  { description: sp.description or '' }

-- Named row from core/spaces.list_fields (core/spaces.moon:422-447). No
-- position: package order follows creation order (list_fields is sorted by
-- position).
field_content = (f) ->
  {
    fieldType: f.fieldType
    notNull: f.notNull == true
    description: f.description or ''
    formula: f.formula or ''
    triggerFields: f.triggerFields or {}
    language: f.language or 'lua'
  }

relation_content = (from_space, from_field, to_space, to_field) ->
  { fromSpace: from_space, fromField: from_field, toSpace: to_space, toField: to_field }

view_content = (space_name, v) ->
  { space: space_name, name: v.name, viewType: v.viewType, config: decode_config(v.config) }

-- Row of _tdb_custom_views (export_resolvers.moon:150-153).
page_content = (row) ->
  { name: row[2], description: row[3] or '', yaml: row[4] or '' }

-- Row of _tdb_data_views (export_resolvers.moon:155-159); sourceSpace is the
-- space NAME.
dataview_content = (row) ->
  {
    name: row[2]
    description: row[3] or ''
    sourceSpace: resolve_space_name(row[4])
    config: decode_config row[5]
  }

-- Row of _tdb_widget_plugins (export_resolvers.moon:161-171).
plugin_content = (row) ->
  {
    name: row[2]
    description: row[3] or ''
    scriptLanguage: row[4] or 'coffeescript'
    templateLanguage: row[5] or 'pug'
    scriptCode: row[6] or ''
    templateCode: row[7] or ''
  }

-- Named group from core/permissions.list_groups (lines 39-43).
group_content = (g) ->
  { name: g.name, description: g.description or '' }

-- Named permission from core/permissions.list_permissions (lines 87-97).
perm_content = (group_name, p) ->
  {
    group: group_name
    resourceType: p.resourceType
    resource: resource_name(p.resourceId)
    level: p.level
  }

seed_content = (space_name, key, data) ->
  { space: space_name, key: key, data: data }

-- ────────────────────────────────────────────────────────────────────────────
-- Key parsing
-- ────────────────────────────────────────────────────────────────────────────

strip_prefix = (key, prefix) ->
  return nil unless type(key) == 'string' and key\sub(1, #prefix) == prefix
  rest = key\sub(#prefix + 1)
  return nil if rest == ''
  rest

-- '<scope>.<name>' split on the last dot (a scope may contain dots).
split_scope_name = (rest) ->
  scope, name = rest\match '^(.*)%.([^%.]+)$'
  return nil unless scope and name and scope != ''
  scope, name

split_pipes = (rest) ->
  parts = {}
  for piece in rest\gmatch '[^|]+'
    table.insert parts, piece
  parts

-- ────────────────────────────────────────────────────────────────────────────
-- Collectors (build_package)
-- ────────────────────────────────────────────────────────────────────────────

sorted_spaces = ->
  list = spaces_mod.list_spaces!
  table.sort list, (a, b) -> a.name < b.name
  list

collect_spaces_and_fields = (space_bucket, field_bucket, space_list) ->
  for sp in *space_list
    table.insert space_bucket, {
      type: ITEM_TYPES.space
      key: "space:#{sp.name}"
      content: space_content(sp)
    }
    for f in *spaces_mod.list_fields sp.id
      table.insert field_bucket, {
        type: ITEM_TYPES.field
        key: "field:#{sp.name}.#{f.name}"
        content: field_content(f)
      }

collect_relations = (bucket, space_list) ->
  seen_ids = {}
  seen_keys = {}
  for sp in *space_list
    for t in *box.space._tdb_relations.index.by_from\select { sp.id }
      continue if seen_ids[t[1]]
      seen_ids[t[1]] = true
      from_sp  = space_name_by_id t[2]
      from_fld = field_name_by_id t[3]
      to_sp    = space_name_by_id t[4]
      to_fld   = field_name_by_id t[5]
      continue unless from_sp and from_fld and to_sp and to_fld
      key = "relation:#{from_sp}.#{from_fld}"
      continue if seen_keys[key]
      seen_keys[key] = true
      table.insert bucket, {
        type: ITEM_TYPES.relation
        key: key
        content: relation_content(from_sp, from_fld, to_sp, to_fld)
      }

collect_views = (bucket, space_list) ->
  for sp in *space_list
    for v in *views_mod.list_views sp.id
      table.insert bucket, {
        type: ITEM_TYPES.view
        key: "view:#{sp.name}.#{v.name}"
        content: view_content(sp.name, v)
      }

collect_pages = (bucket) ->
  for row in *box.space._tdb_custom_views\select {}
    table.insert bucket, {
      type: ITEM_TYPES.page
      key: "page:#{row[2]}"
      content: page_content(row)
    }

collect_dataviews = (bucket) ->
  for row in *box.space._tdb_data_views\select {}
    table.insert bucket, {
      type: ITEM_TYPES.dataview
      key: "dataview:#{row[2]}"
      content: dataview_content(row)
    }

collect_plugins = (bucket) ->
  for row in *box.space._tdb_widget_plugins\select {}
    table.insert bucket, {
      type: ITEM_TYPES.plugin
      key: "plugin:#{row[2]}"
      content: plugin_content(row)
    }

collect_groups_and_perms = (group_bucket, perm_bucket) ->
  seen_perms = {}
  for g in *perms_mod.list_groups!
    continue if BUILTIN_GROUPS[g.name]
    table.insert group_bucket, {
      type: ITEM_TYPES.group
      key: "group:#{g.name}"
      content: group_content(g)
    }
    for p in *perms_mod.list_permissions g.id
      key = "perm:#{g.name}|#{p.resourceType}|#{resource_name p.resourceId}|#{p.level}"
      continue if seen_perms[key]
      seen_perms[key] = true
      table.insert perm_bucket, {
        type: ITEM_TYPES.perm
        key: key
        content: perm_content(g.name, p)
      }

collect_seeds = (bucket, seed_keys) ->
  for space_name, key_field in pairs seed_keys
    user_sp = box.space["data_#{space_name}"]
    continue unless user_sp
    for t in *user_sp\select {}
      data = decode_record t[2]
      v = stable_key data[key_field]
      continue if v == nil
      table.insert bucket, {
        type: ITEM_TYPES.seed
        key: "seed:#{space_name}|#{v}"
        content: seed_content(space_name, v, data)
      }

-- ────────────────────────────────────────────────────────────────────────────
-- Local state lookup (describe_local)
-- ────────────────────────────────────────────────────────────────────────────

find_field = (space_name, field_name) ->
  sp = spaces_mod.get_space_by_name space_name
  return nil unless sp
  for f in *spaces_mod.list_fields sp.id
    return f if f.name == field_name
  nil

find_page_row = (name) ->
  for row in *box.space._tdb_custom_views\select {}
    return row if row[2] == name
  nil

find_dataview_row = (name) ->
  for row in *box.space._tdb_data_views\select {}
    return row if row[2] == name
  nil

find_plugin_row = (name) ->
  box.space._tdb_widget_plugins.index.by_name\get name

find_group = (name) ->
  for g in *perms_mod.list_groups!
    return g if g.name == name
  nil

-- The natural key field is not part of the seed key (plan, identité des
-- éléments), so the row is located by scanning the stored fields of the space
-- in position order until one holds the key value.
find_seed = (space_name, raw_key) ->
  sp = spaces_mod.get_space_by_name space_name
  return nil unless sp
  user_sp = box.space["data_#{space_name}"]
  return nil unless user_sp
  rows = {}
  for t in *user_sp\select {}
    table.insert rows, decode_record t[2]
  for f in *spaces_mod.list_fields sp.id
    for data in *rows
      v = stable_key data[f.name]
      return { key: v, data: data } if v != nil and tostring(v) == raw_key
  nil

describe_space = (key) ->
  name = strip_prefix key, 'space:'
  return nil unless name
  sp = spaces_mod.get_space_by_name name
  return nil unless sp
  space_content sp

describe_field = (key) ->
  rest = strip_prefix key, 'field:'
  return nil unless rest
  sp_name, f_name = split_scope_name rest
  return nil unless sp_name
  f = find_field sp_name, f_name
  return nil unless f
  field_content f

describe_relation = (key) ->
  rest = strip_prefix key, 'relation:'
  return nil unless rest
  from_sp, from_fld = split_scope_name rest
  return nil unless from_sp
  sp = spaces_mod.get_space_by_name from_sp
  return nil unless sp
  for t in *box.space._tdb_relations.index.by_from\select { sp.id }
    continue unless field_name_by_id(t[3]) == from_fld
    from_name = space_name_by_id t[2]
    to_sp = space_name_by_id t[4]
    to_fld = field_name_by_id t[5]
    return nil unless from_name and to_sp and to_fld
    return relation_content(from_name, from_fld, to_sp, to_fld)
  nil

describe_view = (key) ->
  rest = strip_prefix key, 'view:'
  return nil unless rest
  sp_name, v_name = split_scope_name rest
  return nil unless sp_name
  sp = spaces_mod.get_space_by_name sp_name
  return nil unless sp
  for v in *views_mod.list_views sp.id
    return view_content(sp_name, v) if v.name == v_name
  nil

describe_page = (key) ->
  name = strip_prefix key, 'page:'
  return nil unless name
  row = find_page_row name
  return nil unless row
  page_content row

describe_dataview = (key) ->
  name = strip_prefix key, 'dataview:'
  return nil unless name
  row = find_dataview_row name
  return nil unless row
  dataview_content row

describe_plugin = (key) ->
  name = strip_prefix key, 'plugin:'
  return nil unless name
  row = find_plugin_row name
  return nil unless row
  plugin_content row

describe_group = (key) ->
  name = strip_prefix key, 'group:'
  return nil unless name
  g = find_group name
  return nil unless g
  group_content g

describe_perm = (key) ->
  rest = strip_prefix key, 'perm:'
  return nil unless rest
  parts = split_pipes rest
  return nil unless #parts == 4
  group_name, rtype, res, lvl = parts[1], parts[2], parts[3], parts[4]
  g = find_group group_name
  return nil unless g
  for p in *perms_mod.list_permissions g.id
    if p.resourceType == rtype and p.level == lvl and resource_name(p.resourceId) == res
      return perm_content group_name, p
  nil

describe_seed = (key) ->
  rest = strip_prefix key, 'seed:'
  return nil unless rest
  idx = rest\find '|'
  return nil unless idx
  space_name = rest\sub(1, idx - 1)
  raw_key = rest\sub(idx + 1)
  found = find_seed space_name, raw_key
  return nil unless found
  seed_content space_name, found.key, found.data

DESCRIBERS = {
  space: describe_space
  field: describe_field
  relation: describe_relation
  view: describe_view
  page: describe_page
  dataview: describe_dataview
  plugin: describe_plugin
  group: describe_group
  perm: describe_perm
  seed: describe_seed
}

-- Current local content of an element, in package form, or nil when the
-- element does not exist locally.
describe_local = (item_type, key) ->
  return nil unless type(key) == 'string'
  describe = DESCRIBERS[item_type]
  return nil unless describe
  describe key

-- ────────────────────────────────────────────────────────────────────────────
-- Package building
-- ────────────────────────────────────────────────────────────────────────────

by_key = (a, b) -> a.key < b.key

-- meta: { id, name, version, description }
-- opts.seed: { [space name or id] = natural key field }, optional.
-- Returns { app, items = { {type, key, content} … }, seed_keys }.
build_package = (meta, opts) ->
  opts = opts or {}
  buckets = {}
  for t in *TYPE_ORDER
    buckets[t] = {}

  seed_keys = {}
  for space_ref, key_field in pairs(opts.seed or {})
    space_name = resolve_space_name space_ref
    seed_keys[space_name] = key_field if space_name and space_name != ''

  space_list = sorted_spaces!
  collect_spaces_and_fields buckets.space, buckets.field, space_list
  collect_relations buckets.relation, space_list
  collect_views buckets.view, space_list
  collect_pages buckets.page
  collect_dataviews buckets.dataview
  collect_plugins buckets.plugin
  collect_groups_and_perms buckets.group, buckets.perm
  collect_seeds buckets.seed, seed_keys

  -- Fields keep creation order (position); every other type is sorted by key,
  -- so the item list is fully deterministic.
  for t in *TYPE_ORDER
    table.sort buckets[t], by_key unless t == 'field'

  items = {}
  for t in *TYPE_ORDER
    for it in *buckets[t]
      table.insert items, it

  {
    app: {
      id: meta.id
      name: meta.name
      version: meta.version
      description: meta.description or ''
    }
    items: items
    seed_keys: seed_keys
  }

{ :canonical, :fingerprint, :describe_local, :build_package, :ITEM_TYPES }
