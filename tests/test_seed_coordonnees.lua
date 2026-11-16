local R = require('tests.runner')
local json = require('json')
local COORD = require('tools.bibliotheque_seed_coordonnees')
local RNG = require('tools.seed_rng')
local P = { }
for i = 1, 72 do
  table.insert(P, i)
end
local ECOLE = {
  personnes = P
}
local LIBELLES_OK = {
  domicile = true,
  parents = true,
  travail = true
}
local by_space
by_space = function(out)
  local m = { }
  local _list_0 = out.tables
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    m[t.space] = t.rows
  end
  return m
end
local is_address
is_address = function(v)
  if not (type(v) == 'string') then
    return false
  end
  if not (v:match('^%d+ %a+ des ')) then
    return false
  end
  local n = tonumber(v:match('^(%d+)'))
  if not (n and n >= 1 and n <= 150) then
    return false
  end
  return not v:match('%d%d%d%d%d')
end
return R.describe("bibliotheque_seed_coordonnees", function()
  local out = COORD.generate(RNG.new(3003), 1, ECOLE)
  local T = by_space(out)
  local types = T.TypesCoordonnees
  local coords = T.Coordonnees
  local links = T.PersonnesCoordonnees
  R.it("returns the three tables in order", function()
    R.eq(#out.tables, 3, 'tables')
    R.eq(out.tables[1].space, 'TypesCoordonnees')
    R.eq(out.tables[2].space, 'Coordonnees')
    return R.eq(out.tables[3].space, 'PersonnesCoordonnees')
  end)
  R.it("is deterministic for a given seed", function()
    local again = COORD.generate(RNG.new(3003), 1, ECOLE)
    return R.eq(json.encode(again), json.encode(out))
  end)
  R.it("has the exact volumes at k = 1", function()
    R.eq(#types, 3, 'TypesCoordonnees')
    R.eq(#coords, 30, 'Coordonnees')
    return R.eq(#links, 50, 'PersonnesCoordonnees')
  end)
  R.it("scales with k", function()
    local big = by_space(COORD.generate(RNG.new(3003), 2, ECOLE))
    R.eq(#big.Coordonnees, 60, 'Coordonnees k=2')
    return R.eq(#big.PersonnesCoordonnees, 100, 'PersonnesCoordonnees k=2')
  end)
  R.it("defines tel, courriel and adresse", function()
    R.eq(types[1].id, 1, 'id tel')
    R.eq(types[1].type, 'tel')
    R.eq(types[2].id, 2, 'id courriel')
    R.eq(types[2].type, 'courriel')
    R.eq(types[3].id, 3, 'id adresse')
    return R.eq(types[3].type, 'adresse')
  end)
  R.it("uses explicit sequential ids", function()
    local bad = 0
    for i = 1, #types do
      if types[i].id ~= i then
        bad = bad + 1
      end
    end
    for i = 1, #coords do
      if coords[i].id ~= i then
        bad = bad + 1
      end
    end
    for i = 1, #links do
      if links[i].id ~= i then
        bad = bad + 1
      end
    end
    return R.eq(bad, 0, 'ids')
  end)
  R.it("points every foreign key at an existing row", function()
    local type_ids, coord_ids, person_ids = { }, { }, { }
    for _index_0 = 1, #types do
      local t = types[_index_0]
      type_ids[t.id] = true
    end
    for _index_0 = 1, #coords do
      local c = coords[_index_0]
      coord_ids[c.id] = true
    end
    for _index_0 = 1, #P do
      local p = P[_index_0]
      person_ids[p] = true
    end
    local bad_type, bad_coord, bad_person = 0, 0, 0
    for _index_0 = 1, #coords do
      local row = coords[_index_0]
      if not (type_ids[row.type_coordonnee]) then
        bad_type = bad_type + 1
      end
    end
    for _index_0 = 1, #links do
      local row = links[_index_0]
      if not (person_ids[row.personne]) then
        bad_person = bad_person + 1
      end
      if not (coord_ids[row.coordonnee]) then
        bad_coord = bad_coord + 1
      end
    end
    R.eq(bad_type, 0, 'type_coordonnee')
    R.eq(bad_person, 0, 'personne')
    return R.eq(bad_coord, 0, 'coordonnee')
  end)
  R.it("spreads coordinates over the three types", function()
    local used = { }
    for _index_0 = 1, #coords do
      local row = coords[_index_0]
      used[row.type_coordonnee] = (used[row.type_coordonnee] or 0) + 1
    end
    R.eq((used[1] or 0) + (used[2] or 0) + (used[3] or 0), 30, 'total')
    return R.ok((used[1] or 0) > 0 and (used[2] or 0) > 0 and (used[3] or 0) > 0, 'types utilisés')
  end)
  R.it("links distinct couples and shares at least one coordinate", function()
    local seen, counts, dup = { }, { }, 0
    for _index_0 = 1, #links do
      local row = links[_index_0]
      local key = tostring(row.personne) .. "|" .. tostring(row.coordonnee)
      if seen[key] then
        dup = dup + 1
      end
      seen[key] = true
      counts[row.coordonnee] = (counts[row.coordonnee] or 0) + 1
    end
    R.eq(dup, 0, 'couples distincts')
    local shared = 0
    for _, n in pairs(counts) do
      if n >= 2 then
        shared = shared + 1
      end
    end
    return R.ok(shared >= 1, 'coordonnée partagée')
  end)
  R.it("labels links with domicile, parents or travail", function()
    local bad = 0
    for _index_0 = 1, #links do
      local row = links[_index_0]
      if not (LIBELLES_OK[row.libelle]) then
        bad = bad + 1
      end
    end
    return R.eq(bad, 0, 'libelle')
  end)
  R.it("uses fictitious values (.invalid emails, reserved phone prefix, invented streets)", function()
    local bad_tel, bad_mail, bad_addr = 0, 0, 0
    for _index_0 = 1, #coords do
      local row = coords[_index_0]
      local v = row.valeur
      if row.type_coordonnee == 1 then
        if not (v:match('^06 00 00 %d%d %d%d$')) then
          bad_tel = bad_tel + 1
        end
      elseif row.type_coordonnee == 2 then
        if not (v:match('^[%w%.]+@exemple%.invalid$')) then
          bad_mail = bad_mail + 1
        end
      elseif row.type_coordonnee == 3 then
        if not (is_address(v)) then
          bad_addr = bad_addr + 1
        end
      end
    end
    R.eq(bad_tel, 0, 'numéros fictifs')
    R.eq(bad_mail, 0, 'courriels .invalid')
    return R.eq(bad_addr, 0, 'adresses inventées')
  end)
  return R.it("stores no empty value", function()
    local bad = 0
    local _list_0 = {
      types,
      coords,
      links
    }
    for _index_0 = 1, #_list_0 do
      local rows = _list_0[_index_0]
      for _index_1 = 1, #rows do
        local row = rows[_index_1]
        for _, v in pairs(row) do
          if v == nil or v == '' then
            bad = bad + 1
          end
        end
      end
    end
    return R.eq(bad, 0, 'valeurs vides')
  end)
end)
