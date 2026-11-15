-- core/view_presets.moon
-- Summary: CRUD for named view presets (a MoonScript filter plus a sort order)
-- attached to a widget of a page or to the main grid of a space.
-- Inputs/outputs:
-- - Input : scope key, space id, preset name, filter formula, sort JSON.
-- - Output: persisted presets in _tdb_view_presets as
--   {id, scope, spaceId, name, filter, sort, createdAt, updatedAt}.
-- Used by: resolvers/view_preset_resolvers, core/spaces (cascade delete).
uuid = require 'uuid'
json = require 'json'

trim = (s) ->
  tostring(s or '')\match '^%s*(.-)%s*$'

tuple_to_preset = (t) ->
  return nil unless t
  {
    id: t[1]
    scope: t[2]
    spaceId: t[3]
    name: t[4]
    filter: t[5] or ''
    sort: t[6] or '[]'
    createdAt: t[7]
    updatedAt: t[8]
  }

get_preset = (id) ->
  return nil unless id
  tuple_to_preset box.space._tdb_view_presets\get { id }

-- Presets of one scope, sorted by name: index by_scope_name is {scope, name},
-- so its range scan already returns the rows ordered by name.
list_presets = (scope) ->
  result = {}
  return result unless scope and scope != ''
  for t in *box.space._tdb_view_presets.index.by_scope_name\select { scope }
    table.insert result, tuple_to_preset t
  result

-- A sort is a JSON array of {column: String, ascending: Boolean} entries.
-- Returns the JSON text to store, unchanged once validated.
validate_sort = (sort_json) ->
  raw = if sort_json == nil or sort_json == '' then '[]' else tostring(sort_json)
  ok, decoded = pcall json.decode, raw
  error "Invalid sort JSON: #{decoded}" unless ok
  error "Invalid sort JSON: expected an array of sort entries" unless type(decoded) == 'table'
  for key in pairs decoded
    error "Invalid sort JSON: expected an array of sort entries" unless type(key) == 'number'
  for entry in *decoded
    error "Invalid sort entry: expected an object with column and ascending" unless type(entry) == 'table'
    error "Invalid sort entry: column must be a string" unless type(entry.column) == 'string'
    error "Invalid sort entry: ascending must be a boolean" unless type(entry.ascending) == 'boolean'
  raw

-- Create a preset, or overwrite the one already stored under (scope, name):
-- "save as" on an existing name replaces its filter and sort. A preset never
-- changes space: its permissions were granted for the space that owns it.
save_preset = (scope, space_id, name, filter, sort) ->
  scope = tostring(scope or '')
  error "Preset scope cannot be empty" unless scope\match '%S'

  clean_name = trim name
  error "Preset name cannot be empty" if clean_name == ''

  space_id = tostring(space_id or '')
  error "Preset space cannot be empty" if space_id == ''
  error "Space not found: #{space_id}" unless box.space._tdb_spaces\get { space_id }

  filter_src = tostring(filter or '')
  sort_json = validate_sort sort
  now = os.time!

  existing = box.space._tdb_view_presets.index.by_scope_name\get { scope, clean_name }
  if existing
    -- The caller proved 'write' on the NEW space only: re-attaching an existing
    -- preset to it would hijack a preset owned by another space.
    if existing[3] != space_id
      error "Preset '#{clean_name}' belongs to another space"
    box.space._tdb_view_presets\update existing[1], {
      { '=', 5, filter_src }
      { '=', 6, sort_json }
      { '=', 8, now }
    }
    return get_preset existing[1]

  preset_id = tostring uuid.new!
  box.space._tdb_view_presets\insert {
    preset_id, scope, space_id, clean_name, filter_src, sort_json, now, now
  }
  get_preset preset_id

delete_preset = (id) ->
  t = box.space._tdb_view_presets\get { id }
  return false unless t
  box.space._tdb_view_presets\delete { id }
  true

{ :list_presets, :get_preset, :save_preset, :delete_preset, :validate_sort }
