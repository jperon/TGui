-- tests/test_app_apply.moon
-- Tests d'intégration pour backend/core/app_apply.moon (tâche V3a, plan
-- « Étape 4 » : installation, mise à jour atomique, suivi _tdb_apps/_tdb_app_items).
-- Tourne dans l'instance Tarantool de test (box déjà initialisé).
--
-- Mesure d'atomicité préalable (2026-10-07, instance de test) : box.begin!
-- suivi de create_user_space + add_field (String et Sequence) + insertions dans
-- _tdb_apps, _tdb_app_items, _tdb_custom_views, _tdb_data_views et
-- _tdb_widget_plugins, puis box.rollback! : tout est annulé (espace, séquence,
-- métadonnées) ; box.commit! les persiste. L'application est donc encadrée par
-- une transaction, et le test « échec au milieu » le vérifie.

R = require 'tests.runner'
pkg = require 'core.app_package'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
views = require 'core.views'
perms = require 'core.permissions'
data_views = require 'core.data_views'
schema_r = require 'resolvers.schema_resolvers'
cvr = require 'resolvers.custom_view_resolvers'
wpr = require 'resolvers.widget_plugin_resolvers'
dv_r = require 'resolvers.data_view_resolvers'
data_r = require 'resolvers.data_resolvers'
auth = require 'core.auth'
json = require 'json'

SUFFIX = tostring math.random 100000, 999999

SP_BOOKS   = "aap_books_#{SUFFIX}"
SP_AUTHORS = "aap_authors_#{SUFFIX}"
VIEW_NAME  = "aap_view_#{SUFFIX}"
PAGE_NAME  = "aap_page_#{SUFFIX}"
DV_NAME    = "aap_dv_#{SUFFIX}"
PLUGIN_NAME= "aap_plugin_#{SUFFIX}"
GROUP_NAME = "aap_group_#{SUFFIX}"
REL_NAME   = "aap_rel_#{SUFFIX}"
APP_ID     = "org.test.aap_#{SUFFIX}"
APP_BAD_ID = "org.test.aapbad_#{SUFFIX}"
SP_BAD     = "aap_bad_#{SUFFIX}"

KEY_TITLE = "field:#{SP_BOOKS}.title"
KEY_QTY   = "field:#{SP_BOOKS}.qty"
KEY_NOTE  = "field:#{SP_BOOKS}.note"

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

YAML_PAGE = [[
layout:
  direction: vertical
  children:
    - widget:
        title: App apply
        space: aap
]]

FIX = {}
PKG  = nil
PKG2 = nil
PKG3 = nil
seed_opts = {}

subset = (package) ->
  items = [it for it in *package.items when it.key\find SUFFIX, 1, true]
  { app: package.app, items: items, seed_keys: package.seed_keys or {} }

non_seed = (package) ->
  [it for it in *package.items when it.type != 'seed']

item_by_key = (package, key) ->
  for it in *package.items
    return it if it.key == key
  nil

row_dump = (space_name) ->
  rows = {}
  sp = box.space["data_#{space_name}"]
  return rows unless sp
  for t in *sp\select {}
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    table.insert rows, json.encode d
  table.sort rows
  rows

field_by_name = (space_id, name) ->
  for f in *spaces.list_fields space_id
    return f if f.name == name
  nil

describe_intact = (package) ->
  missing = {}
  for it in *non_seed(package)
    content = pkg.describe_local it.type, it.key
    if not content or pkg.canonical(content) != pkg.canonical(it.content)
      table.insert missing, it.key
  missing

installed_count = (app_id) ->
  #box.space._tdb_app_items.index.by_app\select { app_id }

clean_app_rows = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — fixture", ->

  R.it "creates two spaces with fields (String, Int, Sequence) and a relation", ->
    books = spaces.create_user_space SP_BOOKS, 'aap books'
    authors = spaces.create_user_space SP_AUTHORS, 'aap authors'
    FIX.books_id = books.id
    FIX.authors_id = authors.id
    spaces.add_field books.id, 'code', 'String', true, 'natural key'
    spaces.add_field books.id, 'title', 'String', false, ''
    spaces.add_field books.id, 'qty', 'Int', false, ''
    fk = spaces.add_field books.id, 'author_id', 'Int', false, ''
    FIX.fk_id = fk.id
    seq = spaces.add_field authors.id, 'seq_id', 'Sequence'
    FIX.seq_id = seq.id
    spaces.add_field authors.id, 'name', 'String', false, ''
    res = schema_r.Mutation.createRelation {}, {
      input: {
        name: REL_NAME
        fromSpaceId: books.id
        fromFieldId: fk.id
        toSpaceId: authors.id
        toFieldId: seq.id
        reprFormula: '@name'
      }
    }, CTX
    FIX.rel_id = res.id
    R.ok res

  R.it "creates a view, a page, a data view, a plugin, a group and permissions", ->
    v = views.create_view FIX.books_id, VIEW_NAME, 'grid', {
      layout: { direction: 'vertical', children: {} }
    }
    FIX.view_id = v.id
    p = cvr.Mutation.createCustomView {}, {
      name: PAGE_NAME, description: 'aap page', yaml: YAML_PAGE
    }, CTX
    FIX.page_id = p.id
    dv = dv_r.Mutation.createDataView nil, {
      input: {
        name: DV_NAME, description: 'aap data view'
        sourceSpace: SP_BOOKS
        config: json.encode { columns: { 'code', 'title' } }
      }
    }, CTX
    FIX.dv_id = dv.id
    wp = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: PLUGIN_NAME, description: 'aap plugin'
        scriptLanguage: 'coffeescript', templateLanguage: 'pug'
        scriptCode: "render '<div>ok</div>'", templateCode: 'div ok'
      }
    }, CTX
    FIX.plugin_id = wp.id
    g = perms.create_group GROUP_NAME, 'aap group'
    FIX.group_id = g.id
    perms.grant g.id, 'space', FIX.books_id, 'read'
    perms.grant g.id, 'space', nil, 'write'
    R.ok v and p and dv and wp and g

  R.it "inserts seed rows and builds a filtered package", ->
    for row in *{ { code: 'AAP-1', title: 'Premier', qty: 2 },
                  { code: 'AAP-2', title: 'Second', qty: 5 } }
      data_r.Mutation.insertRecord {}, { spaceId: FIX.books_id, data: row }, CTX
    seed_opts[SP_BOOKS] = 'code'
    META = { id: APP_ID, name: 'Aap fixture', version: '1.0.0', description: 'aap' }
    PKG = subset pkg.build_package META, { seed: seed_opts }
    R.ok PKG
    R.eq PKG.app.id, APP_ID
    n_items = #PKG.items
    n_nonseed = #non_seed PKG
    R.ok n_nonseed >= 16, "expected >= 16 non-seed items, got #{n_nonseed}"
    R.eq n_items - n_nonseed, 2, 'two seed items'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — load_package", ->

  R.it "recomputes every fingerprint from content, ignoring a supplied one", ->
    p = {
      app: { id: APP_ID, name: 'x', version: '1.0.0' }
      items: { { type: 'space', key: "space:#{SP_BOOKS}", content: { description: 'aap books' }, fingerprint: 'BOGUS' } }
    }
    norm = apply.load_package p
    R.ok norm
    R.ne norm.items[1].fingerprint, 'BOGUS'
    R.eq norm.items[1].fingerprint, pkg.fingerprint({ description: 'aap books' })

  R.it "rejects a package without app id", ->
    norm, err = apply.load_package { app: {}, items: {} }
    R.is_nil norm
    R.matches err, 'app id'

  R.it "rejects an item without content", ->
    norm = apply.load_package {
      app: { id: APP_ID, version: '1.0.0' }
      items: { { type: 'space', key: "space:#{SP_BOOKS}" } }
    }
    R.is_nil norm

  R.it "rejects an unknown item type", ->
    norm = apply.load_package {
      app: { id: APP_ID, version: '1.0.0' }
      items: { { type: 'gizmo', key: 'gizmo:x', content: {} } }
    }
    R.is_nil norm

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — preview_update", ->

  R.it "reports every element as unchanged while the local DB matches the package", ->
    plan = apply.preview_update PKG
    R.eq #plan.errors, 0, 'preview errors'
    R.eq #plan.create, 0, 'create'
    R.eq #plan.unchanged, #PKG.items, 'unchanged'

-- ────────────────────────────────────────────────────────────────────────────
-- Installation on a half-empty base
-- ────────────────────────────────────────────────────────────────────────────
remove_app_elements = ->
  if FIX.rel_id
    schema_r.Mutation.deleteRelation {}, { id: FIX.rel_id }, CTX
  views.delete_view FIX.view_id if FIX.view_id
  box.space._tdb_custom_views\delete FIX.page_id if FIX.page_id
  data_views.delete_view FIX.dv_id if FIX.dv_id
  box.space._tdb_widget_plugins\delete FIX.plugin_id if FIX.plugin_id
  perms.delete_group FIX.group_id if FIX.group_id
  spaces.delete_user_space SP_BOOKS
  spaces.delete_user_space SP_AUTHORS
  FIX.rel_id = nil
  FIX.view_id = nil
  FIX.page_id = nil
  FIX.dv_id = nil
  FIX.plugin_id = nil
  FIX.group_id = nil

R.describe "app_apply — installation on a half-empty base", ->

  R.it "removes the app elements locally", ->
    remove_app_elements!
    R.is_nil pkg.describe_local('space', "space:#{SP_BOOKS}")
    R.is_nil pkg.describe_local('relation', "relation:#{SP_BOOKS}.author_id")
    R.is_nil pkg.describe_local('page', "page:#{PAGE_NAME}")
    R.is_nil pkg.describe_local('group', "group:#{GROUP_NAME}")

  R.it "preview shows every packaged element to create (seed items included)", ->
    plan = apply.preview_update PKG
    R.eq #plan.errors, 0
    R.eq #plan.create, #PKG.items
    R.eq #plan.conflict, 0

  R.it "apply_update creates everything and records the version", ->
    report = apply.apply_update PKG, {}, {}
    R.ok report.ok, report.error
    R.eq #report.created, #non_seed(PKG), 'created'
    R.eq #report.updated, 0, 'updated'
    R.eq #report.conflicts, 0, 'conflicts'
    R.eq #describe_intact(PKG), 0, 'all non-seed elements match the package'
    R.eq installed_count(APP_ID), #non_seed(PKG), 'tracked items'
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.0.0', 'installed version'

  R.it "recreated the spaces, fields, relation, view, page, data view, plugin, group and perms", ->
    R.ok spaces.get_space_by_name SP_BOOKS
    R.ok spaces.get_space_by_name SP_AUTHORS
    R.ok (field_by_name spaces.get_space_by_name(SP_BOOKS).id, 'code')
    R.ok pkg.describe_local('relation', "relation:#{SP_BOOKS}.author_id")
    R.ok pkg.describe_local('view', "view:#{SP_BOOKS}.#{VIEW_NAME}")
    R.ok pkg.describe_local('page', "page:#{PAGE_NAME}")
    R.ok pkg.describe_local('dataview', "dataview:#{DV_NAME}")
    R.ok pkg.describe_local('plugin', "plugin:#{PLUGIN_NAME}")
    R.ok pkg.describe_local('group', "group:#{GROUP_NAME}")
    R.ok pkg.describe_local('perm', "perm:#{GROUP_NAME}|space|*|write")
    R.ok pkg.describe_local('perm', "perm:#{GROUP_NAME}|space|#{SP_BOOKS}|read")

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — reinstall of the same package", ->

  R.it "reports everything unchanged and creates nothing", ->
    report = apply.apply_update PKG, {}, {}
    R.ok report.ok, report.error
    R.eq #report.created, 0, 'created'
    R.eq #report.updated, 0, 'updated'
    R.eq #report.unchanged, #non_seed(PKG), 'unchanged'
    R.eq #report.conflicts, 0, 'conflicts'

-- ────────────────────────────────────────────────────────────────────────────
-- Update: author adds a field, user data must survive
-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — author adds a field, data preserved", ->

  R.it "builds v1.1.0 with an extra field, then removes it locally", ->
    for row in *{ { code: 'AAP-3', title: 'Troisieme', qty: 7 } }
      data_r.Mutation.insertRecord {}, { spaceId: spaces.get_space_by_name(SP_BOOKS).id, data: row }, CTX
    note = spaces.add_field spaces.get_space_by_name(SP_BOOKS).id, 'note', 'String', false, ''
    META2 = { id: APP_ID, name: 'Aap fixture', version: '1.1.0', description: 'aap' }
    PKG2 = subset pkg.build_package META2, { seed: seed_opts }
    spaces.remove_field note.id
    R.is_nil (field_by_name spaces.get_space_by_name(SP_BOOKS).id, 'note')
    FIX.rows_before = row_dump SP_BOOKS
    R.ok PKG2

  R.it "creates the new field and leaves user data untouched", ->
    report = apply.apply_update PKG2, {}, {}
    R.ok report.ok, report.error
    R.eq #report.created, 1, 'created'
    R.eq report.created[1], KEY_NOTE
    R.ok (field_by_name spaces.get_space_by_name(SP_BOOKS).id, 'note')
    rows_after = row_dump SP_BOOKS
    R.eq table.concat(rows_after, '|'), table.concat(FIX.rows_before, '|'), 'rows unchanged'
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.1.0', 'installed version'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — local-only changes are kept", ->

  R.it "keeps a field modified locally only", ->
    sid = spaces.get_space_by_name(SP_BOOKS).id
    spaces.update_field (field_by_name sid, 'title').id, { description: 'locally changed' }
    report = apply.apply_update PKG2, {}, {}
    R.ok report.ok, report.error
    R.eq #report.updated, 0, 'updated'
    found = false
    for k in *report.kept
      found = true if k == KEY_TITLE
    R.ok found, "expected #{KEY_TITLE} in kept"
    f = field_by_name sid, 'title'
    R.eq f.description, 'locally changed'

  R.it "leaves elements created locally outside the package intact", ->
    sid = spaces.get_space_by_name(SP_BOOKS).id
    spaces.add_field sid, 'local_only', 'String', false, 'mine'
    before = installed_count APP_ID
    report = apply.apply_update PKG2, {}, {}
    R.ok report.ok, report.error
    R.ok (field_by_name sid, 'local_only'), 'local_only still present'
    R.eq (field_by_name sid, 'local_only').description, 'mine'
    R.eq installed_count(APP_ID), before, 'no tracking row for a local element'
    R.is_nil item_by_key(PKG2, "field:#{SP_BOOKS}.local_only")

-- ────────────────────────────────────────────────────────────────────────────
-- Conflict: changed on both sides
-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — conflicts", ->

  R.it "sets up a local change and an author change on two fields", ->
    sid = spaces.get_space_by_name(SP_BOOKS).id
    spaces.update_field (field_by_name sid, 'title').id, { description: 'LOCAL-A' }
    spaces.update_field (field_by_name sid, 'qty').id, { description: 'LOCAL-B' }
    spaces.update_field (field_by_name sid, 'title').id, { description: 'AUTHOR-A' }
    spaces.update_field (field_by_name sid, 'qty').id, { description: 'AUTHOR-B' }
    META3 = { id: APP_ID, name: 'Aap fixture', version: '1.2.0', description: 'aap' }
    PKG3 = subset pkg.build_package META3, { seed: seed_opts }
    spaces.update_field (field_by_name sid, 'title').id, { description: 'LOCAL-A' }
    spaces.update_field (field_by_name sid, 'qty').id, { description: 'LOCAL-B' }
    R.ok PKG3
    R.eq item_by_key(PKG3, KEY_TITLE).content.description, 'AUTHOR-A'
    R.eq item_by_key(PKG3, KEY_QTY).content.description, 'AUTHOR-B'

  R.it "aborts without a decision and writes nothing", ->
    before = installed_count APP_ID
    report = apply.apply_update PKG3, {}, {}
    R.nok report.ok
    R.matches report.error, 'requires a decision'
    R.eq installed_count(APP_ID), before, 'no tracking write'
    sid = spaces.get_space_by_name(SP_BOOKS).id
    R.eq (field_by_name sid, 'title').description, 'LOCAL-A'
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.1.0', 'version unchanged'

  R.it "resolves 'local' for one and 'delivered' for the other", ->
    d = {}
    d[KEY_TITLE] = 'local'
    d[KEY_QTY] = 'delivered'
    report = apply.apply_update PKG3, d, {}
    R.ok report.ok, report.error
    R.eq #report.conflicts, 2, 'conflicts'
    sid = spaces.get_space_by_name(SP_BOOKS).id
    R.eq (field_by_name sid, 'title').description, 'LOCAL-A', 'local kept'
    R.eq (field_by_name sid, 'qty').description, 'AUTHOR-B', 'delivered applied'
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.2.0', 'installed version'
    R.eq pkg.describe_local('field', KEY_TITLE).description, 'LOCAL-A'
    R.eq pkg.describe_local('field', KEY_QTY).description, 'AUTHOR-B'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — downgrade is refused", ->

  R.it "refuses an older version without allow_downgrade and writes nothing", ->
    before = installed_count APP_ID
    report = apply.apply_update PKG2, {}, {}
    R.nok report.ok
    R.matches report.error, 'downgrade'
    R.eq installed_count(APP_ID), before
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.2.0'

  R.it "lifts the downgrade guard with allow_downgrade", ->
    report = apply.apply_update PKG2, {}, { allow_downgrade: true }
    err = report.error or ''
    R.is_nil (err\match 'downgrade'), "downgrade must no longer block: #{err}"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — invalid package", ->

  R.it "is refused without any write", ->
    spaces_before = #spaces.list_spaces!
    report = apply.apply_update { app: {}, items: {} }, {}, {}
    R.nok report.ok
    R.eq #spaces.list_spaces!, spaces_before
    R.nok box.space._tdb_apps\get(APP_BAD_ID)

  R.it "refuses an item without content", ->
    report = apply.apply_update {
      app: { id: APP_BAD_ID, version: '1.0.0' }
      items: { { type: 'space', key: "space:#{SP_BAD}" } }
    }, {}, {}
    R.nok report.ok
    R.nok box.space._tdb_apps\get(APP_BAD_ID)
    R.is_nil spaces.get_space_by_name SP_BAD

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — failure in the middle rolls back everything", ->

  R.it "creates a space, then fails on a relation to an unknown space", ->
    bad = {
      app: { id: APP_BAD_ID, name: 'Bad', version: '1.0.0' }
      items: {
        { type: 'space', key: "space:#{SP_BAD}", content: { description: 'bad' } }
        { type: 'field', key: "field:#{SP_BAD}.name",
          content: { fieldType: 'String', notNull: false, description: '',
                     formula: '', triggerFields: {}, language: 'lua' } }
        { type: 'relation', key: "relation:#{SP_BAD}.name",
          content: { fromSpace: SP_BAD, fromField: 'name',
                     toSpace: "no_such_space_#{SUFFIX}", toField: 'x' } }
      }
    }
    R.ok apply.load_package(bad), 'the package shape is valid (failure is operational)'
    spaces_before = #spaces.list_spaces!
    report = apply.apply_update bad, {}, {}
    R.nok report.ok
    R.is_nil spaces.get_space_by_name(SP_BAD), 'space rolled back'
    R.eq #spaces.list_spaces!, spaces_before, 'space count restored'
    R.is_nil box.space._tdb_apps\get(APP_BAD_ID), 'no app row'
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_BAD_ID }), 0, 'no item rows'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "app_apply — cleanup", ->

  R.it "removes every fixture element and tracking row", ->
    sid = spaces.get_space_by_name SP_BOOKS
    if sid
      for t in *box.space._tdb_relations.index.by_from\select { sid.id }
        box.space._tdb_relations\delete t[1]
    for v in *box.space._tdb_views\select {}
      views.delete_view v[1] if v[3] == VIEW_NAME
    for dv in *box.space._tdb_data_views\select {}
      data_views.delete_view dv[1] if dv[2] == DV_NAME
    for cv in *box.space._tdb_custom_views\select {}
      box.space._tdb_custom_views\delete cv[1] if cv[2] == PAGE_NAME
    for wp in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete wp[1] if wp[2] == PLUGIN_NAME
    for g in *perms.list_groups!
      perms.delete_group g.id if g.name == GROUP_NAME
    clean_app_rows APP_ID
    clean_app_rows APP_BAD_ID
    spaces.delete_user_space SP_BOOKS
    spaces.delete_user_space SP_AUTHORS
    R.is_nil spaces.get_space_by_name SP_BOOKS
    R.is_nil pkg.describe_local('page', "page:#{PAGE_NAME}")
    R.is_nil pkg.describe_local('plugin', "plugin:#{PLUGIN_NAME}")
    R.is_nil pkg.describe_local('group', "group:#{GROUP_NAME}")
    R.is_nil box.space._tdb_apps\get APP_ID
    R.eq installed_count(APP_ID), 0
