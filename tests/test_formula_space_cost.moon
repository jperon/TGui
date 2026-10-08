-- tests/test_formula_space_cost.moon
-- T10 — coût des formules qui lisent d'autres espaces.
--
-- La garde d'instructions (core.config.safe_formula_call) doit borner le code
-- de la FORMULE (boucles infinies), pas le chargement de données fait par
-- l'hôte pendant son appel : select + json.decode de toutes les lignes d'un
-- espace (core.formula_proxy.make_space_helper / ensure_space), construction
-- d'une carte de relations (ensure_fk_def_map), compilation MoonScript
-- (ensure_formulas, ~46M d'instructions mesurés). Sans run_unguarded, space()
-- sur un espace de 150 lignes (~126M d'instructions mesurées pour 100 lignes)
-- et la compilation dépassent la limite de 20M : la colonne calculée rend
-- null ou « instruction limit exceeded ».
--
-- Chemin de lecture testé : Query.records avec reprFormula de champ
-- (`_repr_<champ>`), c'est-à-dire le chemin réellement utilisé par la grille
-- de données du frontend (frontend/src/views/data_view.coffee lit
-- `_repr_#{name}`), et le seul qui fasse évaluer une colonne calculée par le
-- proxy de core.formula_proxy.
--
-- Avant le correctif, « le bon compte » doit être ROUGE (la compilation de la
-- formule et le chargement de A sont imputés au budget de la formule). Les
-- autres cas sont des gardes de non-régression : verts avant ET après
-- (boucles infinies toujours bornées, trigger non mémoïsé, cache par requête,
-- can_read respecté même quand l'espace est déjà en cache).

R         = require 'tests.runner'
json      = require 'json'
auth      = require 'core.auth'
perms_mod = require 'core.permissions'
spaces_mod = require 'core.spaces'
triggers  = require 'core.triggers'
config_mod = require 'core.config'
data_r    = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999

A_NAME  = "fsc_a_#{SUFFIX}"    -- 150 lignes, champ k Int
B_NAME  = "fsc_b_#{SUFFIX}"    -- 150 lignes, colonne calculée n lisant A
D_NAME  = "fsc_d_#{SUFFIX}"    -- colonne calculée en boucle infinie
E_NAME  = "fsc_e_#{SUFFIX}"    -- colonne calculée : while true do space(A)
T_NAME  = "fsc_t_#{SUFFIX}"    -- trigger en boucle sur space(A)
SA_NAME = "fsc_sa_#{SUFFIX}"   -- petit espace (3 lignes) compté par un trigger
U_NAME  = "fsc_u_#{SUFFIX}"    -- trigger comptant les lignes de SA
PA_NAME = "fsc_pa_#{SUFFIX}"   -- espace secret (contrôle can_read)
PB_NAME = "fsc_pb_#{SUFFIX}"   -- colonne calculée lisant PA

SECRET = "secret-t10-#{SUFFIX}"

MAX_BOUNDED_SECONDS = 20

-- ── Helpers ──────────────────────────────────────────────────────────────────

admin_user = auth.get_user_by_username 'admin'
admin_sess = auth.create_session admin_user.id

-- Un contexte neuf = une requête HTTP distincte (http_server en bâtit un par
-- requête) : c'est lui qui porte le fk_cache « par requête ».
fresh_ctx = -> { user_id: admin_user.id, token: admin_sess.token }

ins = (space_id, data) ->
  data_r.Mutation.insertRecord nil, { spaceId: space_id, data: data }, fresh_ctx!

run_records = (space_id, ctx) ->
  data_r.Query.records nil, { spaceId: space_id, limit: 500 }, ctx

decode_item = (item) -> if type(item.data) == 'string' then json.decode(item.data) else item.data

err_count = (key) ->
  m = config_mod.get_formula_metrics!.error_details[key]
  return 0 unless m
  m.count

read_field = (space_name, id, fname) ->
  t = box.space["data_#{space_name}"]\get id
  return nil unless t
  json.decode(t[2])[fname]

-- ── Fixture ──────────────────────────────────────────────────────────────────

-- A : 150 lignes, k réparti de 1 à 25 (6 lignes par valeur).
a_sp = spaces_mod.create_user_space A_NAME, 'T10 — espace lu par space()'
a_id = a_sp.id
spaces_mod.add_field a_id, 'k', 'Int'

-- B : 150 lignes, colonne calculée MoonScript comptant les lignes de A dont
-- k vaut l'id de la ligne courante, plus un reprFormula qui la fait évaluer
-- par Query.records (chemin grille du frontend).
b_sp = spaces_mod.create_user_space B_NAME, 'T10 — colonne calculée lisant A'
b_id = b_sp.id
spaces_mod.add_field b_id, 'id', 'Int'
count_formula = '#[a for a in *space("' .. A_NAME .. '") when a.k == @id]'
spaces_mod.add_field b_id, 'n', 'Int', false, '', count_formula, nil, 'moonscript', 'self.n'

for i = 1, 150
  ins a_id, { k: ((i - 1) % 25) + 1 }
  ins b_id, { id: i }

-- D : colonne calculée en boucle infinie (langage Lua, repr de champ).
d_sp = spaces_mod.create_user_space D_NAME, 'T10 — boucle infinie'
d_id = d_sp.id
spaces_mod.add_field d_id, 'label', 'String'
spaces_mod.add_field d_id, 'boucle', 'String', false, '',
  '(function() while true do end end)()', nil, 'lua', 'self.boucle'
ins d_id, { label: 'x' }

-- E : colonne calculée bouclant sur space(A) — chemin mémoïsé (fk_cache).
e_sp = spaces_mod.create_user_space E_NAME, 'T10 — boucle sur space()'
e_id = e_sp.id
spaces_mod.add_field e_id, 'label', 'String'
e_formula = '(function() while true do space("' .. A_NAME .. '") end end)()'
spaces_mod.add_field e_id, 'boucle', 'String', false, '', e_formula, nil, 'lua', 'self.boucle'
ins e_id, { label: 'x' }

-- T : trigger bouclant sur space(A) — chemin non mémoïsé, sous garde.
t_sp = spaces_mod.create_user_space T_NAME, 'T10 — trigger bouclé'
t_id = t_sp.id
spaces_mod.add_field t_id, 'label', 'String'
spaces_mod.add_field t_id, 'boucle', 'String', false, '', e_formula, {}, 'lua'
triggers.register_space_trigger T_NAME

-- SA : petit espace (3 lignes), compté par le trigger de U.
sa_sp = spaces_mod.create_user_space SA_NAME, 'T10 — espace compté par un trigger'
sa_id = sa_sp.id
spaces_mod.add_field sa_id, 'k', 'Int'
for i = 1, 3
  ins sa_id, { k: i }

-- U : trigger comptant les lignes de SA (fraîcheur des données non mémoïsées).
u_sp = spaces_mod.create_user_space U_NAME, 'T10 — trigger compteur'
u_id = u_sp.id
spaces_mod.add_field u_id, 'label', 'String'
count_trigger = '#space("' .. SA_NAME .. '")'
spaces_mod.add_field u_id, 'nb', 'Int', false, '', count_trigger, {}, 'lua'
triggers.register_space_trigger U_NAME

-- PA/PB : colonne calculée lisant un espace soumis à can_read.
pa_sp = spaces_mod.create_user_space PA_NAME, 'T10 — espace secret'
pa_id = pa_sp.id
spaces_mod.add_field pa_id, 'secret', 'String'
ins pa_id, { secret: SECRET }

pb_sp = spaces_mod.create_user_space PB_NAME, 'T10 — colonne calculée lisant PA'
pb_id = pb_sp.id
spaces_mod.add_field pb_id, 'label', 'String'
seen_formula = 'space("' .. PA_NAME .. '")[1] and space("' .. PA_NAME .. '")[1].secret or "none"'
spaces_mod.add_field pb_id, 'seen', 'String', false, '', seen_formula, nil, 'lua', 'self.seen'
ins pb_id, { label: 'x' }

-- Utilisateur témoin : lecture sur PB et, dans un premier temps, sur PA.
user_x = auth.create_user "fscx_#{SUFFIX}", "fscx_#{SUFFIX}@test.local", "pass1234"
sess_x = auth.create_session user_x.id
ctx_x = { user_id: user_x.id, token: sess_x.token }
grp_x = perms_mod.create_group "fscx_#{SUFFIX}", ''
perms_mod.grant grp_x.id, 'space', pb_id, 'read'
perm_a = perms_mod.grant grp_x.id, 'space', pa_id, 'read'
perms_mod.add_member user_x.id, grp_x.id

-- ── Tests ────────────────────────────────────────────────────────────────────

R.describe "T10 — space() dans une colonne calculée (150 lignes)", ->
  R.it "records(B) rend le bon compte pour chaque ligne, sans instruction limit exceeded", ->
    t0 = os.clock!
    res = run_records b_id, fresh_ctx!
    elapsed = os.clock! - t0
    print "    [measure] #{B_NAME}: #{res.total} lignes lues en #{elapsed}s"
    R.eq res.total, 150, 'total records(B)'
    bad = {}
    for item in *res.items
      d = decode_item item
      n_id = tonumber d.id
      expected = 0
      expected = 6 if n_id and n_id <= 25
      got = tonumber d._repr_n
      if got != expected
        table.insert bad, "id=#{tostring d.id}: _repr_n=#{tostring d._repr_n} (attendu #{expected})"
    R.eq #bad, 0, "#{#bad}/150 comptes incorrects; premier: #{bad[1]}"

R.describe "T10 — la garde reste sur le code de la formule", ->
  R.it "boucle infinie dans une colonne calculée -> instruction limit exceeded", ->
    res = run_records d_id, fresh_ctx!
    R.eq res.total, 1, 'total records(D)'
    d = decode_item res.items[1]
    R.matches tostring(d._repr_boucle), 'instruction limit exceeded',
      "colonne calculée en boucle, got #{tostring d._repr_boucle}"

  R.it "while true do space(A) end en colonne calculée (chemin mémoïsé) reste borné", ->
    t0 = os.clock!
    res = run_records e_id, fresh_ctx!
    elapsed = os.clock! - t0
    print "    [measure] colonne calculée bouclée sur space(): coupée en #{elapsed}s"
    R.eq res.total, 1, 'total records(E)'
    d = decode_item res.items[1]
    R.matches tostring(d._repr_boucle), 'instruction limit exceeded',
      "colonne calculée bouclée sur space(), got #{tostring d._repr_boucle}"
    R.ok elapsed < MAX_BOUNDED_SECONDS, "doit revenir en moins de #{MAX_BOUNDED_SECONDS}s (#{elapsed}s)"

  R.it "while true do space(A) end dans un trigger reste borné", ->
    key = "trigger #{T_NAME}.boucle"
    before = err_count key
    t0 = os.clock!
    res = data_r.Mutation.insertRecord nil, { spaceId: t_id, data: { label: 'loop' } }, fresh_ctx!
    elapsed = os.clock! - t0
    after = err_count key
    print "    [measure] trigger bouclé sur space(): coupé en #{elapsed}s"
    R.ok res.id, "l'insertion doit aboutir (le trigger attrape l'erreur)"
    R.ok after > before, "la garde doit s'être déclenchée (#{before} -> #{after})"
    m = config_mod.get_formula_metrics!.error_details[key]
    R.matches tostring(m and m.last_error), 'instruction limit exceeded',
      "message de la garde, got #{m and m.last_error}"
    R.ok elapsed < MAX_BOUNDED_SECONDS, "doit revenir en moins de #{MAX_BOUNDED_SECONDS}s (#{elapsed}s)"

R.describe "T10 — mémoïsation : fraîcheur et permissions", ->
  R.it "un trigger comptant les lignes voit l'écriture fraîche dans l'espace lu", ->
    r1 = ins u_id, { label: 'u1' }
    R.eq read_field(U_NAME, r1.id, 'nb'), 3, "3 lignes dans SA avant insertion"
    ins sa_id, { k: 4 }
    r2 = ins u_id, { label: 'u2' }
    R.eq read_field(U_NAME, r2.id, 'nb'), 4, "la 4e ligne de SA doit être vue (pas de cache)"

  R.it "le cache est par requête : deux records successifs voient la modification de A", ->
    res1 = run_records b_id, fresh_ctx!
    d1 = nil
    for item in *res1.items
      d = decode_item item
      d1 = d if tonumber(d.id) == 1
    R.ok d1, "ligne id=1 trouvée"
    R.eq tonumber(d1._repr_n), 6, "compte avant insertion dans A"

    ins a_id, { k: 1 }

    res2 = run_records b_id, fresh_ctx!
    d2 = nil
    for item in *res2.items
      d = decode_item item
      d2 = d if tonumber(d.id) == 1
    R.ok d2, "ligne id=1 trouvée (2e requête)"
    R.eq tonumber(d2._repr_n), 7, "compte après insertion dans A (nouvelle requête)"

  R.it "space() refuse un espace non lisible même quand il est déjà en cache", ->
    res = run_records pb_id, ctx_x
    d = decode_item res.items[1]
    R.eq d._repr_seen, SECRET, "témoin avec droit de lecture sur PA"

    fk_cache = ctx_x._fk_cache
    R.ok fk_cache and fk_cache.spaces and fk_cache.spaces[PA_NAME],
      "PA doit être en cache dans le fk_cache de la requête"

    perms_mod.revoke perm_a.id

    -- Même contexte : le fk_cache (donc la copie de PA) reste en place, seule
    -- la carte de lisibilité est recalculée par fk_cache_for.
    res2 = run_records pb_id, ctx_x
    d2 = decode_item res2.items[1]
    R.eq d2._repr_seen, 'none', "sans droit de lecture, space() doit renvoyer une liste vide"
    R.ok ctx_x._fk_cache and ctx_x._fk_cache.spaces and ctx_x._fk_cache.spaces[PA_NAME],
      "le cache de la requête reste chaud"

-- ── Cleanup ──────────────────────────────────────────────────────────────────

auth.delete_session sess_x.token
box.space._tdb_users\delete user_x.id
auth.delete_session admin_sess.token
perms_mod.delete_group grp_x.id

for name in *{ B_NAME, E_NAME, D_NAME, T_NAME, U_NAME, SA_NAME, PB_NAME, PA_NAME, A_NAME }
  spaces_mod.delete_user_space name

require('resolvers.init').reinit!
