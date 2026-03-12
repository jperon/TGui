local R = require('tests.runner')
local wpr = require('resolvers.widget_plugin_resolvers')
local auth = require('core.auth')
local SUFFIX = tostring(math.random(100000, 999999))
local PLUGIN_NAME = "test_plugin_" .. tostring(SUFFIX)
local SCRIPT_CS = [[module.exports = ({ gql, emitSelection, render, onInputSelection, params }) ->
  render '<div>Hello</div>'
  onInputSelection (sel) ->
    emitSelection sel
]]
local TEMPLATE_PUG = [[div.widget
  h3 Hello Plugin
]]
local plugin_id = nil
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
R.describe("WidgetPlugins — creation", function()
  R.it("createWidgetPlugin returns metadata", function()
    local res = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = PLUGIN_NAME,
        description = 'test plugin',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = SCRIPT_CS,
        templateCode = TEMPLATE_PUG
      }
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    R.eq(res.name, PLUGIN_NAME)
    R.eq(res.scriptLanguage, 'coffeescript')
    R.eq(res.templateLanguage, 'pug')
    plugin_id = res.id
  end)
  R.it("widgetPlugins includes created plugin", function()
    local found = false
    local _list_0 = wpr.Query.widgetPlugins({ }, { }, CTX)
    for _index_0 = 1, #_list_0 do
      local p = _list_0[_index_0]
      if p.id == plugin_id then
        found = true
        break
      end
    end
    return R.ok(found)
  end)
  R.it("widgetPlugin fetches by id", function()
    local p = wpr.Query.widgetPlugin({ }, {
      id = plugin_id
    }, CTX)
    R.ok(p)
    R.eq(p.id, plugin_id)
    return R.eq(p.name, PLUGIN_NAME)
  end)
  return R.it("widgetPlugin fetches by name", function()
    local p = wpr.Query.widgetPlugin({ }, {
      name = PLUGIN_NAME
    }, CTX)
    R.ok(p)
    return R.eq(p.id, plugin_id)
  end)
end)
R.describe("WidgetPlugins — update", function()
  R.it("updateWidgetPlugin supports partial update", function()
    local res = wpr.Mutation.updateWidgetPlugin({ }, {
      id = plugin_id,
      input = {
        scriptLanguage = 'javascript',
        templateLanguage = 'html'
      }
    }, CTX)
    R.ok(res)
    R.eq(res.id, plugin_id)
    R.eq(res.scriptLanguage, 'javascript')
    R.eq(res.templateLanguage, 'html')
    return R.eq(res.name, PLUGIN_NAME)
  end)
  return R.it("updateWidgetPlugin rejects unsupported language", function()
    return R.raises((function()
      return wpr.Mutation.updateWidgetPlugin({ }, {
        id = plugin_id,
        input = {
          scriptLanguage = 'python'
        }
      }, CTX)
    end), 'Unsupported script language')
  end)
end)
return R.describe("WidgetPlugins — validation and deletion", function()
  R.it("createWidgetPlugin rejects duplicate name", function()
    return R.raises((function()
      return wpr.Mutation.createWidgetPlugin({ }, {
        input = {
          name = PLUGIN_NAME,
          scriptCode = SCRIPT_CS,
          templateCode = TEMPLATE_PUG
        }
      }, CTX)
    end), 'already exists')
  end)
  R.it("deleteWidgetPlugin returns true", function()
    local ok = wpr.Mutation.deleteWidgetPlugin({ }, {
      id = plugin_id
    }, CTX)
    return R.ok(ok)
  end)
  return R.it("deleted plugin no longer returned", function()
    local p = wpr.Query.widgetPlugin({ }, {
      id = plugin_id
    }, CTX)
    return R.is_nil(p)
  end)
end)
