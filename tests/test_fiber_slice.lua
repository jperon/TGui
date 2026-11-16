local R = require('tests.runner')
local fiber = require('fiber')
local clock = require('clock')
local fio = require('fio')
local config = require('core.config')
local BURN_SECONDS = 1.5
local burn
burn = function(sec)
  local t0 = clock.monotonic()
  while clock.monotonic() - t0 < sec do
    local _scrap_0 = nil
  end
end
local pack
pack = function(...)
  return {
    n = select('#', ...),
    ...
  }
end
local in_fiber
in_fiber = function(fn)
  local packed = nil
  local fi = fiber.new(function()
    packed = pack(fn())
  end)
  fi:set_joinable(true)
  fi:join()
  return unpack(packed, 1, packed.n)
end
local burn_checked
burn_checked = function(sec)
  return pcall(function()
    burn(sec)
    return fiber.check_slice()
  end)
end
local read_source
read_source = function(name)
  local _list_0 = {
    "/app/backend/" .. tostring(name),
    "backend/" .. tostring(name)
  }
  for _index_0 = 1, #_list_0 do
    local path = _list_0[_index_0]
    local f = fio.open(path, {
      'O_RDONLY'
    })
    if f then
      local content = f:read()
      f:close()
      return content
    end
  end
  return nil
end
return R.describe("fiber slice — par requête, plus globale", function()
  R.it("init.moon ne relève plus la tranche de toute l'instance", function()
    local src = read_source('init.lua')
    R.ok((type(src) == 'string' and #src > 0), "init.lua lisible")
    R.nok((src and src:find('set_max_slice', 1, true)), "init.lua ne doit plus appeler set_max_slice (relève globale)")
    return R.nok((src and src:find('fiber.se', 1, true)), "init.lua ne doit plus toucher au module fiber pour la tranche")
  end)
  R.it("http_server pose la tranche sur la fibre de la requête", function()
    local src = read_source('http_server.lua')
    R.ok((type(src) == 'string' and #src > 0), "http_server.lua lisible")
    return R.ok((src and src:find('set_request_slice', 1, true)), "handle_graphql doit appeler set_request_slice")
  end)
  R.it("REQUEST_SLICE est une borne finie, relevée au-dessus du défaut", function()
    R.eq(config.REQUEST_SLICE.warn, 1, 'warn')
    R.eq(config.REQUEST_SLICE.err, 5, 'err')
    R.ok((config.REQUEST_SLICE.warn < config.REQUEST_SLICE.err), 'warn < err')
    return R.ok((config.REQUEST_SLICE.err < math.huge), 'borne finie (pas un retrait)')
  end)
  R.it("set_request_slice relève la tranche de la fibre courante (API par fibre)", function()
    local ms = in_fiber(function()
      config.set_request_slice()
      return fiber.self():info().max_slice
    end)
    R.eq(ms.err, config.REQUEST_SLICE.err, 'err')
    return R.eq(ms.warn, config.REQUEST_SLICE.warn, 'warn')
  end)
  R.it("une fibre de requête survit à 1,5 s de CPU sans yield (borne 5 s)", function()
    local ok, err = in_fiber(function()
      config.set_request_slice()
      return burn_checked(BURN_SECONDS)
    end)
    return R.ok(ok, "pas d'interruption dans la requête (" .. tostring(tostring(err)) .. ")")
  end)
  R.it("une fibre neuve n'hérite pas de la tranche relevée", function()
    local parent_before, child_after = in_fiber(function()
      local before = fiber.self():info().max_slice.err
      config.set_request_slice()
      local after = in_fiber(function()
        return fiber.self():info().max_slice.err
      end)
      return before, after
    end)
    R.eq(child_after, parent_before, "la fibre enfant garde la valeur d'instance (" .. tostring(child_after) .. ")")
    return R.ok((child_after ~= config.REQUEST_SLICE.err), "la fibre enfant ne prend pas la borne de requête (" .. tostring(config.REQUEST_SLICE.err) .. ")")
  end)
  return R.it("la tranche reste appliquée : un dépassement est détecté", function()
    local ok, err = in_fiber(function()
      fiber.self():set_max_slice({
        warn = 0.05,
        err = 0.1
      })
      return burn_checked(0.25)
    end)
    R.nok(ok, "un dépassement doit être interrompu (" .. tostring(tostring(err)) .. ")")
    return R.matches((tostring(err)), 'slice', "message d'interruption (" .. tostring(tostring(err)) .. ")")
  end)
end)
