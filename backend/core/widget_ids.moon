-- core/widget_ids.moon
-- Summary: guarantees that every widget of a custom-view (page) YAML document
-- carries a stable `id`, formatted `w_` followed by 8 hexadecimal characters.
-- Why: the widget id is the key of widget-scoped records — a named view preset
-- is stored under the scope 'widget:<pageId>:<widgetId>' (core/view_presets).
-- A missing or unstable id silently detaches those records, so the invariant is
-- enforced at the storage boundary instead of at each write site of
-- _tdb_custom_views (14 of them in resolvers/ and core/app_apply.moon).
-- How:
-- - ensure_widget_ids/1 rewrites the YAML text in place: the `id:` line is
--   inserted right after the `- widget:` header, under the indentation of the
--   widget's first child key. Hand-written comments, key order and formatting
--   are left untouched; a full yaml.encode is only used when the textual patch
--   cannot be verified by decoding the result.
-- - A before_replace trigger on _tdb_custom_views normalizes every insert,
--   replace and update. Tarantool does not persist triggers, so install_trigger
--   is called at bootstrap on each start.
-- - migrate_stored_pages rewrites the pages stored before this module existed.
-- Used by: core/spaces (bootstrap and migrate), tests/test_widget_ids.

yaml = require 'yaml'

ID_PREFIX = 'w_'
ID_HEX_DIGITS = 8

-- ────────────────────────────────────────────────────────────────────────────
-- Id generation
-- ────────────────────────────────────────────────────────────────────────────

random_id = ->
  digits = {}
  for _ = 1, ID_HEX_DIGITS
    table.insert digits, string.format('%x', math.random(0, 15))
  ID_PREFIX .. table.concat digits

-- An id has to be unique inside its page only (the scope is page-scoped), so
-- collisions with the ids already present are avoided by retrying.
generate_unique_id = (used) ->
  for _ = 1, 100
    id = random_id!
    return id unless used[id]
  -- Deterministic fallback: never loop forever on a degenerate RNG.
  n = 0
  while true
    id = ID_PREFIX .. string.format('%08x', n)
    return id unless used[id]
    n += 1

-- ────────────────────────────────────────────────────────────────────────────
-- Layout tree
-- ────────────────────────────────────────────────────────────────────────────

-- Collects the widget mappings of a layout tree, in render order. Mirrors
-- CustomView#_collectWidgetNodes (frontend/src/views/custom_view.coffee) and
-- collect_widgets_and_zones (resolvers/custom_view_widgets.moon): a node with
-- `widget` is a leaf; a node wraps its container under `layout` or `zone`, or
-- carries `children` itself. Children of a zone are visited recursively.
collect_widgets = (node, out) ->
  out = {} unless out
  return out unless type(node) == 'table'
  if type(node.widget) == 'table'
    table.insert out, node.widget
    return out
  container = node
  if type(node.layout) == 'table'
    container = node.layout
  elseif type(node.zone) == 'table'
    container = node.zone
  if type(container.widget) == 'table'
    table.insert out, container.widget
  elseif type(container.children) == 'table'
    for _, child in ipairs container.children
      collect_widgets child, out
  out

decode_config = (yaml_str) ->
  return nil unless type(yaml_str) == 'string' and yaml_str != ''
  ok, config = pcall yaml.decode, yaml_str
  return nil unless ok and type(config) == 'table'
  return nil unless type(config.layout) == 'table'
  config

trim = (s) ->
  tostring(s or '')\match '^%s*(.-)%s*$'

-- The old layout encoders wrote `id: tostring(widget.id)`, so a widget saved
-- without an id carries the literal string "nil": a missing id in disguise.
-- An empty id, an explicit null or that placeholder all count as missing.
is_missing_id = (widget) ->
  return true if type(widget) != 'table'
  id = widget.id
  return true if id == nil
  return false unless type(id) == 'string'
  trimmed = trim id
  trimmed == '' or trimmed == 'nil'

-- ────────────────────────────────────────────────────────────────────────────
-- Textual patch of one widget header
-- ────────────────────────────────────────────────────────────────────────────

-- Splits the text into lines, remembering whether it ended with a newline so
-- that joining restores the exact original bytes.
split_lines = (text) ->
  lines = {}
  for line in (text .. "\n")\gmatch '([^\n]*)\n'
    table.insert lines, line
  trailing = false
  if #lines > 0 and lines[#lines] == '' and text\sub(-1) == "\n"
    table.remove lines
    trailing = true
  { :lines, :trailing }

join_lines = (split) ->
  text = table.concat split.lines, "\n"
  text ..= "\n" if split.trailing
  text

-- Matches a `widget:` mapping key line, with or without the `- ` of a sequence
-- entry, with or without leading indentation.
-- Returns { indent, key_col, rest } — key_col is the column of the `widget` key,
-- children of the widget mapping sit strictly to its right.
match_widget_key = (line) ->
  indent = line\match '^%s*'
  body = line\sub #indent + 1
  key_col = #indent
  dash = body\match '^%-%s+'
  if dash
    key_col += #dash
    body = body\sub #dash + 1
  rest = body\match '^widget%s*:%s*(.*)$'
  return nil unless rest
  { :indent, :key_col, :rest }

-- Indentation of the first significant child line, nil when the mapping is
-- empty (or only holds comments/blank lines).
find_child_indent = (lines, header_idx, key_col) ->
  for j = header_idx + 1, #lines
    raw = lines[j]
    unless (raw\match '^%s*$') or (raw\match '^%s*#')
      ind = #(raw\match '^%s*')
      return ind if ind > key_col
      return nil
  nil

-- First `id:` line of the widget mapping (a child line, deeper than key_col).
find_id_line = (lines, header_idx, key_col) ->
  for j = header_idx + 1, #lines
    raw = lines[j]
    continue if (raw\match '^%s*$') or (raw\match '^%s*#')
    ind = #(raw\match '^%s*')
    break if ind <= key_col
    key, value = raw\match '^%s*([%w_%-%.]+)%s*:%s*(.*)$'
    return { line: j, indent: ind, value: value } if key == 'id'
  nil

-- An id pointing nowhere: empty, quoted-empty, explicit null, the "nil"
-- placeholder written by the old encoders, or commented out.
is_empty_scalar = (raw) ->
  value = trim raw
  return true if value == ''
  return true if value\sub(1, 1) == '#'
  return true if value == "''" or value == '""' or value == '~'
  lowered = value\lower!
  lowered == 'null' or lowered == 'nil'

-- Block style: `- widget:` followed by its keys. Either the existing empty id
-- line is filled in, or a new id line is inserted right after the header.
apply_to_block = (lines, header_idx, key_col, new_id) ->
  found = find_id_line lines, header_idx, key_col
  if found
    return false unless is_empty_scalar found.value
    lines[found.line] = (' ')\rep(found.indent) .. 'id: ' .. new_id
    return true
  child_indent = find_child_indent lines, header_idx, key_col
  child_indent = key_col + 2 unless child_indent
  table.insert lines, header_idx + 1, (' ')\rep(child_indent) .. 'id: ' .. new_id
  true

-- Flow style: `- widget: {title: A}`. The id goes inside the flow mapping; an
-- id already present there is the caller's problem (returns nil → re-encode).
apply_to_flow = (line, new_id) ->
  header = line\find 'widget%s*:%s*{'
  return nil unless header
  open = line\find '{', header
  return nil unless open
  inside = line\sub open + 1
  return nil if inside\match '^%s*id%s*:'
  if inside\match '^%s*}'
    line\sub(1, open) .. 'id: ' .. new_id .. ' ' .. inside
  else
    line\sub(1, open) .. 'id: ' .. new_id .. ', ' .. inside

-- ────────────────────────────────────────────────────────────────────────────
-- Whole-document patch
-- ────────────────────────────────────────────────────────────────────────────

-- Verifies the patched text by decoding it: every widget, in the same order,
-- must carry the id that was intended for it. Catches a misplaced insertion.
text_matches = (text, intended) ->
  ok, config = pcall yaml.decode, text
  return false unless ok and type(config) == 'table'
  widgets = collect_widgets config
  return false unless #widgets == #intended
  for k, widget in ipairs widgets
    return false if is_missing_id widget
    return false unless tostring(widget.id) == intended[k]
  true

-- Returns the patched text, or nil when the textual patch is not possible.
patch_text = (text, intended) ->
  split = split_lines text
  lines = split.lines
  headers = {}
  for idx, raw in ipairs lines
    m = match_widget_key raw
    continue unless m
    head = m.rest\sub 1, 1
    if m.rest == '' or head == '#' or head == '{'
      table.insert headers, { idx: idx, rest: m.rest, key_col: m.key_col }
  return nil unless #headers == #intended
  -- Bottom-up: an inserted line must not shift the headers still to patch.
  for k = #headers, 1, -1
    header = headers[k]
    if header.rest\sub(1, 1) == '{'
      patched = apply_to_flow lines[header.idx], intended[k]
      return nil unless patched
      lines[header.idx] = patched
    else
      return nil unless apply_to_block lines, header.idx, header.key_col, intended[k]
  join_lines split

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

-- Returns `new_yaml, changed`. Empty, invalid, or layout-less documents are
-- returned untouched with changed = false: the write-site validation reports
-- those, this module only fills in ids.
ensure_widget_ids = (yaml_str) ->
  config = decode_config yaml_str
  return yaml_str, false unless config
  widgets = collect_widgets config
  return yaml_str, false if #widgets == 0

  used = {}
  any_missing = false
  for widget in *widgets
    if is_missing_id widget
      any_missing = true
    else
      used[tostring widget.id] = true
  return yaml_str, false unless any_missing

  intended = {}
  for widget in *widgets
    id = if is_missing_id(widget) then generate_unique_id(used) else tostring(widget.id)
    used[id] = true
    widget.id = id
    table.insert intended, id

  patched = patch_text yaml_str, intended
  return patched, true if patched and text_matches(patched, intended)
  -- Textual insertion impossible (or unverified): re-encode the decoded tree.
  yaml.encode(config), true

-- ────────────────────────────────────────────────────────────────────────────
-- Storage boundary
-- ────────────────────────────────────────────────────────────────────────────

-- before_replace callback: normalizes column 4 (yaml) of _tdb_custom_views.
normalize_tuple = (old_tuple, new_tuple) ->
  return nil if new_tuple == nil
  yaml_str = new_tuple[4]
  return new_tuple unless type(yaml_str) == 'string'
  patched, changed = ensure_widget_ids yaml_str
  return new_tuple unless changed
  new_tuple\update { { '=', 4, patched } }

-- Registers the trigger. space:before_replace replaces the previous trigger
-- instead of stacking a new one, so calling this again is harmless.
install_trigger = ->
  sp = box.space._tdb_custom_views
  return false unless sp
  sp\before_replace normalize_tuple
  true

-- Rewrites the pages stored before this module existed. Returns the number of
-- rows changed. A replace goes through the trigger, which re-checks the result.
migrate_stored_pages = ->
  sp = box.space._tdb_custom_views
  return 0 unless sp
  changed = 0
  for t in *sp\select {}
    patched, patched_changed = ensure_widget_ids t[4]
    if patched_changed
      sp\replace { t[1], t[2], t[3], patched, t[5], t[6] }
      changed += 1
  changed

{
  :ensure_widget_ids
  :collect_widgets
  :install_trigger
  :migrate_stored_pages
  :ID_PREFIX
}
