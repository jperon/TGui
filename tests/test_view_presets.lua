local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local presets = require('core.view_presets')
local resolvers = require('resolvers.view_preset_resolvers')
local executor = require('graphql.executor')
local trusted_ctx
trusted_ctx = require('resolvers.utils').trusted_ctx
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "vp_space_" .. tostring(SUFFIX)
local OTHER_NAME = "vp_other_" .. tostring(SUFFIX)
local SCOPE_W = "widget:page_" .. tostring(SUFFIX) .. ":w1"
local SCOPE_W2 = "widget:page_" .. tostring(SUFFIX) .. ":w2"
local sp_id = nil
local other_id = nil
local scope_other = nil
local alpha_id = nil
return R.describe("ViewPresets — storage and scopes", function()
  R.it("creates two test spaces", function()
    local sp = spaces_mod.create_user_space(SP_NAME, 'view presets fixture')
    sp_id = sp.id
    local other = spaces_mod.create_user_space(OTHER_NAME, 'view presets other fixture')
    other_id = other.id
    scope_other = "space:" .. tostring(other_id)
    R.ok(sp_id)
    return R.ok(other_id)
  end)
  R.it("saves presets in one scope and in another scope of the same space", function()
    local a = presets.save_preset(SCOPE_W, sp_id, 'Alpha', '', nil)
    local b = presets.save_preset(SCOPE_W, sp_id, 'Bêta', 'self.age > 3', '[{"column":"age","ascending":false}]')
    local c = presets.save_preset(SCOPE_W2, sp_id, 'Alpha', 'self.role == "admin"', '[]')
    alpha_id = a.id
    R.ok(a.id)
    R.ok(b.id)
    R.eq(a.scope, SCOPE_W)
    R.eq(a.spaceId, sp_id)
    R.eq(a.filter, '')
    R.eq(a.sort, '[]')
    R.eq(b.filter, 'self.age > 3')
    R.eq(b.sort, '[{"column":"age","ascending":false}]')
    return R.eq(c.scope, SCOPE_W2)
  end)
  R.it("lists presets sorted by name and isolated per scope", function()
    local w = presets.list_presets(SCOPE_W)
    R.eq(#w, 2)
    R.eq(w[1].name, 'Alpha')
    R.eq(w[2].name, 'Bêta')
    local w2 = presets.list_presets(SCOPE_W2)
    R.eq(#w2, 1)
    R.eq(w2[1].name, 'Alpha')
    return R.eq(#presets.list_presets(SCOPE_W), 2)
  end)
  R.it("allows the same name in two different scopes", function()
    local w = presets.list_presets(SCOPE_W)
    local w2 = presets.list_presets(SCOPE_W2)
    return R.ne(w[1].id, w2[1].id)
  end)
  R.it("overwrites the preset stored under the same (scope, name)", function()
    local saved = presets.save_preset(SCOPE_W, sp_id, 'Alpha', 'self.x == 1', '[{"column":"x","ascending":true}]')
    R.eq(saved.id, alpha_id)
    R.eq(saved.filter, 'self.x == 1')
    R.eq(saved.sort, '[{"column":"x","ascending":true}]')
    return R.eq(#presets.list_presets(SCOPE_W), 2)
  end)
  R.it("refuses to move an existing preset to another space", function()
    R.raises((function()
      return presets.save_preset(SCOPE_W, other_id, 'Alpha', 'self.y == 2', '[]')
    end), 'belongs to another space')
    local kept = presets.get_preset(alpha_id)
    R.eq(kept.spaceId, sp_id)
    R.eq(kept.filter, 'self.x == 1')
    return R.eq(kept.sort, '[{"column":"x","ascending":true}]')
  end)
  R.it("rejects an invalid sort", function()
    R.raises((function()
      return presets.save_preset(SCOPE_W, sp_id, 'Bad1', '', 'not-json')
    end), 'Invalid sort JSON')
    R.raises((function()
      return presets.save_preset(SCOPE_W, sp_id, 'Bad2', '', '{"column":"x"}')
    end), 'Invalid sort')
    R.raises((function()
      return presets.save_preset(SCOPE_W, sp_id, 'Bad3', '', '[{"column":1,"ascending":true}]')
    end), 'column')
    R.raises((function()
      return presets.save_preset(SCOPE_W, sp_id, 'Bad4', '', '[{"column":"x","ascending":"yes"}]')
    end), 'ascending')
    local _list_0 = presets.list_presets(SCOPE_W)
    for _index_0 = 1, #_list_0 do
      local p = _list_0[_index_0]
      R.nok(p.name:match('^Bad'), 'no invalid preset stored')
    end
  end)
  R.it("rejects an empty name and an unknown space", function()
    R.raises((function()
      return presets.save_preset(SCOPE_W, sp_id, '   ', '', '[]')
    end), 'name')
    return R.raises((function()
      return presets.save_preset(SCOPE_W, 'missing-space-id', 'Nom', '', '[]')
    end), 'Space not found')
  end)
  R.it("deletes a preset by id", function()
    local p = presets.save_preset(SCOPE_W2, sp_id, 'ToDelete', '', '[]')
    R.ok(presets.delete_preset(p.id))
    R.is_nil(presets.get_preset(p.id))
    return R.nok(presets.delete_preset(p.id))
  end)
  R.it("keeps presets of another space out of a readable spaceId", function()
    local other = presets.save_preset(scope_other, other_id, 'Other', '', '[]')
    R.ok(other.id)
    local ctx = trusted_ctx('admin')
    local via_resolver = resolvers.Query.viewPresets(nil, {
      scope = scope_other,
      spaceId = sp_id
    }, ctx)
    return R.eq(#via_resolver, 0)
  end)
  R.it("exposes presets through GraphQL with the same isolation", function()
    require('resolvers.init').reinit()
    local ctx = trusted_ctx('admin')
    local q = 'query($s: String!, $id: ID!) { viewPresets(scope: $s, spaceId: $id) { id name scope spaceId filter sort createdAt } }'
    local res = executor.execute({
      query = q,
      variables = {
        s = SCOPE_W,
        id = sp_id
      },
      context = ctx
    })
    R.nok(res.errors, 'viewPresets query must succeed')
    R.eq(#res.data.viewPresets, 2)
    R.eq(res.data.viewPresets[1].name, 'Alpha')
    R.eq(res.data.viewPresets[1].scope, SCOPE_W)
    R.eq(res.data.viewPresets[1].spaceId, sp_id)
    R.ok(res.data.viewPresets[1].createdAt)
    local res_iso = executor.execute({
      query = q,
      variables = {
        s = scope_other,
        id = sp_id
      },
      context = ctx
    })
    R.nok(res_iso.errors, 'isolated viewPresets query must succeed')
    R.eq(#res_iso.data.viewPresets, 0)
    local m = 'mutation($s: String!, $id: ID!, $n: String!, $f: String, $o: String) { saveViewPreset(scope: $s, spaceId: $id, name: $n, filter: $f, sort: $o) { id name filter sort spaceId } }'
    local mres = executor.execute({
      query = m,
      variables = {
        s = SCOPE_W,
        id = sp_id,
        n = 'Gamma',
        f = 'self.n > 0',
        o = '[{"column":"n","ascending":true}]'
      },
      context = ctx
    })
    R.nok(mres.errors, 'saveViewPreset mutation must succeed')
    R.eq(mres.data.saveViewPreset.name, 'Gamma')
    R.eq(mres.data.saveViewPreset.filter, 'self.n > 0')
    R.eq(mres.data.saveViewPreset.spaceId, sp_id)
    local d = 'mutation($id: ID!) { deleteViewPreset(id: $id) }'
    local dres = executor.execute({
      query = d,
      variables = {
        id = mres.data.saveViewPreset.id
      },
      context = ctx
    })
    R.nok(dres.errors, 'deleteViewPreset mutation must succeed')
    return R.eq(dres.data.deleteViewPreset, true)
  end)
  R.it("cascades preset deletion when the space is deleted", function()
    local other = presets.save_preset(scope_other, other_id, 'Other', '', '[]')
    R.ok(other.id)
    R.eq(#presets.list_presets(scope_other), 1)
    spaces_mod.delete_user_space(OTHER_NAME)
    R.eq(#presets.list_presets(scope_other), 0)
    local _list_0 = box.space._tdb_view_presets.index.by_space:select({
      other_id
    })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      R.ok(false, 'no preset must remain for the deleted space')
    end
  end)
  return R.it("cleanup", function()
    local _list_0 = {
      SCOPE_W,
      SCOPE_W2
    }
    for _index_0 = 1, #_list_0 do
      local scope = _list_0[_index_0]
      local _list_1 = presets.list_presets(scope)
      for _index_1 = 1, #_list_1 do
        local p = _list_1[_index_1]
        presets.delete_preset(p.id)
      end
    end
    spaces_mod.delete_user_space(SP_NAME)
    R.eq(#presets.list_presets(SCOPE_W), 0)
    return R.eq(#presets.list_presets(SCOPE_W2), 0)
  end)
end)
