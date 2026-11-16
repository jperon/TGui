-- tests/test_widget_plugin_manifest.moon
-- Manifest des widgets personnalisés (spec
-- docs/superpowers/specs/2026-11-16-custom-widgets-design.md §3) : stockage
-- (champ manifest en fin de format de _tdb_widget_plugins), validation YAML,
-- migration des tuples d'ancien format, export/installation d'app.

R = require 'tests.runner'
wpr = require 'resolvers.widget_plugin_resolvers'
pkg = require 'core.app_package'
apply = require 'core.app_apply'
auth = require 'core.auth'
json = require 'json'
yaml = require 'yaml'

SUFFIX = tostring math.random 100000, 999999
NAME = "wpman_plugin_#{SUFFIX}"
APP_ID = "org.test.wpman_#{SUFFIX}"

MANIFEST = [[
access: read
columns:
  - {name: titre, type: String}
  - {name: debut, type: Date}
  - {name: fin, type: Date, optional: true}
options:
  - {name: couleur, type: color, default: '#36c'}
]]

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

plugin_id = nil

R.describe "WidgetPlugins — validation du manifest", ->

  R.it "accepte un manifest valide et le rend tel quel", ->
    R.eq wpr.validate_manifest(MANIFEST), MANIFEST

  R.it "traite absent, vide ou commentaires seuls comme « pas de manifest »", ->
    R.eq wpr.validate_manifest(nil), ''
    R.eq wpr.validate_manifest('  \n\t'), ''
    R.eq wpr.validate_manifest('# seulement un commentaire\n'), ''

  R.it "refuse un YAML invalide", ->
    R.raises (-> wpr.validate_manifest 'access: [oops'), 'invalid YAML'

  R.it "refuse une valeur access inconnue", ->
    R.raises (-> wpr.validate_manifest 'access: write'), 'access must be one of none, read, full'

  R.it "accepte les trois valeurs access", ->
    for access in *{ 'none', 'read', 'full' }
      R.eq wpr.validate_manifest("access: #{access}\n"), "access: #{access}\n"

  R.it "refuse un manifest qui n’est pas un mapping", ->
    R.raises (-> wpr.validate_manifest '- a\n- b\n'), 'must be a YAML mapping'

  R.it "refuse columns sous forme de mapping", ->
    R.raises (-> wpr.validate_manifest 'columns: {titre: nom}\n'), 'columns must be a list'

  R.it "refuse une colonne sans nom, sans type ou avec un nom invalide", ->
    R.raises (-> wpr.validate_manifest 'columns:\n  - {type: String}\n'), 'name is required'
    R.raises (-> wpr.validate_manifest 'columns:\n  - {name: titre}\n'), 'type is required'
    R.raises (-> wpr.validate_manifest 'columns:\n  - {name: 1titre, type: String}\n'), 'must match'

  R.it "refuse une colonne en double et un optional non booléen", ->
    R.raises (->
      wpr.validate_manifest 'columns:\n  - {name: a, type: String}\n  - {name: a, type: String}\n'
    ), 'duplicate column name'
    R.raises (->
      wpr.validate_manifest 'columns:\n  - {name: a, type: String, optional: 1}\n'
    ), 'optional must be a boolean'

  R.it "valide les options (nom, type, défaut scalaire)", ->
    R.eq wpr.validate_manifest("options:\n  - {name: couleur, type: color, default: '#36c'}\n"),
      "options:\n  - {name: couleur, type: color, default: '#36c'}\n"
    R.raises (-> wpr.validate_manifest 'options:\n  - {type: color}\n'), 'name is required'
    R.raises (-> wpr.validate_manifest 'options:\n  - {name: c}\n'), 'type is required'
    R.raises (->
      wpr.validate_manifest 'options:\n  - {name: c, type: color, default: [1, 2]}\n'
    ), 'default must be a scalar'

R.describe "WidgetPlugins — stockage du manifest", ->

  R.it "createWidgetPlugin enregistre et renvoie le manifest", ->
    res = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: NAME
        description: 'manifest test'
        scriptLanguage: 'javascript'
        templateLanguage: 'html'
        scriptCode: 'module.exports = function () {}'
        templateCode: '<div></div>'
        manifest: MANIFEST
      }
    }, CTX
    R.ok res
    plugin_id = res.id
    R.eq res.manifest, MANIFEST
    R.eq box.space._tdb_widget_plugins\get(plugin_id)[10], MANIFEST

  R.it "createWidgetPlugin refuse un manifest invalide", ->
    R.raises (->
      wpr.Mutation.createWidgetPlugin {}, {
        input: {
          name: "#{NAME}_bad"
          scriptCode: 'x'
          templateCode: 'y'
          manifest: 'access: write'
        }
      }, CTX
    ), 'access must be one of'
    R.is_nil box.space._tdb_widget_plugins.index.by_scope_name\get { '', "#{NAME}_bad" }

  R.it "updateWidgetPlugin partiel conserve le manifest existant", ->
    res = wpr.Mutation.updateWidgetPlugin {}, {
      id: plugin_id
      input: { description: 'changed' }
    }, CTX
    R.eq res.description, 'changed'
    R.eq res.manifest, MANIFEST

  R.it "updateWidgetPlugin remplace le manifest", ->
    res = wpr.Mutation.updateWidgetPlugin {}, {
      id: plugin_id
      input: { manifest: "access: full\n" }
    }, CTX
    R.eq res.manifest, "access: full\n"

  R.it "updateWidgetPlugin refuse un manifest invalide sans toucher l’existant", ->
    R.raises (->
      wpr.Mutation.updateWidgetPlugin {}, {
        id: plugin_id
        input: { manifest: 'columns:\n  - {name: a}\n' }
      }, CTX
    ), 'type is required'
    R.eq wpr.Query.widgetPlugin({}, { id: plugin_id }, CTX).manifest, "access: full\n"

  R.it "remet le manifest complet pour la suite", ->
    res = wpr.Mutation.updateWidgetPlugin {}, {
      id: plugin_id
      input: { manifest: MANIFEST }
    }, CTX
    R.eq res.manifest, MANIFEST

R.describe "WidgetPlugins — migration d’un tuple d’ancien format", ->

  R.it "un tuple sans champ manifest se lit avec manifest vide", ->
    old_id = "wpman_old_#{SUFFIX}"
    now = os.time!
    -- Format d'avant tdb_v5 : 9 champs, sans manifest. Le champ ajouté étant
    -- nullable en fin de format, Tarantool accepte encore ce tuple court.
    box.space._tdb_widget_plugins\insert {
      old_id, "wpman_old_name_#{SUFFIX}", '', 'coffeescript', 'pug', 'x', 'y', now, now
    }
    p = wpr.Query.widgetPlugin {}, { id: old_id }, CTX
    R.ok p
    R.eq p.manifest, ''

  R.it "migrate_widget_plugin_manifest complète les tuples courts", ->
    spaces = require 'core.spaces'
    n = spaces.migrate_widget_plugin_manifest!
    R.ok n >= 1, "au moins un tuple normalisé (obtenu #{n})"
    old = box.space._tdb_widget_plugins.index.by_scope_name\get { '', "wpman_old_name_#{SUFFIX}" }
    R.eq #old, 12, 'le tuple a maintenant 12 champs (manifest, app_id, compiled)'
    R.eq old[10], ''
    R.eq old[11], '', 'définition globale (bibliothèque)'
    R.eq old[12], '', 'aucun code compilé avant tdb_v7'
    R.eq spaces.migrate_widget_plugin_manifest!, 0, 'idempotente'
    box.space._tdb_widget_plugins\delete old[1]

R.describe "WidgetPlugins — mappage de colonnes dans le YAML de page", ->

  R.it "addWidgetToView écrit un mapping columns déclaré → champ", ->
    cvr = require 'resolvers.custom_view_resolvers'
    spaces = require 'core.spaces'
    cvw = require 'resolvers.custom_view_widgets'
    sp = spaces.create_user_space "wpman_map_#{SUFFIX}", ''
    page = cvr.Mutation.createCustomView {}, {
      name: "wpman_page_#{SUFFIX}"
      description: ''
      yaml: 'layout:\n  direction: vertical\n  children: []'
    }, CTX
    res = cvr.Mutation.addWidgetToView {}, {
      viewId: page.id
      widget: {
        title: 'Calendrier'
        type: NAME
        spaceId: sp.id
        fields: {}
        columns: { titre: 'nom', debut: 'date_debut' }
        params: { couleur: '#c33' }
      }
    }, CTX
    R.ok res
    R.matches res.yaml, 'columns:'
    R.matches res.yaml, 'titre: nom'
    R.matches res.yaml, 'debut: date_debut'
    config = yaml.decode res.yaml
    widget = config.layout.children[1].widget
    R.eq widget.type, NAME
    R.eq widget.columns.titre, 'nom'
    R.eq widget.columns.debut, 'date_debut'
    R.eq widget.params.couleur, '#c33'

    -- un réordonnancement conserve le mapping (pas de liste, pas de perte)
    reordered = cvw.reorder_widgets page.id, {
      { widgetId: widget.id, index: 1 }
    }
    again = yaml.decode(reordered.yaml).layout.children[1].widget
    R.eq again.columns.titre, 'nom'
    R.eq again.columns.debut, 'date_debut'

    cvr.Mutation.deleteCustomView {}, { id: page.id }, CTX
    spaces.delete_user_space sp.name

  R.it "un widget tableau garde une liste columns", ->
    cvr = require 'resolvers.custom_view_resolvers'
    spaces = require 'core.spaces'
    sp = spaces.create_user_space "wpman_list_#{SUFFIX}", ''
    page = cvr.Mutation.createCustomView {}, {
      name: "wpman_list_page_#{SUFFIX}"
      description: ''
      yaml: 'layout:\n  direction: vertical\n  children: []'
    }, CTX
    res = cvr.Mutation.addWidgetToView {}, {
      viewId: page.id
      widget: { title: 'Tableau', type: 'table', spaceId: sp.id, fields: { 'nom', 'age' } }
    }, CTX
    widget = yaml.decode(res.yaml).layout.children[1].widget
    R.eq #widget.columns, 2
    R.eq widget.columns[1], 'nom'
    R.eq widget.columns[2], 'age'
    cvr.Mutation.deleteCustomView {}, { id: page.id }, CTX
    spaces.delete_user_space sp.name

R.describe "WidgetPlugins — export et installation d’app", ->

  R.it "l’export inclut le manifest", ->
    row = box.space._tdb_widget_plugins\get plugin_id
    content = pkg.plugin_content row
    R.eq content.manifest, MANIFEST
    R.eq content.name, NAME

  R.it "l’empreinte change avec le manifest", ->
    base = { name: NAME, description: '', scriptLanguage: 'javascript',
             templateLanguage: 'html', scriptCode: 'c', templateCode: 't' }
    with_manifest = pkg.normalize_content 'plugin',
      { name: NAME, description: '', scriptLanguage: 'javascript',
        templateLanguage: 'html', scriptCode: 'c', templateCode: 't',
        manifest: "access: read\n" }
    without_manifest = pkg.normalize_content 'plugin', base
    R.eq with_manifest.manifest, "access: read\n"
    R.eq without_manifest.manifest, ''
    R.ne pkg.fingerprint(with_manifest), pkg.fingerprint(without_manifest)

  R.it "un aller-retour YAML conserve le manifest à l’identique", ->
    row = box.space._tdb_widget_plugins\get plugin_id
    content = pkg.plugin_content row
    decoded = yaml.decode yaml.encode { content: content }
    norm = pkg.normalize_content 'plugin', pkg.strip_null decoded.content
    R.eq norm.manifest, MANIFEST
    R.eq pkg.canonical(norm), pkg.canonical(content)

  R.it "l’installation recrée le manifest", ->
    -- Le paquet ne livre que les définitions référencées par ses pages ; ici la
    -- définition est posée directement (contenu de paquet, portée bibliothèque).
    row = box.space._tdb_widget_plugins\get plugin_id
    items = {
      { type: 'plugin', key: "plugin:#{NAME}", content: pkg.plugin_content(row), origin: 'library' }
    }
    R.eq items[1].content.manifest, MANIFEST

    -- Retire le plugin local : l'installation doit le recréer depuis le paquet.
    box.space._tdb_widget_plugins\delete plugin_id
    R.is_nil pkg.describe_local 'plugin', "plugin:#{NAME}"

    p = { app: { id: APP_ID, name: "wpman #{SUFFIX}", version: '1.0.0', description: '' }, items: items, seed_keys: {} }
    plan = apply.preview_update p
    R.eq #plan.errors, 0, 'preview errors'
    R.eq #plan.create, 1, 'plugin à créer'
    report = apply.apply_update p, {}, {}
    R.ok report.ok, report.error

    installed = pkg.describe_local 'plugin', "plugin:#{NAME}"
    R.ok installed
    R.eq installed.manifest, MANIFEST
    plugin_id = wpr.Query.widgetPlugin({}, { name: NAME }, CTX).id

  R.it "nettoie le plugin et le suivi d’app", ->
    box.space._tdb_widget_plugins\delete plugin_id if plugin_id
    box.space._tdb_app_items\delete { APP_ID, "plugin:#{NAME}" }
    box.space._tdb_apps\delete APP_ID
    R.is_nil pkg.describe_local 'plugin', "plugin:#{NAME}"
