-- tests/test_custom_view_resolvers_api.moon
-- Guards the public surface of resolvers/custom_view_resolvers.moon:
-- splitting the module into custom_view_* must not rename nor drop any
-- Query/Mutation field.

R   = require 'tests.runner'
cvr = require 'resolvers.custom_view_resolvers'

sorted_keys = (t) ->
  ks = {}
  for k in pairs t
    table.insert ks, k
  table.sort ks
  ks

R.describe "CustomViewResolvers — API surface", ->
  R.it "Query exposes exactly the expected fields", ->
    expected = { 'customView', 'customViews', 'exportLayout', 'listLayoutSnapshots' }
    R.eq table.concat(sorted_keys(cvr.Query), ','), table.concat(expected, ',')

  R.it "every Query field is a function", ->
    for k in pairs cvr.Query
      R.eq type(cvr.Query[k]), 'function', "Query.#{k}"

  R.it "Mutation exposes exactly the expected fields", ->
    expected = {
      'addDataViewToPage'
      'addWidgetToView'
      'createCustomView'
      'createLayoutSnapshot'
      'createZone'
      'deleteCustomView'
      'importLayout'
      'mergeZones'
      'reorderWidgets'
      'resizeZone'
      'restoreLayoutSnapshot'
      'splitZone'
      'updateCustomView'
    }
    R.eq table.concat(sorted_keys(cvr.Mutation), ','), table.concat(expected, ',')

  R.it "every Mutation field is a function", ->
    for k in pairs cvr.Mutation
      R.eq type(cvr.Mutation[k]), 'function', "Mutation.#{k}"
