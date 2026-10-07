local R = require('tests.runner')
local auth = require('core.auth')
local perms_mod = require('core.permissions')
local spaces = require('core.spaces')
local views = require('core.views')
local data_views = require('core.data_views')
local app_package = require('core.app_package')
local app_r = require('resolvers.app_resolvers')
local executor = require('graphql.executor')
local yaml = require('yaml')
local json = require('json')
local data_r = require('resolvers.data_resolvers')
local cvr = require('resolvers.custom_view_resolvers')
local dv_r = require('resolvers.data_view_resolvers')
local wpr = require('resolvers.widget_plugin_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "ar_sp_" .. tostring(SUFFIX)
local SP_AUX = "ar_aux_" .. tostring(SUFFIX)
local VIEW_NAME = "ar_view_" .. tostring(SUFFIX)
local PAGE_NAME = "ar_page_" .. tostring(SUFFIX)
local DV_NAME = "ar_dv_" .. tostring(SUFFIX)
local PLUGIN_NAME = "ar_plugin_" .. tostring(SUFFIX)
local GROUP_NAME = "ar_group_" .. tostring(SUFFIX)
local FIELD_CODE = "field:" .. tostring(SP_NAME) .. ".code"
local FIELD_QTY = "field:" .. tostring(SP_NAME) .. ".qty"
local FIELD_NOTE = "field:" .. tostring(SP_NAME) .. ".note"
local APP_ID = "org.test.ar_" .. tostring(SUFFIX)
local GHOST_PLUGIN = "ar_ghost_plugin_" .. tostring(SUFFIX)
local GHOST_PAGE = "ar_ghost_page_" .. tostring(SUFFIX)
local GHOST_DV = "ar_ghost_dv_" .. tostring(SUFFIX)
local GHOST_BASE = "ar_ghost_" .. tostring(SUFFIX)
local admin = auth.get_user_by_username('admin')
local ADMIN_CTX = {
  user_id = admin.id
}
local ACTOR = auth.create_user("aractor_" .. tostring(SUFFIX), "aractor_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
local ACTOR_SESSION = auth.create_session(ACTOR.id)
local NONADMIN_CTX = {
  user_id = ACTOR.id,
  token = ACTOR_SESSION.token
}
local ANON_CTX = { }
local YAML_PAGE = [[layout:
  direction: vertical
  children:
    - widget:
        title: App resolvers
        space: ar
]]
local FIX = { }
local YAML1 = nil
local DECODED1 = nil
local YAML3 = nil
local seed_opts = { }
local field_by_name
field_by_name = function(space_name, name)
  local sp = spaces.get_space_by_name(space_name)
  if not (sp) then
    return nil
  end
  local _list_0 = spaces.list_fields(sp.id)
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    if f.name == name then
      return f
    end
  end
  return nil
end
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
local find_created
find_created = function(plan, key)
  local _list_0 = plan.create
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key == key then
      return it
    end
  end
  return nil
end
local set_description
set_description = function(package, key, value)
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key == key and type(it.content) == 'table' then
      it.content.description = value
    end
  end
  return package
end
local without_item
without_item = function(package, key)
  local kept
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = package.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key ~= key then
        _accum_0[_len_0] = it
        _len_0 = _len_0 + 1
      end
    end
    kept = _accum_0
  end
  package.items = kept
  return package
end
local variant
variant = function(base_yaml, key, value)
  local package = yaml.decode(base_yaml)
  return yaml.encode(set_description(package, key, value))
end
local remove_fixture
remove_fixture = function()
  local _list_0 = box.space._tdb_views:select({ })
  for _index_0 = 1, #_list_0 do
    local v = _list_0[_index_0]
    if v[3] == VIEW_NAME then
      views.delete_view(v[1])
    end
  end
  local _list_1 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_1 do
    local cv = _list_1[_index_0]
    if cv[2] == PAGE_NAME then
      cvr.Mutation.deleteCustomView({ }, {
        id = cv[1]
      }, ADMIN_CTX)
    end
  end
  local _list_2 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_2 do
    local dv = _list_2[_index_0]
    if dv[2] == DV_NAME then
      dv_r.Mutation.deleteDataView(nil, {
        id = dv[1]
      }, ADMIN_CTX)
    end
  end
  local _list_3 = box.space._tdb_widget_plugins:select({ })
  for _index_0 = 1, #_list_3 do
    local wp = _list_3[_index_0]
    if wp[2] == PLUGIN_NAME then
      wpr.Mutation.deleteWidgetPlugin({ }, {
        id = wp[1]
      }, ADMIN_CTX)
    end
  end
  local _list_4 = perms_mod.list_groups()
  for _index_0 = 1, #_list_4 do
    local g = _list_4[_index_0]
    if g.name == GROUP_NAME then
      perms_mod.delete_group(g.id)
    end
  end
  spaces.delete_user_space(SP_NAME)
  return spaces.delete_user_space(SP_AUX)
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
local run_gql
run_gql = function(query, vars, ctx)
  return executor.execute({
    query = query,
    variables = (vars or { }),
    context = ctx
  })
end
local errs_json
errs_json = function(res)
  return json.encode(res.errors or { })
end
local ghost_package
ghost_package = function()
  local items = {
    {
      type = 'field',
      key = "field:" .. tostring(GHOST_BASE) .. ".plain",
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
      type = 'field',
      key = "field:" .. tostring(GHOST_BASE) .. ".calc",
      content = {
        fieldType = 'Int',
        notNull = false,
        description = '',
        formula = '1 + 1',
        triggerFields = { },
        language = 'lua'
      }
    },
    {
      type = 'field',
      key = "field:" .. tostring(GHOST_BASE) .. ".trig",
      content = {
        fieldType = 'String',
        notNull = false,
        description = '',
        formula = '',
        triggerFields = {
          'a'
        },
        language = 'moon'
      }
    },
    {
      type = 'plugin',
      key = "plugin:" .. tostring(GHOST_PLUGIN),
      content = {
        name = GHOST_PLUGIN,
        description = '',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = 'x = 1',
        templateCode = 'div'
      }
    },
    {
      type = 'page',
      key = "page:" .. tostring(GHOST_PAGE),
      content = {
        name = GHOST_PAGE,
        description = '',
        yaml = 'layout: {}'
      }
    },
    {
      type = 'dataview',
      key = "dataview:" .. tostring(GHOST_DV),
      content = {
        name = GHOST_DV,
        description = '',
        sourceSpace = GHOST_BASE,
        config = {
          columns = {
            'x'
          }
        }
      }
    }
  }
  return {
    app = {
      id = "org.test.arghost_" .. tostring(SUFFIX),
      name = 'Ghost',
      version = '1.0.0',
      description = ''
    },
    items = items,
    seed_keys = { }
  }
end
R.describe("app_resolvers — fixture", function()
  R.it("creates a space with data, a view, a page, a data view, a plugin and a group", function()
    local books = spaces.create_user_space(SP_NAME, 'app resolvers books')
    FIX.books_id = books.id
    spaces.add_field(books.id, 'code', 'String', true, 'natural key')
    spaces.add_field(books.id, 'qty', 'Int', false, '')
    spaces.add_field(books.id, 'total', 'Int', false, '', '(self.qty or 0) * 2')
    spaces.add_field(books.id, 'note', 'String', false, '')
    FIX.view_id = views.create_view(books.id, VIEW_NAME, 'grid', {
      layout = {
        direction = 'vertical',
        children = { }
      }
    }).id
    FIX.page_id = cvr.Mutation.createCustomView({ }, {
      name = PAGE_NAME,
      description = 'ar page',
      yaml = YAML_PAGE
    }, ADMIN_CTX).id
    FIX.dv_id = dv_r.Mutation.createDataView(nil, {
      input = {
        name = DV_NAME,
        description = 'ar dv',
        sourceSpace = SP_NAME,
        config = json.encode({
          columns = {
            'code',
            'qty'
          }
        })
      }
    }, ADMIN_CTX).id
    FIX.plugin_id = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = PLUGIN_NAME,
        description = 'ar plugin',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = "render 'x'",
        templateCode = 'div x'
      }
    }, ADMIN_CTX).id
    FIX.group_id = perms_mod.create_group(GROUP_NAME, 'ar group').id
    perms_mod.grant(FIX.group_id, 'space', books.id, 'read')
    R.ok(spaces.get_space_by_name(SP_NAME))
    R.ok(FIX.view_id)
    R.ok(FIX.page_id)
    R.ok(FIX.dv_id)
    R.ok(FIX.plugin_id)
    return R.ok(FIX.group_id)
  end)
  return R.it("inserts seed rows (including one with a note value)", function()
    local _list_0 = {
      {
        code = 'AR-1',
        qty = 2
      },
      {
        code = 'AR-2',
        qty = 5
      },
      {
        code = 'AR-3',
        qty = 0,
        note = 'hello'
      }
    }
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      data_r.Mutation.insertRecord({ }, {
        spaceId = FIX.books_id,
        data = row
      }, ADMIN_CTX)
    end
    seed_opts[SP_NAME] = 'code'
    local sp = box.space["data_" .. tostring(SP_NAME)]
    return R.eq(#sp:select({ }), 3)
  end)
end)
R.describe("app_resolvers — permissions", function()
  local export_args
  export_args = function()
    return {
      meta = {
        id = APP_ID,
        name = 'AR',
        version = '1.0.0',
        description = ''
      },
      seed = {
        {
          space = SP_NAME,
          keyField = 'code'
        }
      }
    }
  end
  R.it("every operation is Unauthorized for an anonymous context", function()
    R.raises((function()
      return app_r.Query.listApps(nil, { }, ANON_CTX)
    end), 'Unauthorized')
    R.raises((function()
      return app_r.Query.exportApp(nil, export_args(), ANON_CTX)
    end), 'Unauthorized')
    R.raises((function()
      return app_r.Query.previewAppUpdate(nil, {
        yaml = 'a: 1'
      }, ANON_CTX)
    end), 'Unauthorized')
    R.raises((function()
      return app_r.Query.previewAppPurge(nil, {
        appId = APP_ID,
        keys = { }
      }, ANON_CTX)
    end), 'Unauthorized')
    R.raises((function()
      return app_r.Mutation.applyAppUpdate(nil, {
        yaml = 'a: 1'
      }, ANON_CTX)
    end), 'Unauthorized')
    return R.raises((function()
      return app_r.Mutation.purgeAppObsolete(nil, {
        appId = APP_ID,
        keys = { },
        confirmed = true
      }, ANON_CTX)
    end), 'Unauthorized')
  end)
  return R.it("every operation is Forbidden for an authenticated non-admin", function()
    R.raises((function()
      return app_r.Query.listApps(nil, { }, NONADMIN_CTX)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.exportApp(nil, export_args(), NONADMIN_CTX)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.previewAppUpdate(nil, {
        yaml = 'a: 1'
      }, NONADMIN_CTX)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.previewAppPurge(nil, {
        appId = APP_ID,
        keys = { }
      }, NONADMIN_CTX)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Mutation.applyAppUpdate(nil, {
        yaml = 'a: 1'
      }, NONADMIN_CTX)
    end), 'Forbidden')
    return R.raises((function()
      return app_r.Mutation.purgeAppObsolete(nil, {
        appId = APP_ID,
        keys = { },
        confirmed = true
      }, NONADMIN_CTX)
    end), 'Forbidden')
  end)
end)
R.describe("app_resolvers — exportApp", function()
  R.it("builds a YAML package that reloads into a valid package", function()
    YAML1 = app_r.Query.exportApp({ }, {
      meta = {
        id = APP_ID,
        name = 'App resolvers',
        version = '1.0.0',
        description = 'ar'
      },
      seed = {
        {
          space = SP_NAME,
          keyField = 'code'
        }
      }
    }, ADMIN_CTX)
    R.eq(type(YAML1), 'string')
    DECODED1 = yaml.decode(YAML1)
    R.ok(DECODED1)
    R.eq(DECODED1.app.id, APP_ID)
    R.eq(DECODED1.app.version, '1.0.0')
    R.ok(DECODED1.app.name)
    R.ok((find_item(DECODED1, FIELD_CODE)), 'code field delivered')
    R.ok((find_item(DECODED1, FIELD_QTY)), 'qty field delivered')
    R.ok((find_item(DECODED1, FIELD_NOTE)), 'note field delivered')
    R.eq((find_item(DECODED1, FIELD_NOTE)).content.formula, '')
    R.ok((find_item(DECODED1, "seed:" .. tostring(SP_NAME) .. "|AR-1")), 'seed row delivered')
    return R.is_nil(find_item(DECODED1, 'group:admin'), 'admin group never delivered')
  end)
  return R.it("refuses a version that is not x.y.z", function()
    local bad = {
      meta = {
        id = APP_ID,
        name = 'AR',
        version = '1.0',
        description = ''
      }
    }
    R.raises((function()
      return app_r.Query.exportApp(nil, bad, ADMIN_CTX)
    end), 'semver')
    local bad2 = {
      meta = {
        id = APP_ID,
        name = 'AR',
        version = 'abc',
        description = ''
      }
    }
    R.raises((function()
      return app_r.Query.exportApp(nil, bad2, ADMIN_CTX)
    end), 'semver')
    local bad3 = {
      meta = {
        id = APP_ID,
        name = 'AR',
        version = nil,
        description = ''
      }
    }
    return R.raises((function()
      return app_r.Query.exportApp(nil, bad3, ADMIN_CTX)
    end), 'semver')
  end)
end)
R.describe("app_resolvers — previewAppUpdate is read-only", function()
  R.it("reports every element unchanged while the local DB matches the package", function()
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = YAML1
    }, ADMIN_CTX)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 0, 'create')
    R.eq(#plan.update, 0, 'update')
    R.eq(#plan.conflict, 0, 'conflict')
    return R.eq(#plan.unchanged, #DECODED1.items, 'unchanged')
  end)
  return R.it("writes nothing", function()
    local spaces_before = #spaces.list_spaces()
    local fields_before = #box.space._tdb_fields:select({ })
    local rows_before = #box.space._tdb_app_items.index.by_app:select({
      APP_ID
    })
    local qty_desc_before = (field_by_name(SP_NAME, 'qty')).description
    app_r.Query.previewAppUpdate(nil, {
      yaml = YAML1
    }, ADMIN_CTX)
    R.eq(#spaces.list_spaces(), spaces_before)
    R.eq(#box.space._tdb_fields:select({ }), fields_before)
    R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }), rows_before)
    R.eq((field_by_name(SP_NAME, 'qty')).description, qty_desc_before)
    return R.nok(box.space._tdb_apps:get(APP_ID), 'preview must not install the app')
  end)
end)
R.describe("app_resolvers — GraphQL wiring via the executor", function()
  return R.it("listApps and previewAppUpdate are reachable through the real schema", function()
    require('resolvers.init').reinit()
    local q = "{ listApps { appId name version activeCount obsoleteCount } }"
    local res = run_gql(q, { }, ADMIN_CTX)
    R.nok(res.errors, errs_json(res))
    R.eq(type(res.data.listApps), 'table')
    local q2 = 'query($y: String!) { previewAppUpdate(yaml: $y) { create { key type isCode } update { key } conflict { key local delivered } unchanged errors } }'
    local res2 = run_gql(q2, {
      y = YAML1
    }, ADMIN_CTX)
    R.nok(res2.errors, errs_json(res2))
    R.eq(#res2.data.previewAppUpdate.errors, 0)
    R.eq(#res2.data.previewAppUpdate.create, 0)
    return R.eq(#res2.data.previewAppUpdate.unchanged, #DECODED1.items)
  end)
end)
R.describe("app_resolvers — apply on a deleted base recreates everything", function()
  R.it("removes every fixture element", function()
    remove_fixture()
    R.is_nil(spaces.get_space_by_name(SP_NAME))
    R.is_nil(app_package.describe_local('view', "view:" .. tostring(SP_NAME) .. "." .. tostring(VIEW_NAME)))
    R.is_nil(app_package.describe_local('page', "page:" .. tostring(PAGE_NAME)))
    R.is_nil(app_package.describe_local('group', "group:" .. tostring(GROUP_NAME)))
    return R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }), 0)
  end)
  return R.it("applyAppUpdate recreates the space, the elements and the seed rows", function()
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = YAML1
    }, ADMIN_CTX)
    R.ok(report.ok, report.error)
    R.ok(#report.created > 0, 'some items were created')
    R.ok(spaces.get_space_by_name(SP_NAME))
    R.ok((field_by_name(SP_NAME, 'code')))
    R.ok((field_by_name(SP_NAME, 'qty')))
    R.ok((field_by_name(SP_NAME, 'note')))
    R.eq(#box.space["data_" .. tostring(SP_NAME)]:select({ }), 3)
    R.ok(app_package.describe_local('view', "view:" .. tostring(SP_NAME) .. "." .. tostring(VIEW_NAME)))
    R.ok(app_package.describe_local('page', "page:" .. tostring(PAGE_NAME)))
    R.ok(app_package.describe_local('dataview', "dataview:" .. tostring(DV_NAME)))
    R.ok(app_package.describe_local('plugin', "plugin:" .. tostring(PLUGIN_NAME)))
    R.ok(app_package.describe_local('group', "group:" .. tostring(GROUP_NAME)))
    R.eq(box.space._tdb_apps:get(APP_ID)[3], '1.0.0')
    return R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }), #DECODED1.items)
  end)
end)
R.describe("app_resolvers — obsolete items and purge", function()
  R.it("applying a package without the note field marks it obsolete", function()
    YAML3 = yaml.encode(without_item(yaml.decode(YAML1), FIELD_NOTE))
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = YAML3
    }, ADMIN_CTX)
    R.ok(report.ok, report.error)
    local found = false
    local _list_0 = report.obsolete
    for _index_0 = 1, #_list_0 do
      local key = _list_0[_index_0]
      if key == FIELD_NOTE then
        found = true
      end
    end
    R.ok(found, 'note field reported obsolete')
    local note_tracking = box.space._tdb_app_items:get({
      APP_ID,
      FIELD_NOTE
    })
    R.eq(note_tracking[6], 'obsolète')
    return R.ok((field_by_name(SP_NAME, 'note')), 'obsolete field is never deleted')
  end)
  R.it("previewAppPurge reports the losses and writes nothing", function()
    local preview = app_r.Query.previewAppPurge(nil, {
      appId = APP_ID,
      keys = {
        FIELD_NOTE
      }
    }, ADMIN_CTX)
    R.eq(#preview.losses, 1)
    R.eq(preview.losses[1].key, FIELD_NOTE)
    R.eq(preview.losses[1].type, 'field')
    R.eq(preview.losses[1].records, 1, 'one row carries a note value')
    R.eq(preview.totalRecords, 1)
    R.ok((field_by_name(SP_NAME, 'note')), 'preview must not purge')
    local still = box.space._tdb_app_items:get({
      APP_ID,
      FIELD_NOTE
    })
    return R.eq(still[6], 'obsolète')
  end)
  R.it("purgeAppObsolete refuses without explicit confirmation", function()
    local report = app_r.Mutation.purgeAppObsolete(nil, {
      appId = APP_ID,
      keys = {
        FIELD_NOTE
      },
      confirmed = false
    }, ADMIN_CTX)
    R.nok(report.ok)
    R.matches(report.error, 'confirmation')
    return R.ok((field_by_name(SP_NAME, 'note')), 'not purged without confirmation')
  end)
  return R.it("purgeAppObsolete purges with confirmed = true", function()
    local report = app_r.Mutation.purgeAppObsolete(nil, {
      appId = APP_ID,
      keys = {
        FIELD_NOTE
      },
      confirmed = true
    }, ADMIN_CTX)
    R.ok(report.ok, report.error)
    R.eq(#report.purged, 1)
    R.eq(report.purged[1], FIELD_NOTE)
    R.is_nil(field_by_name(SP_NAME, 'note'))
    return R.is_nil(box.space._tdb_app_items:get({
      APP_ID,
      FIELD_NOTE
    }))
  end)
end)
R.describe("app_resolvers — conflict decisions", function()
  R.it("a conflict without a decision is refused and writes nothing", function()
    local qty = field_by_name(SP_NAME, 'qty')
    spaces.update_field(qty.id, {
      description = 'LOCAL-QTY'
    })
    FIX.yaml2 = variant(YAML3, FIELD_QTY, 'AUTHOR-QTY')
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = FIX.yaml2
    }, ADMIN_CTX)
    R.nok(report.ok)
    R.matches(report.error, 'decision')
    return R.eq((field_by_name(SP_NAME, 'qty')).description, 'LOCAL-QTY')
  end)
  R.it("preview exposes local and delivered contents for the conflict", function()
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = FIX.yaml2
    }, ADMIN_CTX)
    R.eq(#plan.conflict, 1)
    R.eq(plan.conflict[1].key, FIELD_QTY)
    R.eq(plan.conflict[1]["local"].description, 'LOCAL-QTY')
    return R.eq(plan.conflict[1].delivered.description, 'AUTHOR-QTY')
  end)
  R.it("an invalid choice is rejected", function()
    local bad = {
      yaml = FIX.yaml2,
      decisions = {
        {
          key = FIELD_QTY,
          choice = 'banana'
        }
      }
    }
    return R.raises((function()
      return app_r.Mutation.applyAppUpdate(nil, bad, ADMIN_CTX)
    end), 'Invalid decision')
  end)
  return R.it("accepting the delivered value applies the author change", function()
    local args = {
      yaml = FIX.yaml2,
      decisions = {
        {
          key = FIELD_QTY,
          choice = 'delivered'
        }
      }
    }
    local report = app_r.Mutation.applyAppUpdate(nil, args, ADMIN_CTX)
    R.ok(report.ok, report.error)
    return R.eq((field_by_name(SP_NAME, 'qty')).description, 'AUTHOR-QTY')
  end)
end)
R.describe("app_resolvers — isCode marks third-party code", function()
  return R.it("flags plugins, pages, data views and formula/trigger fields", function()
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = yaml.encode(ghost_package())
    }, ADMIN_CTX)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 6)
    R.nok((find_created(plan, "field:" .. tostring(GHOST_BASE) .. ".plain")).isCode, 'plain field')
    R.ok((find_created(plan, "field:" .. tostring(GHOST_BASE) .. ".calc")).isCode, 'formula field')
    R.ok((find_created(plan, "field:" .. tostring(GHOST_BASE) .. ".trig")).isCode, 'trigger field')
    R.ok((find_created(plan, "plugin:" .. tostring(GHOST_PLUGIN))).isCode, 'plugin')
    R.ok((find_created(plan, "page:" .. tostring(GHOST_PAGE))).isCode, 'page')
    return R.ok((find_created(plan, "dataview:" .. tostring(GHOST_DV))).isCode, 'data view')
  end)
end)
R.describe("app_resolvers — invalid inputs", function()
  R.it("invalid YAML is refused with a clear error", function()
    R.raises((function()
      return app_r.Query.previewAppUpdate(nil, {
        yaml = '{{{'
      }, ADMIN_CTX)
    end), 'Invalid YAML')
    return R.raises((function()
      return app_r.Mutation.applyAppUpdate(nil, {
        yaml = 'a: [1, 2'
      }, ADMIN_CTX)
    end), 'Invalid YAML')
  end)
  return R.it("a package without app id is refused with a clear error", function()
    local bad = yaml.encode({
      app = { },
      items = { }
    })
    return R.raises((function()
      return app_r.Query.previewAppUpdate(nil, {
        yaml = bad
      }, ADMIN_CTX)
    end), 'Invalid package')
  end)
end)
R.describe("app_resolvers — listApps", function()
  return R.it("lists the installed app with its item counts", function()
    local apps = app_r.Query.listApps(nil, { }, ADMIN_CTX)
    local found = nil
    for _index_0 = 1, #apps do
      local app = apps[_index_0]
      if app.appId == APP_ID then
        found = app
      end
    end
    R.ok(found, 'installed app listed')
    R.eq(found.name, 'App resolvers')
    R.eq(found.version, '1.0.0')
    R.ok(found.activeCount > 0, 'active items counted')
    R.eq(found.obsoleteCount, 0, 'no obsolete item remains after purge')
    return R.ok(found.installedAt > 0)
  end)
end)
return R.describe("app_resolvers — cleanup", function()
  return R.it("removes the fixture and the app tracking rows", function()
    remove_fixture()
    clean_app_rows(APP_ID)
    auth.delete_session(ACTOR_SESSION.token)
    box.space._tdb_users:delete(ACTOR.id)
    R.is_nil(spaces.get_space_by_name(SP_NAME))
    R.is_nil(box.space._tdb_apps:get(APP_ID))
    return R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }), 0)
  end)
end)
