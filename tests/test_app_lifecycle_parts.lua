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
      if v[3] == VIEW_N then
        views.delete_view(v[1])
      end
    end
    local _list_1 = box.space._tdb_data_views:select({ })
    for _index_0 = 1, #_list_1 do
      local dv = _list_1[_index_0]
      if dv[2] == DV_N then
        data_views.delete_view(dv[1])
      end
    end
    local _list_2 = box.space._tdb_custom_views:select({ })
    for _index_0 = 1, #_list_2 do
      local cv = _list_2[_index_0]
      if cv[2] == PAGE_N then
        box.space._tdb_custom_views:delete(cv[1])
      end
    end
    local _list_3 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_3 do
      local wp = _list_3[_index_0]
      if wp[2] == PLUG_N then
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
    return R.is_nil(spaces.get_space_by_name(SP_B))
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
