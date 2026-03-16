local R = require('tests.runner')
local GraphQLFlattener = require('core.graphql_flattener')
return R.describe("GraphQL Flattener", function()
  R.it("should export GraphQLFlattener module", function()
    assert(type(GraphQLFlattener) == 'table')
    return assert(type(GraphQLFlattener.flatten) == 'function')
  end)
  R.it("should validate data types", function()
    assert(GraphQLFlattener.isArray({
      1,
      2,
      3
    }))
    assert(GraphQLFlattener.isObject({
      name = 'test',
      value = 123
    }))
    assert(GraphQLFlattener.isSimpleType('string'))
    assert(GraphQLFlattener.isSimpleType(123))
    return assert(GraphQLFlattener.isSimpleType(true))
  end)
  R.it("should validate flattener functionality", function()
    GraphQLFlattener = require('core.graphql_flattener')
    local data = {
      records = { }
    }
    local flattened = GraphQLFlattener.flatten(data, '', { })
    return assert(type(flattened) == 'table')
  end)
  R.it("should handle empty data", function()
    local flattened = GraphQLFlattener.flatten({
      records = { }
    }, '', { })
    assert(type(flattened) == 'table')
    flattened = GraphQLFlattener.flatten(nil, '', { })
    return assert(type(flattened) == 'table')
  end)
  R.it("should validate flattened data", function()
    local flattened = {
      {
        id = '1',
        title = 'Test',
        price = 19.99
      }
    }
    local schema = {
      id = 'string',
      title = 'string',
      price = 'number'
    }
    local errors = GraphQLFlattener.validateFlattened(flattened, schema)
    return assert(#errors == 0)
  end)
  return R.it("should detect validation errors", function()
    local flattened = {
      {
        id = '1',
        title = 'Test',
        price = 'not_a_number'
      }
    }
    local schema = {
      id = 'string',
      title = 'string',
      price = 'number'
    }
    local errors = GraphQLFlattener.validateFlattened(flattened, schema)
    return assert(#errors > 0)
  end)
end)
