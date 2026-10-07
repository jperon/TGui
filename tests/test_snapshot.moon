-- tests/test_snapshot.moon
-- Tests exportSnapshot / diffSnapshot / importSnapshot resolvers.
-- Runs inside Tarantool instance (box already initialized).

R      = require 'tests.runner'
auth   = require 'core.auth'
spaces = require 'core.spaces'
export_r = require 'resolvers.export_resolvers'
data_res = require 'resolvers.data_resolvers'
yaml   = require 'yaml'
json   = require 'json'

SUFFIX = tostring math.random 100000, 999999

-- Fake admin context (uses the real 'admin' user)
admin_user = auth.get_user_by_username 'admin'
ADMIN_CTX  = { user_id: admin_user and admin_user.id }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "exportSnapshot — structure", ->

  R.it "returns a non-empty YAML string", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    R.ok result
    R.ok #result > 10

  R.it "le YAML est parsable", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.ok snap
    R.ok snap.version

  R.it "contient une section schema.spaces", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.ok snap.schema
    R.ok snap.schema.spaces
    R.ok #snap.schema.spaces >= 0

  R.it "ne contient pas de section data en mode structure-seulement", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.eq snap.data, nil

  R.it "contient une section data en mode include_data", ->
    result = export_r.Query.exportSnapshot nil, { includeData: true }, ADMIN_CTX
    snap = yaml.decode result
    R.ok result
    R.ok type(snap.data) == 'table'
    expected_count = #spaces.list_spaces!
    exported_count = 0
    for _k, _v in pairs snap.data
      exported_count += 1
    R.eq exported_count, expected_count

  R.it "contient une section schema.widget_plugins", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.ok snap.schema
    R.ok type(snap.schema.widget_plugins) == 'table'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "diffSnapshot — no difference", ->
  local current_yaml

  R.it "exports current schema", ->
    current_yaml = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    R.ok current_yaml

  R.it "diff on current schema -> no divergence", ->
    diff = export_r.Query.diffSnapshot nil, { yaml: current_yaml }, ADMIN_CTX
    R.ok diff
    R.eq #diff.spacesToCreate,  0
    R.eq #diff.spacesToDelete,  0
    R.eq #diff.fieldsToCreate,  0
    R.eq #diff.fieldsToDelete,  0

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — mode merge", ->
  SP = "snap_test_#{SUFFIX}"

  R.it "creates a minimal YAML snapshot with a new space", ->
    snap = {
      version: "1"
      schema: {
        spaces: {
          {
            name: SP
            fields: {
              { name: "titre", fieldType: "String", notNull: false }
              { name: "valeur", fieldType: "Int", notNull: false }
            }
            views: {}
          }
        }
        relations: {}
        custom_views: {}
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok result
    R.ok result.ok
    R.ok result.created > 0
    R.eq #result.errors, 0

  R.it "imported space is visible in list_spaces", ->
    found = false
    for sp in *spaces.list_spaces!
      if sp.name == SP
        found = true
        break
    R.ok found

  R.it "imported fields are present", ->
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == SP
    R.ok sp
    fields = spaces.list_fields sp.id
    names = [f.name for f in *fields]
    has_titre  = false
    has_valeur = false
    for n in *names
      has_titre  = true if n == 'titre'
      has_valeur = true if n == 'valeur'
    R.ok has_titre
    R.ok has_valeur

  R.it "second identical import -> all skipped, no error", ->
    snap = {
      version: "1"
      schema: {
        spaces: {
          {
            name: SP
            fields: {
              { name: "titre",  fieldType: "String", notNull: false }
              { name: "valeur", fieldType: "Int",    notNull: false }
            }
            views: {}
          }
        }
        relations: {}
        custom_views: {}
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok result
    R.ok result.ok
    R.eq result.created, 0
    R.ok result.skipped > 0
    R.eq #result.errors, 0

  -- Cleanup
  R.it "delete test space", ->
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == SP
    R.ok sp
    spaces.delete_user_space SP   -- expects space name, not id
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP
    R.eq found, false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — widget plugins", ->
  PLUGIN = "snap_plugin_#{SUFFIX}"

  R.it "imports widget plugin definitions from snapshot schema", ->
    snap = {
      version: "1"
      schema: {
        spaces: {}
        relations: {}
        custom_views: {}
        widget_plugins: {
          {
            name: PLUGIN
            description: "plugin from snapshot"
            scriptLanguage: "coffeescript"
            templateLanguage: "pug"
            scriptCode: "module.exports = ({ render }) -> render '<div>ok</div>'"
            templateCode: "div ok"
          }
        }
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok result
    R.ok result.ok
    tuple = box.space._tdb_widget_plugins.index.by_name\get PLUGIN
    R.ok tuple

  R.it "cleanup imported widget plugin", ->
    tuple = box.space._tdb_widget_plugins.index.by_name\get PLUGIN
    box.space._tdb_widget_plugins\delete tuple[1] if tuple

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — mode replace", ->
  SP_A = "replace_a_#{SUFFIX}"
  SP_B = "replace_b_#{SUFFIX}"

  R.it "creates two initial spaces", ->
    for name in *{ SP_A, SP_B }
      ok, err = pcall -> spaces.create_user_space name, ''
      R.ok ok

  R.it "replace mode removes existing spaces and recreates from snapshot", ->
    -- Snapshot containing only SP_B (SP_A will be removed)
    snap = {
      version: "1"
      schema: {
        spaces: {
          { name: SP_B, fields: { { name: "val", fieldType: "String", notNull: false } }, views: {} }
        }
        relations: {}
        custom_views: {}
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'replace' }, ADMIN_CTX
    R.ok result
    R.eq #result.errors, 0

  R.it "SP_B still exists (recreated by replace)", ->
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP_B
    R.ok found

  R.it "SP_B has imported val field", ->
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == SP_B
    R.ok sp
    fields = spaces.list_fields sp.id
    has_val = false
    for f in *fields
      has_val = true if f.name == 'val'
    R.ok has_val

  -- Cleanup
  R.it "cleanup replace_* spaces", ->
    for name in *{ SP_A, SP_B }
      sp = nil
      for s in *spaces.list_spaces!
        sp = s if s.name == name
      spaces.delete_user_space name if sp
    -- Verify both spaces are absent
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP_A or s.name == SP_B
    R.eq found, false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — invalid YAML", ->

  R.it "error on empty YAML", ->
    ok, err = pcall ->
      export_r.Mutation.importSnapshot nil, { yaml: '', mode: 'merge' }, ADMIN_CTX
    R.eq ok, false

  R.it "import with non-table YAML -> error", ->
    ok, err = pcall ->
      export_r.Mutation.importSnapshot nil, { yaml: '42', mode: 'merge' }, ADMIN_CTX
    R.eq ok, false

-- ────────────────────────────────────────────────────────────────────────────
-- Round trip: export with data → delete space → import (merge) → compare.
-- A record is stored as { id, json.encode(data) } (data_resolvers.moon:100),
-- and do_import re-inserts it the same way (export_resolvers.moon, data section).
-- ────────────────────────────────────────────────────────────────────────────
R.describe "round trip export → import (includeData)", ->
  RT = "snap_rt_#{SUFFIX}"
  RT_FIELDS = {
    { name: 'titre',   fieldType: 'String',  notNull: true }
    { name: 'valeur',  fieldType: 'Int',     notNull: false }
    { name: 'prix',    fieldType: 'Float',   notNull: false }
    { name: 'actif',   fieldType: 'Boolean', notNull: false }
  }
  ORIG_ROWS = {
    { titre: 'Alpha', valeur: 1, prix: 1.5,  actif: true }
    { titre: 'Beta',  valeur: 2, prix: 2.25, actif: false }
    { titre: 'Gamma', valeur: 3, prix: 3,    actif: true }
  }
  rt_id = nil
  rt_yaml = nil

  -- Every stored record of the test space, decoded from its JSON blob.
  read_rows = ->
    user_sp = box.space["data_#{RT}"]
    return {} unless user_sp
    rows = {}
    for t in *user_sp\select {}
      table.insert rows, json.decode t[2]
    rows

  -- Canonical, order-independent form of a row set: one string per row, keys
  -- sorted, values typed via json.encode — two sets compare with R.eq.
  canonical_rows = (rows) ->
    parts = {}
    for r in *rows
      keys = [k for k, _ in pairs r]
      table.sort keys
      kv = {}
      for k in *keys
        table.insert kv, "#{k}=#{json.encode r[k]}"
      table.insert parts, "{#{table.concat kv, ' '}}"
    table.sort parts
    parts

  assert_same_rows = (actual, expected, label) ->
    got = canonical_rows actual
    exp = canonical_rows expected
    R.eq #got, #exp, "#{label}: row count"
    n = math.min #got, #exp
    for i = 1, n
      R.eq got[i], exp[i], "#{label}: row #{i}"

  R.it "creates the test space with several field types", ->
    ok, sp = pcall spaces.create_user_space, RT, 'round trip space'
    R.ok ok, tostring(sp)
    rt_id = sp.id
    for f in *RT_FIELDS
      ok2, err2 = pcall spaces.add_field, rt_id, f.name, f.fieldType, f.notNull
      R.ok ok2, "add_field #{f.name}: #{err2}"
    fields = spaces.list_fields rt_id
    R.eq #fields, #RT_FIELDS

  R.it "inserts the original records", ->
    for r in *ORIG_ROWS
      rec = data_res.Mutation.insertRecord {}, { spaceId: rt_id, data: r }, ADMIN_CTX
      R.ok rec, "insert #{r.titre}"
    R.eq #read_rows!, #ORIG_ROWS

  R.it "exports the space together with its data", ->
    yaml_str = export_r.Query.exportSnapshot nil, { includeData: true }, ADMIN_CTX
    R.ok yaml_str
    snap = yaml.decode yaml_str
    R.ok snap
    R.ok snap.data
    R.ok snap.data[RT], "data section for #{RT}"
    R.eq #snap.data[RT], #ORIG_ROWS
    rt_yaml = yaml_str

  R.it "exported rows hold the decoded field values", ->
    snap = yaml.decode rt_yaml
    assert_same_rows(snap.data[RT] or {}, ORIG_ROWS, 'exported data')

  R.it "deletes the test space", ->
    spaces.delete_user_space RT
    R.eq #read_rows!, 0
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == RT
    R.eq found, false

  R.it "reimports the snapshot in merge mode", ->
    result = export_r.Mutation.importSnapshot nil, { yaml: rt_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok result
    R.ok result.ok, table.concat(result.errors or {}, ' | ')
    R.eq #read_rows!, #ORIG_ROWS

  R.it "reimported records match the originals", ->
    assert_same_rows(read_rows!, ORIG_ROWS, 'restored data')

  -- Cleanup
  R.it "deletes the reimported test space", ->
    spaces.delete_user_space RT
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == RT
    R.eq found, false
