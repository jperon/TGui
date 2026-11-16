(function() {
  // widget_plugins.coffee
  // API helpers for custom widget plugins.

  // Portées (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §5) :
  // une définition appartient à la bibliothèque (`appId` nul) ou à une app. Une
  // instance de page résout d'abord la définition de l'app de la page, puis la
  // globale : les appels de rendu passent donc `pageId`, les appels d'édition
  // peuvent passer `appId` (ou rien, pour lister toutes les définitions).
  var GET_WIDGET_PLUGIN, LIST_WIDGET_PLUGINS;

  LIST_WIDGET_PLUGINS = `query WidgetPlugins($appId: String, $pageId: ID) {
  widgetPlugins(appId: $appId, pageId: $pageId) {
    id
    name
    description
    scriptLanguage
    templateLanguage
    scriptCode
    templateCode
    manifest
    appId
    compiled
    updatedAt
  }
}`;

  GET_WIDGET_PLUGIN = `query WidgetPluginByName($name: String, $pageId: ID) {
  widgetPlugin(name: $name, pageId: $pageId) {
    id
    name
    description
    scriptLanguage
    templateLanguage
    scriptCode
    templateCode
    manifest
    appId
    compiled
    updatedAt
  }
}`;

  window.WidgetPlugins = {
    // Exposed so app.coffee can reuse the single canonical query text (T13).
    LIST_QUERY: LIST_WIDGET_PLUGINS,
    // Arguments optionnels : { pageId } pour les définitions que voit une page,
    // { appId } pour une portée d'app, rien pour toutes les définitions (éditeur).
    list: function(args = {}) {
      var variables;
      variables = {};
      if (args.pageId) {
        variables.pageId = args.pageId;
      }
      if (args.appId) {
        variables.appId = args.appId;
      }
      return GQL.query(LIST_WIDGET_PLUGINS, variables).then(function(d) {
        return d.widgetPlugins || [];
      });
    },
    // `pageId` fait résoudre l'instance comme le rendu : app de la page, sinon
    // bibliothèque. Sans `pageId`, recherche par nom dans toutes les portées.
    getByName: function(name, pageId = null) {
      var variables;
      if (!name) {
        return Promise.resolve(null);
      }
      variables = {name};
      if (pageId) {
        variables.pageId = pageId;
      }
      return GQL.query(GET_WIDGET_PLUGIN, variables).then(function(d) {
        return d.widgetPlugin || null;
      });
    },
    // Libellé de portée affiché dans les fenêtres (bibliothèque / app).
    scopeLabel: function(plugin) {
      var appId;
      appId = plugin != null ? plugin.appId : void 0;
      if (appId) {
        return `app ${appId}`;
      } else {
        return 'bibliothèque';
      }
    }
  };

}).call(this);
