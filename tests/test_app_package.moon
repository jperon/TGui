-- tests/test_app_package.moon
-- Tests for backend/core/app_package.moon (task V1, plan « Étape 4 » :
-- identité, empreinte, Interfaces, ligne V1).
-- Covers: canonical JSON, fingerprints, the _tdb_apps / _tdb_app_items system
-- spaces created by core.spaces.migrate, build_package and describe_local.
-- Runs inside the Tarantool test instance (box already initialized).

R = require 'tests.runner'
pkg = require 'core.app_package'
spaces = require 'core.spaces'
views = require 'core.views'
perms = require 'core.permissions'
schema_r = require 'resolvers.schema_resolvers'
cvr = require 'resolvers.custom_view_resolvers'
wpr = require 'resolvers.widget_plugin_resolvers'
dv_r = require 'resolvers.data_view_resolvers'
data_r = require 'resolvers.data_resolvers'
auth = require 'core.auth'
json = require 'json'
yaml = require 'yaml'

SUFFIX = tostring math.random 100000, 999999

SP_BOOKS    = "apkg_books_#{SUFFIX}"
SP_AUTHORS  = "apkg_authors_#{SUFFIX}"
VIEW_NAME   = "apkg_view_#{SUFFIX}"
PAGE_NAME   = "apkg_page_#{SUFFIX}"
DV_NAME     = "apkg_dataview_#{SUFFIX}"
PLUGIN_NAME = "apkg_plugin_#{SUFFIX}"
GROUP_NAME  = "apkg_group_#{SUFFIX}"
REL_NAME    = "apkg_rel_#{SUFFIX}"
SP_SEED     = "apkg_seed_#{SUFFIX}"

-- DÉFAUT 1 : noms contenant des délimiteurs de clé (., |, :, %).
SP_ESP   = "apkg_esp.ace_#{SUFFIX}"
FLD_ESP  = 'a.b|c:d%e'
FLDN_ESP = 'plain_field'
GRP_ESP  = "apkg_grp|x.y_#{SUFFIX}"
GRP_FORGE = "#{GRP_ESP}|space|*|read"

FIX_ESP = {}

META = {
  id: 'org.test.apkg'
  name: 'Apkg fixture'
  version: '1.0.0'
  description: 'app package fixture'
}

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

YAML_PAGE = [[
layout:
  direction: vertical
  children:
    - widget:
        title: App package
        space: apkg
]]

FIX = {}
FIX_SEED = {}
PKG  = nil
PKG2 = nil
seed_opts = {}

find_item = (package, key) ->
  for it in *package.items
    return it if it.key == key
  nil

-- build_package with a seed config must raise; return the message for asserts.
seed_error = (seed_config) ->
  ok, err = pcall -> pkg.build_package META, { seed: seed_config }
  R.nok ok, 'expected an invalid seed configuration to raise'
  tostring err

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — canonical", ->

  R.it "is independent of object key order, recursively", ->
    a = { b: 1, a: 2, c: { z: 9, y: { q: 1, p: 2 } } }
    b = { c: { y: { p: 2, q: 1 }, z: 9 }, a: 2, b: 1 }
    R.eq pkg.canonical(a), pkg.canonical(b)

  R.it "keeps array order", ->
    R.ne pkg.canonical({ 1, 2, 3 }), pkg.canonical({ 3, 2, 1 })

  R.it "encodes scalars through Tarantool json.encode", ->
    R.eq(pkg.canonical('x'), json.encode('x'))
    R.eq(pkg.canonical(42), json.encode(42))
    R.eq(pkg.canonical(true), json.encode(true))
    R.eq pkg.canonical(nil), 'null'

  R.it "canonicalizes an empty table as an empty array", ->
    R.eq pkg.canonical({}), '[]'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — fingerprint", ->

  R.it "is a 64-char lowercase hex digest", ->
    fp = pkg.fingerprint { a: 1 }
    R.eq #fp, 64
    R.matches fp, '^[0-9a-f]+$'

  R.it "is stable for equal content, whatever the key order", ->
    R.eq(pkg.fingerprint({ a: 1, b: 'x' }), pkg.fingerprint({ b: 'x', a: 1 }))

  R.it "changes when the content changes", ->
    R.ne(pkg.fingerprint({ a: 1 }), pkg.fingerprint({ a: 2 }))
    R.ne(pkg.fingerprint({ a: 1 }), pkg.fingerprint({ a: 1, b: 2 }))

-- ────────────────────────────────────────────────────────────────────────────
-- DÉFAUT 1 : les clés encodent chaque composante de nom (app_package.key_part).
R.describe "app_package — key escaping", ->

  R.it "key_part/unkey_part round-trip every special character", ->
    for s in *{ '', 'plain', 'a.b|c:d%e', '%2E', 'esp ace', 'accÉnt', 'idself.id',
                'a|space|*|admin', 'Esp.ace', 'x%7Cy' }
      R.eq pkg.unkey_part(pkg.key_part(s)), s, "round-trip #{s}"

  R.it "only the four delimiters are escaped", ->
    R.eq pkg.key_part('a.b|c:d%e'), 'a%2Eb%7Cc%3Ad%25e'
    R.eq pkg.key_part('plain_name'), 'plain_name'
    R.eq pkg.key_part('%2E'), '%252E'

  R.it "a component never keeps an unescaped delimiter", ->
    k = pkg.key_part 'a.b|c:d%e'
    R.is_nil (k\find '.', 1, true)
    R.is_nil (k\find '|', 1, true)
    R.is_nil (k\find ':', 1, true)

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — system spaces (_tdb_apps, _tdb_app_items)", ->

  R.it "migrate creates both spaces with their indexes", ->
    spaces.migrate!
    R.ok box.space._tdb_apps, "_tdb_apps created by migrate"
    R.ok box.space._tdb_app_items, "_tdb_app_items created by migrate"
    R.ok box.space._tdb_apps.index.primary
    R.ok box.space._tdb_app_items.index.primary
    R.ok box.space._tdb_app_items.index.by_app

  R.it "recreates them when they are missing", ->
    box.space._tdb_app_items\drop!
    box.space._tdb_apps\drop!
    spaces.migrate!
    R.ok box.space._tdb_apps
    R.ok box.space._tdb_app_items
    R.ok box.space._tdb_app_items.index.by_app

  R.it "exposes the documented columns", ->
    apps_cols = { f.name, true for f in *box.space._tdb_apps\format! }
    R.ok apps_cols['app_id']
    R.ok apps_cols['name']
    R.ok apps_cols['version']
    R.ok apps_cols['installed_at']
    R.ok apps_cols['source']
    items_cols = { f.name, true for f in *box.space._tdb_app_items\format! }
    for col in *{ 'app_id', 'key', 'type', 'local_id', 'fingerprint', 'state', 'version' }
      R.ok items_cols[col], "missing column #{col}"

  R.it "has a composite primary key {app_id, key} and a non-unique by_app", ->
    now = os.time!
    box.space._tdb_apps\insert { 'apkg_sys_test', 'Sys', '1.0.0', now, 'test' }
    box.space._tdb_app_items\insert { 'apkg_sys_test', 'k1', 'space', 'loc1', 'fp1', 'active', '1.0.0' }
    box.space._tdb_app_items\insert { 'apkg_sys_test', 'k2', 'field', 'loc2', 'fp2', 'active', '1.0.0' }
    R.eq(#box.space._tdb_app_items.index.by_app\select({ 'apkg_sys_test' }), 2)
    ok_dup = pcall ->
      box.space._tdb_app_items\insert { 'apkg_sys_test', 'k1', 'space', 'loc9', 'fp9', 'active', '1.0.0' }
    R.eq ok_dup, false, "duplicate {app_id, key} must be rejected"
    box.space._tdb_app_items\delete { 'apkg_sys_test', 'k1' }
    box.space._tdb_app_items\delete { 'apkg_sys_test', 'k2' }
    box.space._tdb_apps\delete 'apkg_sys_test'
    R.eq(#box.space._tdb_app_items.index.by_app\select({ 'apkg_sys_test' }), 0)

-- ────────────────────────────────────────────────────────────────────────────
-- Fixture: every item type delivered by an app package
-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — fixture", ->

  R.it "creates the two test spaces", ->
    books = spaces.create_user_space SP_BOOKS, 'apkg books'
    authors = spaces.create_user_space SP_AUTHORS, 'apkg authors'
    FIX.books_id = books.id
    FIX.authors_id = authors.id
    R.ok books
    R.ok authors

  R.it "adds fields of several types, including a formula field", ->
    R.ok spaces.add_field(FIX.books_id, 'code', 'String', true, 'natural key')
    R.ok spaces.add_field(FIX.books_id, 'title', 'String', false, '')
    R.ok spaces.add_field(FIX.books_id, 'qty', 'Int', false, '')
    total = spaces.add_field FIX.books_id, 'total', 'Int', false, '', '(self.qty or 0) * 2'
    R.eq total.formula, '(self.qty or 0) * 2'
    R.eq total.language, 'lua'
    seq = spaces.add_field FIX.authors_id, 'seq_id', 'Sequence'
    FIX.seq_id = seq.id
    R.ok spaces.add_field(FIX.authors_id, 'name', 'String', false, '')

  R.it "creates a relation books.author_id → authors.seq_id", ->
    fk = spaces.add_field FIX.books_id, 'author_id', 'Int', false, ''
    FIX.fk_id = fk.id
    res = schema_r.Mutation.createRelation {}, {
      input: {
        name: REL_NAME
        fromSpaceId: FIX.books_id
        fromFieldId: FIX.fk_id
        toSpaceId: FIX.authors_id
        toFieldId: FIX.seq_id
        reprFormula: '@name'
        cardinality: 'many'
      }
    }, CTX
    R.ok res
    FIX.rel_id = res.id

  R.it "creates a grid view on the books space", ->
    v = views.create_view FIX.books_id, VIEW_NAME, 'grid', {
      layout: { direction: 'vertical', children: {} }
    }
    R.ok v
    FIX.view_id = v.id

  R.it "creates a page (custom view)", ->
    res = cvr.Mutation.createCustomView {}, {
      name: PAGE_NAME
      description: 'apkg page'
      yaml: YAML_PAGE
    }, CTX
    R.ok res
    FIX.page_id = res.id

  R.it "creates a data view over the books space", ->
    res = dv_r.Mutation.createDataView nil, {
      input: {
        name: DV_NAME
        description: 'apkg data view'
        sourceSpace: SP_BOOKS
        config: json.encode { columns: { 'code', 'title' } }
      }
    }, CTX
    R.ok res
    FIX.dv_id = res.id

  R.it "creates a widget plugin", ->
    res = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: PLUGIN_NAME
        description: 'apkg plugin'
        scriptLanguage: 'coffeescript'
        templateLanguage: 'pug'
        scriptCode: "render '<div>ok</div>'"
        templateCode: 'div ok'
      }
    }, CTX
    R.ok res
    FIX.plugin_id = res.id

  R.it "creates a group with permissions", ->
    g = perms.create_group GROUP_NAME, 'apkg group'
    FIX.group_id = g.id
    R.ok g
    perms.grant g.id, 'space', FIX.books_id, 'read'
    perms.grant g.id, 'space', nil, 'write'
    R.eq #perms.list_permissions(g.id), 2

  R.it "inserts seed rows in the books space", ->
    rows = {
      { code: 'APKG-1', title: 'Premier', qty: 2 }
      { code: 'APKG-2', title: 'Second', qty: 5 }
      { code: 'APKG-3', title: 'Troisieme', qty: 7 }
    }
    for row in *rows
      rec = data_r.Mutation.insertRecord {}, { spaceId: FIX.books_id, data: row }, CTX
      R.ok rec
    seed_opts[SP_BOOKS] = 'code'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — build_package", ->

  R.it "returns app metadata, items and seed_keys", ->
    PKG = pkg.build_package META, { seed: seed_opts }
    R.ok PKG
    R.eq PKG.app.id, META.id
    R.eq PKG.app.name, META.name
    R.eq PKG.app.version, META.version
    R.eq PKG.app.description, META.description
    R.ok #PKG.items >= 20, "expected at least the 20 fixture items, got #{#PKG.items}"
    R.eq PKG.seed_keys[SP_BOOKS], 'code'

  R.it "every item carries type, key and content", ->
    bad = 0
    for it in *PKG.items
      bad += 1 unless it.type and it.key and type(it.content) == 'table'
    R.eq bad, 0

  R.it "covers the ten item types", ->
    seen = { it.type, true for it in *PKG.items }
    for t in *{ 'space', 'field', 'relation', 'view', 'page', 'dataview', 'plugin', 'group', 'perm', 'seed' }
      R.ok seen[t], "missing item type #{t}"

  R.it "delivers both test spaces sorted by name", ->
    keys = [it.key for it in *PKG.items when it.type == 'space']
    expected = [k for k in *keys]
    table.sort expected
    R.eq table.concat(keys, ','), table.concat(expected, ',')

  R.it "lists the fields of a space in position order", ->
    keys = {}
    for it in *PKG.items
      table.insert keys, it.key if it.type == 'field' and it.key\match "^field:#{SP_BOOKS}%."
    expected = ["field:#{SP_BOOKS}.#{f.name}" for f in *spaces.list_fields FIX.books_id]
    R.eq #keys, #expected
    for i = 1, #expected
      R.eq keys[i], expected[i]

  R.it "never delivers the built-in admin group", ->
    found = false
    for it in *PKG.items
      found = true if it.key == 'group:admin' or it.key\match '^perm:admin|'
    R.nok found

  R.it "relation items carry the declared cardinality", ->
    key = "relation:#{SP_BOOKS}.author_id"
    item = find_item PKG, key
    R.ok item
    R.eq item.content.cardinality, 'many'
    R.eq pkg.describe_local('relation', key).cardinality, 'many'
    R.eq pkg.canonical(pkg.describe_local('relation', key)), pkg.canonical(item.content)

  R.it "is deterministic: two calls give the same items and fingerprints", ->
    PKG2 = pkg.build_package META, { seed: seed_opts }
    R.eq #PKG2.items, #PKG.items
    diffs = {}
    for i = 1, #PKG.items
      a, b = PKG.items[i], PKG2.items[i]
      if a.key != b.key or a.type != b.type or pkg.fingerprint(a.content) != pkg.fingerprint(b.content)
        table.insert diffs, tostring(i)
    R.eq #diffs, 0, "diverging items at #{table.concat diffs, ','}"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — describe_local", ->

  R.it "matches the package content of every item", ->
    mismatches = {}
    for it in *PKG.items
      local_content = pkg.describe_local it.type, it.key
      if not local_content or pkg.canonical(local_content) != pkg.canonical(it.content)
        table.insert mismatches, it.key
    R.eq #mismatches, 0, "describe_local mismatch: #{table.concat mismatches, ', '}"
    R.ok #PKG.items >= 20, "expected at least the 20 fixture items, got #{#PKG.items}"

  R.it "space: returns the stored description", ->
    key = "space:#{SP_BOOKS}"
    item = find_item PKG, key
    R.ok item
    R.eq(pkg.canonical(pkg.describe_local('space', key)), pkg.canonical(item.content))
    R.eq item.content.description, 'apkg books'

  R.it "field: normalizes empty values (description, formula, triggerFields)", ->
    key = "field:#{SP_BOOKS}.total"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'field', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.formula, '(self.qty or 0) * 2'
    R.eq local_content.language, 'lua'
    R.eq #local_content.triggerFields, 0
    R.eq local_content.description, ''
    R.eq pkg.canonical(local_content), pkg.canonical({
      fieldType: 'Int'
      notNull: false
      description: ''
      formula: '(self.qty or 0) * 2'
      triggerFields: {}
      language: 'lua'
    })

  R.it "relation: returns the four endpoint names", ->
    key = "relation:#{SP_BOOKS}.author_id"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'relation', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.fromSpace, SP_BOOKS
    R.eq local_content.fromField, 'author_id'
    R.eq local_content.toSpace, SP_AUTHORS
    R.eq local_content.toField, 'seq_id'
    R.eq local_content.cardinality, 'many'

  R.it "view: returns space, name, viewType and config", ->
    key = "view:#{SP_BOOKS}.#{VIEW_NAME}"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'view', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.space, SP_BOOKS
    R.eq local_content.viewType, 'grid'

  R.it "page: returns name, description and yaml", ->
    key = "page:#{PAGE_NAME}"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'page', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.name, PAGE_NAME
    R.eq local_content.description, 'apkg page'
    R.eq local_content.yaml, YAML_PAGE

  R.it "dataview: returns sourceSpace as a space name", ->
    key = "dataview:#{DV_NAME}"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'dataview', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.sourceSpace, SP_BOOKS
    R.eq local_content.description, 'apkg data view'

  R.it "plugin: returns the script and template code", ->
    key = "plugin:#{PLUGIN_NAME}"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'plugin', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.scriptLanguage, 'coffeescript'
    R.eq local_content.templateLanguage, 'pug'
    R.eq local_content.scriptCode, "render '<div>ok</div>'"
    R.eq local_content.templateCode, 'div ok'

  R.it "group: returns name and description", ->
    key = "group:#{GROUP_NAME}"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'group', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.name, GROUP_NAME
    R.eq local_content.description, 'apkg group'

  R.it "perm: resolves the resource to a space name and to '*'", ->
    key = "perm:#{GROUP_NAME}|space|#{SP_BOOKS}|read"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'perm', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.resource, SP_BOOKS
    R.eq local_content.group, GROUP_NAME
    R.eq local_content.level, 'read'
    wild_key = "perm:#{GROUP_NAME}|space|*|write"
    wild_item = find_item PKG, wild_key
    R.ok wild_item
    wild_local = pkg.describe_local 'perm', wild_key
    R.eq(pkg.canonical(wild_local), pkg.canonical(wild_item.content))
    R.eq wild_local.resource, '*'

  R.it "seed: returns the row keyed by its natural key", ->
    key = "seed:#{SP_BOOKS}|APKG-2"
    item = find_item PKG, key
    R.ok item
    local_content = pkg.describe_local 'seed', key
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq local_content.space, SP_BOOKS
    R.eq local_content.key, 'APKG-2'
    R.eq local_content.data.title, 'Second'
    R.eq local_content.data.qty, 5

  R.it "returns nil for elements that do not exist", ->
    R.is_nil pkg.describe_local('space', "space:no_such_space_#{SUFFIX}")
    R.is_nil pkg.describe_local('field', "field:#{SP_BOOKS}.no_such_field")
    R.is_nil pkg.describe_local('page', "page:no_such_page_#{SUFFIX}")
    R.is_nil pkg.describe_local('group', "group:no_such_group_#{SUFFIX}")
    R.is_nil pkg.describe_local('seed', "seed:#{SP_BOOKS}|NO-SUCH-KEY")
    R.is_nil pkg.describe_local('nonsense', 'nonsense:x')

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — seed validation (F1)", ->

  R.it "creates a dedicated seed space with one field and a baseline row", ->
    sp = spaces.create_user_space SP_SEED, 'apkg seed'
    FIX_SEED.id = sp.id
    spaces.add_field sp.id, 'code', 'String', true, ''
    box.space["data_#{SP_SEED}"]\insert {
      "apkgseed_base_#{SUFFIX}", json.encode { code: 'BASE', label: 'baseline' }
    }
    R.ok sp

  R.it "rejects an unknown seed space, naming it and the word 'space'", ->
    msg = seed_error { ["apkg_ghost_#{SUFFIX}"]: 'code' }
    R.matches msg, "apkg_ghost_#{SUFFIX}"
    R.matches msg, 'space'

  R.it "rejects an unknown key field, naming the space and the field", ->
    msg = seed_error { [SP_SEED]: 'no_such_field' }
    R.matches msg, SP_SEED
    R.matches msg, 'no_such_field'

  R.it "rejects rows missing the key value, naming space, field and count", ->
    row_id = "apkgseed_nokey_#{SUFFIX}"
    box.space["data_#{SP_SEED}"]\insert { row_id, json.encode { label: 'no code' } }
    msg = seed_error { [SP_SEED]: 'code' }
    R.matches msg, SP_SEED
    R.matches msg, 'code'
    R.matches msg, '1 seed row'
    box.space["data_#{SP_SEED}"]\delete row_id

  R.it "rejects a duplicated key value, naming the space and the value", ->
    row_id = "apkgseed_dup_#{SUFFIX}"
    box.space["data_#{SP_SEED}"]\insert { row_id, json.encode { code: 'BASE' } }
    msg = seed_error { [SP_SEED]: 'code' }
    R.matches msg, SP_SEED
    R.matches msg, 'BASE'
    R.matches msg, 'duplicate'
    box.space["data_#{SP_SEED}"]\delete row_id

  R.it "a valid seed configuration still delivers the same items", ->
    package = pkg.build_package META, { seed: { [SP_SEED]: 'code' } }
    R.eq package.seed_keys[SP_SEED], 'code'
    item = find_item package, "seed:#{SP_SEED}|BASE"
    R.ok item
    R.eq item.content.space, SP_SEED
    R.eq item.content.key, 'BASE'
    R.eq item.content.data.label, 'baseline'

-- ────────────────────────────────────────────────────────────────────────────
-- DÉFAUT 1 : build_package et describe_local pour des noms à délimiteurs.
R.describe "app_package — special names are unambiguous", ->

  R.it "creates a space, a field and groups whose names contain delimiters", ->
    sp = spaces.create_user_space SP_ESP, 'esp ace space'
    FIX_ESP.space_id = sp.id
    f = spaces.add_field sp.id, FLD_ESP, 'String', false, 'champ spécial'
    FIX_ESP.field_id = f.id
    spaces.add_field sp.id, FLDN_ESP, 'String', false, ''
    g1 = perms.create_group GRP_ESP, 'groupe à barres'
    FIX_ESP.group_id = g1.id
    perms.grant g1.id, 'space', sp.id, 'read'
    g2 = perms.create_group GRP_FORGE, 'groupe forgeant une clé'
    FIX_ESP.forge_id = g2.id
    perms.grant g2.id, 'space', nil, 'read'
    R.ok sp and f and g1 and g2

  R.it "the generated keys are unambiguous and round-trip through describe_local", ->
    package = pkg.build_package META, {}
    esp = [it for it in *package.items when it.key\find SUFFIX, 1, true]
    -- Clés attendues, encodées explicitement.
    sp_key = "space:#{pkg.key_part SP_ESP}"
    f_key = "field:#{pkg.key_part SP_ESP}.#{pkg.key_part FLD_ESP}"
    fn_key = "field:#{pkg.key_part SP_ESP}.#{pkg.key_part FLDN_ESP}"
    p_key = "perm:#{pkg.key_part GRP_ESP}|space|#{pkg.key_part SP_ESP}|read"
    forge_key = "perm:#{pkg.key_part GRP_FORGE}|space|*|read"
    for key in *{ sp_key, f_key, fn_key, p_key, forge_key }
      item = find_item package, key
      R.ok item, "missing item #{key}"
      local_content = pkg.describe_local item.type, key
      R.ok local_content, "describe_local(#{key})"
      R.eq pkg.canonical(local_content), pkg.canonical(item.content), "content #{key}"
    -- Le champ spécial se relit bien sous son espace et son nom d'origine.
    fld = pkg.describe_local 'field', f_key
    R.eq fld.fieldType, 'String'
    R.eq fld.description, 'champ spécial'
    -- La clé perm d'un groupe à barres a exactement trois barres non échappées.
    body = p_key\match '^perm:(.*)$'
    n_parts = 0
    for _ in body\gmatch '[^|]+'
      n_parts += 1
    R.eq n_parts, 4
    -- Deux groupes aux noms forgés ne produisent jamais la même clé.
    R.ne p_key, forge_key
    keys = {}
    dup = nil
    for it in *esp
      dup = it.key if keys[it.key]
      keys[it.key] = true
    R.is_nil dup, "duplicate key #{dup}"

  R.it "an escaped key survives a JSON round-trip unchanged", ->
    package = pkg.build_package META, {}
    for it in *package.items
      continue unless it.key\find SUFFIX, 1, true
      R.eq json.decode(json.encode(it.key)), it.key

  R.it "removes the special-name fixture", ->
    if FIX_ESP.forge_id
      perms.delete_group FIX_ESP.forge_id
    if FIX_ESP.group_id
      perms.delete_group FIX_ESP.group_id
    spaces.delete_user_space SP_ESP
    R.is_nil pkg.describe_local('space', "space:#{pkg.key_part SP_ESP}")
    R.is_nil pkg.describe_local('group', "group:#{pkg.key_part GRP_ESP}")

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — cleanup", ->

  R.it "removes the fixture elements", ->
    if FIX.rel_id
      schema_r.Mutation.deleteRelation {}, { id: FIX.rel_id }, CTX
    if FIX.view_id
      views.delete_view FIX.view_id
    if FIX.page_id
      cvr.Mutation.deleteCustomView {}, { id: FIX.page_id }, CTX
    if FIX.dv_id
      dv_r.Mutation.deleteDataView nil, { id: FIX.dv_id }, CTX
    if FIX.plugin_id
      wpr.Mutation.deleteWidgetPlugin {}, { id: FIX.plugin_id }, CTX
    if FIX.group_id
      perms.delete_group FIX.group_id
    R.is_nil pkg.describe_local('relation', "relation:#{SP_BOOKS}.author_id")
    R.is_nil pkg.describe_local('view', "view:#{SP_BOOKS}.#{VIEW_NAME}")
    R.is_nil pkg.describe_local('page', "page:#{PAGE_NAME}")
    R.is_nil pkg.describe_local('dataview', "dataview:#{DV_NAME}")
    R.is_nil pkg.describe_local('plugin', "plugin:#{PLUGIN_NAME}")
    R.is_nil pkg.describe_local('group', "group:#{GROUP_NAME}")

  R.it "removes the two test spaces and their seed rows", ->
    spaces.delete_user_space SP_BOOKS
    spaces.delete_user_space SP_AUTHORS
    spaces.delete_user_space SP_SEED
    R.is_nil pkg.describe_local('space', "space:#{SP_BOOKS}")
    R.is_nil pkg.describe_local('space', "space:#{SP_AUTHORS}")
    R.is_nil pkg.describe_local('space', "space:#{SP_SEED}")
    R.is_nil pkg.describe_local('seed', "seed:#{SP_BOOKS}|APKG-1")
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP_BOOKS or s.name == SP_AUTHORS
    R.nok found

-- ────────────────────────────────────────────────────────────────────────────
-- T22 : normalisation à la frontière de lecture (box.NULL, clés absentes).
-- Les valeurs sont produites par le VRAI yaml.decode de Tarantool, jamais
-- construites à la main côté Lua.
-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_package — strip_null (T22)", ->

  R.it "drops box.NULL from object values and array elements decoded by yaml", ->
    raw = yaml.decode "a: null\nb: ~\nc:\nd: [1, null, 2]\ne:\n  x: null\n  y: ok\n"
    R.ok raw.a == box.NULL, 'yaml null decodes to box.NULL'
    R.ok raw.b == box.NULL, 'yaml ~ decodes to box.NULL'
    R.eq raw.c, '', 'an empty yaml value is an empty string'
    R.ok raw.d[2] == box.NULL, 'null inside a list decodes to box.NULL'
    s = pkg.strip_null raw
    R.is_nil s.a
    R.is_nil s.b
    R.eq s.c, ''
    R.eq #s.d, 2
    R.eq s.d[1], 1
    R.eq s.d[2], 2
    R.is_nil s.e.x
    R.eq s.e.y, 'ok'
    R.ok raw.a == box.NULL, 'strip_null does not mutate its argument'

  R.it "leaves ordinary scalars and non-null cdata untouched", ->
    R.eq pkg.strip_null('x'), 'x'
    R.eq pkg.strip_null(3), 3
    R.eq pkg.strip_null(true), true
    R.is_nil pkg.strip_null(nil)
    R.is_nil pkg.strip_null(box.NULL)

R.describe "app_package — normalize_content (T22)", ->

  R.it "reproduces each builder's defaults for absent optional keys", ->
    expected = {
      space: { description: '' }
      field: { notNull: false, description: '', formula: '', triggerFields: {}, language: 'lua' }
      relation: { cardinality: 'one' }
      view: {}
      page: { description: '', yaml: '' }
      dataview: { description: '', sourceSpace: '' }
      plugin: { description: '', scriptLanguage: 'coffeescript', templateLanguage: 'pug',
                scriptCode: '', templateCode: '' }
      group: { description: '' }
      perm: { resource: '*' }
      seed: { data: {} }
    }
    for item_type, exp in pairs expected
      got = pkg.normalize_content item_type, {}
      R.eq pkg.canonical(got), pkg.canonical(exp), "normalize #{item_type}"

  R.it "normalizes a field content decoded by yaml (null optionals)", ->
    raw = yaml.decode "fieldType: Int\nnotNull: ~\ndescription: null\nformula: ~\ntriggerFields: null\nlanguage: null\n"
    c = pkg.normalize_content 'field', pkg.strip_null(raw)
    R.eq pkg.canonical(c), pkg.canonical {
      fieldType: 'Int'
      notNull: false
      description: ''
      formula: ''
      triggerFields: {}
      language: 'lua'
    }

  R.it "is idempotent and does not mutate its argument", ->
    original = { fieldType: 'Int', description: 'x' }
    c1 = pkg.normalize_content 'field', original
    c2 = pkg.normalize_content 'field', c1
    R.eq pkg.canonical(c1), pkg.canonical(c2)
    R.eq pkg.canonical(original), pkg.canonical({ fieldType: 'Int', description: 'x' })
    R.eq original.formula, nil, 'the argument gained no key'

  R.it "matches the fingerprint of the equivalent builder content", ->
    raw = yaml.decode "fieldType: String\nnotNull: false\ndescription: null\nformula: ~\ntriggerFields:\nlanguage: null\n"
    c = pkg.normalize_content 'field', pkg.strip_null(raw)
    built = {
      fieldType: 'String', notNull: false, description: '', formula: '',
      triggerFields: {}, language: 'lua'
    }
    R.eq pkg.fingerprint(c), pkg.fingerprint(built)
