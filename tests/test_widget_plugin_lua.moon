-- tests/test_widget_plugin_lua.moon
-- Définitions Lua / MoonScript des widgets personnalisés (spec
-- docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7) :
-- compilation côté serveur dans le champ `compiled`, refus d'enregistrer un
-- MoonScript invalide (message avec la ligne), Lua stocké tel quel (sa syntaxe
-- n'est vérifiée qu'à l'exécution, par wasmoon en Lua 5.4), migration tdb_v7.

R = require 'tests.runner'
wpr = require 'resolvers.widget_plugin_resolvers'
spaces = require 'core.spaces'
auth = require 'core.auth'

SUFFIX = tostring math.random 100000, 999999
BASE = "wplua_#{SUFFIX}"

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

-- Un exemple réaliste : rendu des lignes reçues par onRecords.
MOON_SCRIPT = [[
widget.render "<h3>" .. (widget.params.titre or 'Widget') .. "</h3>"
widget.onRecords (rows) ->
  items = for row in *rows
    "<li>" .. tostring(row.nom) .. "</li>"
  widget.render "<ul>" .. table.concat(items) .. "</ul>"
]]

TEMPLATE = 'div.plugin-root'

-- Syntaxes valides en Lua 5.4 (wasmoon) mais pas en LuaJIT 5.1 (loadstring) :
-- le serveur ne doit plus les refuser (spec widgets personnalisés §7).
LUA54_SNIPPETS = {
  'x = 7 // 2'
  'y = 5 & 3'
  'z = 1 << 4'
  'local c <const> = 1'
  'x = ~0'
}

created = {}

R.describe "WidgetPlugins — langages Lua / MoonScript", ->

  R.it "lua et moonscript sont acceptés par createWidgetPlugin", ->
    for lang in *{'lua', 'moonscript'}
      code = if lang == 'lua' then 'widget.render("ok")' else MOON_SCRIPT
      p = wpr.Mutation.createWidgetPlugin {}, {
        input: {
          name: "#{BASE}_#{lang}"
          description: "widget #{lang}"
          scriptLanguage: lang
          templateLanguage: 'html'
          scriptCode: code
          templateCode: TEMPLATE
        }
      }, CTX
      R.eq p.scriptLanguage, lang
      created[lang] = p

  R.it "lua : le source est stocké tel quel dans compiled", ->
    p = created.lua
    R.ok p
    R.eq p.compiled, 'widget.render("ok")'

  R.it "lua : les syntaxes Lua 5.4 sont acceptées (vérification à l'exécution)", ->
    for i, code in ipairs LUA54_SNIPPETS
      name = "#{BASE}_lua54_#{i}"
      p = wpr.Mutation.createWidgetPlugin {}, {
        input: {
          name: name
          scriptLanguage: 'lua'
          templateLanguage: 'html'
          scriptCode: code
          templateCode: TEMPLATE
        }
      }, CTX
      R.eq p.compiled, code, "le source doit être gardé tel quel : #{code}"
      box.space._tdb_widget_plugins\delete p.id

  R.it "moonscript : compiled contient le Lua transpilé, exécutable", ->
    p = created.moonscript
    R.ok p
    R.ok p.compiled and p.compiled != '', 'compiled ne doit pas être vide'
    R.ok p.compiled\find('widget.render', 1, true) != nil,
      "le Lua compilé doit appeler widget.render, vu : #{p.compiled}"
    R.ok p.compiled\find('onRecords', 1, true) != nil,
      "le Lua compilé doit appeler onRecords, vu : #{p.compiled}"
    fn, err = loadstring p.compiled
    R.ok fn, "le Lua compilé doit être valide : #{err}"

  R.it "le source et l'empreinte d'export restent fondés sur le script", ->
    p = created.moonscript
    row = box.space._tdb_widget_plugins\get p.id
    R.eq row[6], MOON_SCRIPT, 'script_code garde le source MoonScript'
    R.eq row[12], p.compiled, 'compiled est la colonne 12'

  R.it "updateWidgetPlugin recompile, même sans changer le code", ->
    p = created.moonscript
    res = wpr.Mutation.updateWidgetPlugin {}, {
      id: p.id
      input: { scriptLanguage: 'moonscript' }
    }, CTX
    R.eq res.compiled, p.compiled

R.describe "WidgetPlugins — refus d’un MoonScript invalide", ->

  R.it "refuse un MoonScript invalide en nommant la ligne", ->
    ok, err = pcall ->
      wpr.Mutation.createWidgetPlugin {}, {
        input: {
          name: "#{BASE}_badmoon"
          scriptLanguage: 'moonscript'
          templateLanguage: 'html'
          scriptCode: "widget.render \"a\"\ny = =\n"
          templateCode: TEMPLATE
        }
      }, CTX
    R.eq ok, false, 'createWidgetPlugin devait refuser le script'
    msg = tostring err
    R.ok msg\find('MoonScript invalide', 1, true) != nil, "message attendu, vu : #{msg}"
    R.ok msg\find('ligne 2', 1, true) != nil, "la ligne doit être nommée, vu : #{msg}"

  R.it "updateWidgetPlugin refuse et laisse la définition intacte", ->
    p = created.lua
    ok, err = pcall ->
      wpr.Mutation.updateWidgetPlugin {}, {
        id: p.id
        input: { scriptLanguage: 'moonscript', scriptCode: "x = = 1\n" }
      }, CTX
    R.eq ok, false
    R.ok tostring(err)\find('MoonScript invalide', 1, true) != nil
    row = box.space._tdb_widget_plugins\get p.id
    R.eq row[4], 'lua', 'le langage enregistré ne change pas'
    R.eq row[6], 'widget.render("ok")', 'le script enregistré ne change pas'

R.describe "WidgetPlugins — Lua invalide enregistré tel quel", ->

  R.it "un Lua syntaxiquement faux est enregistré sans refus", ->
    code = "widget.render \"a\"\nif then\n"
    p = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: "#{BASE}_badlua"
        scriptLanguage: 'lua'
        templateLanguage: 'html'
        scriptCode: code
        templateCode: TEMPLATE
      }
    }, CTX
    R.eq p.scriptLanguage, 'lua'
    R.eq p.compiled, code, 'le source doit être gardé tel quel (erreur à l’exécution)'
    box.space._tdb_widget_plugins\delete p.id

R.describe "WidgetPlugins — migration tdb_v7 (compiled)", ->

  R.it "un tuple de 10 champs reçoit compiled vide", ->
    old_id = "wplua_old_#{SUFFIX}"
    now = os.time!
    box.space._tdb_widget_plugins\insert {
      old_id, "wplua_old_name_#{SUFFIX}", '', 'coffeescript', 'pug', 'x', 'y', now, now, ''
    }
    n = spaces.migrate_widget_plugin_compiled!
    R.ok n >= 1, "au moins un tuple normalisé (obtenu #{n})"
    old = box.space._tdb_widget_plugins\get old_id
    R.eq #old, 12, 'le tuple a maintenant 12 champs'
    R.eq old[12], '', 'aucun code compilé'
    R.eq spaces.migrate_widget_plugin_compiled!, 0, 'idempotente'
    box.space._tdb_widget_plugins\delete old_id

R.describe "WidgetPlugins — cleanup (Lua/MoonScript)", ->
  R.it "supprime les définitions de la fixture", ->
    for _, p in pairs created
      box.space._tdb_widget_plugins\delete p.id
    for row in *box.space._tdb_widget_plugins\select {}
      if row[2] == "#{BASE}_badmoon" or row[2] == "#{BASE}_badlua"
        box.space._tdb_widget_plugins\delete row[1]
    R.ok true
