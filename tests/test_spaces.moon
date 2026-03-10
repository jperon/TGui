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
    R.eq f.language, 'lua'  -- langage par défaut
    field_id_formula = f.id

  R.it "add_field avec triggerFields", ->
    f = spaces_mod.add_field space_id, 'initiales', 'String', false, '',
        'string.upper(string.sub(self.nom or "", 1, 1))',
        {'nom'}
    R.ok f
    R.ok f.triggerFields
    R.eq f.triggerFields[1], 'nom'

  R.it "add_field avec language=moonscript", ->
    f = spaces_mod.add_field space_id, 'nom_moon', 'String', false, '',
        '(self.nom or "") .. " (moon)"',
        nil, 'moonscript'
    R.ok f
    R.eq f.language, 'moonscript'
    R.eq f.formula, '(self.nom or "") .. " (moon)"'

  R.it "add_field avec type invalide → erreur", ->
    R.raises (-> spaces_mod.add_field space_id, 'x', 'TypeInexistant'), 'invalide'

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
        R.eq f.language, 'lua'
        return
    R.ok false  -- champ non trouvé

  R.it "champ moonscript a son language dans list_fields", ->
    fields = spaces_mod.list_fields space_id
    for f in *fields
      if f.name == 'nom_moon'
        R.eq f.language, 'moonscript'
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

  R.it "contient Datetime", ->
    found = false
    for _, ft in ipairs spaces_mod.FIELD_TYPES do
      if ft == 'Datetime' then found = true
    R.ok found

R.describe "Spaces — reprFormula et conversion", ->
  R.it "peut creer un champ avec reprFormula et Datetime", ->
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

  R.it "peut changer le type d'un champ avec conversion", ->
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

  R.it "conversion Int vers Sequence préserve les IDs existants", ->
    sp = spaces_mod.create_user_space 'test_seq_conv', 'Test sequence conversion'
    id_field = spaces_mod.add_field sp.id, 'id', 'Int', false, 'ID existant'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insérer des enregistrements avec des IDs spécifiques
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({id: 100, name: "A"}) }
    box.space["data_#{sp.name}"]\insert { "2", require('json').encode({id: 250, name: "B"}) }
    box.space["data_#{sp.name}"]\insert { "3", require('json').encode({id: 75, name: "C"}) }

    -- Convertir le champ id en Sequence
    changed = spaces_mod.change_field_type id_field.id, 'Sequence', nil, 'lua'
    R.eq 'Sequence', changed.fieldType

    -- Vérifier que les IDs existants sont préservés
    data1 = box.space["data_#{sp.name}"]\get "1"
    data2 = box.space["data_#{sp.name}"]\get "2"
    data3 = box.space["data_#{sp.name}"]\get "3"

    parsed1 = require('json').decode data1[2]
    parsed2 = require('json').decode data2[2]
    parsed3 = require('json').decode data3[2]

    R.eq 100, parsed1.id
    R.eq 250, parsed2.id
    R.eq 75, parsed3.id

    -- Vérifier que la séquence démarre après la valeur max (250)
    -- La séquence est créée mais on vérifie juste que les valeurs sont préservées
    -- Le test de la séquence lui-même peut être fait séparément

    spaces_mod.delete_user_space 'test_seq_conv'

  R.it "ajout champ Sequence sur espace non-vide préserve les valeurs", ->
    sp = spaces_mod.create_user_space 'test_seq_add', 'Test add sequence to non-empty'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insérer des enregistrements
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({name: "A"}) }
    box.space["data_#{sp.name}"]\insert { "2", require('json').encode({name: "B"}) }

    -- Ajouter un champ Sequence avec des valeurs existantes dans un autre champ
    id_field = spaces_mod.add_field sp.id, 'id', 'Sequence', false, 'ID auto'

    -- Vérifier que les nouveaux enregistrements ont des IDs de la séquence
    data1 = box.space["data_#{sp.name}"]\get "1"
    data2 = box.space["data_#{sp.name}"]\get "2"

    parsed1 = require('json').decode data1[2]
    parsed2 = require('json').decode data2[2]

    -- Les IDs devraient être 1 et 2 (premières valeurs de la séquence)
    R.eq 1, parsed1.id
    R.eq 2, parsed2.id

    spaces_mod.delete_user_space 'test_seq_add'

-- Nettoyage : suppression de l'espace créé pour ces tests
spaces_mod.delete_user_space SP_NAME

R.describe "Spaces — conversion Int vers Sequence", ->
  R.it "conversion Int vers Sequence préserve les IDs existants", ->
    sp = spaces_mod.create_user_space 'test_seq_conv', 'Test sequence conversion'
    id_field = spaces_mod.add_field sp.id, 'id', 'Int', false, 'ID existant'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insérer des enregistrements avec des IDs spécifiques
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({id: 100, name: "A"}) }
    box.space["data_#{sp.name}"]\insert { "2", require('json').encode({id: 250, name: "B"}) }
    box.space["data_#{sp.name}"]\insert { "3", require('json').encode({id: 75, name: "C"}) }

    -- Convertir le champ id en Sequence
    changed = spaces_mod.change_field_type id_field.id, 'Sequence', nil, 'lua'
    R.eq 'Sequence', changed.fieldType

    -- Vérifier que les IDs existants sont préservés
    data1 = box.space["data_#{sp.name}"]\get "1"
    data2 = box.space["data_#{sp.name}"]\get "2"
    data3 = box.space["data_#{sp.name}"]\get "3"

    parsed1 = require('json').decode data1[2]
    parsed2 = require('json').decode data2[2]
    parsed3 = require('json').decode data3[2]

    R.eq 100, parsed1.id
    R.eq 250, parsed2.id
    R.eq 75, parsed3.id

    -- Vérifier que la séquence démarre après la valeur max (250)
    -- La séquence est créée mais on vérifie juste que les valeurs sont préservées
    -- Le test de la séquence lui-même peut être fait séparément

    spaces_mod.delete_user_space 'test_seq_conv'

  R.it "conversion Int vers Sequence avec enregistrements sans valeur", ->
    sp = spaces_mod.create_user_space 'test_seq_empty', 'Test sequence empty values'
    id_field = spaces_mod.add_field sp.id, 'test_id', 'Int', false, 'Test ID'
    name_field = spaces_mod.add_field sp.id, 'name', 'String', false, 'Nom'

    -- Insérer un enregistrement sans valeur pour test_id
    box.space["data_#{sp.name}"]\insert { "1", require('json').encode({name: "No ID"}) }

    -- Convertir le champ en Sequence
    changed = spaces_mod.change_field_type id_field.id, 'Sequence', nil, 'lua'
    R.eq 'Sequence', changed.fieldType

    -- Vérifier que l'enregistrement sans ID a reçu une valeur
    data = box.space["data_#{sp.name}"]\get "1"
    parsed = require('json').decode data[2]

    -- Devrait avoir une valeur de séquence (commence à 1 car max_val = 0)
    error "L'enregistrement sans ID devrait avoir reçu une valeur" unless parsed.test_id != nil
    error "La valeur devrait être un nombre" unless type(parsed.test_id) == 'number'

    spaces_mod.delete_user_space 'test_seq_empty'
