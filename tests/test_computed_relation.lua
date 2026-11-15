local R = require('tests.runner')
local json = require('json')
local spaces_mod = require('core.spaces')
local schema_r = require('resolvers.schema_resolvers')
local executor = require('graphql.executor')
local dynamic = require('graphql.dynamic')
local data_r = require('resolvers.data_resolvers')
local trusted_ctx
trusted_ctx = require('resolvers.utils').trusted_ctx
local SUFFIX = tostring(math.random(100000, 999999))
local CLS = "crel_cls_" .. tostring(SUFFIX)
local PERS = "crel_pers_" .. tostring(SUFFIX)
local CTX = trusted_ctx('test-user')
local CLASSES = {
  'CM2',
  '6eB',
  '3eA'
}
local PERSONS = {
  {
    nom = 'Ada',
    classe_id = 1
  },
  {
    nom = 'Bruno',
    classe_id = 2
  },
  {
    nom = 'Chloé',
    classe_id = 3
  },
  {
    nom = 'David',
    classe_id = 2
  }
}
local ins
ins = function(name, id, data)
  return box.space["data_" .. tostring(name)]:insert({
    id,
    json.encode(data)
  })
end
local cls_sp = spaces_mod.create_user_space(CLS, 'crel — classes (cible)')
local pers_sp = spaces_mod.create_user_space(PERS, 'crel — personnes (source)')
spaces_mod.add_field(cls_sp.id, 'id', 'Sequence')
spaces_mod.add_field(cls_sp.id, 'nom', 'String')
spaces_mod.add_field(pers_sp.id, 'nom', 'String')
spaces_mod.add_field(pers_sp.id, 'classe_id', 'Int')
spaces_mod.add_field(pers_sp.id, 'classe_actuelle', 'Int', false, '', 'self.classe_id', nil, 'moonscript')
spaces_mod.add_field(pers_sp.id, 'classe_fixe', 'Int')
spaces_mod.add_field(pers_sp.id, 'classe_nom', 'String', false, '', '(@classe_actuelle and @classe_actuelle.nom) or ""', nil, 'moonscript')
local fields_cls = { }
local fields_pers = { }
local _list_0 = spaces_mod.list_fields(cls_sp.id)
for _index_0 = 1, #_list_0 do
  local f = _list_0[_index_0]
  fields_cls[f.name] = f
end
local _list_1 = spaces_mod.list_fields(pers_sp.id)
for _index_0 = 1, #_list_1 do
  local f = _list_1[_index_0]
  fields_pers[f.name] = f
end
for i, nom in ipairs(CLASSES) do
  ins(CLS, "cls_" .. tostring(i), {
    id = i,
    nom = nom
  })
end
for i, p in ipairs(PERSONS) do
  ins(PERS, "pers_" .. tostring(i), {
    nom = p.nom,
    classe_id = p.classe_id,
    classe_fixe = p.classe_id
  })
end
local rel_computed = schema_r.Mutation.createRelation(nil, {
  input = {
    name = 'ct_classe',
    fromSpaceId = pers_sp.id,
    fromFieldId = fields_pers['classe_actuelle'].id,
    toSpaceId = cls_sp.id,
    toFieldId = fields_cls['id'].id,
    reprFormula = '@nom'
  }
}, CTX)
local rel_stored = schema_r.Mutation.createRelation(nil, {
  input = {
    name = 'ct_fixe',
    fromSpaceId = pers_sp.id,
    fromFieldId = fields_pers['classe_fixe'].id,
    toSpaceId = cls_sp.id,
    toFieldId = fields_cls['id'].id,
    reprFormula = '@nom'
  }
}, CTX)
local PERS_T = dynamic.gql_name(PERS)
local CLS_T = dynamic.gql_name(CLS)
local query
query = function(q)
  local res = executor.execute({
    query = q,
    context = CTX
  })
  R.nok(res.errors, json.encode(res.errors))
  return res.data
end
R.describe("Relation sur un champ calculé", function()
  R.it("(a) la requête dynamique résout le champ calculé en objet cible", function()
    local data = query("{ " .. tostring(PERS_T) .. " { items { nom classe_actuelle { nom } } } }")
    local items = data[PERS_T].items
    R.eq(#items, #PERSONS, 'items')
    local bad = { }
    for i, item in ipairs(items) do
      local expected = CLASSES[PERSONS[i].classe_id]
      local got = item.classe_actuelle and item.classe_actuelle.nom
      if got ~= expected then
        table.insert(bad, tostring(item.nom) .. ": " .. tostring(tostring(got)) .. " != " .. tostring(expected))
      end
    end
    return R.eq(#bad, 0, tostring(#bad) .. " valeur(s) fausse(s); premiere: " .. tostring(bad[1]))
  end)
  R.it("(b) une formule de filtre navigue @classe_actuelle.nom", function()
    local q = "{ " .. tostring(PERS_T) .. "(filter: { formula: \"@classe_actuelle.nom == '6eB'\", language: \"moonscript\" }) { total items { nom } } }"
    local data = query(q)
    local page = data[PERS_T]
    R.eq(page.total, 2, 'deux personnes en 6eB')
    local noms
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_2 = page.items
      for _index_0 = 1, #_list_2 do
        local item = _list_2[_index_0]
        _accum_0[_len_0] = item.nom
        _len_0 = _len_0 + 1
      end
      noms = _accum_0
    end
    table.sort(noms)
    R.eq(noms[1], 'Bruno')
    return R.eq(noms[2], 'David')
  end)
  R.it("(c) la relation inverse depuis la cible voit les lignes calculées", function()
    local data = query("{ " .. tostring(CLS_T) .. " { items { nom ct_classe { items { nom } } } } }")
    local by_name = { }
    local _list_2 = data[CLS_T].items
    for _index_0 = 1, #_list_2 do
      local item = _list_2[_index_0]
      do
        local _accum_0 = { }
        local _len_0 = 1
        local _list_3 = item.ct_classe.items
        for _index_1 = 1, #_list_3 do
          local p = _list_3[_index_1]
          _accum_0[_len_0] = p.nom
          _len_0 = _len_0 + 1
        end
        by_name[item.nom] = _accum_0
      end
    end
    table.sort(by_name['6eB'])
    R.eq(#by_name['CM2'], 1, 'CM2')
    R.eq(by_name['CM2'][1], 'Ada')
    R.eq(#by_name['6eB'], 2, '6eB')
    R.eq(by_name['6eB'][1], 'Bruno')
    R.eq(by_name['6eB'][2], 'David')
    return R.eq(#by_name['3eA'], 1, '3eA')
  end)
  R.it("(d) sans sous-sélection, la valeur brute est un Int (chemin grille)", function()
    local data = query("{ " .. tostring(PERS_T) .. " { items { nom classe_actuelle classe_fixe } } }")
    for i, item in ipairs(data[PERS_T].items) do
      local expected = PERSONS[i].classe_id
      R.eq(item.classe_actuelle, expected, "classe_actuelle de " .. tostring(item.nom))
      R.eq(item.classe_fixe, expected, "classe_fixe de " .. tostring(item.nom))
    end
  end)
  R.it("(d bis) une relation non calculée continue de se résoudre en objet", function()
    local data = query("{ " .. tostring(PERS_T) .. " { items { nom classe_fixe { nom } } } }")
    for i, item in ipairs(data[PERS_T].items) do
      local expected = CLASSES[PERSONS[i].classe_id]
      R.eq(item.classe_fixe and item.classe_fixe.nom, expected, "classe_fixe de " .. tostring(item.nom))
    end
  end)
  R.it("(e) une autre colonne calculée navigue @classe_actuelle.nom", function()
    local data = query("{ " .. tostring(PERS_T) .. " { items { nom classe_nom } } }")
    for i, item in ipairs(data[PERS_T].items) do
      local expected = CLASSES[PERSONS[i].classe_id]
      R.eq(item.classe_nom, expected, "classe_nom de " .. tostring(item.nom))
    end
  end)
  return R.it("(e bis) Query.records expose la valeur calculée (chemin custom views)", function()
    local res = data_r.Query.records(nil, {
      spaceId = pers_sp.id,
      limit = 100
    }, CTX)
    R.eq(res.total, #PERSONS, 'total')
    local by_nom = { }
    local _list_2 = res.items
    for _index_0 = 1, #_list_2 do
      local item = _list_2[_index_0]
      local d
      if type(item.data) == 'string' then
        d = json.decode(item.data)
      else
        d = item.data
      end
      by_nom[d.nom] = d
    end
    for i, p in ipairs(PERSONS) do
      R.eq(by_nom[p.nom].classe_actuelle, p.classe_id, "classe_actuelle de " .. tostring(p.nom))
    end
  end)
end)
box.space._tdb_relations:delete({
  rel_computed.id
})
box.space._tdb_relations:delete({
  rel_stored.id
})
spaces_mod.delete_user_space(PERS)
spaces_mod.delete_user_space(CLS)
return require('resolvers.init').reinit()
