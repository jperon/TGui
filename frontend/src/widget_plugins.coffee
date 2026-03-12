# widget_plugins.coffee
# API helpers for custom widget plugins.

LIST_WIDGET_PLUGINS = """
  query {
    widgetPlugins {
      id
      name
      description
      scriptLanguage
      templateLanguage
      scriptCode
      templateCode
      updatedAt
    }
  }
"""

GET_WIDGET_PLUGIN = """
  query WidgetPluginByName($name: String) {
    widgetPlugin(name: $name) {
      id
      name
      description
      scriptLanguage
      templateLanguage
      scriptCode
      templateCode
      updatedAt
    }
  }
"""

window.WidgetPlugins =
  list: ->
    GQL.query(LIST_WIDGET_PLUGINS).then (d) -> d.widgetPlugins or []

  getByName: (name) ->
    return Promise.resolve(null) unless name
    GQL.query(GET_WIDGET_PLUGIN, { name }).then (d) -> d.widgetPlugin or null
