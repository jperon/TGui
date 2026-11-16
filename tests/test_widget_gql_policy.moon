-- tests/test_widget_gql_policy.moon
-- Requêtes relayées depuis une iframe de widget (en-tête `X-TDB-Widget: 1`
-- posé par le parent, frontend/src/views/custom_view_plugins.coffee) :
-- lectures autorisées, mutations limitées aux enregistrements de données.
-- Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §6 :
-- « Jamais de mutation de schéma, d'utilisateurs ou d'apps depuis un widget,
-- quel que soit access. »
-- S'exécute dans l'instance de tests via `make test`.

R          = require 'tests.runner'
auth       = require 'core.auth'
spaces_mod = require 'core.spaces'
executor   = require 'graphql.executor'
http_server = require 'http_server'
json       = require 'json'

SUFFIX = tostring math.random 100000, 999999
SPACE_NAME = "wgq_#{SUFFIX}"
DATA_SPACE = "data_#{SPACE_NAME}"

-- ── Fixture : un espace avec un enregistrement ───────────────────────────────

sp = spaces_mod.create_user_space SPACE_NAME, 'widget gql policy'
spaces_mod.add_field sp.id, 'label', 'String'
box.space[DATA_SPACE]\insert { 'rec1', json.encode { label: 'initial' } }
box.space[DATA_SPACE]\insert { 'rec2', json.encode { label: 'deletable' } }
require('resolvers.init').reinit!

admin_user = auth.get_user_by_username 'admin'
R.ok admin_user, 'fixture: admin user must exist'
admin_sess = auth.create_session admin_user.id

ADMIN_CTX  = { user_id: admin_user.id, token: admin_sess.token }
WIDGET_CTX = { user_id: admin_user.id, token: admin_sess.token, widget: true }

EVIL_NAME = "wgq_evil_#{SUFFIX}"
PLAIN_NAME = "wgq_plain_#{SUFFIX}"

-- ── Helpers ──────────────────────────────────────────────────────────────────

run = (query, ctx, vars) ->
  executor.execute { query: query, variables: vars or {}, context: ctx }

err_msgs = (res) ->
  return '' unless res.errors
  msgs = [tostring(e.message) for e in *res.errors]
  table.concat msgs, ' | '

has_err = (res, pattern) ->
  return false unless res.errors
  for e in *res.errors
    return true if tostring(e.message)\find pattern
  false

stored_label = (id) ->
  t = box.space[DATA_SPACE]\get id
  return nil unless t
  json.decode(t[2]).label

create_user_q = (username) ->
  "mutation { createUser(input: {username: \"#{username}\", email: \"#{username}@test.local\", password: \"pass1234\"}) { id username } }"

update_q = (label) ->
  "mutation { updateRecord(spaceId: \"#{sp.id}\", id: \"rec1\", data: {label: \"#{label}\"}) { id } }"

-- Requête factice minimale pour handle_graphql (json déja décodé par le
-- serveur : on fournit `read_cached` et `render` à la place).
mk_gql_req = (headers, body) ->
  req = { headers: headers }
  req.read_cached = -> json.encode body
  req.render = (_, res) -> res
  req

auth_headers = (extra) ->
  h = { authorization: "Bearer #{admin_sess.token}" }
  for k, v in pairs extra or {}
    h[k] = v
  h

-- ── Lecture ──────────────────────────────────────────────────────────────────

R.describe "Widget relay — lectures autorisées", ->

  R.it "une query passe (les résolveurs gardent core.permissions.can)", ->
    res = run '{ spaces { id name } }', WIDGET_CTX
    R.nok res.errors, err_msgs res
    R.ok #res.data.spaces > 0, 'les espaces doivent être listés'

  R.it "une query typée d’espace passe", ->
    spaces_mod.add_field sp.id, 'note', 'String'
    require('resolvers.init').reinit!
    gql_name = require('graphql.dynamic').gql_name SPACE_NAME
    res = run "{ #{gql_name} { items { label } } }", WIDGET_CTX
    R.nok res.errors, err_msgs res
    R.eq #res.data[gql_name].items, 2

-- ── Mutations de données ─────────────────────────────────────────────────────

R.describe "Widget relay — mutations de données autorisées", ->

  R.it "updateRecord passe", ->
    res = run update_q('updated'), WIDGET_CTX
    R.nok res.errors, err_msgs res
    R.eq stored_label('rec1'), 'updated'

  R.it "insertRecord passe", ->
    res = run "mutation { insertRecord(spaceId: \"#{sp.id}\", data: {label: \"inserted\"}) { id } }", WIDGET_CTX
    R.nok res.errors, err_msgs res
    new_id = res.data.insertRecord.id
    R.eq stored_label(new_id), 'inserted'

  R.it "deleteRecords passe", ->
    res = run "mutation { deleteRecords(spaceId: \"#{sp.id}\", ids: [\"rec2\"]) }", WIDGET_CTX
    R.nok res.errors, err_msgs res
    R.is_nil box.space[DATA_SPACE]\get 'rec2'

-- ── Mutations interdites ─────────────────────────────────────────────────────

R.describe "Widget relay — mutations hors données refusées", ->

  R.it "createUser refusé, aucun utilisateur créé", ->
    res = run create_user_q(EVIL_NAME), WIDGET_CTX
    R.ok has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs res
    R.is_nil auth.get_user_by_username(EVIL_NAME), 'aucun utilisateur ne doit être créé'
    R.eq type(res.data), 'cdata', 'aucune donnée ne doit être retournée'

  R.it "grant refusé", ->
    res = run 'mutation { grant(groupId: "g1", input: {resourceType: "*", level: "admin"}) { id } }', WIDGET_CTX
    R.ok has_err(res, "Mutation 'grant' not allowed from a widget"), err_msgs res

  R.it "createSpace refusé", ->
    name = "wgq_new_#{SUFFIX}"
    res = run "mutation { createSpace(input: {name: \"#{name}\"}) { id } }", WIDGET_CTX
    R.ok has_err(res, "Mutation 'createSpace' not allowed from a widget"), err_msgs res
    R.is_nil box.space._tdb_spaces.index.by_name\get(name), 'aucun espace ne doit être créé'

  R.it "updateWidgetPlugin refusé", ->
    res = run 'mutation { updateWidgetPlugin(id: "p1", input: {scriptCode: "x"}) { id } }', WIDGET_CTX
    R.ok has_err(res, "Mutation 'updateWidgetPlugin' not allowed from a widget"), err_msgs res

  R.it "un alias ne masque pas le nom du champ (x: createUser)", ->
    q = "mutation { x: createUser(input: {username: \"alias_#{SUFFIX}\", email: \"alias_#{SUFFIX}@test.local\", password: \"pass1234\"}) { id } }"
    res = run q, WIDGET_CTX
    R.ok has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs res
    R.is_nil auth.get_user_by_username("alias_#{SUFFIX}"), 'aucun utilisateur ne doit être créé'

  R.it "un fragment racine est déplié puis refusé", ->
    q = "mutation { ...F } fragment F on Mutation { createUser(input: {username: \"frag_#{SUFFIX}\", email: \"frag_#{SUFFIX}@test.local\", password: \"pass1234\"}) { id } }"
    res = run q, WIDGET_CTX
    R.ok has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs res
    R.is_nil auth.get_user_by_username("frag_#{SUFFIX}"), 'aucun utilisateur ne doit être créé'

  R.it "un fragment racine autorisé est déplié et exécuté", ->
    q = "mutation { ...F } fragment F on Mutation { updateRecord(spaceId: \"#{sp.id}\", id: \"rec1\", data: {label: \"fragmented\"}) { id } }"
    res = run q, WIDGET_CTX
    R.nok res.errors, err_msgs res
    R.eq stored_label('rec1'), 'fragmented'

  R.it "mutation mixte (autorisée + interdite) refusée en bloc, sans effet", ->
    run update_q('before-mix'), WIDGET_CTX
    q = "mutation { updateRecord(spaceId: \"#{sp.id}\", id: \"rec1\", data: {label: \"mixed\"}) { id } createUser(input: {username: \"mix_#{SUFFIX}\", email: \"mix_#{SUFFIX}@test.local\", password: \"pass1234\"}) { id } }"
    res = run q, WIDGET_CTX
    R.ok has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs res
    R.eq stored_label('rec1'), 'before-mix', 'le champ autorisé ne doit pas être résolu'
    R.is_nil auth.get_user_by_username("mix_#{SUFFIX}"), 'aucun utilisateur ne doit être créé'

  R.it "subscription refusée", ->
    res = run 'subscription { __typename }', WIDGET_CTX
    R.ok has_err(res, 'Subscription operations are not allowed from a widget'), err_msgs res
    R.eq type(res.data), 'cdata', 'aucune donnée ne doit être retournée'

  R.it "l’opération nommée interdite est refusée, la nommée autorisée passe", ->
    q = "mutation Bad { createUser(input: {username: \"multi_#{SUFFIX}\", email: \"multi@test.local\", password: \"pass1234\"}) { id } } query Good { spaces { id } }"
    res = executor.execute { query: q, operationName: 'Bad', context: WIDGET_CTX }
    R.ok has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs res
    res = executor.execute { query: q, operationName: 'Good', context: WIDGET_CTX }
    R.nok res.errors, err_msgs res
    R.ok #res.data.spaces > 0

-- ── Sans le drapeau widget : comportement inchangé ───────────────────────────

R.describe "Sans contexte widget — comportement inchangé", ->

  R.it "createUser passe pour un admin", ->
    res = run create_user_q(PLAIN_NAME), ADMIN_CTX
    R.nok res.errors, err_msgs res
    R.eq res.data.createUser.username, PLAIN_NAME

  R.it "la même mutation serait refusée avec ctx.widget", ->
    res = run create_user_q(EVIL_NAME), WIDGET_CTX
    R.ok has_err(res, "Mutation 'createUser' not allowed from a widget"), err_msgs res

-- ── handle_graphql : en-tête HTTP → ctx.widget ───────────────────────────────

R.describe "handle_graphql — en-tête X-TDB-Widget", ->

  R.it "has_widget_header : reconnu quelle que soit la casse", ->
    R.ok http_server.has_widget_header({ headers: { ['x-tdb-widget']: '1' } })
    R.ok http_server.has_widget_header({ headers: { ['X-TDB-Widget']: '1' } })

  R.it "has_widget_header : absent, vide ou '0' -> false", ->
    R.nok http_server.has_widget_header({ headers: {} })
    R.nok http_server.has_widget_header({ headers: { ['x-tdb-widget']: '0' } })
    R.nok http_server.has_widget_header({ headers: { ['x-tdb-widget']: '' } })
    R.nok http_server.has_widget_header(nil)

  R.it "createUser relayé (en-tête) -> erreur, aucun utilisateur créé", ->
    req = mk_gql_req auth_headers({ ['x-tdb-widget']: '1' }), { query: create_user_q("hdr_#{SUFFIX}") }
    res = http_server.handle_graphql req
    R.ok has_err(res.json, "Mutation 'createUser' not allowed from a widget"), err_msgs(res.json)
    R.is_nil auth.get_user_by_username("hdr_#{SUFFIX}")

  R.it "query relayée (en-tête) -> données servies", ->
    req = mk_gql_req auth_headers({ ['x-tdb-widget']: '1' }), { query: '{ spaces { id name } }' }
    res = http_server.handle_graphql req
    R.nok res.json.errors, err_msgs(res.json)
    R.ok #res.json.data.spaces > 0

  R.it "sans en-tête : createUser aboutit (chemin admin normal)", ->
    req = mk_gql_req auth_headers(nil), { query: create_user_q("nohdr_#{SUFFIX}") }
    res = http_server.handle_graphql req
    R.nok res.json.errors, err_msgs(res.json)
    R.eq res.json.data.createUser.username, "nohdr_#{SUFFIX}"

-- ── Nettoyage ────────────────────────────────────────────────────────────────

for name in *{ "nohdr_#{SUFFIX}", PLAIN_NAME }
  u = auth.get_user_by_username name
  box.space._tdb_users\delete u.id if u and u.id
auth.delete_session admin_sess.token
spaces_mod.delete_user_space SPACE_NAME
require('resolvers.init').reinit!
