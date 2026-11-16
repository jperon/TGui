-- tests/test_widget_plugin_permissions.moon
-- Écriture du code d'un widget plugin = exécution de code dans le navigateur
-- des autres utilisateurs : seuls les admins peuvent créer / modifier une
-- définition (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md
-- §6, « Jamais de mutation de schéma, d'utilisateurs ou d'apps depuis un
-- widget »). Avant ce test, un simple droit `write` global suffisait : un
-- utilisateur `write` écrivait un plugin qui, ouvert par un admin, relayait
-- `createUser` / `grant` avec la session de l'admin (élévation write → admin).
-- S'exécute dans l'instance de tests via `make test`.

R          = require 'tests.runner'
wpr        = require 'resolvers.widget_plugin_resolvers'
auth       = require 'core.auth'
perms_mod  = require 'core.permissions'
executor   = require 'graphql.executor'

SUFFIX = tostring math.random 100000, 999999

SCRIPT_CS = [[
module.exports = ({ render }) ->
  render '<div>Hello</div>'
]]

TEMPLATE_PUG = [[
div.widget
  h3 Hello Plugin
]]

-- ── Acteurs ──────────────────────────────────────────────────────────────────

admin_user = auth.get_user_by_username 'admin'
R.ok admin_user, 'fixture: admin user must exist'
ADMIN_CTX = { user_id: admin_user.id }

make_actor = (prefix, level) ->
  user = auth.create_user "#{prefix}_#{SUFFIX}", "#{prefix}_#{SUFFIX}@test.local", 'pass1234'
  grp = perms_mod.create_group "wpg_#{prefix}_#{SUFFIX}", ''
  perms_mod.grant grp.id, '*', nil, level if level
  perms_mod.add_member user.id, grp.id
  { user: user, group: grp, ctx: { user_id: user.id } }

-- Droit `write` global : le cas de la faille.
actor_write = make_actor 'wpwrite', 'write'
-- Droit `read` global seulement : refuse aussi.
actor_read = make_actor 'wpread', 'read'
-- Droit `admin` global sans être membre du groupe admin : autorisé (le contrôle
-- est un niveau de permission, pas un nom d'utilisateur).
actor_admin_perm = make_actor 'wpadminperm', 'admin'

-- ── Helpers ──────────────────────────────────────────────────────────────────

plugin_input = (name) ->
  {
    name: name
    description: 'permissions test'
    scriptLanguage: 'coffeescript'
    templateLanguage: 'pug'
    scriptCode: SCRIPT_CS
    templateCode: TEMPLATE_PUG
  }

plugin_exists = (name) ->
  p = box.space._tdb_widget_plugins.index.by_scope_name\get { '', name }
  p != nil

-- ── Tests ────────────────────────────────────────────────────────────────────

R.describe "WidgetPlugins — le code du plugin exige le niveau admin", ->

  R.it "utilisateur `write` global : createWidgetPlugin -> Forbidden", ->
    name = "denied_create_#{SUFFIX}"
    R.raises (->
      wpr.Mutation.createWidgetPlugin {}, { input: plugin_input name }, actor_write.ctx
    ), 'Forbidden'
    R.nok plugin_exists(name), 'aucune définition ne doit être créée'

  R.it "utilisateur `write` global : updateWidgetPlugin -> Forbidden", ->
    name = "denied_update_#{SUFFIX}"
    created = wpr.Mutation.createWidgetPlugin {}, { input: plugin_input name }, ADMIN_CTX
    R.raises (->
      wpr.Mutation.updateWidgetPlugin {}, {
        id: created.id
        input: { scriptCode: 'module.exports = -> null' }
      }, actor_write.ctx
    ), 'Forbidden'
    stored = box.space._tdb_widget_plugins\get created.id
    R.eq stored[6], SCRIPT_CS, 'le script stocké ne doit pas changer'
    wpr.Mutation.deleteWidgetPlugin {}, { id: created.id }, ADMIN_CTX

  R.it "utilisateur `read` global : createWidgetPlugin -> Forbidden", ->
    R.raises (->
      wpr.Mutation.createWidgetPlugin {}, { input: plugin_input "denied_read_#{SUFFIX}" }, actor_read.ctx
    ), 'Forbidden'

  R.it "admin (groupe admin) : createWidgetPlugin et updateWidgetPlugin -> OK", ->
    name = "admin_ok_#{SUFFIX}"
    res = wpr.Mutation.createWidgetPlugin {}, { input: plugin_input name }, ADMIN_CTX
    R.ok res.id, 'admin doit pouvoir créer'
    upd = wpr.Mutation.updateWidgetPlugin {}, {
      id: res.id
      input: { scriptCode: "module.exports = ({ render }) ->\n  render '<b>ok</b>'\n" }
    }, ADMIN_CTX
    R.eq upd.id, res.id
    R.matches upd.scriptCode, 'ok'
    wpr.Mutation.deleteWidgetPlugin {}, { id: res.id }, ADMIN_CTX

  R.it "permission `admin` globale sans groupe admin : autorisé", ->
    name = "admin_perm_#{SUFFIX}"
    res = wpr.Mutation.createWidgetPlugin {}, { input: plugin_input name }, actor_admin_perm.ctx
    R.ok res.id, 'le niveau admin suffit'
    wpr.Mutation.deleteWidgetPlugin {}, { id: res.id }, actor_admin_perm.ctx

  R.it "chemin GraphQL : mutation createWidgetPlugin refusée pour `write`", ->
    -- Vérifie le câblage complet (schéma + resolveur), pas seulement l'appel direct.
    require('resolvers.init').reinit!
    name = "denied_gql_#{SUFFIX}"
    vars = { input: plugin_input name }
    res = executor.execute {
      query: 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id } }'
      variables: vars
      context: actor_write.ctx
    }
    R.ok res.errors, 'la mutation doit échouer'
    R.matches tostring(res.errors[1].message), 'Forbidden'
    R.nok plugin_exists(name), 'aucune définition ne doit être créée'

-- ── Nettoyage ────────────────────────────────────────────────────────────────

for a in *{ actor_write, actor_read, actor_admin_perm }
  for s in *box.space._tdb_sessions.index.by_user\select { a.user.id }
    box.space._tdb_sessions\delete s[1]
  perms_mod.delete_group a.group.id
  box.space._tdb_users\delete a.user.id

require('resolvers.init').reinit!
