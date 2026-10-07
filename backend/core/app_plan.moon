-- backend/core/app_plan.moon
-- Moteur pur de calcul du plan de mise a jour d'une application (spec §2).
-- Fonction pure : aucun acces a box ni a la base, uniquement des tables.

SPECIAL_TYPES =
  seed: true
  group: true
  perm: true

_empty_plan = (errors) ->
  {
    create: {}
    update: {}
    conflict: {}
    keep_local: {}
    obsolete: {}
    rename: {}
    unchanged: {}
    errors: errors or {}
  }

_is_special = (type_) -> SPECIAL_TYPES[type_] == true

_parse_version = (value) ->
  return nil unless type(value) == 'string'
  parts = {}
  for part in value\gmatch '[^.]+'
    n = tonumber part
    return nil if n == nil
    table.insert parts, n
  return nil if #parts == 0
  parts

compare_versions = (a, b) ->
  pa = _parse_version a
  pb = _parse_version b
  return nil if pa == nil or pb == nil
  count = math.max #pa, #pb
  for i = 1, count
    x = pa[i] or 0
    y = pb[i] or 0
    return 1 if x > y
    return -1 if x < y
  0

_downgrade_error = (package, opts) ->
  return nil unless opts.installed_version
  return nil if compare_versions(package.app.version, opts.installed_version) != -1
  return nil if opts.allow_downgrade
  "downgrade from #{opts.installed_version} to #{package.app.version} is not allowed"

_validate = (package) ->
  errors = {}
  app = package and package.app
  if type(app) != 'table' or type(app.id) != 'string' or app.id == ''
    table.insert errors, "package app id is required"
  items = package and package.items
  if type(items) != 'table'
    table.insert errors, "package items must be a list"
    return errors
  for entry in *items
    if type(entry) != 'table'
      table.insert errors, "package item must be a table"
      continue
    table.insert errors, "package item is missing type" if entry.type == nil
    table.insert errors, "package item is missing key" if entry.key == nil
    table.insert errors, "package item is missing fingerprint" if entry.fingerprint == nil
  errors

_classify_create = (entry, local_state, plan) ->
  if local_state.fingerprint == entry.fingerprint
    table.insert plan.unchanged, entry.key
  elseif _is_special entry.type
    table.insert plan.keep_local, entry
  else
    table.insert plan.conflict, { entry, local_state, entry.fingerprint }

_classify_uninstalled = (entry, local_state, plan) ->
  return table.insert plan.create, entry if local_state == nil
  _classify_create entry, local_state, plan

_classify_installed = (entry, old, local_state, plan) ->
  L = old.fingerprint
  N = entry.fingerprint
  if local_state == nil
    if N == L or _is_special entry.type
      table.insert plan.keep_local, entry
    else
      table.insert plan.conflict, { entry, nil, N }
    return
  C = local_state.fingerprint
  if C == L and N == L
    table.insert plan.unchanged, entry.key
  elseif C == L
    table.insert plan.update, entry
  elseif N == L
    table.insert plan.keep_local, entry
  elseif C == N
    table.insert plan.unchanged, entry.key
  elseif _is_special entry.type
    table.insert plan.keep_local, entry
  else
    table.insert plan.conflict, { entry, local_state, N }

_sort_by = (list, keyfn) ->
  table.sort list, (a, b) -> keyfn(a) < keyfn(b)

_sort_plan = (plan) ->
  _sort_by plan.create, (e) -> e.key
  _sort_by plan.update, (e) -> e.key
  _sort_by plan.keep_local, (e) -> e.key
  _sort_by plan.conflict, (e) -> e[1].key
  _sort_by plan.rename, (e) -> e[1]
  table.sort plan.obsolete
  table.sort plan.unchanged
  plan

_collect_package_keys = (package) ->
  result = {}
  for entry in *package.items
    result[entry.key] = true if entry.key != nil
  result

_mark_obsolete = (installed, package, consumed, plan) ->
  pkg_keys = _collect_package_keys package
  for key, info in pairs installed
    continue if consumed[key] or pkg_keys[key]
    continue if info.type == 'seed' or info.type == 'perm'
    continue if info.state == 'obsolète'
    table.insert plan.obsolete, key

plan_update = (installed, package, local_states, opts) ->
  installed or= {}
  local_states or= {}
  opts or= {}
  plan = _empty_plan!
  errors = _validate package
  if #errors > 0
    plan.errors = errors
    return plan
  downgrade = _downgrade_error package, opts
  if downgrade
    plan.errors = { downgrade }
    return plan
  consumed = {}
  for entry in *package.items
    if entry.renamed_from
      if installed[entry.renamed_from]
        consumed[entry.renamed_from] = true
        table.insert plan.rename, { entry.renamed_from, entry.key }
        _classify_installed entry, installed[entry.renamed_from], local_states[entry.renamed_from], plan
      else
        table.insert plan.create, entry
      continue
    old = installed[entry.key]
    if old == nil
      _classify_uninstalled entry, local_states[entry.key], plan
    else
      _classify_installed entry, old, local_states[entry.key], plan
  _mark_obsolete installed, package, consumed, plan
  _sort_plan plan

{ :plan_update, :compare_versions }
