local yaml = require('yaml')
local app_package = require('core.app_package')
local app_apply = require('core/app_apply')
local require_admin
require_admin = require('resolvers.utils').require_admin
local CODE_TYPES = {
  plugin = true,
  page = true,
  dataview = true,
  preset = true
}
local SEMVER_PATTERN = '^%d+%.%d+%.%d+$'
local parse_yaml
parse_yaml = function(text)
  local ok, parsed = pcall(function()
    return yaml.decode(text)
  end)
  if not (ok and type(parsed) == 'table') then
    error("Invalid YAML: " .. tostring(parsed))
  end
  return parsed
end
local require_valid_package
require_valid_package = function(package)
  local normalized, err = app_apply.load_package(package)
  if not (normalized) then
    error("Invalid package: " .. tostring(err))
  end
  return normalized
end
local seed_map_of
seed_map_of = function(entries)
  local result = { }
  local _list_0 = (entries or { })
  for _index_0 = 1, #_list_0 do
    local entry = _list_0[_index_0]
    if type(entry) == 'table' and entry.space and entry.keyField then
      result[entry.space] = entry.keyField
    end
  end
  return result
end
local decisions_map_of
decisions_map_of = function(entries)
  local choices = { }
  local names = { }
  local _list_0 = (entries or { })
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local entry = _list_0[_index_0]
      if not (type(entry) == 'table' and entry.key) then
        _continue_0 = true
        break
      end
      local choice = entry.choice
      if not (choice == 'local' or choice == 'delivered' or choice == 'rename') then
        error("Invalid decision '" .. tostring(tostring(choice)) .. "' for '" .. tostring(entry.key) .. "': expected 'local', 'delivered' or 'rename'")
      end
      if choice == 'rename' then
        if entry.newName ~= nil and entry.newName ~= '' then
          if not (widget_scopes.valid_name(entry.newName)) then
            error("Invalid new name '" .. tostring(tostring(entry.newName)) .. "' for '" .. tostring(entry.key) .. "'")
          end
          names[entry.key] = entry.newName
        end
      end
      choices[entry.key] = choice
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return {
    choices = choices,
    names = names
  }
end
local has_code_field
has_code_field = function(content)
  if not (type(content) == 'table') then
    return false
  end
  local formula = content.formula
  if type(formula) == 'string' and formula ~= '' then
    return true
  end
  local triggers = content.triggerFields
  if type(triggers) == 'table' and #triggers > 0 then
    return true
  end
  return false
end
local is_code_item
is_code_item = function(item_type, content)
  if CODE_TYPES[item_type] == true then
    return true
  end
  return item_type == 'field' and has_code_field(content)
end
local plan_item_of
plan_item_of = function(entry)
  return {
    key = entry.key,
    type = entry.type,
    content = entry.content,
    fingerprint = entry.fingerprint,
    isCode = is_code_item(entry.type, entry.content)
  }
end
local conflict_of
conflict_of = function(conflict)
  local entry = conflict[1]
  local local_state = conflict[2]
  local result = {
    key = entry.key,
    type = entry.type,
    delivered = entry.content
  }
  result['local'] = local_state and local_state.content or nil
  if entry.type == 'plugin' then
    local scope = (local_state and local_state.app_id) or entry.app_scope
    result.pages = widget_scopes.pages_using_name(entry.content.name, scope)
  end
  return result
end
local plan_shape
plan_shape = function(plan)
  return {
    create = (function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = plan.create
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        _accum_0[_len_0] = plan_item_of(it)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)(),
    update = (function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = plan.update
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        _accum_0[_len_0] = plan_item_of(it)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)(),
    conflict = (function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = plan.conflict
      for _index_0 = 1, #_list_0 do
        local c = _list_0[_index_0]
        _accum_0[_len_0] = conflict_of(c)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)(),
    keepLocal = (function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = plan.keep_local
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        _accum_0[_len_0] = plan_item_of(it)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)(),
    obsolete = plan.obsolete or { },
    rename = (function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = plan.rename
      for _index_0 = 1, #_list_0 do
        local pair = _list_0[_index_0]
        _accum_0[_len_0] = {
          from = pair[1],
          to = pair[2]
        }
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)(),
    unchanged = plan.unchanged or { },
    errors = plan.errors or { }
  }
end
local apply_report_shape
apply_report_shape = function(report)
  return {
    ok = report.ok == true,
    created = report.created or { },
    updated = report.updated or { },
    kept = report.kept or { },
    unchanged = report.unchanged or { },
    obsolete = report.obsolete or { },
    skipped = report.skipped or { },
    error = report.error
  }
end
local loss_shape
loss_shape = function(loss)
  return {
    key = loss.key,
    type = loss.type,
    records = loss.records or 0,
    fields = loss.fields or 0,
    relations = loss.relations or 0,
    views = loss.views or 0
  }
end
local purge_preview_shape
purge_preview_shape = function(preview)
  return {
    losses = (function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = preview.losses
      for _index_0 = 1, #_list_0 do
        local loss = _list_0[_index_0]
        _accum_0[_len_0] = loss_shape(loss)
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)(),
    totalRecords = preview.total_records or 0
  }
end
local purge_report_shape
purge_report_shape = function(report)
  return {
    ok = report.ok == true,
    purged = report.purged or { },
    error = report.error
  }
end
local list_apps
list_apps = function()
  local result = { }
  local _list_0 = box.space._tdb_apps:select({ })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    local app_id = row[1]
    local active = 0
    local obsolete = 0
    local _list_1 = box.space._tdb_app_items.index.by_app:select({
      app_id
    })
    for _index_1 = 1, #_list_1 do
      local item = _list_1[_index_1]
      if item[6] == 'obsolète' then
        obsolete = obsolete + 1
      else
        active = active + 1
      end
    end
    table.insert(result, {
      appId = app_id,
      name = row[2] or '',
      version = row[3] or '',
      installedAt = row[4] or 0,
      source = row[5] or '',
      activeCount = active,
      obsoleteCount = obsolete
    })
  end
  return result
end
local app_items
app_items = function(app_id)
  local result = { }
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #_list_0 do
    local row = _list_0[_index_0]
    table.insert(result, {
      key = row[2],
      type = row[3],
      state = row[6] or 'actif',
      version = row[7]
    })
  end
  table.sort(result, function(a, b)
    return a.key < b.key
  end)
  return result
end
local Query = {
  listApps = function(_, _, ctx)
    require_admin(ctx)
    return list_apps()
  end,
  appItems = function(_, args, ctx)
    require_admin(ctx)
    return app_items(args.appId)
  end,
  exportApp = function(_, args, ctx)
    require_admin(ctx)
    local meta = args.meta or { }
    local version = meta.version
    if not (type(version) == 'string' and version:match(SEMVER_PATTERN)) then
      error("Invalid version '" .. tostring(tostring(version)) .. "': expected semver x.y.z")
    end
    local package = app_package.build_package(meta, {
      seed = seed_map_of(args.seed)
    })
    return yaml.encode(package)
  end,
  previewAppUpdate = function(_, args, ctx)
    require_admin(ctx)
    local package = require_valid_package(parse_yaml(args.yaml))
    local plan = app_apply.preview_update(package, {
      allow_downgrade = args.allowDowngrade == true
    })
    return plan_shape(plan)
  end,
  previewAppPurge = function(_, args, ctx)
    require_admin(ctx)
    local preview = app_apply.preview_purge(args.appId, args.keys or { })
    if preview.error then
      error(preview.error)
    end
    return purge_preview_shape(preview)
  end
}
local Mutation = {
  applyAppUpdate = function(_, args, ctx)
    require_admin(ctx)
    local package = require_valid_package(parse_yaml(args.yaml))
    local decision_info = decisions_map_of(args.decisions)
    local report = app_apply.apply_update(package, decision_info.choices, {
      allow_downgrade = args.allowDowngrade == true,
      rename_names = decision_info.names
    })
    return apply_report_shape(report)
  end,
  purgeAppObsolete = function(_, args, ctx)
    require_admin(ctx)
    local report = app_apply.purge_obsolete(args.appId, args.keys or { }, {
      confirmed = args.confirmed == true
    })
    return purge_report_shape(report)
  end
}
return {
  Query = Query,
  Mutation = Mutation
}
