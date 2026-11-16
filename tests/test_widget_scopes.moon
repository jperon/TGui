-- tests/test_widget_scopes.moon
-- Portées des définitions de widgets personnalisés (spec
-- docs/superpowers/specs/2026-11-16-custom-widgets-design.md §5) :
-- migration (app_id, unicité par portée), résolution d'une instance (app de la
-- page, puis bibliothèque), export des seules définitions référencées avec
-- `origin`, installation dans la portée d'origine, trois choix de conflit et
-- suppression refusée d'une définition globale utilisée.

R = require 'tests.runner'
wpr = require 'resolvers.widget_plugin_resolvers'
scopes = require 'core.widget_scopes'
pkg = require 'core.app_package'
apply = require 'core.app_apply'
auth = require 'core.auth'
spaces = require 'core.spaces'
cvr = require 'resolvers.custom_view_resolvers'
json = require 'json'
yaml = require 'yaml'

SUFFIX = tostring math.random 100000, 999999
APP_A = "org.test.scope_a_#{SUFFIX}"
APP_B = "org.test.scope_b_#{SUFFIX}"
APP_C = "org.test.scope_c_#{SUFFIX}"
OWNER_A = "own_#{SUFFIX}"
PAGE_A_NAME = "scope_page_a_#{SUFFIX}"
PAGE_LOCAL_NAME = "scope_page_local_#{SUFFIX}"

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

FIX = { pages: {} }

-- Une app installée : createWidgetPlugin(appId) exige qu'elle existe.
register_app = (app_id, name) ->
  box.space._tdb_apps\replace { app_id, name, '1.0.0', os.time!, 'test' }

-- Une page dont le YAML contient une instance `type: <plugin>`.
page_yaml = (plugin_name) ->
  "layout:\n  direction: vertical\n  children:\n    - widget:\n        title: Test\n        type: #{plugin_name}\n"

create_page = (name, plugin_name) ->
  p = cvr.Mutation.createCustomView {}, {
    name: name
    description: ''
    yaml: page_yaml plugin_name
  }, CTX
  p

-- Une page livrée par une app (l'app de la page = celle de _tdb_app_items).
track_page = (app_id, page_id, page_name) ->
  box.space._tdb_app_items\replace {
    app_id, "page:#{pkg.key_part page_name}", 'page', page_id, 'fp', 'actif', '1.0.0'
  }

plugin = (name, app_id, opts = {}) ->
  input = {
    name: name
    description: opts.description or "scope test #{name}"
    scriptLanguage: 'javascript'
    templateLanguage: 'html'
    scriptCode: opts.scriptCode or "module.exports = function (api) { api.render('<b>#{name}</b>'); };"
    templateCode: '<b>init</b>'
    manifest: opts.manifest or ''
  }
  input.appId = app_id if app_id
  wpr.Mutation.createWidgetPlugin {}, { input: input }, CTX

delete_plugin = (p) ->
  box.space._tdb_widget_plugins\delete p.id if p and p.id

delete_page = (p) ->
  box.space._tdb_custom_views\delete p.id if p and p.id

clean_app = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

-- ────────────────────────────────────────────────────────────────────────────
-- Fixture
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — fixture", ->

  R.it "enregistre deux apps et leurs définitions homonymes", ->
    register_app APP_A, "Scope A #{SUFFIX}"
    register_app APP_B, "Scope B #{SUFFIX}"
    register_app APP_C, "Scope C #{SUFFIX}"
    FIX.global = plugin "wscope_#{SUFFIX}", nil
    FIX.app_a = plugin "wscope_#{SUFFIX}", APP_A
    FIX.app_b = plugin "wscope_#{SUFFIX}", APP_B
    FIX.global_only = plugin "wscope_global_#{SUFFIX}", nil
    R.ne FIX.global.id, FIX.app_a.id
    R.eq FIX.app_a.appId, APP_A
    R.is_nil FIX.global.appId
    R.eq scopes.find_row("wscope_#{SUFFIX}", nil)[1], FIX.global.id
    R.eq scopes.find_row("wscope_#{SUFFIX}", APP_A)[1], FIX.app_a.id
    R.eq scopes.find_row("wscope_#{SUFFIX}", APP_B)[1], FIX.app_b.id

  R.it "crée une page de l'app A et une page locale, toutes deux sur ce nom", ->
    FIX.pages.a = create_page PAGE_A_NAME, "wscope_#{SUFFIX}"
    track_page APP_A, FIX.pages.a.id, PAGE_A_NAME
    FIX.pages.local = create_page PAGE_LOCAL_NAME, "wscope_#{SUFFIX}"
    -- Une page d'une app qui ne définit pas ce nom : elle retombe sur la globale.
    FIX.pages.a_global = create_page "scope_page_c_#{SUFFIX}", "wscope_#{SUFFIX}"
    track_page APP_C, FIX.pages.a_global.id, "scope_page_c_#{SUFFIX}"
    -- Une page locale qui ne référence qu'une définition globale.
    FIX.pages.global_only = create_page "scope_page_glob_#{SUFFIX}", "wscope_global_#{SUFFIX}"
    R.ok FIX.pages.a.id
    R.ok FIX.pages.local.id
    R.eq scopes.page_app_id(FIX.pages.a.id), APP_A
    R.is_nil scopes.page_app_id(FIX.pages.local.id)

-- ────────────────────────────────────────────────────────────────────────────
-- Unicité du nom par portée
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — unicité du nom par portée", ->

  R.it "accepte le même nom dans la bibliothèque et dans deux apps", ->
    R.ok scopes.find_row "wscope_#{SUFFIX}", nil
    R.ok scopes.find_row "wscope_#{SUFFIX}", APP_A
    R.ok scopes.find_row "wscope_#{SUFFIX}", APP_B

  R.it "refuse un doublon dans la même portée", ->
    R.raises (-> plugin "wscope_#{SUFFIX}", nil), 'name already exists'
    R.raises (-> plugin "wscope_#{SUFFIX}", APP_A), 'name already exists'

  R.it "refuse une portée inconnue", ->
    R.raises (-> plugin "wscope_orphan_#{SUFFIX}", "org.test.unknown_#{SUFFIX}"), 'Unknown app'

  R.it "déplace une définition vers la bibliothèque sans collision", ->
    moved = plugin "wscope_move_#{SUFFIX}", APP_A
    res = wpr.Mutation.updateWidgetPlugin {}, {
      id: moved.id
      input: { appId: '' }
    }, CTX
    R.is_nil res.appId
    R.eq scopes.find_row("wscope_move_#{SUFFIX}", nil)[1], moved.id
    R.is_nil scopes.find_row "wscope_move_#{SUFFIX}", APP_A
    delete_plugin moved

-- ────────────────────────────────────────────────────────────────────────────
-- Résolution d'une instance : app de la page, sinon globale
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — résolution d’une instance", ->

  R.it "une page de l'app A résout la définition de A", ->
    row = scopes.resolve_for_page "wscope_#{SUFFIX}", FIX.pages.a.id
    R.eq row[1], FIX.app_a.id
    p = wpr.Query.widgetPlugin {}, { name: "wscope_#{SUFFIX}", pageId: FIX.pages.a.id }, CTX
    R.eq p.id, FIX.app_a.id
    R.eq p.appId, APP_A

  R.it "une page locale résout la définition globale", ->
    row = scopes.resolve_for_page "wscope_#{SUFFIX}", FIX.pages.local.id
    R.eq row[1], FIX.global.id
    p = wpr.Query.widgetPlugin {}, { name: "wscope_#{SUFFIX}", pageId: FIX.pages.local.id }, CTX
    R.eq p.id, FIX.global.id
    R.is_nil p.appId

  R.it "une page d'une app sans définition propre résout la globale", ->
    row = scopes.resolve_for_page "wscope_#{SUFFIX}", FIX.pages.a_global.id
    R.eq row[1], FIX.global.id

  R.it "widgetPlugins(pageId) liste les définitions visibles, sans doublon", ->
    list = wpr.Query.widgetPlugins {}, { pageId: FIX.pages.a.id }, CTX
    names = [p.name for p in *list]
    R.eq #([n for n in *names when n == "wscope_#{SUFFIX}"]), 1, 'un seul exemplaire de ce nom'
    mine = [p for p in *list when p.name == "wscope_#{SUFFIX}"]
    R.eq mine[1].id, FIX.app_a.id, 'la définition de l’app masque la globale'
    R.is_nil (([p for p in *list when p.id == FIX.app_b.id])[1]), 'la définition de B n’est pas visible'

  R.it "widgetPlugins() sans argument liste toutes les portées (éditeur)", ->
    list = wpr.Query.widgetPlugins {}, {}, CTX
    seen = {}
    seen[p.id] = true for p in *list
    R.ok seen[FIX.global.id], 'globale présente'
    R.ok seen[FIX.app_a.id], 'définition de A présente'
    R.ok seen[FIX.app_b.id], 'définition de B présente'

-- ────────────────────────────────────────────────────────────────────────────
-- Export : seules les définitions référencées, avec origin
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — export des définitions référencées", ->

  R.it "ne livre que les définitions référencées par les pages", ->
    built = pkg.build_package {
      id: APP_A, name: 'Scope export', version: '1.0.0', description: ''
    }, {}
    keys = {}
    for it in *built.items
      keys[it.key] = it if it.type == 'plugin'
    R.ok keys["plugin:wscope_#{SUFFIX}"], 'la définition référencée est livrée'
    R.is_nil keys["plugin:wscope_unused_#{SUFFIX}"], 'une définition non référencée reste à la maison'

  R.it "marque origin app ou library selon la portée de la définition livrée", ->
    built = pkg.build_package {
      id: APP_A, name: 'Scope export', version: '1.0.0', description: ''
    }, {}
    item = ([it for it in *built.items when it.key == "plugin:wscope_#{SUFFIX}"])[1]
    R.eq item.origin, 'app', 'la définition de l’app exportée est livrée en portée app'
    global_item = ([it for it in *built.items when it.key == "plugin:wscope_global_#{SUFFIX}"])[1]
    R.ok global_item, 'la définition globale référencée est livrée'
    R.eq global_item.origin, 'library'

  R.it "une définition propre à une autre app est livrée avec le paquet", ->
    built = pkg.build_package {
      id: "org.test.other_#{SUFFIX}", name: 'Other', version: '1.0.0', description: ''
    }, {}
    item = ([it for it in *built.items when it.key == "plugin:wscope_#{SUFFIX}"])[1]
    R.ok item, 'la définition résolue par la page est livrée'
    R.eq item.content.name, "wscope_#{SUFFIX}"

  R.it "l’empreinte couvre manifest, script, gabarit et langages, pas la portée", ->
    content = pkg.plugin_content box.space._tdb_widget_plugins\get FIX.global.id
    from_a = pkg.plugin_content box.space._tdb_widget_plugins\get FIX.app_a.id
    R.eq pkg.fingerprint(content), pkg.fingerprint(from_a), 'même code, même empreinte quelle que soit la portée'
    with_manifest = {}
    with_manifest[k] = v for k, v in pairs content
    with_manifest.manifest = "access: read\n"
    R.ne pkg.fingerprint(content), pkg.fingerprint(with_manifest)
    other_script = {}
    other_script[k] = v for k, v in pairs content
    other_script.scriptCode = "module.exports = function () {}"
    R.ne pkg.fingerprint(content), pkg.fingerprint(other_script)

-- ────────────────────────────────────────────────────────────────────────────
-- Installation : absente, même empreinte, conflit et trois choix
-- ────────────────────────────────────────────────────────────────────────────

item_of = (name, origin, extra = {}) ->
  content = {
    name: name
    description: extra.description or "livré #{name}"
    scriptLanguage: 'javascript'
    templateLanguage: 'html'
    scriptCode: extra.scriptCode or "module.exports = function (api) { api.render('<i>#{name}</i>'); };"
    templateCode: '<i>init</i>'
    manifest: extra.manifest or ''
  }
  { type: 'plugin', key: "plugin:#{name}", content: content, origin: origin }

package_of = (app_id, items) ->
  { app: { id: app_id, name: 'Scope install', version: '1.0.0', description: '' },
    items: items, seed_keys: {} }

R.describe "WidgetScopes — installation", ->

  R.it "crée une définition absente dans sa portée (bibliothèque ou app)", ->
    library_name = "wscope_install_lib_#{SUFFIX}"
    app_name = "wscope_install_app_#{SUFFIX}"
    p = package_of APP_A, {
      item_of library_name, 'library'
      item_of app_name, 'app'
    }
    report = apply.apply_update p, {}, {}
    R.ok report.ok, report.error
    lib_row = scopes.find_row library_name, nil
    R.ok lib_row, 'définition de bibliothèque créée'
    R.is_nil (scopes.scope_of lib_row[11]), 'app_id vide = bibliothèque'
    app_row = scopes.find_row app_name, APP_A
    R.ok app_row, 'définition créée dans l’app du paquet'
    R.is_nil scopes.find_row app_name, nil

    -- Même empreinte : réutilisée, aucun conflit.
    plan = apply.preview_update p
    R.eq #plan.errors, 0
    R.eq #plan.conflict, 0, 'aucun conflit'
    R.eq #plan.create, 0, 'aucune création'
    report2 = apply.apply_update p, {}, {}
    R.ok report2.ok, report2.error
    R.eq #report2.unchanged, 2, 'les deux définitions sont inchangées'

  R.it "conflit sur empreinte différente : garder le local", ->
    name = "wscope_keep_#{SUFFIX}"
    p1 = package_of APP_A, { item_of name, 'library' }
    R.ok (apply.apply_update p1, {}, {}).ok
    wpr.Mutation.updateWidgetPlugin {}, {
      id: (scopes.find_row name, nil)[1]
      input: { description: 'modifié localement' }
    }, CTX
    -- L'auteur publie une nouvelle version : les deux côtés ont changé.
    p2 = package_of APP_A, { item_of name, 'library', { description: 'livré v2' } }
    plan = apply.preview_update p2
    R.eq #plan.conflict, 1, 'conflit détecté'
    R.eq plan.conflict[1][1].key, "plugin:#{name}"
    report = apply.apply_update p2, { ["plugin:#{name}"]: 'local' }, {}
    R.ok report.ok, report.error
    R.eq (scopes.find_row name, nil)[3], 'modifié localement', 'le local est conservé'

  R.it "conflit : remplacer par la version livrée", ->
    name = "wscope_replace_#{SUFFIX}"
    p1 = package_of APP_A, { item_of name, 'library' }
    R.ok (apply.apply_update p1, {}, {}).ok
    wpr.Mutation.updateWidgetPlugin {}, {
      id: (scopes.find_row name, nil)[1]
      input: { description: 'modifié localement' }
    }, CTX
    p2 = package_of APP_A, { item_of name, 'library', { description: 'livré v2' } }
    report = apply.apply_update p2, { ["plugin:#{name}"]: 'delivered' }, {}
    R.ok report.ok, report.error
    R.eq (scopes.find_row name, nil)[3], 'livré v2', 'la version livrée remplace la locale'

  R.it "conflit : importer sous un autre nom (défaut), pages réécrites", ->
    name = "wscope_rename_#{SUFFIX}"
    page_name = "wscope_rename_page_#{SUFFIX}"
    -- L'auteur : une définition globale et une page qui la référence.
    plugin name, nil
    create_page page_name, name
    built = pkg.build_package {
      id: APP_A, name: 'Scope rename', version: '1.0.0', description: ''
    }, {}
    items = [it for it in *built.items when it.key\find SUFFIX, 1, true]
    has_page = [it for it in *items when it.key == "page:#{page_name}"]
    R.eq #has_page, 1, 'la page livrée est dans le paquet'
    p1 = { app: built.app, items: items, seed_keys: {} }
    R.ok (apply.apply_update p1, {}, {}).ok

    -- Modification locale de la définition : conflit au prochain import.
    wpr.Mutation.updateWidgetPlugin {}, {
      id: (scopes.find_row name, nil)[1]
      input: { description: 'modifié localement' }
    }, CTX
    -- L'auteur publie une nouvelle version de la définition (page inchangée).
    items2 = {}
    for it in *items
      if it.key == "plugin:#{name}"
        content = {}
        content[k] = v for k, v in pairs it.content
        content.description = 'livré v2'
        table.insert items2, {
          type: it.type, key: it.key, content: content, origin: it.origin
        }
      else
        table.insert items2, it
    p2 = { app: built.app, items: items2, seed_keys: {} }

    app_r = require 'resolvers.app_resolvers'
    shaped = app_r.Query.previewAppUpdate nil, { yaml: yaml.encode p2 }, CTX
    conflict = ([c for c in *shaped.conflict when c.key == "plugin:#{name}"])[1]
    R.ok conflict, 'conflit sur la définition'
    listed = false
    for listed_page in *(conflict.pages or {})
      listed = true if listed_page == page_name
    R.ok listed, 'la page touchée est listée'

    -- Sans décision : « importer sous un autre nom » est le défaut.
    report = apply.apply_update p2, {}, {}
    R.ok report.ok, report.error
    R.ok (scopes.find_row name, nil)[1], 'la définition locale est conservée'
    imported = scopes.find_row "#{name}_imported", nil
    R.ok imported, 'la définition livrée est importée sous un autre nom'
    R.eq imported[3], 'livré v2', 'la copie porte le contenu livré'
    R.eq (scopes.find_row name, nil)[3], 'modifié localement', 'le local n’est pas écrasé'
    stored_page = box.space._tdb_custom_views.index.by_name\get page_name
    R.ok stored_page, 'la page livrée existe'
    R.matches stored_page[4], "type: #{name}_imported"
    R.is_nil stored_page[4]\find("type: #{name}\n", 1, true), 'plus aucune référence à l’ancien nom'

  R.it "conflit sur une définition locale non suivie (installation neuve) : remplacer", ->
    name = "wscope_fresh_#{SUFFIX}"
    plugin name, nil
    wpr.Mutation.updateWidgetPlugin {}, {
      id: (scopes.find_row name, nil)[1]
      input: { description: 'local seul' }
    }, CTX
    p = package_of APP_A, { item_of name, 'library', { description: 'livré neuf' } }
    plan = apply.preview_update p
    R.eq #plan.conflict, 1, 'une définition locale non suivie entre en conflit'
    report = apply.apply_update p, { ["plugin:#{name}"]: 'delivered' }, {}
    R.ok report.ok, report.error
    R.eq (scopes.find_row name, nil)[3], 'livré neuf', 'la définition locale est remplacée'

  R.it "conflit : importer sous un nom choisi par la décision newName", ->
    name = "wscope_named_#{SUFFIX}"
    p1 = package_of APP_A, { item_of name, 'library' }
    R.ok (apply.apply_update p1, {}, {}).ok
    wpr.Mutation.updateWidgetPlugin {}, {
      id: (scopes.find_row name, nil)[1]
      input: { description: 'modifié localement' }
    }, CTX
    p2 = package_of APP_A, { item_of name, 'library', { description: 'livré v2' } }
    report = apply.apply_update p2, { ["plugin:#{name}"]: 'rename' }, {
      rename_names: { ["plugin:#{name}"]: "wscope_named_copy_#{SUFFIX}" }
    }
    R.ok report.ok, report.error
    R.ok scopes.find_row "wscope_named_copy_#{SUFFIX}", nil
    R.is_nil scopes.find_row "#{name}_imported", nil

-- ────────────────────────────────────────────────────────────────────────────
-- Suppression d'une définition globale utilisée
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — suppression d’une définition utilisée", ->

  R.it "refuse la suppression d’une définition globale utilisée, en listant les pages", ->
    name = "wscope_used_#{SUFFIX}"
    p = plugin name, nil
    page = create_page "wscope_used_page_#{SUFFIX}", name
    ok, err = pcall -> wpr.Mutation.deleteWidgetPlugin {}, { id: p.id }, CTX
    R.nok ok, 'suppression refusée'
    R.matches (tostring err), 'is used by page'
    R.matches (tostring err), "wscope_used_page_#{SUFFIX}"
    R.ok box.space._tdb_widget_plugins\get(p.id), 'la définition est toujours là'
    delete_page page

  R.it "accepte la suppression quand plus aucune page ne l’utilise", ->
    name = "wscope_free_#{SUFFIX}"
    p = plugin name, nil
    R.ok wpr.Mutation.deleteWidgetPlugin {}, { id: p.id }, CTX
    R.is_nil scopes.find_row name, nil

  R.it "accepte la suppression d’une définition d’app même utilisée", ->
    name = "wscope_appdel_#{SUFFIX}"
    p = plugin name, APP_A
    page = create_page "wscope_appdel_page_#{SUFFIX}", name
    track_page APP_A, page.id, "wscope_appdel_page_#{SUFFIX}"
    R.eq scopes.resolve_for_page(name, page.id)[1], p.id
    R.ok wpr.Mutation.deleteWidgetPlugin {}, { id: p.id }, CTX
    R.is_nil scopes.find_row name, APP_A
    delete_page page

-- ────────────────────────────────────────────────────────────────────────────
-- Migration
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — migration d’un tuple d’ancien format", ->

  R.it "un tuple de 10 champs devient une définition de bibliothèque", ->
    old_id = "wscope_old_#{SUFFIX}"
    old_name = "wscope_old_name_#{SUFFIX}"
    now = os.time!
    box.space._tdb_widget_plugins\insert {
      old_id, old_name, '', 'coffeescript', 'pug', 'x', 'y', now, now, ''
    }
    R.is_nil scopes.find_row old_name, nil
    n = spaces.migrate_widget_plugin_app_id!
    R.ok n >= 1, "au moins un tuple normalisé (obtenu #{n})"
    row = scopes.find_row old_name, nil
    R.ok row, 'la définition est désormais globale'
    R.eq #row, 11
    R.eq row[11], ''
    R.eq spaces.migrate_widget_plugin_app_id!, 0, 'idempotente'
    box.space._tdb_widget_plugins\delete old_id

-- ────────────────────────────────────────────────────────────────────────────
-- Nettoyage
-- ────────────────────────────────────────────────────────────────────────────

R.describe "WidgetScopes — cleanup", ->

  R.it "supprime les pages, définitions et apps de la fixture", ->
    for _, p in pairs FIX.pages
      delete_page p
    rename_page = box.space._tdb_custom_views.index.by_name\get "wscope_rename_page_#{SUFFIX}"
    box.space._tdb_custom_views\delete rename_page[1] if rename_page
    for row in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete row[1] if row[2]\find SUFFIX, 1, true
    for page in *box.space._tdb_custom_views\select {}
      box.space._tdb_custom_views\delete page[1] if page[2]\find SUFFIX, 1, true
    clean_app APP_A
    clean_app APP_B
    clean_app APP_C
    R.is_nil scopes.find_row "wscope_#{SUFFIX}", nil
    R.is_nil scopes.find_row "wscope_#{SUFFIX}", APP_A
