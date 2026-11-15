local R = require('tests.runner')
local pkg = require('core.app_package')
local spaces = require('core.spaces')
local views = require('core.views')
local perms = require('core.permissions')
local schema_r = require('resolvers.schema_resolvers')
local cvr = require('resolvers.custom_view_resolvers')
local wpr = require('resolvers.widget_plugin_resolvers')
local dv_r = require('resolvers.data_view_resolvers')
local data_r = require('resolvers.data_resolvers')
local auth = require('core.auth')
local json = require('json')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_BOOKS = "apkg_books_" .. tostring(SUFFIX)
local SP_AUTHORS = "apkg_authors_" .. tostring(SUFFIX)
local VIEW_NAME = "apkg_view_" .. tostring(SUFFIX)
local PAGE_NAME = "apkg_page_" .. tostring(SUFFIX)
local DV_NAME = "apkg_dataview_" .. tostring(SUFFIX)
local PLUGIN_NAME = "apkg_plugin_" .. tostring(SUFFIX)
local GROUP_NAME = "apkg_group_" .. tostring(SUFFIX)
local REL_NAME = "apkg_rel_" .. tostring(SUFFIX)
local SP_SEED = "apkg_seed_" .. tostring(SUFFIX)
local SP_ESP = "apkg_esp.ace_" .. tostring(SUFFIX)
local FLD_ESP = 'a.b|c:d%e'
local FLDN_ESP = 'plain_field'
local GRP_ESP = "apkg_grp|x.y_" .. tostring(SUFFIX)
local GRP_FORGE = tostring(GRP_ESP) .. "|space|*|read"
local FIX_ESP = { }
local META = {
  id = 'org.test.apkg',
  name = 'Apkg fixture',
  version = '1.0.0',
  description = 'app package fixture'
}
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local YAML_PAGE = [[layout:
  direction: vertical
  children:
    - widget:
        title: App package
        space: apkg
]]
local FIX = { }
local FIX_SEED = { }
local PKG = nil
local PKG2 = nil
local seed_opts = { }
local find_item
find_item = function(package, key)
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key == key then
      return it
    end
  end
  return nil
end
local seed_error
seed_error = function(seed_config)
  local ok, err = pcall(function()
    return pkg.build_package(META, {
      seed = seed_config
    })
  end)
  R.nok(ok, 'expected an invalid seed configuration to raise')
  return tostring(err)
end
R.describe("app_package — canonical", function()
  R.it("is independent of object key order, recursively", function()
    local a = {
      b = 1,
      a = 2,
      c = {
        z = 9,
        y = {
          q = 1,
          p = 2
        }
      }
    }
    local b = {
      c = {
        y = {
          p = 2,
          q = 1
        },
        z = 9
      },
      a = 2,
      b = 1
    }
    return R.eq(pkg.canonical(a), pkg.canonical(b))
  end)
  R.it("keeps array order", function()
    return R.ne(pkg.canonical({
      1,
      2,
      3
    }), pkg.canonical({
      3,
      2,
      1
    }))
  end)
  R.it("encodes scalars through Tarantool json.encode", function()
    R.eq(pkg.canonical('x'), json.encode('x'))
    R.eq(pkg.canonical(42), json.encode(42))
    R.eq(pkg.canonical(true), json.encode(true))
    return R.eq(pkg.canonical(nil), 'null')
  end)
  return R.it("canonicalizes an empty table as an empty array", function()
    return R.eq(pkg.canonical({ }), '[]')
  end)
end)
R.describe("app_package — fingerprint", function()
  R.it("is a 64-char lowercase hex digest", function()
    local fp = pkg.fingerprint({
      a = 1
    })
    R.eq(#fp, 64)
    return R.matches(fp, '^[0-9a-f]+$')
  end)
  R.it("is stable for equal content, whatever the key order", function()
    return R.eq(pkg.fingerprint({
      a = 1,
      b = 'x'
    }), pkg.fingerprint({
      b = 'x',
      a = 1
    }))
  end)
  return R.it("changes when the content changes", function()
    R.ne(pkg.fingerprint({
      a = 1
    }), pkg.fingerprint({
      a = 2
    }))
    return R.ne(pkg.fingerprint({
      a = 1
    }), pkg.fingerprint({
      a = 1,
      b = 2
    }))
  end)
end)
R.describe("app_package — key escaping", function()
  R.it("key_part/unkey_part round-trip every special character", function()
    local _list_0 = {
      '',
      'plain',
      'a.b|c:d%e',
      '%2E',
      'esp ace',
      'accÉnt',
      'idself.id',
      'a|space|*|admin',
      'Esp.ace',
      'x%7Cy'
    }
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      R.eq(pkg.unkey_part(pkg.key_part(s)), s, "round-trip " .. tostring(s))
    end
  end)
  R.it("only the four delimiters are escaped", function()
    R.eq(pkg.key_part('a.b|c:d%e'), 'a%2Eb%7Cc%3Ad%25e')
    R.eq(pkg.key_part('plain_name'), 'plain_name')
    return R.eq(pkg.key_part('%2E'), '%252E')
  end)
  return R.it("a component never keeps an unescaped delimiter", function()
    local k = pkg.key_part('a.b|c:d%e')
    R.is_nil((k:find('.', 1, true)))
    R.is_nil((k:find('|', 1, true)))
    return R.is_nil((k:find(':', 1, true)))
  end)
end)
R.describe("app_package — system spaces (_tdb_apps, _tdb_app_items)", function()
  R.it("migrate creates both spaces with their indexes", function()
    spaces.migrate()
    R.ok(box.space._tdb_apps, "_tdb_apps created by migrate")
    R.ok(box.space._tdb_app_items, "_tdb_app_items created by migrate")
    R.ok(box.space._tdb_apps.index.primary)
    R.ok(box.space._tdb_app_items.index.primary)
    return R.ok(box.space._tdb_app_items.index.by_app)
  end)
  R.it("recreates them when they are missing", function()
    box.space._tdb_app_items:drop()
    box.space._tdb_apps:drop()
    spaces.migrate()
    R.ok(box.space._tdb_apps)
    R.ok(box.space._tdb_app_items)
    return R.ok(box.space._tdb_app_items.index.by_app)
  end)
  R.it("exposes the documented columns", function()
    local apps_cols
    do
      local _tbl_0 = { }
      local _list_0 = box.space._tdb_apps:format()
      for _index_0 = 1, #_list_0 do
        local f = _list_0[_index_0]
        _tbl_0[f.name] = true
      end
      apps_cols = _tbl_0
    end
    R.ok(apps_cols['app_id'])
    R.ok(apps_cols['name'])
    R.ok(apps_cols['version'])
    R.ok(apps_cols['installed_at'])
    R.ok(apps_cols['source'])
    local items_cols
    do
      local _tbl_0 = { }
      local _list_0 = box.space._tdb_app_items:format()
      for _index_0 = 1, #_list_0 do
        local f = _list_0[_index_0]
        _tbl_0[f.name] = true
      end
      items_cols = _tbl_0
    end
    local _list_0 = {
      'app_id',
      'key',
      'type',
      'local_id',
      'fingerprint',
      'state',
      'version'
    }
    for _index_0 = 1, #_list_0 do
      local col = _list_0[_index_0]
      R.ok(items_cols[col], "missing column " .. tostring(col))
    end
  end)
  return R.it("has a composite primary key {app_id, key} and a non-unique by_app", function()
    local now = os.time()
    box.space._tdb_apps:insert({
      'apkg_sys_test',
      'Sys',
      '1.0.0',
      now,
      'test'
    })
    box.space._tdb_app_items:insert({
      'apkg_sys_test',
      'k1',
      'space',
      'loc1',
      'fp1',
      'active',
      '1.0.0'
    })
    box.space._tdb_app_items:insert({
      'apkg_sys_test',
      'k2',
      'field',
      'loc2',
      'fp2',
      'active',
      '1.0.0'
    })
    R.eq(#box.space._tdb_app_items.index.by_app:select({
      'apkg_sys_test'
    }), 2)
    local ok_dup = pcall(function()
      return box.space._tdb_app_items:insert({
        'apkg_sys_test',
        'k1',
        'space',
        'loc9',
        'fp9',
        'active',
        '1.0.0'
      })
    end)
    R.eq(ok_dup, false, "duplicate {app_id, key} must be rejected")
    box.space._tdb_app_items:delete({
      'apkg_sys_test',
      'k1'
    })
    box.space._tdb_app_items:delete({
      'apkg_sys_test',
      'k2'
    })
    box.space._tdb_apps:delete('apkg_sys_test')
    return R.eq(#box.space._tdb_app_items.index.by_app:select({
      'apkg_sys_test'
    }), 0)
  end)
end)
R.describe("app_package — fixture", function()
  R.it("creates the two test spaces", function()
    local books = spaces.create_user_space(SP_BOOKS, 'apkg books')
    local authors = spaces.create_user_space(SP_AUTHORS, 'apkg authors')
    FIX.books_id = books.id
    FIX.authors_id = authors.id
    R.ok(books)
    return R.ok(authors)
  end)
  R.it("adds fields of several types, including a formula field", function()
    R.ok(spaces.add_field(FIX.books_id, 'code', 'String', true, 'natural key'))
    R.ok(spaces.add_field(FIX.books_id, 'title', 'String', false, ''))
    R.ok(spaces.add_field(FIX.books_id, 'qty', 'Int', false, ''))
    local total = spaces.add_field(FIX.books_id, 'total', 'Int', false, '', '(self.qty or 0) * 2')
    R.eq(total.formula, '(self.qty or 0) * 2')
    R.eq(total.language, 'lua')
    local seq = spaces.add_field(FIX.authors_id, 'seq_id', 'Sequence')
    FIX.seq_id = seq.id
    return R.ok(spaces.add_field(FIX.authors_id, 'name', 'String', false, ''))
  end)
  R.it("creates a relation books.author_id → authors.seq_id", function()
    local fk = spaces.add_field(FIX.books_id, 'author_id', 'Int', false, '')
    FIX.fk_id = fk.id
    local res = schema_r.Mutation.createRelation({ }, {
      input = {
        name = REL_NAME,
        fromSpaceId = FIX.books_id,
        fromFieldId = FIX.fk_id,
        toSpaceId = FIX.authors_id,
        toFieldId = FIX.seq_id,
        reprFormula = '@name',
        cardinality = 'many'
      }
    }, CTX)
    R.ok(res)
    FIX.rel_id = res.id
  end)
  R.it("creates a grid view on the books space", function()
    local v = views.create_view(FIX.books_id, VIEW_NAME, 'grid', {
      layout = {
        direction = 'vertical',
        children = { }
      }
    })
    R.ok(v)
    FIX.view_id = v.id
  end)
  R.it("creates a page (custom view)", function()
    local res = cvr.Mutation.createCustomView({ }, {
      name = PAGE_NAME,
      description = 'apkg page',
      yaml = YAML_PAGE
    }, CTX)
    R.ok(res)
    FIX.page_id = res.id
  end)
  R.it("creates a data view over the books space", function()
    local res = dv_r.Mutation.createDataView(nil, {
      input = {
        name = DV_NAME,
        description = 'apkg data view',
        sourceSpace = SP_BOOKS,
        config = json.encode({
          columns = {
            'code',
            'title'
          }
        })
      }
    }, CTX)
    R.ok(res)
    FIX.dv_id = res.id
  end)
  R.it("creates a widget plugin", function()
    local res = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = PLUGIN_NAME,
        description = 'apkg plugin',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = "render '<div>ok</div>'",
        templateCode = 'div ok'
      }
    }, CTX)
    R.ok(res)
    FIX.plugin_id = res.id
  end)
  R.it("creates a group with permissions", function()
    local g = perms.create_group(GROUP_NAME, 'apkg group')
    FIX.group_id = g.id
    R.ok(g)
    perms.grant(g.id, 'space', FIX.books_id, 'read')
    perms.grant(g.id, 'space', nil, 'write')
    return R.eq(#perms.list_permissions(g.id), 2)
  end)
  return R.it("inserts seed rows in the books space", function()
    local rows = {
      {
        code = 'APKG-1',
        title = 'Premier',
        qty = 2
      },
      {
        code = 'APKG-2',
        title = 'Second',
        qty = 5
      },
      {
        code = 'APKG-3',
        title = 'Troisieme',
        qty = 7
      }
    }
    for _index_0 = 1, #rows do
      local row = rows[_index_0]
      local rec = data_r.Mutation.insertRecord({ }, {
        spaceId = FIX.books_id,
        data = row
      }, CTX)
      R.ok(rec)
    end
    seed_opts[SP_BOOKS] = 'code'
  end)
end)
R.describe("app_package — build_package", function()
  R.it("returns app metadata, items and seed_keys", function()
    PKG = pkg.build_package(META, {
      seed = seed_opts
    })
    R.ok(PKG)
    R.eq(PKG.app.id, META.id)
    R.eq(PKG.app.name, META.name)
    R.eq(PKG.app.version, META.version)
    R.eq(PKG.app.description, META.description)
    R.ok(#PKG.items >= 20, "expected at least the 20 fixture items, got " .. tostring(#PKG.items))
    return R.eq(PKG.seed_keys[SP_BOOKS], 'code')
  end)
  R.it("every item carries type, key and content", function()
    local bad = 0
    local _list_0 = PKG.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if not (it.type and it.key and type(it.content) == 'table') then
        bad = bad + 1
      end
    end
    return R.eq(bad, 0)
  end)
  R.it("covers the ten item types", function()
    local seen
    do
      local _tbl_0 = { }
      local _list_0 = PKG.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        _tbl_0[it.type] = true
      end
      seen = _tbl_0
    end
    local _list_0 = {
      'space',
      'field',
      'relation',
      'view',
      'page',
      'dataview',
      'plugin',
      'group',
      'perm',
      'seed'
    }
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      R.ok(seen[t], "missing item type " .. tostring(t))
    end
  end)
  R.it("delivers both test spaces sorted by name", function()
    local keys
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = PKG.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.type == 'space' then
          _accum_0[_len_0] = it.key
          _len_0 = _len_0 + 1
        end
      end
      keys = _accum_0
    end
    local expected
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #keys do
        local k = keys[_index_0]
        _accum_0[_len_0] = k
        _len_0 = _len_0 + 1
      end
      expected = _accum_0
    end
    table.sort(expected)
    return R.eq(table.concat(keys, ','), table.concat(expected, ','))
  end)
  R.it("lists the fields of a space in position order", function()
    local keys = { }
    local _list_0 = PKG.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.type == 'field' and it.key:match("^field:" .. tostring(SP_BOOKS) .. "%.") then
        table.insert(keys, it.key)
      end
    end
    local expected
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_1 = spaces.list_fields(FIX.books_id)
      for _index_0 = 1, #_list_1 do
        local f = _list_1[_index_0]
        _accum_0[_len_0] = "field:" .. tostring(SP_BOOKS) .. "." .. tostring(f.name)
        _len_0 = _len_0 + 1
      end
      expected = _accum_0
    end
    R.eq(#keys, #expected)
    for i = 1, #expected do
      R.eq(keys[i], expected[i])
    end
  end)
  R.it("never delivers the built-in admin group", function()
    local found = false
    local _list_0 = PKG.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key == 'group:admin' or it.key:match('^perm:admin|') then
        found = true
      end
    end
    return R.nok(found)
  end)
  R.it("relation items carry the declared cardinality", function()
    local key = "relation:" .. tostring(SP_BOOKS) .. ".author_id"
    local item = find_item(PKG, key)
    R.ok(item)
    R.eq(item.content.cardinality, 'many')
    R.eq(pkg.describe_local('relation', key).cardinality, 'many')
    return R.eq(pkg.canonical(pkg.describe_local('relation', key)), pkg.canonical(item.content))
  end)
  return R.it("is deterministic: two calls give the same items and fingerprints", function()
    PKG2 = pkg.build_package(META, {
      seed = seed_opts
    })
    R.eq(#PKG2.items, #PKG.items)
    local diffs = { }
    for i = 1, #PKG.items do
      local a, b = PKG.items[i], PKG2.items[i]
      if a.key ~= b.key or a.type ~= b.type or pkg.fingerprint(a.content) ~= pkg.fingerprint(b.content) then
        table.insert(diffs, tostring(i))
      end
    end
    return R.eq(#diffs, 0, "diverging items at " .. tostring(table.concat(diffs, ',')))
  end)
end)
R.describe("app_package — describe_local", function()
  R.it("matches the package content of every item", function()
    local mismatches = { }
    local _list_0 = PKG.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      local local_content = pkg.describe_local(it.type, it.key)
      if not local_content or pkg.canonical(local_content) ~= pkg.canonical(it.content) then
        table.insert(mismatches, it.key)
      end
    end
    R.eq(#mismatches, 0, "describe_local mismatch: " .. tostring(table.concat(mismatches, ', ')))
    return R.ok(#PKG.items >= 20, "expected at least the 20 fixture items, got " .. tostring(#PKG.items))
  end)
  R.it("space: returns the stored description", function()
    local key = "space:" .. tostring(SP_BOOKS)
    local item = find_item(PKG, key)
    R.ok(item)
    R.eq(pkg.canonical(pkg.describe_local('space', key)), pkg.canonical(item.content))
    return R.eq(item.content.description, 'apkg books')
  end)
  R.it("field: normalizes empty values (description, formula) and keeps no trigger", function()
    local key = "field:" .. tostring(SP_BOOKS) .. ".total"
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('field', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.formula, '(self.qty or 0) * 2')
    R.eq(local_content.language, 'lua')
    R.is_nil(local_content.triggerFields, 'computed column: no trigger, key absent')
    R.eq(local_content.description, '')
    return R.eq(pkg.canonical(local_content), pkg.canonical({
      fieldType = 'Int',
      notNull = false,
      description = '',
      formula = '(self.qty or 0) * 2',
      language = 'lua'
    }))
  end)
  R.it("relation: returns the four endpoint names", function()
    local key = "relation:" .. tostring(SP_BOOKS) .. ".author_id"
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('relation', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.fromSpace, SP_BOOKS)
    R.eq(local_content.fromField, 'author_id')
    R.eq(local_content.toSpace, SP_AUTHORS)
    R.eq(local_content.toField, 'seq_id')
    return R.eq(local_content.cardinality, 'many')
  end)
  R.it("view: returns space, name, viewType and config", function()
    local key = "view:" .. tostring(SP_BOOKS) .. "." .. tostring(VIEW_NAME)
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('view', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.space, SP_BOOKS)
    return R.eq(local_content.viewType, 'grid')
  end)
  R.it("page: returns name, description and yaml", function()
    local key = "page:" .. tostring(PAGE_NAME)
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('page', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.name, PAGE_NAME)
    R.eq(local_content.description, 'apkg page')
    R.ok(local_content.yaml:find('title: App package', 1, true), 'widget conservé')
    R.ok(local_content.yaml:find('space: apkg', 1, true), 'espace du widget conservé')
    return R.matches(local_content.yaml, 'id: w_%x%x%x%x%x%x%x%x', 'id de widget attribué')
  end)
  R.it("dataview: returns sourceSpace as a space name", function()
    local key = "dataview:" .. tostring(DV_NAME)
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('dataview', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.sourceSpace, SP_BOOKS)
    return R.eq(local_content.description, 'apkg data view')
  end)
  R.it("plugin: returns the script and template code", function()
    local key = "plugin:" .. tostring(PLUGIN_NAME)
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('plugin', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.scriptLanguage, 'coffeescript')
    R.eq(local_content.templateLanguage, 'pug')
    R.eq(local_content.scriptCode, "render '<div>ok</div>'")
    return R.eq(local_content.templateCode, 'div ok')
  end)
  R.it("group: returns name and description", function()
    local key = "group:" .. tostring(GROUP_NAME)
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('group', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.name, GROUP_NAME)
    return R.eq(local_content.description, 'apkg group')
  end)
  R.it("perm: resolves the resource to a space name and to '*'", function()
    local key = "perm:" .. tostring(GROUP_NAME) .. "|space|" .. tostring(SP_BOOKS) .. "|read"
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('perm', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.resource, SP_BOOKS)
    R.eq(local_content.group, GROUP_NAME)
    R.eq(local_content.level, 'read')
    local wild_key = "perm:" .. tostring(GROUP_NAME) .. "|space|*|write"
    local wild_item = find_item(PKG, wild_key)
    R.ok(wild_item)
    local wild_local = pkg.describe_local('perm', wild_key)
    R.eq(pkg.canonical(wild_local), pkg.canonical(wild_item.content))
    return R.eq(wild_local.resource, '*')
  end)
  R.it("seed: returns the row keyed by its natural key", function()
    local key = "seed:" .. tostring(SP_BOOKS) .. "|APKG-2"
    local item = find_item(PKG, key)
    R.ok(item)
    local local_content = pkg.describe_local('seed', key)
    R.eq(pkg.canonical(local_content), pkg.canonical(item.content))
    R.eq(local_content.space, SP_BOOKS)
    R.eq(local_content.key, 'APKG-2')
    R.eq(local_content.data.title, 'Second')
    return R.eq(local_content.data.qty, 5)
  end)
  return R.it("returns nil for elements that do not exist", function()
    R.is_nil(pkg.describe_local('space', "space:no_such_space_" .. tostring(SUFFIX)))
    R.is_nil(pkg.describe_local('field', "field:" .. tostring(SP_BOOKS) .. ".no_such_field"))
    R.is_nil(pkg.describe_local('page', "page:no_such_page_" .. tostring(SUFFIX)))
    R.is_nil(pkg.describe_local('group', "group:no_such_group_" .. tostring(SUFFIX)))
    R.is_nil(pkg.describe_local('seed', "seed:" .. tostring(SP_BOOKS) .. "|NO-SUCH-KEY"))
    return R.is_nil(pkg.describe_local('nonsense', 'nonsense:x'))
  end)
end)
R.describe("app_package — seed validation (F1)", function()
  R.it("creates a dedicated seed space with one field and a baseline row", function()
    local sp = spaces.create_user_space(SP_SEED, 'apkg seed')
    FIX_SEED.id = sp.id
    spaces.add_field(sp.id, 'code', 'String', true, '')
    box.space["data_" .. tostring(SP_SEED)]:insert({
      "apkgseed_base_" .. tostring(SUFFIX),
      json.encode({
        code = 'BASE',
        label = 'baseline'
      })
    })
    return R.ok(sp)
  end)
  R.it("rejects an unknown seed space, naming it and the word 'space'", function()
    local msg = seed_error({
      ["apkg_ghost_" .. tostring(SUFFIX)] = 'code'
    })
    R.matches(msg, "apkg_ghost_" .. tostring(SUFFIX))
    return R.matches(msg, 'space')
  end)
  R.it("rejects an unknown key field, naming the space and the field", function()
    local msg = seed_error({
      [SP_SEED] = 'no_such_field'
    })
    R.matches(msg, SP_SEED)
    return R.matches(msg, 'no_such_field')
  end)
  R.it("rejects rows missing the key value, naming space, field and count", function()
    local row_id = "apkgseed_nokey_" .. tostring(SUFFIX)
    box.space["data_" .. tostring(SP_SEED)]:insert({
      row_id,
      json.encode({
        label = 'no code'
      })
    })
    local msg = seed_error({
      [SP_SEED] = 'code'
    })
    R.matches(msg, SP_SEED)
    R.matches(msg, 'code')
    R.matches(msg, '1 seed row')
    return box.space["data_" .. tostring(SP_SEED)]:delete(row_id)
  end)
  R.it("rejects a duplicated key value, naming the space and the value", function()
    local row_id = "apkgseed_dup_" .. tostring(SUFFIX)
    box.space["data_" .. tostring(SP_SEED)]:insert({
      row_id,
      json.encode({
        code = 'BASE'
      })
    })
    local msg = seed_error({
      [SP_SEED] = 'code'
    })
    R.matches(msg, SP_SEED)
    R.matches(msg, 'BASE')
    R.matches(msg, 'duplicate')
    return box.space["data_" .. tostring(SP_SEED)]:delete(row_id)
  end)
  return R.it("a valid seed configuration still delivers the same items", function()
    local package = pkg.build_package(META, {
      seed = {
        [SP_SEED] = 'code'
      }
    })
    R.eq(package.seed_keys[SP_SEED], 'code')
    local item = find_item(package, "seed:" .. tostring(SP_SEED) .. "|BASE")
    R.ok(item)
    R.eq(item.content.space, SP_SEED)
    R.eq(item.content.key, 'BASE')
    return R.eq(item.content.data.label, 'baseline')
  end)
end)
R.describe("app_package — special names are unambiguous", function()
  R.it("creates a space, a field and groups whose names contain delimiters", function()
    local sp = spaces.create_user_space(SP_ESP, 'esp ace space')
    FIX_ESP.space_id = sp.id
    local f = spaces.add_field(sp.id, FLD_ESP, 'String', false, 'champ spécial')
    FIX_ESP.field_id = f.id
    spaces.add_field(sp.id, FLDN_ESP, 'String', false, '')
    local g1 = perms.create_group(GRP_ESP, 'groupe à barres')
    FIX_ESP.group_id = g1.id
    perms.grant(g1.id, 'space', sp.id, 'read')
    local g2 = perms.create_group(GRP_FORGE, 'groupe forgeant une clé')
    FIX_ESP.forge_id = g2.id
    perms.grant(g2.id, 'space', nil, 'read')
    return R.ok(sp and f and g1 and g2)
  end)
  R.it("the generated keys are unambiguous and round-trip through describe_local", function()
    local package = pkg.build_package(META, { })
    local esp
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
      esp = _accum_0
    end
    local sp_key = "space:" .. tostring(pkg.key_part(SP_ESP))
    local f_key = "field:" .. tostring(pkg.key_part(SP_ESP)) .. "." .. tostring(pkg.key_part(FLD_ESP))
    local fn_key = "field:" .. tostring(pkg.key_part(SP_ESP)) .. "." .. tostring(pkg.key_part(FLDN_ESP))
    local p_key = "perm:" .. tostring(pkg.key_part(GRP_ESP)) .. "|space|" .. tostring(pkg.key_part(SP_ESP)) .. "|read"
    local forge_key = "perm:" .. tostring(pkg.key_part(GRP_FORGE)) .. "|space|*|read"
    local _list_0 = {
      sp_key,
      f_key,
      fn_key,
      p_key,
      forge_key
    }
    for _index_0 = 1, #_list_0 do
      local key = _list_0[_index_0]
      local item = find_item(package, key)
      R.ok(item, "missing item " .. tostring(key))
      local local_content = pkg.describe_local(item.type, key)
      R.ok(local_content, "describe_local(" .. tostring(key) .. ")")
      R.eq(pkg.canonical(local_content), pkg.canonical(item.content), "content " .. tostring(key))
    end
    local fld = pkg.describe_local('field', f_key)
    R.eq(fld.fieldType, 'String')
    R.eq(fld.description, 'champ spécial')
    local body = p_key:match('^perm:(.*)$')
    local n_parts = 0
    for _ in body:gmatch('[^|]+') do
      n_parts = n_parts + 1
    end
    R.eq(n_parts, 4)
    R.ne(p_key, forge_key)
    local keys = { }
    local dup = nil
    for _index_0 = 1, #esp do
      local it = esp[_index_0]
      if keys[it.key] then
        dup = it.key
      end
      keys[it.key] = true
    end
    return R.is_nil(dup, "duplicate key " .. tostring(dup))
  end)
  R.it("an escaped key survives a JSON round-trip unchanged", function()
    local package = pkg.build_package(META, { })
    local _list_0 = package.items
    for _index_0 = 1, #_list_0 do
      local _continue_0 = false
      repeat
        local it = _list_0[_index_0]
        if not (it.key:find(SUFFIX, 1, true)) then
          _continue_0 = true
          break
        end
        R.eq(json.decode(json.encode(it.key)), it.key)
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  return R.it("removes the special-name fixture", function()
    if FIX_ESP.forge_id then
      perms.delete_group(FIX_ESP.forge_id)
    end
    if FIX_ESP.group_id then
      perms.delete_group(FIX_ESP.group_id)
    end
    spaces.delete_user_space(SP_ESP)
    R.is_nil(pkg.describe_local('space', "space:" .. tostring(pkg.key_part(SP_ESP))))
    return R.is_nil(pkg.describe_local('group', "group:" .. tostring(pkg.key_part(GRP_ESP))))
  end)
end)
R.describe("app_package — cleanup", function()
  R.it("removes the fixture elements", function()
    if FIX.rel_id then
      schema_r.Mutation.deleteRelation({ }, {
        id = FIX.rel_id
      }, CTX)
    end
    if FIX.view_id then
      views.delete_view(FIX.view_id)
    end
    if FIX.page_id then
      cvr.Mutation.deleteCustomView({ }, {
        id = FIX.page_id
      }, CTX)
    end
    if FIX.dv_id then
      dv_r.Mutation.deleteDataView(nil, {
        id = FIX.dv_id
      }, CTX)
    end
    if FIX.plugin_id then
      wpr.Mutation.deleteWidgetPlugin({ }, {
        id = FIX.plugin_id
      }, CTX)
    end
    if FIX.group_id then
      perms.delete_group(FIX.group_id)
    end
    R.is_nil(pkg.describe_local('relation', "relation:" .. tostring(SP_BOOKS) .. ".author_id"))
    R.is_nil(pkg.describe_local('view', "view:" .. tostring(SP_BOOKS) .. "." .. tostring(VIEW_NAME)))
    R.is_nil(pkg.describe_local('page', "page:" .. tostring(PAGE_NAME)))
    R.is_nil(pkg.describe_local('dataview', "dataview:" .. tostring(DV_NAME)))
    R.is_nil(pkg.describe_local('plugin', "plugin:" .. tostring(PLUGIN_NAME)))
    return R.is_nil(pkg.describe_local('group', "group:" .. tostring(GROUP_NAME)))
  end)
  return R.it("removes the two test spaces and their seed rows", function()
    spaces.delete_user_space(SP_BOOKS)
    spaces.delete_user_space(SP_AUTHORS)
    spaces.delete_user_space(SP_SEED)
    R.is_nil(pkg.describe_local('space', "space:" .. tostring(SP_BOOKS)))
    R.is_nil(pkg.describe_local('space', "space:" .. tostring(SP_AUTHORS)))
    R.is_nil(pkg.describe_local('space', "space:" .. tostring(SP_SEED)))
    R.is_nil(pkg.describe_local('seed', "seed:" .. tostring(SP_BOOKS) .. "|APKG-1"))
    local found = false
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP_BOOKS or s.name == SP_AUTHORS then
        found = true
      end
    end
    return R.nok(found)
  end)
end)
R.describe("app_package — strip_null (T22)", function()
  R.it("drops box.NULL from object values and array elements decoded by yaml", function()
    local raw = yaml.decode("a: null\nb: ~\nc:\nd: [1, null, 2]\ne:\n  x: null\n  y: ok\n")
    R.ok(raw.a == box.NULL, 'yaml null decodes to box.NULL')
    R.ok(raw.b == box.NULL, 'yaml ~ decodes to box.NULL')
    R.eq(raw.c, '', 'an empty yaml value is an empty string')
    R.ok(raw.d[2] == box.NULL, 'null inside a list decodes to box.NULL')
    local s = pkg.strip_null(raw)
    R.is_nil(s.a)
    R.is_nil(s.b)
    R.eq(s.c, '')
    R.eq(#s.d, 2)
    R.eq(s.d[1], 1)
    R.eq(s.d[2], 2)
    R.is_nil(s.e.x)
    R.eq(s.e.y, 'ok')
    return R.ok(raw.a == box.NULL, 'strip_null does not mutate its argument')
  end)
  return R.it("leaves ordinary scalars and non-null cdata untouched", function()
    R.eq(pkg.strip_null('x'), 'x')
    R.eq(pkg.strip_null(3), 3)
    R.eq(pkg.strip_null(true), true)
    R.is_nil(pkg.strip_null(nil))
    return R.is_nil(pkg.strip_null(box.NULL))
  end)
end)
return R.describe("app_package — normalize_content (T22)", function()
  R.it("reproduces each builder's defaults for absent optional keys", function()
    local expected = {
      space = {
        description = ''
      },
      field = {
        notNull = false,
        description = '',
        formula = '',
        language = 'lua'
      },
      relation = {
        cardinality = 'one'
      },
      view = { },
      page = {
        description = '',
        yaml = ''
      },
      dataview = {
        description = '',
        sourceSpace = ''
      },
      plugin = {
        description = '',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = '',
        templateCode = ''
      },
      group = {
        description = ''
      },
      perm = {
        resource = '*'
      },
      seed = {
        data = { }
      }
    }
    for item_type, exp in pairs(expected) do
      local got = pkg.normalize_content(item_type, { })
      R.eq(pkg.canonical(got), pkg.canonical(exp), "normalize " .. tostring(item_type))
    end
  end)
  R.it("normalizes a field content decoded by yaml (null optionals)", function()
    local raw = yaml.decode("fieldType: Int\nnotNull: ~\ndescription: null\nformula: ~\ntriggerFields: null\nlanguage: null\n")
    local c = pkg.normalize_content('field', pkg.strip_null(raw))
    R.eq(pkg.canonical(c), pkg.canonical({
      fieldType = 'Int',
      notNull = false,
      description = '',
      formula = '',
      language = 'lua'
    }))
    return R.is_nil(c.triggerFields, 'triggerFields: null means no trigger')
  end)
  R.it("is idempotent and does not mutate its argument", function()
    local original = {
      fieldType = 'Int',
      description = 'x'
    }
    local c1 = pkg.normalize_content('field', original)
    local c2 = pkg.normalize_content('field', c1)
    R.eq(pkg.canonical(c1), pkg.canonical(c2))
    R.eq(pkg.canonical(original), pkg.canonical({
      fieldType = 'Int',
      description = 'x'
    }))
    return R.eq(original.formula, nil, 'the argument gained no key')
  end)
  return R.it("matches the fingerprint of the equivalent builder content", function()
    local raw = yaml.decode("fieldType: String\nnotNull: false\ndescription: null\nformula: ~\ntriggerFields:\nlanguage: null\n")
    local c = pkg.normalize_content('field', pkg.strip_null(raw))
    local built = {
      fieldType = 'String',
      notNull = false,
      description = '',
      formula = '',
      language = 'lua'
    }
    return R.eq(pkg.fingerprint(c), pkg.fingerprint(built))
  end)
end)
