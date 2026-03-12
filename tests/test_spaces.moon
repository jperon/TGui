-- tests/test_spaces.moon
-- Tests CRUD operations on spaces (core/spaces.moon).
-- Requires Tarantool (box already initialized in run.moon).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'

-- Unique identifier to isolate this test session.
SUFFIX = tostring(math.random 100000, 999999)
SP_NAME = "test_space_#{SUFFIX}"

local space_id, field_id_str, field_id_int, field_id_seq, field_id_formula

R.describe "Spaces — space creation", ->
  R.it "create_user_space returns metadata", ->
    sp = spaces_mod.create_user_space SP_NAME, "Test space"
    R.ok sp
    R.ok sp.id
    R.eq sp.name, SP_NAME
    R.ok sp.createdAt
    space_id = sp.id

  R.it "list_spaces includes created space", ->
    found = false
    for sp in *spaces_mod.list_spaces!
      if sp.id == space_id then found = true
    R.ok found

  R.it "get_space returns space by id", ->
    sp = spaces_mod.get_space space_id
    R.ok sp
    R.eq sp.name, SP_NAME

  R.it "data_X data space is created in Tarantool", ->
    R.ok box.space["data_#{SP_NAME}"]

R.describe "Spaces — add fields", ->
  R.it "add_field String", ->
    f = spaces_mod.add_field space_id, 'nom', 'String', false, 'Nom de la personne'
    R.ok f
    R.ok f.id
    R.eq f.name, 'nom'
    R.eq f.fieldType, 'String'
    R.eq f.notNull, false
    field_id_str = f.id

  R.it "add_field Int notNull", ->
    f = spaces_mod.add_field space_id, 'age', 'Int', true
    R.ok f
    R.eq f.fieldType, 'Int'
    R.eq f.notNull, true
    field_id_int = f.id

  R.it "add_field Sequence", ->
    f = spaces_mod.add_field space_id, 'seq_id', 'Sequence'
    R.ok f
    R.eq f.fieldType, 'Sequence'
    field_id_seq = f.id

  R.it "add_field with formula", ->
    f = spaces_mod.add_field space_id, 'nom_complet', 'String', false, '', 'self.nom or ""'
    R.ok f
    R.eq f.formula, 'self.nom or ""'
    R.eq f.language, 'lua'  -- default language
    field_id_formula = f.id

  R.it "add_field with triggerFields", ->
    f = spaces_mod.add_field space_id, 'initiales', 'String', false, '',
        'string.upper(string.sub(self.nom or "", 1, 1))',
        {'nom'}
    R.ok f
    R.ok f.triggerFields
    R.eq f.triggerFields[1], 'nom'

  R.it "add_field with language=moonscript", ->
    f = spaces_mod.add_field space_id, 'nom_moon', 'String', false, '',
        '(self.nom or "") .. " (moon)"',
        nil, 'moonscript'
    R.ok f
    R.eq f.language, 'moonscript'
    R.eq f.formula, '(self.nom or "") .. " (moon)"'

  R.it "add_field with invalid type -> error", ->
    R.raises (-> spaces_mod.add_field space_id, 'x', 'TypeInexistant'), 'invalide'

R.describe "Spaces — list_fields", ->
  R.it "returns fields sorted by position", ->
    fields = spaces_mod.list_fields space_id
    R.ok #fields >= 3
    -- verify ascending position order
    for i = 2, #fields
      R.ok fields[i].position >= fields[i-1].position

  R.it "fields include nom, age, seq_id", ->
    fields = spaces_mod.list_fields space_id
    names = { f.name, true for f in *fields }
    R.ok names['nom']
    R.ok names['age']
    R.ok names['seq_id']

  R.it "formula column contains formula in list_fields", ->
    fields = spaces_mod.list_fields space_id
    for f in *fields
      if f.name == 'nom_complet'
        R.ok f.formula and f.formula != ''
        R.eq f.language, 'lua'
        return
    R.ok false  -- field not found

  R.it "moonscript field keeps language in list_fields", ->
    fields = spaces_mod.list_fields space_id
    for f in *fields
      if f.name == 'nom_moon'
        R.eq f.language, 'moonscript'
        return
    R.ok false  -- field not found

  R.it "trigger formula keeps triggerFields in list_fields", ->
    fields = spaces_mod.list_fields space_id
    for f in *fields
      if f.name == 'initiales'
        R.ok f.triggerFields
        R.eq f.triggerFields[1], 'nom'
        return
    R.ok false

R.describe "Spaces — field deletion", ->
  R.it "remove_field deletes field", ->
    -- Add a temporary field then remove it
    tmp = spaces_mod.add_field space_id, 'tmp_field', 'Boolean'
    spaces_mod.remove_field tmp.id
    fields = spaces_mod.list_fields space_id
    found = false
    for f in *fields
      if f.name == 'tmp_field' then found = true
    R.nok found

R.describe "Spaces — reordering", ->
  R.it "reorder_fields change les positions", ->
    fields = spaces_mod.list_fields space_id
    ids = [f.id for f in *fields]
    -- Reverse order
    reversed = [ids[#ids - i + 1] for i = 1, #ids]
    result = spaces_mod.reorder_fields space_id, reversed
    R.ok result
    -- Verify first returned field has position 1
    R.eq result[1].position, 1

R.describe "Spaces — FIELD_TYPES", ->
  R.it "contains basic types", ->
    for _, t in ipairs {'String', 'Int', 'Float', 'Boolean', 'UUID'} do
      found = false
      for _, ft in ipairs spaces_mod.FIELD_TYPES do
        if ft == t then found = true
      R.ok found, "FIELD_TYPES doit contenir #{t}"

  R.it "contains Any, Map, Array", ->
    for _, t in ipairs {'Any', 'Map', 'Array'} do
      found = false
      for _, ft in ipairs spaces_mod.FIELD_TYPES do
        if ft == t then found = true
      R.ok found, "FIELD_TYPES doit contenir #{t}"

  R.it "contains Sequence", ->
    found = false
    for _, ft in ipairs spaces_mod.FIELD_TYPES do
      if ft == 'Sequence' then found = true
    R.ok found

  R.it "contains Datetime", ->
    found = false
    for _, ft in ipairs spaces_mod.FIELD_TYPES do
      if ft == 'Datetime' then found = true
    R.ok found

R.describe "Spaces — reprFormula and conversion", ->
  R.it "can create a field with reprFormula and Datetime", ->
    sp = spaces_mod.create_user_space 'test_repr_space', 'space for repr tests'

    -- Datetime field
    dt_field = spaces_mod.add_field sp.id, 'created_at', 'Datetime', false, '', '', nil, 'lua', ''
    R.eq 'Datetime', dt_field.fieldType

    -- String field with reprFormula
    repr_field = spaces_mod.add_field sp.id, 'status', 'String', false, '', '', nil, 'lua', "return string.upper(self.status or '')"
    R.eq "return string.upper(self.status or '')", repr_field.reprFormula

    fields = spaces_mod.list_fields sp.id
    R.eq 2, #fields  -- created_at, status
    R.eq 'Datetime', fields[1].fieldType
    R.eq "return string.upper(self.status or '')", fields[2].reprFormula

    spaces_mod.delete_user_space 'test_repr_space'

  R.it "can change field type with conversion", ->
    sp = spaces_mod.create_user_space 'test_conv_space', 'space for conversion tests'
    str_field = spaces_mod.add_field sp.id, 'amount', 'String', false, ''

    -- Insert some string data
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({amount: "42"}) }

    -- Change type to Int with conversion formula
    changed = spaces_mod.change_field_type str_field.id, 'Int', 'tonumber(self.amount)', 'lua'
    R.eq 'Int', changed.fieldType

    -- Verify data was converted
    data = box.space["data_#{sp.name}"]\get "1"
    parsed = require('json').decode data[2]
    R.eq 42, parsed.amount

    spaces_mod.delete_user_space 'test_conv_space'

  R.it "Int to Sequence conversion preserves existing IDs", ->
    sp = spaces_mod.create_user_space 'test_seq_conv', 'Test sequence conversion'
    id_field = spaces_mod.add_field sp.id, 'id', 'Int', false, 'ID existant'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insert records with specific IDs
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({id: 100, name: "A"}) }
    box.space["data_#{sp.name}"]\insert { "2", require('json').encode({id: 250, name: "B"}) }
    box.space["data_#{sp.name}"]\insert { "3", require('json').encode({id: 75, name: "C"}) }

    -- Convert id field to Sequence
    changed = spaces_mod.change_field_type id_field.id, 'Sequence', nil, 'lua'
    R.eq 'Sequence', changed.fieldType

    -- Verify existing IDs are preserved
    data1 = box.space["data_#{sp.name}"]\get "1"
    data2 = box.space["data_#{sp.name}"]\get "2"
    data3 = box.space["data_#{sp.name}"]\get "3"

    parsed1 = require('json').decode data1[2]
    parsed2 = require('json').decode data2[2]
    parsed3 = require('json').decode data3[2]

    R.eq 100, parsed1.id
    R.eq 250, parsed2.id
    R.eq 75, parsed3.id

    -- Verify sequence starts after max value (250)
    -- Sequence is created; here we only verify values are preserved
    -- Sequence behavior itself can be tested separately

    spaces_mod.delete_user_space 'test_seq_conv'

  R.it "adding Sequence field on non-empty space preserves values", ->
    sp = spaces_mod.create_user_space 'test_seq_add', 'Test add sequence to non-empty'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insert records
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({name: "A"}) }
    box.space["data_#{sp.name}"]\insert { "2", require('json').encode({name: "B"}) }

    -- Add Sequence field while existing rows already exist
    id_field = spaces_mod.add_field sp.id, 'id', 'Sequence', false, 'ID auto'

    -- Verify existing rows received sequence IDs
    data1 = box.space["data_#{sp.name}"]\get "1"
    data2 = box.space["data_#{sp.name}"]\get "2"

    parsed1 = require('json').decode data1[2]
    parsed2 = require('json').decode data2[2]

    -- IDs should be 1 and 2 (first sequence values)
    R.eq 1, parsed1.id
    R.eq 2, parsed2.id

    spaces_mod.delete_user_space 'test_seq_add'

-- Cleanup: remove space created for these tests
spaces_mod.delete_user_space SP_NAME

R.describe "Spaces — Int to Sequence conversion", ->
  R.it "Int to Sequence conversion preserves existing IDs", ->
    sp = spaces_mod.create_user_space 'test_seq_conv', 'Test sequence conversion'
    id_field = spaces_mod.add_field sp.id, 'id', 'Int', false, 'ID existant'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insert records with specific IDs
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({id: 100, name: "A"}) }
    box.space["data_#{sp.name}"]\insert { "2", require('json').encode({id: 250, name: "B"}) }
    box.space["data_#{sp.name}"]\insert { "3", require('json').encode({id: 75, name: "C"}) }

    -- Convert id field to Sequence
    changed = spaces_mod.change_field_type id_field.id, 'Sequence', nil, 'lua'
    R.eq 'Sequence', changed.fieldType

    -- Verify existing IDs are preserved
    data1 = box.space["data_#{sp.name}"]\get "1"
    data2 = box.space["data_#{sp.name}"]\get "2"
    data3 = box.space["data_#{sp.name}"]\get "3"

    parsed1 = require('json').decode data1[2]
    parsed2 = require('json').decode data2[2]
    parsed3 = require('json').decode data3[2]

    R.eq 100, parsed1.id
    R.eq 250, parsed2.id
    R.eq 75, parsed3.id

    -- Verify sequence starts after max value (250)
    -- Sequence is created; here we only verify values are preserved
    -- Sequence behavior itself can be tested separately

    spaces_mod.delete_user_space 'test_seq_conv'

  R.it "Int to Sequence conversion with records missing value", ->
    sp = spaces_mod.create_user_space 'test_seq_empty', 'Test sequence empty values'
    id_field = spaces_mod.add_field sp.id, 'test_id', 'Int', false, 'Test ID'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insert a record without test_id value
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({name: "No ID"}) }

    -- Convert field to Sequence
    changed = spaces_mod.change_field_type id_field.id, 'Sequence', nil, 'lua'
    R.eq 'Sequence', changed.fieldType

    -- Verify record without ID received a value
    data = box.space["data_#{sp.name}"]\get "1"
    parsed = require('json').decode data[2]

    -- Should have a sequence value (starts at 1 because max_val = 0)
    error "Record without ID should receive a value" unless parsed.test_id != nil
    error "Value should be a number" unless type(parsed.test_id) == 'number'

    spaces_mod.delete_user_space 'test_seq_empty'
