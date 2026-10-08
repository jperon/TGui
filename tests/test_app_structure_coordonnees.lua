local R = require('tests.runner')
local yaml = require('yaml')
local fio = require('fio')
local json = require('json')
local B = require('tools.app_builder')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local auth = require('core.auth')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local APP_ID = "org.test.coordonnees_" .. tostring(SUFFIX)
local SP_PERS = 'Personnes'
local STRUCT_PATH = '/app/backend/apps/bibliotheque/structure/coordonnees.yaml'
local OWN_SPACES = {
  'TypesCoordonnees',
  'Coordonnees',
  'PersonnesCoordonnees'
}
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
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
local space_id
space_id = function(name)
  local sp = spaces.get_space_by_name(name)
  if not (sp) then
    error("space missing: " .. tostring(name))
  end
  return sp.id
end
local rows_of
rows_of = function(name)
  local out = { }
  local res = data_r.Query.records(nil, {
    spaceId = space_id(name)
  }, CTX)
  local _list_0 = res.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    table.insert(out, json.decode(it.data))
  end
  return out
end
local insert_into
insert_into = function(name, data)
  return data_r.Mutation.insertRecord({ }, {
    spaceId = space_id(name),
    data = data
  }, CTX)
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
R.describe("app_structure_coordonnees — install", function()
  return R.it("installs the three spaces declared in structure/coordonnees.yaml", function()
    local part = read_yaml(STRUCT_PATH)
    local declared = { }
    local _list_0 = part.spaces
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      declared[sp.name] = true
    end
    R.eq(#part.spaces, 3, 'declared spaces')
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      R.ok(declared[n], "declares " .. tostring(n))
    end
    local pers = spaces.create_user_space(SP_PERS, 'T5 minimal persons')
    spaces.add_field(pers.id, 'id', 'Sequence', true, 'Identifiant')
    spaces.add_field(pers.id, 'nom', 'String', false, '')
    spaces.add_field(pers.id, 'prenom', 'String', false, '')
    local structure = {
      app = {
        id = APP_ID,
        name = 'Coordonnees T5',
        version = '1.0.0',
        description = 'T5'
      },
      spaces = part.spaces
    }
    local pkg = B.expand(structure)
    local report = apply.apply_update(pkg, { }, { })
    R.ok(report.ok, report.error)
    for _index_0 = 1, #OWN_SPACES do
      local n = OWN_SPACES[_index_0]
      R.ok(spaces.get_space_by_name(n), tostring(n) .. " installed")
    end
  end)
end)
R.describe("app_structure_coordonnees — data", function()
  R.it("inserts the three contact types", function()
    local _list_0 = {
      'tel',
      'courriel',
      'adresse'
    }
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      insert_into('TypesCoordonnees', {
        type = t
      })
    end
    return R.eq(#rows_of('TypesCoordonnees'), 3, 'types')
  end)
  R.it("inserts one coordonnée whose type_coordonnee points at an existing type", function()
    local types = rows_of('TypesCoordonnees')
    insert_into('Coordonnees', {
      type_coordonnee = types[1].id,
      valeur = '06 00 00 12 34'
    })
    local coords = rows_of('Coordonnees')
    R.eq(#coords, 1, 'coordonnées')
    local known = { }
    for _index_0 = 1, #types do
      local t = types[_index_0]
      known[t.id] = true
    end
    return R.ok(known[coords[1].type_coordonnee], 'type_coordonnee points at an installed type')
  end)
  R.it("links two people to the same coordonnée (N-N)", function()
    local p1 = insert_into(SP_PERS, {
      nom = 'Martin',
      prenom = 'Luc'
    })
    local p2 = insert_into(SP_PERS, {
      nom = 'Dupont',
      prenom = 'Jeanne'
    })
    local coord_id = rows_of('Coordonnees')[1].id
    local _list_0 = {
      json.decode(p1.data).id,
      json.decode(p2.data).id
    }
    for _index_0 = 1, #_list_0 do
      local pid = _list_0[_index_0]
      insert_into('PersonnesCoordonnees', {
        personne = pid,
        coordonnee = coord_id,
        libelle = 'domicile'
      })
    end
    local links = rows_of('PersonnesCoordonnees')
    R.eq(#links, 2, 'liaisons N-N')
    R.eq(links[1].coordonnee, coord_id, 'first link shares the coordonnée')
    R.eq(links[2].coordonnee, coord_id, 'second link shares the coordonnée')
    return R.ne(links[1].personne, links[2].personne, 'two distinct personnes')
  end)
  return R.it("refuses a Coordonnée without valeur (notNull)", function()
    R.raises((function()
      return insert_into('Coordonnees', {
        type_coordonnee = 1
      })
    end), 'not_null', 'valeur required')
    return R.eq(#rows_of('Coordonnees'), 1, 'no row written')
  end)
end)
return R.describe("app_structure_coordonnees — cleanup", function()
  return R.it("removes the spaces, relations and tracking rows", function()
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
    R.is_nil(spaces.get_space_by_name(SP_PERS))
    R.is_nil(box.space._tdb_apps:get(APP_ID))
    return R.eq(#box.space._tdb_app_items.index.by_app:select({
      APP_ID
    }), 0, 'tracking rows')
  end)
end)
