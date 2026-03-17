-- tests/test_resize_zone.moon
-- Tests for the resizeZone mutation

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
spaces = require 'core.spaces'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_resize_cv_#{SUFFIX}"
SPACE_NAME = "test_resize_space_#{SUFFIX}"

local cv_id, space_id
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "ResizeZone — setup test space", ->
  R.it "create test space for resize tests", ->
    space = spaces.create_user_space SPACE_NAME, 'Test space for resize', CTX.user_id
    R.ok space
    R.ok space.id
    R.eq space.name, SPACE_NAME
    space_id = space.id

    spaces.add_field space_id, 'id', 'Sequence'
    spaces.add_field space_id, 'name', 'String', false, ''

R.describe "ResizeZone — creation", ->
  R.it "createCustomView with zones", ->
    yaml_content = [[
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
              space: #{SPACE_NAME}
              position: 1
    - zone:
        id: zone2
        title: Second Zone
        factor: 0.5
        direction: vertical
        children: []
]]
    res = cvr.Mutation.createCustomView {}, { name: CV_NAME, description: 'test', yaml: yaml_content }, CTX
    R.ok res
    R.ok res.id
    cv_id = res.id

R.describe "ResizeZone — basic resizing", ->
  R.it "resizeZone changes zone factor", ->
    res = cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1', factor: 0.7 }, CTX
    R.ok res
    R.ok res.id

    view = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok view
    R.ok view.yaml

    R.ok view.yaml\find("factor: 0.7"), "zone1 should have factor 0.7"

  R.it "resizeZone recalculates sibling factors", ->
    res = cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1', factor: 0.8 }, CTX
    R.ok res

    view = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok view.yaml

    R.ok view.yaml\find("factor: 0.8"), "zone1 should have factor 0.8"

R.describe "ResizeZone — error handling", ->
  R.it "resizeZone on unknown page -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { pageId: 'no-such-id', zoneId: 'zone1', factor: 0.5 }, CTX), 'not found'

  R.it "resizeZone with unknown zone -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'unknown-zone', factor: 0.5 }, CTX), 'Zone not found'

  R.it "resizeZone with invalid factor < 0.1 -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1', factor: 0.05 }, CTX), 'factor must be between'

  R.it "resizeZone with invalid factor > 1.0 -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1', factor: 1.5 }, CTX), 'factor must be between'

  R.it "resizeZone with missing pageId -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { zoneId: 'zone1', factor: 0.5 }, CTX), 'pageId is required'

  R.it "resizeZone with missing zoneId -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { pageId: cv_id, factor: 0.5 }, CTX), 'zoneId is required'

  R.it "resizeZone with missing factor -> error", ->
    R.raises (-> cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1' }, CTX), 'factor is required'

R.describe "ResizeZone — edge cases", ->
  R.it "resizeZone with minimum factor 0.1", ->
    res = cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1', factor: 0.1 }, CTX
    R.ok res

    view = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok view.yaml\find("factor: 0.1"), "zone1 should have factor 0.1"

  R.it "resizeZone with maximum factor 1.0", ->
    res = cvr.Mutation.resizeZone {}, { pageId: cv_id, zoneId: 'zone1', factor: 1.0 }, CTX
    R.ok res

    view = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok view.yaml\find("factor: 1"), "zone1 should have factor 1"

R.describe "ResizeZone — cleanup", ->
  R.it "cleanup test space and page", ->
    if cv_id
      cvr.Mutation.deleteCustomView {}, { id: cv_id }, CTX
    if space_id
      spaces.delete_user_space space_id
