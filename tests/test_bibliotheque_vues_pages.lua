local R = require('tests.runner')
local json = require('json')
local yaml = require('yaml')
local spaces = require('core.spaces')
local auth = require('core.auth')
local apply = require('core.app_apply')
local data_views = require('core.data_views')
local executor = require('core.data_views_executor')
local fiber = require('fiber')
local APP_ID = 'org.tgui.bibliotheque'
local EXPECTED_VIEWS = {
  'Emprunts en cours',
  'Exemplaires disponibles',
  'Exemplaires prêtés',
  'Livres sans exemplaire',
  'Livres les plus empruntés',
  'Emprunts par année',
  'Livres par genre',
  'Effectifs par classe'
}
local EXPECTED_PAGES = {
  'Prêts et retours',
  'Catalogue',
  'Lecteurs et classes',
  'Tableau de bord'
}
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local pkg_mod = nil
local pkg
pkg = function()
  pkg_mod = pkg_mod or require('tools.bibliotheque_app').build()
  return pkg_mod
end
local items_of_type
items_of_type = function(t)
  local _accum_0 = { }
  local _len_0 = 1
  local _list_0 = pkg().items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    if it.type == t then
      _accum_0[_len_0] = it
      _len_0 = _len_0 + 1
    end
  end
  return _accum_0
end
local data_view_rows
data_view_rows = function()
  local out = { }
  local _list_0 = box.space._tdb_data_views:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    out[t[2]] = {
      id = t[1],
      name = t[2],
      description = t[3],
      sourceSpace = t[4],
      config = t[5]
    }
  end
  return out
end
local page_rows
page_rows = function()
  local out = { }
  local _list_0 = box.space._tdb_custom_views:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    out[t[2]] = {
      id = t[1],
      name = t[2],
      description = t[3],
      yaml = t[4]
    }
  end
  return out
end
local exec_view
exec_view = function(name)
  local v = data_views.get_view_by_name(name)
  if not (v) then
    error("vue absente: " .. tostring(name))
  end
  fiber.yield()
  return executor.execute_view(v.sourceSpace, v.config, { })
end
local space_fields
space_fields = function(name)
  local sp = spaces.get_space_by_name(name)
  if not (sp) then
    return nil
  end
  local m = { }
  local _list_0 = spaces.list_fields(sp.id)
  for _index_0 = 1, #_list_0 do
    local f = _list_0[_index_0]
    m[f.name] = true
  end
  return m
end
local view_columns
view_columns = function(name)
  local v = data_views.get_view_by_name(name)
  if not (v) then
    return nil
  end
  local cfg = { }
  local ok, dec = pcall(json.decode, v.config)
  if ok and type(dec) == 'table' then
    cfg = dec
  end
  local cols = { }
  local _list_0 = (cfg.columns or { })
  for _index_0 = 1, #_list_0 do
    local c = _list_0[_index_0]
    if type(c) == 'string' then
      cols[c] = true
    elseif type(c) == 'table' and c.field then
      cols[c.as or c.field] = true
    end
  end
  local _list_1 = (cfg.groupBy or { })
  for _index_0 = 1, #_list_1 do
    local f = _list_1[_index_0]
    cols[f] = true
  end
  local _list_2 = (cfg.aggregates or { })
  for _index_0 = 1, #_list_2 do
    local a = _list_2[_index_0]
    local alias = a.as or ((function()
      if a.field then
        return tostring(a.fn) .. "_" .. tostring(a.field)
      else
        return a.fn
      end
    end)())
    cols[alias] = true
  end
  return cols
end
local ref_fields
ref_fields = function(name)
  local f = space_fields(name)
  return f or view_columns(name)
end
local walk_widgets
walk_widgets = function(node, out)
  if not (type(node) == 'table') then
    return 
  end
  if node.widget then
    table.insert(out, node.widget)
    return 
  end
  if node.layout then
    walk_widgets(node.layout, out)
    return 
  end
  local _list_0 = (node.children or { })
  for _index_0 = 1, #_list_0 do
    local c = _list_0[_index_0]
    walk_widgets(c, out)
  end
end
local validate_page
validate_page = function(name)
  local t = box.space._tdb_custom_views:select({ })
  local yml = nil
  for _index_0 = 1, #t do
    local row = t[_index_0]
    if row[2] == name then
      yml = row[4]
    end
  end
  if not (yml) then
    R.ok(false, "page " .. tostring(name) .. ": absente de _tdb_custom_views")
    return 
  end
  local ok, doc = pcall(yaml.decode, yml)
  R.ok(ok, "page " .. tostring(name) .. ": YAML invalide (" .. tostring(doc) .. ")")
  if not (ok) then
    return 
  end
  R.ok(doc.layout, "page " .. tostring(name) .. ": layout absent")
  if not (doc.layout) then
    return 
  end
  local widgets = { }
  walk_widgets(doc.layout, widgets)
  R.ok(#widgets > 0, "page " .. tostring(name) .. ": aucun widget")
  local seen = { }
  for _index_0 = 1, #widgets do
    local w = widgets[_index_0]
    local ref = w.space
    if not ref then
      R.ok(false, "page " .. tostring(name) .. ": widget sans 'space'")
    else
      local fields = ref_fields(ref)
      if not fields then
        R.ok(false, "page " .. tostring(name) .. ": '" .. tostring(ref) .. "' ne référence ni espace ni vue")
        fields = { }
      end
      local _list_0 = (w.columns or { })
      for _index_1 = 1, #_list_0 do
        local col = _list_0[_index_1]
        R.ok(fields[col], "page " .. tostring(name) .. ": colonne '" .. tostring(col) .. "' inconnue dans '" .. tostring(ref) .. "'")
      end
      local _list_1 = (w.groupBy or { })
      for _index_1 = 1, #_list_1 do
        local g = _list_1[_index_1]
        R.ok(fields[g], "page " .. tostring(name) .. ": groupBy '" .. tostring(g) .. "' inconnu dans '" .. tostring(ref) .. "'")
      end
      local dep = w.depends_on
      if dep then
        local src = seen[dep.widget]
        R.ok(src, "page " .. tostring(name) .. ": depends_on '" .. tostring(dep.widget) .. "' non défini plus haut")
        if dep.field then
          R.ok(fields[dep.field], "page " .. tostring(name) .. ": field '" .. tostring(dep.field) .. "' inconnu dans '" .. tostring(ref) .. "'")
        end
        if src and dep.from_field then
          local srcfields = ref_fields(src.space) or { }
          R.ok(srcfields[dep.from_field], "page " .. tostring(name) .. ": from_field '" .. tostring(dep.from_field) .. "' inconnu dans '" .. tostring(src.space) .. "'")
        end
      end
    end
    if w.id then
      seen[w.id] = w
    end
  end
end
R.describe("T16b — paquet Bibliothèque (vues et pages)", function()
  return R.it("a 8 vues de données et 4 pages, version 1.1.0", function()
    R.eq(pkg().app.version, '1.1.0', 'version')
    local dv_items = items_of_type('dataview')
    local pg_items = items_of_type('page')
    R.eq(#dv_items, 8, 'items dataview')
    R.eq(#pg_items, 4, 'items page')
    R.eq(json.encode((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #dv_items do
        local it = dv_items[_index_0]
        _accum_0[_len_0] = it.content.name
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)()), json.encode(EXPECTED_VIEWS), 'noms des vues')
    return R.eq(json.encode((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #pg_items do
        local it = pg_items[_index_0]
        _accum_0[_len_0] = it.content.name
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)()), json.encode(EXPECTED_PAGES), 'noms des pages')
  end)
end)
R.describe("T16b — état installé", function()
  R.it("applies the current package (idempotent on a fresh container)", function()
    fiber.yield()
    local report = apply.apply_update(pkg(), { }, { })
    R.ok(report.ok, "apply_update: " .. tostring(report.error))
    return R.is_nil(report.reinit_error, 'reinit_schema')
  end)
  return R.it("the 8 data views and 4 pages are installed with the right names", function()
    local vs = data_view_rows()
    for _index_0 = 1, #EXPECTED_VIEWS do
      local name = EXPECTED_VIEWS[_index_0]
      R.ok(vs[name], "vue installée manquante: " .. tostring(name))
    end
    R.eq(#((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #EXPECTED_VIEWS do
        local n = EXPECTED_VIEWS[_index_0]
        if vs[n] then
          _accum_0[_len_0] = n
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)()), 8, 'vues installées')
    local ps = page_rows()
    for _index_0 = 1, #EXPECTED_PAGES do
      local name = EXPECTED_PAGES[_index_0]
      R.ok(ps[name], "page installée manquante: " .. tostring(name))
    end
    return R.eq(#((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #EXPECTED_PAGES do
        local n = EXPECTED_PAGES[_index_0]
        if ps[n] then
          _accum_0[_len_0] = n
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)()), 4, 'pages installées')
  end)
end)
R.describe("T16b — exécution des vues de données", function()
  R.it("Emprunts en cours — 30 lignes triées par emprunt", function()
    local rows = exec_view('Emprunts en cours')
    R.eq(#rows, 30, 'nb lignes')
    for i = 2, #rows do
      R.ok(tostring(rows[i - 1].emprunt) <= tostring(rows[i].emprunt), "tri emprunt " .. tostring(i))
    end
  end)
  R.it("Exemplaires disponibles — 65 lignes triées par cote", function()
    local rows = exec_view('Exemplaires disponibles')
    R.eq(#rows, 65, 'nb lignes')
    for i = 2, #rows do
      R.ok(tostring(rows[i - 1].cote) <= tostring(rows[i].cote), "tri cote " .. tostring(i))
    end
  end)
  R.it("Exemplaires prêtés — 30 lignes", function()
    local rows = exec_view('Exemplaires prêtés')
    return R.eq(#rows, 30, 'nb lignes')
  end)
  R.it("Livres sans exemplaire — 15 lignes", function()
    local rows = exec_view('Livres sans exemplaire')
    return R.eq(#rows, 15, 'nb lignes')
  end)
  R.it("Livres les plus empruntés — 10 lignes, nb_emprunts décroissant", function()
    local rows = exec_view('Livres les plus empruntés')
    R.eq(#rows, 10, 'limit 10')
    for i = 2, #rows do
      R.ok((rows[i - 1].nb_emprunts or 0) >= (rows[i].nb_emprunts or 0), "tri desc " .. tostring(i))
    end
    return R.ok(rows[1] and rows[1].livre_titre, 'libellé livre_titre non vide')
  end)
  R.it("Emprunts par année — 2 groupes 90 + 30 = 120", function()
    local rows = exec_view('Emprunts par année')
    R.eq(#rows, 2, '2 groupes')
    local by = { }
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      by[tostring(r.annee_scolaire)] = r.nb_emprunts
    end
    R.eq(by['2025 - 2026'], 90, '2025 - 2026')
    R.eq(by['2026 - 2027'], 30, '2026 - 2027')
    local sum = 0
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      sum = sum + (r.nb_emprunts or 0)
    end
    return R.eq(sum, 120, 'somme')
  end)
  R.it("Livres par genre — somme des nb_livres = 60", function()
    local rows = exec_view('Livres par genre')
    local sum = 0
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      sum = sum + (r.nb_livres or 0)
    end
    R.eq(sum, 60, 'somme')
    return R.ok(rows[1] and rows[1].genre_nom, 'libellé genre_nom non vide')
  end)
  return R.it("Effectifs par classe — 5 groupes de 12", function()
    local rows = exec_view('Effectifs par classe')
    R.eq(#rows, 5, '5 classes')
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      R.eq(r.effectif, 12, "effectif classe " .. tostring(r.classe_nom))
    end
  end)
end)
return R.describe("T16b — pages (YAML, widgets, dépendances)", function()
  return R.it("each page has a valid YAML layout and existing references", function()
    for _index_0 = 1, #EXPECTED_PAGES do
      local name = EXPECTED_PAGES[_index_0]
      validate_page(name)
    end
  end)
end)
