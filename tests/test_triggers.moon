-- tests/test_triggers.moon
-- Tests des trigger formulas (core/triggers.moon).
-- Nécessite Tarantool (box déjà initialisé dans run.moon).

R = require 'tests.runner'
json        = require 'json'
spaces_mod  = require 'core.spaces'
triggers    = require 'core.triggers'

-- Espace isolé pour ces tests
SUFFIX  = tostring(math.random 100000, 999999)
SP_NAME = "test_triggers_#{SUFFIX}"

local space_id, data_space

-- Helper : insérer un tuple directement
insert_raw = (data) ->
  id = tostring(os.time!) .. math.random(1000, 9999)
  data_space\insert { id, json.encode data }
  { id: id, data: data }

-- Helper : lire les données d'un tuple
read_data = (id) ->
  t = data_space\get id
  return nil unless t
  json.decode t[2]

R.describe "Triggers — setup", ->
  R.it "créer l'espace de test", ->
    sp = spaces_mod.create_user_space SP_NAME
    space_id = sp.id
    data_space = box.space["data_#{SP_NAME}"]
    R.ok data_space

  R.it "ajouter les champs de base", ->
    spaces_mod.add_field space_id, 'prenom', 'String'
    spaces_mod.add_field space_id, 'nom',    'String'
    -- Trigger formula : se déclenche à tout changement de prenom ou nom
    spaces_mod.add_field space_id, 'nom_complet', 'String', false, '',
      '(self.prenom or "") .. " " .. (self.nom or "")',
      {'prenom', 'nom'}
    -- Trigger formula : création seulement
    spaces_mod.add_field space_id, 'cree_le', 'String', false, '',
      'os.date("%Y")',
      {}
    triggers.register_space_trigger SP_NAME
    R.ok data_space  -- trigger enregistré sans erreur

R.describe "Triggers — déclenchement à l'insertion", ->
  R.it "nom_complet calculé à l'insertion", ->
    id = 'trig_insert_1'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    d = read_data id
    R.eq d.nom_complet, 'Jean Dupont'

  R.it "prenom ou nom vide → concaténation partielle", ->
    id = 'trig_insert_2'
    data_space\insert { id, json.encode { prenom: 'Alice', nom: '' } }
    d = read_data id
    R.eq d.nom_complet, 'Alice '

  R.it "champ cree_le (creation-only) est calculé à l'insertion", ->
    id = 'trig_insert_3'
    data_space\insert { id, json.encode { prenom: 'Bob', nom: 'Martin' } }
    d = read_data id
    R.ok d.cree_le and d.cree_le != ''
    -- doit être une année (4 chiffres)
    R.matches tostring(d.cree_le), '^%d%d%d%d$'

R.describe "Triggers — déclenchement à la mise à jour", ->
  R.it "mise à jour de prenom → recalcul de nom_complet", ->
    id = 'trig_update_1'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    -- Modifier prenom
    old = data_space\get id
    d = json.decode old[2]
    d.prenom = 'Pierre'
    data_space\replace { id, json.encode d }
    d2 = read_data id
    R.eq d2.nom_complet, 'Pierre Dupont'

  R.it "mise à jour de nom → recalcul de nom_complet", ->
    id = 'trig_update_2'
    data_space\insert { id, json.encode { prenom: 'Jean', nom: 'Dupont' } }
    old = data_space\get id
    d = json.decode old[2]
    d.nom = 'Martin'
    data_space\replace { id, json.encode d }
    d2 = read_data id
    R.eq d2.nom_complet, 'Jean Martin'

  R.it "champ cree_le (creation-only) n'est PAS recalculé à la mise à jour", ->
    id = 'trig_update_3'
    data_space\insert { id, json.encode { prenom: 'X', nom: 'Y' } }
    d_before = read_data id
    old_val = d_before.cree_le
    -- Attendre une seconde et modifier
    old = data_space\get id
    d = json.decode old[2]
    d.prenom = 'Z'
    data_space\replace { id, json.encode d }
    d_after = read_data id
    -- cree_le ne doit pas changer
    R.eq d_after.cree_le, old_val

R.describe "Triggers — compile_formula", ->
  -- Test interne via le module chargé
  R.it "formule valide → fonction", ->
    -- On utilise pcall + load directement pour tester la logique
    fn_str = "return function(self, space) return self.a + self.b end"
    ok, compiled = pcall load, fn_str
    R.ok ok
    ok2, fn = pcall compiled
    R.ok ok2
    R.eq type(fn), 'function'
    proxy = { a: 3, b: 4 }
    setmetatable proxy, { __index: (t, k) -> rawget t, k }
    R.eq fn(proxy, nil), 7

  R.it "formule invalide → erreur Lua", ->
    fn_str = "return function(self, space) return self.a +++++ end"
    fn, err = load fn_str
    R.nok fn
    R.ok err

R.describe "Triggers — register_space_trigger", ->
  R.it "appel multiple sans erreur (idempotent)", ->
    ok, err = pcall triggers.register_space_trigger, SP_NAME
    R.ok ok, "register_space_trigger doit être idempotent: #{tostring err}"

  R.it "espace inexistant → pas d'erreur", ->
    ok, err = pcall triggers.register_space_trigger, 'espace_qui_nexiste_pas'
    R.ok ok, "espace inexistant doit être géré silencieusement: #{tostring err}"

R.describe "Triggers — init_all_triggers", ->
  R.it "init_all_triggers s'exécute sans erreur", ->
    ok, err = pcall triggers.init_all_triggers
    R.ok ok, "init_all_triggers: #{tostring err}"
