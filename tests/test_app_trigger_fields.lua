local R = require('tests.runner')
local apply = require('core.app_apply')
local pkg_mod = require('core.app_package')
local spaces = require('core.spaces')
local data_r = require('resolvers.data_resolvers')
local dynamic = require('graphql.dynamic')
local executor = require('graphql.executor')
local auth = require('core.auth')
local builder = require('tools.app_builder')
local json = require('json')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local SP = "t3b_calc_" .. tostring(SUFFIX)
local APP_ID = "org.test.t3b_" .. tostring(SUFFIX)
local F_PLAIN = 'qty'
local F_READ = 'calc_read'
local F_WRITE = 'calc_write'
local KEY_SPACE = "space:" .. tostring(SP)
local KEY_PLAIN = "field:" .. tostring(SP) .. "." .. tostring(F_PLAIN)
local KEY_READ = "field:" .. tostring(SP) .. "." .. tostring(F_READ)
local KEY_WRITE = "field:" .. tostring(SP) .. "." .. tostring(F_WRITE)
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local plain_item = {
  type = 'field',
  key = KEY_PLAIN,
  content = {
    fieldType = 'Int',
    notNull = false,
    description = '',
    formula = '',
    language = 'lua'
  }
}
local read_item = {
  type = 'field',
  key = KEY_READ,
  content = {
    fieldType = 'Int',
    notNull = false,
    description = '',
    formula = '(self.qty or 0) * 2',
    language = 'lua'
  }
}
local write_item = {
  type = 'field',
  key = KEY_WRITE,
  content = {
    fieldType = 'Int',
    notNull = false,
    description = '',
    formula = '(self.qty or 0) * 3',
    triggerFields = { },
    language = 'lua'
  }
}
local PKG = {
  app = {
    id = APP_ID,
    name = 'T3b trigger fields',
    version = '1.0.0',
    description = ''
  },
  items = {
    {
      type = 'space',
      key = KEY_SPACE,
      content = {
        description = 't3b computed columns'
      }
    },
    plain_item,
    read_item,
    write_item
  },
  seed_keys = { }
}
local field_tuple
field_tuple = function(sid, name)
  local _list_0 = box.space._tdb_fields.index.by_space:select({
    sid
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[3] == name then
      return t
    end
  end
  return nil
end
local stored_row
stored_row = function(id)
  local t = box.space["data_" .. tostring(SP)]:get(id)
  return json.decode(t[2])
end
local subset
subset = function(package)
  local items
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = package.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key:find(SP, 1, true) then
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
local local_package
local_package = function(version)
  local meta = {
    id = APP_ID,
    name = 'T3b trigger fields',
    version = version,
    description = ''
  }
  return subset(pkg_mod.build_package(meta, { }))
end
local by_key
by_key = function(package)
  local m = { }
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    m[it.key] = it
  end
  return m
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
R.describe("T3b — install d'un paquet à colonnes calculées", function()
  R.it("installs the package (one space, three fields)", function()
    local report = apply.apply_update(PKG, { }, { })
    R.ok(report.ok, report.error)
    R.eq(#(report.errors or { }), 0, 'errors')
    R.eq(#report.created, 4, 'created')
    return R.ok(spaces.get_space_by_name(SP))
  end)
  R.it("(1) _tdb_fields column 9: null for (a) and (c), [] for (b)", function()
    local sid = spaces.get_space_by_name(SP).id
    local t_read = field_tuple(sid, F_READ)
    R.ok(t_read, 'computed field row')
    R.eq(t_read[9], 'null', 'computed column must carry no trigger')
    local t_write = field_tuple(sid, F_WRITE)
    R.ok(t_write, 'trigger field row')
    R.eq(t_write[9], '[]', 'create-only trigger must be an empty list')
    local t_plain = field_tuple(sid, F_PLAIN)
    R.ok(t_plain, 'plain field row')
    return R.ok((t_plain[9] == nil or t_plain[9] == 'null'), 'plain field carries no trigger')
  end)
  R.it("(2) insert stores the trigger value of (b) only", function()
    local sp = spaces.get_space_by_name(SP)
    local res = data_r.Mutation.insertRecord({ }, {
      spaceId = sp.id,
      data = {
        qty = 5
      }
    }, CTX)
    R.ok(res, 'record inserted')
    local row = stored_row(res.id)
    R.eq(row.qty, 5, 'source field')
    R.is_nil(row[F_READ], 'computed column is not evaluated at write')
    return R.eq(row[F_WRITE], 15, 'create-only trigger is evaluated at write')
  end)
  R.it("(3) Query.records returns the stored row, without the computed column", function()
    local sp = spaces.get_space_by_name(SP)
    local res = data_r.Query.records({ }, {
      spaceId = sp.id
    }, CTX)
    R.eq(res.total, 1, 'one record')
    local row = json.decode(res.items[1].data)
    R.is_nil(row[F_READ], 'records does not evaluate the formula column')
    return R.eq(row[F_WRITE], 15, 'stored trigger value read back')
  end)
  return R.it("(3) the typed query evaluates the computed column at read", function()
    local sp = spaces.get_space_by_name(SP)
    local gname = dynamic.gql_name(SP)
    local query = "{ " .. tostring(gname) .. " { items { qty " .. tostring(F_READ) .. " " .. tostring(F_WRITE) .. " } } }"
    local res = executor.execute({
      query = query,
      context = CTX
    })
    R.nok(res.errors, json.encode(res.errors))
    local item = res.data[gname].items[1]
    R.ok(item, 'one item')
    R.eq(item[F_PLAIN], 5, 'source field')
    R.eq(item[F_READ], 10, 'computed column evaluated at read')
    return R.eq(item[F_WRITE], 15, 'stored trigger value read back')
  end)
end)
R.describe("T3b — aller-retour export / preview", function()
  R.it("(4) build_package keeps the no-trigger / trigger distinction", function()
    local m = by_key(local_package('1.1.0'))
    R.ok(m[KEY_PLAIN], 'plain field exported')
    R.is_nil(m[KEY_PLAIN].content.triggerFields, 'plain field: no triggerFields key')
    R.ok(m[KEY_READ], 'computed field exported')
    R.is_nil(m[KEY_READ].content.triggerFields, 'computed column: no triggerFields key')
    R.ok(m[KEY_WRITE], 'trigger field exported')
    R.ok((type(m[KEY_WRITE].content.triggerFields) == 'table'), 'trigger kept')
    return R.eq(#m[KEY_WRITE].content.triggerFields, 0, 'create-only trigger list is empty')
  end)
  R.it("(4) preview_update of the same package reports no create and no update", function()
    local p = local_package('1.1.0')
    local plan = apply.preview_update(p)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 0, 'create')
    R.eq(#plan.update, 0, 'update')
    R.eq(#plan.conflict, 0, 'conflict')
    return R.eq(#plan.unchanged, #p.items, 'unchanged')
  end)
  return R.it("(4) the same package survives a YAML round-trip unchanged", function()
    local raw = yaml.encode(local_package('1.1.0'))
    local p = yaml.decode(raw)
    local plan = apply.preview_update(p)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 0, 'create')
    R.eq(#plan.update, 0, 'update')
    R.eq(#plan.conflict, 0, 'conflict')
    return R.eq(#plan.unchanged, #p.items, 'unchanged')
  end)
end)
local BUILDER_STRUCT = {
  app = {
    id = 'org.test.t3bbuilder',
    name = 'T3b builder',
    version = '1.0.0',
    description = ''
  },
  spaces = {
    {
      name = SP,
      description = 't3b builder',
      fields = {
        {
          name = F_PLAIN,
          type = 'Int'
        },
        {
          name = F_READ,
          type = 'Int',
          formula = '(self.qty or 0) * 2'
        }
      }
    }
  }
}
R.describe("T3b — app_builder n'émet plus triggerFields", function()
  return R.it("field items carry no triggerFields key", function()
    local m = by_key(builder.expand(BUILDER_STRUCT))
    R.ok(m[KEY_PLAIN], 'plain field emitted')
    R.is_nil(m[KEY_PLAIN].content.triggerFields, 'plain field: no triggerFields key')
    R.ok(m[KEY_READ], 'formula field emitted')
    return R.is_nil(m[KEY_READ].content.triggerFields, 'formula field: no triggerFields key')
  end)
end)
return R.describe("T3b — cleanup", function()
  return R.it("removes the fixture", function()
    clean_app_rows(APP_ID)
    local sp = spaces.get_space_by_name(SP)
    if sp then
      spaces.delete_user_space(SP)
    end
    R.is_nil(spaces.get_space_by_name(SP))
    R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }), 0, 'no app item left')
    return R.is_nil(box.space._tdb_apps:get(APP_ID), 'no app row left')
  end)
end)
