-- tests/test_preset_page_cascade.moon
-- Préréglages de widgets attachés à une page ('widget:<pageId>:<widgetId>') :
--   (a) supprimer la page doit emporter ses préréglages (cascade), sinon le
--       scope survit à sa cible et devient inexploitable ;
--   (b) un préréglage orphelin déjà présent en base (base antérieure au
--       correctif) ne doit pas être exporté : preset_scope_portable y laisse
--       l'uuid brut, app_apply._preset_scope lève « unknown page » et annule
--       toute l'installation, describe_preset rend nil (fausse suppression).

R             = require 'tests.runner'
spaces_mod    = require 'core.spaces'
presets       = require 'core.view_presets'
app_package   = require 'core.app_package'
crud          = require 'resolvers.custom_view_crud'
export_r      = require 'resolvers.export_resolvers'

SUFFIX  = tostring math.random 100000, 999999
SP_NAME = "ppc_space_#{SUFFIX}"
PAGE_NAME = "ppc_page_#{SUFFIX}"

sp_id     = nil
page      = nil
scope_w1  = nil
ghost_page_id = "ghost-page-#{SUFFIX}"
ghost_space_id = "ghost-space-#{SUFFIX}"

-- Portable scope of a page: the page name, never its id.
portable_page_scope = (name, widget_id) -> "widget:#{name}:#{widget_id}"

R.describe "Préréglages — cascade à la suppression d'une page", ->

  R.it "setup : espace, page et préréglages de deux widgets", ->
    sp = spaces_mod.create_user_space SP_NAME, 'preset page cascade fixture'
    sp_id = sp.id
    page = crud.create_custom_view PAGE_NAME, 'page fixture', "title: #{PAGE_NAME}\n"
    R.ok page.id
    scope_w1 = "widget:#{page.id}:w1"
    a = presets.save_preset scope_w1, sp_id, 'Alpha', '', '[]'
    b = presets.save_preset "widget:#{page.id}:w2", sp_id, 'Bêta', 'self.x > 0', '[]'
    R.ok a.id
    R.ok b.id
    R.eq #presets.list_presets(scope_w1), 1

  R.it "deleteCustomView emporte les préréglages de ses widgets", ->
    R.ok crud.delete_custom_view page.id
    R.is_nil crud.get_custom_view page.id
    R.eq #presets.list_presets(scope_w1), 0, 'plus aucun préréglage pour le widget w1'
    R.eq #presets.list_presets("widget:#{page.id}:w2"), 0, 'plus aucun préréglage pour le widget w2'
    leftover = {}
    for t in *box.space._tdb_view_presets\select {}
      prefix = "widget:#{page.id}:"
      if type(t[2]) == 'string' and t[2]\sub(1, #prefix) == prefix
        table.insert leftover, t[2]
    R.eq #leftover, 0, "préréglage(s) orphelin(s) restant(s) : #{leftover[1]}"

  R.it "build_package ignore un préréglage dont la page n'existe plus", ->
    -- Base héritée d'avant la cascade : la page référencée n'existe pas.
    ghost_scope = portable_page_scope ghost_page_id, 'w1' -- id brut, jamais un nom
    presets.save_preset ghost_scope, sp_id, 'Fantôme', '', '[]'
    R.eq #presets.list_presets(ghost_scope), 1, 'préréglage orphelin présent en base'

    built = app_package.build_package { id: 'ppc', name: 'ppc', version: '1' }, {}
    exported = {}
    for item in *built.items
      if item.type == 'preset' and tostring(item.content.scope)\find ghost_page_id, 1, true
        table.insert exported, item.key
    R.eq #exported, 0, "préréglage orphelin exporté : #{exported[1]}"
    R.is_nil app_package.describe_local('preset', "preset:#{app_package.key_part ghost_scope}|Fantôme"),
      'le préréglage orphelin ne se décrit pas localement'

  R.it "build_snapshot ignore un préréglage orphelin (page ou espace disparu)", ->
    ghost_page_scope = portable_page_scope ghost_page_id, 'w1'
    ghost_space_scope = "space:#{ghost_space_id}"
    now = os.time!
    box.space._tdb_view_presets\insert {
      "ppc-ghost-space-#{SUFFIX}", ghost_space_scope, ghost_space_id, 'Perdu', '', '[]', now, now
    }

    snap = export_r.build_snapshot false
    orphans = {}
    for entry in *snap.schema.view_presets
      scope = tostring entry.scope
      if scope\find(ghost_page_id, 1, true) or scope\find(ghost_space_id, 1, true)
        table.insert orphans, scope
    R.eq #orphans, 0, "préréglage(s) orphelin(s) exporté(s) : #{orphans[1]}"

    -- Le snapshot produit doit être installable : aucune référence morte.
    built = app_package.build_package { id: 'ppc', name: 'ppc', version: '1' }, {}
    for item in *built.items
      continue unless item.type == 'preset'
      local_scope = app_package.preset_scope_local item.content.scope
      R.ok local_scope, "scope non résoluble exporté : #{item.content.scope}"

  R.it "une page existante garde ses préréglages à l'export", ->
    kept = crud.create_custom_view "ppc_keep_#{SUFFIX}", 'page conservée', "title: keep\n"
    scope = "widget:#{kept.id}:w1"
    presets.save_preset scope, sp_id, 'Gardé', '', '[]'
    built = app_package.build_package { id: 'ppc', name: 'ppc', version: '1' }, {}
    found = nil
    for item in *built.items
      found = item if item.type == 'preset' and item.content.name == 'Gardé'
    R.ok found, 'le préréglage de la page existante doit être exporté'
    R.eq found.content.scope, portable_page_scope("ppc_keep_#{SUFFIX}", 'w1'),
      'le scope exporté porte le nom de la page'
    crud.delete_custom_view kept.id

  R.it "cleanup", ->
    for t in *box.space._tdb_view_presets\select {}
      if t[3] == sp_id or t[3] == ghost_space_id
        box.space._tdb_view_presets\delete t[1]
    spaces_mod.delete_user_space SP_NAME
    require('resolvers.init').reinit!
