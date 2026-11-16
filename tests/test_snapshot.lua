local R = require('tests.runner')
local auth = require('core.auth')
local spaces = require('core.spaces')
local view_presets = require('core.view_presets')
local export_r = require('resolvers.export_resolvers')
local data_res = require('resolvers.data_resolvers')
local yaml = require('yaml')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local admin_user = auth.get_user_by_username('admin')
local ADMIN_CTX = {
  user_id = admin_user and admin_user.id
}
R.describe("exportSnapshot — structure", function()
  R.it("returns a non-empty YAML string", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    R.ok(result)
    return R.ok(#result > 10)
  end)
  R.it("le YAML est parsable", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    R.ok(snap)
    return R.ok(snap.version)
  end)
  R.it("contient une section schema.spaces", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    R.ok(snap.schema)
    R.ok(snap.schema.spaces)
    return R.ok(#snap.schema.spaces >= 0)
  end)
  R.it("ne contient pas de section data en mode structure-seulement", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    return R.eq(snap.data, nil)
  end)
  R.it("contient une section data en mode include_data", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = true
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    R.ok(result)
    R.ok(type(snap.data) == 'table')
    local expected_count = #spaces.list_spaces()
    local exported_count = 0
    for _k, _v in pairs(snap.data) do
      exported_count = exported_count + 1
    end
    return R.eq(exported_count, expected_count)
  end)
  return R.it("contient une section schema.widget_plugins", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    R.ok(snap.schema)
    return R.ok(type(snap.schema.widget_plugins) == 'table')
  end)
end)
R.describe("diffSnapshot — no difference", function()
  local current_yaml
  R.it("exports current schema", function()
    current_yaml = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    return R.ok(current_yaml)
  end)
  return R.it("diff on current schema -> no divergence", function()
    local diff = export_r.Query.diffSnapshot(nil, {
      yaml = current_yaml
    }, ADMIN_CTX)
    R.ok(diff)
    R.eq(#diff.spacesToCreate, 0)
    R.eq(#diff.spacesToDelete, 0)
    R.eq(#diff.fieldsToCreate, 0)
    return R.eq(#diff.fieldsToDelete, 0)
  end)
end)
R.describe("importSnapshot — mode merge", function()
  local SP = "snap_test_" .. tostring(SUFFIX)
  R.it("creates a minimal YAML snapshot with a new space", function()
    local snap = {
      version = "1",
      schema = {
        spaces = {
          {
            name = SP,
            fields = {
              {
                name = "titre",
                fieldType = "String",
                notNull = false
              },
              {
                name = "valeur",
                fieldType = "Int",
                notNull = false
              }
            },
            views = { }
          }
        },
        relations = { },
        custom_views = { },
        groups = { }
      }
    }
    local snap_yaml = yaml.encode(snap)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok)
    R.ok(result.created > 0)
    return R.eq(#result.errors, 0)
  end)
  R.it("imported space is visible in list_spaces", function()
    local found = false
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      if sp.name == SP then
        found = true
        break
      end
    end
    return R.ok(found)
  end)
  R.it("imported fields are present", function()
    local sp = nil
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP then
        sp = s
      end
    end
    R.ok(sp)
    local fields = spaces.list_fields(sp.id)
    local names
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #fields do
        local f = fields[_index_0]
        _accum_0[_len_0] = f.name
        _len_0 = _len_0 + 1
      end
      names = _accum_0
    end
    local has_titre = false
    local has_valeur = false
    for _index_0 = 1, #names do
      local n = names[_index_0]
      if n == 'titre' then
        has_titre = true
      end
      if n == 'valeur' then
        has_valeur = true
      end
    end
    R.ok(has_titre)
    return R.ok(has_valeur)
  end)
  R.it("second identical import -> all skipped, no error", function()
    local snap = {
      version = "1",
      schema = {
        spaces = {
          {
            name = SP,
            fields = {
              {
                name = "titre",
                fieldType = "String",
                notNull = false
              },
              {
                name = "valeur",
                fieldType = "Int",
                notNull = false
              }
            },
            views = { }
          }
        },
        relations = { },
        custom_views = { },
        groups = { }
      }
    }
    local snap_yaml = yaml.encode(snap)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok)
    R.eq(result.created, 0)
    R.ok(result.skipped > 0)
    return R.eq(#result.errors, 0)
  end)
  return R.it("delete test space", function()
    local sp = nil
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP then
        sp = s
      end
    end
    R.ok(sp)
    spaces.delete_user_space(SP)
    local found = false
    local _list_1 = spaces.list_spaces()
    for _index_0 = 1, #_list_1 do
      local s = _list_1[_index_0]
      if s.name == SP then
        found = true
      end
    end
    return R.eq(found, false)
  end)
end)
R.describe("importSnapshot — widget plugins", function()
  local PLUGIN = "snap_plugin_" .. tostring(SUFFIX)
  R.it("imports widget plugin definitions from snapshot schema", function()
    local snap = {
      version = "1",
      schema = {
        spaces = { },
        relations = { },
        custom_views = { },
        widget_plugins = {
          {
            name = PLUGIN,
            description = "plugin from snapshot",
            scriptLanguage = "coffeescript",
            templateLanguage = "pug",
            scriptCode = "module.exports = ({ render }) -> render '<div>ok</div>'",
            templateCode = "div ok"
          }
        },
        groups = { }
      }
    }
    local snap_yaml = yaml.encode(snap)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok)
    local tuple = box.space._tdb_widget_plugins.index.by_scope_name:get({
      '',
      PLUGIN
    })
    return R.ok(tuple)
  end)
  return R.it("cleanup imported widget plugin", function()
    local tuple = box.space._tdb_widget_plugins.index.by_scope_name:get({
      '',
      PLUGIN
    })
    if tuple then
      return box.space._tdb_widget_plugins:delete(tuple[1])
    end
  end)
end)
R.describe("snapshot — view presets", function()
  local SP_P = "snap_preset_" .. tostring(SUFFIX)
  local PAGE_P = "snap_preset_page_" .. tostring(SUFFIX)
  local PAGE_ID = "snap_preset_page_id_" .. tostring(SUFFIX)
  local PRESET_P = "snap:preset_" .. tostring(SUFFIX)
  local WIDGET_P = 'w_0000e1'
  R.it("exports presets with a portable scope and space name", function()
    local sp = spaces.create_user_space(SP_P, 'presets')
    R.ok(sp)
    box.space._tdb_custom_views:insert({
      PAGE_ID,
      PAGE_P,
      '',
      'layout: {}',
      os.time(),
      os.time()
    })
    view_presets.save_preset("widget:" .. tostring(PAGE_ID) .. ":" .. tostring(WIDGET_P), sp.id, PRESET_P, 'self.a > 1', '[{"column":"a","ascending":true}]')
    local snap = yaml.decode(export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX))
    R.ok(type(snap.schema.view_presets) == 'table')
    local found = nil
    local _list_0 = snap.schema.view_presets
    for _index_0 = 1, #_list_0 do
      local vp = _list_0[_index_0]
      if vp.name == PRESET_P then
        found = vp
      end
    end
    R.ok(found, 'preset exported')
    R.eq(found.scope, "widget:" .. tostring(PAGE_P) .. ":" .. tostring(WIDGET_P))
    R.eq(found.space, SP_P)
    R.eq(found.filter, 'self.a > 1')
    R.eq(found.sort, '[{"column":"a","ascending":true}]')
    R.is_nil(found.scope:find(PAGE_ID, 1, true), 'no local page id in the scope')
    return R.is_nil(found.space:find(sp.id, 1, true), 'no local space id in the space')
  end)
  R.it("re-importing the same snapshot skips the existing preset", function()
    local snap_yaml = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok, table.concat(result.errors, '; '))
    local n = 0
    local _list_0 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_0 do
      local vp = _list_0[_index_0]
      if vp[4] == PRESET_P then
        n = n + 1
      end
    end
    return R.eq(n, 1, 'one preset row, not a duplicate')
  end)
  R.it("recreates the preset from the snapshot on a cleaned base", function()
    local snap_yaml = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local _list_0 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_0 do
      local vp = _list_0[_index_0]
      if vp[4] == PRESET_P then
        view_presets.delete_preset(vp[1])
      end
    end
    box.space._tdb_custom_views:delete(PAGE_ID)
    spaces.delete_user_space(SP_P)
    R.is_nil(spaces.get_space_by_name(SP_P))
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok, table.concat(result.errors, '; '))
    local new_sp = spaces.get_space_by_name(SP_P)
    local new_page = box.space._tdb_custom_views.index.by_name:get(PAGE_P)
    R.ok(new_sp, 'space recreated')
    R.ok(new_page, 'page recreated')
    local row = box.space._tdb_view_presets.index.by_scope_name:get({
      "widget:" .. tostring(new_page[1]) .. ":" .. tostring(WIDGET_P),
      PRESET_P
    })
    R.ok(row, 'preset recreated')
    R.eq(row[3], new_sp.id, 'attached to the recreated space')
    R.eq(row[5], 'self.a > 1')
    return R.eq(json.decode(row[6])[1].column, 'a')
  end)
  return R.it("cleanup the preset fixture", function()
    local _list_0 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_0 do
      local vp = _list_0[_index_0]
      if vp[4] == PRESET_P then
        view_presets.delete_preset(vp[1])
      end
    end
    local page = box.space._tdb_custom_views.index.by_name:get(PAGE_P)
    if page then
      box.space._tdb_custom_views:delete(page[1])
    end
    spaces.delete_user_space(SP_P)
    R.is_nil(spaces.get_space_by_name(SP_P))
    local n = 0
    local _list_1 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_1 do
      local vp = _list_1[_index_0]
      if vp[4] == PRESET_P then
        n = n + 1
      end
    end
    return R.eq(n, 0)
  end)
end)
R.describe("importSnapshot — mode replace", function()
  local SP_A = "replace_a_" .. tostring(SUFFIX)
  local SP_B = "replace_b_" .. tostring(SUFFIX)
  R.it("creates two initial spaces", function()
    local _list_0 = {
      SP_A,
      SP_B
    }
    for _index_0 = 1, #_list_0 do
      local name = _list_0[_index_0]
      local ok, err = pcall(function()
        return spaces.create_user_space(name, '')
      end)
      R.ok(ok)
    end
  end)
  R.it("replace mode removes existing spaces and recreates from snapshot", function()
    local snap = {
      version = "1",
      schema = {
        spaces = {
          {
            name = SP_B,
            fields = {
              {
                name = "val",
                fieldType = "String",
                notNull = false
              }
            },
            views = { }
          }
        },
        relations = { },
        custom_views = { },
        groups = { }
      }
    }
    local snap_yaml = yaml.encode(snap)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'replace'
    }, ADMIN_CTX)
    R.ok(result)
    return R.eq(#result.errors, 0)
  end)
  R.it("SP_B still exists (recreated by replace)", function()
    local found = false
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP_B then
        found = true
      end
    end
    return R.ok(found)
  end)
  R.it("SP_B has imported val field", function()
    local sp = nil
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP_B then
        sp = s
      end
    end
    R.ok(sp)
    local fields = spaces.list_fields(sp.id)
    local has_val = false
    for _index_0 = 1, #fields do
      local f = fields[_index_0]
      if f.name == 'val' then
        has_val = true
      end
    end
    return R.ok(has_val)
  end)
  return R.it("cleanup replace_* spaces", function()
    local _list_0 = {
      SP_A,
      SP_B
    }
    for _index_0 = 1, #_list_0 do
      local name = _list_0[_index_0]
      local sp = nil
      local _list_1 = spaces.list_spaces()
      for _index_1 = 1, #_list_1 do
        local s = _list_1[_index_1]
        if s.name == name then
          sp = s
        end
      end
      if sp then
        spaces.delete_user_space(name)
      end
    end
    local found = false
    local _list_1 = spaces.list_spaces()
    for _index_0 = 1, #_list_1 do
      local s = _list_1[_index_0]
      if s.name == SP_A or s.name == SP_B then
        found = true
      end
    end
    return R.eq(found, false)
  end)
end)
R.describe("importSnapshot — invalid YAML", function()
  R.it("error on empty YAML", function()
    local ok, err = pcall(function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = '',
        mode = 'merge'
      }, ADMIN_CTX)
    end)
    return R.eq(ok, false)
  end)
  return R.it("import with non-table YAML -> error", function()
    local ok, err = pcall(function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = '42',
        mode = 'merge'
      }, ADMIN_CTX)
    end)
    return R.eq(ok, false)
  end)
end)
return R.describe("round trip export → import (includeData)", function()
  local RT = "snap_rt_" .. tostring(SUFFIX)
  local RT_FIELDS = {
    {
      name = 'titre',
      fieldType = 'String',
      notNull = true
    },
    {
      name = 'valeur',
      fieldType = 'Int',
      notNull = false
    },
    {
      name = 'prix',
      fieldType = 'Float',
      notNull = false
    },
    {
      name = 'actif',
      fieldType = 'Boolean',
      notNull = false
    }
  }
  local ORIG_ROWS = {
    {
      titre = 'Alpha',
      valeur = 1,
      prix = 1.5,
      actif = true
    },
    {
      titre = 'Beta',
      valeur = 2,
      prix = 2.25,
      actif = false
    },
    {
      titre = 'Gamma',
      valeur = 3,
      prix = 3,
      actif = true
    }
  }
  local rt_id = nil
  local rt_yaml = nil
  local read_rows
  read_rows = function()
    local user_sp = box.space["data_" .. tostring(RT)]
    if not (user_sp) then
      return { }
    end
    local rows = { }
    local _list_0 = user_sp:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      table.insert(rows, json.decode(t[2]))
    end
    return rows
  end
  local canonical_rows
  canonical_rows = function(rows)
    local parts = { }
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      local keys
      do
        local _accum_0 = { }
        local _len_0 = 1
        for k, _ in pairs(r) do
          _accum_0[_len_0] = k
          _len_0 = _len_0 + 1
        end
        keys = _accum_0
      end
      table.sort(keys)
      local kv = { }
      for _index_1 = 1, #keys do
        local k = keys[_index_1]
        table.insert(kv, tostring(k) .. "=" .. tostring(json.encode(r[k])))
      end
      table.insert(parts, "{" .. tostring(table.concat(kv, ' ')) .. "}")
    end
    table.sort(parts)
    return parts
  end
  local assert_same_rows
  assert_same_rows = function(actual, expected, label)
    local got = canonical_rows(actual)
    local exp = canonical_rows(expected)
    R.eq(#got, #exp, tostring(label) .. ": row count")
    local n = math.min(#got, #exp)
    for i = 1, n do
      R.eq(got[i], exp[i], tostring(label) .. ": row " .. tostring(i))
    end
  end
  R.it("creates the test space with several field types", function()
    local ok, sp = pcall(spaces.create_user_space, RT, 'round trip space')
    R.ok(ok, tostring(sp))
    rt_id = sp.id
    for _index_0 = 1, #RT_FIELDS do
      local f = RT_FIELDS[_index_0]
      local ok2, err2 = pcall(spaces.add_field, rt_id, f.name, f.fieldType, f.notNull)
      R.ok(ok2, "add_field " .. tostring(f.name) .. ": " .. tostring(err2))
    end
    local fields = spaces.list_fields(rt_id)
    return R.eq(#fields, #RT_FIELDS)
  end)
  R.it("inserts the original records", function()
    for _index_0 = 1, #ORIG_ROWS do
      local r = ORIG_ROWS[_index_0]
      local rec = data_res.Mutation.insertRecord({ }, {
        spaceId = rt_id,
        data = r
      }, ADMIN_CTX)
      R.ok(rec, "insert " .. tostring(r.titre))
    end
    return R.eq(#read_rows(), #ORIG_ROWS)
  end)
  R.it("exports the space together with its data", function()
    local yaml_str = export_r.Query.exportSnapshot(nil, {
      includeData = true
    }, ADMIN_CTX)
    R.ok(yaml_str)
    local snap = yaml.decode(yaml_str)
    R.ok(snap)
    R.ok(snap.data)
    R.ok(snap.data[RT], "data section for " .. tostring(RT))
    R.eq(#snap.data[RT], #ORIG_ROWS)
    rt_yaml = yaml_str
  end)
  R.it("exported rows hold the decoded field values", function()
    local snap = yaml.decode(rt_yaml)
    return assert_same_rows(snap.data[RT] or { }, ORIG_ROWS, 'exported data')
  end)
  R.it("deletes the test space", function()
    spaces.delete_user_space(RT)
    R.eq(#read_rows(), 0)
    local found = false
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == RT then
        found = true
      end
    end
    return R.eq(found, false)
  end)
  R.it("reimports the snapshot in merge mode", function()
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = rt_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok, table.concat(result.errors or { }, ' | '))
    return R.eq(#read_rows(), #ORIG_ROWS)
  end)
  R.it("reimported records match the originals", function()
    return assert_same_rows(read_rows(), ORIG_ROWS, 'restored data')
  end)
  return R.it("deletes the reimported test space", function()
    spaces.delete_user_space(RT)
    local found = false
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == RT then
        found = true
      end
    end
    return R.eq(found, false)
  end)
end)
