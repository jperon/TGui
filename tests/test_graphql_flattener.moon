-- tests/test_graphql_flattener.moon
-- Tests for GraphQL Flattener with list support

R = require 'tests.runner'
GraphQLFlattener = require 'core.graphql_flattener'

R.describe "GraphQL Flattener", ->
  R.it "should export GraphQLFlattener module", ->
    assert type(GraphQLFlattener) == 'table'
    assert type(GraphQLFlattener.flatten) == 'function'

  R.it "should validate data types", ->
    assert GraphQLFlattener.isArray {1, 2, 3}
    assert GraphQLFlattener.isObject {name: 'test', value: 123}
    assert GraphQLFlattener.isSimpleType 'string'
    assert GraphQLFlattener.isSimpleType 123
    assert GraphQLFlattener.isSimpleType true

  R.it "should validate flattener functionality", ->
    GraphQLFlattener = require 'core.graphql_flattener'

    -- Test basic flattening with simple data
    data = {records: {}}
    flattened = GraphQLFlattener.flatten data, '', {}
    assert type(flattened) == 'table'

  R.it "should handle empty data", ->
    flattened = GraphQLFlattener.flatten {records: {}}, '', {}
    assert type(flattened) == 'table'

    flattened = GraphQLFlattener.flatten nil, '', {}
    assert type(flattened) == 'table'

  R.it "should validate flattened data", ->
    flattened = {
      {id: '1', title: 'Test', price: 19.99}
    }

    schema = {
      id: 'string'
      title: 'string'
      price: 'number'
    }

    errors = GraphQLFlattener.validateFlattened flattened, schema
    assert #errors == 0

  R.it "should detect validation errors", ->
    flattened = {
      {id: '1', title: 'Test', price: 'not_a_number'}
    }

    schema = {
      id: 'string'
      title: 'string'
      price: 'number'
    }

    errors = GraphQLFlattener.validateFlattened flattened, schema
    assert #errors > 0
