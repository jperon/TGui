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
view_presets = require 'core.view_presets'
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

-- Named view preset attached to a widget of the page: its package key and
-- scope name the PAGE, so renaming the page moves them.
PRESET_N   = "v3b:preset_#{SUFFIX}"
WIDGET_N   = 'w_0000d00d'
SCOPE_N    = "widget:#{PAGE_N}:#{WIDGET_N}"
PRESET_KEY = "preset:#{pkg.key_part SCOPE_N}|#{pkg.key_part PRESET_N}"

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
    - widget:
        title: Custom
        space: v3b_books
        type: ]] .. PLUG_N .. [[
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

-- The stored row of the fixture preset, located by (local scope, name). The
-- local ids change on reinstallation, so the row is never located by id.
preset_row = (page_name) ->
  page = box.space._tdb_custom_views.index.by_name\get page_name
  return nil unless page
  box.space._tdb_view_presets.index.by_scope_name\get { "widget:#{page[1]}:#{WIDGET_N}", PRESET_N }

build_current = (version) ->
  meta = { id: APP_ID, name: 'V3b fixture', version: version, description: 'v3b' }
  subset pkg.build_package meta, { seed: seed_opts }

rename_item = (package, old_key, new_key) ->
  items = {}
  for it in *package.items
    if it.key == old_key
      table.insert items, { type: it.type, key: new_key, content: it.content, renamed_from: old_key }
    else
      table.insert items, it
  { app: package.app, items: items, seed_keys: package.seed_keys }

-- A real author republishes the preset under the new page name: the preset key
-- and its scope name the page, so both move with the page rename.
rename_page_preset = (package, old_key, new_key, new_scope) ->
  items = {}
  for it in *package.items
    if it.type == 'preset' and it.key == old_key
      content = { scope: new_scope, space: it.content.space, name: it.content.name,
                  filter: it.content.filter, sort: it.content.sort }
      table.insert items, { type: 'preset', key: new_key, content: content, renamed_from: old_key }
    else
      table.insert items, it
  { app: package.app, items: items, seed_keys: package.seed_keys }

str_after = (key, prefix) ->
  return nil unless key\sub(1, #prefix) == prefix
  rest = key\sub #prefix + 1
  rest != '' and rest or nil

retarget_key = (key, old_space, new_space) ->
  for prefix in *{ 'field:', 'relation:', 'view:' }
    rest = str_after key, "#{prefix}#{old_space}."
    return "#{prefix}#{new_space}.#{rest}" if rest
  rest = str_after key, "seed:#{old_space}|"
  return "seed:#{new_space}|#{rest}" if rest
  key

rename_space_pkg = (package, old_space, new_space) ->
  items = {}
  for it in *package.items
    if it.type == 'space' and it.key == "space:#{old_space}"
      table.insert items, { type: 'space', key: "space:#{new_space}",
                            content: it.content, renamed_from: it.key }
      continue
    new_key = retarget_key it.key, old_space, new_space
    content = it.content
    if it.type == 'relation' and content.toSpace == old_space
      content = { fromSpace: content.fromSpace, fromField: content.fromField,
                  toSpace: new_space, toField: content.toField }
    if it.type == 'dataview' and content.sourceSpace == old_space
      content = { name: content.name, description: content.description,
                  sourceSpace: new_space, config: content.config }
    renamed = new_key != it.key
    if renamed or content != it.content
      entry = { type: it.type, key: new_key, content: content }
      entry.renamed_from = it.key if renamed
      table.insert items, entry
    else
      table.insert items, it
  { app: package.app, items: items, seed_keys: package.seed_keys }

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
    preset = view_presets.save_preset "widget:#{p.id}:#{WIDGET_N}", FIX.books_id,
      PRESET_N, 'self.qty > 1', '[]'
    FIX.preset_id = preset.id
    g = perms.create_group GROUP_N, 'v3b group'
    FIX.group_id = g.id
    perms.grant g.id, 'space', FIX.books_id, 'read'
    R.ok v and p and dv and wp and g and preset

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

-- ── PARTIE 3 : renommages (renamed_from) ─────────────────────────────────────
SP_A2   = "#{SP_A}_ren"
PAGE_N2 = "#{PAGE_N}2"
PLUG_N2 = "#{PLUG_N}2"
PRESET_KEY2 = "preset:#{pkg.key_part "widget:#{PAGE_N2}:#{WIDGET_N}"}|#{pkg.key_part PRESET_N}"

R.describe "v3b partie 3 — renommages", ->

  R.it "renames a field in place and keeps values under the new name", ->
    sid = spaces.get_space_by_name(SP_A).id
    data_r.Mutation.insertRecord {}, { spaceId: sid, data: { name: 'Alice' } }, CTX
    R.ok (find_record SP_A, 'name', 'Alice'), 'author record inserted'
    base = build_current '1.4.0'
    PKG_F = reversion (rename_item base, "field:#{SP_A}.name", "field:#{SP_A}.nom"), '1.4.0'
    report = apply.apply_update PKG_F, {}, {}
    R.ok report.ok, report.error
    R.ok pkg.describe_local('field', "field:#{SP_A}.nom"), 'new field present'
    R.is_nil pkg.describe_local('field', "field:#{SP_A}.name"), 'old field gone'
    rec = find_record SP_A, 'nom', 'Alice'
    R.ok rec, 'value preserved under the new key'
    R.is_nil rec.data.name, 'old JSON key removed'
    R.eq item_state(APP_ID, "field:#{SP_A}.nom"), 'actif'
    R.is_nil item_row(APP_ID, "field:#{SP_A}.name")

  R.it "renames a page and a plugin in place", ->
    base = build_current '1.5.0'
    PKG_P = rename_item base, "page:#{PAGE_N}", "page:#{PAGE_N2}"
    PKG_P = rename_item PKG_P, "plugin:#{PLUG_N}", "plugin:#{PLUG_N2}"
    PKG_P = rename_page_preset PKG_P, PRESET_KEY, PRESET_KEY2,
      "widget:#{PAGE_N2}:#{WIDGET_N}"
    report = apply.apply_update PKG_P, {}, {}
    R.ok report.ok, report.error
    R.ok pkg.describe_local('page', "page:#{PAGE_N2}"), 'page renamed'
    R.is_nil pkg.describe_local('page', "page:#{PAGE_N}"), 'old page gone'
    R.ok pkg.describe_local('plugin', "plugin:#{PLUG_N2}"), 'plugin renamed'
    R.is_nil pkg.describe_local('plugin', "plugin:#{PLUG_N}"), 'old plugin gone'
    -- The preset is keyed by the page name: its key and scope follow the page,
    -- its local row keeps the page id.
    R.ok pkg.describe_local('preset', PRESET_KEY2), 'preset follows the renamed page'
    R.is_nil pkg.describe_local('preset', PRESET_KEY), 'old preset key gone'
    R.eq item_state(APP_ID, PRESET_KEY2), 'actif', 'preset tracked under the new key'
    R.is_nil item_row(APP_ID, PRESET_KEY), 'old key untracked'
    R.ok preset_row(PAGE_N2), 'preset row kept'

  R.it "renames a space in place, remapping child keys and preserving records", ->
    before = local_rows SP_A
    PKG_S = reversion (rename_space_pkg (build_current '1.6.0'), SP_A, SP_A2), '2.0.0'
    FIX.pkg_s = PKG_S
    dbg = apply.preview_update PKG_S
    R.eq #dbg.create, 0, 'rename is previewed as a rename, not a creation'
    R.eq #dbg.rename, 3, 'space plus two child fields renamed'
    R.is_nil box.space._tdb_spaces.index.by_name\get(SP_A2), 'SP_A2 absent before apply'
    report = apply.apply_update PKG_S, {}, {}
    R.ok report.ok, report.error
    R.ok spaces.get_space_by_name(SP_A2), 'new space exists'
    R.is_nil spaces.get_space_by_name(SP_A), 'old space gone'
    R.ok box.space["data_#{SP_A2}"], 'new data space exists'
    R.is_nil box.space["data_#{SP_A}"], 'old data space gone'
    R.eq #local_rows(SP_A2), #before, 'records preserved'
    R.ok (find_record SP_A2, 'nom', 'Alice'), 'author record preserved'
    R.ok pkg.describe_local('field', "field:#{SP_A2}.nom"), 'child field remapped'
    R.is_nil item_row(APP_ID, "field:#{SP_A}.nom"), 'old child key untracked'
    R.eq item_state(APP_ID, "space:#{SP_A2}"), 'actif'

  R.it "a further update with the same package recreates nothing", ->
    report = apply.apply_update FIX.pkg_s, {}, {}
    R.ok report.ok, report.error
    R.eq #report.created, 0, 'nothing recreated'
    R.eq item_state(APP_ID, "space:#{SP_A2}"), 'actif'

  R.it "refuses a rename whose target already exists locally", ->
    cvr.Mutation.createCustomView {}, { name: "#{PAGE_N2}_tgt", description: 'taken', yaml: '' }, CTX
    before_version = box.space._tdb_apps\get(APP_ID)[3]
    PKG_C = reversion (rename_item (build_current '2.1.0'), "page:#{PAGE_N2}", "page:#{PAGE_N2}_tgt"), '2.1.0'
    report = apply.apply_update PKG_C, {}, {}
    R.nok report.ok
    R.matches report.error, 'already exists locally'
    R.eq box.space._tdb_apps\get(APP_ID)[3], before_version, 'no write'

-- ── PARTIE 4 : aperçu des pertes et purge ────────────────────────────────────
R.describe "v3b partie 4 — aperçu des pertes et purge", ->

  R.it "makes a field obsolete and previews its losses exactly, without writing", ->
    sid = spaces.get_space_by_name(SP_B).id
    spaces.add_field sid, 'legacy', 'String', false, ''
    sp = box.space["data_#{SP_B}"]
    n = 0
    for t in *sp\select {}
      d = json.decode t[2]
      if n < 2
        d.legacy = "v#{n}"
        sp\replace { t[1], json.encode d }
      n += 1
    R.ok (apply.apply_update (build_current '2.1.0'), {}, {}).ok, 'legacy field installed'
    PKG_N = reversion (without (build_current '2.2.0'), "field:#{SP_B}.legacy"), '2.2.0'
    R.ok (apply.apply_update PKG_N, {}, {}).ok, 'legacy field removed from the package'
    R.eq item_state(APP_ID, "field:#{SP_B}.legacy"), 'obsolète'
    R.ok field_by_name(sid, 'legacy'), 'field still present locally'
    pv = apply.preview_purge APP_ID, { "field:#{SP_B}.legacy" }
    R.is_nil pv.error
    R.eq #pv.losses, 1
    R.eq pv.losses[1].type, 'field'
    R.eq pv.losses[1].records, 2
    R.eq pv.total_records, 2
    R.ok field_by_name(sid, 'legacy'), 'preview wrote nothing'

  R.it "refuses to purge an active or unknown item and requires confirmation", ->
    sid = spaces.get_space_by_name(SP_B).id
    r = apply.purge_obsolete APP_ID, { "field:#{SP_B}.title" }, { confirmed: true }
    R.nok r.ok
    R.matches r.error, 'not obsolete'
    R.is_nil r.purged[1]
    pv = apply.preview_purge APP_ID, { "field:#{SP_B}.local_xyz" }
    R.matches pv.error, 'unknown app item'
    r2 = apply.purge_obsolete APP_ID, { "field:#{SP_B}.legacy" }, {}
    R.nok r2.ok
    R.matches r2.error, 'confirmation required'
    R.ok field_by_name(sid, 'legacy'), 'no purge without confirmation'

  R.it "purges an obsolete field: removes the key from records and nothing else", ->
    sid = spaces.get_space_by_name(SP_B).id
    rows_before = count_rows SP_B
    r = apply.purge_obsolete APP_ID, { "field:#{SP_B}.legacy" }, { confirmed: true }
    R.ok r.ok, r.error
    R.is_nil field_by_name(sid, 'legacy')
    R.is_nil item_row(APP_ID, "field:#{SP_B}.legacy")
    R.eq count_rows(SP_B), rows_before, 'record count unchanged'
    has = false
    for row in *local_rows SP_B
      has = true if row.legacy != nil
    R.nok has, 'legacy key removed from every record'
    R.ok field_by_name(sid, 'title'), 'other fields untouched'

  R.it "marks a preset removed from the package obsolete, then purges it", ->
    PKG_O = reversion (without (build_current '2.2.5'), PRESET_KEY2), '2.2.5'
    r = apply.apply_update PKG_O, {}, {}
    R.ok r.ok, r.error
    R.eq item_state(APP_ID, PRESET_KEY2), 'obsolète', 'preset marked obsolete'
    R.ok preset_row(PAGE_N2), 'preset never deleted by an update'
    pv = apply.preview_purge APP_ID, { PRESET_KEY2 }
    R.is_nil pv.error
    R.eq #pv.losses, 1
    R.eq pv.losses[1].type, 'preset'
    rp = apply.purge_obsolete APP_ID, { PRESET_KEY2 }, { confirmed: true }
    R.ok rp.ok, rp.error
    R.is_nil preset_row(PAGE_N2)
    R.is_nil item_row(APP_ID, PRESET_KEY2)

  R.it "purges an obsolete space after its relation", ->
    base = build_current '2.3.0'
    pkg_r = reversion (without (without base, "relation:#{SP_B}.author_id"), "space:#{SP_A2}"), '2.3.0'
    r = apply.apply_update pkg_r, {}, {}
    R.ok r.ok, r.error
    R.eq item_state(APP_ID, "relation:#{SP_B}.author_id"), 'obsolète'
    R.eq item_state(APP_ID, "space:#{SP_A2}"), 'obsolète'
    R.ok (apply.purge_obsolete APP_ID, { "relation:#{SP_B}.author_id" }, { confirmed: true }).ok
    pv = apply.preview_purge APP_ID, { "space:#{SP_A2}" }
    R.is_nil pv.error
    R.eq pv.losses[1].records, 1
    R.eq pv.losses[1].fields, 2
    R.eq pv.losses[1].relations, 0
    rp = apply.purge_obsolete APP_ID, { "space:#{SP_A2}" }, { confirmed: true }
    R.ok rp.ok, rp.error
    R.is_nil spaces.get_space_by_name(SP_A2)
    R.is_nil box.space["data_#{SP_A2}"]
    R.is_nil item_row(APP_ID, "space:#{SP_A2}")
    R.is_nil item_row(APP_ID, "field:#{SP_A2}.nom")

  R.it "rolls back a purge that fails in the middle", ->
    sid = spaces.get_space_by_name(SP_B).id
    f = spaces.add_field sid, 'legacy2', 'String', false, ''
    sp = box.space["data_#{SP_B}"]
    for t in *sp\select {}
      d = json.decode t[2]
      if d.legacy2 == nil and d.code == 'V3B-1'
        d.legacy2 = 'keepme'
        sp\replace { t[1], json.encode d }
    box.space._tdb_app_items\replace { APP_ID, "field:#{SP_B}.legacy2", 'field', f.id, 'fp', 'obsolète', '2.3.0' }
    box.space._tdb_app_items\replace { APP_ID, "page:#{PAGE_N2}_ghost", 'page', '', 'fp', 'obsolète', '2.3.0' }
    r = apply.purge_obsolete APP_ID,
      { "field:#{SP_B}.legacy2", "page:#{PAGE_N2}_ghost" }, { confirmed: true }
    R.nok r.ok
    R.matches r.error, 'missing local_id'
    R.ok field_by_name(sid, 'legacy2'), 'field restored by rollback'
    R.ok (find_record SP_B, 'legacy2', 'keepme'), 'value preserved through rollback'
    R.eq item_state(APP_ID, "field:#{SP_B}.legacy2"), 'obsolète', 'tracking restored'

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
      views.delete_view v[1] if v[3]\find(VIEW_N, 1, true)
    for dv in *box.space._tdb_data_views\select {}
      data_views.delete_view dv[1] if dv[2]\find(DV_N, 1, true)
    for cv in *box.space._tdb_custom_views\select {}
      box.space._tdb_custom_views\delete cv[1] if cv[2]\find(PAGE_N, 1, true)
    for wp in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete wp[1] if wp[2]\find(PLUG_N, 1, true)
    for vp in *box.space._tdb_view_presets\select {}
      box.space._tdb_view_presets\delete vp[1] if vp[4] == PRESET_N
    for g in *perms.list_groups!
      perms.delete_group g.id if g.name == GROUP_N
    clean_app!
    spaces.delete_user_space SP_B
    spaces.delete_user_space SP_A
    spaces.delete_user_space SP_A2
    R.is_nil spaces.get_space_by_name SP_B
    R.is_nil spaces.get_space_by_name SP_A2

{ :FIX, :APP_ID, :SP_B, :SP_A, :KEY_CODE, :KEY_TITLE, :KEY_QTY, :KEY_NOTE,
  :KEY_PAGE, :VIEW_N, :PAGE_N, :DV_N, :PLUG_N, :GROUP_N, :REL_N, :CTX,
  :subset, :without, :reversion, :seed_count, :row_dump, :local_rows,
  :count_rows, :item_state, :item_row, :count_items, :clean_app, :field_by_name }
