-- tests/test_widget_plugins.moon
-- Tests CRUD operations on widget plugins (resolvers/widget_plugin_resolvers.moon).

R = require 'tests.runner'
wpr = require 'resolvers.widget_plugin_resolvers'
auth = require 'core.auth'

SUFFIX = tostring math.random(100000, 999999)
PLUGIN_NAME = "test_plugin_#{SUFFIX}"

SCRIPT_CS = [[
module.exports = ({ gql, emitSelection, render, onInputSelection, params }) ->
  render '<div>Hello</div>'
  onInputSelection (sel) ->
    emitSelection sel
]]

TEMPLATE_PUG = [[
div.widget
  h3 Hello Plugin
]]

plugin_id = nil
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "WidgetPlugins — creation", ->
  R.it "createWidgetPlugin returns metadata", ->
    res = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: PLUGIN_NAME
        description: 'test plugin'
        scriptLanguage: 'coffeescript'
        templateLanguage: 'pug'
        scriptCode: SCRIPT_CS
        templateCode: TEMPLATE_PUG
      }
    }, CTX

    R.ok res
    R.ok res.id
    R.eq res.name, PLUGIN_NAME
    R.eq res.scriptLanguage, 'coffeescript'
    R.eq res.templateLanguage, 'pug'
    plugin_id = res.id

  R.it "widgetPlugins includes created plugin", ->
    found = false
    for p in *wpr.Query.widgetPlugins({}, {}, CTX)
      if p.id == plugin_id
        found = true
        break
    R.ok found

  R.it "widgetPlugin fetches by id", ->
    p = wpr.Query.widgetPlugin {}, { id: plugin_id }, CTX
    R.ok p
    R.eq p.id, plugin_id
    R.eq p.name, PLUGIN_NAME

  R.it "widgetPlugin fetches by name", ->
    p = wpr.Query.widgetPlugin {}, { name: PLUGIN_NAME }, CTX
    R.ok p
    R.eq p.id, plugin_id

R.describe "WidgetPlugins — update", ->
  R.it "updateWidgetPlugin supports partial update", ->
    res = wpr.Mutation.updateWidgetPlugin {}, {
      id: plugin_id
      input: {
        scriptLanguage: 'javascript'
        templateLanguage: 'html'
      }
    }, CTX

    R.ok res
    R.eq res.id, plugin_id
    R.eq res.scriptLanguage, 'javascript'
    R.eq res.templateLanguage, 'html'
    R.eq res.name, PLUGIN_NAME

  R.it "updateWidgetPlugin rejects unsupported language", ->
    R.raises (->
      wpr.Mutation.updateWidgetPlugin {}, {
        id: plugin_id
        input: { scriptLanguage: 'python' }
      }, CTX
    ), 'Unsupported script language'

R.describe "WidgetPlugins — validation and deletion", ->
  R.it "createWidgetPlugin rejects duplicate name", ->
    R.raises (->
      wpr.Mutation.createWidgetPlugin {}, {
        input: {
          name: PLUGIN_NAME
          scriptCode: SCRIPT_CS
          templateCode: TEMPLATE_PUG
        }
      }, CTX
    ), 'already exists'

  R.it "deleteWidgetPlugin returns true", ->
    ok = wpr.Mutation.deleteWidgetPlugin {}, { id: plugin_id }, CTX
    R.ok ok

  R.it "deleted plugin no longer returned", ->
    p = wpr.Query.widgetPlugin {}, { id: plugin_id }, CTX
    R.is_nil p
