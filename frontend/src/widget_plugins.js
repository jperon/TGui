(function() {
  // widget_plugins.coffee
  // API helpers for custom widget plugins.
  var GET_WIDGET_PLUGIN, LIST_WIDGET_PLUGINS;

  LIST_WIDGET_PLUGINS = `query {
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
}`;

  GET_WIDGET_PLUGIN = `query WidgetPluginByName($name: String) {
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
}`;

  window.WidgetPlugins = {
    list: function() {
      return GQL.query(LIST_WIDGET_PLUGINS).then(function(d) {
        return d.widgetPlugins || [];
      });
    },
    getByName: function(name) {
      if (!name) {
        return Promise.resolve(null);
      }
      return GQL.query(GET_WIDGET_PLUGIN, {name}).then(function(d) {
        return d.widgetPlugin || null;
      });
    }
  };

}).call(this);
