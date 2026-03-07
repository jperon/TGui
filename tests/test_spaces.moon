-- tests/test_spaces.moon
-- Tests des opérations CRUD sur les espaces (core/spaces.moon).
-- Nécessite Tarantool (box déjà initialisé dans run.moon).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'

-- Identifiant unique pour isoler les tests de cette session
SUFFIX = tostring(math.random 100000, 999999)
SP_NAME = "test_space_#{SUFFIX}"

local space_id, field_id_str, field_id_int, field_id_seq, field_id_formula

R.describe "Spaces — création d'espace", ->
  R.it "create_user_space retourne les métadonnées", ->
    sp = spaces_mod.create_user_space SP_NAME, "Espace de test"
    R.ok sp
    R.ok sp.id
    R.eq sp.name, SP_NAME
    R.ok sp.createdAt
    space_id = sp.id

  R.it "list_spaces inclut l'espace créé", ->
    found = false
    for sp in *spaces_mod.list_spaces!
      if sp.id == space_id then found = true
    R.ok found

  R.it "get_space retourne l'espace par id", ->
    sp = spaces_mod.get_space space_id
    R.ok sp
    R.eq sp.name, SP_NAME

  R.it "l'espace de données data_X est créé dans Tarantool", ->
    R.ok box.space["data_#{SP_NAME}"]

R.describe "Spaces — ajout de champs", ->
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

  R.it "add_field avec formula", ->
    f = spaces_mod.add_field space_id, 'nom_complet', 'String', false, '', 'self.nom or ""'
    R.ok f
    R.eq f.formula, 'self.nom or ""'
    field_id_formula = f.id

  R.it "add_field avec triggerFields", ->
    f = spaces_mod.add_field space_id, 'initiales', 'String', false, '',
        'string.upper(string.sub(self.nom or "", 1, 1))',
        {'nom'}
    R.ok f
    R.ok f.triggerFields
    R.eq f.triggerFields[1], 'nom'

R.describe "Spaces — list_fields", ->
  R.it "retourne les champs triés par position", ->
    fields = spaces_mod.list_fields space_id
    R.ok #fields >= 3
    -- vérifier l'ordre croissant des positions
    for i = 2, #fields
      R.ok fields[i].position >= fields[i-1].position

  R.it "les champs incluent nom, age, seq_id", ->
    fields = spaces_mod.list_fields space_id
    names = { f.name, true for f in *fields }
    R.ok names['nom']
    R.ok names['age']
    R.ok names['seq_id']

  R.it "formula column a sa formula dans list_fields", ->
    fields = spaces_mod.list_fields space_id
    for f in *fields
      if f.name == 'nom_complet'
        R.ok f.formula and f.formula != ''
        return
    R.ok false  -- champ non trouvé

  R.it "trigger formula a ses triggerFields dans list_fields", ->
    fields = spaces_mod.list_fields space_id
    for f in *fields
      if f.name == 'initiales'
        R.ok f.triggerFields
        R.eq f.triggerFields[1], 'nom'
        return
    R.ok false

R.describe "Spaces — suppression de champ", ->
  R.it "remove_field supprime le champ", ->
    -- Ajouter un champ temporaire puis le supprimer
    tmp = spaces_mod.add_field space_id, 'tmp_field', 'Boolean'
    spaces_mod.remove_field tmp.id
    fields = spaces_mod.list_fields space_id
    found = false
    for f in *fields
      if f.name == 'tmp_field' then found = true
    R.nok found

R.describe "Spaces — réordonnancement", ->
  R.it "reorder_fields change les positions", ->
    fields = spaces_mod.list_fields space_id
    ids = [f.id for f in *fields]
    -- Inverser l'ordre
    reversed = [ids[#ids - i + 1] for i = 1, #ids]
    result = spaces_mod.reorder_fields space_id, reversed
    R.ok result
    -- Vérifier que le premier champ retourné a position 1
    R.eq result[1].position, 1

R.describe "Spaces — FIELD_TYPES", ->
  R.it "contient les types de base", ->
    for _, t in ipairs {'String', 'Int', 'Float', 'Boolean', 'UUID'} do
      found = false
      for _, ft in ipairs spaces_mod.FIELD_TYPES do
        if ft == t then found = true
      R.ok found, "FIELD_TYPES doit contenir #{t}"

  R.it "contient Any, Map, Array", ->
    for _, t in ipairs {'Any', 'Map', 'Array'} do
      found = false
      for _, ft in ipairs spaces_mod.FIELD_TYPES do
        if ft == t then found = true
      R.ok found, "FIELD_TYPES doit contenir #{t}"

  R.it "contient Sequence", ->
    found = false
    for _, ft in ipairs spaces_mod.FIELD_TYPES do
      if ft == 'Sequence' then found = true
    R.ok found
