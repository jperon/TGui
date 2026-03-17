-- tests/test_change_parent.moon
-- Tests for changing widget parent via reorderWidgets mutation

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
spaces = require 'core.spaces'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_change_parent_cv_#{SUFFIX}"
SPACE_NAME = "test_change_parent_space_#{SUFFIX}"

local cv_id, space_id
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "ChangeParent — setup test space", ->
  R.it "create test space for change parent tests", ->
    space = spaces.create_user_space SPACE_NAME, 'Test space for change parent', CTX.user_id
    R.ok space
    R.ok space.id
    R.eq space.name, SPACE_NAME
    space_id = space.id

    spaces.add_field space_id, 'id', 'Sequence'
    spaces.add_field space_id, 'name', 'String', false, ''

R.describe "ChangeParent — creation", ->
  R.it "createCustomView with zones and widgets", ->
    yaml_content = [[
layout:
  direction: vertical
  children:
    - zone:
        id: zone1
        title: First Zone
        factor: 0.5
        direction: vertical
        children:
          - widget:
              id: widget1
              title: Widget 1
              space: #{SPACE_NAME}
              position: 1
    - zone:
        id: zone2
        title: Second Zone
        factor: 0.5
        direction: vertical
        children:
          - widget:
              id: widget2
              title: Widget 2
              space: #{SPACE_NAME}
              position: 1
]]
    res = cvr.Mutation.createCustomView {}, { name: CV_NAME, description: 'test', yaml: yaml_content }, CTX
    R.ok res
    R.ok res.id
    cv_id = res.id

R.describe "ChangeParent — moving widget between zones", ->
  R.it "move widget from one zone to another", ->
    widget_positions = {
      { widgetId: 'widget1', index: 1, parentId: 'zone2' }
      { widgetId: 'widget2', index: 2, parentId: 'zone2' }
    }

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res
    R.ok res.id
    R.ok res.yaml

    view = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok view.yaml

    yaml_str = view.yaml
    R.ok yaml_str\find("zone2"), "zone2 should still exist"
    R.ok yaml_str\find("widget1"), "widget1 should still exist"
    R.ok yaml_str\find("widget2"), "widget2 should still exist"

  R.it "move widget from zone to root", ->
    widget_positions = {
      { widgetId: 'widget2', index: 1, parentId: null }
    }

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res
    R.ok res.yaml

R.describe "ChangeParent — error handling", ->
  R.it "move widget to non-existent zone -> handled gracefully", ->
    widget_positions = {
      { widgetId: 'widget1', index: 1, parentId: 'nonexistent-zone' }
    }

    res = cvr.Mutation.reorderWidgets {}, { pageId: cv_id, widgetPositions: widget_positions }, CTX
    R.ok res

R.describe "ChangeParent — cleanup", ->
  R.it "cleanup test space and page", ->
    if cv_id
      cvr.Mutation.deleteCustomView {}, { id: cv_id }, CTX
    if space_id
      spaces.delete_user_space space_id
