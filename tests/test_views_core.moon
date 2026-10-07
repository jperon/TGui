-- tests/test_views_core.moon
-- Non-regression tests for the two bugs of core/views.moon (task T5).
-- Plan: docs/superpowers/plans/2026-10-07-etape-2-integrite-donnees.md,
-- section « T5 : bugs de core/views.moon ».

R = require 'tests.runner'
spaces = require 'core.spaces'
views = require 'core.views'
json = require 'json'

SUFFIX = tostring math.random(100000, 999999)
SPACE_NAME = "test_views_core_#{SUFFIX}"
VIEW_NAME = "tvc_#{SUFFIX}"

VALID_CONFIG = { layout: { direction: 'vertical', children: {} } }

FIX = { sid: nil, created: {} }

R.describe "core/views — fixture", ->
  R.it "creates the test space", ->
    sp = spaces.create_user_space SPACE_NAME, 'fixture for core/views tests'
    R.ok sp
    R.ok sp.id
    FIX.sid = sp.id

R.describe "core/views — create_view validates its config", ->
  R.it "create_view with a valid config inserts the row", ->
    v = views.create_view FIX.sid, VIEW_NAME, 'grid', VALID_CONFIG
    R.ok v, "create_view must return the created view"
    R.ok v.id, "created view id"
    R.eq v.name, VIEW_NAME
    R.eq v.viewType, 'grid'
    R.eq v.spaceId, FIX.sid
    row = box.space._tdb_views\get v.id
    R.ok row, "row present in _tdb_views"
    decoded = json.decode row[5]
    R.eq decoded.layout.direction, 'vertical'
    table.insert FIX.created, v.id

  R.it "create_view with an invalid config raises the validation message", ->
    R.raises (-> views.create_view FIX.sid, "#{VIEW_NAME}_bad", 'grid', {}), 'layout'

R.describe "core/views — cleanup", ->
  R.it "removes the fixture view rows and the test space", ->
    for id in *FIX.created
      box.space._tdb_views\delete id
    spaces.delete_user_space SPACE_NAME
