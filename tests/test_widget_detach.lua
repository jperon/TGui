local R = require('tests.runner')
local wpr = require('resolvers.widget_plugin_resolvers')
local scopes = require('core.widget_scopes')
local pkg = require('core.app_package')
local auth = require('core.auth')
local perms = require('core.permissions')
local cvr = require('resolvers.custom_view_resolvers')
local executor = require('graphql.executor')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local APP_ID = "org.test.detach_" .. tostring(SUFFIX)
local APP_NAME = "Detach app " .. tostring(SUFFIX)
local PAGE_1 = "wdetach_page_" .. tostring(SUFFIX)
local PAGE_2 = "wdetach_other_" .. tostring(SUFFIX)
local PAGE_3 = "wdetach_misc_" .. tostring(SUFFIX)
local SCRIPT = "module.exports = function (api) { api.render('<b>original</b>'); };"
local TEMPLATE = '<b>init</b>'
local MANIFEST = "access: read\ncolumns:\n  - {name: titre, type: String}\n"
local admin = auth.get_user_by_username('admin')
R.ok(admin, 'fixture: admin must exist')
local CTX = {
  user_id = admin.id
}
local FIX = {
  pages = { },
  plugins = { },
  actor = nil
}
local register_app
register_app = function(app_id, name)
  return box.space._tdb_apps:replace({
    app_id,
    name,
    '1.0.0',
    os.time(),
    'detach test'
  })
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
    description = opts.description or "detach " .. tostring(name),
    scriptLanguage = 'javascript',
    templateLanguage = 'html',
    scriptCode = opts.scriptCode or SCRIPT,
    templateCode = opts.templateCode or TEMPLATE,
    manifest = opts.manifest or MANIFEST
  }
  if app_id then
    input.appId = app_id
  end
  local created = wpr.Mutation.createWidgetPlugin({ }, {
    input = input
  }, CTX)
  FIX.plugins[created.name] = created
  return created
end
local create_page
create_page = function(name, page_yaml)
  local page = cvr.Mutation.createCustomView({ }, {
    name = name,
    description = 'detach test',
    yaml = page_yaml
  }, CTX)
  FIX.pages[name] = page
  return page
end
local delete_page
delete_page = function(page)
  if page and page.id then
    return box.space._tdb_custom_views:delete(page.id)
  end
end
local page_yaml_of
page_yaml_of = function(page_id)
  local t = box.space._tdb_custom_views:get(page_id)
  return t and t[4]
end
local decoded
decoded = function(page_id)
  return yaml.decode(page_yaml_of(page_id))
end
local widgets_by_id
widgets_by_id = function(page_id)
  local config = decoded(page_id)
  local out = { }
  local walk
  walk = function(node)
    if not (type(node) == 'table') then
      return 
    end
    if type(node.widget) == 'table' then
      local w = node.widget
      if w.id ~= nil then
        out[tostring(w.id)] = w
      end
      return 
    end
    for _, child in pairs(node) do
      if type(child) == 'table' then
        walk(child)
      end
    end
  end
  walk(config)
  return out
end
local instance_type
instance_type = function(page_id, widget_id)
  local w = widgets_by_id(page_id)[widget_id]
  return w and w.type
end
local two_instances_yaml
two_instances_yaml = function(plugin_name, title)
  return [[layout:
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
end
local other_page_yaml
other_page_yaml = function(plugin_name)
  return [[layout:
  direction: vertical
  children:
    - widget:
        id: w_0000000a
        title: Ailleurs
        space: personnes
        type: ']] .. plugin_name .. [['
]]
end
local misc_page_yaml
misc_page_yaml = function()
  return [[layout:
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
end
R.describe("WidgetDetach — fixture", function()
  return R.it("enregistre l'app, sa définition et trois pages", function()
    register_app(APP_ID, APP_NAME)
    FIX.plugin = plugin("wdetach_" .. tostring(SUFFIX), nil, {
      description = 'définition globale'
    })
    R.eq(FIX.plugin.appId, nil)
    R.eq(FIX.plugin.manifest, MANIFEST)
    FIX.pages.p1 = create_page(PAGE_1, two_instances_yaml(FIX.plugin.name, PAGE_1))
    track_page(APP_ID, FIX.pages.p1.id, PAGE_1)
    FIX.pages.p2 = create_page(PAGE_2, other_page_yaml(FIX.plugin.name))
    FIX.pages.p3 = create_page(PAGE_3, misc_page_yaml())
    R.eq(scopes.page_app_id(FIX.pages.p1.id), APP_ID, 'la page 1 appartient à l’app')
    return R.is_nil(scopes.page_app_id(FIX.pages.p2.id), 'la page 2 est locale')
  end)
end)
R.describe("WidgetDetach — copie de la définition", function()
  R.it("détache la seconde instance sous le nom par défaut", function()
    local expected = tostring(FIX.plugin.name) .. " (" .. tostring(PAGE_1) .. ")"
    FIX.copy = wpr.Mutation.detachWidgetPlugin({ }, {
      pageId = FIX.pages.p1.id,
      widgetId = 'w_00000002'
    }, CTX)
    R.ok(FIX.copy, 'la mutation renvoie la copie')
    FIX.plugins[FIX.copy.name] = FIX.copy
    R.eq(FIX.copy.name, expected, 'nom par défaut « <nom> (<page>) »')
    return R.ne(FIX.copy.id, FIX.plugin.id, 'nouvelle définition')
  end)
  R.it("copie script, gabarit, langages, manifest et description", function()
    R.eq(FIX.copy.description, FIX.plugin.description)
    R.eq(FIX.copy.scriptLanguage, FIX.plugin.scriptLanguage)
    R.eq(FIX.copy.templateLanguage, FIX.plugin.templateLanguage)
    R.eq(FIX.copy.scriptCode, FIX.plugin.scriptCode)
    R.eq(FIX.copy.templateCode, FIX.plugin.templateCode)
    return R.eq(FIX.copy.manifest, FIX.plugin.manifest)
  end)
  R.it("place la copie dans la portée de la page (app de la page)", function()
    R.eq(FIX.copy.appId, APP_ID)
    R.eq((scopes.find_row(FIX.copy.name, APP_ID))[1], FIX.copy.id)
    return R.is_nil(scopes.find_row(FIX.copy.name, nil), 'pas de copie globale')
  end)
  R.it("réécrit le type de cette seule instance et conserve params/columns", function()
    local w = widgets_by_id(FIX.pages.p1.id)
    R.eq(w['w_00000002'].type, FIX.copy.name)
    R.eq(w['w_00000002'].params.couleur, '#36c', 'params conservés')
    R.eq(w['w_00000002'].columns.titre, 'prenom', 'columns conservées')
    R.eq(w['w_00000002'].title, 'Second')
    R.eq(w['w_00000001'].type, FIX.plugin.name, 'l’autre instance garde l’original')
    R.eq(w['w_00000001'].params.couleur, '#c33')
    return R.eq(w['w_00000003'].type, nil, 'le widget de données est intact')
  end)
  R.it("ne touche ni l’autre page ni la définition d’origine", function()
    R.eq(instance_type(FIX.pages.p2.id, 'w_0000000a'), FIX.plugin.name)
    local stored = wpr.Query.widgetPlugin({ }, {
      id = FIX.plugin.id
    }, CTX)
    R.eq(stored.scriptCode, SCRIPT)
    return R.eq(stored.appId, nil)
  end)
  return R.it("préserve le reste du YAML (titres, ordre, params)", function()
    local text = page_yaml_of(FIX.pages.p1.id)
    R.matches(text, 'title: Premier')
    R.matches(text, 'title: Second')
    R.matches(text, 'title: Grille')
    R.matches(text, 'couleur: \'#c33\'')
    R.matches(text, 'couleur: \'#36c\'')
    local misc = page_yaml_of(FIX.pages.p3.id)
    R.matches(misc, "type: 'aggregate'")
    return R.matches(misc, "type: 'wdetach_unknown_" .. tostring(SUFFIX) .. "'")
  end)
end)
R.describe("WidgetDetach — nom de la copie", function()
  R.it("accepte un nouveau nom explicite", function()
    local copy = wpr.Mutation.detachWidgetPlugin({ }, {
      pageId = FIX.pages.p1.id,
      widgetId = 'w_00000001',
      newName = "ma_copie_" .. tostring(SUFFIX)
    }, CTX)
    FIX.plugins[copy.name] = copy
    R.eq(copy.name, "ma_copie_" .. tostring(SUFFIX))
    R.eq(instance_type(FIX.pages.p1.id, 'w_00000001'), copy.name)
    return R.eq(copy.appId, APP_ID)
  end)
  R.it("suffixe numériquement un nom déjà pris dans la portée", function()
    local page_name = "Collision " .. tostring(SUFFIX)
    local taken = tostring(FIX.plugin.name) .. " (" .. tostring(page_name) .. ")"
    plugin(taken, APP_ID)
    local page = create_page(page_name, two_instances_yaml(FIX.plugin.name, page_name))
    track_page(APP_ID, page.id, page_name)
    local copy = wpr.Mutation.detachWidgetPlugin({ }, {
      pageId = page.id,
      widgetId = 'w_00000002'
    }, CTX)
    FIX.plugins[copy.name] = copy
    R.eq(copy.name, tostring(taken) .. "_2")
    R.eq(copy.appId, APP_ID)
    return delete_page(page)
  end)
  R.it("refuse un nom invalide", function()
    local before = page_yaml_of(FIX.pages.p1.id)
    R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = FIX.pages.p1.id,
        widgetId = 'w_00000002',
        newName = 'bad:name'
      }, CTX)
    end), 'must match')
    return R.eq(page_yaml_of(FIX.pages.p1.id), before, 'la page ne change pas')
  end)
  return R.it("ne confond pas une clé `type` imbriquée avec celle du widget", function()
    local page = create_page("wdetach_nested_" .. tostring(SUFFIX), [[layout:
  direction: vertical
  children:
    - widget:
        id: w_0000000e
        type: ']] .. FIX.plugin.name .. [['
        params:
          type: 'nested'
          label: 'X'
]])
    local copy = wpr.Mutation.detachWidgetPlugin({ }, {
      pageId = page.id,
      widgetId = 'w_0000000e'
    }, CTX)
    FIX.plugins[copy.name] = copy
    local w = widgets_by_id(page.id)['w_0000000e']
    R.eq(w.type, copy.name, 'le type du widget est réécrit')
    R.eq(w.params.type, 'nested', 'le type imbriqué des params est intact')
    R.eq(w.params.label, 'X')
    return delete_page(page)
  end)
end)
R.describe("WidgetDetach — erreurs claires", function()
  R.it("page introuvable", function()
    return R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = "missing_" .. tostring(SUFFIX),
        widgetId = 'w_00000001'
      }, CTX)
    end), 'Custom view not found')
  end)
  R.it("instance introuvable dans la page", function()
    return R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = FIX.pages.p1.id,
        widgetId = 'w_ffffffff'
      }, CTX)
    end), 'Widget not found in page')
  end)
  R.it("instance sans type personnalisé (données, agrégat)", function()
    R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = FIX.pages.p3.id,
        widgetId = 'w_0000000b'
      }, CTX)
    end), 'not a custom widget')
    return R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = FIX.pages.p3.id,
        widgetId = 'w_0000000c'
      }, CTX)
    end), 'not a custom widget')
  end)
  return R.it("type personnalisé sans définition résolue", function()
    return R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = FIX.pages.p3.id,
        widgetId = 'w_0000000d'
      }, CTX)
    end), 'Widget definition not found')
  end)
end)
R.describe("WidgetDetach — permissions", function()
  R.it("refuse un utilisateur sans droit admin", function()
    local user = auth.create_user("wdetach_actor_" .. tostring(SUFFIX), "wdetach_actor_" .. tostring(SUFFIX) .. "@test.local", 'pass1234')
    local grp = perms.create_group("wdetach_grp_" .. tostring(SUFFIX), '')
    perms.grant(grp.id, '*', nil, 'write')
    perms.add_member(user.id, grp.id)
    FIX.actor = {
      user = user,
      group = grp
    }
    local before = page_yaml_of(FIX.pages.p1.id)
    R.raises((function()
      return wpr.Mutation.detachWidgetPlugin({ }, {
        pageId = FIX.pages.p1.id,
        widgetId = 'w_00000002'
      }, {
        user_id = user.id
      })
    end), 'Forbidden')
    return R.eq(page_yaml_of(FIX.pages.p1.id), before, 'la page ne change pas')
  end)
  R.it("refuse la mutation relayée par un widget (liste blanche d’executor)", function()
    require('resolvers.init').reinit()
    local res = executor.execute({
      query = 'mutation($p: ID!, $w: ID!) { detachWidgetPlugin(pageId: $p, widgetId: $w) { id name } }',
      variables = {
        p = FIX.pages.p1.id,
        w = 'w_00000002'
      },
      context = {
        user_id = admin.id,
        widget = true
      }
    })
    R.ok(res.errors, 'la mutation doit échouer')
    R.matches(tostring(res.errors[1].message), 'not allowed from a widget')
    return R.matches(tostring(res.errors[1].message), 'detachWidgetPlugin')
  end)
  return R.it("reste disponible par le chemin GraphQL pour un admin", function()
    local copy = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = "gql_copy_" .. tostring(SUFFIX),
        description = 'graphql',
        scriptLanguage = 'javascript',
        templateLanguage = 'html',
        scriptCode = SCRIPT,
        templateCode = TEMPLATE,
        manifest = ''
      }
    }, CTX)
    FIX.plugins[copy.name] = copy
    local page = create_page("wdetach_gql_" .. tostring(SUFFIX), other_page_yaml(copy.name))
    local res = executor.execute({
      query = 'mutation($p: ID!, $w: ID!) { detachWidgetPlugin(pageId: $p, widgetId: $w) { id name appId } }',
      variables = {
        p = page.id,
        w = 'w_0000000a'
      },
      context = {
        user_id = admin.id
      }
    })
    R.nok(res.errors, tostring(res.errors and res.errors[1].message))
    FIX.plugins[res.data.detachWidgetPlugin.name] = res.data.detachWidgetPlugin
    R.ok(res.data.detachWidgetPlugin.id)
    R.eq(instance_type(page.id, 'w_0000000a'), res.data.detachWidgetPlugin.name)
    return delete_page(page)
  end)
end)
return R.describe("WidgetDetach — cleanup", function()
  return R.it("supprime pages, définitions, app et acteur de la fixture", function()
    for _, page in pairs(FIX.pages) do
      delete_page(page)
    end
    local _list_0 = box.space._tdb_custom_views:select({ })
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      if row[2]:find(SUFFIX, 1, true) then
        box.space._tdb_custom_views:delete(row[1])
      end
    end
    local _list_1 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_1 do
      local row = _list_1[_index_0]
      if row[2]:find(SUFFIX, 1, true) then
        box.space._tdb_widget_plugins:delete(row[1])
      end
    end
    local _list_2 = box.space._tdb_app_items.index.by_app:select({
      APP_ID
    })
    for _index_0 = 1, #_list_2 do
      local t = _list_2[_index_0]
      box.space._tdb_app_items:delete({
        t[1],
        t[2]
      })
    end
    box.space._tdb_apps:delete(APP_ID)
    if FIX.actor then
      local _list_3 = box.space._tdb_sessions.index.by_user:select({
        FIX.actor.user.id
      })
      for _index_0 = 1, #_list_3 do
        local s = _list_3[_index_0]
        box.space._tdb_sessions:delete(s[1])
      end
      perms.delete_group(FIX.actor.group.id)
      box.space._tdb_users:delete(FIX.actor.user.id)
    end
    R.is_nil(scopes.find_row("wdetach_" .. tostring(SUFFIX), nil))
    return R.is_nil(box.space._tdb_custom_views.index.by_name:get(PAGE_1))
  end)
end)
