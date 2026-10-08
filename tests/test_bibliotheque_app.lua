local R = require('tests.runner')
local json = require('json')
local _mod = nil
local load_app
load_app = function()
  if _mod then
    return _mod
  end
  local ok, mod = pcall(require, 'tools.bibliotheque_app')
  if not (ok) then
    error("module 'tools.bibliotheque_app' indisponible : " .. tostring(mod))
  end
  _mod = mod
  return _mod
end
local EXPECTED_COUNTS = {
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
  },
  {
    'Genres',
    15
  },
  {
    'Auteurs',
    25
  },
  {
    'MotsCles',
    40
  },
  {
    'Livres',
    60
  },
  {
    'LivresMotsCles',
    120
  },
  {
    'Exemplaires',
    100
  },
  {
    'Emprunts',
    120
  },
  {
    'TypesCoordonnees',
    3
  },
  {
    'Coordonnees',
    30
  },
  {
    'PersonnesCoordonnees',
    50
  }
}
local FOREIGN_KEYS = {
  {
    'Annee',
    'section',
    'Sections'
  },
  {
    'Niveaux',
    'superieur',
    'Niveaux'
  },
  {
    'Personnes',
    'titre',
    'Titres'
  },
  {
    'Personnes',
    'famille',
    'Personnes'
  },
  {
    'Prefectures',
    'annee',
    'Annee'
  },
  {
    'Prefectures',
    'prefet',
    'Personnes'
  },
  {
    'Prefectures',
    'niveau_min',
    'Niveaux'
  },
  {
    'Prefectures',
    'niveau_max',
    'Niveaux'
  },
  {
    'Classes',
    'niveau',
    'Niveaux'
  },
  {
    'Classes',
    'annee',
    'Annee'
  },
  {
    'Classes',
    'prefecture',
    'Prefectures'
  },
  {
    'Classes',
    'professeur_principal',
    'Personnes'
  },
  {
    'ClassesEleves',
    'classe',
    'Classes'
  },
  {
    'ClassesEleves',
    'eleve',
    'Personnes'
  },
  {
    'Genres',
    'parent',
    'Genres'
  },
  {
    'Livres',
    'auteur',
    'Auteurs'
  },
  {
    'Livres',
    'genre',
    'Genres'
  },
  {
    'LivresMotsCles',
    'livre',
    'Livres'
  },
  {
    'LivresMotsCles',
    'mot_cle',
    'MotsCles'
  },
  {
    'Exemplaires',
    'livre',
    'Livres'
  },
  {
    'Emprunts',
    'personne',
    'Personnes'
  },
  {
    'Emprunts',
    'exemplaire',
    'Exemplaires'
  },
  {
    'Coordonnees',
    'type_coordonnee',
    'TypesCoordonnees'
  },
  {
    'PersonnesCoordonnees',
    'personne',
    'Personnes'
  },
  {
    'PersonnesCoordonnees',
    'coordonnee',
    'Coordonnees'
  }
}
local by_space
by_space = function(tables)
  local map = { }
  for _index_0 = 1, #tables do
    local t = tables[_index_0]
    map[t.space] = t.rows
  end
  return map
end
local id_set
id_set = function(rows)
  local ids = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    ids[r.id] = true
  end
  return ids
end
local missing_fk
missing_fk = function(rows, field, ids)
  local out = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    local v = r[field]
    if v ~= nil and v ~= '' and not ids[v] then
      table.insert(out, v)
    end
  end
  return out
end
local duplicate_ids
duplicate_ids = function(rows)
  local seen, out = { }, { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    if r.id == nil then
      table.insert(out, 'nil')
    elseif seen[r.id] then
      table.insert(out, r.id)
    else
      seen[r.id] = true
    end
  end
  return out
end
local space_names
space_names = function(tables)
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #tables do
    local t = tables[_index_0]
    _accum_0[_len_0] = t.space
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
local expected_names
do
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #EXPECTED_COUNTS do
    local e = EXPECTED_COUNTS[_index_0]
    _accum_0[_len_0] = e[1]
    _len_0 = _len_0 + 1
  end
  expected_names = _accum_0
end
return R.describe("bibliotheque_app.seed_tables", function()
  R.it("is deterministic (two calls encode to the same JSON)", function()
    local m = load_app()
    return R.eq(json.encode(m.seed_tables()), json.encode(m.seed_tables()))
  end)
  R.it("has the exact row counts at scale 1, in order", function()
    local m = load_app()
    local tables = m.seed_tables()
    local map = by_space(tables)
    R.eq(json.encode(space_names(tables)), json.encode(expected_names), 'space order')
    for _index_0 = 1, #EXPECTED_COUNTS do
      local e = EXPECTED_COUNTS[_index_0]
      local rows = map[e[1]]
      if rows then
        R.eq(#rows, e[2], e[1])
      else
        R.ok(rows, "espace " .. tostring(e[1]) .. " absent")
      end
    end
  end)
  R.it("keeps every non-empty foreign key valid", function()
    local m = load_app()
    local map = by_space(m.seed_tables())
    for _index_0 = 1, #FOREIGN_KEYS do
      local _continue_0 = false
      repeat
        local fk = FOREIGN_KEYS[_index_0]
        local rows, target = map[fk[1]], map[fk[3]]
        if not (rows and target) then
          R.ok(false, "espace manquant " .. tostring(fk[1]) .. " → " .. tostring(fk[3]))
          _continue_0 = true
          break
        end
        local bad = missing_fk(rows, fk[2], id_set(target))
        R.eq(#bad, 0, tostring(fk[1]) .. "." .. tostring(fk[2]) .. " → " .. tostring(fk[3]) .. ": " .. tostring(json.encode(bad)))
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  R.it("has unique ids in every space", function()
    local m = load_app()
    local _list_0 = m.seed_tables()
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local dups = duplicate_ids(t.rows)
      R.eq(#dups, 0, tostring(t.space) .. ": " .. tostring(json.encode(dups)))
    end
  end)
  return R.it("emits more rows at scale 2 (Personnes, Livres, Emprunts)", function()
    local m = load_app()
    local s1 = by_space(m.seed_tables({
      scale = 1
    }))
    local s2 = by_space(m.seed_tables({
      scale = 2
    }))
    local _list_0 = {
      'Personnes',
      'Livres',
      'Emprunts'
    }
    for _index_0 = 1, #_list_0 do
      local name = _list_0[_index_0]
      local n1 = s1[name] and #s1[name]
      local n2 = s2[name] and #s2[name]
      R.ok(n1 and n2 and n2 > n1, tostring(name) .. ": " .. tostring(n2) .. " > " .. tostring(n1))
    end
  end)
end)
