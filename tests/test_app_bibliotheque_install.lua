local R = require('tests.runner')
local json = require('json')
local B = require('tools.app_builder')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local triggers = require('core.triggers')
local auth = require('core.auth')
local data_r = require('resolvers.data_resolvers')
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local APP_ID = 'org.tgui.bibliotheque'
local MINUS = '\226\136\146'
local PKG = nil
local pkg
pkg = function()
  PKG = PKG or require('tools.bibliotheque_app').build()
  return PKG
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
local LIB_NAMES
do
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #EXPECTED_COUNTS do
    local e = EXPECTED_COUNTS[_index_0]
    _accum_0[_len_0] = e[1]
    _len_0 = _len_0 + 1
  end
  LIB_NAMES = _accum_0
end
local FORMULA_SPACES = {
  'Classes',
  'Livres',
  'Exemplaires',
  'Emprunts',
  'Personnes'
}
local space_id
space_id = function(name)
  local sp = spaces.get_space_by_name(name)
  return sp and sp.id
end
local raw_rows
raw_rows = function(name)
  local out = { }
  local sp = box.space["data_" .. tostring(name)]
  if not (sp) then
    return out
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(out, json.decode(t[2]))
  end
  return out
end
local by_id
by_id = function(rows)
  local m = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    if r.id ~= nil then
      m[r.id] = r
    end
  end
  return m
end
local _show
_show = function(v)
  if type(v) == 'string' then
    return json.encode(v)
  end
  if v == nil then
    return 'nil'
  end
  return tostring(v)
end
local is_formula_error
is_formula_error = function(v)
  return type(v) == 'string' and v:find('[ERROR', 1, true) ~= nil
end
local GENRES_ROWS = raw_rows('Genres')
local AUTEURS_ROWS = raw_rows('Auteurs')
local LIVRES_ROWS = raw_rows('Livres')
local EX_ROWS = raw_rows('Exemplaires')
local EMPRUNTS_ROWS = raw_rows('Emprunts')
local CE_ROWS = raw_rows('ClassesEleves')
local GENRES = by_id(GENRES_ROWS)
local AUTEURS = by_id(AUTEURS_ROWS)
local PERSONNES = by_id(raw_rows('Personnes'))
local CLASSES = by_id(raw_rows('Classes'))
local ANNEES_ROWS = raw_rows('Annee')
local ANNEES = by_id(ANNEES_ROWS)
local NIVEAUX = by_id(raw_rows('Niveaux'))
local LIVRES = by_id(LIVRES_ROWS)
local EX = by_id(EX_ROWS)
local COORD_ROWS = raw_rows('Coordonnees')
local PERS_COORD_ROWS = raw_rows('PersonnesCoordonnees')
local COORDS = by_id(COORD_ROWS)
local OPEN_LOANS
do
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #EMPRUNTS_ROWS do
    local e = EMPRUNTS_ROWS[_index_0]
    if (e.retour or '') == '' then
      _accum_0[_len_0] = e
      _len_0 = _len_0 + 1
    end
  end
  OPEN_LOANS = _accum_0
end
local OPEN_BY_EX = { }
for _index_0 = 1, #OPEN_LOANS do
  local e = OPEN_LOANS[_index_0]
  if e.exemplaire ~= nil then
    OPEN_BY_EX[e.exemplaire] = e
  end
end
local chemin_of
chemin_of = function(genre_id)
  local parts = { }
  local g = GENRES[genre_id]
  while g do
    table.insert(parts, 1, g.genre)
    g = g.parent and GENRES[g.parent]
  end
  return table.concat(parts, ' › ')
end
local niveau_of
niveau_of = function(genre_id)
  local n = 1
  local g = GENRES[genre_id]
  while g and g.parent do
    n = n + 1
    g = GENRES[g.parent]
  end
  return n
end
local nom_complet
nom_complet = function(a)
  local parts = { }
  if a.prenom then
    table.insert(parts, a.prenom)
  end
  if a.particule then
    table.insert(parts, a.particule)
  end
  table.insert(parts, a.nom)
  return table.concat(parts, ' ')
end
local n_ouvrages_of
n_ouvrages_of = function(author_id)
  local n = 0
  for _index_0 = 1, #LIVRES_ROWS do
    local l = LIVRES_ROWS[_index_0]
    if l.auteur == author_id then
      n = n + 1
    end
  end
  return n
end
local n_exemplaires_of
n_exemplaires_of = function(livre_id)
  local n = 0
  for _index_0 = 1, #EX_ROWS do
    local ex = EX_ROWS[_index_0]
    if ex.livre == livre_id and (ex.suppression or '') == '' then
      n = n + 1
    end
  end
  return n
end
local doublon_of
doublon_of = function(l)
  for _index_0 = 1, #LIVRES_ROWS do
    local o = LIVRES_ROWS[_index_0]
    if o.id ~= l.id and o.titre == l.titre and o.auteur == l.auteur then
      return true
    end
  end
  return false
end
local livre_descriptif
livre_descriptif = function(l)
  local a = l.auteur and AUTEURS[l.auteur]
  local name = a and nom_complet(a) or '?'
  return tostring(l.titre) .. " (" .. tostring(name) .. ")"
end
local ex_descriptif
ex_descriptif = function(ex)
  local l = ex.livre and LIVRES[ex.livre]
  local base = l and livre_descriptif(l) or '?'
  return base .. (ex.cote and (" " .. tostring(MINUS) .. " " .. ex.cote) or '')
end
local emprunteur_of
emprunteur_of = function(ex_id)
  local e = OPEN_BY_EX[ex_id]
  if not (e) then
    return nil
  end
  local p = PERSONNES[e.personne]
  if not (p) then
    return nil
  end
  return tostring(p.nom) .. " " .. tostring(p.prenom or '')
end
local emprunts_en_cours_of
emprunts_en_cours_of = function(person_id)
  local n = 0
  for _index_0 = 1, #OPEN_LOANS do
    local e = OPEN_LOANS[_index_0]
    if e.personne == person_id then
      n = n + 1
    end
  end
  return n
end
local classe_actuelle_of
classe_actuelle_of = function(person_id)
  for _index_0 = 1, #CE_ROWS do
    local ce = CE_ROWS[_index_0]
    if ce.eleve == person_id and (ce.depart or '') == '' then
      local c = CLASSES[ce.classe]
      local a = c and ANNEES[c.annee]
      if a and a.en_cours then
        return ce.classe
      end
    end
  end
  return nil
end
local effectif_of
effectif_of = function(class_id)
  local n = 0
  for _index_0 = 1, #CE_ROWS do
    local ce = CE_ROWS[_index_0]
    if ce.classe == class_id and (ce.depart or '') == '' then
      n = n + 1
    end
  end
  return n
end
local classes_descriptif
classes_descriptif = function(c)
  local n = NIVEAUX[c.niveau]
  return tostring(n and n.abrege or '') .. tostring(c.precision or '')
end
local classes_descriptif_complet
classes_descriptif_complet = function(c)
  local a = c and ANNEES[c.annee]
  local n = a and tonumber(a.debut:sub(1, 4))
  return tostring(n or '?') .. " " .. tostring(classes_descriptif(c))
end
local annee_label
annee_label = function(a)
  local n = tonumber(a.debut:sub(1, 4))
  return tostring(n) .. " - " .. tostring(n + 1)
end
local personne_descriptif
personne_descriptif = function(p)
  local s = string.upper(p.nom)
  if p.particule then
    s = tostring(s) .. " (" .. tostring(p.particule) .. ")"
  end
  s = tostring(s) .. " " .. tostring(p.prenom or '')
  if p.precision then
    s = tostring(s) .. " " .. tostring(p.precision)
  end
  return s
end
local niveau_descriptif
niveau_descriptif = function(n)
  return string.format("%02d " .. tostring(MINUS) .. " %s", n.niveau, n.abrege)
end
local ce_annee
ce_annee = function(ce)
  local c = CLASSES[ce.classe]
  return c and c.annee
end
local ce_annee_en_cours
ce_annee_en_cours = function(ce)
  local c = CLASSES[ce.classe]
  local a = c and ANNEES[c.annee]
  if not (a and a.en_cours) then
    return false
  end
  if ce.depart then
    return false
  end
  return true
end
local emprunt_annee_en_cours
emprunt_annee_en_cours = function(e)
  for _index_0 = 1, #ANNEES_ROWS do
    local a = ANNEES_ROWS[_index_0]
    if a.en_cours and a.debut <= e.emprunt and e.emprunt <= a.fin then
      return true
    end
  end
  return false
end
local ITEMS = { }
local items_of
items_of = function(name)
  if not (ITEMS[name]) then
    local sid = space_id(name)
    if sid then
      ITEMS[name] = data_r.Query.records(nil, {
        spaceId = sid,
        limit = 1000
      }, CTX)
    else
      ITEMS[name] = {
        items = { }
      }
    end
  end
  return ITEMS[name].items
end
local proxy_of
proxy_of = function(name, field, value)
  local _list_0 = items_of(name)
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.raw[field] == value then
      return it.proxy
    end
  end
  return nil
end
local check_field
check_field = function(space_name, field_name, expected_fn)
  local rows = items_of(space_name)
  if #rows == 0 then
    R.ok(false, tostring(space_name) .. ": aucune ligne — espace non installé ?")
    return 
  end
  local n = 0
  local bad = { }
  for _index_0 = 1, #rows do
    local it = rows[_index_0]
    local exp = expected_fn(it.raw)
    local got = it.proxy[field_name]
    if not (exp == got) then
      n = n + 1
      if #bad < 3 then
        table.insert(bad, "id " .. tostring(_show(it.raw.id)) .. ": attendu " .. tostring(_show(exp)) .. ", obtenu " .. tostring(_show(got)))
      end
    end
  end
  return R.eq(n, 0, tostring(space_name) .. "." .. tostring(field_name) .. " — " .. tostring(n) .. " écart(s) " .. tostring(table.concat(bad, ' | ')))
end
local check_relation_label
check_relation_label = function(space_name, field_name, expected_fn)
  local rows = items_of(space_name)
  R.ok((#rows >= 20), tostring(space_name) .. ": " .. tostring(#rows) .. " ligne(s) (< 20)")
  local empty, errs, mism = 0, 0, 0
  local bad = { }
  for _index_0 = 1, #rows do
    local it = rows[_index_0]
    local got = it.proxy[field_name]
    if got == nil or got == '' then
      empty = empty + 1
    elseif is_formula_error(got) then
      errs = errs + 1
    else
      local exp = expected_fn(it.raw)
      if exp ~= got then
        mism = mism + 1
        if #bad < 3 then
          table.insert(bad, "id " .. tostring(_show(it.raw.id)) .. ": attendu " .. tostring(_show(exp)) .. ", obtenu " .. tostring(_show(got)))
        end
      end
    end
  end
  R.eq(empty, 0, tostring(space_name) .. "." .. tostring(field_name) .. ": " .. tostring(empty) .. " valeur(s) vide(s)")
  R.eq(errs, 0, tostring(space_name) .. "." .. tostring(field_name) .. ": " .. tostring(errs) .. " erreur(s) de formule")
  return R.eq(mism, 0, tostring(space_name) .. "." .. tostring(field_name) .. ": " .. tostring(mism) .. " écart(s) " .. tostring(table.concat(bad, ' | ')))
end
local assert_proxy
assert_proxy = function(space_name, key_field, key_value, field_name, expected, label)
  local p = proxy_of(space_name, key_field, key_value)
  if not (p) then
    R.ok(false, tostring(label) .. ": ligne " .. tostring(_show(key_value)) .. " absente de " .. tostring(space_name))
    return 
  end
  return R.eq(p[field_name], expected, label)
end
local FK_BY_SPACE = nil
local fk_by_space
fk_by_space = function()
  if FK_BY_SPACE then
    return FK_BY_SPACE
  end
  FK_BY_SPACE = { }
  local _list_0 = pkg().items
  for _index_0 = 1, #_list_0 do
    local item = _list_0[_index_0]
    if item.type == 'relation' then
      local c = item.content
      FK_BY_SPACE[c.fromSpace] = FK_BY_SPACE[c.fromSpace] or { }
      table.insert(FK_BY_SPACE[c.fromSpace], c.fromField)
    end
  end
  return FK_BY_SPACE
end
local warm_fk
warm_fk = function()
  local touched = 0
  for _index_0 = 1, #LIB_NAMES do
    local name = LIB_NAMES[_index_0]
    local rows = items_of(name)
    local _list_0 = (fk_by_space()[name] or { })
    for _index_1 = 1, #_list_0 do
      local f = _list_0[_index_1]
      for _index_2 = 1, #rows do
        local it = rows[_index_2]
        if type(it.proxy[f]) == 'table' then
          touched = touched + 1
        end
      end
    end
  end
  return touched
end
local stored_computed
stored_computed = function(space_name, names)
  local bad = { }
  local sp = box.space["data_" .. tostring(space_name)]
  if not (sp) then
    return {
      "espace data_" .. tostring(space_name) .. " absent"
    }
  end
  local _list_0 = sp:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local row = json.decode(t[2])
    for _index_1 = 1, #names do
      local f = names[_index_1]
      if row[f] ~= nil then
        table.insert(bad, tostring(row.id) .. "." .. tostring(f))
      end
    end
  end
  return bad
end
local formula_field_names
formula_field_names = function()
  local out = { }
  local _list_0 = pkg().items
  for _index_0 = 1, #_list_0 do
    local _continue_0 = false
    repeat
      local item = _list_0[_index_0]
      if not (item.type == 'field') then
        _continue_0 = true
        break
      end
      if not (item.content.formula and item.content.formula ~= '') then
        _continue_0 = true
        break
      end
      local sp_name, f_name = item.key:match('^field:(.+)%.(.+)$')
      if sp_name then
        out[sp_name] = out[sp_name] or { }
        table.insert(out[sp_name], f_name)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return out
end
local check_formulas
check_formulas = function()
  local checked = 0
  for _index_0 = 1, #LIB_NAMES do
    local _continue_0 = false
    repeat
      local name = LIB_NAMES[_index_0]
      local sp = spaces.get_space_by_name(name)
      R.ok(sp, "espace " .. tostring(name) .. " non installé")
      if not (sp) then
        _continue_0 = true
        break
      end
      local _list_0 = spaces.list_fields(sp.id)
      for _index_1 = 1, #_list_0 do
        local _continue_1 = false
        repeat
          local f = _list_0[_index_1]
          if not (f.formula and f.formula ~= '') then
            _continue_1 = true
            break
          end
          local fn = triggers.compile_formula(f.formula, tostring(name) .. "." .. tostring(f.name), f.language)
          R.ok((type(fn) == 'function'), "formule non compilable " .. tostring(name) .. "." .. tostring(f.name))
          checked = checked + 1
          _continue_1 = true
        until true
        if not _continue_1 then
          break
        end
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return checked
end
R.describe("bibliotheque install — état livré par les fixtures", function()
  R.it("installs every space with the exact seed row counts", function()
    for _index_0 = 1, #EXPECTED_COUNTS do
      local _continue_0 = false
      repeat
        local e = EXPECTED_COUNTS[_index_0]
        local sp = box.space["data_" .. tostring(e[1])]
        if not (sp) then
          R.ok(false, "espace data_" .. tostring(e[1]) .. " absent")
          _continue_0 = true
          break
        end
        R.eq(sp:len(), e[2], e[1])
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  R.it("keeps every relation source value present in the target space", function()
    local _list_0 = pkg().items
    for _index_0 = 1, #_list_0 do
      local _continue_0 = false
      repeat
        local item = _list_0[_index_0]
        if not (item.type == 'relation') then
          _continue_0 = true
          break
        end
        local c = item.content
        local tgt = { }
        local _list_1 = raw_rows(c.toSpace)
        for _index_1 = 1, #_list_1 do
          local r = _list_1[_index_1]
          if r[c.toField] ~= nil then
            tgt[tostring(r[c.toField])] = true
          end
        end
        local n = 0
        local sample = { }
        local _list_2 = raw_rows(c.fromSpace)
        for _index_1 = 1, #_list_2 do
          local r = _list_2[_index_1]
          local v = r[c.fromField]
          if v ~= nil and v ~= '' and not tgt[tostring(v)] then
            n = n + 1
            if #sample < 3 then
              table.insert(sample, tostring(v))
            end
          end
        end
        R.eq(n, 0, tostring(item.key) .. ": " .. tostring(n) .. " valeur(s) absente(s) de " .. tostring(c.toSpace) .. "." .. tostring(c.toField) .. " " .. tostring(table.concat(sample, ', ')))
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  return R.it("stores no computed field in Classes, Livres, Exemplaires, Emprunts, Personnes", function()
    local names_by_space = formula_field_names()
    for _index_0 = 1, #FORMULA_SPACES do
      local sp_name = FORMULA_SPACES[_index_0]
      local bad = stored_computed(sp_name, names_by_space[sp_name] or { })
      R.eq(#bad, 0, tostring(sp_name) .. ": champs calculés stockés " .. tostring(table.concat(bad, ' | ')))
    end
  end)
end)
R.describe("bibliotheque install — formules (data_r.Query.records)", function()
  R.it("warms the foreign-key metadata caches", function()
    return R.ok((warm_fk() > 0), 'aucun champ de clé étrangère résolu')
  end)
  R.it("compiles every formula of the installed spaces (anciens tests T3/T4)", function()
    return R.ok((check_formulas() > 0), 'aucune formule dans les espaces installés')
  end)
  R.it("T3 — ecole formulas recomputed from the installed seed", function()
    check_field('Annee', 'annee', function(a)
      return annee_label(a)
    end)
    check_field('Niveaux', 'descriptif', function(n)
      return niveau_descriptif(n)
    end)
    check_field('Personnes', 'descriptif', function(p)
      return personne_descriptif(p)
    end)
    check_field('Personnes', 'classe_actuelle', function(p)
      return classe_actuelle_of(p.id)
    end)
    check_field('Personnes', 'emprunts_en_cours', function(p)
      return emprunts_en_cours_of(p.id)
    end)
    check_field('Classes', 'effectif', function(c)
      return effectif_of(c.id)
    end)
    check_field('Classes', 'descriptif', function(c)
      return classes_descriptif(c)
    end)
    check_field('ClassesEleves', 'annee', function(ce)
      return ce_annee(ce)
    end)
    return check_field('ClassesEleves', 'annee_en_cours', function(ce)
      return ce_annee_en_cours(ce)
    end)
  end)
  R.it("T3 — literal school values", function()
    assert_proxy('Annee', 'id', 3, 'annee', '2026 - 2027', 'Annee.annee de l’année en cours')
    assert_proxy('Niveaux', 'id', 1, 'descriptif', "01 " .. tostring(MINUS) .. " CP", 'Niveaux.descriptif du CP')
    assert_proxy('Classes', 'id', 6, 'effectif', 12, 'Classes.effectif de la classe 6')
    return assert_proxy('Personnes', 'id', 1, 'classe_actuelle', nil, 'classe_actuelle d’un adulte (cas 4)')
  end)
  R.it("T3 — a level-1 student has classe_actuelle = 6", function()
    local sid = nil
    for _index_0 = 1, #CE_ROWS do
      local ce = CE_ROWS[_index_0]
      local c = CLASSES[ce.classe]
      local a = c and ANNEES[c.annee]
      if c and a and a.en_cours and not ce.depart and c.niveau == 1 then
        sid = ce.eleve
        break
      end
    end
    R.ok(sid, 'aucun élève de niveau 1 dans la classe de l’année en cours')
    if sid then
      return assert_proxy('Personnes', 'id', sid, 'classe_actuelle', 6, 'classe_actuelle d’un élève de niveau 1')
    end
  end)
  R.it("T4 — library formulas recomputed from the installed seed", function()
    check_field('Genres', 'niveau', function(g)
      return niveau_of(g.id)
    end)
    check_field('Genres', 'chemin', function(g)
      return chemin_of(g.id)
    end)
    check_field('Auteurs', 'nom_complet', function(a)
      return nom_complet(a)
    end)
    check_field('Auteurs', 'n_ouvrages', function(a)
      return n_ouvrages_of(a.id)
    end)
    check_field('Livres', 'n_exemplaires', function(l)
      return n_exemplaires_of(l.id)
    end)
    check_field('Livres', 'doublon', function(l)
      return doublon_of(l)
    end)
    check_field('Livres', 'descriptif', function(l)
      return livre_descriptif(l)
    end)
    return check_field('Exemplaires', 'emprunteur', function(e)
      return emprunteur_of(e.id)
    end)
  end)
  R.it("T4 — literal library values", function()
    assert_proxy('Genres', 'id', 3, 'chemin', 'Fiction › Roman › Policier', 'Genres.chemin du genre 3')
    assert_proxy('Genres', 'id', 1, 'niveau', 1, 'Genres.niveau du genre racine')
    assert_proxy('Genres', 'id', 1, 'chemin', 'Fiction', 'Genres.chemin du genre racine')
    local total, errs, zeros = 0, 0, 0
    local _list_0 = items_of('Auteurs')
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      local v = it.proxy.n_ouvrages
      if type(v) == 'number' then
        total = total + v
      elseif v ~= nil then
        errs = errs + 1
      end
      if v == 0 then
        zeros = zeros + 1
      end
    end
    R.eq(total, 60, "somme de Auteurs.n_ouvrages (" .. tostring(errs) .. " valeur(s) en erreur de formule)")
    R.ok(zeros > 0, "au moins un auteur sans livre (cas 3) (" .. tostring(errs) .. " erreur(s))")
    local dbl_t, dbl_f, zero_ex, dbl_err = 0, 0, 0, 0
    local _list_1 = items_of('Livres')
    for _index_0 = 1, #_list_1 do
      local it = _list_1[_index_0]
      local d = it.proxy.doublon
      if d == true then
        dbl_t = dbl_t + 1
      elseif d == false then
        dbl_f = dbl_f + 1
      else
        dbl_err = dbl_err + 1
      end
      if (it.proxy.n_exemplaires or 0) == 0 then
        zero_ex = zero_ex + 1
      end
    end
    R.ok(dbl_t > 0, "au moins un doublon vrai (" .. tostring(dbl_err) .. " valeur(s) en erreur)")
    R.ok(dbl_f > 0, "au moins un doublon faux (" .. tostring(dbl_err) .. " valeur(s) en erreur)")
    return R.ok(zero_ex > 0, 'au moins un livre sans exemplaire (cas 3)')
  end)
  R.it("T5 — contact types, N-N shared coordonnée, notNull refusal", function()
    local types = { }
    local _list_0 = raw_rows('TypesCoordonnees')
    for _index_0 = 1, #_list_0 do
      local r = _list_0[_index_0]
      if r.type ~= nil then
        types[r.type] = true
      end
    end
    local _list_1 = {
      'tel',
      'courriel',
      'adresse'
    }
    for _index_0 = 1, #_list_1 do
      local t = _list_1[_index_0]
      R.ok(types[t], "type de coordonnée '" .. tostring(t) .. "'")
    end
    local links = raw_rows('PersonnesCoordonnees')
    local counts = { }
    for _index_0 = 1, #links do
      local l = links[_index_0]
      if l.coordonnee ~= nil then
        counts[l.coordonnee] = (counts[l.coordonnee] or 0) + 1
      end
    end
    local shared = { }
    for cid, n in pairs(counts) do
      if n >= 2 then
        table.insert(shared, cid)
      end
    end
    R.ok(#shared > 0, 'aucune coordonnée partagée par deux personnes (liaison N-N)')
    if #shared > 0 then
      local seen = { }
      local distinct = 0
      for _index_0 = 1, #links do
        local l = links[_index_0]
        if l.coordonnee == shared[1] and not seen[l.personne] then
          seen[l.personne] = true
          distinct = distinct + 1
        end
      end
      R.ok(distinct >= 2, 'la coordonnée partagée lie deux personnes distinctes')
    end
    local coord_sp = box.space["data_Coordonnees"]
    if not (coord_sp) then
      R.ok(false, 'espace data_Coordonnees absent')
      return 
    end
    local nb_before = coord_sp:len()
    local insert_without_valeur
    insert_without_valeur = function()
      return data_r.Mutation.insertRecord({ }, {
        spaceId = space_id('Coordonnees'),
        data = {
          type_coordonnee = 1
        }
      }, CTX)
    end
    R.raises(insert_without_valeur, 'not_null', 'valeur required')
    return R.eq(coord_sp:len(), nb_before, 'aucune ligne écrite')
  end)
  R.it("T9b — Emprunts.annee_en_cours is true for exactly 30 emprunts", function()
    check_field('Emprunts', 'annee_en_cours', function(e)
      return emprunt_annee_en_cours(e)
    end)
    local n = 0
    local _list_0 = items_of('Emprunts')
    for _index_0 = 1, #_list_0 do
      local it = _list_0[_index_0]
      if it.proxy.annee_en_cours then
        n = n + 1
      end
    end
    R.eq(n, 30, 'Emprunts.annee_en_cours vrai')
    local open, open_err = 0, 0
    local _list_1 = items_of('Exemplaires')
    for _index_0 = 1, #_list_1 do
      local it = _list_1[_index_0]
      local v = it.proxy.emprunteur
      if type(v) == 'string' and not is_formula_error(v) then
        open = open + 1
      elseif v ~= nil then
        open_err = open_err + 1
      end
    end
    R.eq(open, 30, "Exemplaires.emprunteur non vide (" .. tostring(open_err) .. " valeur(s) en erreur de formule)")
    local total, errs = 0, 0
    local _list_2 = items_of('Personnes')
    for _index_0 = 1, #_list_2 do
      local it = _list_2[_index_0]
      local v = it.proxy.emprunts_en_cours
      if type(v) == 'number' then
        total = total + v
      elseif v ~= nil then
        errs = errs + 1
      end
    end
    return R.eq(total, 30, "somme de Personnes.emprunts_en_cours (" .. tostring(errs) .. " valeur(s) en erreur de formule)")
  end)
  R.it("T16a — relation labels match the raw seed", function()
    check_relation_label('Emprunts', 'lecteur', function(e)
      return personne_descriptif(PERSONNES[e.personne])
    end)
    check_relation_label('Emprunts', 'ouvrage', function(e)
      return ex_descriptif(EX[e.exemplaire])
    end)
    check_relation_label('Exemplaires', 'livre_titre', function(e)
      return LIVRES[e.livre].titre
    end)
    check_relation_label('Livres', 'auteur_nom', function(l)
      return nom_complet(AUTEURS[l.auteur])
    end)
    check_relation_label('Livres', 'genre_nom', function(l)
      return chemin_of(l.genre)
    end)
    check_relation_label('ClassesEleves', 'eleve_nom', function(ce)
      return personne_descriptif(PERSONNES[ce.eleve])
    end)
    check_relation_label('ClassesEleves', 'classe_nom', function(ce)
      return classes_descriptif_complet(CLASSES[ce.classe])
    end)
    check_relation_label('PersonnesCoordonnees', 'personne_nom', function(pc)
      return personne_descriptif(PERSONNES[pc.personne])
    end)
    return check_relation_label('PersonnesCoordonnees', 'coordonnee_valeur', function(pc)
      return COORDS[pc.coordonnee].valeur
    end)
  end)
  return R.it("T16a — the package gained the nine label formulas", function()
    local names = formula_field_names()
    local total = 0
    for _, lst in pairs(names) do
      total = total + #lst
    end
    R.eq(total, 40, "nombre total de champs calculés (29 avant T16a + 9 T16a + 2 T16b)")
    local wanted = {
      {
        'Emprunts',
        'lecteur'
      },
      {
        'Emprunts',
        'ouvrage'
      },
      {
        'Exemplaires',
        'livre_titre'
      },
      {
        'Livres',
        'auteur_nom'
      },
      {
        'Livres',
        'genre_nom'
      },
      {
        'ClassesEleves',
        'eleve_nom'
      },
      {
        'ClassesEleves',
        'classe_nom'
      },
      {
        'PersonnesCoordonnees',
        'personne_nom'
      },
      {
        'PersonnesCoordonnees',
        'coordonnee_valeur'
      }
    }
    for _index_0 = 1, #wanted do
      local w = wanted[_index_0]
      local found = false
      local _list_0 = (names[w[1]] or { })
      for _index_1 = 1, #_list_0 do
        local f = _list_0[_index_1]
        if f == w[2] then
          found = true
        end
      end
      R.ok(found, "champ calculé manquant " .. tostring(w[1]) .. "." .. tostring(w[2]))
    end
  end)
end)
return R.describe("bibliotheque install — contrat applicatif", function()
  R.it("apply_update of the same package creates and updates nothing", function()
    local report = apply.apply_update(pkg(), { }, { })
    R.ok(report.ok, "apply_update: " .. tostring(report.error))
    R.is_nil(report.reinit_error, 'reinit_schema')
    R.eq(#(report.created or { }), 0, 'created')
    return R.eq(#(report.updated or { }), 0, 'updated')
  end)
  R.it("insertRecord gets an id above every seed id, then restores the row counts", function()
    local specs = {
      {
        'Livres',
        {
          titre = 'T9b',
          auteur = 1,
          genre = 1
        }
      },
      {
        'Personnes',
        {
          nom = 'T9b',
          prenom = 'X'
        }
      },
      {
        'Emprunts',
        {
          personne = 13,
          exemplaire = 1,
          emprunt = '2026-10-08'
        }
      }
    }
    for _index_0 = 1, #specs do
      local _continue_0 = false
      repeat
        local spec = specs[_index_0]
        local name, data = spec[1], spec[2]
        local sp = box.space["data_" .. tostring(name)]
        if not (sp) then
          R.ok(false, "espace data_" .. tostring(name) .. " absent")
          _continue_0 = true
          break
        end
        local count_before = sp:len()
        local max_before = 0
        local _list_0 = raw_rows(name)
        for _index_1 = 1, #_list_0 do
          local r = _list_0[_index_1]
          if type(r.id) == 'number' and r.id > max_before then
            max_before = r.id
          end
        end
        local rec = data_r.Mutation.insertRecord({ }, {
          spaceId = space_id(name),
          data = data
        }, CTX)
        local new_id = json.decode(rec.data).id
        if type(new_id) ~= 'number' then
          R.ok(false, tostring(name) .. ": id attribué " .. tostring(_show(new_id)) .. " (séquence absente ?)")
        else
          R.ok(new_id > max_before, tostring(name) .. ": id " .. tostring(_show(new_id)) .. " > seed max " .. tostring(max_before))
        end
        data_r.Mutation.deleteRecord({ }, {
          spaceId = space_id(name),
          id = rec.id
        }, CTX)
        R.eq(sp:len(), count_before, tostring(name) .. ": comptes rétablis")
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  return R.it("emit(build()) is byte-identical on two calls", function()
    local a = B.emit(pkg())
    local b = B.emit(require('tools.bibliotheque_app').build())
    return R.ok((a == b), "emit(build()) diffère (" .. tostring(#a) .. " vs " .. tostring(#b) .. " octets)")
  end)
end)
