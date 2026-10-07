-- tests/test_zone_merge_split.moon
-- Tests for the mergeZones and splitZone mutations.

R    = require 'tests.runner'
cvr  = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
yaml = require 'yaml'

SUFFIX = tostring math.random(100000, 999999)

admin = auth.get_user_by_username 'admin'
CTX_ADMIN = { user_id: admin and admin.id }

-- Real non-admin user (stored), so require_perm evaluates it and refuses.
NO_PERM_USER = auth.create_user "zoneu_#{SUFFIX}", "zoneu_#{SUFFIX}@test.local", "pass1234"
CTX_NOPERM = { user_id: NO_PERM_USER.id }

YAML_TWO_ZONES = [[
layout:
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

YAML_ONE_ZONE = [[
layout:
  direction: vertical
  children:
    - zone:
        id: zoneA
        title: Alone Zone
        factor: 0.6
        direction: vertical
        children: []
]]

-- Counts zone entries recursively in a decoded layout children list.
count_zones = (children) ->
  n = 0
  for child in *children
    if child.zone
      n += 1
      if child.zone.children and type(child.zone.children) == 'table'
        n += count_zones child.zone.children
  n

zones_in_view = (view) ->
  config = yaml.decode view.yaml
  count_zones config.layout.children

R.describe "ZoneMergeSplit — API surface", ->
  R.it "mergeZones is registered in Mutation", ->
    R.eq type(cvr.Mutation.mergeZones), 'function'

  R.it "splitZone is registered in Mutation", ->
    R.eq type(cvr.Mutation.splitZone), 'function'

R.describe "ZoneMergeSplit — mergeZones", ->
  merge_id = nil

  R.it "setup page with two adjacent zones", ->
    res = cvr.Mutation.createCustomView {}, {
      name: "merge_cv_#{SUFFIX}"
      description: 'merge test'
      yaml: YAML_TWO_ZONES
    }, CTX_ADMIN
    R.ok res
    R.ok res.id
    merge_id = res.id
    R.eq zones_in_view(res), 2

  R.it "mergeZones of two sibling zones leaves a single zone", ->
    res = cvr.Mutation.mergeZones {}, {
      pageId: merge_id
      zoneId1: 'zone1'
      zoneId2: 'zone2'
    }, CTX_ADMIN
    R.ok res
    R.ok res.yaml
    R.eq zones_in_view(res), 1
    R.ok res.yaml\find('widget1'), "merged zone keeps the original children"

  R.it "cleanup merged page", ->
    R.eq cvr.Mutation.deleteCustomView({}, { id: merge_id }, CTX_ADMIN), true

R.describe "ZoneMergeSplit — splitZone", ->
  split_id = nil

  R.it "setup page with one zone", ->
    res = cvr.Mutation.createCustomView {}, {
      name: "split_cv_#{SUFFIX}"
      description: 'split test'
      yaml: YAML_ONE_ZONE
    }, CTX_ADMIN
    R.ok res
    R.ok res.id
    split_id = res.id
    R.eq zones_in_view(res), 1

  R.it "splitZone of one zone yields two zones", ->
    res = cvr.Mutation.splitZone {}, {
      pageId: split_id
      zoneId: 'zoneA'
      direction: 'vertical'
    }, CTX_ADMIN
    R.ok res
    R.ok res.yaml
    R.eq zones_in_view(res), 2

  R.it "cleanup split page", ->
    R.eq cvr.Mutation.deleteCustomView({}, { id: split_id }, CTX_ADMIN), true

R.describe "ZoneMergeSplit — permissions", ->
  perm_id = nil

  R.it "setup page for permission checks", ->
    res = cvr.Mutation.createCustomView {}, {
      name: "perm_cv_#{SUFFIX}"
      description: 'perm test'
      yaml: YAML_TWO_ZONES
    }, CTX_ADMIN
    R.ok res
    perm_id = res.id

  R.it "mergeZones refuses a user without write permission", ->
    R.raises (-> cvr.Mutation.mergeZones {}, {
      pageId: perm_id
      zoneId1: 'zone1'
      zoneId2: 'zone2'
    }, CTX_NOPERM), 'Forbidden'

  R.it "splitZone refuses a user without write permission", ->
    R.raises (-> cvr.Mutation.splitZone {}, {
      pageId: perm_id
      zoneId: 'zone1'
      direction: 'vertical'
    }, CTX_NOPERM), 'Forbidden'

  R.it "admin can mergeZones", ->
    res = cvr.Mutation.mergeZones {}, {
      pageId: perm_id
      zoneId1: 'zone1'
      zoneId2: 'zone2'
    }, CTX_ADMIN
    R.ok res
    R.eq zones_in_view(res), 1

  R.it "admin can splitZone", ->
    res = cvr.Mutation.splitZone {}, {
      pageId: perm_id
      zoneId: 'zone1'
      direction: 'horizontal'
    }, CTX_ADMIN
    R.ok res
    R.eq zones_in_view(res), 2

  R.it "cleanup permission page and user", ->
    R.eq cvr.Mutation.deleteCustomView({}, { id: perm_id }, CTX_ADMIN), true
    box.space._tdb_users\delete NO_PERM_USER.id
