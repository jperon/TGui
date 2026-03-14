local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local spaces = require('core.spaces')
local SUFFIX = tostring(math.random(100000, 999999))
local CV_NAME = "test_cv_" .. tostring(SUFFIX)
local SPACE_NAME = "test_space_" .. tostring(SUFFIX)
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
local cv_id, space_id
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
R.describe("CustomViews — setup test space", function()
  return R.it("create test space for widget tests", function()
    local space = spaces.create_user_space(SPACE_NAME, 'Test space for widgets', CTX.user_id)
    R.ok(space)
    R.ok(space.id)
    R.eq(space.name, SPACE_NAME)
    space_id = space.id
    local fields = {
      {
        name = 'id',
        type = 'Sequence',
        position = 1,
        not_null = true
      },
      {
        name = 'name',
        type = 'String',
        position = 2,
        not_null = false
      }
    }
    for _index_0 = 1, #fields do
      local field = fields[_index_0]
      if field.type == 'Sequence' then
        spaces.add_field(space_id, field.name, 'Sequence')
      else
        spaces.add_field(space_id, field.name, field.type, false, '')
      end
    end
  end)
end)
R.describe("CustomViews — creation", function()
  R.it("createCustomView returns metadata", function()
    local res = cvr.Mutation.createCustomView({ }, {
      name = CV_NAME,
      description = 'test',
      yaml = YAML_SIMPLE
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
R.describe("CustomViews — addWidgetToView", function()
  R.it("addWidgetToView adds widget to existing view", function()
    local empty_yaml = [[layout:
  direction: vertical
  children: []
]]
    local cv = cvr.Mutation.createCustomView({ }, {
      name = "test_widget_cv_" .. tostring(SUFFIX),
      yaml = empty_yaml
    }, CTX)
    cv_id = cv.id
    local widget_input = {
      title = "Test Widget",
      type = "table",
      spaceId = space_id,
      fields = {
        "id",
        "name"
      },
      groupBy = null,
      params = { }
    }
    local res = cvr.Mutation.addWidgetToView({ }, {
      viewId = cv_id,
      widget = widget_input
    }, CTX)
    R.ok(res)
    R.ok(res.id, cv_id)
    R.ok(res.yaml)
    R.ok(res.yaml:find("space: " .. tostring(SPACE_NAME)), "doit contenir le nom de l'espace, pas l'UUID")
    R.ok(res.yaml:find("title: Test Widget"), "doit contenir le titre du widget")
    R.ok(res.yaml:find("columns:"), "doit contenir la section columns")
    R.ok(res.yaml:find("- id"), "doit contenir la colonne id")
    return R.ok(res.yaml:find("- name"), "doit contenir la colonne name")
  end)
  return R.it("addWidgetToView on unknown view -> error", function()
    local widget_input = {
      title = "Test",
      type = "table",
      spaceId = space_id,
      fields = {
        "id"
      }
    }
    return R.raises((function()
      return cvr.Mutation.addWidgetToView({ }, {
        viewId = 'no-such-id',
        widget = widget_input
      }, CTX)
    end), 'not found')
  end)
end)
R.describe("CustomViews — deletion", function()
  R.it("deleteCustomView returns true", function()
    if cv_id then
      local ok = cvr.Mutation.deleteCustomView({ }, {
        id = cv_id
      }, CTX)
      return R.ok(ok)
    end
  end)
  R.it("deleted view no longer appears in list", function()
    if cv_id then
      local found = false
      local _list_0 = cvr.Query.customViews({ }, { }, CTX)
      for _index_0 = 1, #_list_0 do
        local v = _list_0[_index_0]
        if v.id == cv_id then
          found = true
        end
      end
      return R.nok(found)
    end
  end)
  return R.it("customView on deleted id returns nil", function()
    if cv_id then
      local v = cvr.Query.customView({ }, {
        id = cv_id
      }, CTX)
      return R.eq(v, nil)
    end
  end)
end)
return R.describe("CustomViews — cleanup", function()
  return R.it("cleanup test space", function()
    if space_id then
      return spaces.delete_user_space(space_id)
    end
  end)
end)
