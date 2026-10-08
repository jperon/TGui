local R = require('tests.runner')
local yaml = require('yaml')
local B = require('tools.app_builder')
local RNG = require('tools.seed_rng')
local pkg_mod = require('core.app_package')
R.describe("seed_rng", function()
  R.it("is deterministic for a given seed", function()
    local a, b = RNG.new(42), RNG.new(42)
    for _ = 1, 20 do
      R.eq(a.int(1, 1000), b.int(1, 1000))
    end
  end)
  R.it("int stays in bounds", function()
    local r = RNG.new(7)
    for _ = 1, 500 do
      local v = r.int(3, 9)
      R.ok(v >= 3 and v <= 9)
    end
  end)
  return R.it("differs between seeds", function()
    return R.ne(RNG.new(1).int(1, 1000000), RNG.new(2).int(1, 1000000))
  end)
end)
R.describe("app_builder.key_part", function()
  return R.it("matches core.app_package.key_part", function()
    local _list_0 = {
      'Livres',
      'a.b',
      'x|y',
      'k:v',
      '100%'
    }
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      R.eq(B.key_part(s), pkg_mod.key_part(s))
    end
  end)
end)
local STRUCT = {
  app = {
    id = 'org.test.mini',
    name = 'Mini',
    version = '1.0.0',
    description = 'd'
  },
  spaces = {
    {
      name = 'Auteurs',
      description = 'auteurs',
      fields = {
        {
          name = 'nom',
          type = 'String',
          notNull = true
        }
      }
    },
    {
      name = 'Livres',
      description = 'livres',
      fields = {
        {
          name = 'titre',
          type = 'String'
        },
        {
          name = 'auteur',
          type = 'Int',
          ref = 'Auteurs.id'
        },
        {
          name = 'n',
          type = 'Int',
          formula = "1 + 1"
        },
        {
          name = 'multi',
          type = 'Int',
          formula = "a = 1\na + 1\n"
        }
      }
    }
  }
}
R.describe("app_builder.expand", function()
  local pkg = B.expand(STRUCT)
  local by_key = { }
  local _list_0 = pkg.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    by_key[it.key] = it
  end
  R.it("emits space, field and relation items, id first", function()
    R.ok(by_key['space:Auteurs'])
    R.eq(by_key['field:Auteurs.id'].content.fieldType, 'Sequence')
    R.eq(by_key['field:Livres.titre'].content.fieldType, 'String')
    local rel = by_key['relation:Livres.auteur']
    R.eq(rel.content.toSpace, 'Auteurs')
    R.eq(rel.content.toField, 'id')
    return R.eq(rel.content.cardinality, 'one')
  end)
  R.it("orders spaces, then fields, then relations", function()
    local last = {
      space = 0,
      field = 0,
      relation = 0
    }
    local seen_field, seen_rel = false, false
    local _list_1 = pkg.items
    for _index_0 = 1, #_list_1 do
      local it = _list_1[_index_0]
      if it.type == 'field' then
        seen_field = true
      end
      if it.type == 'relation' then
        seen_rel = true
      end
      R.ok(not (it.type == 'space' and seen_field))
      R.ok(not (it.type == 'field' and seen_rel))
    end
  end)
  R.it("formula: single line kept, multi line prefixed by newline and indented", function()
    R.eq(by_key['field:Livres.n'].content.formula, '1 + 1')
    R.eq(by_key['field:Livres.n'].content.language, 'moonscript')
    return R.eq(by_key['field:Livres.multi'].content.formula, "\n  a = 1\n  a + 1")
  end)
  return R.it("seed_keys point to id", function()
    return R.eq(pkg.seed_keys.Livres, 'id')
  end)
end)
R.describe("app_builder.emit", function()
  R.it("round-trips accented and punctuated text through yaml.decode", function()
    local pkg = B.expand(STRUCT)
    B.add_seed(pkg, 'Auteurs', {
      {
        id = 1,
        nom = "L'île: Éloïse"
      },
      {
        id = 2,
        nom = "a: b # c"
      }
    })
    local out = B.emit(pkg)
    local back = yaml.decode(out)
    local seeds
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = back.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.type == 'seed' then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      seeds = _accum_0
    end
    R.eq(#seeds, 2)
    R.eq(seeds[1].content.data.nom, "L'île: Éloïse")
    return R.eq(seeds[2].content.data.nom, "a: b # c")
  end)
  R.it("is byte-identical on two emissions", function()
    local pkg = B.expand(STRUCT)
    return R.eq(B.emit(pkg), B.emit(B.expand(STRUCT)))
  end)
  return R.it("keys are sorted", function()
    local out = B.emit(B.expand(STRUCT))
    local a = out:find('description', 1, true)
    local f = out:find('items', 1, true)
    return R.ok(a and f and a < f)
  end)
end)
local fio = require('fio')
local _deep_eq
_deep_eq = function(a, b)
  if a == b then
    return true
  end
  if not (type(a) == 'table' and type(b) == 'table') then
    return false
  end
  for k, v in pairs(a) do
    if not (_deep_eq(v, b[k])) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end
local DV_CONFIG = {
  columns = {
    'id',
    'retour'
  },
  filter = {
    field = 'retour',
    op = 'EQ',
    value = ''
  },
  aggregates = {
    {
      fn = 'count',
      as = 'n'
    }
  },
  sort = {
    field = 'n',
    order = 'desc'
  },
  limit = 10
}
local PAGE_YAML = "titre: Accueil\ntexte: \"a: b\"\nliste:\n  - 1\n  - 2\n"
local STRUCT_VIEWS = {
  app = {
    id = 'org.test.views',
    name = 'Views',
    version = '1.0.0',
    description = 'd'
  },
  spaces = {
    {
      name = 'Auteurs',
      description = '',
      fields = {
        {
          name = 'nom',
          type = 'String'
        }
      }
    },
    {
      name = 'Emprunts',
      description = '',
      fields = {
        {
          name = 'auteur',
          type = 'Int',
          ref = 'Auteurs.id'
        },
        {
          name = 'retour',
          type = 'Datetime'
        },
        {
          name = 'n',
          type = 'Int'
        }
      }
    }
  },
  pages = {
    {
      name = 'Accueil.principal',
      description = 'page',
      yaml = PAGE_YAML
    }
  },
  dataviews = {
    {
      name = 'Emprunts en cours',
      description = 'dv',
      sourceSpace = 'Emprunts',
      config = DV_CONFIG
    },
    {
      name = 'Suivi: retards',
      sourceSpace = 'Emprunts',
      config = {
        limit = 3
      }
    }
  }
}
R.describe("app_builder.expand — dataviews et pages", function()
  local pkg = B.expand(STRUCT_VIEWS)
  local by_key = { }
  local _list_0 = pkg.items
  for _index_0 = 1, #_list_0 do
    local it = _list_0[_index_0]
    by_key[it.key] = it
  end
  R.it("produit les items page et dataview avec clés et contenus", function()
    local pg = by_key['page:Accueil%2Eprincipal']
    R.ok(pg, 'page présente')
    R.eq(pg.content.name, 'Accueil.principal')
    R.eq(pg.content.description, 'page')
    R.eq(pg.content.yaml, PAGE_YAML)
    local dv = by_key['dataview:Emprunts en cours']
    R.ok(dv, 'dataview présente (espaces préservés)')
    R.eq(dv.content.name, 'Emprunts en cours')
    R.eq(dv.content.description, 'dv')
    R.eq(dv.content.sourceSpace, 'Emprunts')
    R.eq(dv.content.config.limit, 10)
    R.eq(dv.content.config.filter.value, '')
    R.ok(by_key['dataview:Suivi%3A retards'], 'deux-points encodés')
    return R.eq(by_key['dataview:Suivi%3A retards'].content.description, '')
  end)
  R.it("émet les groupes dans l'ordre space, field, relation, page, dataview", function()
    local rank = {
      space = 1,
      field = 2,
      relation = 3,
      page = 4,
      dataview = 5
    }
    local last = 0
    local _list_1 = pkg.items
    for _index_0 = 1, #_list_1 do
      local it = _list_1[_index_0]
      local r = rank[it.type]
      R.ok(r, "type connu: " .. tostring(it.type))
      R.ok(r >= last, "ordre: " .. tostring(it.type) .. " après rang " .. tostring(last))
      last = r
    end
  end)
  return R.it("conserve le comportement d'une structure sans vue ni page", function()
    local p = B.expand(STRUCT)
    local extra
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_1 = p.items
      for _index_0 = 1, #_list_1 do
        local it = _list_1[_index_0]
        if it.type == 'page' or it.type == 'dataview' then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      extra = _accum_0
    end
    R.eq(#extra, 0)
    return R.eq(B.emit(p), B.emit(B.expand(STRUCT)))
  end)
end)
R.describe("app_builder.emit — aller-retour vues et pages", function()
  return R.it("préserve une config de vue et un YAML de page multi-ligne", function()
    local pkg = B.expand(STRUCT_VIEWS)
    local back = yaml.decode(B.emit(pkg))
    local pages
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = back.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.type == 'page' then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      pages = _accum_0
    end
    local dvs
    do
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = back.items
      for _index_0 = 1, #_list_0 do
        local it = _list_0[_index_0]
        if it.type == 'dataview' then
          _accum_0[_len_0] = it
          _len_0 = _len_0 + 1
        end
      end
      dvs = _accum_0
    end
    R.eq(#pages, 1)
    R.eq(#dvs, 2)
    R.eq(pages[1].key, 'page:Accueil%2Eprincipal')
    R.eq(pages[1].content.yaml, PAGE_YAML)
    local dv = ((function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #dvs do
        local d = dvs[_index_0]
        if d.content.name == 'Emprunts en cours' then
          _accum_0[_len_0] = d
          _len_0 = _len_0 + 1
        end
      end
      return _accum_0
    end)())[1]
    R.ok(dv, 'dataview retrouvée')
    R.ok(_deep_eq(dv.content.config, DV_CONFIG), 'config identique')
    R.eq(dv.content.config.filter.value, '')
    R.eq(dv.content.config.aggregates[1].fn, 'count')
    R.eq(dv.content.config.sort.order, 'desc')
    return R.eq(dv.content.config.limit, 10)
  end)
end)
return R.describe("app_builder.load_structure — dataviews et pages", function()
  local dir = "/tmp/tgui_t15_" .. tostring(tostring(math.random(100000, 999999)))
  local write
  write = function(rel, text)
    local fh = fio.open(fio.pathjoin(dir, rel), {
      'O_WRONLY',
      'O_CREAT',
      'O_TRUNC'
    })
    fh:write(text)
    return fh:close()
  end
  R.it("concatène spaces, dataviews et pages de chaque fichier", function()
    fio.mktree(dir)
    fio.mktree(fio.pathjoin(dir, 'structure'))
    write('app.yaml', "app:\n  id: org.test.ls\n  name: LS\n  version: 1.0.0\n  description: d\n")
    write('structure/a.yaml', "spaces:\n- {name: A, description: a, fields: [{name: x, type: String}]}\ndataviews:\n- {name: D1, sourceSpace: A, config: {limit: 1}}\n")
    write('structure/b.yaml', "pages:\n- {name: P1, yaml: \"hi\"}\ndataviews:\n- {name: D2, sourceSpace: A, config: {limit: 2}}\n")
    local s = B.load_structure(dir)
    R.eq(#s.spaces, 1)
    R.eq(s.spaces[1].name, 'A')
    R.eq(#s.dataviews, 2)
    R.eq(s.dataviews[1].name, 'D1')
    R.eq(s.dataviews[2].name, 'D2')
    R.eq(#s.pages, 1)
    return R.eq(s.pages[1].name, 'P1')
  end)
  R.it("listes absentes → listes vides", function()
    write('structure/a.yaml', "spaces:\n- {name: A, description: a, fields: [{name: x, type: String}]}\n")
    local fh = fio.open(fio.pathjoin(dir, 'structure', 'b.yaml'), {
      'O_RDONLY'
    })
    if fh then
      fh:close()
      fio.unlink(fio.pathjoin(dir, 'structure', 'b.yaml'))
    end
    local s = B.load_structure(dir)
    R.eq(#s.dataviews, 0)
    return R.eq(#s.pages, 0)
  end)
  return R.it("nettoie", function()
    if fio.stat(dir) then
      fio.rmtree(dir)
    end
    return R.nok(fio.stat(dir), 'répertoire temporaire supprimé')
  end)
end)
