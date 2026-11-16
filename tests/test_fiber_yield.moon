-- tests/test_fiber_yield.moon
-- Cession coopérative des boucles de lecture (core.config.yield_every).
--
-- Tarantool est coopératif : une lecture de grille lourde (une formule par
-- ligne) bloque toutes les autres fibres jusqu'à son retour. Les boucles par
-- ligne de lecture appellent désormais yield_every(i) : une fibre concurrente
-- progresse pendant la lecture. Le garde box.is_in_txn() interdit la cession
-- dans une transaction, où Tarantool refuse catégoriquement yield (box.atomic
-- des résolveurs de lot et de app_apply).
--
-- Couvre :
--   1. yield_every ne cède JAMAIS dans box.atomic, sans lever d'erreur ;
--   2. yield_every cède hors transaction et une fibre concurrente progresse ;
--   3. une lecture GraphQL records de 500 lignes (colonne calculée) laisse
--      progresser une fibre concurrente et reste exacte ;
--   4. idem pour data_resolvers.Query.records (formules de représentation) ;
--   5. une requête concurrente intercalée ne corrompt aucune des deux lectures
--      (cache fk_cache/space() par requête).
R          = require 'tests.runner'
json       = require 'json'
fiber      = require 'fiber'
config     = require 'core.config'
spaces_mod = require 'core.spaces'
auth       = require 'core.auth'
executor   = require 'graphql.executor'
dynamic    = require 'graphql.dynamic'
data_r     = require 'resolvers.data_resolvers'

SUFFIX     = tostring math.random 100000, 999999
SPACE_NAME = "fyield_#{SUFFIX}"
ROW_COUNT  = 500

CALC_FORMULA = 'tostring(self.a) .. "-" .. tostring(self.b)'
REPR_FORMULA = "tostring(self.a) .. '/' .. tostring(self.b)"

expected_calc = (a, b) -> "#{tostring a}-#{tostring b}"
expected_repr = (a, b) -> "#{tostring a}/#{tostring b}"

-- ── Fixture : un espace de 500 lignes avec une colonne calculée ──────────────

sp = spaces_mod.create_user_space SPACE_NAME, 'T-yield — cession cooperative'
spaces_mod.add_field sp.id, 'id', 'Int'
spaces_mod.add_field sp.id, 'a', 'Int'
spaces_mod.add_field sp.id, 'b', 'Int'
spaces_mod.add_field sp.id, 'calc', 'String', false, '', CALC_FORMULA, nil, 'lua'
spaces_mod.add_field sp.id, 'label', 'String', false, '', nil, nil, nil, REPR_FORMULA

data_sp = box.space["data_#{SPACE_NAME}"]
for i = 1, ROW_COUNT
  data_sp\insert { i, json.encode { id: i, a: i, b: i * 2, label: "L#{i}" } }

require('resolvers.init').reinit!

admin_user = auth.get_user_by_username 'admin'
admin_sess = auth.create_session admin_user.id
CTX  = { user_id: admin_user.id, token: admin_sess.token }
-- One ctx per simulated request: caches are per request, never shared.
CTX2 = { user_id: admin_user.id, token: admin_sess.token }

T = dynamic.gql_name SPACE_NAME

-- ── Acteurs ──────────────────────────────────────────────────────────────────

-- A fiber that counts its own scheduling opportunities: it increments once per
-- turn and yields back, so the counter only grows when somebody else yields.
start_counter = ->
  state = { count: 0, stop: false }
  fi = fiber.new ->
    while not state.stop
      state.count += 1
      fiber.yield!
  fi\set_joinable true
  state.fiber = fi
  state

-- Start the counter and let it take one turn, so `count` is already non-zero.
primed_counter = ->
  state = start_counter!
  fiber.yield!
  state

stop_counter = (state) ->
  state.stop = true
  state.fiber\join!

decode_item = (item) ->
  if type(item.data) == 'string' then json.decode item.data else item.data

-- ── Tests ────────────────────────────────────────────────────────────────────

R.describe "yield_every — cession coopérative des lectures", ->

  R.it "ne cède pas dans box.atomic et ne lève aucune erreur de transaction", ->
    counter = primed_counter!
    before = counter.count
    yielded = 0
    saw_txn = false
    ok, err = pcall ->
      box.atomic ->
        saw_txn = box.is_in_txn!
        for i = 1, 256
          yielded += 1 if config.yield_every i
    stop_counter counter
    R.ok ok, "box.atomic doit se terminer sans erreur (#{tostring err})"
    R.ok saw_txn, "la transaction était bien ouverte"
    R.eq yielded, 0, 'aucun yield dans la transaction'
    R.eq counter.count, before, 'la fibre concurrente ne progresse pas dans la transaction'

  R.it "cède hors transaction : une fibre concurrente progresse", ->
    counter = primed_counter!
    before = counter.count
    yielded = 0
    for i = 1, 256
      yielded += 1 if config.yield_every i
    progressed = counter.count - before
    stop_counter counter
    R.eq yielded, 4, 'cessions pour 256 itérations (YIELD_EVERY = 64)'
    R.ok (progressed >= 4), "la fibre concurrente avance de #{progressed} tours"

  R.it "lecture GraphQL de 500 lignes : une fibre concurrente progresse", ->
    counter = primed_counter!
    before = counter.count
    res = executor.execute { query: "{ #{T}(limit: 1000) { items { id a b calc } } }", context: CTX }
    after = counter.count
    stop_counter counter
    R.nok res.errors, json.encode res.errors
    items = res.data[T].items
    R.eq #items, ROW_COUNT, 'items'
    bad = 0
    for item in *items
      bad += 1 if tostring(item.calc) != expected_calc(item.a, item.b)
    R.eq bad, 0, "#{bad}/#{ROW_COUNT} valeurs calc fausses apres cession"
    print "    [measure] 500 lignes lues, fibre concurrente : #{before} -> #{after} tours"
    R.ok (after > before), "la lecture doit ceder la main (tours #{before} -> #{after})"

  R.it "Query.records de 500 lignes (reprFormula) : une fibre concurrente progresse", ->
    counter = primed_counter!
    before = counter.count
    res = data_r.Query.records nil, { spaceId: sp.id, limit: 1000 }, CTX
    after = counter.count
    stop_counter counter
    R.eq res.total, ROW_COUNT, 'total'
    bad = 0
    for item in *res.items
      d = decode_item item
      bad += 1 if tostring(d._repr_label) != expected_repr(d.a, d.b)
    R.eq bad, 0, "#{bad}/#{ROW_COUNT} _repr_label fausses apres cession"
    print "    [measure] Query.records 500 lignes, fibre concurrente : #{before} -> #{after} tours"
    R.ok (after > before), "la boucle de lignes doit ceder la main (tours #{before} -> #{after})"

  R.it "une requête concurrente intercalée ne corrompt aucune des deux lectures", ->
    other = { ok: 0, errors: 0, last_error: nil, stop: false }
    fi = fiber.new ->
      while not other.stop
        r = executor.execute { query: "{ #{T}(limit: 1000) { items { id calc } } }", context: CTX2 }
        if r.errors
          other.errors += 1
          other.last_error = json.encode r.errors
        else
          other.ok += 1
        fiber.yield!
    fi\set_joinable true

    res = executor.execute { query: "{ #{T}(limit: 1000) { items { id a b calc } } }", context: CTX }
    other.stop = true
    fi\join!

    R.nok res.errors, json.encode res.errors
    items = res.data[T].items
    R.eq #items, ROW_COUNT, 'items'
    bad = 0
    for item in *items
      bad += 1 if tostring(item.calc) != expected_calc(item.a, item.b)
    R.eq bad, 0, "#{bad}/#{ROW_COUNT} valeurs fausses apres entrelacement"
    R.eq other.errors, 0, "requete concurrente : #{other.errors} erreur(s) (#{tostring other.last_error})"
    print "    [measure] requetes concurrentes terminees : #{other.ok} lectures entrelacees"
    R.ok (other.ok > 0), "la requete concurrente doit avoir tourne au moins une fois"

-- ── Nettoyage ────────────────────────────────────────────────────────────────

auth.delete_session CTX.token
spaces_mod.delete_user_space SPACE_NAME
require('resolvers.init').reinit!
