local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local CV_NAME = "test_cv_" .. tostring(SUFFIX)
local YAML_SIMPLE = [[layout:
  direction: vertical
  children:
    - widget:
        title: Test
        space: test
]]
local YAML_FACTOR = [[layout:
  direction: horizontal
  children:
    - factor: 2
      widget:
        title: A
        space: test
    - factor: 1
      widget:
        title: B
        space: test
        columns: [nom, prenom]
]]
local cv_id
R.describe("CustomViews — création", function()
  R.it("createCustomView retourne les métadonnées", function()
    local res = cvr.Mutation.createCustomView({ }, {
      input = {
        name = CV_NAME,
        description = 'test',
        yaml = YAML_SIMPLE
      }
    }, { })
    R.ok(res)
    R.ok(res.id)
    R.eq(res.name, CV_NAME)
    R.eq(res.description, 'test')
    R.eq(res.yaml, YAML_SIMPLE)
    cv_id = res.id
  end)
  R.it("customViews liste inclut la vue créée", function()
    local found = false
    local _list_0 = cvr.Query.customViews({ }, { }, { })
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      if v.id == cv_id then
        found = true
      end
    end
    return R.ok(found)
  end)
  return R.it("customView retourne la vue par id", function()
    local v = cvr.Query.customView({ }, {
      id = cv_id
    }, { })
    R.ok(v)
    R.eq(v.id, cv_id)
    return R.eq(v.name, CV_NAME)
  end)
end)
R.describe("CustomViews — mise à jour", function()
  R.it("updateCustomView modifie le nom et le yaml", function()
    local res = cvr.Mutation.updateCustomView({ }, {
      id = cv_id,
      input = {
        name = CV_NAME .. '_v2',
        yaml = YAML_FACTOR
      }
    }, { })
    R.ok(res)
    R.eq(res.name, CV_NAME .. '_v2')
    return R.eq(res.yaml, YAML_FACTOR)
  end)
  R.it("updateCustomView avec champs partiels conserve les anciens", function()
    local res = cvr.Mutation.updateCustomView({ }, {
      id = cv_id,
      input = {
        name = CV_NAME .. '_v2'
      }
    }, { })
    R.ok(res)
    return R.eq(res.yaml, YAML_FACTOR)
  end)
  return R.it("updateCustomView sur id inexistant → erreur", function()
    return R.raises((function()
      return cvr.Mutation.updateCustomView({ }, {
        id = 'no-such-id',
        input = {
          name = 'x'
        }
      }, { })
    end), 'not found')
  end)
end)
return R.describe("CustomViews — suppression", function()
  R.it("deleteCustomView retourne true", function()
    local ok = cvr.Mutation.deleteCustomView({ }, {
      id = cv_id
    }, { })
    return R.ok(ok)
  end)
  R.it("la vue supprimée n'apparaît plus dans la liste", function()
    local found = false
    local _list_0 = cvr.Query.customViews({ }, { }, { })
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      if v.id == cv_id then
        found = true
      end
    end
    return R.nok(found)
  end)
  return R.it("customView sur id supprimé retourne nil", function()
    local v = cvr.Query.customView({ }, {
      id = cv_id
    }, { })
    return R.is_nil(v)
  end)
end)
