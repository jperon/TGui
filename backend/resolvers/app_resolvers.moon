-- backend/resolvers/app_resolvers.moon
-- Summary: GraphQL resolvers for application versioning (list, export, preview, apply, purge).
-- Responsibilities:
-- - Expose the app-versioning surface reserved to administrators (require_admin).
-- - Turn core/app_package and core/app_apply structures into SDL shapes.
-- - Mark third-party code (plugins, pages, data views, formula fields) in the plan.
-- Key Flows:
-- - exportApp: build_package -> yaml.encode.
-- - previewAppUpdate/previewAppPurge: read-only plans and loss previews.
-- - applyAppUpdate/purgeAppObsolete: delegated to core/app_apply transactions.
-- Depends on:
-- - core/app_package, core/app_apply, resolvers.utils.
-- Used by:
-- - resolvers/init.moon (merged into the Query and Mutation roots).

yaml        = require 'yaml'
app_package = require 'core.app_package'
app_apply   = require 'core/app_apply'
{ :require_admin } = require 'resolvers.utils'

-- Item types whose delivered content is executable third-party code (spec §4).
-- `preset` belongs here: its content carries a MoonScript filter formula
-- (`self.age > 3`, tests/test_view_presets.moon:37) evaluated against each
-- record like every other `filter` formula (resolvers/graphql_view_resolvers.moon:
-- 140-169 compiles it with triggers.compile_formula formula, 'filter',
-- 'moonscript'). `dataview` is here for the computed-field formulas embedded in
-- its config (core/data_views.moon:9 compiles them).
CODE_TYPES = { plugin: true, page: true, dataview: true, preset: true }

SEMVER_PATTERN = '^%d+%.%d+%.%d+$'

-- ────────────────────────────────────────────────────────────────────────────
-- Parsing and input normalization
-- ────────────────────────────────────────────────────────────────────────────

-- Decode a package YAML string, with the same error wording as export_resolvers.
parse_yaml = (text) ->
  ok, parsed = pcall -> yaml.decode text
  error "Invalid YAML: #{parsed}" unless ok and type(parsed) == 'table'
  parsed

-- Validate the package through core/app_apply (recomputes every fingerprint)
-- and return the normalized package, or raise a clear list of the errors.
require_valid_package = (package) ->
  normalized, err = app_apply.load_package package
  error "Invalid package: #{err}" unless normalized
  normalized

-- [AppSeedInput!] -> { [space] = keyField }
seed_map_of = (entries) ->
  result = {}
  for entry in *(entries or {})
    if type(entry) == 'table' and entry.space and entry.keyField
      result[entry.space] = entry.keyField
  result

-- [AppDecisionInput!] -> { [key] = 'local' | 'delivered' }
decisions_map_of = (entries) ->
  result = {}
  for entry in *(entries or {})
    continue unless type(entry) == 'table' and entry.key
    choice = entry.choice
    unless choice == 'local' or choice == 'delivered'
      error "Invalid decision '#{tostring choice}' for '#{entry.key}': expected 'local' or 'delivered'"
    result[entry.key] = choice
  result

-- ────────────────────────────────────────────────────────────────────────────
-- Plan shape
-- ────────────────────────────────────────────────────────────────────────────

-- A field is code-bearing when it carries a formula or trigger fields.
has_code_field = (content) ->
  return false unless type(content) == 'table'
  formula = content.formula
  return true if type(formula) == 'string' and formula != ''
  triggers = content.triggerFields
  return true if type(triggers) == 'table' and #triggers > 0
  false

is_code_item = (item_type, content) ->
  return true if CODE_TYPES[item_type] == true
  item_type == 'field' and has_code_field content

plan_item_of = (entry) ->
  {
    key: entry.key
    type: entry.type
    content: entry.content
    fingerprint: entry.fingerprint
    isCode: is_code_item entry.type, entry.content
  }

-- A plan conflict is { entry, local_state|nil, delivered_fingerprint }.
-- `local` is a reserved Lua word: assign it with a bracket key.
conflict_of = (conflict) ->
  entry = conflict[1]
  local_state = conflict[2]
  result = { key: entry.key, type: entry.type, delivered: entry.content }
  result['local'] = local_state and local_state.content or nil
  result

plan_shape = (plan) ->
  {
    create: [plan_item_of it for it in *plan.create]
    update: [plan_item_of it for it in *plan.update]
    conflict: [conflict_of c for c in *plan.conflict]
    keepLocal: [plan_item_of it for it in *plan.keep_local]
    obsolete: plan.obsolete or {}
    rename: [{ from: pair[1], to: pair[2] } for pair in *plan.rename]
    unchanged: plan.unchanged or {}
    errors: plan.errors or {}
  }

-- ────────────────────────────────────────────────────────────────────────────
-- Report shapes
-- ────────────────────────────────────────────────────────────────────────────

apply_report_shape = (report) ->
  {
    ok: report.ok == true
    created: report.created or {}
    updated: report.updated or {}
    kept: report.kept or {}
    unchanged: report.unchanged or {}
    obsolete: report.obsolete or {}
    skipped: report.skipped or {}
    error: report.error
  }

loss_shape = (loss) ->
  {
    key: loss.key
    type: loss.type
    records: loss.records or 0
    fields: loss.fields or 0
    relations: loss.relations or 0
    views: loss.views or 0
  }

purge_preview_shape = (preview) ->
  {
    losses: [loss_shape loss for loss in *preview.losses]
    totalRecords: preview.total_records or 0
  }

purge_report_shape = (report) ->
  {
    ok: report.ok == true
    purged: report.purged or {}
    error: report.error
  }

-- ────────────────────────────────────────────────────────────────────────────
-- Installed apps listing
-- ────────────────────────────────────────────────────────────────────────────

list_apps = ->
  result = {}
  for row in *box.space._tdb_apps\select {}
    app_id = row[1]
    active = 0
    obsolete = 0
    for item in *box.space._tdb_app_items.index.by_app\select { app_id }
      if item[6] == 'obsolète'
        obsolete += 1
      else
        active += 1
    table.insert result, {
      appId: app_id
      name: row[2] or ''
      version: row[3] or ''
      installedAt: row[4] or 0
      source: row[5] or ''
      activeCount: active
      obsoleteCount: obsolete
    }
  result

-- Tracked items of one installed app, sorted by key. Unknown appId → {}.
-- Tuple: app_id(1) key(2) type(3) local_id(4) fingerprint(5) state(6) version(7)
app_items = (app_id) ->
  result = {}
  for row in *box.space._tdb_app_items.index.by_app\select { app_id }
    table.insert result, {
      key: row[2]
      type: row[3]
      state: row[6] or 'actif'
      version: row[7]
    }
  table.sort result, (a, b) -> a.key < b.key
  result

-- ────────────────────────────────────────────────────────────────────────────
-- Resolvers
-- ────────────────────────────────────────────────────────────────────────────

Query =
  listApps: (_, _, ctx) ->
    require_admin ctx
    list_apps!

  appItems: (_, args, ctx) ->
    require_admin ctx
    app_items args.appId

  exportApp: (_, args, ctx) ->
    require_admin ctx
    meta = args.meta or {}
    version = meta.version
    unless type(version) == 'string' and version\match SEMVER_PATTERN
      error "Invalid version '#{tostring version}': expected semver x.y.z"
    package = app_package.build_package meta, { seed: seed_map_of(args.seed) }
    yaml.encode package

  previewAppUpdate: (_, args, ctx) ->
    require_admin ctx
    package = require_valid_package parse_yaml(args.yaml)
    plan = app_apply.preview_update package, { allow_downgrade: args.allowDowngrade == true }
    plan_shape plan

  previewAppPurge: (_, args, ctx) ->
    require_admin ctx
    preview = app_apply.preview_purge args.appId, args.keys or {}
    error preview.error if preview.error
    purge_preview_shape preview

Mutation =
  applyAppUpdate: (_, args, ctx) ->
    require_admin ctx
    package = require_valid_package parse_yaml(args.yaml)
    decisions = decisions_map_of args.decisions
    report = app_apply.apply_update package, decisions, { allow_downgrade: args.allowDowngrade == true }
    apply_report_shape report

  purgeAppObsolete: (_, args, ctx) ->
    require_admin ctx
    report = app_apply.purge_obsolete args.appId, args.keys or {}, { confirmed: args.confirmed == true }
    purge_report_shape report

{ :Query, :Mutation }
