-- tests/test_app_resolvers.moon
-- Tests des résolveurs GraphQL du versionnage des apps (tâche V4, spec §3/§4,
-- plan « Étape 4 » ligne V4) : permissions, export YAML, aperçu sans écriture,
-- installation, conflit, obsolètes/purge, isCode, câblage SDL via l'exécuteur.
-- Tourne dans l'instance Tarantool de test (box déjà initialisé).

R           = require 'tests.runner'
auth        = require 'core.auth'
perms_mod   = require 'core.permissions'
spaces      = require 'core.spaces'
views       = require 'core.views'
data_views  = require 'core.data_views'
app_package = require 'core.app_package'
app_r       = require 'resolvers.app_resolvers'
executor    = require 'graphql.executor'
yaml        = require 'yaml'
json        = require 'json'
data_r      = require 'resolvers.data_resolvers'
cvr         = require 'resolvers.custom_view_resolvers'
dv_r        = require 'resolvers.data_view_resolvers'
wpr         = require 'resolvers.widget_plugin_resolvers'

SUFFIX = tostring math.random 100000, 999999

SP_NAME     = "ar_sp_#{SUFFIX}"
SP_AUX      = "ar_aux_#{SUFFIX}"
VIEW_NAME   = "ar_view_#{SUFFIX}"
PAGE_NAME   = "ar_page_#{SUFFIX}"
DV_NAME     = "ar_dv_#{SUFFIX}"
PLUGIN_NAME = "ar_plugin_#{SUFFIX}"
GROUP_NAME  = "ar_group_#{SUFFIX}"

FIELD_CODE = "field:#{SP_NAME}.code"
FIELD_QTY  = "field:#{SP_NAME}.qty"
FIELD_NOTE = "field:#{SP_NAME}.note"

APP_ID       = "org.test.ar_#{SUFFIX}"
GHOST_PLUGIN = "ar_ghost_plugin_#{SUFFIX}"
GHOST_PAGE   = "ar_ghost_page_#{SUFFIX}"
GHOST_DV     = "ar_ghost_dv_#{SUFFIX}"
GHOST_BASE   = "ar_ghost_#{SUFFIX}"

admin = auth.get_user_by_username 'admin'
ADMIN_CTX = { user_id: admin.id }

ACTOR = auth.create_user "aractor_#{SUFFIX}", "aractor_#{SUFFIX}@test.local", "pass1234"
ACTOR_SESSION = auth.create_session ACTOR.id
NONADMIN_CTX = { user_id: ACTOR.id, token: ACTOR_SESSION.token }
ANON_CTX = {}

YAML_PAGE = [[
layout:
  direction: vertical
  children:
    - widget:
        title: App resolvers
        space: ar
]]

FIX = {}
YAML1 = nil
DECODED1 = nil
YAML3 = nil
seed_opts = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

field_by_name = (space_name, name) ->
  sp = spaces.get_space_by_name space_name
  return nil unless sp
  for f in *spaces.list_fields sp.id
    return f if f.name == name
  nil

find_item = (package, key) ->
  for it in *package.items
    return it if it.key == key
  nil

find_created = (plan, key) ->
  for it in *plan.create
    return it if it.key == key
  nil

set_description = (package, key, value) ->
  for it in *package.items
    it.content.description = value if it.key == key and type(it.content) == 'table'
  package

without_item = (package, key) ->
  kept = [it for it in *package.items when it.key != key]
  package.items = kept
  package

variant = (base_yaml, key, value) ->
  package = yaml.decode base_yaml
  yaml.encode set_description(package, key, value)

remove_fixture = ->
  for v in *box.space._tdb_views\select {}
    views.delete_view v[1] if v[3] == VIEW_NAME
  for cv in *box.space._tdb_custom_views\select {}
    cvr.Mutation.deleteCustomView {}, { id: cv[1] }, ADMIN_CTX if cv[2] == PAGE_NAME
  for dv in *box.space._tdb_data_views\select {}
    dv_r.Mutation.deleteDataView nil, { id: dv[1] }, ADMIN_CTX if dv[2] == DV_NAME
  for wp in *box.space._tdb_widget_plugins\select {}
    wpr.Mutation.deleteWidgetPlugin {}, { id: wp[1] }, ADMIN_CTX if wp[2] == PLUGIN_NAME
  for g in *perms_mod.list_groups!
    perms_mod.delete_group g.id if g.name == GROUP_NAME
  spaces.delete_user_space SP_NAME
  spaces.delete_user_space SP_AUX

clean_app_rows = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

run_gql = (query, vars, ctx) ->
  executor.execute { query: query, variables: (vars or {}), context: ctx }

errs_json = (res) -> json.encode res.errors or {}

ghost_package = ->
  items = {
    { type: 'field', key: "field:#{GHOST_BASE}.plain",
      content: { fieldType: 'String', notNull: false, description: '',
                 formula: '', triggerFields: {}, language: 'lua' } }
    { type: 'field', key: "field:#{GHOST_BASE}.calc",
      content: { fieldType: 'Int', notNull: false, description: '',
                 formula: '1 + 1', triggerFields: {}, language: 'lua' } }
    { type: 'field', key: "field:#{GHOST_BASE}.trig",
      content: { fieldType: 'String', notNull: false, description: '',
                 formula: '', triggerFields: { 'a' }, language: 'moon' } }
    { type: 'plugin', key: "plugin:#{GHOST_PLUGIN}",
      content: { name: GHOST_PLUGIN, description: '', scriptLanguage: 'coffeescript',
                 templateLanguage: 'pug', scriptCode: 'x = 1', templateCode: 'div' } }
    { type: 'page', key: "page:#{GHOST_PAGE}",
      content: { name: GHOST_PAGE, description: '', yaml: 'layout: {}' } }
    { type: 'dataview', key: "dataview:#{GHOST_DV}",
      content: { name: GHOST_DV, description: '', sourceSpace: GHOST_BASE,
                 config: { columns: { 'x' } } } }
  }
  {
    app: { id: "org.test.arghost_#{SUFFIX}", name: 'Ghost', version: '1.0.0', description: '' }
    items: items
    seed_keys: {}
  }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — fixture", ->

  R.it "creates a space with data, a view, a page, a data view, a plugin and a group", ->
    books = spaces.create_user_space SP_NAME, 'app resolvers books'
    FIX.books_id = books.id
    spaces.add_field books.id, 'code', 'String', true, 'natural key'
    spaces.add_field books.id, 'qty', 'Int', false, ''
    spaces.add_field books.id, 'total', 'Int', false, '', '(self.qty or 0) * 2'
    spaces.add_field books.id, 'note', 'String', false, ''
    FIX.view_id = views.create_view(books.id, VIEW_NAME, 'grid', {
      layout: { direction: 'vertical', children: {} }
    }).id
    FIX.page_id = cvr.Mutation.createCustomView({}, {
      name: PAGE_NAME, description: 'ar page', yaml: YAML_PAGE
    }, ADMIN_CTX).id
    FIX.dv_id = dv_r.Mutation.createDataView(nil, {
      input: { name: DV_NAME, description: 'ar dv', sourceSpace: SP_NAME,
               config: json.encode { columns: { 'code', 'qty' } } }
    }, ADMIN_CTX).id
    FIX.plugin_id = wpr.Mutation.createWidgetPlugin({}, {
      input: { name: PLUGIN_NAME, description: 'ar plugin',
               scriptLanguage: 'coffeescript', templateLanguage: 'pug',
               scriptCode: "render 'x'", templateCode: 'div x' }
    }, ADMIN_CTX).id
    FIX.group_id = perms_mod.create_group(GROUP_NAME, 'ar group').id
    perms_mod.grant FIX.group_id, 'space', books.id, 'read'
    R.ok spaces.get_space_by_name SP_NAME
    R.ok FIX.view_id
    R.ok FIX.page_id
    R.ok FIX.dv_id
    R.ok FIX.plugin_id
    R.ok FIX.group_id

  R.it "inserts seed rows (including one with a note value)", ->
    for row in *{ { code: 'AR-1', qty: 2 }, { code: 'AR-2', qty: 5 },
                  { code: 'AR-3', qty: 0, note: 'hello' } }
      data_r.Mutation.insertRecord {}, { spaceId: FIX.books_id, data: row }, ADMIN_CTX
    seed_opts[SP_NAME] = 'code'
    sp = box.space["data_#{SP_NAME}"]
    R.eq #sp\select({}), 3

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — permissions", ->

  export_args = -> {
    meta: { id: APP_ID, name: 'AR', version: '1.0.0', description: '' }
    seed: { { space: SP_NAME, keyField: 'code' } }
  }

  R.it "every operation is Unauthorized for an anonymous context", ->
    R.raises (-> app_r.Query.listApps nil, {}, ANON_CTX), 'Unauthorized'
    R.raises (-> app_r.Query.appItems nil, { appId: APP_ID }, ANON_CTX), 'Unauthorized'
    R.raises (-> app_r.Query.exportApp nil, export_args!, ANON_CTX), 'Unauthorized'
    R.raises (-> app_r.Query.previewAppUpdate nil, { yaml: 'a: 1' }, ANON_CTX), 'Unauthorized'
    R.raises (-> app_r.Query.previewAppPurge nil, { appId: APP_ID, keys: {} }, ANON_CTX), 'Unauthorized'
    R.raises (-> app_r.Mutation.applyAppUpdate nil, { yaml: 'a: 1' }, ANON_CTX), 'Unauthorized'
    R.raises (-> app_r.Mutation.purgeAppObsolete nil, { appId: APP_ID, keys: {}, confirmed: true }, ANON_CTX), 'Unauthorized'

  R.it "every operation is Forbidden for an authenticated non-admin", ->
    R.raises (-> app_r.Query.listApps nil, {}, NONADMIN_CTX), 'Forbidden'
    R.raises (-> app_r.Query.appItems nil, { appId: APP_ID }, NONADMIN_CTX), 'Forbidden'
    R.raises (-> app_r.Query.exportApp nil, export_args!, NONADMIN_CTX), 'Forbidden'
    R.raises (-> app_r.Query.previewAppUpdate nil, { yaml: 'a: 1' }, NONADMIN_CTX), 'Forbidden'
    R.raises (-> app_r.Query.previewAppPurge nil, { appId: APP_ID, keys: {} }, NONADMIN_CTX), 'Forbidden'
    R.raises (-> app_r.Mutation.applyAppUpdate nil, { yaml: 'a: 1' }, NONADMIN_CTX), 'Forbidden'
    R.raises (-> app_r.Mutation.purgeAppObsolete nil, { appId: APP_ID, keys: {}, confirmed: true }, NONADMIN_CTX), 'Forbidden'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — exportApp", ->

  R.it "builds a YAML package that reloads into a valid package", ->
    YAML1 = app_r.Query.exportApp {}, {
      meta: { id: APP_ID, name: 'App resolvers', version: '1.0.0', description: 'ar' }
      seed: { { space: SP_NAME, keyField: 'code' } }
    }, ADMIN_CTX
    R.eq type(YAML1), 'string'
    DECODED1 = yaml.decode YAML1
    R.ok DECODED1
    R.eq DECODED1.app.id, APP_ID
    R.eq DECODED1.app.version, '1.0.0'
    R.ok DECODED1.app.name
    R.ok (find_item DECODED1, FIELD_CODE), 'code field delivered'
    R.ok (find_item DECODED1, FIELD_QTY), 'qty field delivered'
    R.ok (find_item DECODED1, FIELD_NOTE), 'note field delivered'
    R.eq (find_item DECODED1, FIELD_NOTE).content.formula, ''
    R.ok (find_item DECODED1, "seed:#{SP_NAME}|AR-1"), 'seed row delivered'
    R.is_nil find_item(DECODED1, 'group:admin'), 'admin group never delivered'

  R.it "refuses a version that is not x.y.z", ->
    bad = { meta: { id: APP_ID, name: 'AR', version: '1.0', description: '' } }
    R.raises (-> app_r.Query.exportApp nil, bad, ADMIN_CTX), 'semver'
    bad2 = { meta: { id: APP_ID, name: 'AR', version: 'abc', description: '' } }
    R.raises (-> app_r.Query.exportApp nil, bad2, ADMIN_CTX), 'semver'
    bad3 = { meta: { id: APP_ID, name: 'AR', version: nil, description: '' } }
    R.raises (-> app_r.Query.exportApp nil, bad3, ADMIN_CTX), 'semver'

  R.it "propagates an invalid seed configuration as a readable GraphQL error", ->
    require('resolvers.init').reinit!
    ghost = "ar_ghost_seed_#{SUFFIX}"
    q = 'query($m: AppMetaInput!, $s: [AppSeedInput!]) { exportApp(meta: $m, seed: $s) }'
    res = run_gql q, {
      m: { id: APP_ID, name: 'AR', version: '1.0.0', description: '' }
      s: { { space: ghost, keyField: 'code' } }
    }, ADMIN_CTX
    R.ok res.errors, 'export with an unknown seed space must fail'
    msg = tostring res.errors[1].message
    R.matches msg, ghost
    R.matches msg, 'space'
    R.is_nil res.data.exportApp, 'no partial package is returned'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — previewAppUpdate is read-only", ->

  R.it "reports every element unchanged while the local DB matches the package", ->
    plan = app_r.Query.previewAppUpdate nil, { yaml: YAML1 }, ADMIN_CTX
    R.eq #plan.errors, 0, json.encode(plan.errors)
    R.eq #plan.create, 0, 'create'
    R.eq #plan.update, 0, 'update'
    R.eq #plan.conflict, 0, 'conflict'
    R.eq #plan.unchanged, #DECODED1.items, 'unchanged'

  R.it "writes nothing", ->
    spaces_before = #spaces.list_spaces!
    fields_before = #box.space._tdb_fields\select {}
    rows_before = #box.space._tdb_app_items.index.by_app\select { APP_ID }
    qty_desc_before = (field_by_name SP_NAME, 'qty').description
    app_r.Query.previewAppUpdate nil, { yaml: YAML1 }, ADMIN_CTX
    R.eq #spaces.list_spaces!, spaces_before
    R.eq #box.space._tdb_fields\select({}), fields_before
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_ID }), rows_before
    R.eq (field_by_name SP_NAME, 'qty').description, qty_desc_before
    R.nok box.space._tdb_apps\get(APP_ID), 'preview must not install the app'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — GraphQL wiring via the executor", ->

  R.it "listApps and previewAppUpdate are reachable through the real schema", ->
    require('resolvers.init').reinit!
    q = "{ listApps { appId name version activeCount obsoleteCount } }"
    res = run_gql q, {}, ADMIN_CTX
    R.nok res.errors, errs_json res
    R.eq type(res.data.listApps), 'table'
    q2 = 'query($y: String!) { previewAppUpdate(yaml: $y) { create { key type isCode } update { key } conflict { key local delivered } unchanged errors } }'
    res2 = run_gql q2, { y: YAML1 }, ADMIN_CTX
    R.nok res2.errors, errs_json res2
    R.eq #res2.data.previewAppUpdate.errors, 0
    R.eq #res2.data.previewAppUpdate.create, 0
    R.eq #res2.data.previewAppUpdate.unchanged, #DECODED1.items

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — apply on a deleted base recreates everything", ->

  R.it "removes every fixture element", ->
    remove_fixture!
    R.is_nil spaces.get_space_by_name SP_NAME
    R.is_nil app_package.describe_local('view', "view:#{SP_NAME}.#{VIEW_NAME}")
    R.is_nil app_package.describe_local('page', "page:#{PAGE_NAME}")
    R.is_nil app_package.describe_local('group', "group:#{GROUP_NAME}")
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_ID }), 0

  R.it "applyAppUpdate recreates the space, the elements and the seed rows", ->
    report = app_r.Mutation.applyAppUpdate nil, { yaml: YAML1 }, ADMIN_CTX
    R.ok report.ok, report.error
    R.ok #report.created > 0, 'some items were created'
    R.ok spaces.get_space_by_name SP_NAME
    R.ok (field_by_name SP_NAME, 'code')
    R.ok (field_by_name SP_NAME, 'qty')
    R.ok (field_by_name SP_NAME, 'note')
    R.eq #box.space["data_#{SP_NAME}"]\select({}), 3
    R.ok app_package.describe_local('view', "view:#{SP_NAME}.#{VIEW_NAME}")
    R.ok app_package.describe_local('page', "page:#{PAGE_NAME}")
    R.ok app_package.describe_local('dataview', "dataview:#{DV_NAME}")
    R.ok app_package.describe_local('plugin', "plugin:#{PLUGIN_NAME}")
    R.ok app_package.describe_local('group', "group:#{GROUP_NAME}")
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.0.0'
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_ID }), #DECODED1.items

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — obsolete items and purge", ->

  R.it "applying a package without the note field marks it obsolete", ->
    YAML3 = yaml.encode without_item(yaml.decode(YAML1), FIELD_NOTE)
    report = app_r.Mutation.applyAppUpdate nil, { yaml: YAML3 }, ADMIN_CTX
    R.ok report.ok, report.error
    found = false
    for key in *report.obsolete
      found = true if key == FIELD_NOTE
    R.ok found, 'note field reported obsolete'
    note_tracking = box.space._tdb_app_items\get { APP_ID, FIELD_NOTE }
    R.eq note_tracking[6], 'obsolète'
    R.ok (field_by_name SP_NAME, 'note'), 'obsolete field is never deleted'

  R.it "appItems lists tracked items sorted by key with their states", ->
    items = app_r.Query.appItems nil, { appId: APP_ID }, ADMIN_CTX
    R.ok #items > 0, 'tracked items returned'
    note_found = nil
    prev_key = ''
    for it in *items
      R.ok it.key > prev_key, "sorted after #{prev_key}: #{it.key}"
      prev_key = it.key
      if it.key == FIELD_NOTE
        note_found = it
      else
        R.eq it.state, 'actif', "state of #{it.key}"
        R.eq it.version, '1.0.0', "version of #{it.key}"
    R.ok note_found, 'obsolete note item listed'
    R.eq note_found.state, 'obsolète'
    R.eq note_found.type, 'field'
    R.eq note_found.version, '1.0.0'

  R.it "appItems returns an empty list for an unknown appId", ->
    items = app_r.Query.appItems nil, { appId: "org.test.unknown_#{SUFFIX}" }, ADMIN_CTX
    R.eq #items, 0

  R.it "appItems is reachable through the real GraphQL schema", ->
    require('resolvers.init').reinit!
    q = 'query($id: String!) { appItems(appId: $id) { key type state version } }'
    res = run_gql q, { id: APP_ID }, ADMIN_CTX
    R.nok res.errors, errs_json res
    R.eq type(res.data.appItems), 'table'
    R.ok #res.data.appItems > 0, 'items via GraphQL'
    note_found = nil
    for it in *res.data.appItems
      note_found = it if it.key == FIELD_NOTE
    R.ok note_found, 'note item via GraphQL'
    R.eq note_found.state, 'obsolète'
    R.eq note_found.type, 'field'
    res2 = run_gql q, { id: "org.test.unknown_#{SUFFIX}" }, ADMIN_CTX
    R.nok res2.errors, errs_json res2
    R.eq #res2.data.appItems, 0
    res3 = run_gql q, { id: APP_ID }, ANON_CTX
    R.ok res3.errors, 'anonymous refused via GraphQL'
    R.ok (errs_json res3)\match 'Unauthorized'

  R.it "previewAppPurge reports the losses and writes nothing", ->
    preview = app_r.Query.previewAppPurge nil, { appId: APP_ID, keys: { FIELD_NOTE } }, ADMIN_CTX
    R.eq #preview.losses, 1
    R.eq preview.losses[1].key, FIELD_NOTE
    R.eq preview.losses[1].type, 'field'
    R.eq preview.losses[1].records, 1, 'one row carries a note value'
    R.eq preview.totalRecords, 1
    R.ok (field_by_name SP_NAME, 'note'), 'preview must not purge'
    still = box.space._tdb_app_items\get { APP_ID, FIELD_NOTE }
    R.eq still[6], 'obsolète'

  R.it "purgeAppObsolete refuses without explicit confirmation", ->
    report = app_r.Mutation.purgeAppObsolete nil,
      { appId: APP_ID, keys: { FIELD_NOTE }, confirmed: false }, ADMIN_CTX
    R.nok report.ok
    R.matches report.error, 'confirmation'
    R.ok (field_by_name SP_NAME, 'note'), 'not purged without confirmation'

  R.it "purgeAppObsolete purges with confirmed = true", ->
    report = app_r.Mutation.purgeAppObsolete nil,
      { appId: APP_ID, keys: { FIELD_NOTE }, confirmed: true }, ADMIN_CTX
    R.ok report.ok, report.error
    R.eq #report.purged, 1
    R.eq report.purged[1], FIELD_NOTE
    R.is_nil field_by_name(SP_NAME, 'note')
    R.is_nil box.space._tdb_app_items\get { APP_ID, FIELD_NOTE }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — conflict decisions", ->

  R.it "a conflict without a decision is refused and writes nothing", ->
    qty = field_by_name SP_NAME, 'qty'
    spaces.update_field qty.id, { description: 'LOCAL-QTY' }
    FIX.yaml2 = variant YAML3, FIELD_QTY, 'AUTHOR-QTY'
    report = app_r.Mutation.applyAppUpdate nil, { yaml: FIX.yaml2 }, ADMIN_CTX
    R.nok report.ok
    R.matches report.error, 'decision'
    R.eq (field_by_name SP_NAME, 'qty').description, 'LOCAL-QTY'

  R.it "preview exposes local and delivered contents for the conflict", ->
    plan = app_r.Query.previewAppUpdate nil, { yaml: FIX.yaml2 }, ADMIN_CTX
    R.eq #plan.conflict, 1
    R.eq plan.conflict[1].key, FIELD_QTY
    R.eq plan.conflict[1].local.description, 'LOCAL-QTY'
    R.eq plan.conflict[1].delivered.description, 'AUTHOR-QTY'

  R.it "an invalid choice is rejected", ->
    bad = { yaml: FIX.yaml2, decisions: { { key: FIELD_QTY, choice: 'banana' } } }
    R.raises (-> app_r.Mutation.applyAppUpdate nil, bad, ADMIN_CTX), 'Invalid decision'

  R.it "accepting the delivered value applies the author change", ->
    args = { yaml: FIX.yaml2, decisions: { { key: FIELD_QTY, choice: 'delivered' } } }
    report = app_r.Mutation.applyAppUpdate nil, args, ADMIN_CTX
    R.ok report.ok, report.error
    R.eq (field_by_name SP_NAME, 'qty').description, 'AUTHOR-QTY'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — isCode marks third-party code", ->

  R.it "flags plugins, pages, data views and formula/trigger fields", ->
    plan = app_r.Query.previewAppUpdate nil,
      { yaml: yaml.encode(ghost_package!) }, ADMIN_CTX
    R.eq #plan.errors, 0, json.encode(plan.errors)
    R.eq #plan.create, 6
    R.nok (find_created plan, "field:#{GHOST_BASE}.plain").isCode, 'plain field'
    R.ok (find_created plan, "field:#{GHOST_BASE}.calc").isCode, 'formula field'
    R.ok (find_created plan, "field:#{GHOST_BASE}.trig").isCode, 'trigger field'
    R.ok (find_created plan, "plugin:#{GHOST_PLUGIN}").isCode, 'plugin'
    R.ok (find_created plan, "page:#{GHOST_PAGE}").isCode, 'page'
    R.ok (find_created plan, "dataview:#{GHOST_DV}").isCode, 'data view'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — invalid inputs", ->

  R.it "invalid YAML is refused with a clear error", ->
    R.raises (-> app_r.Query.previewAppUpdate nil, { yaml: '{{{' }, ADMIN_CTX), 'Invalid YAML'
    R.raises (-> app_r.Mutation.applyAppUpdate nil, { yaml: 'a: [1, 2' }, ADMIN_CTX), 'Invalid YAML'

  R.it "a package without app id is refused with a clear error", ->
    bad = yaml.encode { app: {}, items: {} }
    R.raises (-> app_r.Query.previewAppUpdate nil, { yaml: bad }, ADMIN_CTX), 'Invalid package'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — listApps", ->

  R.it "lists the installed app with its item counts", ->
    apps = app_r.Query.listApps nil, {}, ADMIN_CTX
    found = nil
    for app in *apps
      found = app if app.appId == APP_ID
    R.ok found, 'installed app listed'
    R.eq found.name, 'App resolvers'
    R.eq found.version, '1.0.0'
    R.ok found.activeCount > 0, 'active items counted'
    R.eq found.obsoleteCount, 0, 'no obsolete item remains after purge'
    R.ok found.installedAt > 0

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_resolvers — cleanup", ->

  R.it "removes the fixture and the app tracking rows", ->
    remove_fixture!
    clean_app_rows APP_ID
    auth.delete_session ACTOR_SESSION.token
    box.space._tdb_users\delete ACTOR.id
    R.is_nil spaces.get_space_by_name SP_NAME
    R.is_nil box.space._tdb_apps\get APP_ID
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_ID }), 0
