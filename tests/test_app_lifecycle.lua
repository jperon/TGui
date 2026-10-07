local R = require('tests.runner')
local auth = require('core.auth')
local perms = require('core.permissions')
local spaces = require('core.spaces')
local schema_r = require('resolvers.schema_resolvers')
local data_r = require('resolvers.data_resolvers')
local app_r = require('resolvers.app_resolvers')
local app_package = require('core.app_package')
local yaml = require('yaml')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local SUFFIX2 = tostring(math.random(100000, 999999))
local SP_A = "vl_a_" .. tostring(SUFFIX)
local SP_B = "vl_b_" .. tostring(SUFFIX)
local SP_LOCAL = "vl_local_" .. tostring(SUFFIX)
local GROUP = "vl_group_" .. tostring(SUFFIX)
local PLUG = "vl_plugin_" .. tostring(SUFFIX)
local APP_ID = "org.test.vl_" .. tostring(SUFFIX)
local FIELD_NOM = "field:" .. tostring(SP_A) .. ".nom"
local FIELD_NAT = "field:" .. tostring(SP_A) .. ".nationalite"
local FIELD_ORDRE = "field:" .. tostring(SP_A) .. ".ordre"
local FIELD_ISBN = "field:" .. tostring(SP_A) .. ".isbn"
local SP_D = "vl_d_" .. tostring(SUFFIX2)
local APP2 = "org.test.vl2_" .. tostring(SUFFIX2)
local FIELD_Z = "field:" .. tostring(SP_D) .. ".z"
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local ACTOR = auth.create_user("vlactor_" .. tostring(SUFFIX), "vlactor_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
local SESSION = auth.create_session(ACTOR.id)
local NONADMIN = {
  user_id = ACTOR.id,
  token = SESSION.token
}
local FIX = { }
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
find_item = function(items, key)
  for _index_0 = 1, #items do
    local it = items[_index_0]
    if it.key == key then
      return it
    end
  end
  return nil
end
local key_in_list
key_in_list = function(list, key)
  for _index_0 = 1, #list do
    local k = list[_index_0]
    if k == key then
      return true
    end
  end
  return false
end
local count_rows
count_rows = function(space_name)
  local sp = box.space["data_" .. tostring(space_name)]
  return sp and #sp:select({ }) or 0
end
local has_key
has_key = function(space_name, key)
  local sp = box.space["data_" .. tostring(space_name)]
  if not (sp) then
    return false
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local d = json.decode(t[2])
    if d[key] ~= nil then
      return true
    end
  end
  return false
end
local record_by_key
record_by_key = function(space_name, key_field, val)
  local sp = box.space["data_" .. tostring(space_name)]
  if not (sp) then
    return nil
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local d = json.decode(t[2])
    if d[key_field] ~= nil and tostring(d[key_field]) == tostring(val) then
      return d
    end
  end
  return nil
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
local app_items
app_items = function(app_id)
  return app_r.Query.appItems(nil, {
    appId = app_id
  }, CTX)
end
local installed_version
installed_version = function(app_id)
  local row = box.space._tdb_apps:get(app_id)
  return row and row[3] or nil
end
local clean_app
clean_app = function(app_id)
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
local subset_for
subset_for = function(package, marker)
  local items
  do
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = package.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.key:find(marker, 1, true) then
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
local subset
subset = function(package)
  return subset_for(package, SUFFIX)
end
local set_desc
set_desc = function(package, key, value)
  local _list_0 = package.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.key == key and type(it.content) == 'table' then
      it.content.description = value
    end
  end
  return package
end
local without
without = function(package, key)
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
    package.items = _accum_0
  end
  return package
end
local field_item
field_item = function(key, desc)
  return {
    type = 'field',
    key = key,
    content = {
      fieldType = 'String',
      notNull = false,
      description = desc,
      formula = '',
      triggerFields = { },
      language = 'lua'
    }
  }
end
local plugin_item
plugin_item = function(name)
  return {
    type = 'plugin',
    key = "plugin:" .. tostring(name),
    content = {
      name = name,
      description = 'vl plugin',
      scriptLanguage = 'coffeescript',
      templateLanguage = 'pug',
      scriptCode = "render 'x'",
      templateCode = 'div x'
    }
  }
end
local build_v11
build_v11 = function(base)
  local p = subset(base)
  p.app.version = '1.1.0'
  set_desc(p, FIELD_NOM, 'AUTHOR-NOM')
  set_desc(p, FIELD_NAT, 'AUTHOR-NAT')
  without(p, FIELD_ORDRE)
  table.insert(p.items, field_item(FIELD_ISBN, 'isbn'))
  table.insert(p.items, plugin_item(PLUG))
  return p
end
local snap
snap = function()
  return {
    spaces = #spaces.list_spaces(),
    fields = #box.space._tdb_fields:select({ }),
    rows_a = count_rows(SP_A),
    rows_b = count_rows(SP_B),
    items = #box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }),
    version = installed_version(APP_ID),
    nat = (field_by_name(SP_A, 'nationalite')).description,
    nom = (field_by_name(SP_A, 'nom')).description
  }
end
local same_snap
same_snap = function(a, b)
  R.eq(a.spaces, b.spaces, 'spaces')
  R.eq(a.fields, b.fields, 'fields')
  R.eq(a.rows_a, b.rows_a, 'rows_a')
  R.eq(a.rows_b, b.rows_b, 'rows_b')
  R.eq(a.items, b.items, 'items')
  R.eq(a.version, b.version, 'version')
  R.eq(a.nat, b.nat, 'nat')
  return R.eq(a.nom, b.nom, 'nom')
end
R.describe("v6a — préparation", function()
  R.it("creates space A with fields and four records", function()
    local a = spaces.create_user_space(SP_A, 'vl space A')
    FIX.a_id = a.id
    FIX.nom_id = (spaces.add_field(a.id, 'nom', 'String', true, 'natural key')).id
    FIX.nat_id = (spaces.add_field(a.id, 'nationalite', 'String', false, '')).id
    FIX.ordre_id = (spaces.add_field(a.id, 'ordre', 'Int', false, '')).id
    R.ok(spaces.get_space_by_name(SP_A))
    R.ok(field_by_name(SP_A, 'nom'))
    R.ok(field_by_name(SP_A, 'nationalite'))
    return R.ok(field_by_name(SP_A, 'ordre'))
  end)
  R.it("creates space B with a field and a relation to A", function()
    local b = spaces.create_user_space(SP_B, 'vl space B')
    FIX.b_id = b.id
    spaces.add_field(b.id, 'titre', 'String', false, '')
    local a_id_field = spaces.add_field(b.id, 'a_id', 'Int', false, '')
    local res = schema_r.Mutation.createRelation({ }, {
      input = {
        name = "vl_rel_" .. tostring(SUFFIX),
        fromSpaceId = b.id,
        fromFieldId = a_id_field.id,
        toSpaceId = FIX.a_id,
        toFieldId = FIX.nom_id,
        reprFormula = '@nom',
        cardinality = 'many'
      }
    }, CTX)
    FIX.rel_id = res.id
    R.ok(res)
    return R.ok(app_package.describe_local('relation', "relation:" .. tostring(SP_B) .. ".a_id"))
  end)
  return R.it("creates a group with read on A and inserts four A records", function()
    FIX.group_id = (perms.create_group(GROUP, 'vl group')).id
    perms.grant(FIX.group_id, 'space', FIX.a_id, 'read')
    local _list_0 = {
      {
        nom = 'N-1',
        nationalite = 'FR',
        ordre = 1
      },
      {
        nom = 'N-2',
        nationalite = 'FR',
        ordre = 2
      },
      {
        nom = 'N-3',
        nationalite = 'BE',
        ordre = 3
      },
      {
        nom = 'N-4',
        nationalite = 'BE',
        ordre = 4
      }
    }
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      data_r.Mutation.insertRecord({ }, {
        spaceId = FIX.a_id,
        data = row
      }, CTX)
    end
    R.eq(count_rows(SP_A), 4)
    R.eq(count_rows(SP_B), 0)
    R.ok(app_package.describe_local('group', "group:" .. tostring(GROUP)))
    return R.eq(app_package.describe_local('perm', "perm:" .. tostring(GROUP) .. "|space|" .. tostring(SP_A) .. "|read").level, 'read')
  end)
end)
R.describe("v6a — exportApp", function()
  R.it("exports a reloadable YAML package with the four seed lines", function()
    local RAW = app_r.Query.exportApp({ }, {
      meta = {
        id = APP_ID,
        name = 'VL fixture',
        version = '1.0.0',
        description = 'vl'
      },
      seed = {
        {
          space = SP_A,
          keyField = 'nom'
        }
      }
    }, CTX)
    FIX.raw = RAW
    R.eq(type(RAW), 'string')
    FIX.pkg1 = subset(yaml.decode(RAW))
    FIX.yaml1 = yaml.encode(FIX.pkg1)
    R.eq(FIX.pkg1.app.id, APP_ID)
    R.eq(FIX.pkg1.app.name, 'VL fixture')
    R.eq(FIX.pkg1.app.version, '1.0.0')
    local n_seed = 0
    local _list_0 = FIX.pkg1.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.type == 'seed' and it.content.space == SP_A then
        n_seed = n_seed + 1
      end
    end
    R.eq(n_seed, 4, 'four seed lines for A')
    R.ok(find_item(FIX.pkg1.items, "seed:" .. tostring(SP_A) .. "|N-1"))
    R.ok(find_item(FIX.pkg1.items, "seed:" .. tostring(SP_A) .. "|N-4"))
    return R.is_nil(find_item(FIX.pkg1.items, 'group:admin'), 'admin group never delivered')
  end)
  return R.it("carries no local identifier nor date in the raw YAML", function()
    R.nok((FIX.raw:find(FIX.a_id, 1, true)), 'no space id')
    R.nok((FIX.raw:find(FIX.nom_id, 1, true)), 'no field id')
    R.nok((FIX.raw:find(FIX.rel_id, 1, true)), 'no relation id')
    R.nok((FIX.raw:find(FIX.group_id, 1, true)), 'no group id')
    return R.nok((FIX.raw:match('%d%d%d%d%d%d%d%d%d%d')), 'no epoch timestamp')
  end)
end)
R.describe("v6a — aperçu identique", function()
  return R.it("reports everything unchanged and writes nothing", function()
    local before = snap()
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = FIX.yaml1
    }, CTX)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 0, 'create')
    R.eq(#plan.update, 0, 'update')
    R.eq(#plan.conflict, 0, 'conflict')
    R.eq(#plan.obsolete, 0, 'obsolete')
    R.eq(#plan.keepLocal, 0, 'keepLocal')
    R.eq(#plan.unchanged, #FIX.pkg1.items, 'unchanged')
    return same_snap(before, snap())
  end)
end)
R.describe("v6a — installation", function()
  return R.it("installs the app and tracks every item as active", function()
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = FIX.yaml1
    }, CTX)
    R.ok(report.ok, report.error)
    local apps = app_r.Query.listApps(nil, { }, CTX)
    local found = nil
    for _index_0 = 1, #apps do
      local a = apps[_index_0]
      if a.appId == APP_ID then
        found = a
      end
    end
    R.ok(found, 'installed app listed')
    R.eq(found.version, '1.0.0')
    R.eq(found.activeCount, #FIX.pkg1.items)
    R.eq(found.obsoleteCount, 0)
    local items = app_items(APP_ID)
    R.eq(#items, #FIX.pkg1.items)
    for _index_0 = 1, #items do
      local it = items[_index_0]
      R.eq(it.state, 'actif', "state of " .. tostring(it.key))
    end
    return R.eq(count_rows(SP_A), 4, 'seed records kept')
  end)
end)
R.describe("v6a — modifications locales", function()
  R.it("changes nationalite (local), space B description and adds a local space", function()
    spaces.update_field((field_by_name(SP_A, 'nationalite')).id, {
      description = 'LOCAL-NAT'
    })
    box.space._tdb_spaces:update(FIX.b_id, {
      {
        '=',
        3,
        'LOCAL-B'
      }
    })
    spaces.create_user_space(SP_LOCAL, 'vl local outside package')
    R.eq((field_by_name(SP_A, 'nationalite')).description, 'LOCAL-NAT')
    R.eq((spaces.get_space_by_name(SP_B)).description, 'LOCAL-B')
    return R.ok(spaces.get_space_by_name(SP_LOCAL))
  end)
  return R.it("adds one local record to A (the +1 to preserve)", function()
    data_r.Mutation.insertRecord({ }, {
      spaceId = FIX.a_id,
      data = {
        nom = 'LOCAL-EXTRA',
        nationalite = 'FR'
      }
    }, CTX)
    FIX.rows_a_before = count_rows(SP_A)
    FIX.rows_b_before = count_rows(SP_B)
    R.eq(FIX.rows_a_before, 5)
    return R.ok(record_by_key(SP_A, 'nom', 'LOCAL-EXTRA'))
  end)
end)
R.describe("v6a — paquet v1.1.0 (auteur)", function()
  R.it("builds v1.1.0 from the exported items (adds isbn and a plugin)", function()
    FIX.pkg2 = build_v11(FIX.pkg1)
    FIX.yaml2 = yaml.encode(FIX.pkg2)
    R.eq(FIX.pkg2.app.version, '1.1.0')
    R.eq((find_item(FIX.pkg2.items, FIELD_NOM)).content.description, 'AUTHOR-NOM')
    R.eq((find_item(FIX.pkg2.items, FIELD_NAT)).content.description, 'AUTHOR-NAT')
    R.is_nil(find_item(FIX.pkg2.items, FIELD_ORDRE))
    R.ok(find_item(FIX.pkg2.items, FIELD_ISBN))
    return R.ok(find_item(FIX.pkg2.items, "plugin:" .. tostring(PLUG)))
  end)
  return R.it("previews created/updated/conflict/kept/obsolete exactly", function()
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = FIX.yaml2
    }, CTX)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 2, 'create')
    R.eq(#plan.update, 1, 'update')
    R.eq(#plan.conflict, 1, 'conflict')
    R.eq(#plan.keepLocal, 1, 'keepLocal')
    R.eq(#plan.obsolete, 1, 'obsolete')
    R.ok(find_item(plan.create, FIELD_ISBN), 'isbn created')
    R.ok(find_item(plan.create, "plugin:" .. tostring(PLUG)), 'plugin created')
    R.ok((find_item(plan.update, FIELD_NOM)), 'nom updated')
    R.eq(plan.conflict[1].key, FIELD_NAT)
    R.eq(plan.conflict[1]["local"].description, 'LOCAL-NAT')
    R.eq(plan.conflict[1].delivered.description, 'AUTHOR-NAT')
    R.ok(find_item(plan.keepLocal, "space:" .. tostring(SP_B)), 'space B kept')
    R.eq(plan.obsolete[1], FIELD_ORDRE)
    return R.ok((find_item(plan.create, "plugin:" .. tostring(PLUG))).isCode, 'plugin flagged as code')
  end)
end)
R.describe("v6a — refus sans décision", function()
  return R.it("refuses the conflict and writes nothing", function()
    local before = snap()
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = FIX.yaml2
    }, CTX)
    R.nok(report.ok)
    R.matches(report.error, 'decision')
    return same_snap(before, snap())
  end)
end)
R.describe("v6a — décision locale", function()
  return R.it("keeps the local value, applies the author changes and tracks obsolete", function()
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = FIX.yaml2,
      decisions = {
        {
          key = FIELD_NAT,
          choice = 'local'
        }
      }
    }, CTX)
    R.ok(report.ok, report.error)
    R.ok(key_in_list(report.created, FIELD_ISBN), 'isbn created')
    R.ok(key_in_list(report.created, "plugin:" .. tostring(PLUG)), 'plugin created')
    R.ok(key_in_list(report.updated, FIELD_NOM), 'nom updated')
    R.ok(key_in_list(report.kept, "space:" .. tostring(SP_B)), 'space B kept')
    R.eq((field_by_name(SP_A, 'nationalite')).description, 'LOCAL-NAT', 'local kept')
    R.eq((field_by_name(SP_A, 'nom')).description, 'AUTHOR-NOM', 'author applied')
    R.ok(field_by_name(SP_A, 'isbn'))
    R.ok(app_package.describe_local('plugin', "plugin:" .. tostring(PLUG)))
    R.ok(spaces.get_space_by_name(SP_LOCAL, 'local space intact'))
    R.ok(record_by_key(SP_A, 'nom', 'LOCAL-EXTRA'), 'local record intact')
    R.ok(field_by_name(SP_A, 'ordre'), 'obsolete field never deleted')
    R.eq(count_rows(SP_A), FIX.rows_a_before, 'A record count preserved')
    R.eq(count_rows(SP_B), FIX.rows_b_before, 'B record count preserved')
    local items = app_items(APP_ID)
    local ordre_state = nil
    for _index_0 = 1, #items do
      local it = items[_index_0]
      if it.key == FIELD_ORDRE then
        ordre_state = it.state
      end
    end
    return R.eq(ordre_state, 'obsolète', 'ordre tracked obsolete')
  end)
end)
R.describe("v6a — réinstallation identique", function()
  return R.it("reinstalls an identical v1.1.0 once nationalite matches the delivered value", function()
    spaces.update_field((field_by_name(SP_A, 'nationalite')).id, {
      description = 'AUTHOR-NAT'
    })
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = FIX.yaml2
    }, CTX)
    R.eq(#plan.errors, 0, json.encode(plan.errors))
    R.eq(#plan.create, 0, 'create')
    R.eq(#plan.update, 0, 'update')
    R.eq(#plan.conflict, 0, 'conflict')
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = FIX.yaml2
    }, CTX)
    R.ok(report.ok, report.error)
    R.eq((field_by_name(SP_A, 'nom')).description, 'AUTHOR-NOM')
    R.eq((field_by_name(SP_A, 'nationalite')).description, 'AUTHOR-NAT')
    return R.eq(installed_version(APP_ID), '1.1.0')
  end)
end)
R.describe("v6a — décision delivered (second cycle)", function()
  R.it("installs a second fixture v1.0.0", function()
    local d = spaces.create_user_space(SP_D, 'vl second')
    FIX.d_id = d.id
    spaces.add_field(d.id, 'z', 'String', false, 'D0')
    local y2 = app_r.Query.exportApp({ }, {
      meta = {
        id = APP2,
        name = 'VL2 fixture',
        version = '1.0.0',
        description = 'vl2'
      }
    }, CTX)
    FIX.pkg_d = subset_for(yaml.decode(y2), SUFFIX2)
    FIX.yaml_d1 = yaml.encode(FIX.pkg_d)
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = FIX.yaml_d1
    }, CTX)
    R.ok(report.ok, report.error)
    R.eq((field_by_name(SP_D, 'z')).description, 'D0')
    return R.ok(app_package.describe_local('space', "space:" .. tostring(SP_D)))
  end)
  return R.it("resolves a new conflict with 'delivered' and applies the author value", function()
    spaces.update_field((field_by_name(SP_D, 'z')).id, {
      description = 'LOCAL-Z'
    })
    local p = yaml.decode(FIX.yaml_d1)
    set_desc(p, FIELD_Z, 'AUTHOR-Z')
    p.app.version = '1.1.0'
    local y2b = yaml.encode(p)
    local plan = app_r.Query.previewAppUpdate(nil, {
      yaml = y2b
    }, CTX)
    R.eq(#plan.conflict, 1, 'conflict')
    R.eq(plan.conflict[1].key, FIELD_Z)
    R.eq(plan.conflict[1]["local"].description, 'LOCAL-Z')
    R.eq(plan.conflict[1].delivered.description, 'AUTHOR-Z')
    local report = app_r.Mutation.applyAppUpdate(nil, {
      yaml = y2b,
      decisions = {
        {
          key = FIELD_Z,
          choice = 'delivered'
        }
      }
    }, CTX)
    R.ok(report.ok, report.error)
    return R.eq((field_by_name(SP_D, 'z')).description, 'AUTHOR-Z', 'delivered applied')
  end)
end)
R.describe("v6a — purge", function()
  R.it("previews the obsolete ordre losses exactly and writes nothing", function()
    local before = snap()
    FIX.rows_a_before_purge = count_rows(SP_A)
    local preview = app_r.Query.previewAppPurge(nil, {
      appId = APP_ID,
      keys = {
        FIELD_ORDRE
      }
    }, CTX)
    R.eq(#preview.losses, 1)
    R.eq(preview.losses[1].key, FIELD_ORDRE)
    R.eq(preview.losses[1].type, 'field')
    R.eq(preview.losses[1].records, 4, 'four records carry ordre')
    R.eq(preview.totalRecords, 4)
    R.ok(field_by_name(SP_A, 'ordre'), 'preview wrote nothing')
    return same_snap(before, snap())
  end)
  R.it("refuses without confirmation, then purges the obsolete field", function()
    local r0 = app_r.Mutation.purgeAppObsolete(nil, {
      appId = APP_ID,
      keys = {
        FIELD_ORDRE
      },
      confirmed = false
    }, CTX)
    R.nok(r0.ok)
    R.matches(r0.error, 'confirmation')
    R.ok(field_by_name(SP_A, 'ordre'), 'not purged without confirmation')
    local r = app_r.Mutation.purgeAppObsolete(nil, {
      appId = APP_ID,
      keys = {
        FIELD_ORDRE
      },
      confirmed = true
    }, CTX)
    R.ok(r.ok, r.error)
    R.is_nil(field_by_name(SP_A, 'ordre'), 'field removed')
    R.is_nil(item_row(APP_ID, FIELD_ORDRE), 'tracking removed')
    R.eq(count_rows(SP_A), FIX.rows_a_before_purge, 'record count unchanged')
    R.nok(has_key(SP_A, 'ordre'), 'ordre key removed from every record')
    R.ok(field_by_name(SP_A, 'nom'), 'other fields untouched')
    R.ok(field_by_name(SP_A, 'nationalite'))
    R.ok(field_by_name(SP_A, 'isbn'))
    local items = app_items(APP_ID)
    local has_obsolete = false
    for _index_0 = 1, #items do
      local it = items[_index_0]
      if it.state == 'obsolète' then
        has_obsolete = true
      end
    end
    return R.nok(has_obsolete, 'no obsolete item left')
  end)
  return R.it("refuses to purge an active or unknown item", function()
    local r = app_r.Mutation.purgeAppObsolete(nil, {
      appId = APP_ID,
      keys = {
        FIELD_NOM
      },
      confirmed = true
    }, CTX)
    R.nok(r.ok)
    R.matches(r.error, 'not obsolete')
    R.raises((function()
      return app_r.Query.previewAppPurge(nil, {
        appId = APP_ID,
        keys = {
          FIELD_NOM
        }
      }, CTX)
    end), 'not obsolete')
    R.raises((function()
      return app_r.Query.previewAppPurge(nil, {
        appId = APP_ID,
        keys = {
          "field:" .. tostring(SP_A) .. ".nope"
        }
      }, CTX)
    end), 'unknown app item')
    return R.ok(field_by_name(SP_A, 'nom'), 'active field untouched')
  end)
end)
R.describe("v6a — droits", function()
  return R.it("a non-admin user receives Forbidden on every operation", function()
    R.raises((function()
      return app_r.Query.listApps(nil, { }, NONADMIN)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.appItems(nil, {
        appId = APP_ID
      }, NONADMIN)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.exportApp(nil, {
        meta = {
          id = APP_ID,
          name = 'x',
          version = '1.0.0'
        },
        seed = { }
      }, NONADMIN)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.previewAppUpdate(nil, {
        yaml = FIX.yaml1
      }, NONADMIN)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Query.previewAppPurge(nil, {
        appId = APP_ID,
        keys = { }
      }, NONADMIN)
    end), 'Forbidden')
    R.raises((function()
      return app_r.Mutation.applyAppUpdate(nil, {
        yaml = FIX.yaml1
      }, NONADMIN)
    end), 'Forbidden')
    return R.raises((function()
      return app_r.Mutation.purgeAppObsolete(nil, {
        appId = APP_ID,
        keys = { },
        confirmed = true
      }, NONADMIN)
    end), 'Forbidden')
  end)
end)
R.describe("v6a — downgrade", function()
  return R.it("refuses v0.9.0 without allowDowngrade and accepts it with the flag", function()
    local p = yaml.decode(FIX.yaml2)
    p.app.version = '0.9.0'
    local y09 = yaml.encode(p)
    local r = app_r.Mutation.applyAppUpdate(nil, {
      yaml = y09
    }, CTX)
    R.nok(r.ok)
    R.matches(r.error, 'downgrade')
    R.eq(installed_version(APP_ID), '1.1.0', 'version unchanged')
    local r2 = app_r.Mutation.applyAppUpdate(nil, {
      yaml = y09,
      allowDowngrade = true
    }, CTX)
    R.ok(r2.ok, r2.error)
    return R.eq(installed_version(APP_ID), '0.9.0', 'downgrade applied')
  end)
end)
return R.describe("v6a — nettoyage", function()
  return R.it("removes every fixture element and tracking row", function()
    local _list_0 = {
      SP_A,
      SP_B,
      SP_LOCAL,
      SP_D
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
    local _list_1 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_1 do
      local wp = _list_1[_index_0]
      if wp[2] == PLUG then
        box.space._tdb_widget_plugins:delete(wp[1])
      end
    end
    local _list_2 = perms.list_groups()
    for _index_0 = 1, #_list_2 do
      local g = _list_2[_index_0]
      if g.name == GROUP then
        perms.delete_group(g.id)
      end
    end
    clean_app(APP_ID)
    clean_app(APP2)
    spaces.delete_user_space(SP_A)
    spaces.delete_user_space(SP_B)
    spaces.delete_user_space(SP_LOCAL)
    spaces.delete_user_space(SP_D)
    auth.delete_session(SESSION.token)
    box.space._tdb_users:delete(ACTOR.id)
    R.is_nil(spaces.get_space_by_name(SP_A))
    R.is_nil(spaces.get_space_by_name(SP_D))
    R.is_nil(app_package.describe_local('space', "space:" .. tostring(SP_A)))
    R.is_nil(box.space._tdb_apps:get(APP_ID))
    return R.is_nil(box.space._tdb_apps:get(APP2))
  end)
end)
