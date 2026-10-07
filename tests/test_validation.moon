-- tests/test_validation.moon
-- Write-time record validation (core.validation).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
auth = require 'core.auth'
json = require 'json'
validation = require 'core.validation'

SUFFIX = tostring math.random 100000, 999999
SP_NAME = "test_val_#{SUFFIX}"

space_id = nil

R.describe "core.validation — validate_record", ->
  R.it "setup: space with one field of each kind", ->
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
    parent_f = spaces_mod.add_field space_id, 'parent', 'Int'
    spaces_mod.change_field_type parent_f.id, 'Relation'
    R.ok space_id

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

  R.it "cleanup", ->
    spaces_mod.delete_user_space SP_NAME
