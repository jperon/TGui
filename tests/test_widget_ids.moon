-- tests/test_widget_ids.moon
-- Tests core/widget_ids: every widget of a page YAML text carries a stable id,
-- both directly (ensure_widget_ids) and through the before_replace trigger of
-- _tdb_custom_views. Widget ids are the key of the widget-scoped records
-- (named view presets: scope 'widget:<pageId>:<widgetId>').

R    = require 'tests.runner'
wid  = require 'core.widget_ids'
cvr  = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
yaml = require 'yaml'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_widget_ids_#{SUFFIX}"

FIX = { cv_id: nil, first_id: nil, extra_pages: {} }
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

-- ── Fixtures ─────────────────────────────────────────────────────────────────

YAML_NO_ID = [[
layout:
  direction: vertical
  children:
    - widget:
        title: Test
        space: test
]]

YAML_WITH_ID = [[
layout:
  direction: vertical
  children:
    - widget:
        id: kept_widget
        title: Test
        space: test
]]

YAML_EMPTY_ID = [[
layout:
  direction: vertical
  children:
    - widget:
        id: ''
        title: Test
        space: test
]]

YAML_TWO_WIDGETS = [[
layout:
  direction: horizontal
  children:
    - widget:
        title: A
        space: test
    - factor: 1
      widget:
        title: B
        space: test
]]

YAML_NESTED_ZONES = [[
layout:
  direction: horizontal
  children:
    - zone:
        id: zone_a
        factor: 1
        direction: vertical
        children:
          - widget:
              title: A
              space: test
    - zone:
        id: zone_b
        factor: 1
        direction: vertical
        children:
          - widget:
              title: B
              space: test
]]

YAML_WITH_COMMENT = [[
layout:
  direction: vertical
  # commentaire conserve
  children:
    - widget:
        title: Test
        space: test
]]

-- Flat list of widget ids of a YAML text, in render order.
ids_of = (text) ->
  config = yaml.decode text
  ids = {}
  for widget in *wid.collect_widgets(config)
    table.insert ids, tostring widget.id
  ids

-- ── Units ────────────────────────────────────────────────────────────────────

R.describe "WidgetIds — normalisation du texte YAML", ->
  R.it "attribue w_ + 8 hexadécimaux à un widget sans id", ->
    new_yaml, changed = wid.ensure_widget_ids YAML_NO_ID
    R.ok changed, 'changed'
    R.ne new_yaml, YAML_NO_ID, 'texte modifié'
    ids = ids_of new_yaml
    R.eq #ids, 1
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'
    R.ok new_yaml\find('id: ' .. ids[1], 1, true), 'id écrit dans le texte'

  R.it "conserve un id existant", ->
    new_yaml, changed = wid.ensure_widget_ids YAML_WITH_ID
    R.nok changed, 'changed'
    R.eq new_yaml, YAML_WITH_ID
    R.eq (ids_of new_yaml)[1], 'kept_widget'

  R.it "remplit un id vide sans dupliquer la clé", ->
    new_yaml, changed = wid.ensure_widget_ids YAML_EMPTY_ID
    R.ok changed, 'changed'
    ids = ids_of new_yaml
    R.eq #ids, 1
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'
    line_count = 0
    for line in *[l for l in new_yaml\gmatch '[^\n]+' when l\match '^%s*id%s*:']
      line_count += 1
    R.eq line_count, 1, 'une seule ligne id'

  R.it "attribue des ids distincts à deux widgets", ->
    new_yaml, changed = wid.ensure_widget_ids YAML_TWO_WIDGETS
    R.ok changed, 'changed'
    ids = ids_of new_yaml
    R.eq #ids, 2
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'
    R.matches ids[2], '^w_%x%x%x%x%x%x%x%x$'
    R.ne ids[1], ids[2], 'ids distincts'

  R.it "couvre les widgets des zones imbriquées", ->
    new_yaml, changed = wid.ensure_widget_ids YAML_NESTED_ZONES
    R.ok changed, 'changed'
    ids = ids_of new_yaml
    R.eq #ids, 2
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'
    R.matches ids[2], '^w_%x%x%x%x%x%x%x%x$'
    R.ne ids[1], ids[2], 'ids distincts'

  R.it "remplace le placeholder id: nil écrit par l'ancien encodeur", ->
    legacy = [[
layout:
  direction: vertical
  children:
    - widget:
        id: nil
        title: Test
        space: test
]]
    new_yaml, changed = wid.ensure_widget_ids legacy
    R.ok changed, 'changed'
    ids = ids_of new_yaml
    R.eq #ids, 1
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'
    R.nok new_yaml\find('id: nil', 1, true), 'placeholder remplacé'
    R.ok new_yaml\find('title: Test', 1, true), 'reste du widget conservé'

  R.it "préserve les commentaires écrits à la main", ->
    new_yaml, changed = wid.ensure_widget_ids YAML_WITH_COMMENT
    R.ok changed, 'changed'
    R.ok new_yaml\find('# commentaire conserve', 1, true), 'commentaire conservé'
    R.eq #ids_of(new_yaml), 1

  R.it "renvoie tel quel un YAML invalide", ->
    invalid = "layout: [unclosed\n  bad"
    new_yaml, changed = wid.ensure_widget_ids invalid
    R.nok changed, 'changed'
    R.eq new_yaml, invalid

  R.it "renvoie tel quel un YAML vide ou sans layout", ->
    new_yaml, changed = wid.ensure_widget_ids ''
    R.nok changed
    R.eq new_yaml, ''
    no_layout = "foo: bar\n"
    new_yaml, changed = wid.ensure_widget_ids no_layout
    R.nok changed
    R.eq new_yaml, no_layout

  R.it "est idempotent", ->
    once, first_changed = wid.ensure_widget_ids YAML_TWO_WIDGETS
    R.ok first_changed, 'premier passage modifie'
    twice, second_changed = wid.ensure_widget_ids once
    R.nok second_changed, 'second passage sans changement'
    R.eq twice, once, 'texte stable'

-- ── Integration (trigger on _tdb_custom_views) ───────────────────────────────

R.describe "WidgetIds — intégration GraphQL", ->
  R.it "createCustomView stocke un id pour chaque widget", ->
    res = cvr.Mutation.createCustomView {}, { name: CV_NAME, description: 'widget ids', yaml: YAML_NO_ID }, CTX
    R.ok res
    R.ok res.id
    FIX.cv_id = res.id

    stored = cvr.Query.customView {}, { id: FIX.cv_id }, CTX
    ids = ids_of stored.yaml
    R.eq #ids, 1
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'
    FIX.first_id = ids[1]

  R.it "un widget ajouté par updateCustomView reçoit un id neuf", ->
    stored = cvr.Query.customView {}, { id: FIX.cv_id }, CTX
    extended = stored.yaml .. "    - widget:\n        title: Second\n        space: test\n"
    res = cvr.Mutation.updateCustomView {}, { id: FIX.cv_id, input: { yaml: extended } }, CTX
    R.ok res

    again = cvr.Query.customView {}, { id: FIX.cv_id }, CTX
    ids = ids_of again.yaml
    R.eq #ids, 2
    R.eq ids[1], FIX.first_id, 'id existant conservé'
    R.matches ids[2], '^w_%x%x%x%x%x%x%x%x$'
    R.ne ids[1], ids[2], 'ids distincts'

  R.it "updateCustomView qui conserve les id ne les change pas", ->
    stored = cvr.Query.customView {}, { id: FIX.cv_id }, CTX
    res = cvr.Mutation.updateCustomView {}, { id: FIX.cv_id, input: { yaml: stored.yaml } }, CTX
    R.ok res
    again = cvr.Query.customView {}, { id: FIX.cv_id }, CTX
    R.eq again.yaml, stored.yaml, 'texte inchangé'

  R.it "un id vide stocké est rempli", ->
    res = cvr.Mutation.createCustomView {}, { name: CV_NAME .. '_empty', description: 'empty id', yaml: YAML_EMPTY_ID }, CTX
    R.ok res
    table.insert FIX.extra_pages, res.id
    stored = cvr.Query.customView {}, { id: res.id }, CTX
    ids = ids_of stored.yaml
    R.eq #ids, 1
    R.matches ids[1], '^w_%x%x%x%x%x%x%x%x$'

R.describe "WidgetIds — cleanup", ->
  R.it "supprime les pages de test", ->
    if FIX.cv_id
      R.ok cvr.Mutation.deleteCustomView {}, { id: FIX.cv_id }, CTX
    for id in *FIX.extra_pages
      R.ok cvr.Mutation.deleteCustomView {}, { id: id }, CTX
