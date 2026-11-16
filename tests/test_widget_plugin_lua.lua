local R = require('tests.runner')
local wpr = require('resolvers.widget_plugin_resolvers')
local spaces = require('core.spaces')
local auth = require('core.auth')
local SUFFIX = tostring(math.random(100000, 999999))
local BASE = "wplua_" .. tostring(SUFFIX)
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local MOON_SCRIPT = [[widget.render "<h3>" .. (widget.params.titre or 'Widget') .. "</h3>"
widget.onRecords (rows) ->
  items = for row in *rows
    "<li>" .. tostring(row.nom) .. "</li>"
  widget.render "<ul>" .. table.concat(items) .. "</ul>"
]]
local TEMPLATE = 'div.plugin-root'
local LUA54_SNIPPETS = {
  'x = 7 // 2',
  'y = 5 & 3',
  'z = 1 << 4',
  'local c <const> = 1',
  'x = ~0'
}
local created = { }
R.describe("WidgetPlugins — langages Lua / MoonScript", function()
  R.it("lua et moonscript sont acceptés par createWidgetPlugin", function()
    local _list_0 = {
      'lua',
      'moonscript'
    }
    for _index_0 = 1, #_list_0 do
      local lang = _list_0[_index_0]
      local code
      if lang == 'lua' then
        code = 'widget.render("ok")'
      else
        code = MOON_SCRIPT
      end
      local p = wpr.Mutation.createWidgetPlugin({ }, {
        input = {
          name = tostring(BASE) .. "_" .. tostring(lang),
          description = "widget " .. tostring(lang),
          scriptLanguage = lang,
          templateLanguage = 'html',
          scriptCode = code,
          templateCode = TEMPLATE
        }
      }, CTX)
      R.eq(p.scriptLanguage, lang)
      created[lang] = p
    end
  end)
  R.it("lua : le source est stocké tel quel dans compiled", function()
    local p = created.lua
    R.ok(p)
    return R.eq(p.compiled, 'widget.render("ok")')
  end)
  R.it("lua : les syntaxes Lua 5.4 sont acceptées (vérification à l'exécution)", function()
    for i, code in ipairs(LUA54_SNIPPETS) do
      local name = tostring(BASE) .. "_lua54_" .. tostring(i)
      local p = wpr.Mutation.createWidgetPlugin({ }, {
        input = {
          name = name,
          scriptLanguage = 'lua',
          templateLanguage = 'html',
          scriptCode = code,
          templateCode = TEMPLATE
        }
      }, CTX)
      R.eq(p.compiled, code, "le source doit être gardé tel quel : " .. tostring(code))
      box.space._tdb_widget_plugins:delete(p.id)
    end
  end)
  R.it("moonscript : compiled contient le Lua transpilé, exécutable", function()
    local p = created.moonscript
    R.ok(p)
    R.ok(p.compiled and p.compiled ~= '', 'compiled ne doit pas être vide')
    R.ok(p.compiled:find('widget.render', 1, true) ~= nil, "le Lua compilé doit appeler widget.render, vu : " .. tostring(p.compiled))
    R.ok(p.compiled:find('onRecords', 1, true) ~= nil, "le Lua compilé doit appeler onRecords, vu : " .. tostring(p.compiled))
    local fn, err = loadstring(p.compiled)
    return R.ok(fn, "le Lua compilé doit être valide : " .. tostring(err))
  end)
  R.it("le source et l'empreinte d'export restent fondés sur le script", function()
    local p = created.moonscript
    local row = box.space._tdb_widget_plugins:get(p.id)
    R.eq(row[6], MOON_SCRIPT, 'script_code garde le source MoonScript')
    return R.eq(row[12], p.compiled, 'compiled est la colonne 12')
  end)
  return R.it("updateWidgetPlugin recompile, même sans changer le code", function()
    local p = created.moonscript
    local res = wpr.Mutation.updateWidgetPlugin({ }, {
      id = p.id,
      input = {
        scriptLanguage = 'moonscript'
      }
    }, CTX)
    return R.eq(res.compiled, p.compiled)
  end)
end)
R.describe("WidgetPlugins — refus d’un MoonScript invalide", function()
  R.it("refuse un MoonScript invalide en nommant la ligne", function()
    local ok, err = pcall(function()
      return wpr.Mutation.createWidgetPlugin({ }, {
        input = {
          name = tostring(BASE) .. "_badmoon",
          scriptLanguage = 'moonscript',
          templateLanguage = 'html',
          scriptCode = "widget.render \"a\"\ny = =\n",
          templateCode = TEMPLATE
        }
      }, CTX)
    end)
    R.eq(ok, false, 'createWidgetPlugin devait refuser le script')
    local msg = tostring(err)
    R.ok(msg:find('MoonScript invalide', 1, true) ~= nil, "message attendu, vu : " .. tostring(msg))
    return R.ok(msg:find('ligne 2', 1, true) ~= nil, "la ligne doit être nommée, vu : " .. tostring(msg))
  end)
  return R.it("updateWidgetPlugin refuse et laisse la définition intacte", function()
    local p = created.lua
    local ok, err = pcall(function()
      return wpr.Mutation.updateWidgetPlugin({ }, {
        id = p.id,
        input = {
          scriptLanguage = 'moonscript',
          scriptCode = "x = = 1\n"
        }
      }, CTX)
    end)
    R.eq(ok, false)
    R.ok(tostring(err):find('MoonScript invalide', 1, true) ~= nil)
    local row = box.space._tdb_widget_plugins:get(p.id)
    R.eq(row[4], 'lua', 'le langage enregistré ne change pas')
    return R.eq(row[6], 'widget.render("ok")', 'le script enregistré ne change pas')
  end)
end)
R.describe("WidgetPlugins — Lua invalide enregistré tel quel", function()
  return R.it("un Lua syntaxiquement faux est enregistré sans refus", function()
    local code = "widget.render \"a\"\nif then\n"
    local p = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = tostring(BASE) .. "_badlua",
        scriptLanguage = 'lua',
        templateLanguage = 'html',
        scriptCode = code,
        templateCode = TEMPLATE
      }
    }, CTX)
    R.eq(p.scriptLanguage, 'lua')
    R.eq(p.compiled, code, 'le source doit être gardé tel quel (erreur à l’exécution)')
    return box.space._tdb_widget_plugins:delete(p.id)
  end)
end)
R.describe("WidgetPlugins — migration tdb_v7 (compiled)", function()
  return R.it("un tuple de 10 champs reçoit compiled vide", function()
    local old_id = "wplua_old_" .. tostring(SUFFIX)
    local now = os.time()
    box.space._tdb_widget_plugins:insert({
      old_id,
      "wplua_old_name_" .. tostring(SUFFIX),
      '',
      'coffeescript',
      'pug',
      'x',
      'y',
      now,
      now,
      ''
    })
    local n = spaces.migrate_widget_plugin_compiled()
    R.ok(n >= 1, "au moins un tuple normalisé (obtenu " .. tostring(n) .. ")")
    local old = box.space._tdb_widget_plugins:get(old_id)
    R.eq(#old, 12, 'le tuple a maintenant 12 champs')
    R.eq(old[12], '', 'aucun code compilé')
    R.eq(spaces.migrate_widget_plugin_compiled(), 0, 'idempotente')
    return box.space._tdb_widget_plugins:delete(old_id)
  end)
end)
return R.describe("WidgetPlugins — cleanup (Lua/MoonScript)", function()
  return R.it("supprime les définitions de la fixture", function()
    for _, p in pairs(created) do
      box.space._tdb_widget_plugins:delete(p.id)
    end
    local _list_0 = box.space._tdb_widget_plugins:select({ })
    for _index_0 = 1, #_list_0 do
      local row = _list_0[_index_0]
      if row[2] == tostring(BASE) .. "_badmoon" or row[2] == tostring(BASE) .. "_badlua" then
        box.space._tdb_widget_plugins:delete(row[1])
      end
    end
    return R.ok(true)
  end)
end)
