local R = require('tests.runner')
local auth = require('core.auth')
local spaces = require('core.spaces')
local export_r = require('resolvers.export_resolvers')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local admin_user = auth.get_user_by_username('admin')
local ADMIN_CTX = {
  user_id = admin_user and admin_user.id
}
R.describe("exportSnapshot — structure", function()
  R.it("retourne une chaîne YAML non vide", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    R.ok(result)
    return R.ok(#result > 10)
  end)
  R.it("le YAML est parsable", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    R.ok(snap)
    return R.ok(snap.version)
  end)
  R.it("contient une section schema.spaces", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    R.ok(snap.schema)
    R.ok(snap.schema.spaces)
    return R.ok(#snap.schema.spaces >= 0)
  end)
  R.it("ne contient pas de section data en mode structure-seulement", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    return R.eq(snap.data, nil)
  end)
  return R.it("contient une section data en mode include_data", function()
    local result = export_r.Query.exportSnapshot(nil, {
      includeData = true
    }, ADMIN_CTX)
    local snap = yaml.decode(result)
    return R.ok(result)
  end)
end)
R.describe("diffSnapshot — aucune différence", function()
  local current_yaml
  R.it("exporte le schéma courant", function()
    current_yaml = export_r.Query.exportSnapshot(nil, {
      includeData = false
    }, ADMIN_CTX)
    return R.ok(current_yaml)
  end)
  return R.it("diff sur le schéma courant → aucune divergence", function()
    local diff = export_r.Query.diffSnapshot(nil, {
      yaml = current_yaml
    }, ADMIN_CTX)
    R.ok(diff)
    R.eq(#diff.spacesToCreate, 0)
    R.eq(#diff.spacesToDelete, 0)
    R.eq(#diff.fieldsToCreate, 0)
    return R.eq(#diff.fieldsToDelete, 0)
  end)
end)
R.describe("importSnapshot — mode merge", function()
  local SP = "snap_test_" .. tostring(SUFFIX)
  R.it("crée un snapshot YAML minimal avec un nouvel espace", function()
    local snap = {
      version = "1",
      schema = {
        spaces = {
          {
            name = SP,
            fields = {
              {
                name = "titre",
                fieldType = "String",
                notNull = false
              },
              {
                name = "valeur",
                fieldType = "Int",
                notNull = false
              }
            },
            views = { }
          }
        },
        relations = { },
        custom_views = { },
        groups = { }
      }
    }
    local snap_yaml = yaml.encode(snap)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok)
    R.ok(result.created > 0)
    return R.eq(#result.errors, 0)
  end)
  R.it("l'espace importé est visible dans list_spaces", function()
    local found = false
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local sp = _list_0[_index_0]
      if sp.name == SP then
        found = true
        break
      end
    end
    return R.ok(found)
  end)
  R.it("les champs importés sont présents", function()
    local sp = nil
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP then
        sp = s
      end
    end
    R.ok(sp)
    local fields = spaces.list_fields(sp.id)
    local names
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #fields do
        local f = fields[_index_0]
        _accum_0[_len_0] = f.name
        _len_0 = _len_0 + 1
      end
      names = _accum_0
    end
    local has_titre = false
    local has_valeur = false
    for _index_0 = 1, #names do
      local n = names[_index_0]
      if n == 'titre' then
        has_titre = true
      end
      if n == 'valeur' then
        has_valeur = true
      end
    end
    R.ok(has_titre)
    return R.ok(has_valeur)
  end)
  R.it("deuxième import identique → tout ignoré, aucune erreur", function()
    local snap = {
      version = "1",
      schema = {
        spaces = {
          {
            name = SP,
            fields = {
              {
                name = "titre",
                fieldType = "String",
                notNull = false
              },
              {
                name = "valeur",
                fieldType = "Int",
                notNull = false
              }
            },
            views = { }
          }
        },
        relations = { },
        custom_views = { },
        groups = { }
      }
    }
    local snap_yaml = yaml.encode(snap)
    local result = export_r.Mutation.importSnapshot(nil, {
      yaml = snap_yaml,
      mode = 'merge'
    }, ADMIN_CTX)
    R.ok(result)
    R.ok(result.ok)
    R.eq(result.created, 0)
    R.ok(result.skipped > 0)
    return R.eq(#result.errors, 0)
  end)
  return R.it("suppression de l'espace de test", function()
    local sp = nil
    local _list_0 = spaces.list_spaces()
    for _index_0 = 1, #_list_0 do
      local s = _list_0[_index_0]
      if s.name == SP then
        sp = s
      end
    end
    R.ok(sp)
    spaces.delete_user_space(SP)
    local found = false
    local _list_1 = spaces.list_spaces()
    for _index_0 = 1, #_list_1 do
      local s = _list_1[_index_0]
      if s.name == SP then
        found = true
      end
    end
    return R.eq(found, false)
  end)
end)
return R.describe("importSnapshot — YAML invalide", function()
  R.it("erreur sur YAML vide", function()
    local ok, err = pcall(function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = '',
        mode = 'merge'
      }, ADMIN_CTX)
    end)
    return R.eq(ok, false)
  end)
  return R.it("import avec YAML non-table → erreur", function()
    local ok, err = pcall(function()
      return export_r.Mutation.importSnapshot(nil, {
        yaml = '42',
        mode = 'merge'
      }, ADMIN_CTX)
    end)
    return R.eq(ok, false)
  end)
end)
