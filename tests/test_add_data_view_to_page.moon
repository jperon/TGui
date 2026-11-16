-- tests/test_add_data_view_to_page.moon
-- Tests the addDataViewToPage mutation.
-- Requires Tarantool (box already initialized in run.moon).

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'
auth = require 'core.auth'
spaces = require 'core.spaces'
data_views = require 'core.data_views'
yaml = require 'yaml'

SUFFIX  = tostring math.random(100000, 999999)
SPACE_NAME = "test_space_#{SUFFIX}"
DATA_VIEW_NAME = "test_dv_#{SUFFIX}"
CV_NAME = "test_cv_#{SUFFIX}"

-- Variables to share across tests
space_id = nil
dv_id = nil
cv_id = nil
ctx = nil

-- Simple YAML for an empty custom view
YAML_EMPTY = [[
layout:
  direction: vertical
  children: []
]]

R.describe "AddDataViewToPage — setup", ->
  R.it "create test space", ->
    space = spaces.create_user_space SPACE_NAME, 'Test space for data view'
    R.ok space
    R.ok space.id
    space_id = space.id

  R.it "create test data view", ->
    dv = data_views.create_view DATA_VIEW_NAME, 'Test data view', SPACE_NAME, '{}'
    R.ok dv
    R.ok dv.id
    dv_id = dv.id

  R.it "create empty custom view and context", ->
    admin = auth.get_user_by_username 'admin'
    ctx = { user_id: admin and admin.id }
    cv = cvr.Mutation.createCustomView {}, {
      name: CV_NAME
      description: 'test'
      yaml: YAML_EMPTY
    }, ctx
    R.ok cv
    R.ok cv.id
    R.eq cv.name, CV_NAME
    R.eq cv.yaml, YAML_EMPTY
    cv_id = cv.id

R.describe "AddDataViewToPage — mutation", ->
  R.it "successfully adds data view to page", ->
    -- Call the mutation
    res = cvr.Mutation.addDataViewToPage {}, { pageId: cv_id, dataViewId: dv_id }, ctx
    R.ok res
    R.eq res.id, cv_id
    R.eq res.name, CV_NAME
    R.ok res.yaml
    
    -- Verify the YAML contains a widget with the dataViewId field
    R.ok res.yaml\find("dataViewId:"), "YAML should contain the dataViewId"
    R.ok res.yaml\find("space: #{DATA_VIEW_NAME}"), "YAML should contain the data view name as space"

    -- Verify the widget is correctly structured
    R.ok res.yaml\find("- widget:"), "YAML should contain a widget entry"

    -- Le YAML généré doit être relisible (un titre contenant « : » est mis
    -- entre guillemets simples, sinon le document devient invalide).
    parsed = yaml.decode res.yaml
    widget = parsed.layout.children[1].widget
    R.eq widget.title, "Data View: #{DATA_VIEW_NAME}"
    R.eq widget.space, DATA_VIEW_NAME
    R.eq widget.dataViewId, dv_id

  R.it "returns error when pageId does not exist", ->
    R.raises (-> cvr.Mutation.addDataViewToPage {}, { pageId: 'non-existent-id', dataViewId: dv_id }, ctx), 'not found'

  R.it "returns error when dataViewId does not exist", ->
    R.raises (-> cvr.Mutation.addDataViewToPage {}, { pageId: cv_id, dataViewId: 'non-existent-id' }, ctx), 'not found'

R.describe "AddDataViewToPage — cleanup", ->
  R.it "delete custom view", ->
    if cv_id
      ok = cvr.Mutation.deleteCustomView {}, { id: cv_id }, ctx
      R.ok ok

  R.it "delete data view", ->
    if dv_id
      ok = data_views.delete_view dv_id
      R.ok ok

  R.it "delete test space", ->
    if space_id
      ok = spaces.delete_user_space SPACE_NAME
      R.ok ok
