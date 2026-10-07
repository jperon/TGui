-- tests/test_app_lifecycle.moon
-- V6a : test d'intégration de bout en bout du cycle de vie d'une application,
-- à travers les résolveurs GraphQL (app_r.Query / app_r.Mutation), comme un
-- administrateur réel. Scénario (spec §2 et §5) :
--   export -> aperçu identique -> installation -> modifications locales ->
--   paquet v1.1.0 (conflit, obsolète, ajouts, plugin) -> refus sans décision ->
--   décision 'local' -> réinstallation identique -> décision 'delivered'
--   (second cycle indépendant) -> purge -> droits -> downgrade.
-- Fixture autonome (suffixe propre) ; tourne dans l'instance de test Tarantool.

R           = require 'tests.runner'
auth        = require 'core.auth'
perms       = require 'core.permissions'
spaces      = require 'core.spaces'
schema_r    = require 'resolvers.schema_resolvers'
data_r      = require 'resolvers.data_resolvers'
app_r       = require 'resolvers.app_resolvers'
app_package = require 'core.app_package'
yaml        = require 'yaml'
json        = require 'json'

SUFFIX  = tostring math.random 100000, 999999
SUFFIX2 = tostring math.random 100000, 999999

SP_A        = "vl_a_#{SUFFIX}"
SP_B        = "vl_b_#{SUFFIX}"
SP_LOCAL    = "vl_local_#{SUFFIX}"
GROUP       = "vl_group_#{SUFFIX}"
PLUG        = "vl_plugin_#{SUFFIX}"
APP_ID      = "org.test.vl_#{SUFFIX}"

FIELD_NOM   = "field:#{SP_A}.nom"
FIELD_NAT   = "field:#{SP_A}.nationalite"
FIELD_ORDRE = "field:#{SP_A}.ordre"
FIELD_ISBN  = "field:#{SP_A}.isbn"

SP_D    = "vl_d_#{SUFFIX2}"
APP2    = "org.test.vl2_#{SUFFIX2}"
FIELD_Z = "field:#{SP_D}.z"

admin   = auth.get_user_by_username 'admin'
CTX     = { user_id: admin and admin.id }

ACTOR   = auth.create_user "vlactor_#{SUFFIX}", "vlactor_#{SUFFIX}@test.local", "pass1234"
SESSION = auth.create_session ACTOR.id
NONADMIN = { user_id: ACTOR.id, token: SESSION.token }

FIX = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

field_by_name = (space_name, name) ->
  sp = spaces.get_space_by_name space_name
  return nil unless sp
  for f in *spaces.list_fields sp.id
    return f if f.name == name
  nil

find_item = (items, key) ->
  for it in *items
    return it if it.key == key
  nil

key_in_list = (list, key) ->
  for k in *list
    return true if k == key
  false

count_rows = (space_name) ->
  sp = box.space["data_#{space_name}"]
  sp and #sp\select({}) or 0

has_key = (space_name, key) ->
  sp = box.space["data_#{space_name}"]
  return false unless sp
  for t in *sp\select {}
    d = json.decode t[2]
    return true if d[key] != nil
  false

record_by_key = (space_name, key_field, val) ->
  sp = box.space["data_#{space_name}"]
  return nil unless sp
  for t in *sp\select {}
    d = json.decode t[2]
    return d if d[key_field] != nil and tostring(d[key_field]) == tostring val
  nil

item_state = (app_id, key) ->
  t = box.space._tdb_app_items\get { app_id, key }
  t and t[6] or nil

item_row = (app_id, key) ->
  box.space._tdb_app_items\get { app_id, key }

app_items = (app_id) ->
  app_r.Query.appItems nil, { appId: app_id }, CTX

installed_version = (app_id) ->
  row = box.space._tdb_apps\get app_id
  row and row[3] or nil

clean_app = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

subset_for = (package, marker) ->
  items = [it for it in *package.items when it.key\find marker, 1, true]
  { app: package.app, items: items, seed_keys: package.seed_keys or {} }

subset = (package) -> subset_for package, SUFFIX

set_desc = (package, key, value) ->
  for it in *package.items
    if it.key == key and type(it.content) == 'table'
      it.content.description = value
  package

without = (package, key) ->
  package.items = [it for it in *package.items when it.key != key]
  package

field_item = (key, desc) ->
  { type: 'field', key: key,
    content: { fieldType: 'String', notNull: false, description: desc,
               formula: '', triggerFields: {}, language: 'lua' } }

plugin_item = (name) ->
  { type: 'plugin', key: "plugin:#{name}",
    content: { name: name, description: 'vl plugin',
               scriptLanguage: 'coffeescript', templateLanguage: 'pug',
               scriptCode: "render 'x'", templateCode: 'div x' } }

build_v11 = (base) ->
  p = subset base
  p.app.version = '1.1.0'
  set_desc p, FIELD_NOM, 'AUTHOR-NOM'
  set_desc p, FIELD_NAT, 'AUTHOR-NAT'
  without p, FIELD_ORDRE
  table.insert p.items, field_item FIELD_ISBN, 'isbn'
  table.insert p.items, plugin_item PLUG
  p

snap = ->
  {
    spaces: #spaces.list_spaces!
    fields: #box.space._tdb_fields\select {}
    rows_a: count_rows SP_A
    rows_b: count_rows SP_B
    items: #box.space._tdb_app_items.index.by_app\select { APP_ID }
    version: installed_version APP_ID
    nat: (field_by_name SP_A, 'nationalite').description
    nom: (field_by_name SP_A, 'nom').description
  }

same_snap = (a, b) ->
  R.eq a.spaces, b.spaces, 'spaces'
  R.eq a.fields, b.fields, 'fields'
  R.eq a.rows_a, b.rows_a, 'rows_a'
  R.eq a.rows_b, b.rows_b, 'rows_b'
  R.eq a.items, b.items, 'items'
  R.eq a.version, b.version, 'version'
  R.eq a.nat, b.nat, 'nat'
  R.eq a.nom, b.nom, 'nom'

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Préparation
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — préparation", ->

  R.it "creates space A with fields and four records", ->
    a = spaces.create_user_space SP_A, 'vl space A'
    FIX.a_id = a.id
    FIX.nom_id = (spaces.add_field a.id, 'nom', 'String', true, 'natural key').id
    FIX.nat_id = (spaces.add_field a.id, 'nationalite', 'String', false, '').id
    FIX.ordre_id = (spaces.add_field a.id, 'ordre', 'Int', false, '').id
    R.ok spaces.get_space_by_name SP_A
    R.ok field_by_name SP_A, 'nom'
    R.ok field_by_name SP_A, 'nationalite'
    R.ok field_by_name SP_A, 'ordre'

  R.it "creates space B with a field and a relation to A", ->
    b = spaces.create_user_space SP_B, 'vl space B'
    FIX.b_id = b.id
    spaces.add_field b.id, 'titre', 'String', false, ''
    a_id_field = spaces.add_field b.id, 'a_id', 'Int', false, ''
    res = schema_r.Mutation.createRelation {}, {
      input: {
        name: "vl_rel_#{SUFFIX}"
        fromSpaceId: b.id
        fromFieldId: a_id_field.id
        toSpaceId: FIX.a_id
        toFieldId: FIX.nom_id
        reprFormula: '@nom'
        cardinality: 'many'
      }
    }, CTX
    FIX.rel_id = res.id
    R.ok res
    R.ok app_package.describe_local('relation', "relation:#{SP_B}.a_id")

  R.it "creates a group with read on A and inserts four A records", ->
    FIX.group_id = (perms.create_group GROUP, 'vl group').id
    perms.grant FIX.group_id, 'space', FIX.a_id, 'read'
    for row in *{ { nom: 'N-1', nationalite: 'FR', ordre: 1 },
                  { nom: 'N-2', nationalite: 'FR', ordre: 2 },
                  { nom: 'N-3', nationalite: 'BE', ordre: 3 },
                  { nom: 'N-4', nationalite: 'BE', ordre: 4 } }
      data_r.Mutation.insertRecord {}, { spaceId: FIX.a_id, data: row }, CTX
    R.eq count_rows(SP_A), 4
    R.eq count_rows(SP_B), 0
    R.ok app_package.describe_local('group', "group:#{GROUP}")
    R.eq app_package.describe_local('perm', "perm:#{GROUP}|space|#{SP_A}|read").level, 'read'

-- ────────────────────────────────────────────────────────────────────────────
-- 2. exportApp
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — exportApp", ->

  R.it "exports a reloadable YAML package with the four seed lines", ->
    RAW = app_r.Query.exportApp {}, {
      meta: { id: APP_ID, name: 'VL fixture', version: '1.0.0', description: 'vl' }
      seed: { { space: SP_A, keyField: 'nom' } }
    }, CTX
    FIX.raw = RAW
    R.eq type(RAW), 'string'
    FIX.pkg1 = subset yaml.decode(RAW)
    FIX.yaml1 = yaml.encode FIX.pkg1
    R.eq FIX.pkg1.app.id, APP_ID
    R.eq FIX.pkg1.app.name, 'VL fixture'
    R.eq FIX.pkg1.app.version, '1.0.0'
    n_seed = 0
    for it in *FIX.pkg1.items
      n_seed += 1 if it.type == 'seed' and it.content.space == SP_A
    R.eq n_seed, 4, 'four seed lines for A'
    R.ok find_item FIX.pkg1.items, "seed:#{SP_A}|N-1"
    R.ok find_item FIX.pkg1.items, "seed:#{SP_A}|N-4"
    R.is_nil find_item(FIX.pkg1.items, 'group:admin'), 'admin group never delivered'

  R.it "carries no local identifier nor date in the raw YAML", ->
    R.nok (FIX.raw\find FIX.a_id, 1, true), 'no space id'
    R.nok (FIX.raw\find FIX.nom_id, 1, true), 'no field id'
    R.nok (FIX.raw\find FIX.rel_id, 1, true), 'no relation id'
    R.nok (FIX.raw\find FIX.group_id, 1, true), 'no group id'
    R.nok (FIX.raw\match '%d%d%d%d%d%d%d%d%d%d'), 'no epoch timestamp'

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Aperçu identique
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — aperçu identique", ->

  R.it "reports everything unchanged and writes nothing", ->
    before = snap!
    plan = app_r.Query.previewAppUpdate nil, { yaml: FIX.yaml1 }, CTX
    R.eq #plan.errors, 0, json.encode(plan.errors)
    R.eq #plan.create, 0, 'create'
    R.eq #plan.update, 0, 'update'
    R.eq #plan.conflict, 0, 'conflict'
    R.eq #plan.obsolete, 0, 'obsolete'
    R.eq #plan.keepLocal, 0, 'keepLocal'
    R.eq #plan.unchanged, #FIX.pkg1.items, 'unchanged'
    same_snap before, snap!

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Installation
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — installation", ->

  R.it "installs the app and tracks every item as active", ->
    report = app_r.Mutation.applyAppUpdate nil, { yaml: FIX.yaml1 }, CTX
    R.ok report.ok, report.error
    apps = app_r.Query.listApps nil, {}, CTX
    found = nil
    for a in *apps
      found = a if a.appId == APP_ID
    R.ok found, 'installed app listed'
    R.eq found.version, '1.0.0'
    R.eq found.activeCount, #FIX.pkg1.items
    R.eq found.obsoleteCount, 0
    items = app_items APP_ID
    R.eq #items, #FIX.pkg1.items
    for it in *items
      R.eq it.state, 'actif', "state of #{it.key}"
    R.eq count_rows(SP_A), 4, 'seed records kept'

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Modifications locales
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — modifications locales", ->

  R.it "changes nationalite (local), space B description and adds a local space", ->
    spaces.update_field (field_by_name SP_A, 'nationalite').id, { description: 'LOCAL-NAT' }
    box.space._tdb_spaces\update FIX.b_id, { { '=', 3, 'LOCAL-B' } }
    spaces.create_user_space SP_LOCAL, 'vl local outside package'
    R.eq (field_by_name SP_A, 'nationalite').description, 'LOCAL-NAT'
    R.eq (spaces.get_space_by_name SP_B).description, 'LOCAL-B'
    R.ok spaces.get_space_by_name SP_LOCAL

  R.it "adds one local record to A (the +1 to preserve)", ->
    data_r.Mutation.insertRecord {}, {
      spaceId: FIX.a_id, data: { nom: 'LOCAL-EXTRA', nationalite: 'FR' }
    }, CTX
    FIX.rows_a_before = count_rows SP_A
    FIX.rows_b_before = count_rows SP_B
    R.eq FIX.rows_a_before, 5
    R.ok record_by_key SP_A, 'nom', 'LOCAL-EXTRA'

-- ────────────────────────────────────────────────────────────────────────────
-- 6. Paquet v1.1.0 : aperçu
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — paquet v1.1.0 (auteur)", ->

  R.it "builds v1.1.0 from the exported items (adds isbn and a plugin)", ->
    FIX.pkg2 = build_v11 FIX.pkg1
    FIX.yaml2 = yaml.encode FIX.pkg2
    R.eq FIX.pkg2.app.version, '1.1.0'
    R.eq (find_item FIX.pkg2.items, FIELD_NOM).content.description, 'AUTHOR-NOM'
    R.eq (find_item FIX.pkg2.items, FIELD_NAT).content.description, 'AUTHOR-NAT'
    R.is_nil find_item FIX.pkg2.items, FIELD_ORDRE
    R.ok find_item FIX.pkg2.items, FIELD_ISBN
    R.ok find_item FIX.pkg2.items, "plugin:#{PLUG}"

  R.it "previews created/updated/conflict/kept/obsolete exactly", ->
    plan = app_r.Query.previewAppUpdate nil, { yaml: FIX.yaml2 }, CTX
    R.eq #plan.errors, 0, json.encode(plan.errors)
    R.eq #plan.create, 2, 'create'
    R.eq #plan.update, 1, 'update'
    R.eq #plan.conflict, 1, 'conflict'
    R.eq #plan.keepLocal, 1, 'keepLocal'
    R.eq #plan.obsolete, 1, 'obsolete'
    R.ok find_item(plan.create, FIELD_ISBN), 'isbn created'
    R.ok find_item(plan.create, "plugin:#{PLUG}"), 'plugin created'
    R.ok (find_item(plan.update, FIELD_NOM)), 'nom updated'
    R.eq plan.conflict[1].key, FIELD_NAT
    R.eq plan.conflict[1].local.description, 'LOCAL-NAT'
    R.eq plan.conflict[1].delivered.description, 'AUTHOR-NAT'
    R.ok find_item(plan.keepLocal, "space:#{SP_B}"), 'space B kept'
    R.eq plan.obsolete[1], FIELD_ORDRE
    R.ok (find_item(plan.create, "plugin:#{PLUG}")).isCode, 'plugin flagged as code'

-- ────────────────────────────────────────────────────────────────────────────
-- 7. Application refusée sans décision
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — refus sans décision", ->

  R.it "refuses the conflict and writes nothing", ->
    before = snap!
    report = app_r.Mutation.applyAppUpdate nil, { yaml: FIX.yaml2 }, CTX
    R.nok report.ok
    R.matches report.error, 'decision'
    same_snap before, snap!

-- ────────────────────────────────────────────────────────────────────────────
-- 8. Application avec décision 'local'
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — décision locale", ->

  R.it "keeps the local value, applies the author changes and tracks obsolete", ->
    report = app_r.Mutation.applyAppUpdate nil, {
      yaml: FIX.yaml2
      decisions: { { key: FIELD_NAT, choice: 'local' } }
    }, CTX
    R.ok report.ok, report.error
    R.ok key_in_list(report.created, FIELD_ISBN), 'isbn created'
    R.ok key_in_list(report.created, "plugin:#{PLUG}"), 'plugin created'
    R.ok key_in_list(report.updated, FIELD_NOM), 'nom updated'
    R.ok key_in_list(report.kept, "space:#{SP_B}"), 'space B kept'
    R.eq (field_by_name SP_A, 'nationalite').description, 'LOCAL-NAT', 'local kept'
    R.eq (field_by_name SP_A, 'nom').description, 'AUTHOR-NOM', 'author applied'
    R.ok field_by_name SP_A, 'isbn'
    R.ok app_package.describe_local('plugin', "plugin:#{PLUG}")
    R.ok spaces.get_space_by_name SP_LOCAL, 'local space intact'
    R.ok record_by_key(SP_A, 'nom', 'LOCAL-EXTRA'), 'local record intact'
    R.ok field_by_name(SP_A, 'ordre'), 'obsolete field never deleted'
    R.eq count_rows(SP_A), FIX.rows_a_before, 'A record count preserved'
    R.eq count_rows(SP_B), FIX.rows_b_before, 'B record count preserved'
    items = app_items APP_ID
    ordre_state = nil
    for it in *items
      ordre_state = it.state if it.key == FIELD_ORDRE
    R.eq ordre_state, 'obsolète', 'ordre tracked obsolete'

-- ────────────────────────────────────────────────────────────────────────────
-- 9. Réinstallation identique v1.1.0
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — réinstallation identique", ->

  R.it "reinstalls an identical v1.1.0 once nationalite matches the delivered value", ->
    spaces.update_field (field_by_name SP_A, 'nationalite').id, { description: 'AUTHOR-NAT' }
    plan = app_r.Query.previewAppUpdate nil, { yaml: FIX.yaml2 }, CTX
    R.eq #plan.errors, 0, json.encode(plan.errors)
    R.eq #plan.create, 0, 'create'
    R.eq #plan.update, 0, 'update'
    R.eq #plan.conflict, 0, 'conflict'
    report = app_r.Mutation.applyAppUpdate nil, { yaml: FIX.yaml2 }, CTX
    R.ok report.ok, report.error
    R.eq (field_by_name SP_A, 'nom').description, 'AUTHOR-NOM'
    R.eq (field_by_name SP_A, 'nationalite').description, 'AUTHOR-NAT'
    R.eq installed_version(APP_ID), '1.1.0'

-- ────────────────────────────────────────────────────────────────────────────
-- 10. Décision 'delivered' — second cycle indépendant
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — décision delivered (second cycle)", ->

  R.it "installs a second fixture v1.0.0", ->
    d = spaces.create_user_space SP_D, 'vl second'
    FIX.d_id = d.id
    spaces.add_field d.id, 'z', 'String', false, 'D0'
    y2 = app_r.Query.exportApp {}, {
      meta: { id: APP2, name: 'VL2 fixture', version: '1.0.0', description: 'vl2' }
    }, CTX
    FIX.pkg_d = subset_for yaml.decode(y2), SUFFIX2
    FIX.yaml_d1 = yaml.encode FIX.pkg_d
    report = app_r.Mutation.applyAppUpdate nil, { yaml: FIX.yaml_d1 }, CTX
    R.ok report.ok, report.error
    R.eq (field_by_name SP_D, 'z').description, 'D0'
    R.ok app_package.describe_local('space', "space:#{SP_D}")

  R.it "resolves a new conflict with 'delivered' and applies the author value", ->
    spaces.update_field (field_by_name SP_D, 'z').id, { description: 'LOCAL-Z' }
    p = yaml.decode FIX.yaml_d1
    set_desc p, FIELD_Z, 'AUTHOR-Z'
    p.app.version = '1.1.0'
    y2b = yaml.encode p
    plan = app_r.Query.previewAppUpdate nil, { yaml: y2b }, CTX
    R.eq #plan.conflict, 1, 'conflict'
    R.eq plan.conflict[1].key, FIELD_Z
    R.eq plan.conflict[1].local.description, 'LOCAL-Z'
    R.eq plan.conflict[1].delivered.description, 'AUTHOR-Z'
    report = app_r.Mutation.applyAppUpdate nil, {
      yaml: y2b
      decisions: { { key: FIELD_Z, choice: 'delivered' } }
    }, CTX
    R.ok report.ok, report.error
    R.eq (field_by_name SP_D, 'z').description, 'AUTHOR-Z', 'delivered applied'

-- ────────────────────────────────────────────────────────────────────────────
-- 11. Purge
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — purge", ->

  R.it "previews the obsolete ordre losses exactly and writes nothing", ->
    before = snap!
    FIX.rows_a_before_purge = count_rows SP_A
    preview = app_r.Query.previewAppPurge nil, { appId: APP_ID, keys: { FIELD_ORDRE } }, CTX
    R.eq #preview.losses, 1
    R.eq preview.losses[1].key, FIELD_ORDRE
    R.eq preview.losses[1].type, 'field'
    R.eq preview.losses[1].records, 4, 'four records carry ordre'
    R.eq preview.totalRecords, 4
    R.ok field_by_name(SP_A, 'ordre'), 'preview wrote nothing'
    same_snap before, snap!

  R.it "refuses without confirmation, then purges the obsolete field", ->
    r0 = app_r.Mutation.purgeAppObsolete nil,
      { appId: APP_ID, keys: { FIELD_ORDRE }, confirmed: false }, CTX
    R.nok r0.ok
    R.matches r0.error, 'confirmation'
    R.ok field_by_name(SP_A, 'ordre'), 'not purged without confirmation'
    r = app_r.Mutation.purgeAppObsolete nil,
      { appId: APP_ID, keys: { FIELD_ORDRE }, confirmed: true }, CTX
    R.ok r.ok, r.error
    R.is_nil field_by_name(SP_A, 'ordre'), 'field removed'
    R.is_nil item_row(APP_ID, FIELD_ORDRE), 'tracking removed'
    R.eq count_rows(SP_A), FIX.rows_a_before_purge, 'record count unchanged'
    R.nok has_key(SP_A, 'ordre'), 'ordre key removed from every record'
    R.ok field_by_name(SP_A, 'nom'), 'other fields untouched'
    R.ok field_by_name(SP_A, 'nationalite')
    R.ok field_by_name(SP_A, 'isbn')
    items = app_items APP_ID
    has_obsolete = false
    for it in *items
      has_obsolete = true if it.state == 'obsolète'
    R.nok has_obsolete, 'no obsolete item left'

  R.it "refuses to purge an active or unknown item", ->
    r = app_r.Mutation.purgeAppObsolete nil,
      { appId: APP_ID, keys: { FIELD_NOM }, confirmed: true }, CTX
    R.nok r.ok
    R.matches r.error, 'not obsolete'
    R.raises (-> app_r.Query.previewAppPurge nil,
      { appId: APP_ID, keys: { FIELD_NOM } }, CTX), 'not obsolete'
    R.raises (-> app_r.Query.previewAppPurge nil,
      { appId: APP_ID, keys: { "field:#{SP_A}.nope" } }, CTX), 'unknown app item'
    R.ok field_by_name(SP_A, 'nom'), 'active field untouched'

-- ────────────────────────────────────────────────────────────────────────────
-- 12. Droits
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — droits", ->

  R.it "a non-admin user receives Forbidden on every operation", ->
    R.raises (-> app_r.Query.listApps nil, {}, NONADMIN), 'Forbidden'
    R.raises (-> app_r.Query.appItems nil, { appId: APP_ID }, NONADMIN), 'Forbidden'
    R.raises (-> app_r.Query.exportApp nil,
      { meta: { id: APP_ID, name: 'x', version: '1.0.0' }, seed: {} }, NONADMIN), 'Forbidden'
    R.raises (-> app_r.Query.previewAppUpdate nil, { yaml: FIX.yaml1 }, NONADMIN), 'Forbidden'
    R.raises (-> app_r.Query.previewAppPurge nil,
      { appId: APP_ID, keys: {} }, NONADMIN), 'Forbidden'
    R.raises (-> app_r.Mutation.applyAppUpdate nil, { yaml: FIX.yaml1 }, NONADMIN), 'Forbidden'
    R.raises (-> app_r.Mutation.purgeAppObsolete nil,
      { appId: APP_ID, keys: {}, confirmed: true }, NONADMIN), 'Forbidden'

-- ────────────────────────────────────────────────────────────────────────────
-- 13. Downgrade
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — downgrade", ->

  R.it "refuses v0.9.0 without allowDowngrade and accepts it with the flag", ->
    p = yaml.decode FIX.yaml2
    p.app.version = '0.9.0'
    y09 = yaml.encode p
    r = app_r.Mutation.applyAppUpdate nil, { yaml: y09 }, CTX
    R.nok r.ok
    R.matches r.error, 'downgrade'
    R.eq installed_version(APP_ID), '1.1.0', 'version unchanged'
    r2 = app_r.Mutation.applyAppUpdate nil, { yaml: y09, allowDowngrade: true }, CTX
    R.ok r2.ok, r2.error
    R.eq installed_version(APP_ID), '0.9.0', 'downgrade applied'

-- ────────────────────────────────────────────────────────────────────────────
-- Nettoyage
-- ────────────────────────────────────────────────────────────────────────────

R.describe "v6a — nettoyage", ->

  R.it "removes every fixture element and tracking row", ->
    for nm in *{ SP_A, SP_B, SP_LOCAL, SP_D }
      sp = spaces.get_space_by_name nm
      if sp
        for t in *box.space._tdb_relations.index.by_from\select { sp.id }
          box.space._tdb_relations\delete t[1]
        for t in *box.space._tdb_relations.index.by_to\select { sp.id }
          box.space._tdb_relations\delete t[1]
    for wp in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete wp[1] if wp[2] == PLUG
    for g in *perms.list_groups!
      perms.delete_group g.id if g.name == GROUP
    clean_app APP_ID
    clean_app APP2
    spaces.delete_user_space SP_A
    spaces.delete_user_space SP_B
    spaces.delete_user_space SP_LOCAL
    spaces.delete_user_space SP_D
    auth.delete_session SESSION.token
    box.space._tdb_users\delete ACTOR.id
    R.is_nil spaces.get_space_by_name SP_A
    R.is_nil spaces.get_space_by_name SP_D
    R.is_nil app_package.describe_local('space', "space:#{SP_A}")
    R.is_nil box.space._tdb_apps\get APP_ID
    R.is_nil box.space._tdb_apps\get APP2
