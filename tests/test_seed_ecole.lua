local R = require('tests.runner')
local json = require('json')
local RNG = require('tools.seed_rng')
local _loaded, SEED = pcall(require, 'tools.bibliotheque_seed_ecole')
if not (_loaded) then
  SEED = nil
end
local need
need = function()
  R.ok(SEED, 'module tools.bibliotheque_seed_ecole absent')
  return SEED ~= nil
end
local gen
gen = function(k)
  return SEED.generate(RNG.new(1001), k or 1)
end
local rows_of
rows_of = function(out, space)
  local _list_0 = out.tables
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t.space == space then
      return t.rows
    end
  end
  return nil
end
local count_of
count_of = function(out, space)
  local rows = rows_of(out, space)
  return rows and #rows or 0
end
local ORDER = 'Titres,Sections,Annee,Niveaux,Personnes,Prefectures,Classes,ClassesEleves'
local VOLUMES = {
  {
    'Titres',
    4
  },
  {
    'Sections',
    2
  },
  {
    'Annee',
    3
  },
  {
    'Niveaux',
    5
  },
  {
    'Personnes',
    72
  },
  {
    'Prefectures',
    3
  },
  {
    'Classes',
    10
  },
  {
    'ClassesEleves',
    108
  }
}
local FK_SPEC = {
  {
    from = 'Personnes',
    field = 'famille',
    to = 'Personnes'
  },
  {
    from = 'Personnes',
    field = 'titre',
    to = 'Titres'
  },
  {
    from = 'Annee',
    field = 'section',
    to = 'Sections'
  },
  {
    from = 'Niveaux',
    field = 'superieur',
    to = 'Niveaux'
  },
  {
    from = 'Prefectures',
    field = 'prefet',
    to = 'Personnes'
  },
  {
    from = 'Prefectures',
    field = 'annee',
    to = 'Annee'
  },
  {
    from = 'Prefectures',
    field = 'niveau_min',
    to = 'Niveaux'
  },
  {
    from = 'Prefectures',
    field = 'niveau_max',
    to = 'Niveaux'
  },
  {
    from = 'Classes',
    field = 'niveau',
    to = 'Niveaux'
  },
  {
    from = 'Classes',
    field = 'annee',
    to = 'Annee'
  },
  {
    from = 'Classes',
    field = 'prefecture',
    to = 'Prefectures'
  },
  {
    from = 'Classes',
    field = 'professeur_principal',
    to = 'Personnes'
  },
  {
    from = 'ClassesEleves',
    field = 'classe',
    to = 'Classes'
  },
  {
    from = 'ClassesEleves',
    field = 'eleve',
    to = 'Personnes'
  }
}
local DATE_SPEC = {
  {
    space = 'Annee',
    field = 'debut'
  },
  {
    space = 'Annee',
    field = 'fin'
  },
  {
    space = 'Personnes',
    field = 'date_de_naissance'
  },
  {
    space = 'ClassesEleves',
    field = 'entree'
  },
  {
    space = 'ClassesEleves',
    field = 'depart'
  }
}
local missing_ids
missing_ids = function(rows, field, targets)
  local ids = { }
  for _index_0 = 1, #targets do
    local r = targets[_index_0]
    ids[r.id] = true
  end
  local bad = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    local v = r[field]
    if v ~= nil and v ~= '' and not ids[v] then
      table.insert(bad, v)
    end
  end
  return bad
end
local niveau_of
niveau_of = function(idx)
  return math.floor((idx - 1) / 12) + 1
end
local _row_bad_keys
_row_bad_keys = function(space, idx, row)
  local bad = { }
  for key, v in pairs(row) do
    if v == nil or v == '' then
      table.insert(bad, tostring(space) .. "[" .. tostring(idx) .. "]." .. tostring(key))
    end
  end
  return bad
end
local empty_values
empty_values = function(out)
  local bad = { }
  local _list_0 = out.tables
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    for i = 1, #t.rows do
      local row_bad = _row_bad_keys(t.space, i, t.rows[i])
      for _index_1 = 1, #row_bad do
        local key = row_bad[_index_1]
        table.insert(bad, key)
      end
    end
  end
  return bad
end
local _row_bad_date
_row_bad_date = function(space, idx, field, v)
  if v == nil then
    return nil
  end
  if not (tostring(v):match('^%d%d%d%d%-%d%d%-%d%d$')) then
    return tostring(space) .. "[" .. tostring(idx) .. "]." .. tostring(field) .. "=" .. tostring(tostring(v))
  end
  return nil
end
local bad_dates
bad_dates = function(out)
  local bad = { }
  for _index_0 = 1, #DATE_SPEC do
    local spec = DATE_SPEC[_index_0]
    local rows = rows_of(out, spec.space)
    for i = 1, #rows do
      local msg = _row_bad_date(spec.space, i, spec.field, rows[i][spec.field])
      if msg then
        table.insert(bad, msg)
      end
    end
  end
  return bad
end
return R.describe("bibliotheque_seed_ecole.generate", function()
  R.it("returns the same rows for the same seed", function()
    if not (need()) then
      return 
    end
    return R.eq(json.encode(gen()), json.encode(gen()), 'deux appels avec RNG.new(1001)')
  end)
  R.it("keeps the exact volumes at k = 1", function()
    if not (need()) then
      return 
    end
    local out = gen()
    R.eq(#out.tables, 8, 'tables')
    for _index_0 = 1, #VOLUMES do
      local pair = VOLUMES[_index_0]
      R.eq(count_of(out, pair[1]), pair[2], pair[1])
    end
    R.eq(#out.adultes, 12, 'adultes')
    R.eq(#out.eleves, 60, 'eleves')
    return R.eq(#out.personnes, 72, 'personnes')
  end)
  R.it("orders the tables as specified", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local names
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = out.tables
      for _index_0 = 1, #_list_0 do
        local t = _list_0[_index_0]
        _accum_0[_len_0] = t.space
        _len_0 = _len_0 + 1
      end
      names = _accum_0
    end
    return R.eq(table.concat(names, ','), ORDER, 'ordre des tables')
  end)
  R.it("gives every row an explicit sequential id", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local _list_0 = out.tables
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      for i = 1, #t.rows do
        local row = t.rows[i]
        R.eq(row.id, i, tostring(t.space) .. " ligne " .. tostring(i))
      end
    end
  end)
  R.it("emits the reference rows of the plan", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local titres = rows_of(out, 'Titres')
    local labels
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #titres do
        local t = titres[_index_0]
        _accum_0[_len_0] = t.titre
        _len_0 = _len_0 + 1
      end
      labels = _accum_0
    end
    R.eq(table.concat(labels, ','), 'M.,Mme,Frère,Sœur', 'titres')
    R.eq(titres[1].femme, false, 'M. femme')
    R.eq(titres[2].femme, true, 'Mme femme')
    R.eq(titres[3].femme, false, 'Frère femme')
    R.eq(titres[4].femme, true, 'Sœur femme')
    local annees = rows_of(out, 'Annee')
    R.eq(annees[1].debut, '2024-09-01', 'annee 1 debut')
    R.eq(annees[1].fin, '2025-06-30', 'annee 1 fin')
    R.eq(annees[2].debut, '2025-09-01', 'annee 2 debut')
    R.eq(annees[2].fin, '2026-06-30', 'annee 2 fin')
    R.eq(annees[3].debut, '2026-09-01', 'annee 3 debut')
    R.eq(annees[3].fin, '2027-06-30', 'annee 3 fin')
    R.nok(annees[1].en_cours, 'annee 1 en_cours')
    R.nok(annees[2].en_cours, 'annee 2 en_cours')
    R.eq(annees[3].en_cours, true, 'annee 3 en_cours')
    local niveaux = rows_of(out, 'Niveaux')
    local abreges
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #niveaux do
        local n = niveaux[_index_0]
        _accum_0[_len_0] = n.abrege
        _len_0 = _len_0 + 1
      end
      abreges = _accum_0
    end
    R.eq(table.concat(abreges, ','), 'CP,CE1,CE2,CM1,CM2', 'abreges')
    for i = 1, #niveaux do
      local n = niveaux[i]
      R.eq(n.niveau, i, "niveau " .. tostring(i))
      if i < 5 then
        R.eq(n.superieur, i + 1, "superieur du niveau " .. tostring(i))
      else
        R.is_nil(n.superieur, 'superieur du niveau 5')
      end
    end
  end)
  R.it("points every foreign key at an existing id", function()
    if not (need()) then
      return 
    end
    local out = gen()
    for _index_0 = 1, #FK_SPEC do
      local spec = FK_SPEC[_index_0]
      local bad = missing_ids(rows_of(out, spec.from), spec.field, rows_of(out, spec.to))
      local label = tostring(spec.from) .. "." .. tostring(spec.field) .. " inconnus: " .. tostring(table.concat(bad, ','))
      R.eq(#bad, 0, label)
    end
  end)
  R.it("uses adults for the staff roles and parents for the families", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local _list_0 = rows_of(out, 'Classes')
    for _index_0 = 1, #_list_0 do
      local c = _list_0[_index_0]
      R.ok(c.professeur_principal and c.professeur_principal <= 5, "professeur_principal " .. tostring(tostring(c.professeur_principal)))
    end
    local _list_1 = rows_of(out, 'Prefectures')
    for _index_0 = 1, #_list_1 do
      local p = _list_1[_index_0]
      R.ok(p.prefet == 6 or p.prefet == 7, "prefet " .. tostring(tostring(p.prefet)))
    end
    local personnes = rows_of(out, 'Personnes')
    for i = 13, #personnes do
      local p = personnes[i]
      R.ok(p.famille and p.famille >= 8 and p.famille <= 12, "famille " .. tostring(tostring(p.famille)) .. " de la personne " .. tostring(p.id))
    end
  end)
  R.it("keeps exactly one class row without depart per student", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local ces = rows_of(out, 'ClassesEleves')
    local _list_0 = out.eleves
    for _index_0 = 1, #_list_0 do
      local eleve = _list_0[_index_0]
      local n = 0
      for _index_1 = 1, #ces do
        local r = ces[_index_1]
        if r.eleve == eleve and not r.depart then
          n = n + 1
        end
      end
      R.eq(n, 1, "eleve " .. tostring(eleve))
    end
  end)
  R.it("places each student in the year-3 class of their own level", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local ces = rows_of(out, 'ClassesEleves')
    for idx = 1, #out.eleves do
      local _continue_0 = false
      repeat
        local eleve = out.eleves[idx]
        local current = nil
        for _index_0 = 1, #ces do
          local r = ces[_index_0]
          if r.eleve == eleve and not r.depart then
            current = r
          end
        end
        if not (current) then
          R.ok(false, "eleve " .. tostring(eleve) .. " sans classe en annee 3")
          _continue_0 = true
          break
        end
        R.eq(current.classe, 5 + niveau_of(idx), "classe annee 3 de l'eleve " .. tostring(eleve))
        R.eq(current.entree, '2026-09-01', "entree annee 3 de l'eleve " .. tostring(eleve))
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  R.it("repeats every student of level 2+ in the class of the level below", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local ces = rows_of(out, 'ClassesEleves')
    for idx = 1, #out.eleves do
      local eleve = out.eleves[idx]
      local niveau = niveau_of(idx)
      local prev = 0
      for _index_0 = 1, #ces do
        local r = ces[_index_0]
        if r.eleve == eleve and r.depart then
          prev = prev + 1
        end
      end
      if niveau == 1 then
        R.eq(prev, 0, "eleve de niveau 1 (" .. tostring(eleve) .. ")")
      else
        R.eq(prev, 1, "eleve de niveau " .. tostring(niveau) .. " (" .. tostring(eleve) .. ")")
      end
    end
  end)
  R.it("dates the year-2 class rows and marks no redoubling", function()
    if not (need()) then
      return 
    end
    local out = gen()
    local ces = rows_of(out, 'ClassesEleves')
    local n_old = 0
    for _index_0 = 1, #ces do
      local r = ces[_index_0]
      if r.depart then
        n_old = n_old + 1
        R.eq(r.entree, '2025-09-01', "entree ligne " .. tostring(r.id))
        R.eq(r.depart, '2026-06-30', "depart ligne " .. tostring(r.id))
        R.eq(r.redoublement, false, "redoublement ligne " .. tostring(r.id))
        R.eq(r.classe, niveau_of(r.eleve - 12) - 1, "classe annee 2 ligne " .. tostring(r.id))
      end
    end
    return R.eq(n_old, 48, 'lignes de deuxieme annee')
  end)
  R.it("contains no empty string or nil value", function()
    if not (need()) then
      return 
    end
    local bad = empty_values(gen())
    return R.eq(#bad, 0, "valeurs vides: " .. tostring(table.concat(bad, ', ')))
  end)
  R.it("writes dates as ISO strings", function()
    if not (need()) then
      return 
    end
    local bad = bad_dates(gen())
    return R.eq(#bad, 0, "dates invalides: " .. tostring(table.concat(bad, ', ')))
  end)
  return R.it("doubles the students at k = 2", function()
    if not (need()) then
      return 
    end
    local out = gen(2)
    R.eq(#out.eleves, 120, 'eleves')
    R.eq(#out.adultes, 12, 'adultes')
    R.eq(#out.personnes, 132, 'personnes')
    R.eq(count_of(out, 'Personnes'), 132, 'Personnes')
    R.eq(count_of(out, 'ClassesEleves'), 216, 'ClassesEleves')
    R.eq(count_of(out, 'Classes'), 10, 'Classes')
    return R.eq(count_of(out, 'Titres'), 4, 'Titres')
  end)
end)
