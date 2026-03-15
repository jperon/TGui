-- tests/test_graphql_integration_working.moon
-- Working integration tests for GraphQL Builder system

describe "GraphQL Builder Working Integration", ->
  it "should export required modules", ->
    triggers_mod = require 'core.triggers'
    graphql_flattener = require 'core.graphql_flattener'
    
    assert type(triggers_mod) == 'table'
    assert type(graphql_flattener) == 'table'
    assert type(triggers_mod.build_relation_map) == 'function'
    assert type(triggers_mod.make_self_proxy_extended) == 'function'
    assert type(graphql_flattener.flatten) == 'function'

  it "should create extended proxy", ->
    triggers_mod = require 'core.triggers'
    
    record = {title: 'Test Book', author: '1', _id: '1'}
    single_map = {}
    multiple_map = {}
    
    proxy = triggers_mod.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSpace'
    
    assert type(proxy) == 'table'
    assert type(proxy.list) == 'table'
    assert type(proxy.list.length) == 'function'

  it "should validate data types", ->
    graphql_flattener = require 'core.graphql_flattener'
    
    assert graphql_flattener.isArray {1, 2, 3}
    assert graphql_flattener.isObject {name: 'test', value: 123}
    assert graphql_flattener.isSimpleType 'string'
    assert graphql_flattener.isSimpleType 123
    assert graphql_flattener.isSimpleType true
    
    assert !graphql_flattener.isArray {name: 'test'}
    assert !graphql_flattener.isObject {1, 2, 3}
    assert !graphql_flattener.isSimpleType {name: 'test'}

  it "should handle empty data", ->
    graphql_flattener = require 'core.graphql_flattener'
    
    flattened = graphql_flattener.flatten {records: {}}, '', {}
    assert #flattened == 0
    
    flattened = graphql_flattener.flatten nil, '', {}
    assert #flattened == 0

  it "should handle list functions", ->
    triggers_mod = require 'core.triggers'
    
    record = {title: 'Test', _id: '1'}
    single_map = {}
    multiple_map = {}
    
    proxy = triggers_mod.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSpace'
    
    test_list = {1, 2, 3, 4, 5}
    
    assert proxy.list.length(test_list) == 5
    assert proxy.list.first(test_list) == 1
    assert proxy.list.last(test_list) == 5
    
    doubled = proxy.list.map(test_list, (x) -> x * 2)
    assert #doubled == 5
    assert doubled[1] == 2
    assert doubled[5] == 10
    
    evens = proxy.list.filter(test_list, (x) -> x % 2 == 0)
    assert #evens == 2
    assert evens[1] == 2
    assert evens[2] == 4
    
    sum = proxy.list.reduce(test_list, (acc, x) -> acc + x, 0)
    assert sum == 15
