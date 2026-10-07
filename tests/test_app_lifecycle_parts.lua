local R = require('tests.runner')
local pkg = require('core.app_package')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local views = require('core.views')
local perms = require('core.permissions')
local data_views = require('core.data_views')
local schema_r = require('resolvers.schema_resolvers')
local cvr = require('resolvers.custom_view_resolvers')
local wpr = require('resolvers.widget_plugin_resolvers')
local dv_r = require('resolvers.data_view_resolvers')
local data_r = require('resolvers.data_resolvers')
local auth = require('core.auth')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_B = "v3b_books_" .. tostring(SUFFIX)
local SP_A = "v3b_authors_" .. tostring(SUFFIX)
local VIEW_N = "v3b_view_" .. tostring(SUFFIX)
local PAGE_N = "v3b_page_" .. tostring(SUFFIX)
local DV_N = "v3b_dv_" .. tostring(SUFFIX)
local PLUG_N = "v3b_plugin_" .. tostring(SUFFIX)
local GROUP_N = "v3b_group_" .. tostring(SUFFIX)
local REL_N = "v3b_rel_" .. tostring(SUFFIX)
local APP_ID = "org.test.v3b_" .. tostring(SUFFIX)
local KEY_CODE = "field:" .. tostring(SP_B) .. ".code"
local KEY_TITLE = "field:" .. tostring(SP_B) .. ".title"
local KEY_QTY = "field:" .. tostring(SP_B) .. ".qty"
local KEY_NOTE = "field:" .. tostring(SP_B) .. ".note"
local KEY_PAGE = "page:" .. tostring(PAGE_N)
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local YAML_PAGE = [[layout:
  direction: vertical
  children:
    - widget:
        title: v3b
        space: v3b_books
]]
local FIX = { }
local seed_opts = { }
local META = {
  id = APP_ID,
  name = 'V3b fixture',
  version = '1.0.0',
  description = 'v3b'
}
local subset
subset = function(package)
  local items
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = package.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key:find(SUFFIX, 1, true) then
        _accum_0[_len_0] = it
        _len_0 = _len_0 + 1
      end
    end
    items = _accum_0
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys or { }
  }
end
local non_seed
non_seed = function(package)
  local _accum_0 = { }
  local _len_0 = 1
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.type ~= 'seed' then
      _accum_0[_len_0] = it
      _len_0 = _len_0 + 1
    end
  end
  return _accum_0
end
local without
without = function(package, item_key)
  local items
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = package.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key ~= item_key then
        _accum_0[_len_0] = it
        _len_0 = _len_0 + 1
      end
    end
    items = _accum_0
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys or { }
  }
end
local reversion
reversion = function(package, version)
  return {
    app = {
      id = package.app.id,
      name = package.app.name,
      version = version,
      description = package.app.description
    },
    items = package.items,
    seed_keys = package.seed_keys or { }
  }
end
local seed_count
seed_count = function(package)
  local n = 0
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.type == 'seed' then
      n = n + 1
    end
  end
  return n
end
local row_dump
row_dump = function(space_name)
  local rows = { }
  local sp = box.space["data_" .. tostring(space_name)]
  if not (sp) then
    return rows
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local d
    if type(t[2]) == 'string' then
      d = json.decode(t[2])
    else
      d = t[2]
    end
    table.insert(rows, json.encode(d))
  end
  table.sort(rows)
  return rows
end
local local_rows
local_rows = function(space_name)
  local rows = { }
  local sp = box.space["data_" .. tostring(space_name)]
  if not (sp) then
    return rows
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local d
    if type(t[2]) == 'string' then
      d = json.decode(t[2])
    else
      d = t[2]
    end
    table.insert(rows, d)
  end
  return rows
end
local count_rows
count_rows = function(space_name)
  local sp = box.space["data_" .. tostring(space_name)]
  return sp and #sp:select({ }) or 0
end
local item_state
item_state = function(app_id, key)
  local t = box.space._tdb_app_items:get({
    app_id,
    key
  })
  return t and t[6] or nil
end
local item_row
item_row = function(app_id, key)
  return box.space._tdb_app_items:get({
    app_id,
    key
  })
end
local count_items
count_items = function(app_id)
  return #box.space._tdb_app_items.index.by_app:select({
    app_id
  })
end
local clean_app
clean_app = function()
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    APP_ID
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    box.space._tdb_app_items:delete({
      t[1],
      t[2]
    })
  end
  return box.space._tdb_apps:delete(APP_ID)
end
local field_by_name
field_by_name = function(space_id, name)
  local _list_0 = spaces.list_fields(space_id)
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    if f.name == name then
      return f
    end
  end
  return nil
end
local find_record
find_record = function(space_name, key_field, key_val)
  local sp = box.space["data_" .. tostring(space_name)]
  if not (sp) then
    return nil
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local d
    if type(t[2]) == 'string' then
      d = json.decode(t[2])
    else
      d = t[2]
    end
    if d[key_field] ~= nil and tostring(d[key_field]) == tostring(key_val) then
      return {
        id = t[1],
        data = d
      }
    end
  end
  return nil
end
local non_seed_rows
non_seed_rows = function(space_name, key_field)
  local n = 0
  local _list_0 = local_rows(space_name)
  for _index_0 = 1, #_list_0 do
    local d = _list_0[_index_0]
    if d[key_field] == nil then
      n = n + 1
    end
  end
  return n
end
local set_seed
set_seed = function(package, space, key, data)
  local items = { }
  local found = false
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.type == 'seed' and it.content.space == space and tostring(it.content.key) == tostring(key) then
      table.insert(items, {
        type = 'seed',
        key = it.key,
        content = {
          space = space,
          key = key,
          data = data
        }
      })
      found = true
    else
      table.insert(items, it)
    end
  end
  if not (found) then
    table.insert(items, {
      type = 'seed',
      key = "seed:" .. tostring(space) .. "|" .. tostring(key),
      content = {
        space = space,
        key = key,
        data = data
      }
    })
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys
  }
end
local in_list
in_list = function(list, key)
  for _index_0 = 1, #list do
    local k = list[_index_0]
    if k == key then
      return true
    end
  end
  return false
end
local build_current
build_current = function(version)
  local meta = {
    id = APP_ID,
    name = 'V3b fixture',
    version = version,
    description = 'v3b'
  }
  return subset(pkg.build_package(meta, {
    seed = seed_opts
  }))
end
local rename_item
rename_item = function(package, old_key, new_key)
  local items = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key == old_key then
      table.insert(items, {
        type = it.type,
        key = new_key,
        content = it.content,
        renamed_from = old_key
      })
    else
      table.insert(items, it)
    end
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys
  }
end
local str_after
str_after = function(key, prefix)
  if not (key:sub(1, #prefix) == prefix) then
    return nil
  end
  local rest = key:sub(#prefix + 1)
  return rest ~= '' and rest or nil
end
local retarget_key
retarget_key = function(key, old_space, new_space)
  local _list_0 = {
    'field:',
    'relation:',
    'view:'
  }
  for _index_0 = 1, #_list_0 do
    local prefix = _list_0[_index_0]
    local rest = str_after(key, tostring(prefix) .. tostring(old_space) .. ".")
    if rest then
      return tostring(prefix) .. tostring(new_space) .. "." .. tostring(rest)
    end
  end
  local rest = str_after(key, "seed:" .. tostring(old_space) .. "|")
  if rest then
    return "seed:" .. tostring(new_space) .. "|" .. tostring(rest)
  end
  return key
end
local rename_space_pkg
rename_space_pkg = function(package, old_space, new_space)
  local items = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local it = _list_0[_index_0]
      if it.type == 'space' and it.key == "space:" .. tostring(old_space) then
        table.insert(items, {
          type = 'space',
          key = "space:" .. tostring(new_space),
          content = it.content,
          renamed_from = it.key
        })
        _continue_0 = true
        break
      end
      local new_key = retarget_key(it.key, old_space, new_space)
      local content = it.content
      if it.type == 'relation' and content.toSpace == old_space then
        content = {
          fromSpace = content.fromSpace,
          fromField = content.fromField,
          toSpace = new_space,
          toField = content.toField
        }
      end
      if it.type == 'dataview' and content.sourceSpace == old_space then
        content = {
          name = content.name,
          description = content.description,
          sourceSpace = new_space,
          config = content.config
        }
      end
      local renamed = new_key ~= it.key
      if renamed or content ~= it.content then
        local entry = {
          type = it.type,
          key = new_key,
          content = content
        }
        if renamed then
          entry.renamed_from = it.key
        end
        table.insert(items, entry)
      else
        table.insert(items, it)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys
  }
end
R.describe("v3b — fixture", function()
  R.it("creates spaces, fields, relation and data", function()
    local books = spaces.create_user_space(SP_B, 'v3b books')
    local authors = spaces.create_user_space(SP_A, 'v3b authors')
    FIX.books_id = books.id
    FIX.authors_id = authors.id
    spaces.add_field(books.id, 'code', 'String', false, 'natural key')
    spaces.add_field(books.id, 'title', 'String', false, '')
    spaces.add_field(books.id, 'qty', 'Int', false, '')
    local fk = spaces.add_field(books.id, 'author_id', 'Int', false, '')
    local seq = spaces.add_field(authors.id, 'seq_id', 'Sequence')
    spaces.add_field(authors.id, 'name', 'String', false, '')
    local res = schema_r.Mutation.createRelation({ }, {
      input = {
        name = REL_N,
        fromSpaceId = books.id,
        fromFieldId = fk.id,
        toSpaceId = authors.id,
        toFieldId = seq.id,
        reprFormula = '@name'
      }
    }, CTX)
    FIX.fk_id = fk.id
    FIX.rel_id = res.id
    local _list_0 = {
      {
        code = 'V3B-1',
        title = 'Premier',
        qty = 2
      },
      {
        code = 'V3B-2',
        title = 'Second',
        qty = 5
      }
    }
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      data_r.Mutation.insertRecord({ }, {
        spaceId = books.id,
        data = row
      }, CTX)
    end
    return R.ok(res)
  end)
  R.it("creates a view, a page, a data view, a plugin, a group and permissions", function()
    local v = views.create_view(FIX.books_id, VIEW_N, 'grid', {
      layout = {
        direction = 'vertical',
        children = { }
      }
    })
    FIX.view_id = v.id
    local p = cvr.Mutation.createCustomView({ }, {
      name = PAGE_N,
      description = 'v3b page',
      yaml = YAML_PAGE
    }, CTX)
    FIX.page_id = p.id
    local dv = dv_r.Mutation.createDataView(nil, {
      input = {
        name = DV_N,
        description = 'v3b dv',
        sourceSpace = SP_B,
        config = json.encode({
          columns = {
            'code',
            'title'
          }
        })
      }
    }, CTX)
    FIX.dv_id = dv.id
    local wp = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = PLUG_N,
        description = 'v3b plugin',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = "render 'ok'",
        templateCode = 'div ok'
      }
    }, CTX)
    FIX.plugin_id = wp.id
    local g = perms.create_group(GROUP_N, 'v3b group')
    FIX.group_id = g.id
    perms.grant(g.id, 'space', FIX.books_id, 'read')
    return R.ok(v and p and dv and wp and g)
  end)
  return R.it("builds the package v1.0.0 with two seed lines", function()
    seed_opts[SP_B] = 'code'
    FIX.PKG = subset(pkg.build_package(META, {
      seed = seed_opts
    }))
    return R.eq(seed_count(FIX.PKG), 2, 'two seed items')
  end)
end)
local remove_elements
remove_elements = function()
  if FIX.rel_id then
    schema_r.Mutation.deleteRelation({ }, {
      id = FIX.rel_id
    }, CTX)
  end
  if FIX.view_id then
    views.delete_view(FIX.view_id)
  end
  if FIX.page_id then
    box.space._tdb_custom_views:delete(FIX.page_id)
  end
  if FIX.dv_id then
    data_views.delete_view(FIX.dv_id)
  end
  if FIX.plugin_id then
    box.space._tdb_widget_plugins:delete(FIX.plugin_id)
  end
  if FIX.group_id then
    perms.delete_group(FIX.group_id)
  end
  spaces.delete_user_space(SP_B)
  spaces.delete_user_space(SP_A)
  FIX.rel_id = nil
  FIX.view_id = nil
  FIX.page_id = nil
  FIX.dv_id = nil
  FIX.plugin_id = nil
  FIX.group_id = nil
end
R.describe("v3b — installation", function()
  return R.it("empties the local elements and installs the package", function()
    remove_elements()
    local report = apply.apply_update(FIX.PKG, { }, { })
    R.ok(report.ok, report.error)
    R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.0.0', 'installed version')
    R.eq(count_items(APP_ID), #FIX.PKG.items, 'all items tracked')
    return R.eq(count_rows(SP_B), seed_count(FIX.PKG), 'seed rows inserted on first install')
  end)
end)
R.describe("v3b partie 1 — obsolètes", function()
  R.it("marks a page removed from the package as obsolete, keeping it locally", function()
    local before_rows = count_rows(SP_B)
    local PKG2 = reversion(without(FIX.PKG, KEY_PAGE), '1.1.0')
    local report = apply.apply_update(PKG2, { }, { })
    R.ok(report.ok, report.error)
    R.eq(item_state(APP_ID, KEY_PAGE), 'obsolète', 'page marked obsolete')
    R.ok(pkg.describe_local('page', KEY_PAGE), 'page still present locally')
    return R.eq(count_rows(SP_B), before_rows, 'no record lost')
  end)
  return R.it("reactivates the item when it reappears in a package", function()
    local PKG3 = reversion(FIX.PKG, '1.2.0')
    local report = apply.apply_update(PKG3, { }, { })
    R.ok(report.ok, report.error)
    return R.eq(item_state(APP_ID, KEY_PAGE), 'actif', 'page active again')
  end)
end)
R.describe("v3b partie 2 — lignes seed", function()
  R.it("prepares: one non-seed local record and one locally modified seed", function()
    local sid = spaces.get_space_by_name(SP_B).id
    data_r.Mutation.insertRecord({ }, {
      spaceId = sid,
      data = {
        title = 'hors seed',
        qty = 9
      }
    }, CTX)
    local rec = find_record(SP_B, 'code', 'V3B-2')
    R.ok(rec, 'seed V3B-2 exists')
    rec.data.title = 'Local second'
    box.space["data_" .. tostring(SP_B)]:replace({
      rec.id,
      json.encode(rec.data)
    })
    FIX.non_seed_before = non_seed_rows(SP_B, 'code')
    FIX.rows_before = count_rows(SP_B)
    return R.eq(FIX.non_seed_before, 1, 'one non-seed record')
  end)
  R.it("adds new seed lines, updates unchanged ones and keeps locally modified ones", function()
    local PKG_A = reversion(FIX.PKG, '1.3.0')
    PKG_A = set_seed(PKG_A, SP_B, 'V3B-1', {
      code = 'V3B-1',
      title = 'Delivered premier',
      qty = 2
    })
    PKG_A = set_seed(PKG_A, SP_B, 'V3B-2', {
      code = 'V3B-2',
      title = 'Delivered second',
      qty = 5
    })
    PKG_A = set_seed(PKG_A, SP_B, 'V3B-3', {
      code = 'V3B-3',
      title = 'Nouveau',
      qty = 7
    })
    local report = apply.apply_update(PKG_A, { }, { })
    R.ok(report.ok, report.error)
    R.ok(in_list(report.created, "seed:" .. tostring(SP_B) .. "|V3B-3"), 'new seed created')
    R.ok(in_list(report.updated, "seed:" .. tostring(SP_B) .. "|V3B-1"), 'unchanged seed updated')
    R.ok(in_list(report.kept, "seed:" .. tostring(SP_B) .. "|V3B-2"), 'locally modified seed kept')
    return R.eq(item_state(APP_ID, "seed:" .. tostring(SP_B) .. "|V3B-1"), 'actif')
  end)
  return R.it("propagates the delivered data and preserves local and non-seed records", function()
    R.eq((find_record(SP_B, 'code', 'V3B-1')).data.title, 'Delivered premier')
    R.eq((find_record(SP_B, 'code', 'V3B-2')).data.title, 'Local second', 'local kept')
    R.eq((find_record(SP_B, 'code', 'V3B-3')).data.title, 'Nouveau')
    R.eq(non_seed_rows(SP_B, 'code'), FIX.non_seed_before, 'non-seed record count unchanged')
    return R.eq(count_rows(SP_B), FIX.rows_before + 1, 'exactly one seed line added, none removed')
  end)
end)
local SP_A2 = tostring(SP_A) .. "_ren"
local PAGE_N2 = tostring(PAGE_N) .. "2"
local PLUG_N2 = tostring(PLUG_N) .. "2"
R.describe("v3b partie 3 — renommages", function()
  R.it("renames a field in place and keeps values under the new name", function()
    local sid = spaces.get_space_by_name(SP_A).id
    data_r.Mutation.insertRecord({ }, {
      spaceId = sid,
      data = {
        name = 'Alice'
      }
    }, CTX)
    R.ok((find_record(SP_A, 'name', 'Alice')), 'author record inserted')
    local base = build_current('1.4.0')
    local PKG_F = reversion((rename_item(base, "field:" .. tostring(SP_A) .. ".name", "field:" .. tostring(SP_A) .. ".nom")), '1.4.0')
    local report = apply.apply_update(PKG_F, { }, { })
    R.ok(report.ok, report.error)
    R.ok(pkg.describe_local('field', "field:" .. tostring(SP_A) .. ".nom"), 'new field present')
    R.is_nil(pkg.describe_local('field', "field:" .. tostring(SP_A) .. ".name"), 'old field gone')
    local rec = find_record(SP_A, 'nom', 'Alice')
    R.ok(rec, 'value preserved under the new key')
    R.is_nil(rec.data.name, 'old JSON key removed')
    R.eq(item_state(APP_ID, "field:" .. tostring(SP_A) .. ".nom"), 'actif')
    return R.is_nil(item_row(APP_ID, "field:" .. tostring(SP_A) .. ".name"))
  end)
  R.it("renames a page and a plugin in place", function()
    local base = build_current('1.5.0')
    local PKG_P = rename_item(base, "page:" .. tostring(PAGE_N), "page:" .. tostring(PAGE_N2))
    PKG_P = rename_item(PKG_P, "plugin:" .. tostring(PLUG_N), "plugin:" .. tostring(PLUG_N2))
    local report = apply.apply_update(PKG_P, { }, { })
    R.ok(report.ok, report.error)
    R.ok(pkg.describe_local('page', "page:" .. tostring(PAGE_N2)), 'page renamed')
    R.is_nil(pkg.describe_local('page', "page:" .. tostring(PAGE_N)), 'old page gone')
    R.ok(pkg.describe_local('plugin', "plugin:" .. tostring(PLUG_N2)), 'plugin renamed')
    return R.is_nil(pkg.describe_local('plugin', "plugin:" .. tostring(PLUG_N)), 'old plugin gone')
  end)
  R.it("renames a space in place, remapping child keys and preserving records", function()
    local before = local_rows(SP_A)
    local PKG_S = reversion((rename_space_pkg((build_current('1.6.0')), SP_A, SP_A2)), '2.0.0')
    FIX.pkg_s = PKG_S
    local dbg = apply.preview_update(PKG_S)
    R.eq(#dbg.create, 0, 'rename is previewed as a rename, not a creation')
    R.eq(#dbg.rename, 3, 'space plus two child fields renamed')
    R.is_nil(box.space._tdb_spaces.index.by_name:get(SP_A2), 'SP_A2 absent before apply')
    local report = apply.apply_update(PKG_S, { }, { })
    R.ok(report.ok, report.error)
    R.ok(spaces.get_space_by_name(SP_A2), 'new space exists')
    R.is_nil(spaces.get_space_by_name(SP_A), 'old space gone')
    R.ok(box.space["data_" .. tostring(SP_A2)], 'new data space exists')
    R.is_nil(box.space["data_" .. tostring(SP_A)], 'old data space gone')
    R.eq(#local_rows(SP_A2), #before, 'records preserved')
    R.ok((find_record(SP_A2, 'nom', 'Alice')), 'author record preserved')
    R.ok(pkg.describe_local('field', "field:" .. tostring(SP_A2) .. ".nom"), 'child field remapped')
    R.is_nil(item_row(APP_ID, "field:" .. tostring(SP_A) .. ".nom"), 'old child key untracked')
    return R.eq(item_state(APP_ID, "space:" .. tostring(SP_A2)), 'actif')
  end)
  R.it("a further update with the same package recreates nothing", function()
    local report = apply.apply_update(FIX.pkg_s, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, 0, 'nothing recreated')
    return R.eq(item_state(APP_ID, "space:" .. tostring(SP_A2)), 'actif')
  end)
  return R.it("refuses a rename whose target already exists locally", function()
    cvr.Mutation.createCustomView({ }, {
      name = tostring(PAGE_N2) .. "_tgt",
      description = 'taken',
      yaml = ''
    }, CTX)
    local before_version = box.space._tdb_apps:get(APP_ID)[3]
    local PKG_C = reversion((rename_item((build_current('2.1.0')), "page:" .. tostring(PAGE_N2), "page:" .. tostring(PAGE_N2) .. "_tgt")), '2.1.0')
    local report = apply.apply_update(PKG_C, { }, { })
    R.nok(report.ok)
    R.matches(report.error, 'already exists locally')
    return R.eq(box.space._tdb_apps:get(APP_ID)[3], before_version, 'no write')
  end)
end)
R.describe("v3b partie 4 — aperçu des pertes et purge", function()
  R.it("makes a field obsolete and previews its losses exactly, without writing", function()
    local sid = spaces.get_space_by_name(SP_B).id
    spaces.add_field(sid, 'legacy', 'String', false, '')
    local sp = box.space["data_" .. tostring(SP_B)]
    local n = 0
    local _list_0 = sp:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local d = json.decode(t[2])
      if n < 2 then
        d.legacy = "v" .. tostring(n)
        sp:replace({
          t[1],
          json.encode(d)
        })
      end
      n = n + 1
    end
    R.ok((apply.apply_update((build_current('2.1.0')), { }, { })).ok, 'legacy field installed')
    local PKG_N = reversion((without((build_current('2.2.0')), "field:" .. tostring(SP_B) .. ".legacy")), '2.2.0')
    R.ok((apply.apply_update(PKG_N, { }, { })).ok, 'legacy field removed from the package')
    R.eq(item_state(APP_ID, "field:" .. tostring(SP_B) .. ".legacy"), 'obsolète')
    R.ok(field_by_name(sid, 'legacy'), 'field still present locally')
    local pv = apply.preview_purge(APP_ID, {
      "field:" .. tostring(SP_B) .. ".legacy"
    })
    R.is_nil(pv.error)
    R.eq(#pv.losses, 1)
    R.eq(pv.losses[1].type, 'field')
    R.eq(pv.losses[1].records, 2)
    R.eq(pv.total_records, 2)
    return R.ok(field_by_name(sid, 'legacy'), 'preview wrote nothing')
  end)
  R.it("refuses to purge an active or unknown item and requires confirmation", function()
    local sid = spaces.get_space_by_name(SP_B).id
    local r = apply.purge_obsolete(APP_ID, {
      "field:" .. tostring(SP_B) .. ".title"
    }, {
      confirmed = true
    })
    R.nok(r.ok)
    R.matches(r.error, 'not obsolete')
    R.is_nil(r.purged[1])
    local pv = apply.preview_purge(APP_ID, {
      "field:" .. tostring(SP_B) .. ".local_xyz"
    })
    R.matches(pv.error, 'unknown app item')
    local r2 = apply.purge_obsolete(APP_ID, {
      "field:" .. tostring(SP_B) .. ".legacy"
    }, { })
    R.nok(r2.ok)
    R.matches(r2.error, 'confirmation required')
    return R.ok(field_by_name(sid, 'legacy'), 'no purge without confirmation')
  end)
  R.it("purges an obsolete field: removes the key from records and nothing else", function()
    local sid = spaces.get_space_by_name(SP_B).id
    local rows_before = count_rows(SP_B)
    local r = apply.purge_obsolete(APP_ID, {
      "field:" .. tostring(SP_B) .. ".legacy"
    }, {
      confirmed = true
    })
    R.ok(r.ok, r.error)
    R.is_nil(field_by_name(sid, 'legacy'))
    R.is_nil(item_row(APP_ID, "field:" .. tostring(SP_B) .. ".legacy"))
    R.eq(count_rows(SP_B), rows_before, 'record count unchanged')
    local has = false
    local _list_0 = local_rows(SP_B)
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      if row.legacy ~= nil then
        has = true
      end
    end
    R.nok(has, 'legacy key removed from every record')
    return R.ok(field_by_name(sid, 'title'), 'other fields untouched')
  end)
  R.it("purges an obsolete space after its relation", function()
    local base = build_current('2.3.0')
    local pkg_r = reversion((without((without(base, "relation:" .. tostring(SP_B) .. ".author_id")), "space:" .. tostring(SP_A2))), '2.3.0')
    local r = apply.apply_update(pkg_r, { }, { })
    R.ok(r.ok, r.error)
    R.eq(item_state(APP_ID, "relation:" .. tostring(SP_B) .. ".author_id"), 'obsolète')
    R.eq(item_state(APP_ID, "space:" .. tostring(SP_A2)), 'obsolète')
    R.ok((apply.purge_obsolete(APP_ID, {
      "relation:" .. tostring(SP_B) .. ".author_id"
    }, {
      confirmed = true
    })).ok)
    local pv = apply.preview_purge(APP_ID, {
      "space:" .. tostring(SP_A2)
    })
    R.is_nil(pv.error)
    R.eq(pv.losses[1].records, 1)
    R.eq(pv.losses[1].fields, 2)
    R.eq(pv.losses[1].relations, 0)
    local rp = apply.purge_obsolete(APP_ID, {
      "space:" .. tostring(SP_A2)
    }, {
      confirmed = true
    })
    R.ok(rp.ok, rp.error)
    R.is_nil(spaces.get_space_by_name(SP_A2))
    R.is_nil(box.space["data_" .. tostring(SP_A2)])
    R.is_nil(item_row(APP_ID, "space:" .. tostring(SP_A2)))
    return R.is_nil(item_row(APP_ID, "field:" .. tostring(SP_A2) .. ".nom"))
  end)
  return R.it("rolls back a purge that fails in the middle", function()
    local sid = spaces.get_space_by_name(SP_B).id
    local f = spaces.add_field(sid, 'legacy2', 'String', false, '')
    local sp = box.space["data_" .. tostring(SP_B)]
    local _list_0 = sp:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local d = json.decode(t[2])
      if d.legacy2 == nil and d.code == 'V3B-1' then
        d.legacy2 = 'keepme'
        sp:replace({
          t[1],
          json.encode(d)
        })
      end
    end
    box.space._tdb_app_items:replace({
      APP_ID,
      "field:" .. tostring(SP_B) .. ".legacy2",
      'field',
      f.id,
      'fp',
      'obsolète',
      '2.3.0'
    })
    box.space._tdb_app_items:replace({
      APP_ID,
      "page:" .. tostring(PAGE_N2) .. "_ghost",
      'page',
      '',
      'fp',
      'obsolète',
      '2.3.0'
    })
    local r = apply.purge_obsolete(APP_ID, {
      "field:" .. tostring(SP_B) .. ".legacy2",
      "page:" .. tostring(PAGE_N2) .. "_ghost"
    }, {
      confirmed = true
    })
    R.nok(r.ok)
    R.matches(r.error, 'missing local_id')
    R.ok(field_by_name(sid, 'legacy2'), 'field restored by rollback')
    R.ok((find_record(SP_B, 'legacy2', 'keepme')), 'value preserved through rollback')
    return R.eq(item_state(APP_ID, "field:" .. tostring(SP_B) .. ".legacy2"), 'obsolète', 'tracking restored')
  end)
end)
R.describe("v3b — cleanup", function()
  return R.it("removes the fixture elements and tracking rows", function()
    local sid = spaces.get_space_by_name(SP_B)
    if sid then
      local _list_0 = box.space._tdb_relations.index.by_from:select({
        sid.id
      })
      for _index_0 = 1, #_list_0 do
        local t = _list_0[_index_0]
        box.space._tdb_relations:delete(t[1])
      end
      local _list_1 = box.space._tdb_relations.index.by_to:select({
        sid.id
      })
      for _index_0 = 1, #_list_1 do
        local t = _list_1[_index_0]
        box.space._tdb_relations:delete(t[1])
      end
    end
    local _list_0 = box.space._tdb_views:select({ })
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      if v[3]:find(VIEW_N, 1, true) then
        views.delete_view(v[1])
      end
    end
    local _list_1 = box.space._tdb_data_views:select({ })
    for _index_0 = 1, #_list_1 do
      local dv = _list_1[_index_0]
      if dv[2]:find(DV_N, 1, true) then
        data_views.delete_view(dv[1])
      end
    end
    local _list_2 = box.space._tdb_custom_views:select({ })
    for _index_0 = 1, #_list_2 do
      local cv = _list_2[_index_0]
      if cv[2]:find(PAGE_N, 1, true) then
        box.space._tdb_custom_views:delete(cv[1])
      end
    end
    local _list_3 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_3 do
      local wp = _list_3[_index_0]
      if wp[2]:find(PLUG_N, 1, true) then
        box.space._tdb_widget_plugins:delete(wp[1])
      end
    end
    local _list_4 = perms.list_groups()
    for _index_0 = 1, #_list_4 do
      local g = _list_4[_index_0]
      if g.name == GROUP_N then
        perms.delete_group(g.id)
      end
    end
    clean_app()
    spaces.delete_user_space(SP_B)
    spaces.delete_user_space(SP_A)
    spaces.delete_user_space(SP_A2)
    R.is_nil(spaces.get_space_by_name(SP_B))
    return R.is_nil(spaces.get_space_by_name(SP_A2))
  end)
end)
return {
  FIX = FIX,
  APP_ID = APP_ID,
  SP_B = SP_B,
  SP_A = SP_A,
  KEY_CODE = KEY_CODE,
  KEY_TITLE = KEY_TITLE,
  KEY_QTY = KEY_QTY,
  KEY_NOTE = KEY_NOTE,
  KEY_PAGE = KEY_PAGE,
  VIEW_N = VIEW_N,
  PAGE_N = PAGE_N,
  DV_N = DV_N,
  PLUG_N = PLUG_N,
  GROUP_N = GROUP_N,
  REL_N = REL_N,
  CTX = CTX,
  subset = subset,
  without = without,
  reversion = reversion,
  seed_count = seed_count,
  row_dump = row_dump,
  local_rows = local_rows,
  count_rows = count_rows,
  item_state = item_state,
  item_row = item_row,
  count_items = count_items,
  clean_app = clean_app,
  field_by_name = field_by_name
}
