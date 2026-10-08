local R = require('tests.runner')
local yaml = require('yaml')
local fio = require('fio')
local json = require('json')
local B = require('tools.app_builder')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local triggers = require('core.triggers')
local auth = require('core.auth')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local APP_ID = "org.test.biblio_" .. tostring(SUFFIX)
local SP_PERS = 'Personnes'
local STRUCT_PATH = '/app/backend/apps/bibliotheque/structure/bibliotheque.yaml'
local OWN_SPACES = {
  'Genres',
  'Auteurs',
  'MotsCles',
  'Livres',
  'LivresMotsCles',
  'Exemplaires',
  'Emprunts'
}
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local FIX = { }
local PKG = nil
local read_yaml
read_yaml = function(path)
  local fh = fio.open(path, {
    'O_RDONLY'
  })
  if not (fh) then
    error("cannot open " .. tostring(path))
  end
  local text = fh:read()
  fh:close()
  return yaml.decode(text)
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
  for _index_0 = 1, #OWN_SPACES do
    local _continue_0 = false
    repeat
      local n = OWN_SPACES[_index_0]
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
return R.describe("app structure — bibliotheque", function()
  R.it("installs the seven library spaces", function()
    local part = read_yaml(STRUCT_PATH)
    local wanted = { }
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      wanted[n] = true
    end
    local declared = { }
    local _list_0 = part.spaces
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      declared[sp.name] = true
    end
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      R.ok(declared[n], "declares " .. tostring(n))
    end
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      if spaces.get_space_by_name(n) then
        drop_relations(n)
        spaces.delete_user_space(n)
      end
    end
    local pers = spaces.create_user_space(SP_PERS, 'T4 minimal persons')
    spaces.add_field(pers.id, 'id', 'Sequence', true, 'Identifiant')
    spaces.add_field(pers.id, 'nom', 'String', false, '')
    spaces.add_field(pers.id, 'prenom', 'String', false, '')
    local _list_1 = part.spaces
    for _index_0 = 1, #_list_1 do
      local sp = _list_1[_index_0]
      local _list_2 = (sp.fields or { })
      for _index_1 = 1, #_list_2 do
        local f = _list_2[_index_1]
        if f.ref then
          local target = f.ref:match('^([^.]+)')
          if not (wanted[target]) then
            f.ref = nil
          end
        end
      end
    end
    local structure = {
      app = {
        id = APP_ID,
        name = "Biblio test " .. tostring(SUFFIX),
        version = '1.0.0',
        description = 'T4'
      },
      spaces = part.spaces
    }
    PKG = B.expand(structure)
    local report = apply.apply_update(PKG, { }, { })
    R.ok(report.ok, "apply_update: " .. tostring(report.error))
    R.is_nil(report.reinit_error, 'reinit_schema')
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      R.ok(spaces.get_space_by_name(n), "espace non installé: " .. tostring(n))
    end
  end)
  R.it("compiles every formula", function()
    return check_formulas()
  end)
  R.it("inserts the library fixture rows", function()
    FIX.fiction = insert_row('Genres', {
      genre = 'Fiction'
    })
    FIX.roman = insert_row('Genres', {
      genre = 'Roman',
      parent = FIX.fiction
    })
    FIX.policier = insert_row('Genres', {
      genre = 'Policier',
      parent = FIX.roman
    })
    FIX.lafontaine = insert_row('Auteurs', {
      nom = 'La Fontaine',
      particule = 'de',
      prenom = 'Jean'
    })
    FIX.sans_livre = insert_row('Auteurs', {
      nom = 'Solitaire',
      prenom = 'Anne'
    })
    FIX.livre1 = insert_row('Livres', {
      titre = 'Fables',
      auteur = FIX.lafontaine,
      genre = FIX.policier
    })
    FIX.ex1 = insert_row('Exemplaires', {
      livre = FIX.livre1,
      cote = 'A1'
    })
    FIX.ex_sup = insert_row('Exemplaires', {
      livre = FIX.livre1,
      cote = 'A2',
      suppression = '2026-01-01'
    })
    FIX.livre2 = insert_row('Livres', {
      titre = 'Fables',
      auteur = FIX.lafontaine,
      genre = FIX.policier
    })
    FIX.livre3 = insert_row('Livres', {
      titre = 'Contes',
      auteur = FIX.lafontaine,
      genre = FIX.roman
    })
    FIX.luc = insert_row(SP_PERS, {
      nom = 'Martin',
      prenom = 'Luc'
    })
    FIX.ex_a = insert_row('Exemplaires', {
      livre = FIX.livre3,
      cote = 'B1'
    })
    FIX.ex_b = insert_row('Exemplaires', {
      livre = FIX.livre3,
      cote = 'B2'
    })
    FIX.emp_a = insert_row('Emprunts', {
      personne = FIX.luc,
      exemplaire = FIX.ex_a,
      emprunt = '2026-09-20'
    })
    FIX.emp_b = insert_row('Emprunts', {
      personne = FIX.luc,
      exemplaire = FIX.ex_b,
      emprunt = '2025-10-01',
      retour = '2025-10-10'
    })
    return R.ok(FIX.emp_a and FIX.emp_b, 'emprunts insérés')
  end)
  R.it("warms the FK metadata caches", function()
    local touched = 0
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      touched = touched + warm_fk(n, 3)
    end
    return R.ok(touched > 0, 'aucun champ de clé étrangère résolu')
  end)
  R.it("computes the genre hierarchy (niveau, chemin)", function()
    local p = row('Genres', 'id', FIX.policier)
    R.ok(p, 'Policier')
    R.eq(p.niveau, 3, 'Genres.niveau de Policier')
    R.eq(p.chemin, 'Fiction › Roman › Policier', 'Genres.chemin de Policier')
    local f = row('Genres', 'id', FIX.fiction)
    R.ok(f, 'Fiction')
    R.eq(f.niveau, 1, 'Genres.niveau de Fiction (racine)')
    return R.eq(f.chemin, 'Fiction', 'Genres.chemin de Fiction (racine)')
  end)
  R.it("computes the author fields (nom_complet, n_ouvrages)", function()
    local lf = row('Auteurs', 'id', FIX.lafontaine)
    R.ok(lf, 'La Fontaine')
    R.eq(lf.nom_complet, 'Jean de La Fontaine', 'Auteurs.nom_complet')
    R.eq(lf.n_ouvrages, 3, 'Auteurs.n_ouvrages de La Fontaine')
    local sl = row('Auteurs', 'id', FIX.sans_livre)
    R.ok(sl, 'auteur sans livre')
    return R.eq(sl.n_ouvrages, 0, 'Auteurs.n_ouvrages sans livre')
  end)
  R.it("counts exemplaires excluding suppressed ones", function()
    local l1 = row('Livres', 'id', FIX.livre1)
    R.ok(l1, 'livre 1')
    R.eq(l1.n_exemplaires, 1, 'n_exemplaires (A1 seul non supprimé)')
    local l2 = row('Livres', 'id', FIX.livre2)
    R.ok(l2, 'livre 2 sans exemplaire')
    return R.eq(l2.n_exemplaires, 0, 'n_exemplaires d\'un livre sans exemplaire')
  end)
  R.it("detects duplicate (same title and author)", function()
    local l1 = row('Livres', 'id', FIX.livre1)
    local l2 = row('Livres', 'id', FIX.livre2)
    R.eq(l1.doublon, true, 'livre 1 doublon')
    R.eq(l2.doublon, true, 'livre 2 doublon')
    return R.eq(l1.descriptif, 'Fables (Jean de La Fontaine)', 'Livres.descriptif')
  end)
  R.it("resolves the current borrower of an open loan (emprunteur)", function()
    local ex_a = row('Exemplaires', 'id', FIX.ex_a)
    local ex_b = row('Exemplaires', 'id', FIX.ex_b)
    R.ok(ex_a and ex_b, 'exemplaires A et B')
    R.eq(ex_a.emprunteur, 'Martin Luc', 'emprunteur du prêt non rendu')
    return R.is_nil(ex_b.emprunteur, 'emprunteur vide si le prêt est rendu')
  end)
  return R.it("cleans up", function()
    clean_app_rows(APP_ID)
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      drop_relations(n)
      spaces.delete_user_space(n)
    end
    drop_relations(SP_PERS)
    spaces.delete_user_space(SP_PERS)
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      R.is_nil(spaces.get_space_by_name(n), tostring(n) .. " removed")
    end
    return R.is_nil(spaces.get_space_by_name(SP_PERS))
  end)
end)
