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
yaml = require 'yaml'

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
        cardinality: 'many'
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
    R.eq #report.created, #PKG.items, 'created'
    R.eq #report.updated, 0, 'updated'
    R.eq #report.conflicts, 0, 'conflicts'
    R.eq #describe_intact(PKG), 0, 'all non-seed elements match the package'
    R.eq installed_count(APP_ID), #PKG.items, 'tracked items'
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.0.0', 'installed version'

  R.it "recreated the spaces, fields, relation, view, page, data view, plugin, group and perms", ->
    R.ok spaces.get_space_by_name SP_BOOKS
    R.ok spaces.get_space_by_name SP_AUTHORS
    R.ok (field_by_name spaces.get_space_by_name(SP_BOOKS).id, 'code')
    R.ok pkg.describe_local('relation', "relation:#{SP_BOOKS}.author_id")
    R.eq pkg.describe_local('relation', "relation:#{SP_BOOKS}.author_id").cardinality, 'many'
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
    R.eq #report.unchanged, #PKG.items, 'unchanged'
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
-- V1b : la cardinalité déclarée d'une relation fait partie du paquet.
-- ────────────────────────────────────────────────────────────────────────────
SP_RB = "aap_relbooks_#{SUFFIX}"
SP_RA = "aap_relauthors_#{SUFFIX}"
APP_REL = "org.test.aaprel_#{SUFFIX}"
REL_RB_KEY = "relation:#{SP_RB}.author_id"
REL_RB_EDITOR = "relation:#{SP_RB}.editor_id"

-- Contenu d'une relation : la clé cardinality n'est posée que si déclarée,
-- pour reproduire un paquet à l'ancien format quand card est nil.
rel_content = (from_field, card) ->
  c = { fromSpace: SP_RB, fromField: from_field, toSpace: SP_RA, toField: 'seq_id' }
  c.cardinality = card if card
  c

rel_field = (name) ->
  { type: 'field', key: "field:#{SP_RB}.#{name}",
    content: { fieldType: 'Int', notNull: false, description: '',
               formula: '', triggerFields: {}, language: 'lua' } }

rel_pkg = (version, author_card) ->
  {
    app: { id: APP_REL, name: 'Rel cardinality', version: version, description: '' }
    items: {
      { type: 'space', key: "space:#{SP_RB}", content: { description: 'rel books' } }
      { type: 'space', key: "space:#{SP_RA}", content: { description: 'rel authors' } }
      rel_field 'author_id'
      rel_field 'editor_id'
      { type: 'field', key: "field:#{SP_RA}.seq_id",
        content: { fieldType: 'Sequence', notNull: false, description: '',
                   formula: '', triggerFields: {}, language: 'lua' } }
      { type: 'relation', key: REL_RB_KEY, content: rel_content('author_id', author_card) }
      { type: 'relation', key: REL_RB_EDITOR, content: rel_content('editor_id', nil) }
    }
    seed_keys: {}
  }

R.describe "app_apply — relation cardinality", ->

  R.it "installs 'many' when declared and 'one' for an old-format relation", ->
    report = apply.apply_update rel_pkg('1.0.0', 'many'), {}, {}
    R.ok report.ok, report.error
    R.eq #report.created, 7, 'created'
    R.eq pkg.describe_local('relation', REL_RB_KEY).cardinality, 'many'
    R.eq pkg.describe_local('relation', REL_RB_EDITOR).cardinality, 'one'

  R.it "an author cardinality change is an update while the local is unchanged", ->
    report = apply.apply_update rel_pkg('1.1.0', 'one'), {}, {}
    R.ok report.ok, report.error
    R.eq #report.updated, 1, 'updated'
    R.eq report.updated[1], REL_RB_KEY
    R.eq pkg.describe_local('relation', REL_RB_KEY).cardinality, 'one'

  R.it "a local-only cardinality change is kept", ->
    sid = spaces.get_space_by_name(SP_RB).id
    fid = (field_by_name sid, 'author_id').id
    rel_id = nil
    for t in *box.space._tdb_relations.index.by_from\select { sid }
      rel_id = t[1] if t[3] == fid
    R.ok rel_id, 'author_id relation row'
    schema_r.Mutation.updateRelation {}, { id: rel_id, input: { cardinality: 'many' } }, CTX
    R.eq pkg.describe_local('relation', REL_RB_KEY).cardinality, 'many'
    report = apply.apply_update rel_pkg('1.1.0', 'one'), {}, {}
    R.ok report.ok, report.error
    found = false
    for k in *report.kept
      found = true if k == REL_RB_KEY
    R.ok found, "expected #{REL_RB_KEY} in kept"
    R.eq pkg.describe_local('relation', REL_RB_KEY).cardinality, 'many'

  R.it "cleans up the relation cardinality fixture", ->
    for nm in *{ SP_RB, SP_RA }
      sp = spaces.get_space_by_name nm
      if sp
        for t in *box.space._tdb_relations.index.by_from\select { sp.id }
          box.space._tdb_relations\delete t[1]
        for t in *box.space._tdb_relations.index.by_to\select { sp.id }
          box.space._tdb_relations\delete t[1]
    clean_app_rows APP_REL
    spaces.delete_user_space SP_RB
    spaces.delete_user_space SP_RA
    R.is_nil spaces.get_space_by_name SP_RB
    R.is_nil pkg.describe_local('relation', REL_RB_KEY)

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

-- ────────────────────────────────────────────────────────────────────────────
-- DÉFAUT 2 (v) : via app_apply, un contenu de champ sans formule (parseur
-- standard) doit quand même appliquer la description sans perdre de colonne.
SP_UF   = "aap_uf_#{SUFFIX}"
APP_UF  = "org.test.aapuf_#{SUFFIX}"
KEY_UF  = "field:#{SP_UF}.calc"

R.describe "app_apply — field without formula in package (DÉFAUT 2)", ->

  R.it "updates the description of a formula field with formula absent", ->
    sp = spaces.create_user_space SP_UF, 'uf'
    spaces.add_field sp.id, 'calc', 'String', false, 'orig desc', 'self.plain or ""'
    p1 = subset pkg.build_package {
      id: APP_UF, name: 'UF', version: '1.0.0', description: ''
    }, {}
    R.ok apply.load_package(p1), 'p1 valid'
    r1 = apply.apply_update p1, {}, {}
    R.ok r1.ok, r1.error
    items = {}
    for it in *p1.items
      if it.key == KEY_UF
        table.insert items, {
          type: 'field'
          key: it.key
          content: {
            fieldType: 'String'
            notNull: false
            description: 'delivered desc'
            triggerFields: {}
            language: 'lua'
          }
        }
      else
        table.insert items, it
    p2 = {
      app: { id: APP_UF, name: 'UF', version: '1.1.0', description: '' }
      items: items
      seed_keys: {}
    }
    r2 = apply.apply_update p2, {}, {}
    R.ok r2.ok, r2.error
    sid = spaces.get_space_by_name(SP_UF).id
    R.eq (field_by_name sid, 'calc').description, 'delivered desc'
    local_c = pkg.describe_local 'field', KEY_UF
    R.eq local_c.description, 'delivered desc'
    R.eq local_c.formula, '', 'delivered field carries no formula'

  R.it "cleans up the field-formula fixture", ->
    clean_app_rows APP_UF
    spaces.delete_user_space SP_UF
    R.is_nil spaces.get_space_by_name SP_UF
    R.eq installed_count(APP_UF), 0

-- ────────────────────────────────────────────────────────────────────────────
-- DÉFAUT 1 (c)(e) : cycle complet et renommage d'un espace au nom à point.
SP_CYC  = "aap_cyc.books_#{SUFFIX}"
SP_CYCB = "aap_cycauth_#{SUFFIX}"
SP_CYC2 = "aap_cyc.moved_#{SUFFIX}"
FLD_CYC = 'cod.e|x'
APP_CYC = "org.test.aapcyc_#{SUFFIX}"
FIXC = {}

retarget_esc = (key, old, new) ->
  for prefix in *{ 'field:', 'relation:', 'view:' }
    old_pref = "#{prefix}#{pkg.key_part old}."
    if key\sub(1, #old_pref) == old_pref
      return "#{prefix}#{pkg.key_part new}.#{key\sub(#old_pref + 1)}"
  nil

R.describe "app_apply — special names full cycle and space rename", ->

  R.it "creates spaces, a special field and a relation, then builds the package", ->
    cyc = spaces.create_user_space SP_CYC, 'cycle books'
    cycb = spaces.create_user_space SP_CYCB, 'cycle authors'
    FIXC.cyc_id = cyc.id
    FIXC.cycb_id = cycb.id
    spaces.add_field cyc.id, FLD_CYC, 'String', false, 'special field'
    fk = spaces.add_field cyc.id, 'author_id', 'Int', false, ''
    seq = spaces.add_field cycb.id, 'seq_id', 'Sequence'
    res = schema_r.Mutation.createRelation {}, {
      input: { name: "aap_cycrel_#{SUFFIX}", fromSpaceId: cyc.id, fromFieldId: fk.id,
               toSpaceId: cycb.id, toFieldId: seq.id, reprFormula: '@name',
               cardinality: 'many' }
    }, CTX
    FIXC.rel_id = res.id
    R.ok res
    FIXC.p1 = subset pkg.build_package {
      id: APP_CYC, name: 'Cycle', version: '1.0.0', description: ''
    }, {}
    R.ok FIXC.p1

  R.it "removes the local elements, then reinstalls the package", ->
    schema_r.Mutation.deleteRelation {}, { id: FIXC.rel_id }, CTX
    spaces.delete_user_space SP_CYC
    spaces.delete_user_space SP_CYCB
    R.is_nil spaces.get_space_by_name SP_CYC
    report = apply.apply_update FIXC.p1, {}, {}
    R.ok report.ok, report.error
    R.eq #describe_intact(FIXC.p1), 0, 'every delivered element matches the package'
    R.ok spaces.get_space_by_name SP_CYC, 'space recreated'
    sid = spaces.get_space_by_name(SP_CYC).id
    R.ok (field_by_name sid, FLD_CYC), 'special field recreated'
    R.ok pkg.describe_local('relation', "relation:#{pkg.key_part SP_CYC}.author_id"), 'relation recreated'

  R.it "renames the dotted space and remaps child keys", ->
    items = {}
    old_space_key = "space:#{pkg.key_part SP_CYC}"
    for it in *FIXC.p1.items
      if it.key == old_space_key
        table.insert items, {
          type: 'space'
          key: "space:#{pkg.key_part SP_CYC2}"
          content: it.content
          renamed_from: old_space_key
        }
        continue
      new_key = retarget_esc it.key, SP_CYC, SP_CYC2
      if new_key
        content = it.content
        if it.type == 'relation' and content.fromSpace == SP_CYC
          content = {
            fromSpace: SP_CYC2, fromField: content.fromField
            toSpace: content.toSpace, toField: content.toField
            cardinality: content.cardinality
          }
        entry = { type: it.type, key: new_key, content: content, renamed_from: it.key }
        table.insert items, entry
      else
        table.insert items, it
    p2 = {
      app: { id: APP_CYC, name: 'Cycle', version: '1.1.0', description: '' }
      items: items
      seed_keys: {}
    }
    report = apply.apply_update p2, {}, {}
    R.ok report.ok, report.error
    R.ok spaces.get_space_by_name(SP_CYC2), 'renamed space exists'
    R.is_nil spaces.get_space_by_name(SP_CYC), 'old space gone'
    nsid = spaces.get_space_by_name(SP_CYC2).id
    R.ok (field_by_name nsid, FLD_CYC), 'child field remapped to the new space'
    R.ok pkg.describe_local('field', "field:#{pkg.key_part SP_CYC2}.#{pkg.key_part FLD_CYC}")
    old_child = "field:#{pkg.key_part SP_CYC}.#{pkg.key_part FLD_CYC}"
    new_child = "field:#{pkg.key_part SP_CYC2}.#{pkg.key_part FLD_CYC}"
    R.is_nil box.space._tdb_app_items\get { APP_CYC, old_child }, 'old child untracked'
    R.ok box.space._tdb_app_items\get { APP_CYC, new_child }, 'new child tracked'

  R.it "cleans up the special-name cycle fixture", ->
    cyc = spaces.get_space_by_name SP_CYC2
    if cyc
      for t in *box.space._tdb_relations.index.by_from\select { cyc.id }
        box.space._tdb_relations\delete t[1]
    clean_app_rows APP_CYC
    spaces.delete_user_space SP_CYC2
    spaces.delete_user_space SP_CYCB
    R.is_nil spaces.get_space_by_name SP_CYC2
    R.is_nil spaces.get_space_by_name SP_CYCB

-- ────────────────────────────────────────────────────────────────────────────
-- T22 : normalisation à la frontière de lecture. Un paquet décodé par le vrai
-- parseur YAML de Tarantool (null → box.NULL, clés absentes) s'installe et se
-- met à jour sans erreur ; l'empreinte du paquet redevient égale à celle de
-- l'état local identique (aucun faux conflit).
-- ────────────────────────────────────────────────────────────────────────────
SP_T22   = "aap_t22_#{SUFFIX}"
SP_T22B  = "aap_t22b_#{SUFFIX}"
APP_T22  = "org.test.aapt22_#{SUFFIX}"
VIEW_T22 = "aap_t22view_#{SUFFIX}"
PAGE_T22 = "aap_t22page_#{SUFFIX}"
DV_T22   = "aap_t22dv_#{SUFFIX}"
PLG_T22  = "aap_t22plugin_#{SUFFIX}"
GRP_T22  = "aap_t22group_#{SUFFIX}"
REL_T22  = "aap_t22rel_#{SUFFIX}"
F22 = {}

YAML_PAGE_T22 = [[
layout:
  direction: vertical
  children:
    - widget:
        title: T22
        space: t22
]]

OPTIONAL_KEYS = {
  space: { 'description' }
  field: { 'description', 'formula', 'triggerFields', 'language' }
  relation: { 'cardinality' }
  page: { 'description' }
  dataview: { 'description' }
  plugin: { 'description', 'scriptLanguage', 'templateLanguage', 'scriptCode', 'templateCode' }
  group: { 'description' }
}

_sparse_content = (item_type, content, mode) ->
  copy = {}
  for k, v in pairs content
    copy[k] = v
  for k in *(OPTIONAL_KEYS[item_type] or {})
    if mode == 'null'
      copy[k] = box.NULL if copy[k] != nil
    else
      copy[k] = nil
  copy

sparse_pkg = (package, mode) ->
  items = {}
  for it in *package.items
    table.insert items, {
      type: it.type
      key: it.key
      content: _sparse_content it.type, it.content, mode
    }
  { app: package.app, items: items, seed_keys: package.seed_keys or {} }

roundtrip = (package) ->
  decoded = yaml.decode yaml.encode(package)
  norm, err = apply.load_package decoded
  R.ok norm, "load_package: #{err}"
  norm

remove_t22 = ->
  for v in *box.space._tdb_views\select {}
    views.delete_view v[1] if v[3] == VIEW_T22
  for dv in *box.space._tdb_data_views\select {}
    data_views.delete_view dv[1] if dv[2] == DV_T22
  for cv in *box.space._tdb_custom_views\select {}
    box.space._tdb_custom_views\delete cv[1] if cv[2] == PAGE_T22
  for wp in *box.space._tdb_widget_plugins\select {}
    box.space._tdb_widget_plugins\delete wp[1] if wp[2] == PLG_T22
  for g in *perms.list_groups!
    perms.delete_group g.id if g.name == GRP_T22
  for nm in *{ SP_T22, SP_T22B }
    sp = spaces.get_space_by_name nm
    if sp
      for t in *box.space._tdb_relations.index.by_from\select { sp.id }
        box.space._tdb_relations\delete t[1]
      for t in *box.space._tdb_relations.index.by_to\select { sp.id }
        box.space._tdb_relations\delete t[1]
  spaces.delete_user_space SP_T22
  spaces.delete_user_space SP_T22B

R.describe "app_apply — T22 fixture", ->

  R.it "creates every element type with default optional values", ->
    books = spaces.create_user_space SP_T22, ''
    authors = spaces.create_user_space SP_T22B, ''
    spaces.add_field books.id, 'code', 'String', true, ''
    fk = spaces.add_field books.id, 'author_id', 'Int', false, ''
    seq = spaces.add_field authors.id, 'seq_id', 'Sequence'
    res = schema_r.Mutation.createRelation {}, {
      input: { name: REL_T22, fromSpaceId: books.id, fromFieldId: fk.id,
               toSpaceId: authors.id, toFieldId: seq.id, reprFormula: '@seq_id',
               cardinality: 'one' }
    }, CTX
    F22.rel_id = res.id
    v = views.create_view books.id, VIEW_T22, 'grid', { layout: { direction: 'vertical', children: {} } }
    F22.view_id = v.id
    p = cvr.Mutation.createCustomView {}, { name: PAGE_T22, description: '', yaml: YAML_PAGE_T22 }, CTX
    F22.page_id = p.id
    dv = dv_r.Mutation.createDataView nil, {
      input: { name: DV_T22, description: '', sourceSpace: SP_T22,
               config: json.encode { columns: { 'code' } } }
    }, CTX
    F22.dv_id = dv.id
    now = os.time!
    F22.plugin_id = "aap_t22plugin_id_#{SUFFIX}"
    box.space._tdb_widget_plugins\insert {
      F22.plugin_id, PLG_T22, '', 'coffeescript', 'pug', '', '', now, now
    }
    g = perms.create_group GRP_T22, ''
    F22.group_id = g.id
    perms.grant g.id, 'space', books.id, 'read'
    perms.grant g.id, 'space', nil, 'write'
    for row in *{ { code: 'T22-1', author_id: 0 }, { code: 'T22-2', author_id: 0 } }
      data_r.Mutation.insertRecord {}, { spaceId: books.id, data: row }, CTX
    F22.seed = { [SP_T22]: 'code' }
    R.ok books and authors and res and v and p and dv and F22.plugin_id and g

R.describe "app_apply — T22 export round-trip invariant", ->

  R.it "a build_package YAML round-trip is entirely unchanged", ->
    F22.pkg = subset pkg.build_package {
      id: APP_T22, name: 'T22', version: '1.0.0', description: ''
    }, { seed: F22.seed }
    F22.norm = roundtrip F22.pkg
    plan = apply.preview_update F22.norm
    R.eq #plan.errors, 0, 'preview errors'
    R.eq #plan.update, 0, 'no spurious update'
    R.eq #plan.conflict, 0, 'no spurious conflict'
    R.eq #plan.create, 0, 'no spurious create'
    R.eq #plan.unchanged, #F22.norm.items, 'all unchanged'

  R.it "nulled and dropped optional keys are still entirely unchanged", ->
    for mode in *{ 'null', 'drop' }
      norm = roundtrip sparse_pkg F22.pkg, mode
      plan = apply.preview_update norm
      R.eq #plan.errors, 0, "errors (#{mode})"
      R.eq #plan.update, 0, "update (#{mode})"
      R.eq #plan.conflict, 0, "conflict (#{mode})"
      R.eq #plan.unchanged, #norm.items, "unchanged (#{mode})"

R.describe "app_apply — T22 install and update through yaml", ->

  R.it "installs a nulled package on a clean base", ->
    remove_t22!
    clean_app_rows APP_T22
    R.is_nil spaces.get_space_by_name SP_T22
    F22.norm2 = roundtrip sparse_pkg F22.pkg, 'null'
    report = apply.apply_update F22.norm2, {}, {}
    R.ok report.ok, report.error
    R.eq #report.created, #F22.norm2.items, 'created'
    R.eq #describe_intact(F22.norm2), 0, 'all delivered elements match'

  R.it "a real author change stays an update", ->
    changed = sparse_pkg F22.pkg, 'null'
    for it in *changed.items
      it.content.description = 'author changed' if it.key == "space:#{SP_T22}"
    norm = roundtrip changed
    plan = apply.preview_update norm
    R.eq #plan.errors, 0
    R.eq #plan.update, 1, 'one update'
    R.eq plan.update[1].key, "space:#{SP_T22}"

  R.it "updates a page and a data view delivered with a null description", ->
    local_pkg = subset pkg.build_package {
      id: APP_T22, name: 'T22', version: '1.1.0', description: ''
    }, { seed: F22.seed }
    changed = sparse_pkg local_pkg, 'null'
    for it in *changed.items
      if it.key == "page:#{PAGE_T22}"
        it.content.yaml = "#{it.content.yaml}\n# changed\n"
      if it.key == "dataview:#{DV_T22}"
        it.content.config = json.encode { columns: { 'code', 'author_id' } }
    norm = roundtrip changed
    plan = apply.preview_update norm
    R.eq #plan.errors, 0, 'preview errors'
    R.eq #plan.update, 2, 'page and data view update'
    report = apply.apply_update norm, {}, {}
    R.ok report.ok, report.error
    R.eq #report.updated, 2, 'updated'
    R.eq pkg.describe_local('page', "page:#{PAGE_T22}").description, ''
    R.eq pkg.describe_local('dataview', "dataview:#{DV_T22}").description, ''

R.describe "app_apply — T22 cleanup", ->

  R.it "removes the T22 fixture", ->
    clean_app_rows APP_T22
    remove_t22!
    R.is_nil spaces.get_space_by_name SP_T22
    R.is_nil spaces.get_space_by_name SP_T22B
    R.is_nil pkg.describe_local('page', "page:#{PAGE_T22}")
    R.is_nil pkg.describe_local('dataview', "dataview:#{DV_T22}")
    R.is_nil pkg.describe_local('plugin', "plugin:#{PLG_T22}")
    R.is_nil pkg.describe_local('group', "group:#{GRP_T22}")
    R.eq installed_count(APP_T22), 0
