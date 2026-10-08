-- tests/test_import_snapshot_format.moon
-- importSnapshot must refuse documents that are not snapshots BEFORE do_import
-- runs: in replace mode do_import deletes every user space first
-- (backend/resolvers/export_resolvers.moon), so an application package or an
-- unknown document must never reach it. Observed with
-- apps/bibliotheque/bibliotheque.tdbapp.yaml imported through the snapshot
-- button: "0 créé(s), 0 ignoré(s)" without any error raised.

R        = require 'tests.runner'
auth     = require 'core.auth'
spaces   = require 'core.spaces'
export_r = require 'resolvers.export_resolvers'
yaml     = require 'yaml'

SUFFIX = tostring math.random 100000, 999999
admin_user = auth.get_user_by_username 'admin'
ADMIN_CTX  = { user_id: admin_user and admin_user.id }

-- Minimal application package: head keys `app` and `items`, as in
-- apps/bibliotheque/bibliotheque.tdbapp.yaml.
PKG_YAML = "app:\n  id: org.test.t13_#{SUFFIX}\n  version: \"1.0.0\"\nitems: []\n"

-- Neither an application package nor a snapshot.
UNKNOWN_YAML = "foo: bar\n"

space_exists = (name) ->
  for s in *spaces.list_spaces!
    return true if s.name == name
  false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — unknown document refused", ->

  R.it "raises an unrecognized-file error", ->
    R.raises (-> export_r.Mutation.importSnapshot nil, { yaml: UNKNOWN_YAML, mode: 'merge' }, ADMIN_CTX), "non reconnu"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — valid snapshot accepted", ->
  RT = "t13_rt_#{SUFFIX}"
  rt_yaml = nil

  R.it "creates a space and exports a snapshot", ->
    ok, sp = pcall spaces.create_user_space, RT, 'round trip space'
    R.ok ok, tostring(sp)
    ok2, err2 = pcall spaces.add_field, sp.id, 'titre', 'String', false
    R.ok ok2, tostring(err2)
    rt_yaml = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    R.ok rt_yaml

  R.it "exported snapshot holds the test space in schema.spaces", ->
    snap = yaml.decode rt_yaml
    R.ok snap.schema
    R.ok type(snap.schema.spaces) == 'table'
    found = false
    for entry in *snap.schema.spaces
      found = true if entry.name == RT
    R.ok found

  R.it "deletes the space then reimports the snapshot in merge mode", ->
    spaces.delete_user_space RT
    R.nok space_exists RT
    res = export_r.Mutation.importSnapshot nil, { yaml: rt_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok res.ok, table.concat(res.errors or {}, ' | ')
    R.ok (res.created > 0), 'created'

  R.it "space and field are back after the round trip", ->
    R.ok space_exists RT
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == RT
    R.ok sp
    has = false
    for f in *spaces.list_fields sp.id
      has = true if f.name == 'titre'
    R.ok has, 'field titre'

  R.it "accepts a snapshot whose schema.spaces list is empty", ->
    empty_snap = {
      version: '1'
      schema: {
        spaces: {}, relations: {}, custom_views: {}
        data_views: {}, widget_plugins: {}, groups: {}
      }
    }
    res = export_r.Mutation.importSnapshot nil, { yaml: yaml.encode(empty_snap), mode: 'merge' }, ADMIN_CTX
    R.ok res.ok, table.concat(res.errors or {}, ' | ')
    R.eq res.created, 0

  -- Cleanup
  R.it "cleanup round-trip space", ->
    spaces.delete_user_space RT if space_exists RT
    R.nok space_exists RT

-- ────────────────────────────────────────────────────────────────────────────
-- LAST on purpose: in the broken state the replace test below deletes every
-- user space (that is the bug), which perturbs the suites running after this
-- file in the same pass.
R.describe "importSnapshot — application package refused", ->
  SP = "t13_pkg_#{SUFFIX}"

  R.it "creates a guard space", ->
    ok, err = pcall spaces.create_user_space, SP, 'guard space'
    R.ok ok, tostring(err)
    R.ok space_exists SP

  R.it "merge mode raises a package error", ->
    R.raises (-> export_r.Mutation.importSnapshot nil, { yaml: PKG_YAML, mode: 'merge' }, ADMIN_CTX), "paquet d.application"

  R.it "replace mode raises and deletes nothing", ->
    R.raises (-> export_r.Mutation.importSnapshot nil, { yaml: PKG_YAML, mode: 'replace' }, ADMIN_CTX), "paquet d.application"
    R.ok space_exists SP, "guard space must survive a refused replace import"

  -- Cleanup
  R.it "cleanup guard space", ->
    spaces.delete_user_space SP if space_exists SP
    R.nok space_exists SP
