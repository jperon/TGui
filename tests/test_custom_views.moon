-- tests/test_custom_views.moon
-- Tests CRUD operations on custom views (resolvers/custom_view_resolvers.moon).
-- Requires Tarantool (box already initialized in run.moon).

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
spaces = require 'core.spaces'
yaml = require 'yaml'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_cv_#{SUFFIX}"
SPACE_NAME = "test_space_#{SUFFIX}"

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

local cv_id, space_id
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "CustomViews — setup test space", ->
  R.it "create test space for widget tests", ->
    space = spaces.create_user_space SPACE_NAME, 'Test space for widgets', CTX.user_id
    R.ok space
    R.ok space.id
    R.eq space.name, SPACE_NAME
    space_id = space.id

    -- Ajouter un champ "name" pour les tests
    fields = {
      { name: 'id', type: 'Sequence', position: 1, not_null: true }
      { name: 'name', type: 'String', position: 2, not_null: false }
    }
    for field in *fields
      if field.type == 'Sequence'
        spaces.add_field space_id, field.name, 'Sequence'
      else
        spaces.add_field space_id, field.name, field.type, false, ''

R.describe "CustomViews — creation", ->
  R.it "createCustomView returns metadata", ->
    res = cvr.Mutation.createCustomView {}, { name: CV_NAME, description: 'test', yaml: YAML_SIMPLE }, CTX
    R.ok res
    R.ok res.id
    R.eq res.name, CV_NAME
    R.eq res.description, 'test'
    R.eq res.yaml, YAML_SIMPLE
    cv_id = res.id

  R.it "customViews list includes created view", ->
    found = false
    for v in *cvr.Query.customViews({}, {}, CTX)
      if v.id == cv_id then found = true
    R.ok found

  R.it "customView returns the view by id", ->
    v = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok v
    R.eq v.id, cv_id
    R.eq v.name, CV_NAME

R.describe "CustomViews — update", ->
  R.it "updateCustomView updates name and yaml", ->
    res = cvr.Mutation.updateCustomView {}, { id: cv_id, input: { name: CV_NAME .. '_v2', yaml: YAML_FACTOR } }, CTX
    R.ok res
    R.eq res.name, CV_NAME .. '_v2'
    R.eq res.yaml, YAML_FACTOR

  R.it "updateCustomView with partial fields keeps previous values", ->
    res = cvr.Mutation.updateCustomView {}, { id: cv_id, input: { name: CV_NAME .. '_v2' } }, CTX
    R.ok res
    -- yaml not provided -> preserved; each widget also carries the id assigned
    -- at storage time (core/widget_ids), so compare the structure, not the text.
    kept = yaml.decode res.yaml
    saved = yaml.decode YAML_FACTOR
    R.eq #(kept.layout.children), #(saved.layout.children)
    for i, child in ipairs saved.layout.children
      R.eq kept.layout.children[i].widget.title, child.widget.title
      R.eq kept.layout.children[i].factor, child.factor
      R.matches tostring(kept.layout.children[i].widget.id), '^w_%x%x%x%x%x%x%x%x$'

  R.it "updateCustomView on unknown id -> error", ->
    R.raises (-> cvr.Mutation.updateCustomView {}, { id: 'no-such-id', input: { name: 'x' } }, CTX), 'not found'

R.describe "CustomViews — addWidgetToView", ->
  R.it "addWidgetToView adds widget to existing view", ->
    -- Créer une vue vide
    empty_yaml = [[
layout:
  direction: vertical
  children: []
]]
    cv = cvr.Mutation.createCustomView {}, { name: "test_widget_cv_#{SUFFIX}", yaml: empty_yaml }, CTX
    cv_id = cv.id

    -- Ajouter un widget
    widget_input =
      title: "Test Widget"
      type: "table"
      spaceId: space_id  -- utiliser l'espace de test créé précédemment
      fields: {"id", "name"}
      groupBy: null
      params: {}

    res = cvr.Mutation.addWidgetToView {}, { viewId: cv_id, widget: widget_input }, CTX
    R.ok res
    R.ok res.id, cv_id
    R.ok res.yaml

    -- Vérifier que le YAML contient le widget avec le nom de l'espace
    R.ok res.yaml\find("space: #{SPACE_NAME}"), "doit contenir le nom de l'espace, pas l'UUID"
    R.ok res.yaml\find("title: Test Widget"), "doit contenir le titre du widget"
    R.ok res.yaml\find("columns:"), "doit contenir la section columns"
    R.ok res.yaml\find("- id"), "doit contenir la colonne id"
    R.ok res.yaml\find("- name"), "doit contenir la colonne name"

  R.it "addWidgetToView on unknown view -> error", ->
    widget_input = title: "Test", type: "table", spaceId: space_id, fields: {"id"}
    R.raises (-> cvr.Mutation.addWidgetToView {}, { viewId: 'no-such-id', widget: widget_input }, CTX), 'not found'

  R.it "addWidgetToView keeps a custom widget type and params in the YAML", ->
    empty_yaml = [[
layout:
  direction: vertical
  children: []
]]
    cv = cvr.Mutation.createCustomView {}, { name: "test_plugin_cv_#{SUFFIX}", yaml: empty_yaml }, CTX

    -- Un widget personnalisé : pas de colonnes, `type` = nom du plugin, et des
    -- paramètres libres (valeurs avec apostrophe et « # » pour le YAML).
    widget_input =
      title: "Calendrier"
      type: "mon_plugin"
      spaceId: space_id
      fields: {}
      params: { couleur: '#c33', titre: "L'été" }

    res = cvr.Mutation.addWidgetToView {}, { viewId: cv.id, widget: widget_input }, CTX
    R.ok res.yaml

    parsed = yaml.decode res.yaml
    R.eq #(parsed.layout.children), 1
    node = parsed.layout.children[1].widget
    R.eq node.type, 'mon_plugin'
    R.eq node.params.couleur, '#c33'
    R.eq node.params.titre, "L'été"
    R.eq node.space, SPACE_NAME
    R.ok node.id, "le nœud YAML doit garder son identifiant"
    R.eq node.columns, nil

    cvr.Mutation.deleteCustomView {}, { id: cv.id }, CTX

  R.it "addWidgetToView accepts a layout position without breaking the YAML", ->
    empty_yaml = [[
layout:
  direction: vertical
  children: []
]]
    cv = cvr.Mutation.createCustomView {}, { name: "test_pos_cv_#{SUFFIX}", yaml: empty_yaml }, CTX

    -- La fenêtre « ＋ Widget » envoie { x, y, w, h } : la page est une liste
    -- ordonnée, le YAML garde un index entier et reste relisible.
    widget_input =
      title: "Avec position"
      type: "table"
      spaceId: space_id
      fields: {"id"}
      position: { x: 0, y: 0, w: 6, h: 4 }

    res = cvr.Mutation.addWidgetToView {}, { viewId: cv.id, widget: widget_input }, CTX
    parsed = yaml.decode res.yaml
    node = parsed.layout.children[1].widget
    R.eq node.position, 1
    R.eq node.title, 'Avec position'

    cvr.Mutation.deleteCustomView {}, { id: cv.id }, CTX

R.describe "CustomViews — deletion", ->
  R.it "deleteCustomView returns true", ->
    if cv_id
      ok = cvr.Mutation.deleteCustomView {}, { id: cv_id }, CTX
      R.ok ok

  R.it "deleted view no longer appears in list", ->
    if cv_id
      found = false
      for v in *cvr.Query.customViews({}, {}, CTX)
        if v.id == cv_id then found = true
      R.nok found

  R.it "customView on deleted id returns nil", ->
    if cv_id
      v = cvr.Query.customView {}, { id: cv_id }, CTX
      R.eq v, nil

R.describe "CustomViews — cleanup", ->
  R.it "cleanup test space", ->
    if space_id
      spaces.delete_user_space space_id
