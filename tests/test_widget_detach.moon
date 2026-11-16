-- tests/test_widget_detach.moon
-- « Détacher » une instance de widget personnalisé (spec
-- docs/superpowers/specs/2026-11-16-custom-widgets-design.md §4) :
--  - la définition résolue est copiée (script, gabarit, langages, manifest,
--    description) sous un nom par défaut « <nom> (<titre de la page>) », suffixé
--    numériquement s'il est déjà pris, dans la portée de la page (app de la
--    page, sinon bibliothèque) ;
--  - seule l'instance visée change de `type:` : paramètres, colonnes et reste du
--    nœud conservés, autres instances et autres pages intactes ;
--  - refus : non-admin, instance absente ou non personnalisée, nom invalide,
--    et opération relayée par une iframe de widget (liste blanche d'executor).
-- S'exécute dans l'instance de tests via `make test`.

R       = require 'tests.runner'
wpr     = require 'resolvers.widget_plugin_resolvers'
scopes  = require 'core.widget_scopes'
pkg     = require 'core.app_package'
auth    = require 'core.auth'
perms   = require 'core.permissions'
cvr     = require 'resolvers.custom_view_resolvers'
executor = require 'graphql.executor'
yaml    = require 'yaml'

SUFFIX   = tostring math.random 100000, 999999
APP_ID   = "org.test.detach_#{SUFFIX}"
APP_NAME = "Detach app #{SUFFIX}"
PAGE_1   = "wdetach_page_#{SUFFIX}"
PAGE_2   = "wdetach_other_#{SUFFIX}"
PAGE_3   = "wdetach_misc_#{SUFFIX}"

SCRIPT = "module.exports = function (api) { api.render('<b>original</b>'); };"
TEMPLATE = '<b>init</b>'
MANIFEST = "access: read\ncolumns:\n  - {name: titre, type: String}\n"

admin = auth.get_user_by_username 'admin'
R.ok admin, 'fixture: admin must exist'
CTX = { user_id: admin.id }

FIX = { pages: {}, plugins: {}, actor: nil }

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

register_app = (app_id, name) ->
  box.space._tdb_apps\replace { app_id, name, '1.0.0', os.time!, 'detach test' }

track_page = (app_id, page_id, page_name) ->
  box.space._tdb_app_items\replace {
    app_id, "page:#{pkg.key_part page_name}", 'page', page_id, 'fp', 'actif', '1.0.0'
  }

plugin = (name, app_id, opts = {}) ->
  input = {
    name: name
    description: opts.description or "detach #{name}"
    scriptLanguage: 'javascript'
    templateLanguage: 'html'
    scriptCode: opts.scriptCode or SCRIPT
    templateCode: opts.templateCode or TEMPLATE
    manifest: opts.manifest or MANIFEST
  }
  input.appId = app_id if app_id
  created = wpr.Mutation.createWidgetPlugin {}, { input: input }, CTX
  FIX.plugins[created.name] = created
  created

create_page = (name, page_yaml) ->
  page = cvr.Mutation.createCustomView {}, {
    name: name
    description: 'detach test'
    yaml: page_yaml
  }, CTX
  FIX.pages[name] = page
  page

delete_page = (page) ->
  box.space._tdb_custom_views\delete page.id if page and page.id

page_yaml_of = (page_id) ->
  t = box.space._tdb_custom_views\get page_id
  t and t[4]

decoded = (page_id) ->
  yaml.decode page_yaml_of page_id

-- Widgets de la page, à plat, indexés par id (l'ordre du YAML n'est pas
-- significatif ici).
widgets_by_id = (page_id) ->
  config = decoded page_id
  out = {}
  walk = (node) ->
    return unless type(node) == 'table'
    if type(node.widget) == 'table'
      w = node.widget
      out[tostring w.id] = w if w.id != nil
      return
    for _, child in pairs node
      walk child if type(child) == 'table'
  walk config
  out

instance_type = (page_id, widget_id) ->
  w = widgets_by_id(page_id)[widget_id]
  w and w.type

-- YAML de la page 1 : DEUX instances du même plugin (params et colonnes
-- différentes) et un widget de données ordinaire.
two_instances_yaml = (plugin_name, title) ->
  [[layout:
  direction: vertical
  children:
    - widget:
        id: w_00000001
        title: Premier
        space: personnes
        type: ']] .. plugin_name .. [['
        columns:
          titre: nom
        params:
          couleur: '#c33'
    - widget:
        id: w_00000002
        title: Second
        space: personnes
        type: ']] .. plugin_name .. [['
        columns:
          titre: prenom
        params:
          couleur: '#36c'
    - widget:
        id: w_00000003
        title: Grille
        space: personnes
]]

-- Page 2 : une autre page qui utilise la même définition.
other_page_yaml = (plugin_name) ->
  [[layout:
  direction: vertical
  children:
    - widget:
        id: w_0000000a
        title: Ailleurs
        space: personnes
        type: ']] .. plugin_name .. [['
]]

-- Page 3 : instances non personnalisées ou définition introuvable.
misc_page_yaml = ->
  [[layout:
  direction: vertical
  children:
    - widget:
        id: w_0000000b
        title: Sans type
        space: personnes
    - widget:
        id: w_0000000c
        title: Agrégat
        space: personnes
        type: 'aggregate'
        groupBy:
          - nom
    - widget:
        id: w_0000000d
        title: Inconnu
        space: personnes
        type: 'wdetach_unknown_]] .. SUFFIX .. [['
]]

-- ────────────────────────────────────────────────────────────────────────────
-- Fixture
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetDetach — fixture", ->

  R.it "enregistre l'app, sa définition et trois pages", ->
    register_app APP_ID, APP_NAME
    FIX.plugin = plugin "wdetach_#{SUFFIX}", nil, { description: 'définition globale' }
    R.eq FIX.plugin.appId, nil
    R.eq FIX.plugin.manifest, MANIFEST

    FIX.pages.p1 = create_page PAGE_1, two_instances_yaml(FIX.plugin.name, PAGE_1)
    track_page APP_ID, FIX.pages.p1.id, PAGE_1
    FIX.pages.p2 = create_page PAGE_2, other_page_yaml(FIX.plugin.name)
    FIX.pages.p3 = create_page PAGE_3, misc_page_yaml!
    R.eq scopes.page_app_id(FIX.pages.p1.id), APP_ID, 'la page 1 appartient à l’app'
    R.is_nil scopes.page_app_id(FIX.pages.p2.id), 'la page 2 est locale'

-- ────────────────────────────────────────────────────────────────────────────
-- Copie : contenu, portée, nom par défaut
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetDetach — copie de la définition", ->

  R.it "détache la seconde instance sous le nom par défaut", ->
    expected = "#{FIX.plugin.name} (#{PAGE_1})"
    FIX.copy = wpr.Mutation.detachWidgetPlugin {}, {
      pageId: FIX.pages.p1.id
      widgetId: 'w_00000002'
    }, CTX
    R.ok FIX.copy, 'la mutation renvoie la copie'
    FIX.plugins[FIX.copy.name] = FIX.copy
    R.eq FIX.copy.name, expected, 'nom par défaut « <nom> (<page>) »'
    R.ne FIX.copy.id, FIX.plugin.id, 'nouvelle définition'

  R.it "copie script, gabarit, langages, manifest et description", ->
    R.eq FIX.copy.description, FIX.plugin.description
    R.eq FIX.copy.scriptLanguage, FIX.plugin.scriptLanguage
    R.eq FIX.copy.templateLanguage, FIX.plugin.templateLanguage
    R.eq FIX.copy.scriptCode, FIX.plugin.scriptCode
    R.eq FIX.copy.templateCode, FIX.plugin.templateCode
    R.eq FIX.copy.manifest, FIX.plugin.manifest

  R.it "place la copie dans la portée de la page (app de la page)", ->
    R.eq FIX.copy.appId, APP_ID
    R.eq (scopes.find_row FIX.copy.name, APP_ID)[1], FIX.copy.id
    R.is_nil scopes.find_row(FIX.copy.name, nil), 'pas de copie globale'

  R.it "réécrit le type de cette seule instance et conserve params/columns", ->
    w = widgets_by_id(FIX.pages.p1.id)
    R.eq w['w_00000002'].type, FIX.copy.name
    R.eq w['w_00000002'].params.couleur, '#36c', 'params conservés'
    R.eq w['w_00000002'].columns.titre, 'prenom', 'columns conservées'
    R.eq w['w_00000002'].title, 'Second'
    R.eq w['w_00000001'].type, FIX.plugin.name, 'l’autre instance garde l’original'
    R.eq w['w_00000001'].params.couleur, '#c33'
    R.eq w['w_00000003'].type, nil, 'le widget de données est intact'

  R.it "ne touche ni l’autre page ni la définition d’origine", ->
    R.eq instance_type(FIX.pages.p2.id, 'w_0000000a'), FIX.plugin.name
    stored = wpr.Query.widgetPlugin {}, { id: FIX.plugin.id }, CTX
    R.eq stored.scriptCode, SCRIPT
    R.eq stored.appId, nil

  R.it "préserve le reste du YAML (titres, ordre, params)", ->
    text = page_yaml_of FIX.pages.p1.id
    R.matches text, 'title: Premier'
    R.matches text, 'title: Second'
    R.matches text, 'title: Grille'
    R.matches text, 'couleur: \'#c33\''
    R.matches text, 'couleur: \'#36c\''
    -- La page « misc » (types non personnalisés) n'a pas été réécrite.
    misc = page_yaml_of FIX.pages.p3.id
    R.matches misc, "type: 'aggregate'"
    R.matches misc, "type: 'wdetach_unknown_#{SUFFIX}'"

-- ────────────────────────────────────────────────────────────────────────────
-- Nom modifiable et collision
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetDetach — nom de la copie", ->

  R.it "accepte un nouveau nom explicite", ->
    copy = wpr.Mutation.detachWidgetPlugin {}, {
      pageId: FIX.pages.p1.id
      widgetId: 'w_00000001'
      newName: "ma_copie_#{SUFFIX}"
    }, CTX
    FIX.plugins[copy.name] = copy
    R.eq copy.name, "ma_copie_#{SUFFIX}"
    R.eq instance_type(FIX.pages.p1.id, 'w_00000001'), copy.name
    R.eq copy.appId, APP_ID

  R.it "suffixe numériquement un nom déjà pris dans la portée", ->
    page_name = "Collision #{SUFFIX}"
    taken = "#{FIX.plugin.name} (#{page_name})"
    plugin taken, APP_ID
    page = create_page page_name, two_instances_yaml(FIX.plugin.name, page_name)
    track_page APP_ID, page.id, page_name
    copy = wpr.Mutation.detachWidgetPlugin {}, {
      pageId: page.id
      widgetId: 'w_00000002'
    }, CTX
    FIX.plugins[copy.name] = copy
    R.eq copy.name, "#{taken}_2"
    R.eq copy.appId, APP_ID
    delete_page page

  R.it "refuse un nom invalide", ->
    before = page_yaml_of FIX.pages.p1.id
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, {
        pageId: FIX.pages.p1.id
        widgetId: 'w_00000002'
        newName: 'bad:name'
      }, CTX
    ), 'must match'
    R.eq page_yaml_of(FIX.pages.p1.id), before, 'la page ne change pas'

  R.it "ne confond pas une clé `type` imbriquée avec celle du widget", ->
    page = create_page "wdetach_nested_#{SUFFIX}", [[layout:
  direction: vertical
  children:
    - widget:
        id: w_0000000e
        type: ']] .. FIX.plugin.name .. [['
        params:
          type: 'nested'
          label: 'X'
]]
    copy = wpr.Mutation.detachWidgetPlugin {}, {
      pageId: page.id
      widgetId: 'w_0000000e'
    }, CTX
    FIX.plugins[copy.name] = copy
    w = widgets_by_id(page.id)['w_0000000e']
    R.eq w.type, copy.name, 'le type du widget est réécrit'
    R.eq w.params.type, 'nested', 'le type imbriqué des params est intact'
    R.eq w.params.label, 'X'
    delete_page page

-- ────────────────────────────────────────────────────────────────────────────
-- Erreurs
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetDetach — erreurs claires", ->

  R.it "page introuvable", ->
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, { pageId: "missing_#{SUFFIX}", widgetId: 'w_00000001' }, CTX
    ), 'Custom view not found'

  R.it "instance introuvable dans la page", ->
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, {
        pageId: FIX.pages.p1.id
        widgetId: 'w_ffffffff'
      }, CTX
    ), 'Widget not found in page'

  R.it "instance sans type personnalisé (données, agrégat)", ->
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, {
        pageId: FIX.pages.p3.id
        widgetId: 'w_0000000b'
      }, CTX
    ), 'not a custom widget'
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, {
        pageId: FIX.pages.p3.id
        widgetId: 'w_0000000c'
      }, CTX
    ), 'not a custom widget'

  R.it "type personnalisé sans définition résolue", ->
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, {
        pageId: FIX.pages.p3.id
        widgetId: 'w_0000000d'
      }, CTX
    ), 'Widget definition not found'

-- ────────────────────────────────────────────────────────────────────────────
-- Permissions : admin requis, refus depuis une iframe de widget
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetDetach — permissions", ->

  R.it "refuse un utilisateur sans droit admin", ->
    user = auth.create_user "wdetach_actor_#{SUFFIX}", "wdetach_actor_#{SUFFIX}@test.local", 'pass1234'
    grp = perms.create_group "wdetach_grp_#{SUFFIX}", ''
    perms.grant grp.id, '*', nil, 'write'
    perms.add_member user.id, grp.id
    FIX.actor = { user: user, group: grp }
    before = page_yaml_of FIX.pages.p1.id
    R.raises (->
      wpr.Mutation.detachWidgetPlugin {}, {
        pageId: FIX.pages.p1.id
        widgetId: 'w_00000002'
      }, { user_id: user.id }
    ), 'Forbidden'
    R.eq page_yaml_of(FIX.pages.p1.id), before, 'la page ne change pas'

  R.it "refuse la mutation relayée par un widget (liste blanche d’executor)", ->
    require('resolvers.init').reinit!
    res = executor.execute {
      query: 'mutation($p: ID!, $w: ID!) { detachWidgetPlugin(pageId: $p, widgetId: $w) { id name } }'
      variables: { p: FIX.pages.p1.id, w: 'w_00000002' }
      context: { user_id: admin.id, widget: true }
    }
    R.ok res.errors, 'la mutation doit échouer'
    R.matches tostring(res.errors[1].message), 'not allowed from a widget'
    R.matches tostring(res.errors[1].message), 'detachWidgetPlugin'

  R.it "reste disponible par le chemin GraphQL pour un admin", ->
    copy = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: "gql_copy_#{SUFFIX}"
        description: 'graphql'
        scriptLanguage: 'javascript'
        templateLanguage: 'html'
        scriptCode: SCRIPT
        templateCode: TEMPLATE
        manifest: ''
      }
    }, CTX
    FIX.plugins[copy.name] = copy
    page = create_page "wdetach_gql_#{SUFFIX}", other_page_yaml(copy.name)
    res = executor.execute {
      query: 'mutation($p: ID!, $w: ID!) { detachWidgetPlugin(pageId: $p, widgetId: $w) { id name appId } }'
      variables: { p: page.id, w: 'w_0000000a' }
      context: { user_id: admin.id }
    }
    R.nok res.errors, tostring(res.errors and res.errors[1].message)
    FIX.plugins[res.data.detachWidgetPlugin.name] = res.data.detachWidgetPlugin
    R.ok res.data.detachWidgetPlugin.id
    R.eq instance_type(page.id, 'w_0000000a'), res.data.detachWidgetPlugin.name
    delete_page page

-- ────────────────────────────────────────────────────────────────────────────
-- Nettoyage
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetDetach — cleanup", ->

  R.it "supprime pages, définitions, app et acteur de la fixture", ->
    for _, page in pairs FIX.pages
      delete_page page
    for row in *box.space._tdb_custom_views\select {}
      box.space._tdb_custom_views\delete row[1] if row[2]\find SUFFIX, 1, true
    for row in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete row[1] if row[2]\find SUFFIX, 1, true
    for t in *box.space._tdb_app_items.index.by_app\select { APP_ID }
      box.space._tdb_app_items\delete { t[1], t[2] }
    box.space._tdb_apps\delete APP_ID
    if FIX.actor
      for s in *box.space._tdb_sessions.index.by_user\select { FIX.actor.user.id }
        box.space._tdb_sessions\delete s[1]
      perms.delete_group FIX.actor.group.id
      box.space._tdb_users\delete FIX.actor.user.id
    R.is_nil scopes.find_row("wdetach_#{SUFFIX}", nil)
    R.is_nil box.space._tdb_custom_views.index.by_name\get(PAGE_1)
