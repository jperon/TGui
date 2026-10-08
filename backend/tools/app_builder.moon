-- tools/app_builder.moon — structure YAML compacte → paquet .tdbapp.yaml.
-- N'utilise aucun module qui exige box (exécutable par `tarantool -e` hors serveur).
json = require 'json'
yaml = require 'yaml'
fio  = require 'fio'

-- Copie de core.app_package.key_part (testé identique) : ce module ne doit pas
-- charger core.app_package, qui dépend de box.
key_part = (s) ->
  s = "#{s}"
  s = s\gsub '%%', '%%25'
  s = s\gsub '%.', '%%2E'
  s = s\gsub '%|', '%%7C'
  s = s\gsub ':', '%%3A'
  s

_formula = (f) ->
  return '' unless f and f != ''
  f = f\gsub '\n+$', ''
  return f unless f\find '\n', 1, true
  -- `f .. "\n"` avec `(.-)\n` : chaque ligne réelle est agrafée par son `\n`
  -- terminant. Un `gmatch '[^\n]*'` produisait en LuaJIT des lignes vides
  -- parasites (une au niveau de chaque `\n`, plus une en fin de chaîne).
  lines = {}
  for l in (f .. "\n")\gmatch '(.-)\n'
    table.insert lines, '  ' .. l
  "\n" .. table.concat lines, '\n'

_field_item = (space, f) ->
  language = f.language or (f.formula and 'moonscript' or 'lua')
  {
    type: 'field'
    key: "field:#{key_part space}.#{key_part f.name}"
    content: {
      fieldType: f.type, notNull: f.notNull == true
      description: f.description or '', formula: _formula f.formula
      triggerFields: {}, language: language
    }
  }

_relation_item = (space, f) ->
  to_space, to_field = f.ref\match '^([^.]+)%.(.+)$'
  {
    type: 'relation'
    key: "relation:#{key_part space}.#{key_part f.name}"
    content: {
      fromSpace: space, fromField: f.name, toSpace: to_space
      toField: to_field, cardinality: 'one'
    }
  }

_all_fields = (sp) ->
  fields = { { name: 'id', type: 'Sequence', notNull: true, description: 'Identifiant' } }
  table.insert fields, f for f in *(sp.fields or {})
  fields

expand = (structure) ->
  a = structure.app
  spaces, fields, rels, seed_keys = {}, {}, {}, {}
  for sp in *structure.spaces
    table.insert spaces, { type: 'space', key: "space:#{key_part sp.name}", content: { description: sp.description or '' } }
    seed_keys[sp.name] = 'id'
    for f in *_all_fields sp
      table.insert fields, _field_item sp.name, f
      table.insert rels, _relation_item sp.name, f if f.ref
  items = {}
  for group in *{ spaces, fields, rels }
    table.insert items, it for it in *group
  { app: { id: a.id, name: a.name, version: a.version, description: a.description or '' }, items: items, seed_keys: seed_keys }

add_seed = (pkg, space_name, rows) ->
  for row in *rows
    k = tostring row.id
    table.insert pkg.items, {
      type: 'seed', key: "seed:#{key_part space_name}|#{key_part k}"
      content: { space: space_name, key: k, data: row }
    }

-- ── Émetteur YAML (clés triées, scalaires JSON-quotés = YAML valide) ────────────
_scalar = (v) ->
  switch type v
    when 'string' then json.encode v
    when 'number', 'boolean' then tostring v
    else 'null'

_is_array = (t) -> #t > 0 or next(t) == nil

_key = (k) ->
  k = tostring k
  k\match('^[%w_]+$') and k or json.encode(k)

_lines = nil
_lines = (v, pad) ->
  out = {}
  if _is_array v
    for item in *v
      if type(item) == 'table' and next(item) != nil
        sub = _lines item, pad .. '  '
        sub[1] = pad .. '- ' .. sub[1]\sub(#pad + 3)
        table.insert out, l for l in *sub
      else
        table.insert out, pad .. '- ' .. (type(item) == 'table' and (_is_array(item) and '[]' or '{}') or _scalar item)
  else
    keys = [k for k, _ in pairs v]
    table.sort keys, (a, b) -> tostring(a) < tostring(b)
    for k in *keys
      val = v[k]
      if type(val) == 'table' and next(val) != nil
        table.insert out, pad .. _key(k) .. ':'
        table.insert out, l for l in *_lines val, pad .. '  '
      elseif type(val) == 'table'
        table.insert out, pad .. _key(k) .. ': ' .. (_is_array(val) and '[]' or '{}')
      else
        table.insert out, pad .. _key(k) .. ': ' .. _scalar val
  out

emit = (pkg) ->
  "---\n" .. table.concat(_lines(pkg, ''), '\n') .. '\n'

_read_yaml = (path) ->
  fh = fio.open path, { 'O_RDONLY' }
  error "cannot open #{path}" unless fh
  text = fh\read!
  fh\close!
  yaml.decode text

load_structure = (dir) ->
  structure = { app: (_read_yaml fio.pathjoin dir, 'app.yaml').app, spaces: {} }
  names = fio.glob fio.pathjoin dir, 'structure', '*.yaml'
  table.sort names
  for path in *names
    for sp in *(_read_yaml path).spaces
      table.insert structure.spaces, sp
  structure

{ :key_part, :expand, :add_seed, :emit, :load_structure }
