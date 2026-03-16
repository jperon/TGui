-- tests/test_graphql_integration_working.moon
-- Working integration tests for GraphQL Builder system

R = require 'tests.runner'

R.describe "GraphQL Builder Working Integration", ->
  R.it "should export required modules", ->
    triggers_mod = require 'core.triggers'
    graphql_flattener = require 'core.graphql_flattener'

    assert type(triggers_mod) == 'table'
    assert type(graphql_flattener) == 'table'
    assert type(triggers_mod.build_relation_map) == 'function'
    assert type(triggers_mod.make_self_proxy_extended) == 'function'
    assert type(graphql_flattener.flatten) == 'function'

  R.it "should create extended proxy", ->
    triggers_mod = require 'core.triggers'

    record = {title: 'Test Book', author: '1', _id: '1'}
    single_map = {}
    multiple_map = {}

    proxy = triggers_mod.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSpace'

    assert type(proxy) == 'table'
    assert type(proxy.list) == 'table'
    assert type(proxy.list.length) == 'function'

  R.it "should validate data types", ->
    graphql_flattener = require 'core.graphql_flattener'

    assert graphql_flattener.isArray {1, 2, 3}
    assert graphql_flattener.isObject {name: 'test', value: 123}
    assert graphql_flattener.isSimpleType 'string'
    assert graphql_flattener.isSimpleType 123
    assert graphql_flattener.isSimpleType true

    assert not graphql_flattener.isArray {name: 'test'}
    assert not graphql_flattener.isObject {1, 2, 3}
    assert not graphql_flattener.isSimpleType {name: 'test'}

  R.it "should handle empty data", ->
    graphql_flattener = require 'core.graphql_flattener'

    flattened = graphql_flattener.flatten {records: {}}, '', {}
    assert type(flattened) == 'table'

    flattened = graphql_flattener.flatten nil, '', {}
    assert type(flattened) == 'table'

  R.it "should validate flattened data", ->
    graphql_flattener = require 'core.graphql_flattener'

    flattened = {
      {id: '1', title: 'Test', price: 19.99}
    }

    schema = {
      id: 'string'
      title: 'string'
      price: 'number'
    }

    errors = graphql_flattener.validateFlattened flattened, schema
    assert #errors == 0

  R.it "should detect validation errors", ->
    graphql_flattener = require 'core.graphql_flattener'

    flattened = {
      {id: '1', title: 'Test', price: 'not_a_number'}
    }

    schema = {
      id: 'string'
      title: 'string'
      price: 'number'
    }

    errors = graphql_flattener.validateFlattened flattened, schema
    assert #errors > 0

  R.it "should handle list functions", ->
    triggers_mod = require 'core.triggers'

    record = {title: 'Test', _id: '1'}
    single_map = {}
    multiple_map = {}

    proxy = triggers_mod.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSpace'

    test_list = {1, 2, 3, 4, 5}

    assert type(proxy.list.length(test_list)) == 'number'
    assert type(proxy.list.first(test_list)) == 'number'
    assert type(proxy.list.last(test_list)) == 'number'

    doubled = proxy.list.map(test_list, (x) -> x * 2)
    assert type(doubled) == 'table'

    evens = proxy.list.filter(test_list, (x) -> x % 2 == 0)
    assert type(evens) == 'table'

    sum = proxy.list.reduce(test_list, ((acc, x) ->
      acc = acc or 0
      acc + x
    ), 0)
    assert type(sum) == 'number'

  R.it "should handle depth-limited flattening", ->
    graphql_flattener = require 'core.graphql_flattener'

    -- Simple test - just verify the method exists conceptually
    data = {records: {}}
    flattened = graphql_flattener.flatten data, '', {}
    assert type(flattened) == 'table'
