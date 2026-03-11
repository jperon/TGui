-- tests/test_custom_views.moon
-- Tests des opérations CRUD sur les vues personnalisées (resolvers/custom_view_resolvers.moon).
-- Nécessite Tarantool (box déjà initialisé dans run.moon).

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_cv_#{SUFFIX}"

YAML_SIMPLE = [[
layout:
  direction: vertical
  children:
    - widget:
        title: Test
        space: test
]]

YAML_FACTOR = [[
layout:
  direction: horizontal
  children:
    - factor: 2
      widget:
        title: A
        space: test
    - factor: 1
      widget:
        title: B
        space: test
        columns: [nom, prenom]
]]

local cv_id
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "CustomViews — création", ->
  R.it "createCustomView retourne les métadonnées", ->
    res = cvr.Mutation.createCustomView {}, { input: { name: CV_NAME, description: 'test', yaml: YAML_SIMPLE } }, CTX
    R.ok res
    R.ok res.id
    R.eq res.name, CV_NAME
    R.eq res.description, 'test'
    R.eq res.yaml, YAML_SIMPLE
    cv_id = res.id

  R.it "customViews liste inclut la vue créée", ->
    found = false
    for v in *cvr.Query.customViews({}, {}, CTX)
      if v.id == cv_id then found = true
    R.ok found

  R.it "customView retourne la vue par id", ->
    v = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok v
    R.eq v.id, cv_id
    R.eq v.name, CV_NAME

R.describe "CustomViews — mise à jour", ->
  R.it "updateCustomView modifie le nom et le yaml", ->
    res = cvr.Mutation.updateCustomView {}, { id: cv_id, input: { name: CV_NAME .. '_v2', yaml: YAML_FACTOR } }, CTX
    R.ok res
    R.eq res.name, CV_NAME .. '_v2'
    R.eq res.yaml, YAML_FACTOR

  R.it "updateCustomView avec champs partiels conserve les anciens", ->
    res = cvr.Mutation.updateCustomView {}, { id: cv_id, input: { name: CV_NAME .. '_v2' } }, CTX
    R.ok res
    R.eq res.yaml, YAML_FACTOR  -- yaml non fourni → conservé

  R.it "updateCustomView sur id inexistant → erreur", ->
    R.raises (-> cvr.Mutation.updateCustomView {}, { id: 'no-such-id', input: { name: 'x' } }, CTX), 'not found'

R.describe "CustomViews — suppression", ->
  R.it "deleteCustomView retourne true", ->
    ok = cvr.Mutation.deleteCustomView {}, { id: cv_id }, CTX
    R.ok ok

  R.it "la vue supprimée n'apparaît plus dans la liste", ->
    found = false
    for v in *cvr.Query.customViews({}, {}, CTX)
      if v.id == cv_id then found = true
    R.nok found

  R.it "customView sur id supprimé retourne nil", ->
    v = cvr.Query.customView {}, { id: cv_id }, CTX
    R.is_nil v
