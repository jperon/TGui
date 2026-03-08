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
  return R.it("contient Sequence", function()
    local found = false
    for _, ft in ipairs(spaces_mod.FIELD_TYPES) do
      if ft == 'Sequence' then
        found = true
      end
    end
    return R.ok(found)
  end)
end)
return spaces_mod.delete_user_space(SP_NAME)
