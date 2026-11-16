local R = require('tests.runner')
local wpr = require('resolvers.widget_plugin_resolvers')
local scopes = require('core.widget_scopes')
local pkg = require('core.app_package')
local apply = require('core.app_apply')
local auth = require('core.auth')
local spaces = require('core.spaces')
local cvr = require('resolvers.custom_view_resolvers')
local json = require('json')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local APP_A = "org.test.scope_a_" .. tostring(SUFFIX)
local APP_B = "org.test.scope_b_" .. tostring(SUFFIX)
local APP_C = "org.test.scope_c_" .. tostring(SUFFIX)
local OWNER_A = "own_" .. tostring(SUFFIX)
local PAGE_A_NAME = "scope_page_a_" .. tostring(SUFFIX)
local PAGE_LOCAL_NAME = "scope_page_local_" .. tostring(SUFFIX)
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local FIX = {
  pages = { }
}
local register_app
register_app = function(app_id, name)
  return box.space._tdb_apps:replace({
    app_id,
    name,
    '1.0.0',
    os.time(),
    'test'
  })
end
local page_yaml
page_yaml = function(plugin_name)
  return "layout:\n  direction: vertical\n  children:\n    - widget:\n        title: Test\n        type: " .. tostring(plugin_name) .. "\n"
end
local create_page
create_page = function(name, plugin_name)
  local p = cvr.Mutation.createCustomView({ }, {
    name = name,
    description = '',
    yaml = page_yaml(plugin_name)
  }, CTX)
  return p
end
local track_page
track_page = function(app_id, page_id, page_name)
  return box.space._tdb_app_items:replace({
    app_id,
    "page:" .. tostring(pkg.key_part(page_name)),
    'page',
    page_id,
    'fp',
    'actif',
    '1.0.0'
  })
end
local plugin
plugin = function(name, app_id, opts)
  if opts == nil then
    opts = { }
  end
  local input = {
    name = name,
    description = opts.description or "scope test " .. tostring(name),
    scriptLanguage = 'javascript',
    templateLanguage = 'html',
    scriptCode = opts.scriptCode or "module.exports = function (api) { api.render('<b>" .. tostring(name) .. "</b>'); };",
    templateCode = '<b>init</b>',
    manifest = opts.manifest or ''
  }
  if app_id then
    input.appId = app_id
  end
  return wpr.Mutation.createWidgetPlugin({ }, {
    input = input
  }, CTX)
end
local delete_plugin
delete_plugin = function(p)
  if p and p.id then
    return box.space._tdb_widget_plugins:delete(p.id)
  end
end
local delete_page
delete_page = function(p)
  if p and p.id then
    return box.space._tdb_custom_views:delete(p.id)
  end
end
local clean_app
clean_app = function(app_id)
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    box.space._tdb_app_items:delete({
      t[1],
      t[2]
    })
  end
  return box.space._tdb_apps:delete(app_id)
end
R.describe("WidgetScopes — fixture", function()
  R.it("enregistre deux apps et leurs définitions homonymes", function()
    register_app(APP_A, "Scope A " .. tostring(SUFFIX))
    register_app(APP_B, "Scope B " .. tostring(SUFFIX))
    register_app(APP_C, "Scope C " .. tostring(SUFFIX))
    FIX.global = plugin("wscope_" .. tostring(SUFFIX), nil)
    FIX.app_a = plugin("wscope_" .. tostring(SUFFIX), APP_A)
    FIX.app_b = plugin("wscope_" .. tostring(SUFFIX), APP_B)
    FIX.global_only = plugin("wscope_global_" .. tostring(SUFFIX), nil)
    R.ne(FIX.global.id, FIX.app_a.id)
    R.eq(FIX.app_a.appId, APP_A)
    R.is_nil(FIX.global.appId)
    R.eq(scopes.find_row("wscope_" .. tostring(SUFFIX), nil)[1], FIX.global.id)
    R.eq(scopes.find_row("wscope_" .. tostring(SUFFIX), APP_A)[1], FIX.app_a.id)
    return R.eq(scopes.find_row("wscope_" .. tostring(SUFFIX), APP_B)[1], FIX.app_b.id)
  end)
  return R.it("crée une page de l'app A et une page locale, toutes deux sur ce nom", function()
    FIX.pages.a = create_page(PAGE_A_NAME, "wscope_" .. tostring(SUFFIX))
    track_page(APP_A, FIX.pages.a.id, PAGE_A_NAME)
    FIX.pages["local"] = create_page(PAGE_LOCAL_NAME, "wscope_" .. tostring(SUFFIX))
    FIX.pages.a_global = create_page("scope_page_c_" .. tostring(SUFFIX), "wscope_" .. tostring(SUFFIX))
    track_page(APP_C, FIX.pages.a_global.id, "scope_page_c_" .. tostring(SUFFIX))
    FIX.pages.global_only = create_page("scope_page_glob_" .. tostring(SUFFIX), "wscope_global_" .. tostring(SUFFIX))
    R.ok(FIX.pages.a.id)
    R.ok(FIX.pages["local"].id)
    R.eq(scopes.page_app_id(FIX.pages.a.id), APP_A)
    return R.is_nil(scopes.page_app_id(FIX.pages["local"].id))
  end)
end)
R.describe("WidgetScopes — unicité du nom par portée", function()
  R.it("accepte le même nom dans la bibliothèque et dans deux apps", function()
    R.ok(scopes.find_row("wscope_" .. tostring(SUFFIX), nil))
    R.ok(scopes.find_row("wscope_" .. tostring(SUFFIX), APP_A))
    return R.ok(scopes.find_row("wscope_" .. tostring(SUFFIX), APP_B))
  end)
  R.it("refuse un doublon dans la même portée", function()
    R.raises((function()
      return plugin("wscope_" .. tostring(SUFFIX), nil)
    end), 'name already exists')
    return R.raises((function()
      return plugin("wscope_" .. tostring(SUFFIX), APP_A)
    end), 'name already exists')
  end)
  R.it("refuse une portée inconnue", function()
    return R.raises((function()
      return plugin("wscope_orphan_" .. tostring(SUFFIX), "org.test.unknown_" .. tostring(SUFFIX))
    end), 'Unknown app')
  end)
  R.it("refuse de changer la portée d’une définition utilisée", function()
    local name = "wscope_move_used_" .. tostring(SUFFIX)
    local p = plugin(name, nil)
    local page = create_page("wscope_move_page_" .. tostring(SUFFIX), name)
    local ok, err = pcall(function()
      return wpr.Mutation.updateWidgetPlugin({ }, {
        id = p.id,
        input = {
          appId = APP_A
        }
      }, CTX)
    end)
    R.nok(ok, 'changement de portée refusé')
    R.matches((tostring(err)), 'cannot change scope')
    R.matches((tostring(err)), "wscope_move_page_" .. tostring(SUFFIX))
    R.eq(scopes.find_row(name, nil)[1], p.id, 'la définition reste globale')
    return delete_page(page)
  end)
  return R.it("déplace une définition non utilisée vers la bibliothèque sans collision", function()
    local moved = plugin("wscope_move_" .. tostring(SUFFIX), APP_A)
    local res = wpr.Mutation.updateWidgetPlugin({ }, {
      id = moved.id,
      input = {
        appId = ''
      }
    }, CTX)
    R.is_nil(res.appId)
    R.eq(scopes.find_row("wscope_move_" .. tostring(SUFFIX), nil)[1], moved.id)
    R.is_nil(scopes.find_row("wscope_move_" .. tostring(SUFFIX), APP_A))
    return delete_plugin(moved)
  end)
end)
R.describe("WidgetScopes — résolution d’une instance", function()
  R.it("une page de l'app A résout la définition de A", function()
    local row = scopes.resolve_for_page("wscope_" .. tostring(SUFFIX), FIX.pages.a.id)
    R.eq(row[1], FIX.app_a.id)
    local p = wpr.Query.widgetPlugin({ }, {
      name = "wscope_" .. tostring(SUFFIX),
      pageId = FIX.pages.a.id
    }, CTX)
    R.eq(p.id, FIX.app_a.id)
    return R.eq(p.appId, APP_A)
  end)
  R.it("une page locale résout la définition globale", function()
    local row = scopes.resolve_for_page("wscope_" .. tostring(SUFFIX), FIX.pages["local"].id)
    R.eq(row[1], FIX.global.id)
    local p = wpr.Query.widgetPlugin({ }, {
      name = "wscope_" .. tostring(SUFFIX),
      pageId = FIX.pages["local"].id
    }, CTX)
    R.eq(p.id, FIX.global.id)
    return R.is_nil(p.appId)
  end)
  R.it("une page d'une app sans définition propre résout la globale", function()
    local row = scopes.resolve_for_page("wscope_" .. tostring(SUFFIX), FIX.pages.a_global.id)
    return R.eq(row[1], FIX.global.id)
  end)
  R.it("widgetPlugins(pageId) liste les définitions visibles, sans doublon", function()
    local list = wpr.Query.widgetPlugins({ }, {
      pageId = FIX.pages.a.id
    }, CTX)
    local names
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #list do
        local p = list[_index_0]
        _accum_0[_len_0] = p.name
        _len_0 = _len_0 + 1
      end
      names = _accum_0
    end
    R.eq(#((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #names do
        local n = names[_index_0]
        if n == "wscope_" .. tostring(SUFFIX) then
          _accum_0[_len_0] = n
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)()), 1, 'un seul exemplaire de ce nom')
    local mine
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #list do
        local p = list[_index_0]
        if p.name == "wscope_" .. tostring(SUFFIX) then
          _accum_0[_len_0] = p
          _len_0 = _len_0 + 1
        end
      end
      mine = _accum_0
    end
    R.eq(mine[1].id, FIX.app_a.id, 'la définition de l’app masque la globale')
    return R.is_nil((((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #list do
        local p = list[_index_0]
        if p.id == FIX.app_b.id then
          _accum_0[_len_0] = p
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)())[1]), 'la définition de B n’est pas visible')
  end)
  return R.it("widgetPlugins() sans argument liste toutes les portées (éditeur)", function()
    local list = wpr.Query.widgetPlugins({ }, { }, CTX)
    local seen = { }
    for _index_0 = 1, #list do
      local p = list[_index_0]
      seen[p.id] = true
    end
    R.ok(seen[FIX.global.id], 'globale présente')
    R.ok(seen[FIX.app_a.id], 'définition de A présente')
    return R.ok(seen[FIX.app_b.id], 'définition de B présente')
  end)
end)
R.describe("WidgetScopes — export des définitions référencées", function()
  R.it("ne livre que les définitions référencées par les pages", function()
    local built = pkg.build_package({
      id = APP_A,
      name = 'Scope export',
      version = '1.0.0',
      description = ''
    }, { })
    local keys = { }
    local _list_0 = built.items
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.type == 'plugin' then
        keys[it.key] = it
      end
    end
    R.ok(keys["plugin:wscope_" .. tostring(SUFFIX)], 'la définition référencée est livrée')
    return R.is_nil(keys["plugin:wscope_unused_" .. tostring(SUFFIX)], 'une définition non référencée reste à la maison')
  end)
  R.it("marque origin app ou library selon la portée de la définition livrée", function()
    local built = pkg.build_package({
      id = APP_A,
      name = 'Scope export',
      version = '1.0.0',
      description = ''
    }, { })
    local item = ((function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = built.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.key == "plugin:wscope_" .. tostring(SUFFIX) then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)())[1]
    R.eq(item.origin, 'app', 'la définition de l’app exportée est livrée en portée app')
    local global_item = ((function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = built.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.key == "plugin:wscope_global_" .. tostring(SUFFIX) then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)())[1]
    R.ok(global_item, 'la définition globale référencée est livrée')
    return R.eq(global_item.origin, 'library')
  end)
  R.it("une définition propre à une autre app est livrée avec le paquet", function()
    local built = pkg.build_package({
      id = "org.test.other_" .. tostring(SUFFIX),
      name = 'Other',
      version = '1.0.0',
      description = ''
    }, { })
    local item = ((function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = built.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.key == "plugin:wscope_" .. tostring(SUFFIX) then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)())[1]
    R.ok(item, 'la définition résolue par la page est livrée')
    return R.eq(item.content.name, "wscope_" .. tostring(SUFFIX))
  end)
  return R.it("l’empreinte couvre manifest, script, gabarit et langages, pas la portée", function()
    local content = pkg.plugin_content(box.space._tdb_widget_plugins:get(FIX.global.id))
    local from_a = pkg.plugin_content(box.space._tdb_widget_plugins:get(FIX.app_a.id))
    R.eq(pkg.fingerprint(content), pkg.fingerprint(from_a), 'même code, même empreinte quelle que soit la portée')
    local with_manifest = { }
    for k, v in pairs(content) do
      with_manifest[k] = v
    end
    with_manifest.manifest = "access: read\n"
    R.ne(pkg.fingerprint(content), pkg.fingerprint(with_manifest))
    local other_script = { }
    for k, v in pairs(content) do
      other_script[k] = v
    end
    other_script.scriptCode = "module.exports = function () {}"
    return R.ne(pkg.fingerprint(content), pkg.fingerprint(other_script))
  end)
end)
local item_of
item_of = function(name, origin, extra)
  if extra == nil then
    extra = { }
  end
  local content = {
    name = name,
    description = extra.description or "livré " .. tostring(name),
    scriptLanguage = 'javascript',
    templateLanguage = 'html',
    scriptCode = extra.scriptCode or "module.exports = function (api) { api.render('<i>" .. tostring(name) .. "</i>'); };",
    templateCode = '<i>init</i>',
    manifest = extra.manifest or ''
  }
  return {
    type = 'plugin',
    key = "plugin:" .. tostring(name),
    content = content,
    origin = origin
  }
end
local package_of
package_of = function(app_id, items)
  return {
    app = {
      id = app_id,
      name = 'Scope install',
      version = '1.0.0',
      description = ''
    },
    items = items,
    seed_keys = { }
  }
end
R.describe("WidgetScopes — installation", function()
  R.it("crée une définition absente dans sa portée (bibliothèque ou app)", function()
    local library_name = "wscope_install_lib_" .. tostring(SUFFIX)
    local app_name = "wscope_install_app_" .. tostring(SUFFIX)
    local p = package_of(APP_A, {
      item_of(library_name, 'library'),
      item_of(app_name, 'app')
    })
    local report = apply.apply_update(p, { }, { })
    R.ok(report.ok, report.error)
    local lib_row = scopes.find_row(library_name, nil)
    R.ok(lib_row, 'définition de bibliothèque créée')
    R.is_nil((scopes.scope_of(lib_row[11])), 'app_id vide = bibliothèque')
    local app_row = scopes.find_row(app_name, APP_A)
    R.ok(app_row, 'définition créée dans l’app du paquet')
    R.is_nil(scopes.find_row(app_name, nil))
    local plan = apply.preview_update(p)
    R.eq(#plan.errors, 0)
    R.eq(#plan.conflict, 0, 'aucun conflit')
    R.eq(#plan.create, 0, 'aucune création')
    local report2 = apply.apply_update(p, { }, { })
    R.ok(report2.ok, report2.error)
    return R.eq(#report2.unchanged, 2, 'les deux définitions sont inchangées')
  end)
  R.it("conflit sur empreinte différente : garder le local", function()
    local name = "wscope_keep_" .. tostring(SUFFIX)
    local p1 = package_of(APP_A, {
      item_of(name, 'library')
    })
    R.ok((apply.apply_update(p1, { }, { })).ok)
    wpr.Mutation.updateWidgetPlugin({ }, {
      id = (scopes.find_row(name, nil))[1],
      input = {
        description = 'modifié localement'
      }
    }, CTX)
    local p2 = package_of(APP_A, {
      item_of(name, 'library', {
        description = 'livré v2'
      })
    })
    local plan = apply.preview_update(p2)
    R.eq(#plan.conflict, 1, 'conflit détecté')
    R.eq(plan.conflict[1][1].key, "plugin:" .. tostring(name))
    local report = apply.apply_update(p2, {
      ["plugin:" .. tostring(name)] = 'local'
    }, { })
    R.ok(report.ok, report.error)
    return R.eq((scopes.find_row(name, nil))[3], 'modifié localement', 'le local est conservé')
  end)
  R.it("conflit : remplacer par la version livrée", function()
    local name = "wscope_replace_" .. tostring(SUFFIX)
    local p1 = package_of(APP_A, {
      item_of(name, 'library')
    })
    R.ok((apply.apply_update(p1, { }, { })).ok)
    wpr.Mutation.updateWidgetPlugin({ }, {
      id = (scopes.find_row(name, nil))[1],
      input = {
        description = 'modifié localement'
      }
    }, CTX)
    local p2 = package_of(APP_A, {
      item_of(name, 'library', {
        description = 'livré v2'
      })
    })
    local report = apply.apply_update(p2, {
      ["plugin:" .. tostring(name)] = 'delivered'
    }, { })
    R.ok(report.ok, report.error)
    return R.eq((scopes.find_row(name, nil))[3], 'livré v2', 'la version livrée remplace la locale')
  end)
  R.it("conflit : importer sous un autre nom (défaut), pages réécrites", function()
    local name = "wscope_rename_" .. tostring(SUFFIX)
    local page_name = "wscope_rename_page_" .. tostring(SUFFIX)
    plugin(name, nil)
    create_page(page_name, name)
    local built = pkg.build_package({
      id = APP_A,
      name = 'Scope rename',
      version = '1.0.0',
      description = ''
    }, { })
    local items
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = built.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.key:find(SUFFIX, 1, true) then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      items = _accum_0
    end
    local has_page
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #items do
        local it = items[_index_0]
        if it.key == "page:" .. tostring(page_name) then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      has_page = _accum_0
    end
    R.eq(#has_page, 1, 'la page livrée est dans le paquet')
    local p1 = {
      app = built.app,
      items = items,
      seed_keys = { }
    }
    R.ok((apply.apply_update(p1, { }, { })).ok)
    wpr.Mutation.updateWidgetPlugin({ }, {
      id = (scopes.find_row(name, nil))[1],
      input = {
        description = 'modifié localement'
      }
    }, CTX)
    local items2 = { }
    for _index_0 = 1, #items do
      local it = items[_index_0]
      if it.key == "plugin:" .. tostring(name) then
        local content = { }
        for k, v in pairs(it.content) do
          content[k] = v
        end
        content.description = 'livré v2'
        table.insert(items2, {
          type = it.type,
          key = it.key,
          content = content,
          origin = it.origin
        })
      else
        table.insert(items2, it)
      end
    end
    local p2 = {
      app = built.app,
      items = items2,
      seed_keys = { }
    }
    local app_r = require('resolvers.app_resolvers')
    local shaped = app_r.Query.previewAppUpdate(nil, {
      yaml = yaml.encode(p2)
    }, CTX)
    local conflict = ((function()
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = shaped.conflict
      for _index_0 = 1, #_list_0 do
        local c = _list_0[_index_0]
        if c.key == "plugin:" .. tostring(name) then
          _accum_0[_len_0] = c
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)())[1]
    R.ok(conflict, 'conflit sur la définition')
    local listed = false
    local _list_0 = (conflict.pages or { })
    for _index_0 = 1, #_list_0 do
      local listed_page = _list_0[_index_0]
      if listed_page == page_name then
        listed = true
      end
    end
    R.ok(listed, 'la page touchée est listée')
    local report = apply.apply_update(p2, { }, { })
    R.ok(report.ok, report.error)
    R.ok((scopes.find_row(name, nil))[1], 'la définition locale est conservée')
    local imported = scopes.find_row(tostring(name) .. "_imported", nil)
    R.ok(imported, 'la définition livrée est importée sous un autre nom')
    R.eq(imported[3], 'livré v2', 'la copie porte le contenu livré')
    R.eq((scopes.find_row(name, nil))[3], 'modifié localement', 'le local n’est pas écrasé')
    local stored_page = box.space._tdb_custom_views.index.by_name:get(page_name)
    R.ok(stored_page, 'la page livrée existe')
    R.matches(stored_page[4], "type: " .. tostring(name) .. "_imported")
    return R.is_nil(stored_page[4]:find("type: " .. tostring(name) .. "\n", 1, true), 'plus aucune référence à l’ancien nom')
  end)
  R.it("conflit sur une définition locale non suivie (installation neuve) : remplacer", function()
    local name = "wscope_fresh_" .. tostring(SUFFIX)
    plugin(name, nil)
    wpr.Mutation.updateWidgetPlugin({ }, {
      id = (scopes.find_row(name, nil))[1],
      input = {
        description = 'local seul'
      }
    }, CTX)
    local p = package_of(APP_A, {
      item_of(name, 'library', {
        description = 'livré neuf'
      })
    })
    local plan = apply.preview_update(p)
    R.eq(#plan.conflict, 1, 'une définition locale non suivie entre en conflit')
    local report = apply.apply_update(p, {
      ["plugin:" .. tostring(name)] = 'delivered'
    }, { })
    R.ok(report.ok, report.error)
    return R.eq((scopes.find_row(name, nil))[3], 'livré neuf', 'la définition locale est remplacée')
  end)
  return R.it("conflit : importer sous un nom choisi par la décision newName", function()
    local name = "wscope_named_" .. tostring(SUFFIX)
    local p1 = package_of(APP_A, {
      item_of(name, 'library')
    })
    R.ok((apply.apply_update(p1, { }, { })).ok)
    wpr.Mutation.updateWidgetPlugin({ }, {
      id = (scopes.find_row(name, nil))[1],
      input = {
        description = 'modifié localement'
      }
    }, CTX)
    local p2 = package_of(APP_A, {
      item_of(name, 'library', {
        description = 'livré v2'
      })
    })
    local report = apply.apply_update(p2, {
      ["plugin:" .. tostring(name)] = 'rename'
    }, {
      rename_names = {
        ["plugin:" .. tostring(name)] = "wscope_named_copy_" .. tostring(SUFFIX)
      }
    })
    R.ok(report.ok, report.error)
    R.ok(scopes.find_row("wscope_named_copy_" .. tostring(SUFFIX), nil))
    return R.is_nil(scopes.find_row(tostring(name) .. "_imported", nil))
  end)
end)
R.describe("WidgetScopes — suppression d’une définition utilisée", function()
  R.it("refuse la suppression d’une définition globale utilisée, en listant les pages", function()
    local name = "wscope_used_" .. tostring(SUFFIX)
    local p = plugin(name, nil)
    local page = create_page("wscope_used_page_" .. tostring(SUFFIX), name)
    local ok, err = pcall(function()
      return wpr.Mutation.deleteWidgetPlugin({ }, {
        id = p.id
      }, CTX)
    end)
    R.nok(ok, 'suppression refusée')
    R.matches((tostring(err)), 'is used by page')
    R.matches((tostring(err)), "wscope_used_page_" .. tostring(SUFFIX))
    R.ok(box.space._tdb_widget_plugins:get(p.id), 'la définition est toujours là')
    return delete_page(page)
  end)
  R.it("accepte la suppression quand plus aucune page ne l’utilise", function()
    local name = "wscope_free_" .. tostring(SUFFIX)
    local p = plugin(name, nil)
    R.ok(wpr.Mutation.deleteWidgetPlugin({ }, {
      id = p.id
    }, CTX))
    return R.is_nil(scopes.find_row(name, nil))
  end)
  return R.it("accepte la suppression d’une définition d’app même utilisée", function()
    local name = "wscope_appdel_" .. tostring(SUFFIX)
    local p = plugin(name, APP_A)
    local page = create_page("wscope_appdel_page_" .. tostring(SUFFIX), name)
    track_page(APP_A, page.id, "wscope_appdel_page_" .. tostring(SUFFIX))
    R.eq(scopes.resolve_for_page(name, page.id)[1], p.id)
    R.ok(wpr.Mutation.deleteWidgetPlugin({ }, {
      id = p.id
    }, CTX))
    R.is_nil(scopes.find_row(name, APP_A))
    return delete_page(page)
  end)
end)
R.describe("WidgetScopes — migration d’un tuple d’ancien format", function()
  return R.it("un tuple de 10 champs devient une définition de bibliothèque", function()
    local old_id = "wscope_old_" .. tostring(SUFFIX)
    local old_name = "wscope_old_name_" .. tostring(SUFFIX)
    local now = os.time()
    box.space._tdb_widget_plugins:insert({
      old_id,
      old_name,
      '',
      'coffeescript',
      'pug',
      'x',
      'y',
      now,
      now,
      ''
    })
    R.is_nil(scopes.find_row(old_name, nil))
    local n = spaces.migrate_widget_plugin_app_id()
    R.ok(n >= 1, "au moins un tuple normalisé (obtenu " .. tostring(n) .. ")")
    local row = scopes.find_row(old_name, nil)
    R.ok(row, 'la définition est désormais globale')
    R.eq(#row, 11)
    R.eq(row[11], '')
    R.eq(spaces.migrate_widget_plugin_app_id(), 0, 'idempotente')
    return box.space._tdb_widget_plugins:delete(old_id)
  end)
end)
return R.describe("WidgetScopes — cleanup", function()
  return R.it("supprime les pages, définitions et apps de la fixture", function()
    for _, p in pairs(FIX.pages) do
      delete_page(p)
    end
    local rename_page = box.space._tdb_custom_views.index.by_name:get("wscope_rename_page_" .. tostring(SUFFIX))
    if rename_page then
      box.space._tdb_custom_views:delete(rename_page[1])
    end
    local _list_0 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      if row[2]:find(SUFFIX, 1, true) then
        box.space._tdb_widget_plugins:delete(row[1])
      end
    end
    local _list_1 = box.space._tdb_custom_views:select({ })
    for _index_0 = 1, #_list_1 do
      local page = _list_1[_index_0]
      if page[2]:find(SUFFIX, 1, true) then
        box.space._tdb_custom_views:delete(page[1])
      end
    end
    clean_app(APP_A)
    clean_app(APP_B)
    clean_app(APP_C)
    R.is_nil(scopes.find_row("wscope_" .. tostring(SUFFIX), nil))
    return R.is_nil(scopes.find_row("wscope_" .. tostring(SUFFIX), APP_A))
  end)
end)
