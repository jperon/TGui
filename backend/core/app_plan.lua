local SPECIAL_TYPES = {
  seed = true,
  group = true,
  perm = true
}
local _empty_plan
_empty_plan = function(errors)
  return {
    create = { },
    update = { },
    conflict = { },
    keep_local = { },
    obsolete = { },
    rename = { },
    unchanged = { },
    errors = errors or { }
  }
end
local _is_special
_is_special = function(type_)
  return SPECIAL_TYPES[type_] == true
end
local _parse_version
_parse_version = function(value)
  if not (type(value) == 'string') then
    return nil
  end
  local parts = { }
  for part in value:gmatch('[^.]+') do
    local n = tonumber(part)
    if n == nil then
      return nil
    end
    table.insert(parts, n)
  end
  if #parts == 0 then
    return nil
  end
  return parts
end
local compare_versions
compare_versions = function(a, b)
  local pa = _parse_version(a)
  local pb = _parse_version(b)
  if pa == nil or pb == nil then
    return nil
  end
  local count = math.max(#pa, #pb)
  for i = 1, count do
    local x = pa[i] or 0
    local y = pb[i] or 0
    if x > y then
      return 1
    end
    if x < y then
      return -1
    end
  end
  return 0
end
local _downgrade_error
_downgrade_error = function(package, opts)
  if not (opts.installed_version) then
    return nil
  end
  if compare_versions(package.app.version, opts.installed_version) ~= -1 then
    return nil
  end
  if opts.allow_downgrade then
    return nil
  end
  return "downgrade from " .. tostring(opts.installed_version) .. " to " .. tostring(package.app.version) .. " is not allowed"
end
local _validate
_validate = function(package)
  local errors = { }
  local app = package and package.app
  if type(app) ~= 'table' or type(app.id) ~= 'string' or app.id == '' then
    table.insert(errors, "package app id is required")
  end
  local items = package and package.items
  if type(items) ~= 'table' then
    table.insert(errors, "package items must be a list")
    return errors
  end
  for _index_0 = 1, #items do
    local _continue_0 = false
    repeat
      local entry = items[_index_0]
      if type(entry) ~= 'table' then
        table.insert(errors, "package item must be a table")
        _continue_0 = true
        break
      end
      if entry.type == nil then
        table.insert(errors, "package item is missing type")
      end
      if entry.key == nil then
        table.insert(errors, "package item is missing key")
      end
      if entry.fingerprint == nil then
        table.insert(errors, "package item is missing fingerprint")
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return errors
end
local _classify_create
_classify_create = function(entry, local_state, plan)
  if local_state.fingerprint == entry.fingerprint then
    return table.insert(plan.unchanged, entry.key)
  elseif _is_special(entry.type) then
    return table.insert(plan.keep_local, entry)
  else
    return table.insert(plan.conflict, {
      entry,
      local_state,
      entry.fingerprint
    })
  end
end
local _classify_uninstalled
_classify_uninstalled = function(entry, local_state, plan)
  if local_state == nil then
    return table.insert(plan.create, entry)
  end
  return _classify_create(entry, local_state, plan)
end
local _classify_installed
_classify_installed = function(entry, old, local_state, plan)
  local L = old.fingerprint
  local N = entry.fingerprint
  if local_state == nil then
    if N == L or _is_special(entry.type) then
      table.insert(plan.keep_local, entry)
    else
      table.insert(plan.conflict, {
        entry,
        nil,
        N
      })
    end
    return 
  end
  local C = local_state.fingerprint
  if C == L and N == L then
    return table.insert(plan.unchanged, entry.key)
  elseif C == L then
    return table.insert(plan.update, entry)
  elseif N == L then
    return table.insert(plan.keep_local, entry)
  elseif C == N then
    return table.insert(plan.unchanged, entry.key)
  elseif _is_special(entry.type) then
    return table.insert(plan.keep_local, entry)
  else
    return table.insert(plan.conflict, {
      entry,
      local_state,
      N
    })
  end
end
local _sort_by
_sort_by = function(list, keyfn)
  return table.sort(list, function(a, b)
    return keyfn(a) < keyfn(b)
  end)
end
local _sort_plan
_sort_plan = function(plan)
  _sort_by(plan.create, function(e)
    return e.key
  end)
  _sort_by(plan.update, function(e)
    return e.key
  end)
  _sort_by(plan.keep_local, function(e)
    return e.key
  end)
  _sort_by(plan.conflict, function(e)
    return e[1].key
  end)
  _sort_by(plan.rename, function(e)
    return e[1]
  end)
  table.sort(plan.obsolete)
  table.sort(plan.unchanged)
  return plan
end
local _collect_package_keys
_collect_package_keys = function(package)
  local result = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local entry = _list_0[_index_0]
    if entry.key ~= nil then
      result[entry.key] = true
    end
  end
  return result
end
local _mark_obsolete
_mark_obsolete = function(installed, package, consumed, plan)
  local pkg_keys = _collect_package_keys(package)
  for key, info in pairs(installed) do
    local _continue_0 = false
    repeat
      if consumed[key] or pkg_keys[key] then
        _continue_0 = true
        break
      end
      if info.type == 'seed' or info.type == 'perm' then
        _continue_0 = true
        break
      end
      if info.state == 'obsolète' then
        _continue_0 = true
        break
      end
      table.insert(plan.obsolete, key)
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
end
local plan_update
plan_update = function(installed, package, local_states, opts)
  installed = installed or { }
  local_states = local_states or { }
  opts = opts or { }
  local plan = _empty_plan()
  local errors = _validate(package)
  if #errors > 0 then
    plan.errors = errors
    return plan
  end
  local downgrade = _downgrade_error(package, opts)
  if downgrade then
    plan.errors = {
      downgrade
    }
    return plan
  end
  local consumed = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local entry = _list_0[_index_0]
      if entry.renamed_from then
        if installed[entry.renamed_from] then
          consumed[entry.renamed_from] = true
          table.insert(plan.rename, {
            entry.renamed_from,
            entry.key
          })
          _classify_installed(entry, installed[entry.renamed_from], local_states[entry.renamed_from], plan)
        else
          table.insert(plan.create, entry)
        end
        _continue_0 = true
        break
      end
      local old = installed[entry.key]
      if old == nil then
        _classify_uninstalled(entry, local_states[entry.key], plan)
      else
        _classify_installed(entry, old, local_states[entry.key], plan)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  _mark_obsolete(installed, package, consumed, plan)
  return _sort_plan(plan)
end
return {
  plan_update = plan_update,
  compare_versions = compare_versions
}
