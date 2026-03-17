local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local spaces = require('core.spaces')
local SUFFIX = tostring(math.random(100000, 999999))
local CV_NAME = "test_change_parent_cv_" .. tostring(SUFFIX)
local SPACE_NAME = "test_change_parent_space_" .. tostring(SUFFIX)
local cv_id, space_id
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
R.describe("ChangeParent — setup test space", function()
  return R.it("create test space for change parent tests", function()
    local space = spaces.create_user_space(SPACE_NAME, 'Test space for change parent', CTX.user_id)
    R.ok(space)
    R.ok(space.id)
    R.eq(space.name, SPACE_NAME)
    space_id = space.id
    spaces.add_field(space_id, 'id', 'Sequence')
    return spaces.add_field(space_id, 'name', 'String', false, '')
  end)
end)
R.describe("ChangeParent — creation", function()
  return R.it("createCustomView with zones and widgets", function()
    local yaml_content = [[layout:
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
    local res = cvr.Mutation.createCustomView({ }, {
      name = CV_NAME,
      description = 'test',
      yaml = yaml_content
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    cv_id = res.id
  end)
end)
R.describe("ChangeParent — moving widget between zones", function()
  R.it("move widget from one zone to another", function()
    local widget_positions = {
      {
        widgetId = 'widget1',
        index = 1,
        parentId = 'zone2'
      },
      {
        widgetId = 'widget2',
        index = 2,
        parentId = 'zone2'
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    R.ok(res.yaml)
    local view = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    R.ok(view.yaml)
    local yaml_str = view.yaml
    R.ok(yaml_str:find("zone2"), "zone2 should still exist")
    R.ok(yaml_str:find("widget1"), "widget1 should still exist")
    return R.ok(yaml_str:find("widget2"), "widget2 should still exist")
  end)
  return R.it("move widget from zone to root", function()
    local widget_positions = {
      {
        widgetId = 'widget2',
        index = 1,
        parentId = null
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res)
    return R.ok(res.yaml)
  end)
end)
R.describe("ChangeParent — error handling", function()
  return R.it("move widget to non-existent zone -> handled gracefully", function()
    local widget_positions = {
      {
        widgetId = 'widget1',
        index = 1,
        parentId = 'nonexistent-zone'
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    return R.ok(res)
  end)
end)
return R.describe("ChangeParent — cleanup", function()
  return R.it("cleanup test space and page", function()
    if cv_id then
      cvr.Mutation.deleteCustomView({ }, {
        id = cv_id
      }, CTX)
    end
    if space_id then
      return spaces.delete_user_space(space_id)
    end
  end)
end)
