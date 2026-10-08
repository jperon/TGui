local R = require('tests.runner')
local json = require('json')
local LIV = require('tools.bibliotheque_seed_livres')
local RNG = require('tools.seed_rng')
local ECOLE = {
  eleves = { },
  personnes = { }
}
for id = 1, 72 do
  table.insert(ECOLE.personnes, id)
end
for id = 13, 72 do
  table.insert(ECOLE.eleves, id)
end
local ORDER = {
  'Genres',
  'Auteurs',
  'MotsCles',
  'Livres',
  'LivresMotsCles',
  'Exemplaires',
  'Emprunts'
}
local GENRE_NAMES = {
  'Fiction',
  'Roman',
  'Policier',
  'Science-fiction',
  'Aventure',
  'Théâtre',
  'Poésie',
  'Documentaire',
  'Histoire',
  'Sciences',
  'Biographie',
  'Bande dessinée',
  'Jeunesse',
  'Contes',
  'Albums'
}
local GENRE_PARENTS = {
  0,
  1,
  2,
  2,
  2,
  1,
  1,
  0,
  8,
  8,
  8,
  0,
  0,
  13,
  13
}
local ts
ts = function(s)
  return os.time({
    year = tonumber(s:sub(1, 4)),
    month = tonumber(s:sub(6, 7)),
    day = tonumber(s:sub(9, 10)),
    hour = 12
  })
end
local days_between
days_between = function(a, b)
  return math.floor((ts(b) - ts(a)) / 86400)
end
local rows_of
rows_of = function(out)
  local t = { }
  local _list_0 = out.tables
  for _index_0 = 1, #_list_0 do
    local tb = _list_0[_index_0]
    t[tb.space] = tb.rows
  end
  return t
end
local id_set
id_set = function(rows)
  local s = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    s[r.id] = true
  end
  return s
end
local has_empty
has_empty = function(rows)
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    for _, v in pairs(r) do
      if v == '' or v == nil then
        return true
      end
    end
  end
  return false
end
local ISO = '^%d%d%d%d%-%d%d%-%d%d$'
local check_loans
check_loans = function(rows, ex_rows, label)
  local supp = { }
  for _index_0 = 1, #ex_rows do
    local e = ex_rows[_index_0]
    if e.suppression then
      supp[e.id] = true
    end
  end
  local ex_ids = id_set(ex_rows)
  local open = { }
  local n_open = 0
  for _index_0 = 1, #rows do
    local e = rows[_index_0]
    R.ok(ex_ids[e.exemplaire], tostring(label) .. ": emprunt " .. tostring(e.id) .. " → exemplaire " .. tostring(e.exemplaire) .. " existe")
    if not e.retour then
      n_open = n_open + 1
      R.nok(open[e.exemplaire], tostring(label) .. ": exemplaire " .. tostring(e.exemplaire) .. " avec deux prêts ouverts")
      R.nok(supp[e.exemplaire], tostring(label) .. ": prêt ouvert sur exemplaire supprimé " .. tostring(e.exemplaire))
      open[e.exemplaire] = true
      R.ok(e.emprunt >= '2026-09-10' and e.emprunt <= '2026-10-07', tostring(label) .. ": date de prêt ouvert " .. tostring(e.emprunt))
    else
      R.ok(e.emprunt >= '2025-09-15' and e.emprunt <= '2026-06-15', tostring(label) .. ": date d'emprunt " .. tostring(e.emprunt))
      local d = days_between(e.emprunt, e.retour)
      R.ok(d >= 7 and d <= 40, tostring(label) .. ": retour à " .. tostring(d) .. " jours (emprunt " .. tostring(e.id) .. ")")
    end
  end
  return n_open
end
local OUT1 = LIV.generate(RNG.new(2002), 1, ECOLE)
local T = rows_of(OUT1)
return R.describe("seed_livres (T7)", function()
  R.it("emits the seven tables in plan order", function()
    R.eq(#OUT1.tables, 7, 'nb de tables')
    for i = 1, #ORDER do
      R.eq(OUT1.tables[i].space, ORDER[i], "table " .. tostring(i))
    end
  end)
  R.it("has the exact k = 1 volumes", function()
    R.eq(#T.Genres, 15, 'Genres')
    R.eq(#T.Auteurs, 25, 'Auteurs')
    R.eq(#T.MotsCles, 40, 'MotsCles')
    R.eq(#T.Livres, 60, 'Livres')
    R.eq(#T.LivresMotsCles, 120, 'LivresMotsCles')
    R.eq(#T.Exemplaires, 100, 'Exemplaires')
    return R.eq(#T.Emprunts, 120, 'Emprunts')
  end)
  R.it("numbers every row with an explicit id from 1 to n", function()
    for _index_0 = 1, #ORDER do
      local name = ORDER[_index_0]
      local rows = T[name]
      for i = 1, #rows do
        R.eq(rows[i].id, i, tostring(name) .. "[" .. tostring(i) .. "].id")
      end
    end
  end)
  R.it("builds the 15-genre tree of the plan", function()
    for i = 1, 15 do
      local g = T.Genres[i]
      R.eq(g.genre, GENRE_NAMES[i], "genre " .. tostring(i))
      if GENRE_PARENTS[i] == 0 then
        R.is_nil(g.parent, "genre " .. tostring(i) .. " racine")
      else
        R.eq(g.parent, GENRE_PARENTS[i], "genre " .. tostring(i) .. " parent")
      end
    end
  end)
  R.it("keeps every foreign key on an existing row", function()
    local A = id_set(T.Auteurs)
    local G = id_set(T.Genres)
    local L = id_set(T.Livres)
    local M = id_set(T.MotsCles)
    local E = id_set(T.Exemplaires)
    local P = { }
    local _list_0 = ECOLE.personnes
    for _index_0 = 1, #_list_0 do
      local id = _list_0[_index_0]
      P[id] = true
    end
    local _list_1 = T.Livres
    for _index_0 = 1, #_list_1 do
      local r = _list_1[_index_0]
      R.ok(A[r.auteur], "livre " .. tostring(r.id) .. ": auteur " .. tostring(r.auteur))
      R.ok(G[r.genre], "livre " .. tostring(r.id) .. ": genre " .. tostring(r.genre))
    end
    local _list_2 = T.LivresMotsCles
    for _index_0 = 1, #_list_2 do
      local r = _list_2[_index_0]
      R.ok(L[r.livre], "livre-mot " .. tostring(r.id) .. ": livre " .. tostring(r.livre))
      R.ok(M[r.mot_cle], "livre-mot " .. tostring(r.id) .. ": mot " .. tostring(r.mot_cle))
    end
    local _list_3 = T.Exemplaires
    for _index_0 = 1, #_list_3 do
      local r = _list_3[_index_0]
      R.ok(L[r.livre], "exemplaire " .. tostring(r.id) .. ": livre " .. tostring(r.livre))
    end
    local _list_4 = T.Emprunts
    for _index_0 = 1, #_list_4 do
      local r = _list_4[_index_0]
      R.ok(P[r.personne], "emprunt " .. tostring(r.id) .. ": personne " .. tostring(r.personne))
      R.ok(E[r.exemplaire], "emprunt " .. tostring(r.id) .. ": exemplaire " .. tostring(r.exemplaire))
    end
  end)
  R.it("stores no empty string anywhere", function()
    for _index_0 = 1, #ORDER do
      local name = ORDER[_index_0]
      R.nok(has_empty(T[name]), name)
    end
  end)
  R.it("writes ISO dates only", function()
    local _list_0 = T.Exemplaires
    for _index_0 = 1, #_list_0 do
      local r = _list_0[_index_0]
      R.ok(r.acquisition:match(ISO), "acquisition ex " .. tostring(r.id))
      if r.suppression then
        R.ok(r.suppression:match(ISO), "suppression ex " .. tostring(r.id))
      end
    end
    local _list_1 = T.Emprunts
    for _index_0 = 1, #_list_1 do
      local r = _list_1[_index_0]
      R.ok(r.emprunt:match(ISO), "emprunt " .. tostring(r.id))
      if r.retour then
        R.ok(r.retour:match(ISO), "retour " .. tostring(r.id))
      end
    end
  end)
  R.it("leaves one book out of four without exemplaire", function()
    local counts = { }
    local _list_0 = T.Exemplaires
    for _index_0 = 1, #_list_0 do
      local e = _list_0[_index_0]
      counts[e.livre] = (counts[e.livre] or 0) + 1
    end
    local n = 0
    local _list_1 = T.Livres
    for _index_0 = 1, #_list_1 do
      local l = _list_1[_index_0]
      if not (counts[l.id]) then
        n = n + 1
      end
    end
    R.ok(n >= 1, 'au moins un livre sans exemplaire')
    return R.eq(n, 15, 'livres sans exemplaire')
  end)
  R.it("leaves at least one author without book", function()
    local used = { }
    local _list_0 = T.Livres
    for _index_0 = 1, #_list_0 do
      local l = _list_0[_index_0]
      used[l.auteur] = true
    end
    local n = 0
    local _list_1 = T.Auteurs
    for _index_0 = 1, #_list_1 do
      local a = _list_1[_index_0]
      if not (used[a.id]) then
        n = n + 1
      end
    end
    return R.ok(n >= 1, 'auteurs sans livre')
  end)
  R.it("has at least one author with a particule", function()
    local n = 0
    local _list_0 = T.Auteurs
    for _index_0 = 1, #_list_0 do
      local a = _list_0[_index_0]
      if a.particule then
        n = n + 1
      end
    end
    return R.ok(n >= 1, 'auteurs avec particule')
  end)
  R.it("marks a duplicate book (same title, same author)", function()
    local seen = { }
    local n_dup = 0
    local _list_0 = T.Livres
    for _index_0 = 1, #_list_0 do
      local l = _list_0[_index_0]
      local key = tostring(l.auteur) .. "|" .. tostring(l.titre)
      if seen[key] then
        n_dup = n_dup + 1
      end
      seen[key] = true
    end
    R.ok(n_dup >= 1, 'doublon présent')
    R.eq(T.Livres[1].titre, T.Livres[2].titre, 'titre du couple')
    return R.eq(T.Livres[1].auteur, T.Livres[2].auteur, 'auteur du couple')
  end)
  R.it("links each book to two distinct keywords", function()
    local per = { }
    local _list_0 = T.LivresMotsCles
    for _index_0 = 1, #_list_0 do
      local r = _list_0[_index_0]
      per[r.livre] = per[r.livre] or { }
      R.nok(per[r.livre][r.mot_cle], "livre " .. tostring(r.livre) .. ": mot " .. tostring(r.mot_cle) .. " en double")
      per[r.livre][r.mot_cle] = true
    end
    local _list_1 = T.Livres
    for _index_0 = 1, #_list_1 do
      local l = _list_1[_index_0]
      local n = 0
      for _ in pairs((per[l.id] or { })) do
        n = n + 1
      end
      R.eq(n, 2, "livre " .. tostring(l.id) .. ": mots-clés")
    end
  end)
  R.it("keeps one open loan per exemplaire, none on a deleted copy", function()
    local n_open = check_loans(T.Emprunts, T.Exemplaires, 'k=1')
    return R.eq(n_open, 30, 'prêts non rendus')
  end)
  R.it("borrows only from ecole.eleves", function()
    local eleves = { }
    local _list_0 = ECOLE.eleves
    for _index_0 = 1, #_list_0 do
      local id = _list_0[_index_0]
      eleves[id] = true
    end
    local _list_1 = T.Emprunts
    for _index_0 = 1, #_list_1 do
      local r = _list_1[_index_0]
      R.ok(eleves[r.personne], "emprunt " .. tostring(r.id) .. ": personne " .. tostring(r.personne))
    end
  end)
  R.it("is deterministic for a given seed", function()
    local again = LIV.generate(RNG.new(2002), 1, ECOLE)
    return R.eq(json.encode(again), json.encode(OUT1))
  end)
  return R.it("scales the catalog with k = 2", function()
    local out2 = LIV.generate(RNG.new(2002), 2, ECOLE)
    local T2 = rows_of(out2)
    R.eq(#T2.Genres, 15, 'Genres')
    R.eq(#T2.Auteurs, 50, 'Auteurs')
    R.eq(#T2.MotsCles, 40, 'MotsCles')
    R.eq(#T2.Livres, 120, 'Livres')
    R.eq(#T2.LivresMotsCles, 240, 'LivresMotsCles')
    R.eq(#T2.Exemplaires, 200, 'Exemplaires')
    R.eq(#T2.Emprunts, 240, 'Emprunts')
    check_loans(T2.Emprunts, T2.Exemplaires, 'k=2')
    R.nok(has_empty(T2.Emprunts), 'Emprunts k=2')
    return R.nok(has_empty(T2.Exemplaires), 'Exemplaires k=2')
  end)
end)
