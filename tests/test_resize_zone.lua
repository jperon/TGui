local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local spaces = require('core.spaces')
local SUFFIX = tostring(math.random(100000, 999999))
local CV_NAME = "test_resize_cv_" .. tostring(SUFFIX)
local SPACE_NAME = "test_resize_space_" .. tostring(SUFFIX)
local cv_id, space_id
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
R.describe("ResizeZone — setup test space", function()
  return R.it("create test space for resize tests", function()
    local space = spaces.create_user_space(SPACE_NAME, 'Test space for resize', CTX.user_id)
    R.ok(space)
    R.ok(space.id)
    R.eq(space.name, SPACE_NAME)
    space_id = space.id
    spaces.add_field(space_id, 'id', 'Sequence')
    return spaces.add_field(space_id, 'name', 'String', false, '')
  end)
end)
R.describe("ResizeZone — creation", function()
  return R.it("createCustomView with zones", function()
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
        children: []
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
R.describe("ResizeZone — basic resizing", function()
  R.it("resizeZone changes zone factor", function()
    local res = cvr.Mutation.resizeZone({ }, {
      pageId = cv_id,
      zoneId = 'zone1',
      factor = 0.7
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    local view = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    R.ok(view)
    R.ok(view.yaml)
    return R.ok(view.yaml:find("factor: 0.7"), "zone1 should have factor 0.7")
  end)
  return R.it("resizeZone recalculates sibling factors", function()
    local res = cvr.Mutation.resizeZone({ }, {
      pageId = cv_id,
      zoneId = 'zone1',
      factor = 0.8
    }, CTX)
    R.ok(res)
    local view = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    R.ok(view.yaml)
    return R.ok(view.yaml:find("factor: 0.8"), "zone1 should have factor 0.8")
  end)
end)
R.describe("ResizeZone — error handling", function()
  R.it("resizeZone on unknown page -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        pageId = 'no-such-id',
        zoneId = 'zone1',
        factor = 0.5
      }, CTX)
    end), 'not found')
  end)
  R.it("resizeZone with unknown zone -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        pageId = cv_id,
        zoneId = 'unknown-zone',
        factor = 0.5
      }, CTX)
    end), 'Zone not found')
  end)
  R.it("resizeZone with invalid factor < 0.1 -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        pageId = cv_id,
        zoneId = 'zone1',
        factor = 0.05
      }, CTX)
    end), 'factor must be between')
  end)
  R.it("resizeZone with invalid factor > 1.0 -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        pageId = cv_id,
        zoneId = 'zone1',
        factor = 1.5
      }, CTX)
    end), 'factor must be between')
  end)
  R.it("resizeZone with missing pageId -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        zoneId = 'zone1',
        factor = 0.5
      }, CTX)
    end), 'pageId is required')
  end)
  R.it("resizeZone with missing zoneId -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        pageId = cv_id,
        factor = 0.5
      }, CTX)
    end), 'zoneId is required')
  end)
  return R.it("resizeZone with missing factor -> error", function()
    return R.raises((function()
      return cvr.Mutation.resizeZone({ }, {
        pageId = cv_id,
        zoneId = 'zone1'
      }, CTX)
    end), 'factor is required')
  end)
end)
R.describe("ResizeZone — edge cases", function()
  R.it("resizeZone with minimum factor 0.1", function()
    local res = cvr.Mutation.resizeZone({ }, {
      pageId = cv_id,
      zoneId = 'zone1',
      factor = 0.1
    }, CTX)
    R.ok(res)
    local view = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    return R.ok(view.yaml:find("factor: 0.1"), "zone1 should have factor 0.1")
  end)
  return R.it("resizeZone with maximum factor 1.0", function()
    local res = cvr.Mutation.resizeZone({ }, {
      pageId = cv_id,
      zoneId = 'zone1',
      factor = 1.0
    }, CTX)
    R.ok(res)
    local view = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    return R.ok(view.yaml:find("factor: 1"), "zone1 should have factor 1")
  end)
end)
return R.describe("ResizeZone — cleanup", function()
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
