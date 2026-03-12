local R = require('tests.runner')
local json = require('json')
local spaces_mod = require('core.spaces')
local triggers = require('core.triggers')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "test_triggers_" .. tostring(SUFFIX)
local MS_SP = "trig_moon_" .. tostring(SUFFIX)
local space_id, data_space
local insert_raw
insert_raw = function(data)
  local id = tostring(os.time()) .. math.random(1000, 9999)
  data_space:insert({
    id,
    json.encode(data)
  })
  return {
    id = id,
    data = data
  }
end
local read_data
read_data = function(id)
  local t = data_space:get(id)
  if not (t) then
    return nil
  end
  return json.decode(t[2])
end
R.describe("Triggers — setup", function()
  R.it("create test space", function()
    local sp = spaces_mod.create_user_space(SP_NAME)
    space_id = sp.id
    data_space = box.space["data_" .. tostring(SP_NAME)]
    return R.ok(data_space)
  end)
  return R.it("add base fields", function()
    spaces_mod.add_field(space_id, 'prenom', 'String')
    spaces_mod.add_field(space_id, 'nom', 'String')
    spaces_mod.add_field(space_id, 'nom_complet', 'String', false, '', '(self.prenom or "") .. " " .. (self.nom or "")', {
      'prenom',
      'nom'
    })
    spaces_mod.add_field(space_id, 'cree_le', 'String', false, '', 'os.date("%Y")', { })
    triggers.register_space_trigger(SP_NAME)
    return R.ok(data_space)
  end)
end)
R.describe("Triggers — fired on insert", function()
  R.it("full_name computed on insert", function()
    local id = 'trig_insert_1'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Jean',
        nom = 'Dupont'
      })
    })
    local d = read_data(id)
    return R.eq(d.nom_complet, 'Jean Dupont')
  end)
  R.it("empty first or last name -> partial concatenation", function()
    local id = 'trig_insert_2'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Alice',
        nom = ''
      })
    })
    local d = read_data(id)
    return R.eq(d.nom_complet, 'Alice ')
  end)
  return R.it("created_at field (creation-only) is computed on insert", function()
    local id = 'trig_insert_3'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Bob',
        nom = 'Martin'
      })
    })
    local d = read_data(id)
    R.ok(d.cree_le and d.cree_le ~= '')
    return R.matches(tostring(d.cree_le), '^%d%d%d%d$')
  end)
end)
R.describe("Triggers — fired on update", function()
  R.it("updating first name -> full_name recomputed", function()
    local id = 'trig_update_1'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Jean',
        nom = 'Dupont'
      })
    })
    local old = data_space:get(id)
    local d = json.decode(old[2])
    d.prenom = 'Pierre'
    data_space:replace({
      id,
      json.encode(d)
    })
    local d2 = read_data(id)
    return R.eq(d2.nom_complet, 'Pierre Dupont')
  end)
  R.it("updating last name -> full_name recomputed", function()
    local id = 'trig_update_2'
    data_space:insert({
      id,
      json.encode({
        prenom = 'Jean',
        nom = 'Dupont'
      })
    })
    local old = data_space:get(id)
    local d = json.decode(old[2])
    d.nom = 'Martin'
    data_space:replace({
      id,
      json.encode(d)
    })
    local d2 = read_data(id)
    return R.eq(d2.nom_complet, 'Jean Martin')
  end)
  return R.it("created_at field (creation-only) is NOT recomputed on update", function()
    local id = 'trig_update_3'
    data_space:insert({
      id,
      json.encode({
        prenom = 'X',
        nom = 'Y'
      })
    })
    local d_before = read_data(id)
    local old_val = d_before.cree_le
    local old = data_space:get(id)
    local d = json.decode(old[2])
    d.prenom = 'Z'
    data_space:replace({
      id,
      json.encode(d)
    })
    local d_after = read_data(id)
    return R.eq(d_after.cree_le, old_val)
  end)
end)
R.describe("Triggers — compile_formula", function()
  R.it("valid formula -> function", function()
    local fn_str = "return function(self, space) return self.a + self.b end"
    local ok, compiled = pcall(load, fn_str)
    R.ok(ok)
    local ok2, fn = pcall(compiled)
    R.ok(ok2)
    R.eq(type(fn), 'function')
    local proxy = {
      a = 3,
      b = 4
    }
    setmetatable(proxy, {
      __index = function(t, k)
        return rawget(t, k)
      end
    })
    return R.eq(fn(proxy, nil), 7)
  end)
  R.it("invalid formula -> Lua error", function()
    local fn_str = "return function(self, space) return self.a +++++ end"
    local fn, err = load(fn_str)
    R.nok(fn)
    return R.ok(err)
  end)
  return R.it("valid MoonScript formula -> compiled to Lua function", function()
    local ok_ms, moon = pcall(require, 'moonscript.base')
    R.ok(ok_ms, "moonscript.base should be available")
    local moon_src = "return (self, space) -> (self.a or 0) + (self.b or 0)"
    local ok_c, lua_code = pcall(moon.to_lua, moon_src)
    R.ok(ok_c, "MoonScript → Lua: " .. tostring(tostring(lua_code)))
    local ok_l, compiled = pcall(load, lua_code)
    R.ok(ok_l, "load Lua: " .. tostring(tostring(compiled)))
    local ok2, fn = pcall(compiled)
    R.ok(ok2)
    R.eq(type(fn), 'function')
    return R.eq(fn({
      a = 10,
      b = 5
    }, nil), 15)
  end)
end)
R.describe("Triggers — trigger formula MoonScript", function()
  local ms_space_id, ms_data_space
  R.it("create space with MoonScript trigger formula", function()
    local sp = spaces_mod.create_user_space(MS_SP)
    ms_space_id = sp.id
    ms_data_space = box.space["data_" .. tostring(MS_SP)]
    R.ok(ms_data_space)
    spaces_mod.add_field(ms_space_id, 'a', 'Int')
    spaces_mod.add_field(ms_space_id, 'b', 'Int')
    spaces_mod.add_field(ms_space_id, 'somme', 'Int', false, '', '(self.a or 0) + (self.b or 0)', {
      'a',
      'b'
    }, 'moonscript')
    triggers.register_space_trigger(MS_SP)
    return R.ok(ms_data_space)
  end)
  R.it("MoonScript trigger computes value on insert", function()
    local id = 'moon_insert_1'
    ms_data_space:insert({
      id,
      json.encode({
        a = 3,
        b = 7
      })
    })
    local d = json.decode((ms_data_space:get(id))[2])
    return R.eq(d.somme, 10)
  end)
  return R.it("MoonScript trigger recomputes on update", function()
    local id = 'moon_update_1'
    ms_data_space:insert({
      id,
      json.encode({
        a = 2,
        b = 4
      })
    })
    local t = ms_data_space:get(id)
    local d = json.decode(t[2])
    d.a = 10
    ms_data_space:replace({
      id,
      json.encode(d)
    })
    local d2 = json.decode((ms_data_space:get(id))[2])
    return R.eq(d2.somme, 14)
  end)
end)
R.describe("Triggers — register_space_trigger", function()
  R.it("multiple calls without error (idempotent)", function()
    local ok, err = pcall(triggers.register_space_trigger, SP_NAME)
    return R.ok(ok, "register_space_trigger should be idempotent: " .. tostring(tostring(err)))
  end)
  return R.it("non-existing space -> no error", function()
    local ok, err = pcall(triggers.register_space_trigger, 'space_that_does_not_exist')
    return R.ok(ok, "non-existing space should be handled silently: " .. tostring(tostring(err)))
  end)
end)
R.describe("Triggers — init_all_triggers", function()
  return R.it("init_all_triggers runs without error", function()
    local ok, err = pcall(triggers.init_all_triggers)
    return R.ok(ok, "init_all_triggers: " .. tostring(tostring(err)))
  end)
end)
spaces_mod.delete_user_space(SP_NAME)
return spaces_mod.delete_user_space(MS_SP)
