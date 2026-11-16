# widget_plugins.coffee
# API helpers for custom widget plugins.
#
# Portées (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §5) :
# une définition appartient à la bibliothèque (`appId` nul) ou à une app. Une
# instance de page résout d'abord la définition de l'app de la page, puis la
# globale : les appels de rendu passent donc `pageId`, les appels d'édition
# peuvent passer `appId` (ou rien, pour lister toutes les définitions).

LIST_WIDGET_PLUGINS = """
  query WidgetPlugins($appId: String, $pageId: ID) {
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
  }
"""

GET_WIDGET_PLUGIN = """
  query WidgetPluginByName($name: String, $pageId: ID) {
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
  }
"""

window.WidgetPlugins =
  # Exposed so app.coffee can reuse the single canonical query text (T13).
  LIST_QUERY: LIST_WIDGET_PLUGINS

  # Arguments optionnels : { pageId } pour les définitions que voit une page,
  # { appId } pour une portée d'app, rien pour toutes les définitions (éditeur).
  list: (args = {}) ->
    variables = {}
    variables.pageId = args.pageId if args.pageId
    variables.appId = args.appId if args.appId
    GQL.query(LIST_WIDGET_PLUGINS, variables).then (d) -> d.widgetPlugins or []

  # `pageId` fait résoudre l'instance comme le rendu : app de la page, sinon
  # bibliothèque. Sans `pageId`, recherche par nom dans toutes les portées.
  getByName: (name, pageId = null) ->
    return Promise.resolve(null) unless name
    variables = { name }
    variables.pageId = pageId if pageId
    GQL.query(GET_WIDGET_PLUGIN, variables).then (d) -> d.widgetPlugin or null

  # Libellé de portée affiché dans les fenêtres (bibliothèque / app).
  scopeLabel: (plugin) ->
    appId = plugin?.appId
    if appId then "app #{appId}" else 'bibliothèque'
