-- tests/test_app_lifecycle_parts.moon
-- Tests d'intégration V3b du cycle de vie d'une app (spec §1-§4, plan « Étape 4 ») :
--   PARTIE 1 — marquage des obsolètes
--   PARTIE 2 — lignes seed
--   PARTIE 3 — renommages (renamed_from)
--   PARTIE 4 — aperçu des pertes et purge
-- Fixture autonome (suffixe propre) ; tourne dans l'instance de test Tarantool.

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

SP_B = "v3b_books_#{SUFFIX}"
SP_A = "v3b_authors_#{SUFFIX}"
VIEW_N = "v3b_view_#{SUFFIX}"
PAGE_N = "v3b_page_#{SUFFIX}"
DV_N   = "v3b_dv_#{SUFFIX}"
PLUG_N = "v3b_plugin_#{SUFFIX}"
GROUP_N= "v3b_group_#{SUFFIX}"
REL_N  = "v3b_rel_#{SUFFIX}"
APP_ID = "org.test.v3b_#{SUFFIX}"

KEY_CODE  = "field:#{SP_B}.code"
KEY_TITLE = "field:#{SP_B}.title"
KEY_QTY   = "field:#{SP_B}.qty"
KEY_NOTE  = "field:#{SP_B}.note"
KEY_PAGE  = "page:#{PAGE_N}"

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

YAML_PAGE = [[
layout:
  direction: vertical
  children:
    - widget:
        title: v3b
        space: v3b_books
]]

FIX = {}
seed_opts = {}
META = { id: APP_ID, name: 'V3b fixture', version: '1.0.0', description: 'v3b' }

-- ── Helpers ─────────────────────────────────────────────────────────────────

subset = (package) ->
  items = [it for it in *package.items when it.key\find SUFFIX, 1, true]
  { app: package.app, items: items, seed_keys: package.seed_keys or {} }

non_seed = (package) ->
  [it for it in *package.items when it.type != 'seed']

without = (package, item_key) ->
  items = [it for it in *package.items when it.key != item_key]
  { app: package.app, items: items, seed_keys: package.seed_keys or {} }

reversion = (package, version) ->
  { app: { id: package.app.id, name: package.app.name, version: version,
           description: package.app.description },
    items: package.items, seed_keys: package.seed_keys or {} }

seed_count = (package) ->
  n = 0
  n += 1 for it in *package.items when it.type == 'seed'
  n

row_dump = (space_name) ->
  rows = {}
  sp = box.space["data_#{space_name}"]
  return rows unless sp
  for t in *sp\select {}
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    table.insert rows, json.encode d
  table.sort rows
  rows

local_rows = (space_name) ->
  rows = {}
  sp = box.space["data_#{space_name}"]
  return rows unless sp
  for t in *sp\select {}
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    table.insert rows, d
  rows

count_rows = (space_name) ->
  sp = box.space["data_#{space_name}"]
  sp and #sp\select({}) or 0

item_state = (app_id, key) ->
  t = box.space._tdb_app_items\get { app_id, key }
  t and t[6] or nil

item_row = (app_id, key) ->
  box.space._tdb_app_items\get { app_id, key }

count_items = (app_id) ->
  #box.space._tdb_app_items.index.by_app\select { app_id }

clean_app = ->
  for t in *box.space._tdb_app_items.index.by_app\select { APP_ID }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete APP_ID

field_by_name = (space_id, name) ->
  for f in *spaces.list_fields space_id
    return f if f.name == name
  nil

find_record = (space_name, key_field, key_val) ->
  sp = box.space["data_#{space_name}"]
  return nil unless sp
  for t in *sp\select {}
    d = if type(t[2]) == 'string' then json.decode(t[2]) else t[2]
    return { id: t[1], data: d } if d[key_field] != nil and tostring(d[key_field]) == tostring(key_val)
  nil

non_seed_rows = (space_name, key_field) ->
  n = 0
  for d in *local_rows space_name
    n += 1 if d[key_field] == nil
  n

set_seed = (package, space, key, data) ->
  items = {}
  found = false
  for it in *package.items
    if it.type == 'seed' and it.content.space == space and tostring(it.content.key) == tostring(key)
      table.insert items, { type: 'seed', key: it.key, content: { space: space, key: key, data: data } }
      found = true
    else
      table.insert items, it
  unless found
    table.insert items, { type: 'seed', key: "seed:#{space}|#{key}",
                          content: { space: space, key: key, data: data } }
  { app: package.app, items: items, seed_keys: package.seed_keys }

in_list = (list, key) ->
  for k in *list
    return true if k == key
  false

-- ── Fixture : construire tous les éléments localement, puis le paquet ────────
R.describe "v3b — fixture", ->

  R.it "creates spaces, fields, relation and data", ->
    books = spaces.create_user_space SP_B, 'v3b books'
    authors = spaces.create_user_space SP_A, 'v3b authors'
    FIX.books_id = books.id
    FIX.authors_id = authors.id
    spaces.add_field books.id, 'code', 'String', false, 'natural key'
    spaces.add_field books.id, 'title', 'String', false, ''
    spaces.add_field books.id, 'qty', 'Int', false, ''
    fk = spaces.add_field books.id, 'author_id', 'Int', false, ''
    seq = spaces.add_field authors.id, 'seq_id', 'Sequence'
    spaces.add_field authors.id, 'name', 'String', false, ''
    res = schema_r.Mutation.createRelation {}, {
      input: { name: REL_N, fromSpaceId: books.id, fromFieldId: fk.id,
               toSpaceId: authors.id, toFieldId: seq.id, reprFormula: '@name' }
    }, CTX
    FIX.fk_id = fk.id
    FIX.rel_id = res.id
    for row in *{ { code: 'V3B-1', title: 'Premier', qty: 2 },
                  { code: 'V3B-2', title: 'Second', qty: 5 } }
      data_r.Mutation.insertRecord {}, { spaceId: books.id, data: row }, CTX
    R.ok res

  R.it "creates a view, a page, a data view, a plugin, a group and permissions", ->
    v = views.create_view FIX.books_id, VIEW_N, 'grid',
      { layout: { direction: 'vertical', children: {} } }
    FIX.view_id = v.id
    p = cvr.Mutation.createCustomView {}, { name: PAGE_N, description: 'v3b page', yaml: YAML_PAGE }, CTX
    FIX.page_id = p.id
    dv = dv_r.Mutation.createDataView nil, {
      input: { name: DV_N, description: 'v3b dv', sourceSpace: SP_B,
               config: json.encode { columns: { 'code', 'title' } } }
    }, CTX
    FIX.dv_id = dv.id
    wp = wpr.Mutation.createWidgetPlugin {}, {
      input: { name: PLUG_N, description: 'v3b plugin', scriptLanguage: 'coffeescript',
               templateLanguage: 'pug', scriptCode: "render 'ok'", templateCode: 'div ok' }
    }, CTX
    FIX.plugin_id = wp.id
    g = perms.create_group GROUP_N, 'v3b group'
    FIX.group_id = g.id
    perms.grant g.id, 'space', FIX.books_id, 'read'
    R.ok v and p and dv and wp and g

  R.it "builds the package v1.0.0 with two seed lines", ->
    seed_opts[SP_B] = 'code'
    FIX.PKG = subset pkg.build_package META, { seed: seed_opts }
    R.eq seed_count(FIX.PKG), 2, 'two seed items'

-- ── Installation (base vidée de ses éléments) ────────────────────────────────
remove_elements = ->
  schema_r.Mutation.deleteRelation {}, { id: FIX.rel_id }, CTX if FIX.rel_id
  views.delete_view FIX.view_id if FIX.view_id
  box.space._tdb_custom_views\delete FIX.page_id if FIX.page_id
  data_views.delete_view FIX.dv_id if FIX.dv_id
  box.space._tdb_widget_plugins\delete FIX.plugin_id if FIX.plugin_id
  perms.delete_group FIX.group_id if FIX.group_id
  spaces.delete_user_space SP_B
  spaces.delete_user_space SP_A
  FIX.rel_id = nil
  FIX.view_id = nil
  FIX.page_id = nil
  FIX.dv_id = nil
  FIX.plugin_id = nil
  FIX.group_id = nil

R.describe "v3b — installation", ->

  R.it "empties the local elements and installs the package", ->
    remove_elements!
    report = apply.apply_update FIX.PKG, {}, {}
    R.ok report.ok, report.error
    R.eq box.space._tdb_apps\get(APP_ID)[3], '1.0.0', 'installed version'
    R.eq count_items(APP_ID), #FIX.PKG.items, 'all items tracked'
    R.eq count_rows(SP_B), seed_count(FIX.PKG), 'seed rows inserted on first install'

-- ── PARTIE 1 : obsolètes ─────────────────────────────────────────────────────
R.describe "v3b partie 1 — obsolètes", ->

  R.it "marks a page removed from the package as obsolete, keeping it locally", ->
    before_rows = count_rows SP_B
    PKG2 = reversion without(FIX.PKG, KEY_PAGE), '1.1.0'
    report = apply.apply_update PKG2, {}, {}
    R.ok report.ok, report.error
    R.eq item_state(APP_ID, KEY_PAGE), 'obsolète', 'page marked obsolete'
    R.ok pkg.describe_local('page', KEY_PAGE), 'page still present locally'
    R.eq count_rows(SP_B), before_rows, 'no record lost'

  R.it "reactivates the item when it reappears in a package", ->
    PKG3 = reversion FIX.PKG, '1.2.0'
    report = apply.apply_update PKG3, {}, {}
    R.ok report.ok, report.error
    R.eq item_state(APP_ID, KEY_PAGE), 'actif', 'page active again'

-- ── PARTIE 2 : lignes seed ───────────────────────────────────────────────────
R.describe "v3b partie 2 — lignes seed", ->

  R.it "prepares: one non-seed local record and one locally modified seed", ->
    sid = spaces.get_space_by_name(SP_B).id
    data_r.Mutation.insertRecord {}, { spaceId: sid, data: { title: 'hors seed', qty: 9 } }, CTX
    rec = find_record SP_B, 'code', 'V3B-2'
    R.ok rec, 'seed V3B-2 exists'
    rec.data.title = 'Local second'
    box.space["data_#{SP_B}"]\replace { rec.id, json.encode rec.data }
    FIX.non_seed_before = non_seed_rows SP_B, 'code'
    FIX.rows_before = count_rows SP_B
    R.eq FIX.non_seed_before, 1, 'one non-seed record'

  R.it "adds new seed lines, updates unchanged ones and keeps locally modified ones", ->
    PKG_A = reversion FIX.PKG, '1.3.0'
    PKG_A = set_seed PKG_A, SP_B, 'V3B-1', { code: 'V3B-1', title: 'Delivered premier', qty: 2 }
    PKG_A = set_seed PKG_A, SP_B, 'V3B-2', { code: 'V3B-2', title: 'Delivered second', qty: 5 }
    PKG_A = set_seed PKG_A, SP_B, 'V3B-3', { code: 'V3B-3', title: 'Nouveau', qty: 7 }
    report = apply.apply_update PKG_A, {}, {}
    R.ok report.ok, report.error
    R.ok in_list(report.created, "seed:#{SP_B}|V3B-3"), 'new seed created'
    R.ok in_list(report.updated, "seed:#{SP_B}|V3B-1"), 'unchanged seed updated'
    R.ok in_list(report.kept, "seed:#{SP_B}|V3B-2"), 'locally modified seed kept'
    R.eq item_state(APP_ID, "seed:#{SP_B}|V3B-1"), 'actif'

  R.it "propagates the delivered data and preserves local and non-seed records", ->
    R.eq (find_record SP_B, 'code', 'V3B-1').data.title, 'Delivered premier'
    R.eq (find_record SP_B, 'code', 'V3B-2').data.title, 'Local second', 'local kept'
    R.eq (find_record SP_B, 'code', 'V3B-3').data.title, 'Nouveau'
    R.eq non_seed_rows(SP_B, 'code'), FIX.non_seed_before, 'non-seed record count unchanged'
    R.eq count_rows(SP_B), FIX.rows_before + 1, 'exactly one seed line added, none removed'

-- ── Nettoyage ────────────────────────────────────────────────────────────────
R.describe "v3b — cleanup", ->

  R.it "removes the fixture elements and tracking rows", ->
    sid = spaces.get_space_by_name SP_B
    if sid
      for t in *box.space._tdb_relations.index.by_from\select { sid.id }
        box.space._tdb_relations\delete t[1]
      for t in *box.space._tdb_relations.index.by_to\select { sid.id }
        box.space._tdb_relations\delete t[1]
    for v in *box.space._tdb_views\select {}
      views.delete_view v[1] if v[3] == VIEW_N
    for dv in *box.space._tdb_data_views\select {}
      data_views.delete_view dv[1] if dv[2] == DV_N
    for cv in *box.space._tdb_custom_views\select {}
      box.space._tdb_custom_views\delete cv[1] if cv[2] == PAGE_N
    for wp in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete wp[1] if wp[2] == PLUG_N
    for g in *perms.list_groups!
      perms.delete_group g.id if g.name == GROUP_N
    clean_app!
    spaces.delete_user_space SP_B
    spaces.delete_user_space SP_A
    R.is_nil spaces.get_space_by_name SP_B

{ :FIX, :APP_ID, :SP_B, :SP_A, :KEY_CODE, :KEY_TITLE, :KEY_QTY, :KEY_NOTE,
  :KEY_PAGE, :VIEW_N, :PAGE_N, :DV_N, :PLUG_N, :GROUP_N, :REL_N, :CTX,
  :subset, :without, :reversion, :seed_count, :row_dump, :local_rows,
  :count_rows, :item_state, :item_row, :count_items, :clean_app, :field_by_name }
