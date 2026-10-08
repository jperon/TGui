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
return R.describe("app_builder.emit", function()
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
