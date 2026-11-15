local R = require('tests.runner')
local json = require('json')
local spaces_mod = require('core.spaces')
local schema_r = require('resolvers.schema_resolvers')
local executor = require('core.data_views_executor')
local trusted_ctx
trusted_ctx = require('resolvers.utils').trusted_ctx
local SUFFIX = tostring(math.random(100000, 999999))
local CLS = "dvg_cls_" .. tostring(SUFFIX)
local PERS = "dvg_pers_" .. tostring(SUFFIX)
local CTX = trusted_ctx('admin')
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
    classe_id = 2
  },
  {
    nom = 'David',
    classe_id = 3
  }
}
local ins
ins = function(name, id, data)
  return box.space["data_" .. tostring(name)]:insert({
    id,
    json.encode(data)
  })
end
local cls_sp = spaces_mod.create_user_space(CLS, 'dvg — classes (cible)')
local pers_sp = spaces_mod.create_user_space(PERS, 'dvg — personnes (source)')
spaces_mod.add_field(cls_sp.id, 'id', 'Sequence')
spaces_mod.add_field(cls_sp.id, 'nom', 'String')
spaces_mod.add_field(pers_sp.id, 'nom', 'String')
spaces_mod.add_field(pers_sp.id, 'classe_id', 'Int')
spaces_mod.add_field(pers_sp.id, 'initiale', 'String', false, '', "string.sub(self.nom or '', 1, 1)", nil, 'lua')
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
    classe_id = p.classe_id
  })
end
local rel = schema_r.Mutation.createRelation(nil, {
  input = {
    name = 'dvg_classe',
    fromSpaceId = pers_sp.id,
    fromFieldId = fields_pers['classe_id'].id,
    toSpaceId = cls_sp.id,
    toFieldId = fields_cls['id'].id,
    reprFormula = '@nom'
  }
}, CTX)
local run_view
run_view = function(config)
  return executor.execute_view(pers_sp.id, json.encode(config), { })
end
R.describe("DataViews — groupBy sur une relation", function()
  R.it("regroupe par la valeur brute du champ relation (un groupe par valeur)", function()
    local res = run_view({
      groupBy = {
        'classe_id'
      },
      aggregates = {
        {
          fn = 'count',
          as = 'n'
        }
      },
      orderBy = {
        {
          field = 'classe_id'
        }
      }
    })
    R.eq(#res, #CLASSES, 'un groupe par classe, pas un par enregistrement')
    local by_group = { }
    for _index_0 = 1, #res do
      local row = res[_index_0]
      R.eq(type(row.classe_id), 'number', "étiquette de groupe " .. tostring(tostring(row.classe_id)) .. " (table = proxy FK)")
      if type(row.classe_id) == 'number' then
        by_group[row.classe_id] = row
      end
    end
    R.eq(by_group[1] and by_group[1].n, 1, 'une personne en CM2')
    R.eq(by_group[2] and by_group[2].n, 2, 'deux personnes en 6eB')
    return R.eq(by_group[3] and by_group[3].n, 1, 'une personne en 3eA')
  end)
  R.it("garde le regroupement sur une colonne calculée (proxy conservé)", function()
    local res = run_view({
      groupBy = {
        'initiale'
      },
      aggregates = {
        {
          fn = 'count',
          as = 'n'
        }
      }
    })
    R.eq(#res, #PERSONS, 'une initiale distincte par personne')
    local initiales = { }
    for _index_0 = 1, #res do
      local row = res[_index_0]
      R.eq(type(row.initiale), 'string', "étiquette calculée " .. tostring(tostring(row.initiale)))
      initiales[row.initiale] = row.n
    end
    R.eq(initiales['A'], 1, 'une personne en A')
    return R.eq(initiales['B'], 1, 'une personne en B')
  end)
  return R.it("agrège aussi une somme sur un champ relation voisin", function()
    local res = run_view({
      groupBy = {
        'classe_id'
      },
      aggregates = {
        {
          field = 'classe_id',
          fn = 'max',
          as = 'classe_max'
        }
      },
      orderBy = {
        {
          field = 'classe_id'
        }
      }
    })
    R.eq(#res, #CLASSES, 'un groupe par classe')
    for _index_0 = 1, #res do
      local row = res[_index_0]
      R.eq(type(row.classe_id), 'number', "étiquette " .. tostring(tostring(row.classe_id)))
      R.eq(row.classe_max, row.classe_id, 'le max du champ relation reste son Int')
    end
  end)
end)
box.space._tdb_relations:delete({
  rel.id
})
spaces_mod.delete_user_space(PERS)
spaces_mod.delete_user_space(CLS)
return require('resolvers.init').reinit()
