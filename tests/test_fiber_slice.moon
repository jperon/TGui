-- tests/test_fiber_slice.moon
-- La tranche de fibre n'est plus relevée pour TOUTE l'instance (init.moon) : une
-- lecture de grille lourde ne doit plus bloquer toutes les autres requêtes
-- jusqu'à l'ancienne borne de 20 s. La relève appartient à la REQUÊTE :
-- http_server.handle_graphql pose core.config.REQUEST_SLICE sur la fibre de la
-- requête avant d'exécuter l'opération.
--
-- Note : la suite de tests elle-même relève la tranche de SA fibre
-- (backend/test_runner.moon), parce que des milliers d'assertions s'exécutent
-- dans une seule fibre et accumulent du CPU. Une fibre NEUVE créée ici hérite
-- donc de cette valeur de test, pas du défaut de Tarantool : la relève globale
-- du serveur est vérifiée sur la source de init (aucun set_max_slice).
--
-- Vérifie :
--   1. init.moon ne relève plus la tranche de toute l'instance, et
--      http_server pose la tranche sur la fibre de la requête ;
--   2. REQUEST_SLICE est une borne finie et relevée ;
--   3. set_request_slice relève la tranche de la fibre courante (API par fibre
--      de Tarantool 3 : fiber.self():set_max_slice { warn, err }) ;
--   4. une fibre de requête survit à 1,5 s de CPU sans yield (borne 5 s) ;
--   5. une fibre neuve n'hérite pas de la tranche relevée par sa créatrice ;
--   6. la tranche reste appliquée : un dépassement est bien détecté.
R       = require 'tests.runner'
fiber   = require 'fiber'
clock   = require 'clock'
fio     = require 'fio'
config  = require 'core.config'

-- > tranche d'erreur par défaut (1 s), < REQUEST_SLICE.err (5 s)
BURN_SECONDS = 1.5

burn = (sec) ->
  t0 = clock.monotonic!
  while clock.monotonic! - t0 < sec
    nil

-- Pack all return values (including nils) of fn.
pack = (...) -> { n: select('#', ...), ... }

-- Run fn in a fresh fiber and return its results. A fresh fiber does not
-- inherit the creator's slice: it starts from the instance-wide value.
in_fiber = (fn) ->
  packed = nil
  fi = fiber.new ->
    packed = pack fn!
  fi\set_joinable true
  fi\join!
  unpack packed, 1, packed.n

-- CPU work above the slice: interrupted when the slice is checked
-- (fiber.check_slice!), which is what box does at its yield points.
-- Returns (ok, err).
burn_checked = (sec) ->
  pcall ->
    burn sec
    fiber.check_slice!

-- Read a backend source file (container path first, repo path as fallback).
read_source = (name) ->
  for path in *{ "/app/backend/#{name}", "backend/#{name}" }
    f = fio.open path, {'O_RDONLY'}
    if f
      content = f\read!
      f\close!
      return content
  nil

R.describe "fiber slice — par requête, plus globale", ->

  R.it "init.moon ne relève plus la tranche de toute l'instance", ->
    src = read_source 'init.lua'
    R.ok (type(src) == 'string' and #src > 0), "init.lua lisible"
    R.nok (src and src\find 'set_max_slice', 1, true),
      "init.lua ne doit plus appeler set_max_slice (relève globale)"
    R.nok (src and src\find 'fiber.se', 1, true),
      "init.lua ne doit plus toucher au module fiber pour la tranche"

  R.it "http_server pose la tranche sur la fibre de la requête", ->
    src = read_source 'http_server.lua'
    R.ok (type(src) == 'string' and #src > 0), "http_server.lua lisible"
    R.ok (src and src\find 'set_request_slice', 1, true),
      "handle_graphql doit appeler set_request_slice"

  R.it "REQUEST_SLICE est une borne finie, relevée au-dessus du défaut", ->
    R.eq config.REQUEST_SLICE.warn, 1, 'warn'
    R.eq config.REQUEST_SLICE.err, 5, 'err'
    R.ok (config.REQUEST_SLICE.warn < config.REQUEST_SLICE.err), 'warn < err'
    R.ok (config.REQUEST_SLICE.err < math.huge), 'borne finie (pas un retrait)'

  R.it "set_request_slice relève la tranche de la fibre courante (API par fibre)", ->
    ms = in_fiber ->
      config.set_request_slice!
      fiber.self!\info!.max_slice
    R.eq ms.err, config.REQUEST_SLICE.err, 'err'
    R.eq ms.warn, config.REQUEST_SLICE.warn, 'warn'

  R.it "une fibre de requête survit à 1,5 s de CPU sans yield (borne 5 s)", ->
    ok, err = in_fiber ->
      config.set_request_slice!
      burn_checked BURN_SECONDS
    R.ok ok, "pas d'interruption dans la requête (#{tostring err})"

  R.it "une fibre neuve n'hérite pas de la tranche relevée", ->
    parent_before, child_after = in_fiber ->
      before = fiber.self!\info!.max_slice.err
      config.set_request_slice!
      -- fibre enfant créée APRÈS la relève : elle repart de la valeur d'instance
      after = in_fiber -> fiber.self!\info!.max_slice.err
      before, after
    R.eq child_after, parent_before, "la fibre enfant garde la valeur d'instance (#{child_after})"
    R.ok (child_after != config.REQUEST_SLICE.err),
      "la fibre enfant ne prend pas la borne de requête (#{config.REQUEST_SLICE.err})"

  R.it "la tranche reste appliquée : un dépassement est détecté", ->
    ok, err = in_fiber ->
      fiber.self!\set_max_slice { warn: 0.05, err: 0.1 }
      burn_checked 0.25
    R.nok ok, "un dépassement doit être interrompu (#{tostring err})"
    R.matches (tostring err), 'slice', "message d'interruption (#{tostring err})"
