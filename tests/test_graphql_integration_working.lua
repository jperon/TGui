return describe("GraphQL Builder Working Integration", function()
  it("should export required modules", function()
    local triggers_mod = require('core.triggers')
    local graphql_flattener = require('core.graphql_flattener')
    assert(type(triggers_mod) == 'table')
    assert(type(graphql_flattener) == 'table')
    assert(type(triggers_mod.build_relation_map) == 'function')
    assert(type(triggers_mod.make_self_proxy_extended) == 'function')
    return assert(type(graphql_flattener.flatten) == 'function')
  end)
  it("should create extended proxy", function()
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
  it("should validate data types", function()
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
    assert()(graphql_flattener.isArray({
      name = 'test'
    }))
    assert()(graphql_flattener.isObject({
      1,
      2,
      3
    }))
    return assert()(graphql_flattener.isSimpleType({
      name = 'test'
    }))
  end)
  it("should handle empty data", function()
    local graphql_flattener = require('core.graphql_flattener')
    local flattened = graphql_flattener.flatten({
      records = { }
    }, '', { })
    assert(#flattened == 0)
    flattened = graphql_flattener.flatten(nil, '', { })
    return assert(#flattened == 0)
  end)
  return it("should handle list functions", function()
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
    assert(proxy.list.length(test_list) == 5)
    assert(proxy.list.first(test_list) == 1)
    assert(proxy.list.last(test_list) == 5)
    local doubled = proxy.list.map(test_list, function(x)
      return x * 2
    end)
    assert(#doubled == 5)
    assert(doubled[1] == 2)
    assert(doubled[5] == 10)
    local evens = proxy.list.filter(test_list, function(x)
      return x % 2 == 0
    end)
    assert(#evens == 2)
    assert(evens[1] == 2)
    assert(evens[2] == 4)
    local sum = proxy.list.reduce(test_list, function(acc, x)
      return acc + x, 0
    end)
    return assert(sum == 15)
  end)
end)
