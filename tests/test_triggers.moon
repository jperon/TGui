-- tests/test_triggers.moon
-- Tests trigger formulas (core/triggers.moon).
-- Requires Tarantool (box already initialized in run.moon).

R = require 'tests.runner'
json        = require 'json'
spaces_mod  = require 'core.spaces'
triggers    = require 'core.triggers'

-- Isolated space for these tests
SUFFIX  = tostring(math.random 100000, 999999)
SP_NAME = "test_triggers_#{SUFFIX}"
MS_SP   = "trig_moon_#{SUFFIX}"

local space_id, data_space

-- Helper: insert a tuple directly
insert_raw = (data) ->
  id = tostring(os.time!) .. math.random(1000, 9999)
  data_space\insert { id, json.encode data }
  { id: id, data: data }

-- Helper: read tuple data
read_data = (id) ->
  t = data_space\get id
  return nil unless t
  json.decode t[2]

R.describe "Triggers — setup", ->
  R.it "create test space", ->
    sp = spaces_mod.create_user_space SP_NAME
    space_id = sp.id
    data_space = box.space["data_#{SP_NAME}"]
    R.ok data_space

  R.it "add base fields", ->
    spaces_mod.add_field space_id, 'prenom', 'String'
    spaces_mod.add_field space_id, 'nom',    'String'
    -- Trigger formula: triggered on any first/last name change
    spaces_mod.add_field space_id, 'nom_complet', 'String', false, '',
      '(self.prenom or "") .. " " .. (self.nom or "")',
      {'prenom', 'nom'}
    -- Trigger formula: creation only
    spaces_mod.add_field space_id, 'cree_le', 'String', false, '',
      'os.date("%Y")',
      {}
    triggers.register_space_trigger SP_NAME
    R.ok data_space  -- trigger registered without error

R.describe "Triggers — fired on insert", ->
  R.it "full_name computed on insert", ->
    id = 'trig_insert_1'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    d = read_data id
    R.eq d.nom_complet, 'Jean Dupont'

  R.it "empty first or last name -> partial concatenation", ->
    id = 'trig_insert_2'
    data_space\insert { id, json.encode { prenom: 'Alice', nom: '' } }
    d = read_data id
    R.eq d.nom_complet, 'Alice '

  R.it "created_at field (creation-only) is computed on insert", ->
    id = 'trig_insert_3'
    data_space\insert { id, json.encode { prenom: 'Bob', nom: 'Martin' } }
    d = read_data id
    R.ok d.cree_le and d.cree_le != ''
    -- should be a year (4 digits)
    R.matches tostring(d.cree_le), '^%d%d%d%d$'

R.describe "Triggers — fired on update", ->
  R.it "updating first name -> full_name recomputed", ->
    id = 'trig_update_1'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    -- Change first name
    old = data_space\get id
    d = json.decode old[2]
    d.prenom = 'Pierre'
    data_space\replace { id, json.encode d }
    d2 = read_data id
    R.eq d2.nom_complet, 'Pierre Dupont'

  R.it "updating last name -> full_name recomputed", ->
    id = 'trig_update_2'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    old = data_space\get id
    d = json.decode old[2]
    d.nom = 'Martin'
    data_space\replace { id, json.encode d }
    d2 = read_data id
    R.eq d2.nom_complet, 'Jean Martin'

  R.it "created_at field (creation-only) is NOT recomputed on update", ->
    id = 'trig_update_3'
    data_space\insert { id, json.encode { prenom: 'X', nom: 'Y' } }
    d_before = read_data id
    old_val = d_before.cree_le
    -- Wait one second and modify
    old = data_space\get id
    d = json.decode old[2]
    d.prenom = 'Z'
    data_space\replace { id, json.encode d }
    d_after = read_data id
    -- created_at must not change
    R.eq d_after.cree_le, old_val

R.describe "Triggers — compile_formula", ->
  -- Internal test through loaded module
  R.it "valid formula -> function", ->
    -- Use pcall + load directly to test behavior
    fn_str = "return function(self, space) return self.a + self.b end"
    ok, compiled = pcall load, fn_str
    R.ok ok
    ok2, fn = pcall compiled
    R.ok ok2
    R.eq type(fn), 'function'
    proxy = { a: 3, b: 4 }
    setmetatable proxy, { __index: (t, k) -> rawget t, k }
    R.eq fn(proxy, nil), 7

  R.it "invalid formula -> Lua error", ->
    fn_str = "return function(self, space) return self.a +++++ end"
    fn, err = load fn_str
    R.nok fn
    R.ok err

  R.it "valid MoonScript formula -> compiled to Lua function", ->
    -- Verify moonscript.base is available and compiles correctly
    ok_ms, moon = pcall require, 'moonscript.base'
    R.ok ok_ms, "moonscript.base should be available"
    moon_src = "return (self, space) -> (self.a or 0) + (self.b or 0)"
    ok_c, lua_code = pcall moon.to_lua, moon_src
    R.ok ok_c, "MoonScript → Lua: #{tostring lua_code}"
    ok_l, compiled = pcall load, lua_code
    R.ok ok_l, "load Lua: #{tostring compiled}"
    ok2, fn = pcall compiled
    R.ok ok2
    R.eq type(fn), 'function'
    R.eq fn({ a: 10, b: 5 }, nil), 15

R.describe "Triggers — trigger formula MoonScript", ->
  local ms_space_id, ms_data_space

  R.it "create space with MoonScript trigger formula", ->
    sp = spaces_mod.create_user_space MS_SP
    ms_space_id = sp.id
    ms_data_space = box.space["data_#{MS_SP}"]
    R.ok ms_data_space
    spaces_mod.add_field ms_space_id, 'a', 'Int'
    spaces_mod.add_field ms_space_id, 'b', 'Int'
    -- MoonScript trigger formula: add a and b
    spaces_mod.add_field ms_space_id, 'somme', 'Int', false, '',
      '(self.a or 0) + (self.b or 0)',
      {'a', 'b'}, 'moonscript'
    triggers.register_space_trigger MS_SP
    R.ok ms_data_space

  R.it "MoonScript trigger computes value on insert", ->
    id = 'moon_insert_1'
    ms_data_space\insert { id, json.encode { a: 3, b: 7 } }
    d = json.decode (ms_data_space\get id)[2]
    R.eq d.somme, 10

  R.it "MoonScript trigger recomputes on update", ->
    id = 'moon_update_1'
    ms_data_space\insert { id, json.encode { a: 2, b: 4 } }
    t = ms_data_space\get id
    d = json.decode t[2]
    d.a = 10
    ms_data_space\replace { id, json.encode d }
    d2 = json.decode (ms_data_space\get id)[2]
    R.eq d2.somme, 14

R.describe "Triggers — register_space_trigger", ->
  R.it "multiple calls without error (idempotent)", ->
    ok, err = pcall triggers.register_space_trigger, SP_NAME
    R.ok ok, "register_space_trigger should be idempotent: #{tostring err}"

  R.it "non-existing space -> no error", ->
    ok, err = pcall triggers.register_space_trigger, 'space_that_does_not_exist'
    R.ok ok, "non-existing space should be handled silently: #{tostring err}"

R.describe "Triggers — init_all_triggers", ->
  R.it "init_all_triggers runs without error", ->
    ok, err = pcall triggers.init_all_triggers
    R.ok ok, "init_all_triggers: #{tostring err}"

-- Cleanup: delete spaces created for these tests
spaces_mod.delete_user_space SP_NAME
spaces_mod.delete_user_space MS_SP
