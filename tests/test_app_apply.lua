local R = require('tests.runner')
local pkg = require('core.app_package')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local views = require('core.views')
local perms = require('core.permissions')
local data_views = require('core.data_views')
local view_presets = require('core.view_presets')
local schema_r = require('resolvers.schema_resolvers')
local cvr = require('resolvers.custom_view_resolvers')
local wpr = require('resolvers.widget_plugin_resolvers')
local dv_r = require('resolvers.data_view_resolvers')
local data_r = require('resolvers.data_resolvers')
local auth = require('core.auth')
local json = require('json')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_BOOKS = "aap_books_" .. tostring(SUFFIX)
local SP_AUTHORS = "aap_authors_" .. tostring(SUFFIX)
local VIEW_NAME = "aap_view_" .. tostring(SUFFIX)
local PAGE_NAME = "aap_page_" .. tostring(SUFFIX)
local DV_NAME = "aap_dv_" .. tostring(SUFFIX)
local PLUGIN_NAME = "aap_plugin_" .. tostring(SUFFIX)
local GROUP_NAME = "aap_group_" .. tostring(SUFFIX)
local REL_NAME = "aap_rel_" .. tostring(SUFFIX)
local APP_ID = "org.test.aap_" .. tostring(SUFFIX)
local APP_BAD_ID = "org.test.aapbad_" .. tostring(SUFFIX)
local SP_BAD = "aap_bad_" .. tostring(SUFFIX)
local KEY_TITLE = "field:" .. tostring(SP_BOOKS) .. ".title"
local KEY_QTY = "field:" .. tostring(SP_BOOKS) .. ".qty"
local KEY_NOTE = "field:" .. tostring(SP_BOOKS) .. ".note"
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local YAML_PAGE = [[layout:
  direction: vertical
  children:
    - widget:
        title: App apply
        space: aap
]]
local FIX = { }
local PKG = nil
local PKG2 = nil
local PKG3 = nil
local seed_opts = { }
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
local item_by_key
item_by_key = function(package, key)
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key == key then
      return it
    end
  end
  return nil
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
local describe_intact
describe_intact = function(package)
  local missing = { }
  local _list_0 = non_seed(package)
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    local content = pkg.describe_local(it.type, it.key)
    if not content or pkg.canonical(content) ~= pkg.canonical(it.content) then
      table.insert(missing, it.key)
    end
  end
  return missing
end
local installed_count
installed_count = function(app_id)
  return #box.space._tdb_app_items.index.by_app:select({
    app_id
  })
end
local clean_app_rows
clean_app_rows = function(app_id)
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    box.space._tdb_app_items:delete({
      t[1],
      t[2]
    })
  end
  return box.space._tdb_apps:delete(app_id)
end
R.describe("app_apply — fixture", function()
  R.it("creates two spaces with fields (String, Int, Sequence) and a relation", function()
    local books = spaces.create_user_space(SP_BOOKS, 'aap books')
    local authors = spaces.create_user_space(SP_AUTHORS, 'aap authors')
    FIX.books_id = books.id
    FIX.authors_id = authors.id
    spaces.add_field(books.id, 'code', 'String', true, 'natural key')
    spaces.add_field(books.id, 'title', 'String', false, '')
    spaces.add_field(books.id, 'qty', 'Int', false, '')
    local fk = spaces.add_field(books.id, 'author_id', 'Int', false, '')
    FIX.fk_id = fk.id
    local seq = spaces.add_field(authors.id, 'seq_id', 'Sequence')
    FIX.seq_id = seq.id
    spaces.add_field(authors.id, 'name', 'String', false, '')
    local res = schema_r.Mutation.createRelation({ }, {
      input = {
        name = REL_NAME,
        fromSpaceId = books.id,
        fromFieldId = fk.id,
        toSpaceId = authors.id,
        toFieldId = seq.id,
        reprFormula = '@name',
        cardinality = 'many'
      }
    }, CTX)
    FIX.rel_id = res.id
    return R.ok(res)
  end)
  R.it("creates a view, a page, a data view, a plugin, a group and permissions", function()
    local v = views.create_view(FIX.books_id, VIEW_NAME, 'grid', {
      layout = {
        direction = 'vertical',
        children = { }
      }
    })
    FIX.view_id = v.id
    local p = cvr.Mutation.createCustomView({ }, {
      name = PAGE_NAME,
      description = 'aap page',
      yaml = YAML_PAGE
    }, CTX)
    FIX.page_id = p.id
    local dv = dv_r.Mutation.createDataView(nil, {
      input = {
        name = DV_NAME,
        description = 'aap data view',
        sourceSpace = SP_BOOKS,
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
        name = PLUGIN_NAME,
        description = 'aap plugin',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = "render '<div>ok</div>'",
        templateCode = 'div ok'
      }
    }, CTX)
    FIX.plugin_id = wp.id
    local g = perms.create_group(GROUP_NAME, 'aap group')
    FIX.group_id = g.id
    perms.grant(g.id, 'space', FIX.books_id, 'read')
    perms.grant(g.id, 'space', nil, 'write')
    return R.ok(v and p and dv and wp and g)
  end)
  return R.it("inserts seed rows and builds a filtered package", function()
    local _list_0 = {
      {
        code = 'AAP-1',
        title = 'Premier',
        qty = 2
      },
      {
        code = 'AAP-2',
        title = 'Second',
        qty = 5
      }
    }
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      data_r.Mutation.insertRecord({ }, {
        spaceId = FIX.books_id,
        data = row
      }, CTX)
    end
    seed_opts[SP_BOOKS] = 'code'
    local META = {
      id = APP_ID,
      name = 'Aap fixture',
      version = '1.0.0',
      description = 'aap'
    }
    PKG = subset(pkg.build_package(META, {
      seed = seed_opts
    }))
    R.ok(PKG)
    R.eq(PKG.app.id, APP_ID)
    local n_items = #PKG.items
    local n_nonseed = #non_seed(PKG)
    R.ok(n_nonseed >= 16, "expected >= 16 non-seed items, got " .. tostring(n_nonseed))
    return R.eq(n_items - n_nonseed, 2, 'two seed items')
  end)
end)
R.describe("app_apply — load_package", function()
  R.it("recomputes every fingerprint from content, ignoring a supplied one", function()
    local p = {
      app = {
        id = APP_ID,
        name = 'x',
        version = '1.0.0'
      },
      items = {
        {
          type = 'space',
          key = "space:" .. tostring(SP_BOOKS),
          content = {
            description = 'aap books'
          },
          fingerprint = 'BOGUS'
        }
      }
    }
    local norm = apply.load_package(p)
    R.ok(norm)
    R.ne(norm.items[1].fingerprint, 'BOGUS')
    return R.eq(norm.items[1].fingerprint, pkg.fingerprint({
      description = 'aap books'
    }))
  end)
  R.it("rejects a package without app id", function()
    local norm, err = apply.load_package({
      app = { },
      items = { }
    })
    R.is_nil(norm)
    return R.matches(err, 'app id')
  end)
  R.it("rejects an item without content", function()
    local norm = apply.load_package({
      app = {
        id = APP_ID,
        version = '1.0.0'
      },
      items = {
        {
          type = 'space',
          key = "space:" .. tostring(SP_BOOKS)
        }
      }
    })
    return R.is_nil(norm)
  end)
  return R.it("rejects an unknown item type", function()
    local norm = apply.load_package({
      app = {
        id = APP_ID,
        version = '1.0.0'
      },
      items = {
        {
          type = 'gizmo',
          key = 'gizmo:x',
          content = { }
        }
      }
    })
    return R.is_nil(norm)
  end)
end)
R.describe("app_apply — preview_update", function()
  return R.it("reports every element as unchanged while the local DB matches the package", function()
    local plan = apply.preview_update(PKG)
    R.eq(#plan.errors, 0, 'preview errors')
    R.eq(#plan.create, 0, 'create')
    return R.eq(#plan.unchanged, #PKG.items, 'unchanged')
  end)
end)
local remove_app_elements
remove_app_elements = function()
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
  spaces.delete_user_space(SP_BOOKS)
  spaces.delete_user_space(SP_AUTHORS)
  FIX.rel_id = nil
  FIX.view_id = nil
  FIX.page_id = nil
  FIX.dv_id = nil
  FIX.plugin_id = nil
  FIX.group_id = nil
end
R.describe("app_apply — installation on a half-empty base", function()
  R.it("removes the app elements locally", function()
    remove_app_elements()
    R.is_nil(pkg.describe_local('space', "space:" .. tostring(SP_BOOKS)))
    R.is_nil(pkg.describe_local('relation', "relation:" .. tostring(SP_BOOKS) .. ".author_id"))
    R.is_nil(pkg.describe_local('page', "page:" .. tostring(PAGE_NAME)))
    return R.is_nil(pkg.describe_local('group', "group:" .. tostring(GROUP_NAME)))
  end)
  R.it("preview shows every packaged element to create (seed items included)", function()
    local plan = apply.preview_update(PKG)
    R.eq(#plan.errors, 0)
    R.eq(#plan.create, #PKG.items)
    return R.eq(#plan.conflict, 0)
  end)
  R.it("apply_update creates everything and records the version", function()
    local report = apply.apply_update(PKG, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, #PKG.items, 'created')
    R.eq(#report.updated, 0, 'updated')
    R.eq(#report.conflicts, 0, 'conflicts')
    R.eq(#describe_intact(PKG), 0, 'all non-seed elements match the package')
    R.eq(installed_count(APP_ID), #PKG.items, 'tracked items')
    return R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.0.0', 'installed version')
  end)
  return R.it("recreated the spaces, fields, relation, view, page, data view, plugin, group and perms", function()
    R.ok(spaces.get_space_by_name(SP_BOOKS))
    R.ok(spaces.get_space_by_name(SP_AUTHORS))
    R.ok((field_by_name(spaces.get_space_by_name(SP_BOOKS).id, 'code')))
    R.ok(pkg.describe_local('relation', "relation:" .. tostring(SP_BOOKS) .. ".author_id"))
    R.eq(pkg.describe_local('relation', "relation:" .. tostring(SP_BOOKS) .. ".author_id").cardinality, 'many')
    R.ok(pkg.describe_local('view', "view:" .. tostring(SP_BOOKS) .. "." .. tostring(VIEW_NAME)))
    R.ok(pkg.describe_local('page', "page:" .. tostring(PAGE_NAME)))
    R.ok(pkg.describe_local('dataview', "dataview:" .. tostring(DV_NAME)))
    R.ok(pkg.describe_local('plugin', "plugin:" .. tostring(PLUGIN_NAME)))
    R.ok(pkg.describe_local('group', "group:" .. tostring(GROUP_NAME)))
    R.ok(pkg.describe_local('perm', "perm:" .. tostring(GROUP_NAME) .. "|space|*|write"))
    return R.ok(pkg.describe_local('perm', "perm:" .. tostring(GROUP_NAME) .. "|space|" .. tostring(SP_BOOKS) .. "|read"))
  end)
end)
R.describe("app_apply — reinstall of the same package", function()
  return R.it("reports everything unchanged and creates nothing", function()
    local report = apply.apply_update(PKG, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, 0, 'created')
    R.eq(#report.updated, 0, 'updated')
    R.eq(#report.unchanged, #PKG.items, 'unchanged')
    return R.eq(#report.conflicts, 0, 'conflicts')
  end)
end)
R.describe("app_apply — author adds a field, data preserved", function()
  R.it("builds v1.1.0 with an extra field, then removes it locally", function()
    local _list_0 = {
      {
        code = 'AAP-3',
        title = 'Troisieme',
        qty = 7
      }
    }
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      data_r.Mutation.insertRecord({ }, {
        spaceId = spaces.get_space_by_name(SP_BOOKS).id,
        data = row
      }, CTX)
    end
    local note = spaces.add_field(spaces.get_space_by_name(SP_BOOKS).id, 'note', 'String', false, '')
    local META2 = {
      id = APP_ID,
      name = 'Aap fixture',
      version = '1.1.0',
      description = 'aap'
    }
    PKG2 = subset(pkg.build_package(META2, {
      seed = seed_opts
    }))
    spaces.remove_field(note.id)
    R.is_nil((field_by_name(spaces.get_space_by_name(SP_BOOKS).id, 'note')))
    FIX.rows_before = row_dump(SP_BOOKS)
    return R.ok(PKG2)
  end)
  return R.it("creates the new field and leaves user data untouched", function()
    local report = apply.apply_update(PKG2, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, 1, 'created')
    R.eq(report.created[1], KEY_NOTE)
    R.ok((field_by_name(spaces.get_space_by_name(SP_BOOKS).id, 'note')))
    local rows_after = row_dump(SP_BOOKS)
    R.eq(table.concat(rows_after, '|'), table.concat(FIX.rows_before, '|'), 'rows unchanged')
    return R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.1.0', 'installed version')
  end)
end)
R.describe("app_apply — local-only changes are kept", function()
  R.it("keeps a field modified locally only", function()
    local sid = spaces.get_space_by_name(SP_BOOKS).id
    spaces.update_field((field_by_name(sid, 'title')).id, {
      description = 'locally changed'
    })
    local report = apply.apply_update(PKG2, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.updated, 0, 'updated')
    local found = false
    local _list_0 = report.kept
    for _index_0 = 1, #_list_0 do
      local k = _list_0[_index_0]
      if k == KEY_TITLE then
        found = true
      end
    end
    R.ok(found, "expected " .. tostring(KEY_TITLE) .. " in kept")
    local f = field_by_name(sid, 'title')
    return R.eq(f.description, 'locally changed')
  end)
  return R.it("leaves elements created locally outside the package intact", function()
    local sid = spaces.get_space_by_name(SP_BOOKS).id
    spaces.add_field(sid, 'local_only', 'String', false, 'mine')
    local before = installed_count(APP_ID)
    local report = apply.apply_update(PKG2, { }, { })
    R.ok(report.ok, report.error)
    R.ok((field_by_name(sid, 'local_only')), 'local_only still present')
    R.eq((field_by_name(sid, 'local_only')).description, 'mine')
    R.eq(installed_count(APP_ID), before, 'no tracking row for a local element')
    return R.is_nil(item_by_key(PKG2, "field:" .. tostring(SP_BOOKS) .. ".local_only"))
  end)
end)
R.describe("app_apply — conflicts", function()
  R.it("sets up a local change and an author change on two fields", function()
    local sid = spaces.get_space_by_name(SP_BOOKS).id
    spaces.update_field((field_by_name(sid, 'title')).id, {
      description = 'LOCAL-A'
    })
    spaces.update_field((field_by_name(sid, 'qty')).id, {
      description = 'LOCAL-B'
    })
    spaces.update_field((field_by_name(sid, 'title')).id, {
      description = 'AUTHOR-A'
    })
    spaces.update_field((field_by_name(sid, 'qty')).id, {
      description = 'AUTHOR-B'
    })
    local META3 = {
      id = APP_ID,
      name = 'Aap fixture',
      version = '1.2.0',
      description = 'aap'
    }
    PKG3 = subset(pkg.build_package(META3, {
      seed = seed_opts
    }))
    spaces.update_field((field_by_name(sid, 'title')).id, {
      description = 'LOCAL-A'
    })
    spaces.update_field((field_by_name(sid, 'qty')).id, {
      description = 'LOCAL-B'
    })
    R.ok(PKG3)
    R.eq(item_by_key(PKG3, KEY_TITLE).content.description, 'AUTHOR-A')
    return R.eq(item_by_key(PKG3, KEY_QTY).content.description, 'AUTHOR-B')
  end)
  R.it("aborts without a decision and writes nothing", function()
    local before = installed_count(APP_ID)
    local report = apply.apply_update(PKG3, { }, { })
    R.nok(report.ok)
    R.matches(report.error, 'requires a decision')
    R.eq(installed_count(APP_ID), before, 'no tracking write')
    local sid = spaces.get_space_by_name(SP_BOOKS).id
    R.eq((field_by_name(sid, 'title')).description, 'LOCAL-A')
    return R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.1.0', 'version unchanged')
  end)
  return R.it("resolves 'local' for one and 'delivered' for the other", function()
    local d = { }
    d[KEY_TITLE] = 'local'
    d[KEY_QTY] = 'delivered'
    local report = apply.apply_update(PKG3, d, { })
    R.ok(report.ok, report.error)
    R.eq(#report.conflicts, 2, 'conflicts')
    local sid = spaces.get_space_by_name(SP_BOOKS).id
    R.eq((field_by_name(sid, 'title')).description, 'LOCAL-A', 'local kept')
    R.eq((field_by_name(sid, 'qty')).description, 'AUTHOR-B', 'delivered applied')
    R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.2.0', 'installed version')
    R.eq(pkg.describe_local('field', KEY_TITLE).description, 'LOCAL-A')
    return R.eq(pkg.describe_local('field', KEY_QTY).description, 'AUTHOR-B')
  end)
end)
R.describe("app_apply — downgrade is refused", function()
  R.it("refuses an older version without allow_downgrade and writes nothing", function()
    local before = installed_count(APP_ID)
    local report = apply.apply_update(PKG2, { }, { })
    R.nok(report.ok)
    R.matches(report.error, 'downgrade')
    R.eq(installed_count(APP_ID), before)
    return R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.2.0')
  end)
  return R.it("lifts the downgrade guard with allow_downgrade", function()
    local report = apply.apply_update(PKG2, { }, {
      allow_downgrade = true
    })
    local err = report.error or ''
    return R.is_nil((err:match('downgrade')), "downgrade must no longer block: " .. tostring(err))
  end)
end)
R.describe("app_apply — invalid package", function()
  R.it("is refused without any write", function()
    local spaces_before = #spaces.list_spaces()
    local report = apply.apply_update({
      app = { },
      items = { }
    }, { }, { })
    R.nok(report.ok)
    R.eq(#spaces.list_spaces(), spaces_before)
    return R.nok(box.space._tdb_apps:get(APP_BAD_ID))
  end)
  return R.it("refuses an item without content", function()
    local report = apply.apply_update({
      app = {
        id = APP_BAD_ID,
        version = '1.0.0'
      },
      items = {
        {
          type = 'space',
          key = "space:" .. tostring(SP_BAD)
        }
      }
    }, { }, { })
    R.nok(report.ok)
    R.nok(box.space._tdb_apps:get(APP_BAD_ID))
    return R.is_nil(spaces.get_space_by_name(SP_BAD))
  end)
end)
R.describe("app_apply — failure in the middle rolls back everything", function()
  return R.it("creates a space, then fails on a relation to an unknown space", function()
    local bad = {
      app = {
        id = APP_BAD_ID,
        name = 'Bad',
        version = '1.0.0'
      },
      items = {
        {
          type = 'space',
          key = "space:" .. tostring(SP_BAD),
          content = {
            description = 'bad'
          }
        },
        {
          type = 'field',
          key = "field:" .. tostring(SP_BAD) .. ".name",
          content = {
            fieldType = 'String',
            notNull = false,
            description = '',
            formula = '',
            language = 'lua'
          }
        },
        {
          type = 'relation',
          key = "relation:" .. tostring(SP_BAD) .. ".name",
          content = {
            fromSpace = SP_BAD,
            fromField = 'name',
            toSpace = "no_such_space_" .. tostring(SUFFIX),
            toField = 'x'
          }
        }
      }
    }
    R.ok(apply.load_package(bad), 'the package shape is valid (failure is operational)')
    local spaces_before = #spaces.list_spaces()
    local report = apply.apply_update(bad, { }, { })
    R.nok(report.ok)
    R.is_nil(spaces.get_space_by_name(SP_BAD), 'space rolled back')
    R.eq(#spaces.list_spaces(), spaces_before, 'space count restored')
    R.is_nil(box.space._tdb_apps:get(APP_BAD_ID), 'no app row')
    return R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_BAD_ID
    }), 0, 'no item rows')
  end)
end)
local SP_RB = "aap_relbooks_" .. tostring(SUFFIX)
local SP_RA = "aap_relauthors_" .. tostring(SUFFIX)
local APP_REL = "org.test.aaprel_" .. tostring(SUFFIX)
local REL_RB_KEY = "relation:" .. tostring(SP_RB) .. ".author_id"
local REL_RB_EDITOR = "relation:" .. tostring(SP_RB) .. ".editor_id"
local rel_content
rel_content = function(from_field, card)
  local c = {
    fromSpace = SP_RB,
    fromField = from_field,
    toSpace = SP_RA,
    toField = 'seq_id'
  }
  if card then
    c.cardinality = card
  end
  return c
end
local rel_field
rel_field = function(name)
  return {
    type = 'field',
    key = "field:" .. tostring(SP_RB) .. "." .. tostring(name),
    content = {
      fieldType = 'Int',
      notNull = false,
      description = '',
      formula = '',
      language = 'lua'
    }
  }
end
local rel_pkg
rel_pkg = function(version, author_card)
  return {
    app = {
      id = APP_REL,
      name = 'Rel cardinality',
      version = version,
      description = ''
    },
    items = {
      {
        type = 'space',
        key = "space:" .. tostring(SP_RB),
        content = {
          description = 'rel books'
        }
      },
      {
        type = 'space',
        key = "space:" .. tostring(SP_RA),
        content = {
          description = 'rel authors'
        }
      },
      rel_field('author_id'),
      rel_field('editor_id'),
      {
        type = 'field',
        key = "field:" .. tostring(SP_RA) .. ".seq_id",
        content = {
          fieldType = 'Sequence',
          notNull = false,
          description = '',
          formula = '',
          language = 'lua'
        }
      },
      {
        type = 'relation',
        key = REL_RB_KEY,
        content = rel_content('author_id', author_card)
      },
      {
        type = 'relation',
        key = REL_RB_EDITOR,
        content = rel_content('editor_id', nil)
      }
    },
    seed_keys = { }
  }
end
R.describe("app_apply — relation cardinality", function()
  R.it("installs 'many' when declared and 'one' for an old-format relation", function()
    local report = apply.apply_update(rel_pkg('1.0.0', 'many'), { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, 7, 'created')
    R.eq(pkg.describe_local('relation', REL_RB_KEY).cardinality, 'many')
    return R.eq(pkg.describe_local('relation', REL_RB_EDITOR).cardinality, 'one')
  end)
  R.it("an author cardinality change is an update while the local is unchanged", function()
    local report = apply.apply_update(rel_pkg('1.1.0', 'one'), { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.updated, 1, 'updated')
    R.eq(report.updated[1], REL_RB_KEY)
    return R.eq(pkg.describe_local('relation', REL_RB_KEY).cardinality, 'one')
  end)
  R.it("a local-only cardinality change is kept", function()
    local sid = spaces.get_space_by_name(SP_RB).id
    local fid = (field_by_name(sid, 'author_id')).id
    local rel_id = nil
    local _list_0 = box.space._tdb_relations.index.by_from:select({
      sid
    })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      if t[3] == fid then
        rel_id = t[1]
      end
    end
    R.ok(rel_id, 'author_id relation row')
    schema_r.Mutation.updateRelation({ }, {
      id = rel_id,
      input = {
        cardinality = 'many'
      }
    }, CTX)
    R.eq(pkg.describe_local('relation', REL_RB_KEY).cardinality, 'many')
    local report = apply.apply_update(rel_pkg('1.1.0', 'one'), { }, { })
    R.ok(report.ok, report.error)
    local found = false
    local _list_1 = report.kept
    for _index_0 = 1, #_list_1 do
      local k = _list_1[_index_0]
      if k == REL_RB_KEY then
        found = true
      end
    end
    R.ok(found, "expected " .. tostring(REL_RB_KEY) .. " in kept")
    return R.eq(pkg.describe_local('relation', REL_RB_KEY).cardinality, 'many')
  end)
  return R.it("cleans up the relation cardinality fixture", function()
    local _list_0 = {
      SP_RB,
      SP_RA
    }
    for _index_0 = 1, #_list_0 do
      local nm = _list_0[_index_0]
      local sp = spaces.get_space_by_name(nm)
      if sp then
        local _list_1 = box.space._tdb_relations.index.by_from:select({
          sp.id
        })
        for _index_1 = 1, #_list_1 do
          local t = _list_1[_index_1]
          box.space._tdb_relations:delete(t[1])
        end
        local _list_2 = box.space._tdb_relations.index.by_to:select({
          sp.id
        })
        for _index_1 = 1, #_list_2 do
          local t = _list_2[_index_1]
          box.space._tdb_relations:delete(t[1])
        end
      end
    end
    clean_app_rows(APP_REL)
    spaces.delete_user_space(SP_RB)
    spaces.delete_user_space(SP_RA)
    R.is_nil(spaces.get_space_by_name(SP_RB))
    return R.is_nil(pkg.describe_local('relation', REL_RB_KEY))
  end)
end)
local SP_P = "aap_preset_" .. tostring(SUFFIX)
local PAGE_P = "aap_preset_page_" .. tostring(SUFFIX)
local PRESET_P = "aap:preset_" .. tostring(SUFFIX)
local WIDGET_P = 'w_0000cafe'
local APP_P = "org.test.aappreset_" .. tostring(SUFFIX)
local SCOPE_P = "widget:" .. tostring(PAGE_P) .. ":" .. tostring(WIDGET_P)
local KEY_PAGE_P = "page:" .. tostring(PAGE_P)
local KEY_PRESET_P = "preset:" .. tostring(pkg.key_part(SCOPE_P)) .. "|" .. tostring(pkg.key_part(PRESET_P))
R.describe("app_apply — préréglages de vue", function()
  R.it("builds a package whose preset scope names the page and the space", function()
    local sp = spaces.create_user_space(SP_P, 'aap preset')
    FIX.preset_space_id = sp.id
    spaces.add_field(sp.id, 'code', 'String', false, '')
    local page = cvr.Mutation.createCustomView({ }, {
      name = PAGE_P,
      description = '',
      yaml = YAML_PAGE
    }, CTX)
    FIX.preset_page_id = page.id
    local local_preset = view_presets.save_preset("widget:" .. tostring(page.id) .. ":" .. tostring(WIDGET_P), sp.id, PRESET_P, 'self.code == "x"', '[{"column":"code","ascending":true}]')
    FIX.local_preset_id = local_preset.id
    local page_content = pkg.describe_local('page', KEY_PAGE_P)
    R.ok(page_content)
    FIX.PKG_P = {
      app = {
        id = APP_P,
        name = 'Preset fixture',
        version = '1.0.0',
        description = ''
      },
      items = {
        {
          type = 'space',
          key = "space:" .. tostring(SP_P),
          content = {
            description = 'aap preset'
          }
        },
        {
          type = 'field',
          key = "field:" .. tostring(SP_P) .. ".code",
          content = {
            fieldType = 'String',
            notNull = false,
            description = '',
            formula = '',
            language = 'lua'
          }
        },
        {
          type = 'page',
          key = KEY_PAGE_P,
          content = page_content
        },
        {
          type = 'preset',
          key = KEY_PRESET_P,
          content = {
            scope = SCOPE_P,
            space = SP_P,
            name = PRESET_P,
            filter = 'self.code == "x"',
            sort = {
              {
                column = 'code',
                ascending = true
              }
            }
          }
        }
      },
      seed_keys = { }
    }
    local built = pkg.build_package({
      id = APP_P,
      name = 'Preset fixture',
      version = '1.0.0',
      description = ''
    }, { })
    local emitted = item_by_key(built, KEY_PRESET_P)
    R.ok(emitted, "missing " .. tostring(KEY_PRESET_P))
    R.eq(emitted.content.scope, SCOPE_P)
    R.eq(emitted.content.space, SP_P)
    R.eq(emitted.content.sort[1].column, 'code')
    R.is_nil(KEY_PRESET_P:find(FIX.local_preset_id, 1, true), 'no local preset id in the key')
    R.is_nil(KEY_PRESET_P:find(sp.id, 1, true), 'no local space id in the key')
    return R.eq(pkg.canonical(emitted.content), pkg.canonical(item_by_key(FIX.PKG_P, KEY_PRESET_P).content))
  end)
  R.it("installs the preset under the local page and space ids", function()
    view_presets.delete_preset(FIX.local_preset_id)
    box.space._tdb_custom_views:delete(FIX.preset_page_id)
    spaces.delete_user_space(SP_P)
    local report = apply.apply_update(FIX.PKG_P, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, #FIX.PKG_P.items, 'created')
    local new_sp = spaces.get_space_by_name(SP_P)
    local new_page = box.space._tdb_custom_views.index.by_name:get(PAGE_P)
    R.ok(new_sp, 'space reinstalled')
    R.ok(new_page, 'page reinstalled')
    local row = box.space._tdb_view_presets.index.by_scope_name:get({
      "widget:" .. tostring(new_page[1]) .. ":" .. tostring(WIDGET_P),
      PRESET_P
    })
    R.ok(row, 'preset installed under the resolved page id')
    R.eq(row[3], new_sp.id, 'attached to the resolved space id')
    R.eq(row[5], 'self.code == "x"')
    R.eq(json.decode(row[6])[1].column, 'code')
    local described = pkg.describe_local('preset', KEY_PRESET_P)
    R.eq(described.scope, SCOPE_P)
    local installed = apply.apply_update(FIX.PKG_P, { }, { })
    R.ok(installed.ok, installed.error)
    R.eq(#installed.created, 0, 'nothing created on a reinstall')
    return R.eq(#installed.unchanged, #FIX.PKG_P.items, 'everything unchanged')
  end)
  R.it("updates the delivered filter and keeps the row", function()
    local page_id = box.space._tdb_custom_views.index.by_name:get(PAGE_P)[1]
    local changed = {
      app = {
        id = APP_P,
        name = 'Preset fixture',
        version = '1.1.0',
        description = ''
      },
      items = { },
      seed_keys = { }
    }
    local _list_0 = FIX.PKG_P.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key == KEY_PRESET_P then
        table.insert(changed.items, {
          type = 'preset',
          key = it.key,
          content = {
            scope = SCOPE_P,
            space = SP_P,
            name = PRESET_P,
            filter = 'self.code == "y"',
            sort = it.content.sort
          }
        })
      else
        table.insert(changed.items, it)
      end
    end
    local report = apply.apply_update(changed, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.updated, 1, 'updated')
    R.eq(report.updated[1], KEY_PRESET_P)
    local row = box.space._tdb_view_presets.index.by_scope_name:get({
      "widget:" .. tostring(page_id) .. ":" .. tostring(WIDGET_P),
      PRESET_P
    })
    return R.eq(row[5], 'self.code == "y"', 'filter updated in place')
  end)
  R.it("refuses a preset whose page does not exist, writing nothing", function()
    local ghost_scope = "widget:no_such_page_" .. tostring(SUFFIX) .. ":" .. tostring(WIDGET_P)
    local bad = {
      app = {
        id = "org.test.aappresetbad_" .. tostring(SUFFIX),
        name = 'Bad',
        version = '1.0.0',
        description = ''
      },
      items = {
        {
          type = 'preset',
          key = "preset:" .. tostring(pkg.key_part(ghost_scope)) .. "|" .. tostring(pkg.key_part('Fantome')),
          content = {
            scope = ghost_scope,
            space = SP_P,
            name = 'Fantome',
            filter = '',
            sort = { }
          }
        }
      },
      seed_keys = { }
    }
    R.ok(apply.load_package(bad), 'the package shape is valid (failure is operational)')
    local rows_before = #box.space._tdb_view_presets:select({ })
    local report = apply.apply_update(bad, { }, { })
    R.nok(report.ok)
    R.matches(report.error, 'unknown page')
    R.matches(report.error, "no_such_page_" .. tostring(SUFFIX))
    R.eq(#box.space._tdb_view_presets:select({ }), rows_before, 'no preset written')
    return R.nok(box.space._tdb_apps:get("org.test.aappresetbad_" .. tostring(SUFFIX), 'no app row'))
  end)
  return R.it("cleans up the preset fixture", function()
    local _list_0 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      if t[4] == PRESET_P then
        view_presets.delete_preset(t[1])
      end
    end
    local page = box.space._tdb_custom_views.index.by_name:get(PAGE_P)
    if page then
      box.space._tdb_custom_views:delete(page[1])
    end
    clean_app_rows(APP_P)
    spaces.delete_user_space(SP_P)
    R.is_nil(spaces.get_space_by_name(SP_P))
    return R.is_nil(pkg.describe_local('preset', KEY_PRESET_P))
  end)
end)
R.describe("app_apply — cleanup", function()
  return R.it("removes every fixture element and tracking row", function()
    local sid = spaces.get_space_by_name(SP_BOOKS)
    if sid then
      local _list_0 = box.space._tdb_relations.index.by_from:select({
        sid.id
      })
      for _index_0 = 1, #_list_0 do
        local t = _list_0[_index_0]
        box.space._tdb_relations:delete(t[1])
      end
    end
    local _list_0 = box.space._tdb_views:select({ })
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      if v[3] == VIEW_NAME then
        views.delete_view(v[1])
      end
    end
    local _list_1 = box.space._tdb_data_views:select({ })
    for _index_0 = 1, #_list_1 do
      local dv = _list_1[_index_0]
      if dv[2] == DV_NAME then
        data_views.delete_view(dv[1])
      end
    end
    local _list_2 = box.space._tdb_custom_views:select({ })
    for _index_0 = 1, #_list_2 do
      local cv = _list_2[_index_0]
      if cv[2] == PAGE_NAME then
        box.space._tdb_custom_views:delete(cv[1])
      end
    end
    local _list_3 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_3 do
      local wp = _list_3[_index_0]
      if wp[2] == PLUGIN_NAME then
        box.space._tdb_widget_plugins:delete(wp[1])
      end
    end
    local _list_4 = perms.list_groups()
    for _index_0 = 1, #_list_4 do
      local g = _list_4[_index_0]
      if g.name == GROUP_NAME then
        perms.delete_group(g.id)
      end
    end
    clean_app_rows(APP_ID)
    clean_app_rows(APP_BAD_ID)
    spaces.delete_user_space(SP_BOOKS)
    spaces.delete_user_space(SP_AUTHORS)
    R.is_nil(spaces.get_space_by_name(SP_BOOKS))
    R.is_nil(pkg.describe_local('page', "page:" .. tostring(PAGE_NAME)))
    R.is_nil(pkg.describe_local('plugin', "plugin:" .. tostring(PLUGIN_NAME)))
    R.is_nil(pkg.describe_local('group', "group:" .. tostring(GROUP_NAME)))
    R.is_nil(box.space._tdb_apps:get(APP_ID))
    return R.eq(installed_count(APP_ID), 0)
  end)
end)
local SP_UF = "aap_uf_" .. tostring(SUFFIX)
local APP_UF = "org.test.aapuf_" .. tostring(SUFFIX)
local KEY_UF = "field:" .. tostring(SP_UF) .. ".calc"
R.describe("app_apply — field without formula in package (DÉFAUT 2)", function()
  R.it("updates the description of a formula field with formula absent", function()
    local sp = spaces.create_user_space(SP_UF, 'uf')
    spaces.add_field(sp.id, 'calc', 'String', false, 'orig desc', 'self.plain or ""')
    local p1 = subset(pkg.build_package({
      id = APP_UF,
      name = 'UF',
      version = '1.0.0',
      description = ''
    }, { }))
    R.ok(apply.load_package(p1), 'p1 valid')
    local r1 = apply.apply_update(p1, { }, { })
    R.ok(r1.ok, r1.error)
    local items = { }
    local _list_0 = p1.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key == KEY_UF then
        table.insert(items, {
          type = 'field',
          key = it.key,
          content = {
            fieldType = 'String',
            notNull = false,
            description = 'delivered desc',
            language = 'lua'
          }
        })
      else
        table.insert(items, it)
      end
    end
    local p2 = {
      app = {
        id = APP_UF,
        name = 'UF',
        version = '1.1.0',
        description = ''
      },
      items = items,
      seed_keys = { }
    }
    local r2 = apply.apply_update(p2, { }, { })
    R.ok(r2.ok, r2.error)
    local sid = spaces.get_space_by_name(SP_UF).id
    R.eq((field_by_name(sid, 'calc')).description, 'delivered desc')
    local local_c = pkg.describe_local('field', KEY_UF)
    R.eq(local_c.description, 'delivered desc')
    return R.eq(local_c.formula, '', 'delivered field carries no formula')
  end)
  return R.it("cleans up the field-formula fixture", function()
    clean_app_rows(APP_UF)
    spaces.delete_user_space(SP_UF)
    R.is_nil(spaces.get_space_by_name(SP_UF))
    return R.eq(installed_count(APP_UF), 0)
  end)
end)
local SP_CYC = "aap_cyc.books_" .. tostring(SUFFIX)
local SP_CYCB = "aap_cycauth_" .. tostring(SUFFIX)
local SP_CYC2 = "aap_cyc.moved_" .. tostring(SUFFIX)
local FLD_CYC = 'cod.e|x'
local APP_CYC = "org.test.aapcyc_" .. tostring(SUFFIX)
local FIXC = { }
local retarget_esc
retarget_esc = function(key, old, new)
  local _list_0 = {
    'field:',
    'relation:',
    'view:'
  }
  for _index_0 = 1, #_list_0 do
    local prefix = _list_0[_index_0]
    local old_pref = tostring(prefix) .. tostring(pkg.key_part(old)) .. "."
    if key:sub(1, #old_pref) == old_pref then
      return tostring(prefix) .. tostring(pkg.key_part(new)) .. "." .. tostring(key:sub(#old_pref + 1))
    end
  end
  return nil
end
R.describe("app_apply — special names full cycle and space rename", function()
  R.it("creates spaces, a special field and a relation, then builds the package", function()
    local cyc = spaces.create_user_space(SP_CYC, 'cycle books')
    local cycb = spaces.create_user_space(SP_CYCB, 'cycle authors')
    FIXC.cyc_id = cyc.id
    FIXC.cycb_id = cycb.id
    spaces.add_field(cyc.id, FLD_CYC, 'String', false, 'special field')
    local fk = spaces.add_field(cyc.id, 'author_id', 'Int', false, '')
    local seq = spaces.add_field(cycb.id, 'seq_id', 'Sequence')
    local res = schema_r.Mutation.createRelation({ }, {
      input = {
        name = "aap_cycrel_" .. tostring(SUFFIX),
        fromSpaceId = cyc.id,
        fromFieldId = fk.id,
        toSpaceId = cycb.id,
        toFieldId = seq.id,
        reprFormula = '@name',
        cardinality = 'many'
      }
    }, CTX)
    FIXC.rel_id = res.id
    R.ok(res)
    FIXC.p1 = subset(pkg.build_package({
      id = APP_CYC,
      name = 'Cycle',
      version = '1.0.0',
      description = ''
    }, { }))
    return R.ok(FIXC.p1)
  end)
  R.it("removes the local elements, then reinstalls the package", function()
    schema_r.Mutation.deleteRelation({ }, {
      id = FIXC.rel_id
    }, CTX)
    spaces.delete_user_space(SP_CYC)
    spaces.delete_user_space(SP_CYCB)
    R.is_nil(spaces.get_space_by_name(SP_CYC))
    local report = apply.apply_update(FIXC.p1, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#describe_intact(FIXC.p1), 0, 'every delivered element matches the package')
    R.ok(spaces.get_space_by_name(SP_CYC, 'space recreated'))
    local sid = spaces.get_space_by_name(SP_CYC).id
    R.ok((field_by_name(sid, FLD_CYC)), 'special field recreated')
    return R.ok(pkg.describe_local('relation', "relation:" .. tostring(pkg.key_part(SP_CYC)) .. ".author_id"), 'relation recreated')
  end)
  R.it("renames the dotted space and remaps child keys", function()
    local items = { }
    local old_space_key = "space:" .. tostring(pkg.key_part(SP_CYC))
    local _list_0 = FIXC.p1.items
    for _index_0 = 1, #_list_0 do
      local _continue_0 = false
      repeat
        local it = _list_0[_index_0]
        if it.key == old_space_key then
          table.insert(items, {
            type = 'space',
            key = "space:" .. tostring(pkg.key_part(SP_CYC2)),
            content = it.content,
            renamed_from = old_space_key
          })
          _continue_0 = true
          break
        end
        local new_key = retarget_esc(it.key, SP_CYC, SP_CYC2)
        if new_key then
          local content = it.content
          if it.type == 'relation' and content.fromSpace == SP_CYC then
            content = {
              fromSpace = SP_CYC2,
              fromField = content.fromField,
              toSpace = content.toSpace,
              toField = content.toField,
              cardinality = content.cardinality
            }
          end
          local entry = {
            type = it.type,
            key = new_key,
            content = content,
            renamed_from = it.key
          }
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
    local p2 = {
      app = {
        id = APP_CYC,
        name = 'Cycle',
        version = '1.1.0',
        description = ''
      },
      items = items,
      seed_keys = { }
    }
    local report = apply.apply_update(p2, { }, { })
    R.ok(report.ok, report.error)
    R.ok(spaces.get_space_by_name(SP_CYC2), 'renamed space exists')
    R.is_nil(spaces.get_space_by_name(SP_CYC), 'old space gone')
    local nsid = spaces.get_space_by_name(SP_CYC2).id
    R.ok((field_by_name(nsid, FLD_CYC)), 'child field remapped to the new space')
    R.ok(pkg.describe_local('field', "field:" .. tostring(pkg.key_part(SP_CYC2)) .. "." .. tostring(pkg.key_part(FLD_CYC))))
    local old_child = "field:" .. tostring(pkg.key_part(SP_CYC)) .. "." .. tostring(pkg.key_part(FLD_CYC))
    local new_child = "field:" .. tostring(pkg.key_part(SP_CYC2)) .. "." .. tostring(pkg.key_part(FLD_CYC))
    R.is_nil(box.space._tdb_app_items:get({
      APP_CYC,
      old_child
    }, 'old child untracked'))
    return R.ok(box.space._tdb_app_items:get({
      APP_CYC,
      new_child
    }, 'new child tracked'))
  end)
  return R.it("cleans up the special-name cycle fixture", function()
    local cyc = spaces.get_space_by_name(SP_CYC2)
    if cyc then
      local _list_0 = box.space._tdb_relations.index.by_from:select({
        cyc.id
      })
      for _index_0 = 1, #_list_0 do
        local t = _list_0[_index_0]
        box.space._tdb_relations:delete(t[1])
      end
    end
    clean_app_rows(APP_CYC)
    spaces.delete_user_space(SP_CYC2)
    spaces.delete_user_space(SP_CYCB)
    R.is_nil(spaces.get_space_by_name(SP_CYC2))
    return R.is_nil(spaces.get_space_by_name(SP_CYCB))
  end)
end)
local SP_T22 = "aap_t22_" .. tostring(SUFFIX)
local SP_T22B = "aap_t22b_" .. tostring(SUFFIX)
local APP_T22 = "org.test.aapt22_" .. tostring(SUFFIX)
local VIEW_T22 = "aap_t22view_" .. tostring(SUFFIX)
local PAGE_T22 = "aap_t22page_" .. tostring(SUFFIX)
local DV_T22 = "aap_t22dv_" .. tostring(SUFFIX)
local PLG_T22 = "aap_t22plugin_" .. tostring(SUFFIX)
local GRP_T22 = "aap_t22group_" .. tostring(SUFFIX)
local REL_T22 = "aap_t22rel_" .. tostring(SUFFIX)
local F22 = { }
local YAML_PAGE_T22 = [[layout:
  direction: vertical
  children:
    - widget:
        title: T22
        space: t22
]]
local OPTIONAL_KEYS = {
  space = {
    'description'
  },
  field = {
    'description',
    'formula',
    'triggerFields',
    'language'
  },
  relation = {
    'cardinality'
  },
  page = {
    'description'
  },
  dataview = {
    'description'
  },
  plugin = {
    'description',
    'scriptLanguage',
    'templateLanguage',
    'scriptCode',
    'templateCode'
  },
  group = {
    'description'
  }
}
local _sparse_content
_sparse_content = function(item_type, content, mode)
  local copy = { }
  for k, v in pairs(content) do
    copy[k] = v
  end
  local _list_0 = (OPTIONAL_KEYS[item_type] or { })
  for _index_0 = 1, #_list_0 do
    local k = _list_0[_index_0]
    if mode == 'null' then
      if copy[k] ~= nil then
        copy[k] = box.NULL
      end
    else
      copy[k] = nil
    end
  end
  return copy
end
local sparse_pkg
sparse_pkg = function(package, mode)
  local items = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    table.insert(items, {
      type = it.type,
      key = it.key,
      content = _sparse_content(it.type, it.content, mode)
    })
  end
  return {
    app = package.app,
    items = items,
    seed_keys = package.seed_keys or { }
  }
end
local roundtrip
roundtrip = function(package)
  local decoded = yaml.decode(yaml.encode(package))
  local norm, err = apply.load_package(decoded)
  R.ok(norm, "load_package: " .. tostring(err))
  return norm
end
local remove_t22
remove_t22 = function()
  local _list_0 = box.space._tdb_views:select({ })
  for _index_0 = 1, #_list_0 do
    local v = _list_0[_index_0]
    if v[3] == VIEW_T22 then
      views.delete_view(v[1])
    end
  end
  local _list_1 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_1 do
    local dv = _list_1[_index_0]
    if dv[2] == DV_T22 then
      data_views.delete_view(dv[1])
    end
  end
  local _list_2 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_2 do
    local cv = _list_2[_index_0]
    if cv[2] == PAGE_T22 then
      box.space._tdb_custom_views:delete(cv[1])
    end
  end
  local _list_3 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_3 do
    local wp = _list_3[_index_0]
    if wp[2] == PLG_T22 then
      box.space._tdb_widget_plugins:delete(wp[1])
    end
  end
  local _list_4 = perms.list_groups()
  for _index_0 = 1, #_list_4 do
    local g = _list_4[_index_0]
    if g.name == GRP_T22 then
      perms.delete_group(g.id)
    end
  end
  local _list_5 = {
    SP_T22,
    SP_T22B
  }
  for _index_0 = 1, #_list_5 do
    local nm = _list_5[_index_0]
    local sp = spaces.get_space_by_name(nm)
    if sp then
      local _list_6 = box.space._tdb_relations.index.by_from:select({
        sp.id
      })
      for _index_1 = 1, #_list_6 do
        local t = _list_6[_index_1]
        box.space._tdb_relations:delete(t[1])
      end
      local _list_7 = box.space._tdb_relations.index.by_to:select({
        sp.id
      })
      for _index_1 = 1, #_list_7 do
        local t = _list_7[_index_1]
        box.space._tdb_relations:delete(t[1])
      end
    end
  end
  spaces.delete_user_space(SP_T22)
  return spaces.delete_user_space(SP_T22B)
end
R.describe("app_apply — T22 fixture", function()
  return R.it("creates every element type with default optional values", function()
    local books = spaces.create_user_space(SP_T22, '')
    local authors = spaces.create_user_space(SP_T22B, '')
    spaces.add_field(books.id, 'code', 'String', true, '')
    local fk = spaces.add_field(books.id, 'author_id', 'Int', false, '')
    local seq = spaces.add_field(authors.id, 'seq_id', 'Sequence')
    local res = schema_r.Mutation.createRelation({ }, {
      input = {
        name = REL_T22,
        fromSpaceId = books.id,
        fromFieldId = fk.id,
        toSpaceId = authors.id,
        toFieldId = seq.id,
        reprFormula = '@seq_id',
        cardinality = 'one'
      }
    }, CTX)
    F22.rel_id = res.id
    local v = views.create_view(books.id, VIEW_T22, 'grid', {
      layout = {
        direction = 'vertical',
        children = { }
      }
    })
    F22.view_id = v.id
    local p = cvr.Mutation.createCustomView({ }, {
      name = PAGE_T22,
      description = '',
      yaml = YAML_PAGE_T22
    }, CTX)
    F22.page_id = p.id
    local dv = dv_r.Mutation.createDataView(nil, {
      input = {
        name = DV_T22,
        description = '',
        sourceSpace = SP_T22,
        config = json.encode({
          columns = {
            'code'
          }
        })
      }
    }, CTX)
    F22.dv_id = dv.id
    local now = os.time()
    F22.plugin_id = "aap_t22plugin_id_" .. tostring(SUFFIX)
    box.space._tdb_widget_plugins:insert({
      F22.plugin_id,
      PLG_T22,
      '',
      'coffeescript',
      'pug',
      '',
      '',
      now,
      now
    })
    local g = perms.create_group(GRP_T22, '')
    F22.group_id = g.id
    perms.grant(g.id, 'space', books.id, 'read')
    perms.grant(g.id, 'space', nil, 'write')
    local _list_0 = {
      {
        code = 'T22-1',
        author_id = 0
      },
      {
        code = 'T22-2',
        author_id = 0
      }
    }
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      data_r.Mutation.insertRecord({ }, {
        spaceId = books.id,
        data = row
      }, CTX)
    end
    F22.seed = {
      [SP_T22] = 'code'
    }
    return R.ok(books and authors and res and v and p and dv and F22.plugin_id and g)
  end)
end)
R.describe("app_apply — T22 export round-trip invariant", function()
  R.it("a build_package YAML round-trip is entirely unchanged", function()
    F22.pkg = subset(pkg.build_package({
      id = APP_T22,
      name = 'T22',
      version = '1.0.0',
      description = ''
    }, {
      seed = F22.seed
    }))
    F22.norm = roundtrip(F22.pkg)
    local plan = apply.preview_update(F22.norm)
    R.eq(#plan.errors, 0, 'preview errors')
    R.eq(#plan.update, 0, 'no spurious update')
    R.eq(#plan.conflict, 0, 'no spurious conflict')
    R.eq(#plan.create, 0, 'no spurious create')
    return R.eq(#plan.unchanged, #F22.norm.items, 'all unchanged')
  end)
  return R.it("nulled and dropped optional keys are still entirely unchanged", function()
    local _list_0 = {
      'null',
      'drop'
    }
    for _index_0 = 1, #_list_0 do
      local mode = _list_0[_index_0]
      local norm = roundtrip(sparse_pkg(F22.pkg, mode))
      local plan = apply.preview_update(norm)
      R.eq(#plan.errors, 0, "errors (" .. tostring(mode) .. ")")
      R.eq(#plan.update, 0, "update (" .. tostring(mode) .. ")")
      R.eq(#plan.conflict, 0, "conflict (" .. tostring(mode) .. ")")
      R.eq(#plan.unchanged, #norm.items, "unchanged (" .. tostring(mode) .. ")")
    end
  end)
end)
R.describe("app_apply — T22 install and update through yaml", function()
  R.it("installs a nulled package on a clean base", function()
    remove_t22()
    clean_app_rows(APP_T22)
    R.is_nil(spaces.get_space_by_name(SP_T22))
    F22.norm2 = roundtrip(sparse_pkg(F22.pkg, 'null'))
    local report = apply.apply_update(F22.norm2, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.created, #F22.norm2.items, 'created')
    return R.eq(#describe_intact(F22.norm2), 0, 'all delivered elements match')
  end)
  R.it("a real author change stays an update", function()
    local changed = sparse_pkg(F22.pkg, 'null')
    local _list_0 = changed.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key == "space:" .. tostring(SP_T22) then
        it.content.description = 'author changed'
      end
    end
    local norm = roundtrip(changed)
    local plan = apply.preview_update(norm)
    R.eq(#plan.errors, 0)
    R.eq(#plan.update, 1, 'one update')
    return R.eq(plan.update[1].key, "space:" .. tostring(SP_T22))
  end)
  return R.it("updates a page and a data view delivered with a null description", function()
    local local_pkg = subset(pkg.build_package({
      id = APP_T22,
      name = 'T22',
      version = '1.1.0',
      description = ''
    }, {
      seed = F22.seed
    }))
    local changed = sparse_pkg(local_pkg, 'null')
    local _list_0 = changed.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key == "page:" .. tostring(PAGE_T22) then
        it.content.yaml = tostring(it.content.yaml) .. "\n# changed\n"
      end
      if it.key == "dataview:" .. tostring(DV_T22) then
        it.content.config = json.encode({
          columns = {
            'code',
            'author_id'
          }
        })
      end
    end
    local norm = roundtrip(changed)
    local plan = apply.preview_update(norm)
    R.eq(#plan.errors, 0, 'preview errors')
    R.eq(#plan.update, 2, 'page and data view update')
    local report = apply.apply_update(norm, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#report.updated, 2, 'updated')
    R.eq(pkg.describe_local('page', "page:" .. tostring(PAGE_T22)).description, '')
    return R.eq(pkg.describe_local('dataview', "dataview:" .. tostring(DV_T22)).description, '')
  end)
end)
return R.describe("app_apply — T22 cleanup", function()
  return R.it("removes the T22 fixture", function()
    clean_app_rows(APP_T22)
    remove_t22()
    R.is_nil(spaces.get_space_by_name(SP_T22))
    R.is_nil(spaces.get_space_by_name(SP_T22B))
    R.is_nil(pkg.describe_local('page', "page:" .. tostring(PAGE_T22)))
    R.is_nil(pkg.describe_local('dataview', "dataview:" .. tostring(DV_T22)))
    R.is_nil(pkg.describe_local('plugin', "plugin:" .. tostring(PLG_T22)))
    R.is_nil(pkg.describe_local('group', "group:" .. tostring(GRP_T22)))
    return R.eq(installed_count(APP_T22), 0)
  end)
end)
