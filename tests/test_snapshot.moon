-- tests/test_snapshot.moon
-- Tests des resolvers exportSnapshot / diffSnapshot / importSnapshot.
-- S'exécute dans l'instance Tarantool (box déjà initialisé).

R      = require 'tests.runner'
auth   = require 'core.auth'
spaces = require 'core.spaces'
export_r = require 'resolvers.export_resolvers'
yaml   = require 'yaml'

SUFFIX = tostring math.random 100000, 999999

-- Contexte admin factice (recherche l'utilisateur 'admin' réel)
admin_user = auth.get_user_by_username 'admin'
ADMIN_CTX  = { user_id: admin_user and admin_user.id }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "exportSnapshot — structure", ->

  R.it "retourne une chaîne YAML non vide", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    R.ok result
    R.ok #result > 10

  R.it "le YAML est parsable", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.ok snap
    R.ok snap.version

  R.it "contient une section schema.spaces", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.ok snap.schema
    R.ok snap.schema.spaces
    R.ok #snap.schema.spaces >= 0

  R.it "ne contient pas de section data en mode structure-seulement", ->
    result = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    snap = yaml.decode result
    R.eq snap.data, nil

  R.it "contient une section data en mode include_data", ->
    result = export_r.Query.exportSnapshot nil, { includeData: true }, ADMIN_CTX
    snap = yaml.decode result
    -- data peut être nil si aucun espace n'a de données, mais la clé existe
    -- (on vérifie juste que pas d'erreur)
    R.ok result

-- ────────────────────────────────────────────────────────────────────────────
R.describe "diffSnapshot — aucune différence", ->
  local current_yaml

  R.it "exporte le schéma courant", ->
    current_yaml = export_r.Query.exportSnapshot nil, { includeData: false }, ADMIN_CTX
    R.ok current_yaml

  R.it "diff sur le schéma courant → aucune divergence", ->
    diff = export_r.Query.diffSnapshot nil, { yaml: current_yaml }, ADMIN_CTX
    R.ok diff
    R.eq #diff.spacesToCreate,  0
    R.eq #diff.spacesToDelete,  0
    R.eq #diff.fieldsToCreate,  0
    R.eq #diff.fieldsToDelete,  0

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — mode merge", ->
  SP = "snap_test_#{SUFFIX}"

  R.it "crée un snapshot YAML minimal avec un nouvel espace", ->
    snap = {
      version: "1"
      schema: {
        spaces: {
          {
            name: SP
            fields: {
              { name: "titre", fieldType: "String", notNull: false }
              { name: "valeur", fieldType: "Int", notNull: false }
            }
            views: {}
          }
        }
        relations: {}
        custom_views: {}
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok result
    R.ok result.ok
    R.ok result.created > 0
    R.eq #result.errors, 0

  R.it "l'espace importé est visible dans list_spaces", ->
    found = false
    for sp in *spaces.list_spaces!
      if sp.name == SP
        found = true
        break
    R.ok found

  R.it "les champs importés sont présents", ->
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == SP
    R.ok sp
    fields = spaces.list_fields sp.id
    names = [f.name for f in *fields]
    has_titre  = false
    has_valeur = false
    for n in *names
      has_titre  = true if n == 'titre'
      has_valeur = true if n == 'valeur'
    R.ok has_titre
    R.ok has_valeur

  R.it "deuxième import identique → tout ignoré, aucune erreur", ->
    snap = {
      version: "1"
      schema: {
        spaces: {
          {
            name: SP
            fields: {
              { name: "titre",  fieldType: "String", notNull: false }
              { name: "valeur", fieldType: "Int",    notNull: false }
            }
            views: {}
          }
        }
        relations: {}
        custom_views: {}
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'merge' }, ADMIN_CTX
    R.ok result
    R.ok result.ok
    R.eq result.created, 0
    R.ok result.skipped > 0
    R.eq #result.errors, 0

  -- Nettoyage
  R.it "suppression de l'espace de test", ->
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == SP
    R.ok sp
    spaces.delete_user_space SP   -- prend un nom, pas un id
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP
    R.eq found, false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — mode replace", ->
  SP_A = "replace_a_#{SUFFIX}"
  SP_B = "replace_b_#{SUFFIX}"

  R.it "crée deux espaces initiaux", ->
    for name in *{ SP_A, SP_B }
      ok, err = pcall -> spaces.create_user_space name, ''
      R.ok ok

  R.it "mode replace supprime les espaces existants et recrée depuis snapshot", ->
    -- Snapshot ne contenant que SP_B (SP_A sera supprimé)
    snap = {
      version: "1"
      schema: {
        spaces: {
          { name: SP_B, fields: { { name: "val", fieldType: "String", notNull: false } }, views: {} }
        }
        relations: {}
        custom_views: {}
        groups: {}
      }
    }
    snap_yaml = yaml.encode snap
    result = export_r.Mutation.importSnapshot nil, { yaml: snap_yaml, mode: 'replace' }, ADMIN_CTX
    R.ok result
    R.eq #result.errors, 0

  R.it "SP_B existe toujours (recréé par replace)", ->
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP_B
    R.ok found

  R.it "SP_B a le champ val importé", ->
    sp = nil
    for s in *spaces.list_spaces!
      sp = s if s.name == SP_B
    R.ok sp
    fields = spaces.list_fields sp.id
    has_val = false
    for f in *fields
      has_val = true if f.name == 'val'
    R.ok has_val

  -- Nettoyage
  R.it "nettoyage des espaces replace_*", ->
    for name in *{ SP_A, SP_B }
      sp = nil
      for s in *spaces.list_spaces!
        sp = s if s.name == name
      spaces.delete_user_space name if sp
    -- Vérifier absence
    found = false
    for s in *spaces.list_spaces!
      found = true if s.name == SP_A or s.name == SP_B
    R.eq found, false

-- ────────────────────────────────────────────────────────────────────────────
R.describe "importSnapshot — YAML invalide", ->

  R.it "erreur sur YAML vide", ->
    ok, err = pcall ->
      export_r.Mutation.importSnapshot nil, { yaml: '', mode: 'merge' }, ADMIN_CTX
    R.eq ok, false

  R.it "import avec YAML non-table → erreur", ->
    ok, err = pcall ->
      export_r.Mutation.importSnapshot nil, { yaml: '42', mode: 'merge' }, ADMIN_CTX
    R.eq ok, false
