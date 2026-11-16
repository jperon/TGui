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
-- (read-only, never modified here): record blob decoding lines 87-96, id →
-- name helpers lines 69-78, spaces/fields/views lines 111-133, relations
-- lines 135-150, custom views lines 152-155, data views lines 158-161, view
-- presets lines 164-175, widget plugins lines 177-187, groups/permissions
-- lines 189-203. Group and
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
  preset: 'preset'
  plugin: 'plugin'
  group: 'group'
  perm: 'perm'
  seed: 'seed'
}

-- Emission order of the buckets inside build_package. `preset` comes after
-- `page` and `dataview` because its scope names a page or a space, both
-- delivered earlier (app_apply applies the types in this same order).
TYPE_ORDER = { 'space', 'field', 'relation', 'view', 'page', 'dataview', 'preset', 'plugin', 'group', 'perm', 'seed' }

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

-- _tdb_custom_views: by_name is unique (core/spaces.moon:86-87); by id is the
-- primary key.
page_id_by_name = (name) ->
  row = box.space._tdb_custom_views.index.by_name\get name
  row and row[1]

page_name_by_id = (pid) ->
  row = box.space._tdb_custom_views\get pid
  row and row[2]

-- A source space or a permission resource may be stored as an id or as a
-- name: resolve to the space name, fall back to the stored value.
resolve_space_name = (value) ->
  return '' if value == nil or value == ''
  by_id = space_name_by_id value
  return by_id if by_id
  return value if spaces_mod.get_space_by_name value
  value

-- A preset scope is stored with LOCAL ids: 'widget:<page id>:<widget id>' or
-- 'space:<space id>' (core/spaces.moon:118-119, core/view_presets.moon:2-5).
-- A package carries the same scope with NAMES, 'widget:<page name>:<widget id>'
-- or 'space:<space name>', so that it stays valid on another installation; the
-- page name may itself contain a colon, the widget id never does
-- (core/widget_ids.moon:23-24). An id that resolves to nothing is kept as
-- stored, like resolve_space_name above.
preset_scope_portable = (scope) ->
  return scope unless type(scope) == 'string'
  page_id, widget_id = scope\match '^widget:([^:]+):(.+)$'
  if page_id
    page_name = page_name_by_id page_id
    return "widget:#{page_name or page_id}:#{widget_id}"
  space_id = scope\match '^space:(.+)$'
  return scope unless space_id
  "space:#{resolve_space_name space_id}"

-- Inverse of preset_scope_portable: a named page or space is resolved to its
-- local id, and nil means the target does not exist locally. A scope with
-- neither prefix is opaque and returned unchanged.
preset_scope_local = (scope) ->
  return scope unless type(scope) == 'string'
  page_name, widget_id = scope\match '^widget:(.*):([^:]+)$'
  if page_name
    page_id = page_id_by_name page_name
    return page_id and "widget:#{page_id}:#{widget_id}" or nil
  space_name = scope\match '^space:(.+)$'
  return scope unless space_name
  sp = spaces_mod.get_space_by_name space_name
  sp and "space:#{sp.id}" or nil

-- True when a preset row's target (page or owning space) no longer exists.
-- Such a row cannot be exported: preset_scope_portable would keep its raw local
-- id and app_apply._preset_scope would refuse the whole package ("unknown
-- page"). Deleting a page or a space cascades (core/view_presets
-- delete_presets_for_page, core/spaces delete_user_space); this guard covers
-- the rows written before that cascade existed.
preset_row_orphan = (row) ->
  return true unless row[3] and space_name_by_id row[3]
  scope = row[2]
  page_id = type(scope) == 'string' and scope\match '^widget:([^:]+):(.+)$'
  if page_id
    return box.space._tdb_custom_views\get(page_id) == nil
  false

-- A preset sort is a JSON array of {column, ascending} entries
-- (core/view_presets.validate_sort) and is packaged as a table, so that `[]`
-- and an absent sort share one fingerprint.
preset_sort = (value) ->
  return {} if value == nil or value == ''
  decode_config value

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
-- yields one fingerprint. Exception: triggerFields, whose ABSENCE is part of
-- the reality (see field_content below).
-- ────────────────────────────────────────────────────────────────────────────

space_content = (sp) ->
  { description: sp.description or '' }

-- Named row from core/spaces.list_fields (core/spaces.moon:422-447). No
-- position: package order follows creation order (list_fields is sorted by the
-- position).
-- triggerFields semantics (T3b): an ABSENT key (nil) means "no trigger" (a
-- column computed at read time, or a plain field); a table — even an empty one —
-- means a trigger formula ({} = on creation only). list_fields returns nil for
-- a stored "null" (or for a tuple without column 9), so the absence is
-- preserved instead of being turned back into a create-only trigger.
field_content = (f) ->
  content = {
    fieldType: f.fieldType
    notNull: f.notNull == true
    description: f.description or ''
    formula: f.formula or ''
    language: f.language or 'lua'
  }
  content.triggerFields = f.triggerFields if f.triggerFields != nil
  content

-- Declared cardinality of a relation: 'many' only when explicitly declared,
-- 'one' otherwise (missing or empty column 8, or an older package without the
-- key). Mirrors schema_resolvers.normalize_cardinality
-- (resolvers/schema_resolvers.moon:36-42) and triggers.build_relation_map
-- (`t[8] or 'one'`, core/triggers.moon:227).
relation_cardinality = (value) ->
  return 'many' if value == 'many'
  'one'

relation_content = (from_space, from_field, to_space, to_field, cardinality) ->
  {
    fromSpace: from_space
    fromField: from_field
    toSpace: to_space
    toField: to_field
    cardinality: relation_cardinality cardinality
  }

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

-- Row of _tdb_view_presets (core/spaces.moon:121-135): scope and space are
-- stored as local ids and delivered as names (preset_scope_portable), the sort
-- as a table (preset_sort).
preset_content = (row) ->
  {
    scope: preset_scope_portable row[2]
    space: resolve_space_name row[3]
    name: row[4]
    filter: row[5] or ''
    sort: preset_sort row[6]
  }

-- Row of _tdb_widget_plugins (export_resolvers.moon:177-187).
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
-- Reading-boundary normalization (task T22)
-- `yaml.decode` turns YAML null/`~` into box.NULL, a cdata that is TRUE in Lua
-- (`c.description or ''` then yields box.NULL). These helpers bring a decoded
-- package item to exactly the shape produced by the *_content builders above,
-- so that fingerprint(delivered) == fingerprint(identical local state).
-- ────────────────────────────────────────────────────────────────────────────

-- Recursively drops box.NULL: object keys holding it disappear, array elements
-- holding it are filtered out. Other cdata and every scalar are left untouched.
strip_null = (value) ->
  return nil if value == box.NULL
  return value unless type(value) == 'table'
  result = {}
  len = array_len value
  if len != nil
    for i = 1, len
      v = strip_null value[i]
      table.insert result, v if v != nil
  else
    for k, v in pairs value
      sv = strip_null v
      result[k] = sv if sv != nil
  result

-- Per-type defaults: mirrors the *_content builders above, one for one. The
-- builders are the reference; these functions deliberately reproduce them.
-- A parser reports an absent or empty value as nil or as ''; both must fall
-- back to the builder default (a plain `or` would keep the empty string).
_nonempty_or = (value, default) ->
  return default if value == nil or value == ''
  value

_table_or_empty = (value) ->
  (type(value) == 'table') and value or {}

_normalize_space_content = (c) -> { description: c.description or '' }

_normalize_field_content = (c) ->
  content = {
    fieldType: c.fieldType
    notNull: c.notNull == true
    description: c.description or ''
    formula: c.formula or ''
    language: _nonempty_or c.language, 'lua'
  }
  -- triggerFields: an absent (or null, already stripped) key stays absent —
  -- "no trigger"; only a table (even an empty one) is a trigger formula. A
  -- non-table value is dropped rather than silently promoted to `{}` (which
  -- would mean "trigger on creation").
  content.triggerFields = c.triggerFields if type(c.triggerFields) == 'table'
  content

_normalize_relation_content = (c) ->
  {
    fromSpace: c.fromSpace
    fromField: c.fromField
    toSpace: c.toSpace
    toField: c.toField
    cardinality: relation_cardinality c.cardinality
  }

_normalize_view_content = (c) ->
  { space: c.space, name: c.name, viewType: c.viewType, config: decode_config c.config }

_normalize_page_content = (c) ->
  { name: c.name, description: c.description or '', yaml: c.yaml or '' }

_normalize_dataview_content = (c) ->
  {
    name: c.name
    description: c.description or ''
    sourceSpace: resolve_space_name c.sourceSpace
    config: decode_config c.config
  }

-- preset_scope_portable and resolve_space_name are idempotent on an already
-- portable scope/space name, so a decoded package item lands on exactly the
-- shape built by preset_content.
_normalize_preset_content = (c) ->
  {
    scope: preset_scope_portable c.scope
    space: resolve_space_name c.space
    name: c.name
    filter: c.filter or ''
    sort: preset_sort c.sort
  }

_normalize_plugin_content = (c) ->
  {
    name: c.name
    description: c.description or ''
    scriptLanguage: _nonempty_or c.scriptLanguage, 'coffeescript'
    templateLanguage: _nonempty_or c.templateLanguage, 'pug'
    scriptCode: c.scriptCode or ''
    templateCode: c.templateCode or ''
  }

_normalize_group_content = (c) ->
  { name: c.name, description: c.description or '' }

_normalize_perm_content = (c) ->
  {
    group: c.group
    resourceType: c.resourceType
    resource: resource_name c.resource
    level: c.level
  }

_normalize_seed_content = (c) ->
  { space: c.space, key: c.key, data: _table_or_empty c.data }

CONTENT_NORMALIZERS = {
  space: _normalize_space_content
  field: _normalize_field_content
  relation: _normalize_relation_content
  view: _normalize_view_content
  page: _normalize_page_content
  dataview: _normalize_dataview_content
  preset: _normalize_preset_content
  plugin: _normalize_plugin_content
  group: _normalize_group_content
  perm: _normalize_perm_content
  seed: _normalize_seed_content
}

-- Canonical shape of a decoded package item content, by type. Unknown types and
-- non-table contents are returned unchanged. Never mutates its argument;
-- applying it twice gives the same result (idempotent).
normalize_content = (item_type, content) ->
  return content unless type(content) == 'table'
  normalizer = CONTENT_NORMALIZERS[item_type]
  return content unless normalizer
  normalizer content

-- ────────────────────────────────────────────────────────────────────────────
-- Key parsing
-- ────────────────────────────────────────────────────────────────────────────

strip_prefix = (key, prefix) ->
  return nil unless type(key) == 'string' and key\sub(1, #prefix) == prefix
  rest = key\sub(#prefix + 1)
  return nil if rest == ''
  rest

-- Percent-encode one component of a key so that no unescaped key delimiter ('.',
-- '|', ':', '%') remains inside it: '%' first, then '.', '|', ':'. A component
-- without any special character is returned unchanged. Keys are otherwise
-- opaque; only these two functions decide how components are embedded.
key_part = (s) ->
  s = "#{s}"
  s = s\gsub '%%', '%%25'
  s = s\gsub '%.', '%%2E'
  s = s\gsub '%|', '%%7C'
  s = s\gsub ':', '%%3A'
  s

-- Inverse of key_part. Decoding runs in the reverse order so that a literal
-- '%2E' in a name survives the round-trip ('%' → '%25' on encode).
unkey_part = (s) ->
  s = "#{s}"
  s = s\gsub '%%3A', ':'
  s = s\gsub '%%7C', '|'
  s = s\gsub '%%2E', '.'
  s = s\gsub '%%25', '%%'
  s

-- '<scope>.<name>' split on the last dot (a scope may contain dots). Both
-- components are decoded back to their original names.
split_scope_name = (rest) ->
  scope, name = rest\match '^(.*)%.([^%.]+)$'
  return nil unless scope and name and scope != ''
  unkey_part(scope), unkey_part(name)

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
      key: "space:#{key_part sp.name}"
      content: space_content(sp)
    }
    for f in *spaces_mod.list_fields sp.id
      table.insert field_bucket, {
        type: ITEM_TYPES.field
        key: "field:#{key_part sp.name}.#{key_part f.name}"
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
      key = "relation:#{key_part from_sp}.#{key_part from_fld}"
      continue if seen_keys[key]
      seen_keys[key] = true
      table.insert bucket, {
        type: ITEM_TYPES.relation
        key: key
        content: relation_content(from_sp, from_fld, to_sp, to_fld, t[8])
      }

collect_views = (bucket, space_list) ->
  for sp in *space_list
    for v in *views_mod.list_views sp.id
      table.insert bucket, {
        type: ITEM_TYPES.view
        key: "view:#{key_part sp.name}.#{key_part v.name}"
        content: view_content(sp.name, v)
      }

collect_pages = (bucket) ->
  for row in *box.space._tdb_custom_views\select {}
    table.insert bucket, {
      type: ITEM_TYPES.page
      key: "page:#{key_part row[2]}"
      content: page_content(row)
    }

collect_dataviews = (bucket) ->
  for row in *box.space._tdb_data_views\select {}
    table.insert bucket, {
      type: ITEM_TYPES.dataview
      key: "dataview:#{key_part row[2]}"
      content: dataview_content(row)
    }

-- Key: 'preset:<portable scope>|<name>', both components escaped by key_part
-- (the scope keeps its ':' separators inside ONE component, like a perm
-- resource name). The scope names its page or space, never an id.
--
-- A preset left behind by an older database (no cascade on page deletion, see
-- core.view_presets.delete_presets_for_page) or pointing at a deleted space is
-- skipped: preset_scope_portable can only keep its raw id and the import side
-- (app_apply._preset_scope) refuses the whole package with "unknown page".
collect_presets = (bucket) ->
  for row in *box.space._tdb_view_presets\select {}
    continue if preset_row_orphan row
    scope = preset_scope_portable row[2]
    table.insert bucket, {
      type: ITEM_TYPES.preset
      key: "preset:#{key_part scope}|#{key_part row[4]}"
      content: preset_content(row)
    }

collect_plugins = (bucket) ->
  for row in *box.space._tdb_widget_plugins\select {}
    table.insert bucket, {
      type: ITEM_TYPES.plugin
      key: "plugin:#{key_part row[2]}"
      content: plugin_content(row)
    }

collect_groups_and_perms = (group_bucket, perm_bucket) ->
  seen_perms = {}
  for g in *perms_mod.list_groups!
    continue if BUILTIN_GROUPS[g.name]
    table.insert group_bucket, {
      type: ITEM_TYPES.group
      key: "group:#{key_part g.name}"
      content: group_content(g)
    }
    for p in *perms_mod.list_permissions g.id
      key = "perm:#{key_part g.name}|#{key_part p.resourceType}|#{key_part(resource_name p.resourceId)}|#{key_part p.level}"
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
        key: "seed:#{key_part space_name}|#{key_part v}"
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

-- A preset row is keyed by its LOCAL scope (by_scope_name): the portable scope
-- of the package key is resolved back first. nil = page or space missing.
find_preset_row = (scope, name) ->
  local_scope = preset_scope_local scope
  return nil unless local_scope
  box.space._tdb_view_presets.index.by_scope_name\get { local_scope, name }

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
  name = unkey_part name
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
    return relation_content(from_name, from_fld, to_sp, to_fld, t[8])
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
  row = find_page_row unkey_part name
  return nil unless row
  page_content row

describe_dataview = (key) ->
  name = strip_prefix key, 'dataview:'
  return nil unless name
  row = find_dataview_row unkey_part name
  return nil unless row
  dataview_content row

-- Key form: 'preset:<portable scope>|<portable name>' (collect_presets).
describe_preset = (key) ->
  rest = strip_prefix key, 'preset:'
  return nil unless rest
  idx = rest\find '|'
  return nil unless idx
  scope = unkey_part rest\sub(1, idx - 1)
  name = unkey_part rest\sub(idx + 1)
  row = find_preset_row scope, name
  return nil unless row
  preset_content row

describe_plugin = (key) ->
  name = strip_prefix key, 'plugin:'
  return nil unless name
  row = find_plugin_row unkey_part name
  return nil unless row
  plugin_content row

describe_group = (key) ->
  name = strip_prefix key, 'group:'
  return nil unless name
  g = find_group unkey_part name
  return nil unless g
  group_content g

describe_perm = (key) ->
  rest = strip_prefix key, 'perm:'
  return nil unless rest
  parts = split_pipes rest
  return nil unless #parts == 4
  group_name = unkey_part parts[1]
  rtype = unkey_part parts[2]
  res = unkey_part parts[3]
  lvl = unkey_part parts[4]
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
  space_name = unkey_part rest\sub(1, idx - 1)
  raw_key = unkey_part rest\sub(idx + 1)
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
  preset: describe_preset
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

-- ────────────────────────────────────────────────────────────────────────────
-- Seed configuration validation (task F1)
-- The whole export is all-or-nothing: an unknown space, an unknown key field,
-- a required key field left empty on some row, or two rows sharing one key
-- value must refuse the package instead of silently dropping seed rows.
-- A row missing an *optional* key field is a local non-seed row and stays out
-- of the package (tests/test_app_lifecycle_parts.moon:306-334 requires this).
-- ────────────────────────────────────────────────────────────────────────────

seed_rows_error = (space_name, key_field, key_required) ->
  user_sp = box.space["data_#{space_name}"]
  return unless user_sp
  missing = 0
  seen = {}
  duplicate = nil
  for t in *user_sp\select {}
    v = stable_key decode_record(t[2])[key_field]
    if v == nil
      missing += 1 if key_required
    else
      sk = tostring v
      duplicate = sk if duplicate == nil and seen[sk] != nil
      seen[sk] = true
  error "#{missing} seed row(s) in space '#{space_name}' have no value for key field '#{key_field}'" if missing > 0
  error "duplicate seed key '#{duplicate}' in space '#{space_name}' for field '#{key_field}'" if duplicate

validate_seed_entry = (space_ref, key_field) ->
  space_name = resolve_space_name space_ref
  sp = nil
  sp = spaces_mod.get_space_by_name space_name if space_name and space_name != ''
  error "unknown seed space '#{space_ref}'" unless sp
  field = find_field space_name, key_field
  error "unknown field '#{key_field}' in seed space '#{space_name}'" unless field
  seed_rows_error space_name, key_field, field.notNull == true
  space_name

validate_seed_config = (seed_opts) ->
  seed_keys = {}
  for space_ref, key_field in pairs(seed_opts or {})
    seed_keys[validate_seed_entry space_ref, key_field] = key_field
  seed_keys

-- meta: { id, name, version, description }
-- opts.seed: { [space name or id] = natural key field }, optional.
-- Returns { app, items = { {type, key, content} … }, seed_keys }.
build_package = (meta, opts) ->
  opts = opts or {}
  buckets = {}
  for t in *TYPE_ORDER
    buckets[t] = {}

  seed_keys = validate_seed_config opts.seed

  space_list = sorted_spaces!
  collect_spaces_and_fields buckets.space, buckets.field, space_list
  collect_relations buckets.relation, space_list
  collect_views buckets.view, space_list
  collect_pages buckets.page
  collect_dataviews buckets.dataview
  collect_presets buckets.preset
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

{ :canonical, :fingerprint, :describe_local, :build_package, :ITEM_TYPES, :key_part, :unkey_part, :strip_null, :normalize_content, :preset_scope_portable, :preset_scope_local, :preset_row_orphan }
