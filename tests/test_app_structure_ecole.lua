local R = require('tests.runner')
local B = require('tools.app_builder')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local triggers = require('core.triggers')
local auth = require('core.auth')
local data_r = require('resolvers.data_resolvers')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local APP_ID = "org.test.ecole_" .. tostring(SUFFIX)
local DIR = '/app/backend/apps/bibliotheque'
local ECOLE = {
  'Titres',
  'Sections',
  'Annee',
  'Niveaux',
  'Prefectures',
  'Classes',
  'Personnes',
  'ClassesEleves'
}
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local FIX = { }
local PKG = nil
local wanted = { }
for _index_0 = 1, #ECOLE do
  local n = ECOLE[_index_0]
  wanted[n] = true
end
local clean_app_rows
clean_app_rows = function(app_id)
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    box.space._tdb_app_items:delete({
      t[1],
      t[2]
    })
  end
  return box.space._tdb_apps:delete(app_id)
end
local drop_relations
drop_relations = function(name)
  local sp = spaces.get_space_by_name(name)
  if not (sp) then
    return 
  end
  local _list_0 = box.space._tdb_relations.index.by_from:select({
    sp.id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    box.space._tdb_relations:delete(t[1])
  end
  local _list_1 = box.space._tdb_relations.index.by_to:select({
    sp.id
  })
  for _index_0 = 1, #_list_1 do
    local t = _list_1[_index_0]
    box.space._tdb_relations:delete(t[1])
  end
end
local insert_row
insert_row = function(space_name, data)
  local sp = spaces.get_space_by_name(space_name)
  local r = data_r.Mutation.insertRecord({ }, {
    spaceId = sp.id,
    data = data
  }, CTX)
  return json.decode(r.data).id
end
local records
records = function(space_name)
  local sp = spaces.get_space_by_name(space_name)
  if not (sp) then
    return { }
  end
  local res = data_r.Query.records(nil, {
    spaceId = sp.id,
    limit = 1000
  }, CTX)
  return res.items
end
local row
row = function(space_name, field, value)
  local items = records(space_name)
  for _index_0 = 1, #items do
    local it = items[_index_0]
    if it.raw[field] == value then
      return it.proxy
    end
  end
  return nil
end
local check_formulas
check_formulas = function()
  for _index_0 = 1, #ECOLE do
    local _continue_0 = false
    repeat
      local n = ECOLE[_index_0]
      local sp = spaces.get_space_by_name(n)
      if not (sp) then
        _continue_0 = true
        break
      end
      local _list_0 = spaces.list_fields(sp.id)
      for _index_1 = 1, #_list_0 do
        local _continue_1 = false
        repeat
          local f = _list_0[_index_1]
          if not (f.formula ~= '') then
            _continue_1 = true
            break
          end
          local fn = triggers.compile_formula(f.formula, tostring(n) .. "." .. tostring(f.name), f.language)
          R.ok((type(fn) == 'function'), "formule non compilable " .. tostring(n) .. "." .. tostring(f.name))
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
end
local warm_fk
warm_fk = function(space_name, depth)
  if depth < 0 then
    return 0
  end
  local sp = spaces.get_space_by_name(space_name)
  if not (sp) then
    return 0
  end
  local fk_map = triggers.build_fk_def_map(sp.id)
  local res = data_r.Query.records(nil, {
    spaceId = sp.id,
    limit = 1000
  }, CTX)
  local touched = 0
  local _list_0 = res.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    for name, def in pairs(fk_map) do
      local v = it.proxy[name]
      if type(v) == 'table' then
        touched = touched + 1
        touched = touched + warm_fk(def.toSpaceName, depth - 1)
      end
    end
  end
  return touched
end
return R.describe("app structure — ecole", function()
  R.it("installs the eight school spaces", function()
    local structure = B.load_structure(DIR)
    local loaded = { }
    local _list_0 = structure.spaces
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      loaded[s.name] = true
    end
    for _index_0 = 1, #ECOLE do
      local n = ECOLE[_index_0]
      R.ok(loaded[n], "espace absent de backend/apps/bibliotheque: " .. tostring(n))
    end
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_1 = structure.spaces
      for _index_0 = 1, #_list_1 do
        local s = _list_1[_index_0]
        if wanted[s.name] then
          _accum_0[_len_0] = s
          _len_0 = _len_0 + 1
        end
      end
      structure.spaces = _accum_0
    end
    structure.app.id = APP_ID
    structure.app.name = "Ecole test " .. tostring(SUFFIX)
    PKG = B.expand(structure)
    local report = apply.apply_update(PKG, { }, { })
    R.ok(report.ok, "apply_update: " .. tostring(report.error))
    R.is_nil(report.reinit_error, 'reinit_schema')
    for _index_0 = 1, #ECOLE do
      local n = ECOLE[_index_0]
      R.ok(spaces.get_space_by_name(n), "espace non installé: " .. tostring(n))
    end
  end)
  R.it("compiles every formula", function()
    return check_formulas()
  end)
  R.it("inserts the school fixture rows", function()
    FIX.sec = insert_row('Sections', {
      section = 'Primaire',
      abregee = 'PRIM'
    })
    FIX.an1 = insert_row('Annee', {
      debut = '2025-09-01',
      fin = '2026-06-30',
      en_cours = false,
      section = FIX.sec
    })
    FIX.an2 = insert_row('Annee', {
      debut = '2026-09-01',
      fin = '2027-06-30',
      en_cours = true,
      section = FIX.sec
    })
    FIX.niv = insert_row('Niveaux', {
      niveau = 1,
      classe = 'CP',
      abrege = 'CP',
      generique = 'CP'
    })
    FIX.cl1 = insert_row('Classes', {
      niveau = FIX.niv,
      annee = FIX.an1
    })
    FIX.cl2 = insert_row('Classes', {
      niveau = FIX.niv,
      annee = FIX.an2
    })
    FIX.jeanne = insert_row('Personnes', {
      nom = 'Dupont',
      particule = 'de',
      prenom = 'Jeanne'
    })
    FIX.luc = insert_row('Personnes', {
      nom = 'Martin',
      prenom = 'Luc'
    })
    FIX.ce_j = insert_row('ClassesEleves', {
      classe = FIX.cl2,
      eleve = FIX.jeanne,
      entree = '2026-09-01'
    })
    FIX.ce_l = insert_row('ClassesEleves', {
      classe = FIX.cl1,
      eleve = FIX.luc,
      entree = '2025-09-01',
      depart = '2026-06-30',
      redoublement = false
    })
    return R.ok(FIX.ce_l, 'ClassesEleves de Luc')
  end)
  R.it("warms the FK metadata caches", function()
    local touched = 0
    for _index_0 = 1, #ECOLE do
      local n = ECOLE[_index_0]
      touched = touched + warm_fk(n, 3)
    end
    return R.ok(touched > 0, 'aucun champ de clé étrangère résolu')
  end)
  R.it("computes the formula columns", function()
    local an2 = row('Annee', 'id', FIX.an2)
    R.ok(an2, 'Annee 2')
    R.eq(an2.annee, '2026 - 2027', 'Annee.annee')
    local niv = row('Niveaux', 'id', FIX.niv)
    R.ok(niv, 'Niveaux 1')
    R.eq(niv.descriptif, '01 − CP', 'Niveaux.descriptif')
    local j = row('Personnes', 'id', FIX.jeanne)
    R.ok(j, 'Jeanne')
    R.eq(j.descriptif, 'DUPONT (de) Jeanne', 'Personnes.descriptif de Jeanne')
    R.eq(j.classe_actuelle, FIX.cl2, 'classe_actuelle de Jeanne')
    R.eq(j.emprunts_en_cours, 0, 'emprunts_en_cours de Jeanne')
    local l = row('Personnes', 'id', FIX.luc)
    R.ok(l, 'Luc')
    R.is_nil(l.classe_actuelle, 'classe_actuelle de Luc')
    R.eq(l.emprunts_en_cours, 0, 'emprunts_en_cours de Luc')
    local c1 = row('Classes', 'id', FIX.cl1)
    local c2 = row('Classes', 'id', FIX.cl2)
    R.ok(c1 and c2, 'classes')
    R.eq(c1.descriptif, 'CP', 'Classes.descriptif')
    R.eq(c2.effectif, 1, 'effectif de la classe 2')
    R.eq(c1.effectif, 0, 'effectif de la classe 1')
    local ce_j = row('ClassesEleves', 'id', FIX.ce_j)
    local ce_l = row('ClassesEleves', 'id', FIX.ce_l)
    R.ok(ce_j and ce_l, 'liaisons ClassesEleves')
    R.eq(ce_j.annee, FIX.an2, 'ClassesEleves.annee de Jeanne')
    R.eq(ce_j.annee_en_cours, true, 'annee_en_cours de Jeanne')
    return R.eq(ce_l.annee_en_cours, false, 'annee_en_cours de Luc')
  end)
  return R.it("cleans up", function()
    clean_app_rows(APP_ID)
    for _index_0 = 1, #ECOLE do
      local n = ECOLE[_index_0]
      drop_relations(n)
      spaces.delete_user_space(n)
    end
    return R.is_nil(spaces.get_space_by_name('Personnes'))
  end)
end)
