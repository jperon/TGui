local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local sorted_keys
sorted_keys = function(t)
  local ks = { }
  for k in pairs(t) do
    table.insert(ks, k)
  end
  table.sort(ks)
  return ks
end
return R.describe("CustomViewResolvers — API surface", function()
  R.it("Query exposes exactly the expected fields", function()
    local expected = {
      'customView',
      'customViews',
      'exportLayout',
      'listLayoutSnapshots'
    }
    return R.eq(table.concat(sorted_keys(cvr.Query), ','), table.concat(expected, ','))
  end)
  R.it("every Query field is a function", function()
    for k in pairs(cvr.Query) do
      R.eq(type(cvr.Query[k]), 'function', "Query." .. tostring(k))
    end
  end)
  R.it("Mutation exposes exactly the expected fields", function()
    local expected = {
      'addDataViewToPage',
      'addWidgetToView',
      'createCustomView',
      'createLayoutSnapshot',
      'createZone',
      'deleteCustomView',
      'importLayout',
      'mergeZones',
      'reorderWidgets',
      'resizeZone',
      'restoreLayoutSnapshot',
      'splitZone',
      'updateCustomView'
    }
    return R.eq(table.concat(sorted_keys(cvr.Mutation), ','), table.concat(expected, ','))
  end)
  return R.it("every Mutation field is a function", function()
    for k in pairs(cvr.Mutation) do
      R.eq(type(cvr.Mutation[k]), 'function', "Mutation." .. tostring(k))
    end
  end)
end)
