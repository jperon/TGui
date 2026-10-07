local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local auth = require('core.auth')
local json = require('json')
local validation = require('core.validation')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "test_val_" .. tostring(SUFFIX)
local space_id = nil
return R.describe("core.validation — validate_record", function()
  R.it("setup: space with one field of each kind", function()
    local sp = spaces_mod.create_user_space(SP_NAME, "validation test")
    space_id = sp.id
    spaces_mod.add_field(space_id, 'nom', 'String', true)
    spaces_mod.add_field(space_id, 'age', 'Int')
    spaces_mod.add_field(space_id, 'prix', 'Float')
    spaces_mod.add_field(space_id, 'actif', 'Boolean')
    spaces_mod.add_field(space_id, 'code', 'UUID')
    spaces_mod.add_field(space_id, 'rid', 'ID')
    spaces_mod.add_field(space_id, 'quand', 'Datetime')
    spaces_mod.add_field(space_id, 'meta', 'Map')
    spaces_mod.add_field(space_id, 'tags', 'Array')
    spaces_mod.add_field(space_id, 'extra', 'Any')
    spaces_mod.add_field(space_id, 'auto_id', 'Sequence', true)
    spaces_mod.add_field(space_id, 'total', 'Int', false, '', '(self.age or 0) * 2', nil, 'lua')
    local parent_f = spaces_mod.add_field(space_id, 'parent', 'Int')
    spaces_mod.change_field_type(parent_f.id, 'Relation')
    return R.ok(space_id)
  end)
  R.it("returns the cleaned table", function()
    local cleaned = validation.validate_record(space_id, {
      nom = 'x',
      age = '10',
      prix = 3.5,
      auto_id = 5,
      total = 3
    }, 'insert')
    R.eq(cleaned.nom, 'x')
    R.eq(cleaned.age, 10)
    R.eq(cleaned.prix, 3.5)
    R.is_nil(cleaned.auto_id)
    return R.is_nil(cleaned.total)
  end)
  R.it("refuses an unknown field", function()
    return R.raises((function()
      return validation.validate_record(space_id, {
        nom = 'x',
        inconnu = 1
      }, 'insert')
    end), 'unknown field')
  end)
  R.it("requires not_null fields on insert", function()
    return R.raises((function()
      return validation.validate_record(space_id, {
        age = 30
      }, 'insert')
    end), 'nom: required')
  end)
  R.it("does not revalidate absent fields on update", function()
    local cleaned, cleared = validation.validate_record(space_id, {
      age = 31
    }, 'update')
    R.eq(cleaned.age, 31)
    return R.eq(#cleared, 0)
  end)
  R.it("refuses null on a not_null field at update", function()
    return R.raises((function()
      return validation.validate_record(space_id, {
        nom = json.NULL
      }, 'update')
    end), 'nom: null is not allowed')
  end)
  R.it("refuses a wrong type and names the field", function()
    R.raises((function()
      return validation.validate_record(space_id, {
        nom = 'x',
        age = 'abc'
      }, 'insert')
    end), 'age: expected Int')
    R.raises((function()
      return validation.validate_record(space_id, {
        nom = 42
      }, 'insert')
    end), 'nom: expected String')
    R.raises((function()
      return validation.validate_record(space_id, {
        nom = 'x',
        actif = 'oui'
      }, 'insert')
    end), 'actif: expected Boolean')
    R.raises((function()
      return validation.validate_record(space_id, {
        nom = 'x',
        prix = 'cher'
      }, 'insert')
    end), 'prix: expected Float')
    R.raises((function()
      return validation.validate_record(space_id, {
        nom = 'x',
        meta = 'texte'
      }, 'insert')
    end), 'meta: expected Map')
    return R.raises((function()
      return validation.validate_record(space_id, {
        nom = 'x',
        tags = 3
      }, 'insert')
    end), 'tags: expected Array')
  end)
  R.it("reports one reason per offending field", function()
    local ok, err = pcall(validation.validate_record, space_id, {
      nom = 42,
      age = 'abc',
      inconnu = true
    }, 'insert')
    R.nok(ok)
    local msg = tostring(err)
    R.ok(msg:find('nom: expected String', 1, true), msg)
    R.ok(msg:find('age: expected Int', 1, true), msg)
    return R.ok(msg:find('inconnu: unknown field', 1, true), msg)
  end)
  R.it("accepts every declared type", function()
    local cleaned = validation.validate_record(space_id, {
      nom = 'Ada',
      age = 42,
      prix = 1.5,
      actif = false,
      code = 'u-1',
      rid = 'r-1',
      quand = '2026-10-07',
      meta = {
        a = 1
      },
      tags = {
        1,
        2
      },
      extra = {
        deep = true
      },
      parent = '3'
    }, 'insert')
    R.eq(cleaned.nom, 'Ada')
    R.eq(cleaned.age, 42)
    R.eq(cleaned.prix, 1.5)
    R.eq(cleaned.actif, false)
    R.eq(cleaned.code, 'u-1')
    R.eq(cleaned.rid, 'r-1')
    R.eq(cleaned.quand, '2026-10-07')
    R.eq(cleaned.parent, '3')
    R.eq(cleaned.meta.a, 1)
    R.eq(#cleaned.tags, 2)
    return R.eq(cleaned.extra.deep, true)
  end)
  R.it("treats an empty non-String value as an empty value", function()
    local cleaned = validation.validate_record(space_id, {
      nom = 'x',
      age = '',
      quand = ''
    }, 'insert')
    R.is_nil(cleaned.age)
    R.is_nil(cleaned.quand)
    local cleaned2, cleared2 = validation.validate_record(space_id, {
      age = ''
    }, 'update')
    R.is_nil(cleaned2.age)
    R.eq(#cleared2, 1)
    return R.eq(cleared2[1], 'age')
  end)
  R.it("refuses a non-object payload and an unknown mode", function()
    R.raises((function()
      return validation.validate_record(space_id, 'pas-un-object', 'insert')
    end), 'expected an object')
    return R.raises((function()
      return validation.validate_record(space_id, { }, 'bogus')
    end), 'mode')
  end)
  return R.it("cleanup", function()
    return spaces_mod.delete_user_space(SP_NAME)
  end)
end)
