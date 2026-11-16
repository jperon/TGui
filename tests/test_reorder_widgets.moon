-- tests/test_reorder_widgets.moon
-- Tests for the reorderWidgets mutation

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
spaces = require 'core.spaces'
yaml = require 'yaml'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_reorder_cv_#{SUFFIX}"
SPACE_NAME = "test_reorder_space_#{SUFFIX}"

local cv_id, space_id, plugin_cv_id
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "ReorderWidgets — setup test space", ->
  R.it "create test space for reorder tests", ->
    space = spaces.create_user_space SPACE_NAME, 'Test space for reorder', CTX.user_id
    R.ok space
    R.ok space.id
    R.eq space.name, SPACE_NAME
    space_id = space.id

    -- Ajouter des champs
    spaces.add_field space_id, 'id', 'Sequence'
    spaces.add_field space_id, 'name', 'String', false, ''

R.describe "ReorderWidgets — creation", ->
  R.it "createCustomView with multiple widgets", ->
    yaml_content = [[
layout:
  direction: vertical
  children:
    - widget:
        id: widget1
        title: First Widget
        space: #{SPACE_NAME}
        position: 1
    - widget:
        id: widget2
        title: Second Widget
        space: #{SPACE_NAME}
        position: 2
    - widget:
        id: widget3
        title: Third Widget
        space: #{SPACE_NAME}
        position: 3
]]
    res = cvr.Mutation.createCustomView {}, { name: CV_NAME, description: 'test', yaml: yaml_content }, CTX
    R.ok res
    R.ok res.id
    cv_id = res.id

R.describe "ReorderWidgets — basic reordering", ->
  R.it "reorderWidgets changes widget order", ->
    -- Réordonner : widget2, widget1, widget3
    widget_positions = {
      { widgetId: 'widget2', index: 1 }
      { widgetId: 'widget1', index: 2 }
      { widgetId: 'widget3', index: 3 }
    }

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res
    R.ok res.id, cv_id
    R.ok res.yaml

    -- Vérifier le nouvel ordre dans le YAML
    R.ok res.yaml\find("id: widget2"), "widget2 should be first"
    R.ok res.yaml\find("id: widget1"), "widget1 should be second"
    R.ok res.yaml\find("id: widget3"), "widget3 should be third"

    -- Vérifier que les positions ont été mises à jour
    R.ok res.yaml\find("position: 1"), "first widget should have position 1"
    R.ok res.yaml\find("position: 2"), "second widget should have position 2"
    R.ok res.yaml\find("position: 3"), "third widget should have position 3"

  R.it "reorderWidgets with same order keeps same YAML", ->
    -- Réordonner avec le même ordre
    widget_positions = {
      { widgetId: 'widget2', index: 1 }
      { widgetId: 'widget1', index: 2 }
      { widgetId: 'widget3', index: 3 }
    }

    original_view = cvr.Query.customView {}, { id: cv_id }, CTX
    original_yaml = original_view.yaml

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res
    R.eq res.yaml, original_yaml

R.describe "ReorderWidgets — widget personnalisé (plugin)", ->
  R.it "reorderWidgets keeps type and params of plugin widgets", ->
    yaml_content = "layout:\n" ..
      "  direction: vertical\n" ..
      "  children:\n" ..
      "    - widget:\n" ..
      "        id: plugin_w\n" ..
      "        title: Calendrier\n" ..
      "        space: #{SPACE_NAME}\n" ..
      "        position: 1\n" ..
      "        type: mon_plugin\n" ..
      "        params:\n" ..
      "          couleur: '#c33'\n" ..
      "    - zone:\n" ..
      "        id: zone_a\n" ..
      "        title: Zone A\n" ..
      "        direction: vertical\n" ..
      "        children:\n" ..
      "          - widget:\n" ..
      "              id: plugin_in_zone\n" ..
      "              title: Dans une zone\n" ..
      "              space: #{SPACE_NAME}\n" ..
      "              position: 1\n" ..
      "              type: mon_plugin\n" ..
      "              params:\n" ..
      "                titre: Zone\n"
    created = cvr.Mutation.createCustomView {}, { name: "#{CV_NAME}_plugin", yaml: yaml_content }, CTX
    R.ok created
    plugin_cv_id = created.id

    widget_positions = { { widgetId: 'plugin_w', index: 2 } }
    res = cvr.Mutation.reorderWidgets {}, { pageId: plugin_cv_id, widgetPositions: widget_positions }, CTX
    R.ok res.yaml

    -- Le YAML réécrit doit rester lisible et conserver type + params, y compris
    -- pour un widget placé dans une zone.
    parsed = yaml.decode res.yaml
    widgets = {}
    collect = (node) ->
      return unless type(node) == 'table'
      table.insert widgets, node.widget if node.widget
      for key, value in pairs node
        collect value if key != 'widget'
    collect parsed.layout

    by_id = {}
    for w in *widgets
      by_id[w.id] = w
    R.ok by_id.plugin_w, "le widget racine doit survivre au réordonnancement"
    R.eq by_id.plugin_w.type, 'mon_plugin'
    R.eq by_id.plugin_w.params.couleur, '#c33'
    R.ok by_id.plugin_in_zone, "le widget de la zone doit survivre au réordonnancement"
    R.eq by_id.plugin_in_zone.type, 'mon_plugin'
    R.eq by_id.plugin_in_zone.params.titre, 'Zone'

R.describe "ReorderWidgets — error handling", ->
  R.it "reorderWidgets on unknown page -> error", ->
    widget_positions = { { widgetId: 'widget1', index: 1 } }
    R.raises (-> cvr.Mutation.reorderWidgets {}, { pageId: 'no-such-id', widgetPositions: widget_positions }, CTX), 'not found'

  R.it "reorderWidgets with invalid widget ID -> error", ->
    widget_positions = { { widgetId: 'invalid-widget', index: 1 } }
    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res  -- Ne devrait pas planter, mais ignorer les widgets invalides

  R.it "reorderWidgets with empty positions -> no change", ->
    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: {} }, CTX
    R.ok res
    R.ok res.yaml

R.describe "ReorderWidgets — edge cases", ->
  R.it "reorderWidgets reverse order", ->
    -- Inverser l'ordre
    widget_positions = {
      { widgetId: 'widget3', index: 1 }
      { widgetId: 'widget1', index: 2 }
      { widgetId: 'widget2', index: 3 }
    }

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res

    -- Vérifier l'ordre inversé
    lines = res.yaml\split('\n')
    widget1_pos = nil
    widget2_pos = nil
    widget3_pos = nil

    for i, line in ipairs(lines)
      if line\match("id: widget1") then widget1_pos = i
      if line\match("id: widget2") then widget2_pos = i
      if line\match("id: widget3") then widget3_pos = i

    R.ok widget3_pos < widget1_pos, "widget3 should come before widget1"
    R.ok widget1_pos < widget2_pos, "widget1 should come before widget2"

  R.it "reorderWidgets with partial positions", ->
    -- Seulement réordonner certains widgets
    widget_positions = {
      { widgetId: 'widget1', index: 1 }
      { widgetId: 'widget3', index: 2 }
    }

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res
    R.ok res.yaml

R.describe "ReorderWidgets — cleanup", ->
  R.it "cleanup test space and page", ->
    if plugin_cv_id
      cvr.Mutation.deleteCustomView {}, { id: plugin_cv_id }, CTX
    if cv_id
      cvr.Mutation.deleteCustomView {}, { id: cv_id }, CTX
    if space_id
      spaces.delete_user_space space_id
