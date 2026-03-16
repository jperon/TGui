-- tests/test_graphql_builder_simple.moon
-- Simple tests for GraphQL Builder functionality (backend only)

R = require 'tests.runner'

R.describe "GraphQL Builder Backend", ->
  R.it "should have GraphQL flattener available", ->
    GraphQLFlattener = require 'core.graphql_flattener'
    assert type(GraphQLFlattener) == 'table'
    assert type(GraphQLFlattener.flatten) == 'function'

  R.it "should have triggers with extended proxy support", ->
    triggers = require 'core.triggers'
    assert type(triggers) == 'table'
    assert type(triggers.make_self_proxy_extended) == 'function'
    assert type(triggers.build_single_and_multiple_maps) == 'function'

  R.it "should validate flattener functionality", ->
    GraphQLFlattener = require 'core.graphql_flattener'

    -- Test basic flattening
    data = {records: {id: '1', name: 'Test'}}
    flattened = GraphQLFlattener.flatten data, '', {}
    assert type(flattened) == 'table'
    assert #flattened == 1
