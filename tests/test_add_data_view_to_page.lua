local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local spaces = require('core.spaces')
local data_views = require('core.data_views')
local SUFFIX = tostring(math.random(100000, 999999))
local SPACE_NAME = "test_space_" .. tostring(SUFFIX)
local DATA_VIEW_NAME = "test_dv_" .. tostring(SUFFIX)
local CV_NAME = "test_cv_" .. tostring(SUFFIX)
local space_id = nil
local dv_id = nil
local cv_id = nil
local ctx = nil
local YAML_EMPTY = [[layout:
  direction: vertical
  children: []
]]
R.describe("AddDataViewToPage — setup", function()
  R.it("create test space", function()
    local space = spaces.create_user_space(SPACE_NAME, 'Test space for data view')
    R.ok(space)
    R.ok(space.id)
    space_id = space.id
  end)
  R.it("create test data view", function()
    local dv = data_views.create_view(DATA_VIEW_NAME, 'Test data view', SPACE_NAME, '{}')
    R.ok(dv)
    R.ok(dv.id)
    dv_id = dv.id
  end)
  return R.it("create empty custom view and context", function()
    local admin = auth.get_user_by_username('admin')
    ctx = {
      user_id = admin and admin.id
    }
    local cv = cvr.Mutation.createCustomView({ }, {
      name = CV_NAME,
      description = 'test',
      yaml = YAML_EMPTY
    }, ctx)
    R.ok(cv)
    R.ok(cv.id)
    R.eq(cv.name, CV_NAME)
    R.eq(cv.yaml, YAML_EMPTY)
    cv_id = cv.id
  end)
end)
R.describe("AddDataViewToPage — mutation", function()
  R.it("successfully adds data view to page", function()
    local res = cvr.Mutation.addDataViewToPage({ }, {
      pageId = cv_id,
      dataViewId = dv_id
    }, ctx)
    R.ok(res)
    R.eq(res.id, cv_id)
    R.eq(res.name, CV_NAME)
    R.ok(res.yaml)
    R.ok(res.yaml:find("dataViewId:"), "YAML should contain the dataViewId")
    R.ok(res.yaml:find("title: Data View: " .. tostring(DATA_VIEW_NAME)), "YAML should contain the correct title")
    R.ok(res.yaml:find("space: " .. tostring(DATA_VIEW_NAME)), "YAML should contain the data view name as space")
    return R.ok(res.yaml:find("- widget:"), "YAML should contain a widget entry")
  end)
  R.it("returns error when pageId does not exist", function()
    return R.raises((function()
      return cvr.Mutation.addDataViewToPage({ }, {
        pageId = 'non-existent-id',
        dataViewId = dv_id
      }, ctx)
    end), 'not found')
  end)
  return R.it("returns error when dataViewId does not exist", function()
    return R.raises((function()
      return cvr.Mutation.addDataViewToPage({ }, {
        pageId = cv_id,
        dataViewId = 'non-existent-id'
      }, ctx)
    end), 'not found')
  end)
end)
return R.describe("AddDataViewToPage — cleanup", function()
  R.it("delete custom view", function()
    if cv_id then
      local ok = cvr.Mutation.deleteCustomView({ }, {
        id = cv_id
      }, ctx)
      return R.ok(ok)
    end
  end)
  R.it("delete data view", function()
    if dv_id then
      local ok = data_views.delete_view(dv_id)
      return R.ok(ok)
    end
  end)
  return R.it("delete test space", function()
    if space_id then
      local ok = spaces.delete_user_space(SPACE_NAME)
      return R.ok(ok)
    end
  end)
end)
