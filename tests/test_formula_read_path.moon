-- tests/test_formula_read_path.moon
-- T12 — chemin de lecture réel des colonnes calculées qui lisent d'autres
-- espaces avec space('X').
--
-- Deux chemins sont couverts, avec une formule « emprunteur » de type
-- Exemplaires.emprunteur (100 exemplaires, 72 personnes, 120 emprunts) :
--   1. la requête GraphQL dynamique par type (graphql.dynamic, colonne calculée) ;
--   2. data_resolvers.Query.records (reprFormula de champ, chemin grille).
--
-- Avant T12, le resolver dynamique reconstruisait son propre helper space()
-- et re-sélectionnait/décodait tout l'espace SOUS la garde à chaque appel
-- (défaut 1) ; et le chemin Query.records dépassait la garde à cause du coût,
-- sous le hook de comptage, des appels de fonction et des boucles
-- pairs/ipairs du proxy (défaut 2). Ce test est ROUGE avant, VERT après :
-- aucune valeur ne doit être nulle ni porter « instruction limit exceeded ».
--
-- Cas de non-régression : une formule calculée imbriquée dont la formule
-- interne boucle doit toujours lever « instruction limit exceeded » en un
-- temps borné, et un utilisateur sans droit de lecture sur l'espace lu par
-- space() doit obtenir une liste vide (aucune fuite).

R          = require 'tests.runner'
json       = require 'json'
auth       = require 'core.auth'
perms_mod  = require 'core.permissions'
spaces_mod = require 'core.spaces'
executor   = require 'graphql.executor'
dynamic    = require 'graphql.dynamic'
data_r     = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999
A_NAME = "frp2_a_#{SUFFIX}"
B_NAME = "frp2_b_#{SUFFIX}"
C_NAME = "frp2_c_#{SUFFIX}"
D_NAME = "frp2_d_#{SUFFIX}"

MAX_BOUNDED_SECONDS = 20

ins = (name, id, data) ->
  box.space["data_#{name}"]\insert { id, json.encode data }

expected_emprunteur = (id) ->
  p = ((id - 1) % 72) + 1
  "NomP#{p} PreP#{p}"

-- ── Fixture ──────────────────────────────────────────────────────────────────

-- A : 72 personnes (id, nom, prenom entiers/explicites)
a_sp = spaces_mod.create_user_space A_NAME, 'T12 — personnes lues par space()'
spaces_mod.add_field a_sp.id, 'id', 'Int'
spaces_mod.add_field a_sp.id, 'nom', 'String'
spaces_mod.add_field a_sp.id, 'prenom', 'String'
for i = 1, 72
  ins A_NAME, i, { id: i, nom: "NomP#{i}", prenom: "PreP#{i}" }

-- B : 120 emprunts référencant A par un champ entier ; 100 prêts ouverts
-- (un par exemplaire) et 20 rendus (exercent le filtre sur retour).
b_sp = spaces_mod.create_user_space B_NAME, 'T12 — emprunts'
spaces_mod.add_field b_sp.id, 'personne', 'Int'
spaces_mod.add_field b_sp.id, 'exemplaire', 'Int'
spaces_mod.add_field b_sp.id, 'retour', 'String'
for i = 1, 100
  ins B_NAME, i, { personne: ((i - 1) % 72) + 1, exemplaire: i }
for i = 101, 120
  ins B_NAME, i, { personne: 1, exemplaire: i - 100, retour: '2026-01-01' }

-- C : 100 exemplaires, colonne calculée emprunteur (formule du plan adaptée).
c_sp = spaces_mod.create_user_space C_NAME, 'T12 — exemplaires'
spaces_mod.add_field c_sp.id, 'id', 'Int'
spaces_mod.add_field c_sp.id, 'label', 'String'
EMP_FORMULA = "([p.nom .. ' ' .. (p.prenom or '') for p in *space('#{A_NAME}') when p.id == ([e.personne for e in *space('#{B_NAME}') when e.exemplaire == @id and (e.retour or '') == ''])[1]])[1]"
spaces_mod.add_field c_sp.id, 'emprunteur', 'String', false, '',
  EMP_FORMULA, nil, 'moonscript', 'self.emprunteur'
for i = 1, 100
  ins C_NAME, i, { id: i, label: "item#{i}" }

-- D : formule calculée imbriquée infinie (a lit b, b boucle).
d_sp = spaces_mod.create_user_space D_NAME, 'T12 — imbriquée'
spaces_mod.add_field d_sp.id, 'label', 'String'
spaces_mod.add_field d_sp.id, 'a', 'String', false, '', 'self.b', nil, 'lua', 'self.a'
spaces_mod.add_field d_sp.id, 'b', 'String', false, '',
  '(function() while true do end end)()', nil, 'lua'
ins D_NAME, 'd_1', { label: 'x' }

require('resolvers.init').reinit!

-- ── Acteurs ──────────────────────────────────────────────────────────────────

admin_user = auth.get_user_by_username 'admin'
admin_sess = auth.create_session admin_user.id
CTX = { user_id: admin_user.id, token: admin_sess.token }

user = auth.create_user "frp2u_#{SUFFIX}", "frp2u_#{SUFFIX}@test.local", 'pass1234'
sess = auth.create_session user.id
grp  = perms_mod.create_group "frp2g_#{SUFFIX}", ''
perms_mod.grant grp.id, 'space', c_sp.id, 'read'
perms_mod.add_member user.id, grp.id
USER_CTX = { user_id: user.id, token: sess.token }

decode_item = (item) ->
  if type(item.data) == 'string' then json.decode item.data else item.data

C_T = dynamic.gql_name C_NAME

-- ── Tests ────────────────────────────────────────────────────────────────────

R.describe "T12 — colonne calculée lisant d'autres espaces", ->
  R.it "chemin GraphQL dynamique : emprunteur correct pour les 100 exemplaires", ->
    res = executor.execute { query: "{ #{C_T} { items { id emprunteur } } }", context: CTX }
    R.nok res.errors, json.encode(res.errors)
    items = res.data[C_T].items
    R.eq #items, 100, 'items'
    bad = {}
    for item in *items
      id = tonumber item.id
      exp = expected_emprunteur id
      if item.emprunteur != exp
        table.insert bad, "id=#{id}: #{tostring item.emprunteur} != #{exp}"
    R.eq #bad, 0, "#{#bad}/100 valeurs fausses; premiere: #{bad[1]}"

  R.it "chemin Query.records : _repr_emprunteur correct pour les 100 exemplaires", ->
    res = data_r.Query.records nil, { spaceId: c_sp.id, limit: 500 }, CTX
    R.eq res.total, 100, 'total'
    bad = {}
    for item in *res.items
      d  = decode_item item
      id = tonumber d.id
      exp = expected_emprunteur id
      if d._repr_emprunteur != exp
        table.insert bad, "id=#{id}: #{tostring d._repr_emprunteur} != #{exp}"
    R.eq #bad, 0, "#{#bad}/100 valeurs fausses; premiere: #{bad[1]}"

  R.it "formule calculée imbriquée infinie : bornee, instruction limit exceeded", ->
    t0 = os.clock!
    res = data_r.Query.records nil, { spaceId: d_sp.id, limit: 10 }, CTX
    elapsed = os.clock! - t0
    print "    [measure] formule imbriquee infinie bornee en #{elapsed}s"
    d = decode_item res.items[1]
    R.matches tostring(d._repr_a), 'instruction limit exceeded', "valeur #{tostring d._repr_a}"
    R.ok elapsed < MAX_BOUNDED_SECONDS, "doit revenir en moins de #{MAX_BOUNDED_SECONDS}s (#{elapsed}s)"

  R.it "sans droit de lecture sur A, space('A') renvoie une liste vide (chemin dynamique)", ->
    res = executor.execute { query: "{ #{C_T} { items { id emprunteur } } }", context: USER_CTX }
    R.nok res.errors, json.encode(res.errors)
    encoded = json.encode res.data
    R.nok (encoded\find 'PreP', 1, true), "aucune donnee de A ne doit fuir"
    leaked = false
    for item in *res.data[C_T].items
      leaked = true if item.emprunteur != nil and item.emprunteur != ''
    R.nok leaked, "emprunteur doit etre vide sans droit de lecture sur A"

-- ── Nettoyage ────────────────────────────────────────────────────────────────

auth.delete_session sess.token
box.space._tdb_users\delete user.id
auth.delete_session admin_sess.token
perms_mod.delete_group grp.id
for name in *{ D_NAME, C_NAME, B_NAME, A_NAME }
  spaces_mod.delete_user_space name
require('resolvers.init').reinit!
