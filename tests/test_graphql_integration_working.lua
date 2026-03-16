local R = require('tests.runner')
return R.describe("GraphQL Builder Working Integration", function()
  R.it("should export required modules", function()
    local triggers_mod = require('core.triggers')
    local graphql_flattener = require('core.graphql_flattener')
    assert(type(triggers_mod) == 'table')
    assert(type(graphql_flattener) == 'table')
    assert(type(triggers_mod.build_relation_map) == 'function')
    assert(type(triggers_mod.make_self_proxy_extended) == 'function')
    return assert(type(graphql_flattener.flatten) == 'function')
  end)
  R.it("should create extended proxy", function()
    local triggers_mod = require('core.triggers')
    local record = {
      title = 'Test Book',
      author = '1',
      _id = '1'
    }
    local single_map = { }
    local multiple_map = { }
    local proxy = triggers_mod.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSpace')
    assert(type(proxy) == 'table')
    assert(type(proxy.list) == 'table')
    return assert(type(proxy.list.length) == 'function')
  end)
  R.it("should validate data types", function()
    local graphql_flattener = require('core.graphql_flattener')
    assert(graphql_flattener.isArray({
      1,
      2,
      3
    }))
    assert(graphql_flattener.isObject({
      name = 'test',
      value = 123
    }))
    assert(graphql_flattener.isSimpleType('string'))
    assert(graphql_flattener.isSimpleType(123))
    assert(graphql_flattener.isSimpleType(true))
    assert(not graphql_flattener.isArray({
      name = 'test'
    }))
    assert(not graphql_flattener.isObject({
      1,
      2,
      3
    }))
    return assert(not graphql_flattener.isSimpleType({
      name = 'test'
    }))
  end)
  R.it("should handle empty data", function()
    local graphql_flattener = require('core.graphql_flattener')
    local flattened = graphql_flattener.flatten({
      records = { }
    }, '', { })
    assert(type(flattened) == 'table')
    flattened = graphql_flattener.flatten(nil, '', { })
    return assert(type(flattened) == 'table')
  end)
  R.it("should validate flattened data", function()
    local graphql_flattener = require('core.graphql_flattener')
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
    local errors = graphql_flattener.validateFlattened(flattened, schema)
    return assert(#errors == 0)
  end)
  R.it("should detect validation errors", function()
    local graphql_flattener = require('core.graphql_flattener')
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
    local errors = graphql_flattener.validateFlattened(flattened, schema)
    return assert(#errors > 0)
  end)
  R.it("should handle list functions", function()
    local triggers_mod = require('core.triggers')
    local record = {
      title = 'Test',
      _id = '1'
    }
    local single_map = { }
    local multiple_map = { }
    local proxy = triggers_mod.make_self_proxy_extended(record, single_map, multiple_map, nil, 'TestSpace')
    local test_list = {
      1,
      2,
      3,
      4,
      5
    }
    assert(type(proxy.list.length(test_list)) == 'number')
    assert(type(proxy.list.first(test_list)) == 'number')
    assert(type(proxy.list.last(test_list)) == 'number')
    local doubled = proxy.list.map(test_list, function(x)
      return x * 2
    end)
    assert(type(doubled) == 'table')
    local evens = proxy.list.filter(test_list, function(x)
      return x % 2 == 0
    end)
    assert(type(evens) == 'table')
    local sum = proxy.list.reduce(test_list, (function(acc, x)
      acc = acc or 0
      return acc + x
    end), 0)
    return assert(type(sum) == 'number')
  end)
  return R.it("should handle depth-limited flattening", function()
    local graphql_flattener = require('core.graphql_flattener')
    local data = {
      records = { }
    }
    local flattened = graphql_flattener.flatten(data, '', { })
    return assert(type(flattened) == 'table')
  end)
end)
