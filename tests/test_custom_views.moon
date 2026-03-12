-- tests/test_custom_views.moon
-- Tests CRUD operations on custom views (resolvers/custom_view_resolvers.moon).
-- Requires Tarantool (box already initialized in run.moon).

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'

SUFFIX  = tostring math.random(100000, 999999)
CV_NAME = "test_cv_#{SUFFIX}"

YAML_SIMPLE = [[
layout:
  direction: vertical
  children:
    - widget:
        title: Test
        space: test
]]

YAML_FACTOR = [[
layout:
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
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

R.describe "CustomViews — creation", ->
  R.it "createCustomView returns metadata", ->
    res = cvr.Mutation.createCustomView {}, { input: { name: CV_NAME, description: 'test', yaml: YAML_SIMPLE } }, CTX
    R.ok res
    R.ok res.id
    R.eq res.name, CV_NAME
    R.eq res.description, 'test'
    R.eq res.yaml, YAML_SIMPLE
    cv_id = res.id

  R.it "customViews list includes created view", ->
    found = false
    for v in *cvr.Query.customViews({}, {}, CTX)
      if v.id == cv_id then found = true
    R.ok found

  R.it "customView returns the view by id", ->
    v = cvr.Query.customView {}, { id: cv_id }, CTX
    R.ok v
    R.eq v.id, cv_id
    R.eq v.name, CV_NAME

R.describe "CustomViews — update", ->
  R.it "updateCustomView updates name and yaml", ->
    res = cvr.Mutation.updateCustomView {}, { id: cv_id, input: { name: CV_NAME .. '_v2', yaml: YAML_FACTOR } }, CTX
    R.ok res
    R.eq res.name, CV_NAME .. '_v2'
    R.eq res.yaml, YAML_FACTOR

  R.it "updateCustomView with partial fields keeps previous values", ->
    res = cvr.Mutation.updateCustomView {}, { id: cv_id, input: { name: CV_NAME .. '_v2' } }, CTX
    R.ok res
    R.eq res.yaml, YAML_FACTOR  -- yaml not provided -> preserved

  R.it "updateCustomView on unknown id -> error", ->
    R.raises (-> cvr.Mutation.updateCustomView {}, { id: 'no-such-id', input: { name: 'x' } }, CTX), 'not found'

R.describe "CustomViews — deletion", ->
  R.it "deleteCustomView returns true", ->
    ok = cvr.Mutation.deleteCustomView {}, { id: cv_id }, CTX
    R.ok ok

  R.it "deleted view no longer appears in list", ->
    found = false
    for v in *cvr.Query.customViews({}, {}, CTX)
      if v.id == cv_id then found = true
    R.nok found

  R.it "customView on deleted id returns nil", ->
    v = cvr.Query.customView {}, { id: cv_id }, CTX
    R.is_nil v
