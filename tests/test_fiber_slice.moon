-- tests/test_fiber_slice.moon
-- T17 — la tranche de fibre par défaut doit être RELEVÉE (pas retirée) : une
-- lecture de grille lourde (100+ lignes, une dizaine de colonnes calculées qui
-- lisent d'autres espaces via space()) s'exécute dans une seule fibre. Avec la
-- valeur par défaut de Tarantool 3.7 ({warn = 0.5, err = 1}), la suite de tests
-- et une requête HTTP chargée dépassent la tranche sans rendre la main et box
-- lève « fiber slice is exceeded ».
--
-- L'API de lecture disponible est fiber.self():info().max_slice ({warn, err}).
R = require 'tests.runner'
fiber = require 'fiber'
clock = require 'clock'

EXPECTED_WARN = 2
EXPECTED_ERR = 20

R.describe "fiber slice — relevée, protegee", ->

  R.it "la fibre courante annonce un max_slice au moins égal à la valeur fixée", ->
    ms = fiber.self!\info!.max_slice
    R.ok (type(ms) == 'table'), "max_slice lisible (#{type ms})"
    R.ok (ms and ms.err >= EXPECTED_ERR), "tranche d'erreur #{ms and ms.err} >= #{EXPECTED_ERR}"
    R.ok (ms and ms.warn >= EXPECTED_WARN), "tranche d'avertissement #{ms and ms.warn} >= #{EXPECTED_WARN}"

  R.it "la protection reste finie : une borne plus haute, pas un retrait", ->
    ms = fiber.self!\info!.max_slice
    R.ok (ms and type(ms.err) == 'number' and ms.err < math.huge),
      "tranche d'erreur finie (#{ms and ms.err})"

  R.it "plus d'une seconde de CPU sans yield n'interrompt plus une lecture box", ->
    -- Ancien défaut err = 1 : ce travail sans rendement dépassait la tranche et
    -- faisait lever fiber.check_slice. Avec la tranche relevée, il passe.
    t0 = clock.monotonic!
    while clock.monotonic! - t0 < 1.5
      fiber.check_slice!
    rows = box.space._tdb_spaces\select {}
    R.ok (#rows >= 0), "select après 1.5s de CPU sans yield (#{#rows} espaces)"
