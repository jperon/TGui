local R = require('tests.runner')
local json = require('json')
local fiber = require('fiber')
local config = require('core.config')
local spaces_mod = require('core.spaces')
local auth = require('core.auth')
local executor = require('graphql.executor')
local dynamic = require('graphql.dynamic')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local SPACE_NAME = "fyield_" .. tostring(SUFFIX)
local ROW_COUNT = 500
local CALC_FORMULA = 'tostring(self.a) .. "-" .. tostring(self.b)'
local REPR_FORMULA = "tostring(self.a) .. '/' .. tostring(self.b)"
local expected_calc
expected_calc = function(a, b)
  return tostring(tostring(a)) .. "-" .. tostring(tostring(b))
end
local expected_repr
expected_repr = function(a, b)
  return tostring(tostring(a)) .. "/" .. tostring(tostring(b))
end
local sp = spaces_mod.create_user_space(SPACE_NAME, 'T-yield — cession cooperative')
spaces_mod.add_field(sp.id, 'id', 'Int')
spaces_mod.add_field(sp.id, 'a', 'Int')
spaces_mod.add_field(sp.id, 'b', 'Int')
spaces_mod.add_field(sp.id, 'calc', 'String', false, '', CALC_FORMULA, nil, 'lua')
spaces_mod.add_field(sp.id, 'label', 'String', false, '', nil, nil, nil, REPR_FORMULA)
local data_sp = box.space["data_" .. tostring(SPACE_NAME)]
for i = 1, ROW_COUNT do
  data_sp:insert({
    i,
    json.encode({
      id = i,
      a = i,
      b = i * 2,
      label = "L" .. tostring(i)
    })
  })
end
require('resolvers.init').reinit()
local admin_user = auth.get_user_by_username('admin')
local admin_sess = auth.create_session(admin_user.id)
local CTX = {
  user_id = admin_user.id,
  token = admin_sess.token
}
local CTX2 = {
  user_id = admin_user.id,
  token = admin_sess.token
}
local T = dynamic.gql_name(SPACE_NAME)
local start_counter
start_counter = function()
  local state = {
    count = 0,
    stop = false
  }
  local fi = fiber.new(function()
    while not state.stop do
      state.count = state.count + 1
      fiber.yield()
    end
  end)
  fi:set_joinable(true)
  state.fiber = fi
  return state
end
local primed_counter
primed_counter = function()
  local state = start_counter()
  fiber.yield()
  return state
end
local stop_counter
stop_counter = function(state)
  state.stop = true
  return state.fiber:join()
end
local decode_item
decode_item = function(item)
  if type(item.data) == 'string' then
    return json.decode(item.data)
  else
    return item.data
  end
end
R.describe("yield_every — cession coopérative des lectures", function()
  R.it("ne cède pas dans box.atomic et ne lève aucune erreur de transaction", function()
    local counter = primed_counter()
    local before = counter.count
    local yielded = 0
    local saw_txn = false
    local ok, err = pcall(function()
      return box.atomic(function()
        saw_txn = box.is_in_txn()
        for i = 1, 256 do
          if config.yield_every(i) then
            yielded = yielded + 1
          end
        end
      end)
    end)
    stop_counter(counter)
    R.ok(ok, "box.atomic doit se terminer sans erreur (" .. tostring(tostring(err)) .. ")")
    R.ok(saw_txn, "la transaction était bien ouverte")
    R.eq(yielded, 0, 'aucun yield dans la transaction')
    return R.eq(counter.count, before, 'la fibre concurrente ne progresse pas dans la transaction')
  end)
  R.it("cède hors transaction : une fibre concurrente progresse", function()
    local counter = primed_counter()
    local before = counter.count
    local yielded = 0
    for i = 1, 256 do
      if config.yield_every(i) then
        yielded = yielded + 1
      end
    end
    local progressed = counter.count - before
    stop_counter(counter)
    R.eq(yielded, 4, 'cessions pour 256 itérations (YIELD_EVERY = 64)')
    return R.ok((progressed >= 4), "la fibre concurrente avance de " .. tostring(progressed) .. " tours")
  end)
  R.it("lecture GraphQL de 500 lignes : une fibre concurrente progresse", function()
    local counter = primed_counter()
    local before = counter.count
    local res = executor.execute({
      query = "{ " .. tostring(T) .. "(limit: 1000) { items { id a b calc } } }",
      context = CTX
    })
    local after = counter.count
    stop_counter(counter)
    R.nok(res.errors, json.encode(res.errors))
    local items = res.data[T].items
    R.eq(#items, ROW_COUNT, 'items')
    local bad = 0
    for _index_0 = 1, #items do
      local item = items[_index_0]
      if tostring(item.calc) ~= expected_calc(item.a, item.b) then
        bad = bad + 1
      end
    end
    R.eq(bad, 0, tostring(bad) .. "/" .. tostring(ROW_COUNT) .. " valeurs calc fausses apres cession")
    print("    [measure] 500 lignes lues, fibre concurrente : " .. tostring(before) .. " -> " .. tostring(after) .. " tours")
    return R.ok((after > before), "la lecture doit ceder la main (tours " .. tostring(before) .. " -> " .. tostring(after) .. ")")
  end)
  R.it("Query.records de 500 lignes (reprFormula) : une fibre concurrente progresse", function()
    local counter = primed_counter()
    local before = counter.count
    local res = data_r.Query.records(nil, {
      spaceId = sp.id,
      limit = 1000
    }, CTX)
    local after = counter.count
    stop_counter(counter)
    R.eq(res.total, ROW_COUNT, 'total')
    local bad = 0
    local _list_0 = res.items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      local d = decode_item(item)
      if tostring(d._repr_label) ~= expected_repr(d.a, d.b) then
        bad = bad + 1
      end
    end
    R.eq(bad, 0, tostring(bad) .. "/" .. tostring(ROW_COUNT) .. " _repr_label fausses apres cession")
    print("    [measure] Query.records 500 lignes, fibre concurrente : " .. tostring(before) .. " -> " .. tostring(after) .. " tours")
    return R.ok((after > before), "la boucle de lignes doit ceder la main (tours " .. tostring(before) .. " -> " .. tostring(after) .. ")")
  end)
  return R.it("une requête concurrente intercalée ne corrompt aucune des deux lectures", function()
    local other = {
      ok = 0,
      errors = 0,
      last_error = nil,
      stop = false
    }
    local fi = fiber.new(function()
      while not other.stop do
        local r = executor.execute({
          query = "{ " .. tostring(T) .. "(limit: 1000) { items { id calc } } }",
          context = CTX2
        })
        if r.errors then
          other.errors = other.errors + 1
          other.last_error = json.encode(r.errors)
        else
          other.ok = other.ok + 1
        end
        fiber.yield()
      end
    end)
    fi:set_joinable(true)
    local res = executor.execute({
      query = "{ " .. tostring(T) .. "(limit: 1000) { items { id a b calc } } }",
      context = CTX
    })
    other.stop = true
    fi:join()
    R.nok(res.errors, json.encode(res.errors))
    local items = res.data[T].items
    R.eq(#items, ROW_COUNT, 'items')
    local bad = 0
    for _index_0 = 1, #items do
      local item = items[_index_0]
      if tostring(item.calc) ~= expected_calc(item.a, item.b) then
        bad = bad + 1
      end
    end
    R.eq(bad, 0, tostring(bad) .. "/" .. tostring(ROW_COUNT) .. " valeurs fausses apres entrelacement")
    R.eq(other.errors, 0, "requete concurrente : " .. tostring(other.errors) .. " erreur(s) (" .. tostring(tostring(other.last_error)) .. ")")
    print("    [measure] requetes concurrentes terminees : " .. tostring(other.ok) .. " lectures entrelacees")
    return R.ok((other.ok > 0), "la requete concurrente doit avoir tourne au moins une fois")
  end)
end)
auth.delete_session(CTX.token)
spaces_mod.delete_user_space(SPACE_NAME)
return require('resolvers.init').reinit()
