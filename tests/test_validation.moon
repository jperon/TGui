-- tests/test_validation.moon
-- Write-time record validation (core.validation), through validate_record and
-- the data mutations insertRecord / updateRecord and their batch variants.

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
triggers_mod = require 'core.triggers'
auth = require 'core.auth'
json = require 'json'
data_r = require 'resolvers.data_resolvers'
validation = require 'core.validation'

SUFFIX = tostring math.random 100000, 999999
SP_NAME = "test_val_#{SUFFIX}"

space_id = nil
ctx = nil

read_rec = (id) ->
  t = box.space["data_#{SP_NAME}"]\get id
  json.decode t[2]

R.describe "core.validation — validate_record", ->
  R.it "setup: space with one field of each kind", ->
    admin = auth.get_user_by_username 'admin'
    ctx = { user_id: admin.id }
    sp = spaces_mod.create_user_space SP_NAME, "validation test"
    space_id = sp.id
    spaces_mod.add_field space_id, 'nom', 'String', true
    spaces_mod.add_field space_id, 'age', 'Int'
    spaces_mod.add_field space_id, 'prix', 'Float'
    spaces_mod.add_field space_id, 'actif', 'Boolean'
    spaces_mod.add_field space_id, 'code', 'UUID'
    spaces_mod.add_field space_id, 'rid', 'ID'
    spaces_mod.add_field space_id, 'quand', 'Datetime'
    spaces_mod.add_field space_id, 'meta', 'Map'
    spaces_mod.add_field space_id, 'tags', 'Array'
    spaces_mod.add_field space_id, 'extra', 'Any'
    spaces_mod.add_field space_id, 'auto_id', 'Sequence', true
    spaces_mod.add_field space_id, 'total', 'Int', false, '', '(self.age or 0) * 2', nil, 'lua'
    spaces_mod.add_field space_id, 'label', 'String', false, '', '(self.nom or "") .. "!"', {}, 'lua'
    parent_f = spaces_mod.add_field space_id, 'parent', 'Int'
    spaces_mod.change_field_type parent_f.id, 'Relation'
    triggers_mod.register_space_trigger SP_NAME
    R.ok space_id
    R.ok ctx

  R.it "returns the cleaned table", ->
    cleaned = validation.validate_record space_id, {
      nom: 'x', age: '10', prix: 3.5, auto_id: 5, total: 3
    }, 'insert'
    R.eq cleaned.nom, 'x'
    R.eq cleaned.age, 10
    R.eq cleaned.prix, 3.5
    R.is_nil cleaned.auto_id
    R.is_nil cleaned.total

  R.it "refuses an unknown field", ->
    R.raises (-> validation.validate_record space_id, { nom: 'x', inconnu: 1 }, 'insert'), 'unknown field'

  R.it "requires not_null fields on insert", ->
    R.raises (-> validation.validate_record space_id, { age: 30 }, 'insert'), 'nom: required'

  R.it "does not revalidate absent fields on update", ->
    cleaned, cleared = validation.validate_record space_id, { age: 31 }, 'update'
    R.eq cleaned.age, 31
    R.eq #cleared, 0

  R.it "refuses null on a not_null field at update", ->
    R.raises (-> validation.validate_record space_id, { nom: json.NULL }, 'update'), 'nom: null is not allowed'

  R.it "refuses a wrong type and names the field", ->
    R.raises (-> validation.validate_record space_id, { nom: 'x', age: 'abc' }, 'insert'), 'age: expected Int'
    R.raises (-> validation.validate_record space_id, { nom: 42 }, 'insert'), 'nom: expected String'
    R.raises (-> validation.validate_record space_id, { nom: 'x', actif: 'oui' }, 'insert'), 'actif: expected Boolean'
    R.raises (-> validation.validate_record space_id, { nom: 'x', prix: 'cher' }, 'insert'), 'prix: expected Float'
    R.raises (-> validation.validate_record space_id, { nom: 'x', meta: 'texte' }, 'insert'), 'meta: expected Map'
    R.raises (-> validation.validate_record space_id, { nom: 'x', tags: 3 }, 'insert'), 'tags: expected Array'

  R.it "reports one reason per offending field", ->
    ok, err = pcall validation.validate_record, space_id, { nom: 42, age: 'abc', inconnu: true }, 'insert'
    R.nok ok
    msg = tostring err
    R.ok msg\find('nom: expected String', 1, true), msg
    R.ok msg\find('age: expected Int', 1, true), msg
    R.ok msg\find('inconnu: unknown field', 1, true), msg

  R.it "accepts every declared type", ->
    cleaned = validation.validate_record space_id, {
      nom: 'Ada', age: 42, prix: 1.5, actif: false, code: 'u-1', rid: 'r-1'
      quand: '2026-10-07', meta: { a: 1 }, tags: { 1, 2 }, extra: { deep: true }
      parent: '3'
    }, 'insert'
    R.eq cleaned.nom, 'Ada'
    R.eq cleaned.age, 42
    R.eq cleaned.prix, 1.5
    R.eq cleaned.actif, false
    R.eq cleaned.code, 'u-1'
    R.eq cleaned.rid, 'r-1'
    R.eq cleaned.quand, '2026-10-07'
    R.eq cleaned.parent, '3'
    R.eq cleaned.meta.a, 1
    R.eq #cleaned.tags, 2
    R.eq cleaned.extra.deep, true

  R.it "treats an empty non-String value as an empty value", ->
    cleaned = validation.validate_record space_id, { nom: 'x', age: '', quand: '' }, 'insert'
    R.is_nil cleaned.age
    R.is_nil cleaned.quand
    cleaned2, cleared2 = validation.validate_record space_id, { age: '' }, 'update'
    R.is_nil cleaned2.age
    R.eq #cleared2, 1
    R.eq cleared2[1], 'age'

  R.it "refuses a non-object payload and an unknown mode", ->
    R.raises (-> validation.validate_record space_id, 'pas-un-object', 'insert'), 'expected an object'
    R.raises (-> validation.validate_record space_id, {}, 'bogus'), 'mode'

R.describe "data mutations — write-time validation", ->
  R.it "insert refuses unknown, missing not_null and wrong types", ->
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'x', inconnu: 1 } }, ctx), 'unknown field'
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { age: 30 } }, ctx), 'nom: required'
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'x', age: 'abc' } }, ctx), 'age: expected Int'

  R.it "insert keeps only declared, valid values and fills the Sequence", ->
    rec = data_r.Mutation.insertRecord nil, {
      spaceId: space_id
      data: {
        nom: 'Ada', age: '42', prix: '3.5', actif: 'true', code: 'u-1', rid: 'r-1'
        quand: '2026-10-07', meta: { k: 1 }, tags: { 1, 2 }, extra: 'x', parent: '1'
      }
    }, ctx
    d = json.decode rec.data
    R.eq d.nom, 'Ada'
    R.eq d.age, 42
    R.eq d.prix, 3.5
    R.eq d.actif, true
    R.eq d.quand, '2026-10-07'
    R.eq d.parent, '1'
    R.eq d.meta.k, 1
    R.eq #d.tags, 2
    R.eq d.extra, 'x'
    R.ok type(d.auto_id) == 'number', 'auto_id filled by the sequence'

  R.it "insert ignores Sequence and computed field input", ->
    rec = data_r.Mutation.insertRecord nil, {
      spaceId: space_id, data: { nom: 'Calc', auto_id: 9999, total: 7, label: 'client' }
    }, ctx
    d = json.decode rec.data
    R.ne d.auto_id, 9999
    R.ok type(d.auto_id) == 'number'
    R.is_nil d.total
    R.ne d.label, 'client'

  R.it "insert drops empty optional values", ->
    rec = data_r.Mutation.insertRecord nil, {
      spaceId: space_id, data: { nom: 'Vide', age: '', prix: '', quand: '', parent: '' }
    }, ctx
    d = json.decode rec.data
    R.is_nil d.age
    R.is_nil d.prix
    R.is_nil d.quand
    R.is_nil d.parent
    R.eq d.nom, 'Vide'

  R.it "update does not revalidate fields absent from the payload", ->
    raw_id = "val_raw_#{SUFFIX}"
    box.space["data_#{SP_NAME}"]\insert { raw_id, json.encode({ age: 10 }) }
    data_r.Mutation.updateRecord nil, { spaceId: space_id, id: raw_id, data: { age: 11 } }, ctx
    d = read_rec raw_id
    R.eq d.age, 11
    R.is_nil d.nom

  R.it "update refuses null on a not_null field", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Keep' } }, ctx
    R.raises (-> data_r.Mutation.updateRecord nil, { spaceId: space_id, id: rec.id, data: '{"nom":null}' }, ctx), 'nom: null is not allowed'
    d = read_rec rec.id
    R.eq d.nom, 'Keep'

  R.it "update refuses unknown fields and wrong types", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Upd' } }, ctx
    R.raises (-> data_r.Mutation.updateRecord nil, { spaceId: space_id, id: rec.id, data: { inconnu: 1 } }, ctx), 'unknown field'
    R.raises (-> data_r.Mutation.updateRecord nil, { spaceId: space_id, id: rec.id, data: { age: 'abc' } }, ctx), 'age: expected Int'

  R.it "update clears a value sent as empty", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Clr', age: 30, parent: '1' } }, ctx
    data_r.Mutation.updateRecord nil, { spaceId: space_id, id: rec.id, data: { age: '', parent: '' } }, ctx
    d = read_rec rec.id
    R.is_nil d.age
    R.is_nil d.parent
    R.eq d.nom, 'Clr'

  R.it "update ignores computed field input", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Trig', label: 'client' } }, ctx
    d0 = read_rec rec.id
    R.ne d0.label, 'client'
    data_r.Mutation.updateRecord nil, { spaceId: space_id, id: rec.id, data: { label: 'autre', nom: 'Trig2' } }, ctx
    d1 = read_rec rec.id
    R.ne d1.label, 'autre'
    R.eq d1.nom, 'Trig2'

  R.it "Relation-typed field accepts id values as string or number", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Rel', parent: 3 } }, ctx
    R.eq (read_rec rec.id).parent, 3
    rec2 = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Rel2', parent: '4' } }, ctx
    R.eq (read_rec rec2.id).parent, '4'
    R.raises (-> data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Rel3', parent: {} } }, ctx), 'parent: expected Relation'

  R.it "batch insert rejects the whole batch", ->
    sp = box.space["data_#{SP_NAME}"]
    before = sp\count!
    R.raises (-> data_r.Mutation.insertRecords nil, { spaceId: space_id, data: { { nom: 'ok' }, { age: 'zzz' } } }, ctx), 'age: expected Int'
    R.eq sp\count!, before

  R.it "batch update rejects an invalid record", ->
    rec = data_r.Mutation.insertRecord nil, { spaceId: space_id, data: { nom: 'Batch' } }, ctx
    R.raises (-> data_r.Mutation.updateRecords nil, {
      spaceId: space_id, records: { { id: rec.id, data: { age: 'zzz' } } }
    }, ctx), 'age: expected Int'
    d = read_rec rec.id
    R.is_nil d.age
    R.eq d.nom, 'Batch'

  R.it "cleanup", ->
    spaces_mod.delete_user_space SP_NAME
