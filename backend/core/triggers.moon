-- core/triggers.moon
-- Manages Tarantool before_replace triggers for trigger formula fields.
-- Trigger formulas are stored computed columns: the formula runs at write time
-- (on INSERT and/or when specific fields change) and the result is stored in the document.
--
-- Triggers are NOT persisted across Tarantool restarts. init_all_triggers() re-registers
-- them at startup from _tdb_fields metadata.
--
-- T14 split: the formula sandbox lives in core.formula_sandbox, the relation
-- maps in core.relation_maps and the formula proxies + cache in
-- core.formula_proxy. This module keeps trigger registration only and
-- re-exports the whole former public API under the same names, so every
-- `require 'core.triggers'` caller keeps working unchanged.

json       = require 'json'
log        = require 'log'
{ :safe_formula_call } = require 'core.config'
{ :compile_formula, :MAX_STRING_REP_BYTES } = require 'core.formula_sandbox'
{ :build_fk_def_map, :build_relation_map, :build_single_and_multiple_maps } = require 'core.relation_maps'
{ :make_self_proxy, :make_self_proxy_extended, :make_space_helper, :format_formula_error, :invalidate_formula_cache } = require 'core.formula_proxy'

-- Maps space_name -> currently registered before_replace function (for later removal).
active_triggers = {}

-- ── Trigger registration ───────────────────────────────────────────────────────

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

-- Builds the before_replace function for a given space.
-- trigger_defs: list of { field_name, fn, trigger_fields_list, fk_def_map }
make_trigger_fn = (trigger_defs, space_name) ->
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
        -- fk_cache is passed as nil for triggers (triggers are usually single-record ops),
        -- but space_name is passed to allow proxy to evaluate other computed formulas of the same record.
        proxy = make_self_proxy new_data, def.fk_def_map, nil, space_name
        val, err = safe_formula_call def.fn, "trigger #{space_name}.#{def.field_name}", nil, nil, { proxy, space_helper }
        if err != nil
          log.error "tdb trigger: error evaluating formula for '#{def.field_name}': #{err}"
        else
          new_data[def.field_name] = val
          modified = true
    if modified
      box.tuple.new { new_tuple[1], json.encode(new_data) }
    else
      new_tuple

-- ── Public API ────────────────────────────────────────────────────────────────

-- Register (or re-register) the before_replace trigger for a space.
-- Reads trigger formula fields from _tdb_fields for this space.
register_space_trigger = (space_name) ->
  -- Find space id
  sp_meta = box.space._tdb_spaces.index.by_name\get { space_name }
  return unless sp_meta
  space_id = sp_meta[1]

  -- Drop existing trigger if any (check data space exists to avoid spurious errors)
  old_fn = active_triggers[space_name]
  if old_fn
    data_sp_old = box.space["data_#{space_name}"]
    if data_sp_old
      ok, err = pcall -> data_sp_old\before_replace nil, old_fn
      log.warn "tdb triggers: could not drop trigger for #{space_name}: #{err}" unless ok
    active_triggers[space_name] = nil

  -- Collect trigger formula fields
  trigger_defs = {}
  fk_def_map   = nil  -- lazy-built once if needed
  for t in *box.space._tdb_fields.index.by_space\select { space_id }
    formula      = t[8]
    trigger_json = t[9]
    language     = t[10] or 'lua'
    -- Register trigger only when trigger_json is present and not "null".
    -- Simple formula columns have trigger_json = nil (legacy) or "null" (new format).
    if formula and formula != '' and trigger_json != nil and trigger_json != 'null'
      ok, trigger_fields_list = pcall json.decode, trigger_json
      unless ok
        log.error "tdb triggers: invalid JSON in trigger_fields for field '#{t[3]}': #{trigger_fields_list}"
        continue
      fk_def_map = build_fk_def_map(space_id) unless fk_def_map
      fn = compile_formula formula, t[3], language
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
  trigger_fn = make_trigger_fn trigger_defs, space_name
  data_sp\before_replace trigger_fn
  active_triggers[space_name] = trigger_fn
  log.info "tdb triggers: registered #{#trigger_defs} trigger formula(s) on '#{space_name}'"

-- Re-register triggers for all spaces that have at least one trigger formula field.
init_all_triggers = ->
  for t in *box.space._tdb_spaces\select {}
    register_space_trigger t[2]

-- Deregister trigger for a deleted space (called via package.loaded to avoid circular dep).
-- Clears the active_triggers cache entry so the memory is freed.
deregister_space_trigger = (space_name) ->
  old_fn = active_triggers[space_name]
  return unless old_fn
  data_sp = box.space["data_#{space_name}"]
  if data_sp
    pcall -> data_sp\before_replace nil, old_fn
  active_triggers[space_name] = nil

{ :compile_formula, :make_self_proxy, :make_self_proxy_extended, :build_fk_def_map, :build_relation_map, :build_single_and_multiple_maps, :register_space_trigger, :deregister_space_trigger, :init_all_triggers, :format_formula_error, :invalidate_formula_cache, :MAX_STRING_REP_BYTES }
