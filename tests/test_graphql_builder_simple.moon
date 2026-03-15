-- tests/test_graphql_builder_simple.moon
-- Simple tests for GraphQL Builder functionality

describe "GraphQL Builder", ->
  it "should export GraphQLBuilder class", ->
    assert type(GraphQLBuilder) == 'function'

  it "should create GraphQL Builder instance", ->
    container = {}
    builder = GraphQLBuilder {
      container: container
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    assert type(builder) == 'table'
    assert builder.container == container

  it "should initialize with empty state", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    assert type(builder._selectedFields) == 'table'
    assert type(builder._computedFields) == 'table'
    assert type(builder._aggregations) == 'table'

  it "should set source space", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.setSourceSpace "123"
    assert builder._sourceSpaceId == "123"

  it "should select fields", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    assert builder._selectedFields["1.title"] == true

  it "should remove fields", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    builder.removeField "1", "title"
    assert builder._selectedFields["1.title"] == nil

  it "should add computed fields", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.addComputedField "display_name", "@name"
    assert builder._computedFields.display_name
    assert builder._computedFields.display_name.formula == "@name"

  it "should add aggregations", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.addAggregation "price", "AVG", "avg_price"
    assert #builder._aggregations == 1
    assert builder._aggregations[1].field == "price"

  it "should build basic query", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    query = builder.buildQuery()
    assert type(query) == 'string'
    assert query\find 'query GetData'

  it "should build aggregated query", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.setSourceSpace "1"
    builder.addAggregation "title", "COUNT", "book_count"
    query = builder.buildQuery()
    assert type(query) == 'string'
    assert query\find 'query GetAggregatedData'

  it "should detect list relations", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    assert builder.hasListRelations() == false
    
    builder._relationTypes["test.field"] = { type: 'List' }
    assert builder.hasListRelations() == true

  it "should get selected fields", ->
    builder = GraphQLBuilder {
      container: {}
      allSpaces: {}
      allRelations: {}
      onChange: ->
    }
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    builder.selectField "1", "author"
    
    selected = builder.getSelectedFields()
    assert #selected == 2
    assert selected[1].spaceId == "1"
    assert selected[1].fieldName == "title"
