-- core/triggers.moon
-- Manages Tarantool before_replace triggers for trigger formula fields.
-- Trigger formulas are stored computed columns: the formula runs at write time
-- (on INSERT and/or when specific fields change) and the result is stored in the document.
--
-- Triggers are NOT persisted across Tarantool restarts. init_all_triggers() re-registers
-- them at startup from _tdb_fields metadata.

json       = require 'json'
log        = require 'log'
spaces_mod = require 'core.spaces'

-- Maps space_name -> currently registered before_replace function (for later removal).
active_triggers = {}

-- ── Formula compilation ───────────────────────────────────────────────────────

-- Compile a formula string into a Lua function(self, space).
-- Returns the compiled function, or nil + logs an error on failure.
compile_formula = (formula, field_name) ->
  fn_str = "return function(self, space) return " .. formula .. " end"
  ok, compiled = pcall load, fn_str
  if not ok or type(compiled) != 'function'
    log.error "tdb triggers: parse error for field '#{field_name}': #{compiled}"
    return nil
  ok2, fn = pcall compiled
  if not ok2 or type(fn) != 'function'
    log.error "tdb triggers: init error for field '#{field_name}': #{fn}"
    return nil
  fn

-- ── Self proxy ────────────────────────────────────────────────────────────────

-- Build a self proxy that resolves FK fields lazily.
-- fk_def_map: { field_name => { toSpaceName, toFieldName } }
make_self_proxy = (record, fk_def_map) ->
  decode_tuple = (t) ->
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    d._id = tostring t[1]
    d
  proxy = {}
  setmetatable proxy,
    __index: (t, k) ->
      cached = rawget t, k
      return cached if cached != nil
      v = record[k]
      return nil if v == nil
      fk = fk_def_map and fk_def_map[k]
      if fk
        tb = box.space["data_#{fk.toSpaceName}"]
        if tb
          for tup in *tb\select {}
            d = decode_tuple tup
            if tostring(d[fk.toFieldName]) == tostring(v)
              rawset t, k, d
              return d
        return nil
      v
  proxy

-- ── Trigger condition check ───────────────────────────────────────────────────

-- Returns true if the trigger formula should run given old/new data and the
-- field's triggerFields configuration.
should_run = (is_insert, trigger_fields_list, old_data, new_data) ->
  return true if is_insert
  return false if #trigger_fields_list == 0    -- create-only
  return true  if trigger_fields_list[1] == '*' -- any change
  for _, fname in ipairs trigger_fields_list
    if tostring(old_data[fname] or '') != tostring(new_data[fname] or '')
      return true
  false

-- ── Space helper for formulas ─────────────────────────────────────────────────

make_space_helper = ->
  decode_tuple = (t) ->
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    d._id = tostring t[1]
    d
  (sname) ->
    sp = box.space["data_#{sname}"]
    return {} unless sp
    [decode_tuple t for t in *sp\select {}]

-- ── Trigger function builder ──────────────────────────────────────────────────

-- Builds the before_replace function for a given space.
-- trigger_defs: list of { field_name, fn, trigger_fields_list, fk_def_map }
make_trigger_fn = (trigger_defs) ->
  space_helper = make_space_helper!
  (old_tuple, new_tuple) ->
    -- On DELETE new_tuple is nil: nothing to compute, just pass through
    return nil if new_tuple == nil
    is_insert = (old_tuple == nil)
    old_data  = if is_insert then {} else
      d = if type(old_tuple[2]) == 'string' then json.decode(old_tuple[2]) else old_tuple[2]
      d
    new_data  = if type(new_tuple[2]) == 'string' then json.decode(new_tuple[2]) else new_tuple[2]
    modified  = false
    for def in *trigger_defs
      if should_run is_insert, def.trigger_fields_list, old_data, new_data
        proxy = make_self_proxy new_data, def.fk_def_map
        r_ok, val = pcall def.fn, proxy, space_helper
        if r_ok
          new_data[def.field_name] = val
          modified = true
        else
          log.error "tdb trigger: error evaluating formula for '#{def.field_name}': #{val}"
    if modified
      box.tuple.new { new_tuple[1], json.encode(new_data) }
    else
      new_tuple

-- ── FK def map builder ────────────────────────────────────────────────────────

-- Build { field_name => { toSpaceName, toFieldName } } for a space's FK fields.
build_fk_def_map = (space_id) ->
  rels = {}
  for t in *box.space._tdb_relations\select {}
    if t[2] == space_id
      rels[t[3]] = { toSpaceId: t[4], toFieldId: t[5] }
  -- Resolve space names and field names
  fk_def_map = {}
  space_by_id = {}
  for t in *box.space._tdb_spaces\select {}
    space_by_id[t[1]] = { name: t[2] }
  field_by_id = {}
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    field_by_id[t[1]] = { name: t[3] }
  -- Also need field names from other spaces for toFieldId
  for _, rel in pairs rels
    tf = box.space._tdb_fields\get rel.toFieldId
    field_by_id[rel.toFieldId] = { name: tf and tf[3] or 'id' }
  for field_id, rel in pairs rels
    fld = box.space._tdb_fields\get field_id
    sp  = space_by_id[rel.toSpaceId]
    if fld and sp
      fk_def_map[fld[3]] =
        toSpaceName: sp.name
        toFieldName: (field_by_id[rel.toFieldId] and field_by_id[rel.toFieldId].name) or 'id'
  fk_def_map

-- ── Public API ────────────────────────────────────────────────────────────────

-- Register (or re-register) the before_replace trigger for a space.
-- Reads trigger formula fields from _tdb_fields for this space.
register_space_trigger = (space_name) ->
  -- Find space id
  sp_meta = box.space._tdb_spaces.index.by_name\get { space_name }
  return unless sp_meta
  space_id = sp_meta[1]

  -- Drop existing trigger if any
  old_fn = active_triggers[space_name]
  if old_fn
    ok, err = pcall -> box.space["data_#{space_name}"]\before_replace nil, old_fn
    log.error "tdb triggers: failed to drop trigger for #{space_name}: #{err}" unless ok
    active_triggers[space_name] = nil

  -- Collect trigger formula fields
  trigger_defs = {}
  fk_def_map   = nil  -- lazy-built once if needed
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    formula       = t[8]
    trigger_json  = t[9]
    if formula and formula != '' and trigger_json != nil
      ok, trigger_fields_list = pcall json.decode, trigger_json
      unless ok
        log.error "tdb triggers: invalid JSON in trigger_fields for field '#{t[3]}': #{trigger_fields_list}"
        continue
      fk_def_map = build_fk_def_map(space_id) unless fk_def_map
      fn = compile_formula formula, t[3]
      if fn
        table.insert trigger_defs, {
          field_name:          t[3]
          fn:                  fn
          trigger_fields_list: trigger_fields_list
          fk_def_map:          fk_def_map
        }

  return if #trigger_defs == 0

  -- Register combined trigger
  data_sp = box.space["data_#{space_name}"]
  return unless data_sp
  trigger_fn = make_trigger_fn trigger_defs
  data_sp\before_replace trigger_fn
  active_triggers[space_name] = trigger_fn
  log.info "tdb triggers: registered #{#trigger_defs} trigger formula(s) on '#{space_name}'"

-- Re-register triggers for all spaces that have at least one trigger formula field.
init_all_triggers = ->
  for t in *box.space._tdb_spaces\select {}
    register_space_trigger t[2]

{ :register_space_trigger, :init_all_triggers }
