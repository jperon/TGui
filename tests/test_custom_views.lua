local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local SUFFIX = tostring(math.random(100000, 999999))
local CV_NAME = "test_cv_" .. tostring(SUFFIX)
local YAML_SIMPLE = [[layout:
  direction: vertical
  children:
    - widget:
        title: Test
        space: test
]]
local YAML_FACTOR = [[layout:
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
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
R.describe("CustomViews — creation", function()
  R.it("createCustomView returns metadata", function()
    local res = cvr.Mutation.createCustomView({ }, {
      input = {
        name = CV_NAME,
        description = 'test',
        yaml = YAML_SIMPLE
      }
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    R.eq(res.name, CV_NAME)
    R.eq(res.description, 'test')
    R.eq(res.yaml, YAML_SIMPLE)
    cv_id = res.id
  end)
  R.it("customViews list includes created view", function()
    local found = false
    local _list_0 = cvr.Query.customViews({ }, { }, CTX)
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      if v.id == cv_id then
        found = true
      end
    end
    return R.ok(found)
  end)
  return R.it("customView returns the view by id", function()
    local v = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    R.ok(v)
    R.eq(v.id, cv_id)
    return R.eq(v.name, CV_NAME)
  end)
end)
R.describe("CustomViews — update", function()
  R.it("updateCustomView updates name and yaml", function()
    local res = cvr.Mutation.updateCustomView({ }, {
      id = cv_id,
      input = {
        name = CV_NAME .. '_v2',
        yaml = YAML_FACTOR
      }
    }, CTX)
    R.ok(res)
    R.eq(res.name, CV_NAME .. '_v2')
    return R.eq(res.yaml, YAML_FACTOR)
  end)
  R.it("updateCustomView with partial fields keeps previous values", function()
    local res = cvr.Mutation.updateCustomView({ }, {
      id = cv_id,
      input = {
        name = CV_NAME .. '_v2'
      }
    }, CTX)
    R.ok(res)
    return R.eq(res.yaml, YAML_FACTOR)
  end)
  return R.it("updateCustomView on unknown id -> error", function()
    return R.raises((function()
      return cvr.Mutation.updateCustomView({ }, {
        id = 'no-such-id',
        input = {
          name = 'x'
        }
      }, CTX)
    end), 'not found')
  end)
end)
return R.describe("CustomViews — deletion", function()
  R.it("deleteCustomView returns true", function()
    local ok = cvr.Mutation.deleteCustomView({ }, {
      id = cv_id
    }, CTX)
    return R.ok(ok)
  end)
  R.it("deleted view no longer appears in list", function()
    local found = false
    local _list_0 = cvr.Query.customViews({ }, { }, CTX)
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      if v.id == cv_id then
        found = true
      end
    end
    return R.nok(found)
  end)
  return R.it("customView on deleted id returns nil", function()
    local v = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    return R.is_nil(v)
  end)
end)
