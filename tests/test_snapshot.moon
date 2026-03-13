-- tests/test_snapshot.moon
-- Tests exportSnapshot / diffSnapshot / importSnapshot resolvers.
-- Runs inside Tarantool instance (box already initialized).

R      = require 'tests.runner'
auth   = require 'core.auth'
spaces = require 'core.spaces'
export_r = require 'resolvers.export_resolvers'
yaml   = require 'yaml'

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
