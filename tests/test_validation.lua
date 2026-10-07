local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local triggers_mod = require('core.triggers')
local auth = require('core.auth')
local json = require('json')
local data_r = require('resolvers.data_resolvers')
local validation = require('core.validation')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "test_val_" .. tostring(SUFFIX)
local space_id = nil
local ctx = nil
local read_rec
read_rec = function(id)
  local t = box.space["data_" .. tostring(SP_NAME)]:get(id)
  return json.decode(t[2])
end
R.describe("core.validation — validate_record", function()
  R.it("setup: space with one field of each kind", function()
    local admin = auth.get_user_by_username('admin')
    ctx = {
      user_id = admin.id
    }
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
    spaces_mod.add_field(space_id, 'label', 'String', false, '', '(self.nom or "") .. "!"', { }, 'lua')
    local parent_f = spaces_mod.add_field(space_id, 'parent', 'Int')
    spaces_mod.change_field_type(parent_f.id, 'Relation')
    triggers_mod.register_space_trigger(SP_NAME)
    R.ok(space_id)
    return R.ok(ctx)
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
  return R.it("refuses a non-object payload and an unknown mode", function()
    R.raises((function()
      return validation.validate_record(space_id, 'pas-un-object', 'insert')
    end), 'expected an object')
    return R.raises((function()
      return validation.validate_record(space_id, { }, 'bogus')
    end), 'mode')
  end)
end)
return R.describe("data mutations — write-time validation", function()
  R.it("insert refuses unknown, missing not_null and wrong types", function()
    R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = space_id,
        data = {
          nom = 'x',
          inconnu = 1
        }
      }, ctx)
    end), 'unknown field')
    R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = space_id,
        data = {
          age = 30
        }
      }, ctx)
    end), 'nom: required')
    return R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = space_id,
        data = {
          nom = 'x',
          age = 'abc'
        }
      }, ctx)
    end), 'age: expected Int')
  end)
  R.it("insert keeps only declared, valid values and fills the Sequence", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Ada',
        age = '42',
        prix = '3.5',
        actif = 'true',
        code = 'u-1',
        rid = 'r-1',
        quand = '2026-10-07',
        meta = {
          k = 1
        },
        tags = {
          1,
          2
        },
        extra = 'x',
        parent = '1'
      }
    }, ctx)
    local d = json.decode(rec.data)
    R.eq(d.nom, 'Ada')
    R.eq(d.age, 42)
    R.eq(d.prix, 3.5)
    R.eq(d.actif, true)
    R.eq(d.quand, '2026-10-07')
    R.eq(d.parent, '1')
    R.eq(d.meta.k, 1)
    R.eq(#d.tags, 2)
    R.eq(d.extra, 'x')
    return R.ok(type(d.auto_id) == 'number', 'auto_id filled by the sequence')
  end)
  R.it("insert ignores Sequence and computed field input", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Calc',
        auto_id = 9999,
        total = 7,
        label = 'client'
      }
    }, ctx)
    local d = json.decode(rec.data)
    R.ne(d.auto_id, 9999)
    R.ok(type(d.auto_id) == 'number')
    R.is_nil(d.total)
    return R.ne(d.label, 'client')
  end)
  R.it("insert drops empty optional values", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Vide',
        age = '',
        prix = '',
        quand = '',
        parent = ''
      }
    }, ctx)
    local d = json.decode(rec.data)
    R.is_nil(d.age)
    R.is_nil(d.prix)
    R.is_nil(d.quand)
    R.is_nil(d.parent)
    return R.eq(d.nom, 'Vide')
  end)
  R.it("update does not revalidate fields absent from the payload", function()
    local raw_id = "val_raw_" .. tostring(SUFFIX)
    box.space["data_" .. tostring(SP_NAME)]:insert({
      raw_id,
      json.encode({
        age = 10
      })
    })
    data_r.Mutation.updateRecord(nil, {
      spaceId = space_id,
      id = raw_id,
      data = {
        age = 11
      }
    }, ctx)
    local d = read_rec(raw_id)
    R.eq(d.age, 11)
    return R.is_nil(d.nom)
  end)
  R.it("update refuses null on a not_null field", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Keep'
      }
    }, ctx)
    R.raises((function()
      return data_r.Mutation.updateRecord(nil, {
        spaceId = space_id,
        id = rec.id,
        data = '{"nom":null}'
      }, ctx)
    end), 'nom: null is not allowed')
    local d = read_rec(rec.id)
    return R.eq(d.nom, 'Keep')
  end)
  R.it("update refuses unknown fields and wrong types", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Upd'
      }
    }, ctx)
    R.raises((function()
      return data_r.Mutation.updateRecord(nil, {
        spaceId = space_id,
        id = rec.id,
        data = {
          inconnu = 1
        }
      }, ctx)
    end), 'unknown field')
    return R.raises((function()
      return data_r.Mutation.updateRecord(nil, {
        spaceId = space_id,
        id = rec.id,
        data = {
          age = 'abc'
        }
      }, ctx)
    end), 'age: expected Int')
  end)
  R.it("update clears a value sent as empty", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Clr',
        age = 30,
        parent = '1'
      }
    }, ctx)
    data_r.Mutation.updateRecord(nil, {
      spaceId = space_id,
      id = rec.id,
      data = {
        age = '',
        parent = ''
      }
    }, ctx)
    local d = read_rec(rec.id)
    R.is_nil(d.age)
    R.is_nil(d.parent)
    return R.eq(d.nom, 'Clr')
  end)
  R.it("update ignores computed field input", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Trig',
        label = 'client'
      }
    }, ctx)
    local d0 = read_rec(rec.id)
    R.ne(d0.label, 'client')
    data_r.Mutation.updateRecord(nil, {
      spaceId = space_id,
      id = rec.id,
      data = {
        label = 'autre',
        nom = 'Trig2'
      }
    }, ctx)
    local d1 = read_rec(rec.id)
    R.ne(d1.label, 'autre')
    return R.eq(d1.nom, 'Trig2')
  end)
  R.it("Relation-typed field accepts id values as string or number", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Rel',
        parent = 3
      }
    }, ctx)
    R.eq((read_rec(rec.id)).parent, 3)
    local rec2 = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Rel2',
        parent = '4'
      }
    }, ctx)
    R.eq((read_rec(rec2.id)).parent, '4')
    return R.raises((function()
      return data_r.Mutation.insertRecord(nil, {
        spaceId = space_id,
        data = {
          nom = 'Rel3',
          parent = { }
        }
      }, ctx)
    end), 'parent: expected Relation')
  end)
  R.it("batch insert rejects the whole batch", function()
    local sp = box.space["data_" .. tostring(SP_NAME)]
    local before = sp:count()
    R.raises((function()
      return data_r.Mutation.insertRecords(nil, {
        spaceId = space_id,
        data = {
          {
            nom = 'ok'
          },
          {
            age = 'zzz'
          }
        }
      }, ctx)
    end), 'age: expected Int')
    return R.eq(sp:count(), before)
  end)
  R.it("batch update rejects an invalid record", function()
    local rec = data_r.Mutation.insertRecord(nil, {
      spaceId = space_id,
      data = {
        nom = 'Batch'
      }
    }, ctx)
    R.raises((function()
      return data_r.Mutation.updateRecords(nil, {
        spaceId = space_id,
        records = {
          {
            id = rec.id,
            data = {
              age = 'zzz'
            }
          }
        }
      }, ctx)
    end), 'age: expected Int')
    local d = read_rec(rec.id)
    R.is_nil(d.age)
    return R.eq(d.nom, 'Batch')
  end)
  return R.it("cleanup", function()
    return spaces_mod.delete_user_space(SP_NAME)
  end)
end)
