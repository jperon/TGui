local R = require('tests.runner')
local fiber = require('fiber')
local clock = require('clock')
local EXPECTED_WARN = 2
local EXPECTED_ERR = 20
return R.describe("fiber slice — relevée, protegee", function()
  R.it("la fibre courante annonce un max_slice au moins égal à la valeur fixée", function()
    local ms = fiber.self():info().max_slice
    R.ok((type(ms) == 'table'), "max_slice lisible (" .. tostring(type(ms)) .. ")")
    R.ok((ms and ms.err >= EXPECTED_ERR), "tranche d'erreur " .. tostring(ms and ms.err) .. " >= " .. tostring(EXPECTED_ERR))
    return R.ok((ms and ms.warn >= EXPECTED_WARN), "tranche d'avertissement " .. tostring(ms and ms.warn) .. " >= " .. tostring(EXPECTED_WARN))
  end)
  R.it("la protection reste finie : une borne plus haute, pas un retrait", function()
    local ms = fiber.self():info().max_slice
    return R.ok((ms and type(ms.err) == 'number' and ms.err < math.huge), "tranche d'erreur finie (" .. tostring(ms and ms.err) .. ")")
  end)
  return R.it("plus d'une seconde de CPU sans yield n'interrompt plus une lecture box", function()
    local t0 = clock.monotonic()
    while clock.monotonic() - t0 < 1.5 do
      fiber.check_slice()
    end
    local rows = box.space._tdb_spaces:select({ })
    return R.ok((#rows >= 0), "select après 1.5s de CPU sans yield (" .. tostring(#rows) .. " espaces)")
  end)
end)
