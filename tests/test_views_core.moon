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

R.describe "core/views — update_view writes config_str", ->
  upd = { id: nil, name: "#{VIEW_NAME}_upd" }

  R.it "creates the view used by the update tests", ->
    v = views.create_view FIX.sid, upd.name, 'grid', VALID_CONFIG
    R.ok v
    upd.id = v.id
    table.insert FIX.created, v.id

  R.it "update_view with a new config replaces the stored config", ->
    new_config = { layout: { direction: 'horizontal', children: {} } }
    views.update_view upd.id, { config: new_config }
    row = box.space._tdb_views\get upd.id
    R.ok row, "row still present after update"
    decoded = json.decode row[5]
    R.eq decoded.layout.direction, 'horizontal'
    R.eq views.get_view(upd.id).config, row[5], "get_view returns the stored config"

  R.it "update_view without config keeps the stored config and updates the name", ->
    before_cfg = box.space._tdb_views\get(upd.id)[5]
    views.update_view upd.id, { name: "#{upd.name}_v2" }
    row = box.space._tdb_views\get upd.id
    R.eq row[3], "#{upd.name}_v2", "name updated"
    R.eq row[5], before_cfg, "config preserved when patch.config is absent"

R.describe "core/views — cleanup", ->
  R.it "removes the fixture view rows and the test space", ->
    for id in *FIX.created
      box.space._tdb_views\delete id
    spaces.delete_user_space SPACE_NAME
