local R = require('tests.runner')
local wpr = require('resolvers.widget_plugin_resolvers')
local pkg = require('core.app_package')
local apply = require('core.app_apply')
local auth = require('core.auth')
local json = require('json')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local NAME = "wpman_plugin_" .. tostring(SUFFIX)
local APP_ID = "org.test.wpman_" .. tostring(SUFFIX)
local MANIFEST = [[access: read
columns:
  - {name: titre, type: String}
  - {name: debut, type: Date}
  - {name: fin, type: Date, optional: true}
options:
  - {name: couleur, type: color, default: '#36c'}
]]
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local plugin_id = nil
R.describe("WidgetPlugins — validation du manifest", function()
  R.it("accepte un manifest valide et le rend tel quel", function()
    return R.eq(wpr.validate_manifest(MANIFEST), MANIFEST)
  end)
  R.it("traite absent, vide ou commentaires seuls comme « pas de manifest »", function()
    R.eq(wpr.validate_manifest(nil), '')
    R.eq(wpr.validate_manifest('  \n\t'), '')
    return R.eq(wpr.validate_manifest('# seulement un commentaire\n'), '')
  end)
  R.it("refuse un YAML invalide", function()
    return R.raises((function()
      return wpr.validate_manifest('access: [oops')
    end), 'invalid YAML')
  end)
  R.it("refuse une valeur access inconnue", function()
    return R.raises((function()
      return wpr.validate_manifest('access: write')
    end), 'access must be one of none, read, full')
  end)
  R.it("accepte les trois valeurs access", function()
    local _list_0 = {
      'none',
      'read',
      'full'
    }
    for _index_0 = 1, #_list_0 do
      local access = _list_0[_index_0]
      R.eq(wpr.validate_manifest("access: " .. tostring(access) .. "\n"), "access: " .. tostring(access) .. "\n")
    end
  end)
  R.it("refuse un manifest qui n’est pas un mapping", function()
    return R.raises((function()
      return wpr.validate_manifest('- a\n- b\n')
    end), 'must be a YAML mapping')
  end)
  R.it("refuse columns sous forme de mapping", function()
    return R.raises((function()
      return wpr.validate_manifest('columns: {titre: nom}\n')
    end), 'columns must be a list')
  end)
  R.it("refuse une colonne sans nom, sans type ou avec un nom invalide", function()
    R.raises((function()
      return wpr.validate_manifest('columns:\n  - {type: String}\n')
    end), 'name is required')
    R.raises((function()
      return wpr.validate_manifest('columns:\n  - {name: titre}\n')
    end), 'type is required')
    return R.raises((function()
      return wpr.validate_manifest('columns:\n  - {name: 1titre, type: String}\n')
    end), 'must match')
  end)
  R.it("refuse une colonne en double et un optional non booléen", function()
    R.raises((function()
      return wpr.validate_manifest('columns:\n  - {name: a, type: String}\n  - {name: a, type: String}\n')
    end), 'duplicate column name')
    return R.raises((function()
      return wpr.validate_manifest('columns:\n  - {name: a, type: String, optional: 1}\n')
    end), 'optional must be a boolean')
  end)
  return R.it("valide les options (nom, type, défaut scalaire)", function()
    R.eq(wpr.validate_manifest("options:\n  - {name: couleur, type: color, default: '#36c'}\n"), "options:\n  - {name: couleur, type: color, default: '#36c'}\n")
    R.raises((function()
      return wpr.validate_manifest('options:\n  - {type: color}\n')
    end), 'name is required')
    R.raises((function()
      return wpr.validate_manifest('options:\n  - {name: c}\n')
    end), 'type is required')
    return R.raises((function()
      return wpr.validate_manifest('options:\n  - {name: c, type: color, default: [1, 2]}\n')
    end), 'default must be a scalar')
  end)
end)
R.describe("WidgetPlugins — stockage du manifest", function()
  R.it("createWidgetPlugin enregistre et renvoie le manifest", function()
    local res = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = NAME,
        description = 'manifest test',
        scriptLanguage = 'javascript',
        templateLanguage = 'html',
        scriptCode = 'module.exports = function () {}',
        templateCode = '<div></div>',
        manifest = MANIFEST
      }
    }, CTX)
    R.ok(res)
    plugin_id = res.id
    R.eq(res.manifest, MANIFEST)
    return R.eq(box.space._tdb_widget_plugins:get(plugin_id)[10], MANIFEST)
  end)
  R.it("createWidgetPlugin refuse un manifest invalide", function()
    R.raises((function()
      return wpr.Mutation.createWidgetPlugin({ }, {
        input = {
          name = tostring(NAME) .. "_bad",
          scriptCode = 'x',
          templateCode = 'y',
          manifest = 'access: write'
        }
      }, CTX)
    end), 'access must be one of')
    return R.is_nil(box.space._tdb_widget_plugins.index.by_name:get(tostring(NAME) .. "_bad"))
  end)
  R.it("updateWidgetPlugin partiel conserve le manifest existant", function()
    local res = wpr.Mutation.updateWidgetPlugin({ }, {
      id = plugin_id,
      input = {
        description = 'changed'
      }
    }, CTX)
    R.eq(res.description, 'changed')
    return R.eq(res.manifest, MANIFEST)
  end)
  R.it("updateWidgetPlugin remplace le manifest", function()
    local res = wpr.Mutation.updateWidgetPlugin({ }, {
      id = plugin_id,
      input = {
        manifest = "access: full\n"
      }
    }, CTX)
    return R.eq(res.manifest, "access: full\n")
  end)
  R.it("updateWidgetPlugin refuse un manifest invalide sans toucher l’existant", function()
    R.raises((function()
      return wpr.Mutation.updateWidgetPlugin({ }, {
        id = plugin_id,
        input = {
          manifest = 'columns:\n  - {name: a}\n'
        }
      }, CTX)
    end), 'type is required')
    return R.eq(wpr.Query.widgetPlugin({ }, {
      id = plugin_id
    }, CTX).manifest, "access: full\n")
  end)
  return R.it("remet le manifest complet pour la suite", function()
    local res = wpr.Mutation.updateWidgetPlugin({ }, {
      id = plugin_id,
      input = {
        manifest = MANIFEST
      }
    }, CTX)
    return R.eq(res.manifest, MANIFEST)
  end)
end)
R.describe("WidgetPlugins — migration d’un tuple d’ancien format", function()
  R.it("un tuple sans champ manifest se lit avec manifest vide", function()
    local old_id = "wpman_old_" .. tostring(SUFFIX)
    local now = os.time()
    box.space._tdb_widget_plugins:insert({
      old_id,
      "wpman_old_name_" .. tostring(SUFFIX),
      '',
      'coffeescript',
      'pug',
      'x',
      'y',
      now,
      now
    })
    local p = wpr.Query.widgetPlugin({ }, {
      id = old_id
    }, CTX)
    R.ok(p)
    return R.eq(p.manifest, '')
  end)
  return R.it("migrate_widget_plugin_manifest complète les tuples courts", function()
    local spaces = require('core.spaces')
    local n = spaces.migrate_widget_plugin_manifest()
    R.ok(n >= 1, "au moins un tuple normalisé (obtenu " .. tostring(n) .. ")")
    local old = box.space._tdb_widget_plugins.index.by_name:get("wpman_old_name_" .. tostring(SUFFIX))
    R.eq(#old, 10, 'le tuple a maintenant 10 champs')
    R.eq(old[10], '')
    R.eq(spaces.migrate_widget_plugin_manifest(), 0, 'idempotente')
    return box.space._tdb_widget_plugins:delete(old[1])
  end)
end)
R.describe("WidgetPlugins — mappage de colonnes dans le YAML de page", function()
  R.it("addWidgetToView écrit un mapping columns déclaré → champ", function()
    local cvr = require('resolvers.custom_view_resolvers')
    local spaces = require('core.spaces')
    local cvw = require('resolvers.custom_view_widgets')
    local sp = spaces.create_user_space("wpman_map_" .. tostring(SUFFIX), '')
    local page = cvr.Mutation.createCustomView({ }, {
      name = "wpman_page_" .. tostring(SUFFIX),
      description = '',
      yaml = 'layout:\n  direction: vertical\n  children: []'
    }, CTX)
    local res = cvr.Mutation.addWidgetToView({ }, {
      viewId = page.id,
      widget = {
        title = 'Calendrier',
        type = NAME,
        spaceId = sp.id,
        fields = { },
        columns = {
          titre = 'nom',
          debut = 'date_debut'
        },
        params = {
          couleur = '#c33'
        }
      }
    }, CTX)
    R.ok(res)
    R.matches(res.yaml, 'columns:')
    R.matches(res.yaml, 'titre: nom')
    R.matches(res.yaml, 'debut: date_debut')
    local config = yaml.decode(res.yaml)
    local widget = config.layout.children[1].widget
    R.eq(widget.type, NAME)
    R.eq(widget.columns.titre, 'nom')
    R.eq(widget.columns.debut, 'date_debut')
    R.eq(widget.params.couleur, '#c33')
    local reordered = cvw.reorder_widgets(page.id, {
      {
        widgetId = widget.id,
        index = 1
      }
    })
    local again = yaml.decode(reordered.yaml).layout.children[1].widget
    R.eq(again.columns.titre, 'nom')
    R.eq(again.columns.debut, 'date_debut')
    cvr.Mutation.deleteCustomView({ }, {
      id = page.id
    }, CTX)
    return spaces.delete_user_space(sp.name)
  end)
  return R.it("un widget tableau garde une liste columns", function()
    local cvr = require('resolvers.custom_view_resolvers')
    local spaces = require('core.spaces')
    local sp = spaces.create_user_space("wpman_list_" .. tostring(SUFFIX), '')
    local page = cvr.Mutation.createCustomView({ }, {
      name = "wpman_list_page_" .. tostring(SUFFIX),
      description = '',
      yaml = 'layout:\n  direction: vertical\n  children: []'
    }, CTX)
    local res = cvr.Mutation.addWidgetToView({ }, {
      viewId = page.id,
      widget = {
        title = 'Tableau',
        type = 'table',
        spaceId = sp.id,
        fields = {
          'nom',
          'age'
        }
      }
    }, CTX)
    local widget = yaml.decode(res.yaml).layout.children[1].widget
    R.eq(#widget.columns, 2)
    R.eq(widget.columns[1], 'nom')
    R.eq(widget.columns[2], 'age')
    cvr.Mutation.deleteCustomView({ }, {
      id = page.id
    }, CTX)
    return spaces.delete_user_space(sp.name)
  end)
end)
return R.describe("WidgetPlugins — export et installation d’app", function()
  R.it("l’export inclut le manifest", function()
    local row = box.space._tdb_widget_plugins:get(plugin_id)
    local content = pkg.plugin_content(row)
    R.eq(content.manifest, MANIFEST)
    return R.eq(content.name, NAME)
  end)
  R.it("l’empreinte change avec le manifest", function()
    local base = {
      name = NAME,
      description = '',
      scriptLanguage = 'javascript',
      templateLanguage = 'html',
      scriptCode = 'c',
      templateCode = 't'
    }
    local with_manifest = pkg.normalize_content('plugin', {
      name = NAME,
      description = '',
      scriptLanguage = 'javascript',
      templateLanguage = 'html',
      scriptCode = 'c',
      templateCode = 't',
      manifest = "access: read\n"
    })
    local without_manifest = pkg.normalize_content('plugin', base)
    R.eq(with_manifest.manifest, "access: read\n")
    R.eq(without_manifest.manifest, '')
    return R.ne(pkg.fingerprint(with_manifest), pkg.fingerprint(without_manifest))
  end)
  R.it("un aller-retour YAML conserve le manifest à l’identique", function()
    local row = box.space._tdb_widget_plugins:get(plugin_id)
    local content = pkg.plugin_content(row)
    local decoded = yaml.decode(yaml.encode({
      content = content
    }))
    local norm = pkg.normalize_content('plugin', pkg.strip_null(decoded.content))
    R.eq(norm.manifest, MANIFEST)
    return R.eq(pkg.canonical(norm), pkg.canonical(content))
  end)
  R.it("l’installation recrée le manifest", function()
    local built = pkg.build_package({
      id = APP_ID,
      name = "wpman " .. tostring(SUFFIX),
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
        if it.key == "plugin:" .. tostring(NAME) then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      items = _accum_0
    end
    R.eq(#items, 1, 'un élément plugin dans le paquet')
    R.eq(items[1].content.manifest, MANIFEST)
    box.space._tdb_widget_plugins:delete(plugin_id)
    R.is_nil(pkg.describe_local('plugin', "plugin:" .. tostring(NAME)))
    local p = {
      app = built.app,
      items = items,
      seed_keys = { }
    }
    local plan = apply.preview_update(p)
    R.eq(#plan.errors, 0, 'preview errors')
    R.eq(#plan.create, 1, 'plugin à créer')
    local report = apply.apply_update(p, { }, { })
    R.ok(report.ok, report.error)
    local installed = pkg.describe_local('plugin', "plugin:" .. tostring(NAME))
    R.ok(installed)
    R.eq(installed.manifest, MANIFEST)
    plugin_id = wpr.Query.widgetPlugin({ }, {
      name = NAME
    }, CTX).id
  end)
  return R.it("nettoie le plugin et le suivi d’app", function()
    if plugin_id then
      box.space._tdb_widget_plugins:delete(plugin_id)
    end
    box.space._tdb_app_items:delete({
      APP_ID,
      "plugin:" .. tostring(NAME)
    })
    box.space._tdb_apps:delete(APP_ID)
    return R.is_nil(pkg.describe_local('plugin', "plugin:" .. tostring(NAME)))
  end)
end)
