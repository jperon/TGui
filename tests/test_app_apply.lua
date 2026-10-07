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
            triggerFields = { },
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
      triggerFields = { },
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
          triggerFields = { },
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
return R.describe("app_apply — cleanup", function()
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
