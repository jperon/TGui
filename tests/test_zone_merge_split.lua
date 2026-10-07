local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local admin = auth.get_user_by_username('admin')
local CTX_ADMIN = {
  user_id = admin and admin.id
}
local NO_PERM_USER = auth.create_user("zoneu_" .. tostring(SUFFIX), "zoneu_" .. tostring(SUFFIX) .. "@test.local", "pass1234")
local CTX_NOPERM = {
  user_id = NO_PERM_USER.id
}
local YAML_TWO_ZONES = [[layout:
  direction: vertical
  children:
    - zone:
        id: zone1
        title: First Zone
        factor: 0.5
        direction: vertical
        children:
          - widget:
              id: widget1
              title: Widget 1
              space: test
              position: 1
    - zone:
        id: zone2
        title: Second Zone
        factor: 0.5
        direction: vertical
        children: []
]]
local YAML_ONE_ZONE = [[layout:
  direction: vertical
  children:
    - zone:
        id: zoneA
        title: Alone Zone
        factor: 0.6
        direction: vertical
        children: []
]]
local count_zones
count_zones = function(children)
  local n = 0
  for _index_0 = 1, #children do
    local child = children[_index_0]
    if child.zone then
      n = n + 1
      if child.zone.children and type(child.zone.children) == 'table' then
        n = n + count_zones(child.zone.children)
      end
    end
  end
  return n
end
local zones_in_view
zones_in_view = function(view)
  local config = yaml.decode(view.yaml)
  return count_zones(config.layout.children)
end
R.describe("ZoneMergeSplit — API surface", function()
  R.it("mergeZones is registered in Mutation", function()
    return R.eq(type(cvr.Mutation.mergeZones), 'function')
  end)
  return R.it("splitZone is registered in Mutation", function()
    return R.eq(type(cvr.Mutation.splitZone), 'function')
  end)
end)
R.describe("ZoneMergeSplit — mergeZones", function()
  local merge_id = nil
  R.it("setup page with two adjacent zones", function()
    local res = cvr.Mutation.createCustomView({ }, {
      name = "merge_cv_" .. tostring(SUFFIX),
      description = 'merge test',
      yaml = YAML_TWO_ZONES
    }, CTX_ADMIN)
    R.ok(res)
    R.ok(res.id)
    merge_id = res.id
    return R.eq(zones_in_view(res), 2)
  end)
  R.it("mergeZones of two sibling zones leaves a single zone", function()
    local res = cvr.Mutation.mergeZones({ }, {
      pageId = merge_id,
      zoneId1 = 'zone1',
      zoneId2 = 'zone2'
    }, CTX_ADMIN)
    R.ok(res)
    R.ok(res.yaml)
    R.eq(zones_in_view(res), 1)
    return R.ok(res.yaml:find('widget1'), "merged zone keeps the original children")
  end)
  return R.it("cleanup merged page", function()
    return R.eq(cvr.Mutation.deleteCustomView({ }, {
      id = merge_id
    }, CTX_ADMIN), true)
  end)
end)
R.describe("ZoneMergeSplit — splitZone", function()
  local split_id = nil
  R.it("setup page with one zone", function()
    local res = cvr.Mutation.createCustomView({ }, {
      name = "split_cv_" .. tostring(SUFFIX),
      description = 'split test',
      yaml = YAML_ONE_ZONE
    }, CTX_ADMIN)
    R.ok(res)
    R.ok(res.id)
    split_id = res.id
    return R.eq(zones_in_view(res), 1)
  end)
  R.it("splitZone of one zone yields two zones", function()
    local res = cvr.Mutation.splitZone({ }, {
      pageId = split_id,
      zoneId = 'zoneA',
      direction = 'vertical'
    }, CTX_ADMIN)
    R.ok(res)
    R.ok(res.yaml)
    return R.eq(zones_in_view(res), 2)
  end)
  return R.it("cleanup split page", function()
    return R.eq(cvr.Mutation.deleteCustomView({ }, {
      id = split_id
    }, CTX_ADMIN), true)
  end)
end)
return R.describe("ZoneMergeSplit — permissions", function()
  local perm_id = nil
  R.it("setup page for permission checks", function()
    local res = cvr.Mutation.createCustomView({ }, {
      name = "perm_cv_" .. tostring(SUFFIX),
      description = 'perm test',
      yaml = YAML_TWO_ZONES
    }, CTX_ADMIN)
    R.ok(res)
    perm_id = res.id
  end)
  R.it("mergeZones refuses a user without write permission", function()
    return R.raises((function()
      return cvr.Mutation.mergeZones({ }, {
        pageId = perm_id,
        zoneId1 = 'zone1',
        zoneId2 = 'zone2'
      }, CTX_NOPERM)
    end), 'Forbidden')
  end)
  R.it("splitZone refuses a user without write permission", function()
    return R.raises((function()
      return cvr.Mutation.splitZone({ }, {
        pageId = perm_id,
        zoneId = 'zone1',
        direction = 'vertical'
      }, CTX_NOPERM)
    end), 'Forbidden')
  end)
  R.it("admin can mergeZones", function()
    local res = cvr.Mutation.mergeZones({ }, {
      pageId = perm_id,
      zoneId1 = 'zone1',
      zoneId2 = 'zone2'
    }, CTX_ADMIN)
    R.ok(res)
    return R.eq(zones_in_view(res), 1)
  end)
  R.it("admin can splitZone", function()
    local res = cvr.Mutation.splitZone({ }, {
      pageId = perm_id,
      zoneId = 'zone1',
      direction = 'horizontal'
    }, CTX_ADMIN)
    R.ok(res)
    return R.eq(zones_in_view(res), 2)
  end)
  return R.it("cleanup permission page and user", function()
    R.eq(cvr.Mutation.deleteCustomView({ }, {
      id = perm_id
    }, CTX_ADMIN), true)
    return box.space._tdb_users:delete(NO_PERM_USER.id)
  end)
end)
