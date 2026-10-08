-- tests/test_app_trigger_fields.moon
-- Correctif T3b : une colonne calculée à la lecture (formule SANS triggerFields)
-- ne doit jamais devenir un trigger d'écriture à l'installation d'un paquet.
--
-- Sémantique du contenu d'un item `field` d'un paquet :
--   clé triggerFields ABSENTE (nil) = pas de trigger (colonne calculée à la
--                                     lecture, ou champ simple)
--   tableau (même vide)            = trigger formula ({} : à la création)
--
-- Mesure du bug : avec l'ancienne forme, _create_field/_update_field passaient
-- `c.triggerFields or {}`, donc colonne 9 de _tdb_fields = '[]' →
-- triggers.register_space_trigger enregistre un trigger → la formule s'exécute
-- à l'écriture (insert) au lieu de la lecture.

R        = require 'tests.runner'
apply    = require 'core.app_apply'
pkg_mod  = require 'core.app_package'
spaces   = require 'core.spaces'
data_r   = require 'resolvers.data_resolvers'
dynamic  = require 'graphql.dynamic'
executor = require 'graphql.executor'
auth     = require 'core.auth'
builder  = require 'tools.app_builder'
json     = require 'json'
yaml     = require 'yaml'

SUFFIX = tostring math.random 100000, 999999
SP     = "t3b_calc_#{SUFFIX}"
APP_ID = "org.test.t3b_#{SUFFIX}"

-- (c) champ simple, source des deux formules
F_PLAIN = 'qty'
-- (a) colonne calculée à la lecture : formule SANS triggerFields
F_READ  = 'calc_read'
-- (b) trigger formula à la création : formule AVEC triggerFields = {}
F_WRITE = 'calc_write'

KEY_SPACE = "space:#{SP}"
KEY_PLAIN = "field:#{SP}.#{F_PLAIN}"
KEY_READ  = "field:#{SP}.#{F_READ}"
KEY_WRITE = "field:#{SP}.#{F_WRITE}"

admin = auth.get_user_by_username 'admin'
CTX   = { user_id: admin and admin.id }

plain_item = {
  type: 'field'
  key: KEY_PLAIN
  content: { fieldType: 'Int', notNull: false, description: '',
             formula: '', language: 'lua' }
}

-- Pas de clé triggerFields : colonne calculée à la lecture.
read_item = {
  type: 'field'
  key: KEY_READ
  content: { fieldType: 'Int', notNull: false, description: '',
             formula: '(self.qty or 0) * 2', language: 'lua' }
}

-- triggerFields = {} : trigger formula exécuté à la création.
write_item = {
  type: 'field'
  key: KEY_WRITE
  content: { fieldType: 'Int', notNull: false, description: '',
             formula: '(self.qty or 0) * 3', triggerFields: {}, language: 'lua' }
}

PKG = {
  app: { id: APP_ID, name: 'T3b trigger fields', version: '1.0.0', description: '' }
  items: {
    { type: 'space', key: KEY_SPACE, content: { description: 't3b computed columns' } }
    plain_item
    read_item
    write_item
  }
  seed_keys: {}
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

field_tuple = (sid, name) ->
  for t in *box.space._tdb_fields.index.by_space\select { sid }
    return t if t[3] == name
  nil

stored_row = (id) ->
  t = box.space["data_#{SP}"]\get id
  json.decode t[2]

-- build_package exporte toutes les espaces de l'instance : on ne garde que
-- celles du suffixe de ce test (pattern subset des autres tests d'app).
subset = (package) ->
  items = [it for it in *package.items when it.key\find SP, 1, true]
  { app: package.app, items: items, seed_keys: package.seed_keys or {} }

local_package = (version) ->
  meta = { id: APP_ID, name: 'T3b trigger fields', version: version, description: '' }
  subset pkg_mod.build_package meta, {}

by_key = (package) ->
  m = {}
  m[it.key] = it for it in *package.items
  m

clean_app_rows = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

-- ────────────────────────────────────────────────────────────────────────────
R.describe "T3b — install d'un paquet à colonnes calculées", ->

  R.it "installs the package (one space, three fields)", ->
    report = apply.apply_update PKG, {}, {}
    R.ok report.ok, report.error
    R.eq #(report.errors or {}), 0, 'errors'
    R.eq #report.created, 4, 'created'
    R.ok spaces.get_space_by_name SP

  R.it "(1) _tdb_fields column 9: null for (a) and (c), [] for (b)", ->
    sid = spaces.get_space_by_name(SP).id
    t_read = field_tuple sid, F_READ
    R.ok t_read, 'computed field row'
    R.eq t_read[9], 'null', 'computed column must carry no trigger'
    t_write = field_tuple sid, F_WRITE
    R.ok t_write, 'trigger field row'
    R.eq t_write[9], '[]', 'create-only trigger must be an empty list'
    t_plain = field_tuple sid, F_PLAIN
    R.ok t_plain, 'plain field row'
    R.ok (t_plain[9] == nil or t_plain[9] == 'null'), 'plain field carries no trigger'

  R.it "(2) insert stores the trigger value of (b) only", ->
    sp = spaces.get_space_by_name SP
    res = data_r.Mutation.insertRecord {}, { spaceId: sp.id, data: { qty: 5 } }, CTX
    R.ok res, 'record inserted'
    row = stored_row res.id
    R.eq row.qty, 5, 'source field'
    R.is_nil row[F_READ], 'computed column is not evaluated at write'
    R.eq row[F_WRITE], 15, 'create-only trigger is evaluated at write'

  -- data_r.Query.records renvoie la ligne STOCKÉE (resolvers/data_resolvers.moon:
  -- `parsed = json.decode t[2]`) : les colonnes calculées ne sont pas évaluées
  -- sur ce chemin, ni avant ni après le correctif. L'évaluation à la lecture est
  -- faite par les résolveurs de champ du type dynamique
  -- (graphql/dynamic.moon: « Prefer raw stored value … else safe_formula_call »),
  -- donc par la requête typée, pas par records.
  R.it "(3) Query.records returns the stored row, without the computed column", ->
    sp = spaces.get_space_by_name SP
    res = data_r.Query.records {}, { spaceId: sp.id }, CTX
    R.eq res.total, 1, 'one record'
    row = json.decode res.items[1].data
    R.is_nil row[F_READ], 'records does not evaluate the formula column'
    R.eq row[F_WRITE], 15, 'stored trigger value read back'

  R.it "(3) the typed query evaluates the computed column at read", ->
    sp = spaces.get_space_by_name SP
    gname = dynamic.gql_name SP
    query = "{ #{gname} { items { qty #{F_READ} #{F_WRITE} } } }"
    res = executor.execute { query: query, context: CTX }
    R.nok res.errors, json.encode res.errors
    item = res.data[gname].items[1]
    R.ok item, 'one item'
    R.eq item[F_PLAIN], 5, 'source field'
    R.eq item[F_READ], 10, 'computed column evaluated at read'
    R.eq item[F_WRITE], 15, 'stored trigger value read back'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "T3b — aller-retour export / preview", ->

  R.it "(4) build_package keeps the no-trigger / trigger distinction", ->
    m = by_key local_package '1.1.0'
    R.ok m[KEY_PLAIN], 'plain field exported'
    R.is_nil m[KEY_PLAIN].content.triggerFields, 'plain field: no triggerFields key'
    R.ok m[KEY_READ], 'computed field exported'
    R.is_nil m[KEY_READ].content.triggerFields, 'computed column: no triggerFields key'
    R.ok m[KEY_WRITE], 'trigger field exported'
    R.ok (type(m[KEY_WRITE].content.triggerFields) == 'table'), 'trigger kept'
    R.eq #m[KEY_WRITE].content.triggerFields, 0, 'create-only trigger list is empty'

  R.it "(4) preview_update of the same package reports no create and no update", ->
    p = local_package '1.1.0'
    plan = apply.preview_update p
    R.eq #plan.errors, 0, json.encode plan.errors
    R.eq #plan.create, 0, 'create'
    R.eq #plan.update, 0, 'update'
    R.eq #plan.conflict, 0, 'conflict'
    R.eq #plan.unchanged, #p.items, 'unchanged'

  -- Le aller-retour YAML est le chemin réel d'un paquet : le parseur de
  -- Tarantool décode `triggerFields: {}` en tableau vide, `triggerFields: null`
  -- (ou la clé absente) en box.NULL, retiré par strip_null. Les deux doivent
  -- redevenir la même empreinte que l'état local.
  R.it "(4) the same package survives a YAML round-trip unchanged", ->
    raw = yaml.encode local_package('1.1.0')
    p = yaml.decode raw
    plan = apply.preview_update p
    R.eq #plan.errors, 0, json.encode plan.errors
    R.eq #plan.create, 0, 'create'
    R.eq #plan.update, 0, 'update'
    R.eq #plan.conflict, 0, 'conflict'
    R.eq #plan.unchanged, #p.items, 'unchanged'

-- ────────────────────────────────────────────────────────────────────────────
-- Le constructeur (backend/tools/app_builder.moon) émettait `triggerFields: {}`
-- pour TOUS les champs : sous la nouvelle sémantique ce serait un trigger à la
-- création sur chaque colonne. La clé doit être absente.
BUILDER_STRUCT = {
  app: { id: 'org.test.t3bbuilder', name: 'T3b builder', version: '1.0.0', description: '' }
  spaces: {
    { name: SP, description: 't3b builder', fields: {
        { name: F_PLAIN, type: 'Int' }
        { name: F_READ, type: 'Int', formula: '(self.qty or 0) * 2' } } }
  }
}

R.describe "T3b — app_builder n'émet plus triggerFields", ->

  R.it "field items carry no triggerFields key", ->
    m = by_key builder.expand BUILDER_STRUCT
    R.ok m[KEY_PLAIN], 'plain field emitted'
    R.is_nil m[KEY_PLAIN].content.triggerFields, 'plain field: no triggerFields key'
    R.ok m[KEY_READ], 'formula field emitted'
    R.is_nil m[KEY_READ].content.triggerFields, 'formula field: no triggerFields key'

-- ────────────────────────────────────────────────────────────────────────────
R.describe "T3b — cleanup", ->

  R.it "removes the fixture", ->
    clean_app_rows APP_ID
    sp = spaces.get_space_by_name SP
    spaces.delete_user_space SP if sp
    R.is_nil spaces.get_space_by_name SP
    R.eq #box.space._tdb_app_items.index.by_app\select({ APP_ID }), 0, 'no app item left'
    R.is_nil box.space._tdb_apps\get(APP_ID), 'no app row left'
