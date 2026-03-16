local R = require('tests.runner')
return R.describe("GraphQL Builder Backend", function()
  R.it("should have GraphQL flattener available", function()
    local GraphQLFlattener = require('core.graphql_flattener')
    assert(type(GraphQLFlattener) == 'table')
    return assert(type(GraphQLFlattener.flatten) == 'function')
  end)
  R.it("should have triggers with extended proxy support", function()
    local triggers = require('core.triggers')
    assert(type(triggers) == 'table')
    assert(type(triggers.make_self_proxy_extended) == 'function')
    return assert(type(triggers.build_single_and_multiple_maps) == 'function')
  end)
  return R.it("should validate flattener functionality", function()
    local GraphQLFlattener = require('core.graphql_flattener')
    local data = {
      records = {
        id = '1',
        name = 'Test'
      }
    }
    local flattened = GraphQLFlattener.flatten(data, '', { })
    assert(type(flattened) == 'table')
    return assert(#flattened == 1)
  end)
end)
