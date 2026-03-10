local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "test_space_" .. tostring(SUFFIX)
local space_id, field_id_str, field_id_int, field_id_seq, field_id_formula
R.describe("Spaces — création d'espace", function()
  R.it("create_user_space retourne les métadonnées", function()
    local sp = spaces_mod.create_user_space(SP_NAME, "Espace de test")
    R.ok(sp)
    R.ok(sp.id)
    R.eq(sp.name, SP_NAME)
    R.ok(sp.createdAt)
    space_id = sp.id
  end)
  R.it("list_spaces inclut l'espace créé", function()
    local found = false
    local _list_0 = spaces_mod.list_spaces()
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      if sp.id == space_id then
        found = true
      end
    end
    return R.ok(found)
  end)
  R.it("get_space retourne l'espace par id", function()
    local sp = spaces_mod.get_space(space_id)
    R.ok(sp)
    return R.eq(sp.name, SP_NAME)
  end)
  return R.it("l'espace de données data_X est créé dans Tarantool", function()
    return R.ok(box.space["data_" .. tostring(SP_NAME)])
  end)
end)
R.describe("Spaces — ajout de champs", function()
  R.it("add_field String", function()
    local f = spaces_mod.add_field(space_id, 'nom', 'String', false, 'Nom de la personne')
    R.ok(f)
    R.ok(f.id)
    R.eq(f.name, 'nom')
    R.eq(f.fieldType, 'String')
    R.eq(f.notNull, false)
    field_id_str = f.id
  end)
  R.it("add_field Int notNull", function()
    local f = spaces_mod.add_field(space_id, 'age', 'Int', true)
    R.ok(f)
    R.eq(f.fieldType, 'Int')
    R.eq(f.notNull, true)
    field_id_int = f.id
  end)
  R.it("add_field Sequence", function()
    local f = spaces_mod.add_field(space_id, 'seq_id', 'Sequence')
    R.ok(f)
    R.eq(f.fieldType, 'Sequence')
    field_id_seq = f.id
  end)
  R.it("add_field avec formula", function()
    local f = spaces_mod.add_field(space_id, 'nom_complet', 'String', false, '', 'self.nom or ""')
    R.ok(f)
    R.eq(f.formula, 'self.nom or ""')
    R.eq(f.language, 'lua')
    field_id_formula = f.id
  end)
  R.it("add_field avec triggerFields", function()
    local f = spaces_mod.add_field(space_id, 'initiales', 'String', false, '', 'string.upper(string.sub(self.nom or "", 1, 1))', {
      'nom'
    })
    R.ok(f)
    R.ok(f.triggerFields)
    return R.eq(f.triggerFields[1], 'nom')
  end)
  R.it("add_field avec language=moonscript", function()
    local f = spaces_mod.add_field(space_id, 'nom_moon', 'String', false, '', '(self.nom or "") .. " (moon)"', nil, 'moonscript')
    R.ok(f)
    R.eq(f.language, 'moonscript')
    return R.eq(f.formula, '(self.nom or "") .. " (moon)"')
  end)
  return R.it("add_field avec type invalide → erreur", function()
    return R.raises((function()
      return spaces_mod.add_field(space_id, 'x', 'TypeInexistant')
    end), 'invalide')
  end)
end)
R.describe("Spaces — list_fields", function()
  R.it("retourne les champs triés par position", function()
    local fields = spaces_mod.list_fields(space_id)
    R.ok(#fields >= 3)
    for i = 2, #fields do
      R.ok(fields[i].position >= fields[i - 1].position)
    end
  end)
  R.it("les champs incluent nom, age, seq_id", function()
    local fields = spaces_mod.list_fields(space_id)
    local names
    do
      local _tbl_0 = { }
      for _index_0 = 1, #fields do
        local f = fields[_index_0]
        _tbl_0[f.name] = true
      end
      names = _tbl_0
    end
    R.ok(names['nom'])
    R.ok(names['age'])
    return R.ok(names['seq_id'])
  end)
  R.it("formula column a sa formula dans list_fields", function()
    local fields = spaces_mod.list_fields(space_id)
    for _index_0 = 1, #fields do
      local f = fields[_index_0]
      if f.name == 'nom_complet' then
        R.ok(f.formula and f.formula ~= '')
        R.eq(f.language, 'lua')
        return 
      end
    end
    return R.ok(false)
  end)
  R.it("champ moonscript a son language dans list_fields", function()
    local fields = spaces_mod.list_fields(space_id)
    for _index_0 = 1, #fields do
      local f = fields[_index_0]
      if f.name == 'nom_moon' then
        R.eq(f.language, 'moonscript')
        return 
      end
    end
    return R.ok(false)
  end)
  return R.it("trigger formula a ses triggerFields dans list_fields", function()
    local fields = spaces_mod.list_fields(space_id)
    for _index_0 = 1, #fields do
      local f = fields[_index_0]
      if f.name == 'initiales' then
        R.ok(f.triggerFields)
        R.eq(f.triggerFields[1], 'nom')
        return 
      end
    end
    return R.ok(false)
  end)
end)
R.describe("Spaces — suppression de champ", function()
  return R.it("remove_field supprime le champ", function()
    local tmp = spaces_mod.add_field(space_id, 'tmp_field', 'Boolean')
    spaces_mod.remove_field(tmp.id)
    local fields = spaces_mod.list_fields(space_id)
    local found = false
    for _index_0 = 1, #fields do
      local f = fields[_index_0]
      if f.name == 'tmp_field' then
        found = true
      end
    end
    return R.nok(found)
  end)
end)
R.describe("Spaces — réordonnancement", function()
  return R.it("reorder_fields change les positions", function()
    local fields = spaces_mod.list_fields(space_id)
    local ids
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #fields do
        local f = fields[_index_0]
        _accum_0[_len_0] = f.id
        _len_0 = _len_0 + 1
      end
      ids = _accum_0
    end
    local reversed
    do
      local _accum_0 = { }
      local _len_0 = 1
      for i = 1, #ids do
        _accum_0[_len_0] = ids[#ids - i + 1]
        _len_0 = _len_0 + 1
      end
      reversed = _accum_0
    end
    local result = spaces_mod.reorder_fields(space_id, reversed)
    R.ok(result)
    return R.eq(result[1].position, 1)
  end)
end)
R.describe("Spaces — FIELD_TYPES", function()
  R.it("contient les types de base", function()
    for _, t in ipairs({
      'String',
      'Int',
      'Float',
      'Boolean',
      'UUID'
    }) do
      local found = false
      for _, ft in ipairs(spaces_mod.FIELD_TYPES) do
        if ft == t then
          found = true
        end
      end
      R.ok(found, "FIELD_TYPES doit contenir " .. tostring(t))
    end
  end)
  R.it("contient Any, Map, Array", function()
    for _, t in ipairs({
      'Any',
      'Map',
      'Array'
    }) do
      local found = false
      for _, ft in ipairs(spaces_mod.FIELD_TYPES) do
        if ft == t then
          found = true
        end
      end
      R.ok(found, "FIELD_TYPES doit contenir " .. tostring(t))
    end
  end)
  R.it("contient Sequence", function()
    local found = false
    for _, ft in ipairs(spaces_mod.FIELD_TYPES) do
      if ft == 'Sequence' then
        found = true
      end
    end
    return R.ok(found)
  end)
  return R.it("contient Datetime", function()
    local found = false
    for _, ft in ipairs(spaces_mod.FIELD_TYPES) do
      if ft == 'Datetime' then
        found = true
      end
    end
    return R.ok(found)
  end)
end)
R.describe("Spaces — reprFormula et conversion", function()
  R.it("peut creer un champ avec reprFormula et Datetime", function()
    local sp = spaces_mod.create_user_space('test_repr_space', 'space for repr tests')
    local dt_field = spaces_mod.add_field(sp.id, 'created_at', 'Datetime', false, '', '', nil, 'lua', '')
    R.eq('Datetime', dt_field.fieldType)
    local repr_field = spaces_mod.add_field(sp.id, 'status', 'String', false, '', '', nil, 'lua', "return string.upper(self.status or '')")
    R.eq("return string.upper(self.status or '')", repr_field.reprFormula)
    local fields = spaces_mod.list_fields(sp.id)
    R.eq(2, #fields)
    R.eq('Datetime', fields[1].fieldType)
    R.eq("return string.upper(self.status or '')", fields[2].reprFormula)
    return spaces_mod.delete_user_space('test_repr_space')
  end)
  R.it("peut changer le type d'un champ avec conversion", function()
    local sp = spaces_mod.create_user_space('test_conv_space', 'space for conversion tests')
    local str_field = spaces_mod.add_field(sp.id, 'amount', 'String', false, '')
    box.space["data_" .. tostring(sp.name)]:insert({
      "1",
      require('json').encode({
        amount = "42"
      })
    })
    local changed = spaces_mod.change_field_type(str_field.id, 'Int', 'tonumber(self.amount)', 'lua')
    R.eq('Int', changed.fieldType)
    local data = box.space["data_" .. tostring(sp.name)]:get("1")
    local parsed = require('json').decode(data[2])
    R.eq(42, parsed.amount)
    return spaces_mod.delete_user_space('test_conv_space')
  end)
  R.it("conversion Int vers Sequence préserve les IDs existants", function()
    local sp = spaces_mod.create_user_space('test_seq_conv', 'Test sequence conversion')
    local id_field = spaces_mod.add_field(sp.id, 'id', 'Int', false, 'ID existant')
    local name_field = spaces_mod.add_field(sp.id, 'name', 'String', false, 'Nom')
    box.space["data_" .. tostring(sp.name)]:insert({
      "1",
      require('json').encode({
        id = 100,
        name = "A"
      })
    })
    box.space["data_" .. tostring(sp.name)]:insert({
      "2",
      require('json').encode({
        id = 250,
        name = "B"
      })
    })
    box.space["data_" .. tostring(sp.name)]:insert({
      "3",
      require('json').encode({
        id = 75,
        name = "C"
      })
    })
    local changed = spaces_mod.change_field_type(id_field.id, 'Sequence', nil, 'lua')
    R.eq('Sequence', changed.fieldType)
    local data1 = box.space["data_" .. tostring(sp.name)]:get("1")
    local data2 = box.space["data_" .. tostring(sp.name)]:get("2")
    local data3 = box.space["data_" .. tostring(sp.name)]:get("3")
    local parsed1 = require('json').decode(data1[2])
    local parsed2 = require('json').decode(data2[2])
    local parsed3 = require('json').decode(data3[2])
    R.eq(100, parsed1.id)
    R.eq(250, parsed2.id)
    R.eq(75, parsed3.id)
    return spaces_mod.delete_user_space('test_seq_conv')
  end)
  return R.it("ajout champ Sequence sur espace non-vide préserve les valeurs", function()
    local sp = spaces_mod.create_user_space('test_seq_add', 'Test add sequence to non-empty')
    local name_field = spaces_mod.add_field(sp.id, 'name', 'String', false, 'Nom')
    box.space["data_" .. tostring(sp.name)]:insert({
      "1",
      require('json').encode({
        name = "A"
      })
    })
    box.space["data_" .. tostring(sp.name)]:insert({
      "2",
      require('json').encode({
        name = "B"
      })
    })
    local id_field = spaces_mod.add_field(sp.id, 'id', 'Sequence', false, 'ID auto')
    local data1 = box.space["data_" .. tostring(sp.name)]:get("1")
    local data2 = box.space["data_" .. tostring(sp.name)]:get("2")
    local parsed1 = require('json').decode(data1[2])
    local parsed2 = require('json').decode(data2[2])
    R.eq(1, parsed1.id)
    R.eq(2, parsed2.id)
    return spaces_mod.delete_user_space('test_seq_add')
  end)
end)
spaces_mod.delete_user_space(SP_NAME)
return R.describe("Spaces — conversion Int vers Sequence", function()
  R.it("conversion Int vers Sequence préserve les IDs existants", function()
    local sp = spaces_mod.create_user_space('test_seq_conv', 'Test sequence conversion')
    local id_field = spaces_mod.add_field(sp.id, 'id', 'Int', false, 'ID existant')
    local name_field = spaces_mod.add_field(sp.id, 'name', 'String', false, 'Nom')
    box.space["data_" .. tostring(sp.name)]:insert({
      "1",
      require('json').encode({
        id = 100,
        name = "A"
      })
    })
    box.space["data_" .. tostring(sp.name)]:insert({
      "2",
      require('json').encode({
        id = 250,
        name = "B"
      })
    })
    box.space["data_" .. tostring(sp.name)]:insert({
      "3",
      require('json').encode({
        id = 75,
        name = "C"
      })
    })
    local changed = spaces_mod.change_field_type(id_field.id, 'Sequence', nil, 'lua')
    R.eq('Sequence', changed.fieldType)
    local data1 = box.space["data_" .. tostring(sp.name)]:get("1")
    local data2 = box.space["data_" .. tostring(sp.name)]:get("2")
    local data3 = box.space["data_" .. tostring(sp.name)]:get("3")
    local parsed1 = require('json').decode(data1[2])
    local parsed2 = require('json').decode(data2[2])
    local parsed3 = require('json').decode(data3[2])
    R.eq(100, parsed1.id)
    R.eq(250, parsed2.id)
    R.eq(75, parsed3.id)
    return spaces_mod.delete_user_space('test_seq_conv')
  end)
  return R.it("conversion Int vers Sequence avec enregistrements sans valeur", function()
    local sp = spaces_mod.create_user_space('test_seq_empty', 'Test sequence empty values')
    local id_field = spaces_mod.add_field(sp.id, 'test_id', 'Int', false, 'Test ID')
    local name_field = spaces_mod.add_field(sp.id, 'name', 'String', false, 'Nom')
    box.space["data_" .. tostring(sp.name)]:insert({
      "1",
      require('json').encode({
        name = "No ID"
      })
    })
    local changed = spaces_mod.change_field_type(id_field.id, 'Sequence', nil, 'lua')
    R.eq('Sequence', changed.fieldType)
    local data = box.space["data_" .. tostring(sp.name)]:get("1")
    local parsed = require('json').decode(data[2])
    if not (parsed.test_id ~= nil) then
      error("L'enregistrement sans ID devrait avoir reçu une valeur")
    end
    if not (type(parsed.test_id) == 'number') then
      error("La valeur devrait être un nombre")
    end
    return spaces_mod.delete_user_space('test_seq_empty')
  end)
end)
