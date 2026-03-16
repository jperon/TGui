# tests/test_graphql_builder_basic.coffee
# Basic tests for GraphQL Builder

describe "GraphQL Builder Basic", ->
  it "should export GraphQLBuilder class", ->
    assert type(GraphQLBuilder) == 'function'
    assert GraphQLBuilder.name == 'GraphQLBuilder'

  it "should create GraphQL Builder with minimal options", ->
    container = document.createElement('div')
    builder = new GraphQLBuilder {
      container: container
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    assert builder instanceof GraphQLBuilder
    assert builder.container == container

  it "should initialize with empty state", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    assert type(builder._selectedFields) == 'table'
    assert type(builder._computedFields) == 'table'
    assert type(builder._aggregations) == 'table'
    assert type(builder._relationTypes) == 'table'
    assert builder._sourceSpaceId == null

  it "should set source space", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.setSourceSpace "123"
    assert builder._sourceSpaceId == "123"

  it "should select and remove fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    
    # Select field
    builder.selectField "1", "title"
    assert builder._selectedFields["1.title"] == true
    
    # Remove field
    builder.removeField "1", "title"
    assert builder._selectedFields["1.title"] == nil

  it "should add computed fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.addComputedField "display_name", "@name .. ' test'"
    assert builder._computedFields.display_name
    assert builder._computedFields.display_name.formula == "@name .. ' test'"
    assert builder._computedFields.display_name.language == 'moonscript'

  it "should add aggregations", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.addAggregation "price", "AVG", "avg_price"
    assert builder._aggregations.length == 1
    assert builder._aggregations[0].field == "price"
    assert builder._aggregations[0].func == "AVG"
    assert builder._aggregations[0].as == "avg_price"

  it "should build basic query", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    
    query = builder.buildQuery()
    assert type(query) == 'string'
    assert query.includes('query GetData')
    assert query.includes('records(spaceId: "1")')
    assert query.includes('title')

  it "should build aggregated query", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.addAggregation "title", "COUNT", "book_count"
    
    query = builder.buildQuery()
    assert type(query) == 'string'
    assert query.includes('query GetAggregatedData')
    assert query.includes('aggregatedRecords')
    assert query.includes('COUNT')

  it "should detect list relations", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    # Initially no list relations
    assert !builder.hasListRelations()
    
    # Add a list relation
    builder._relationTypes["test.field"] = { type: 'List' }
    assert builder.hasListRelations()

  it "should get selected fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    builder.selectField "1", "author"
    
    selected = builder.getSelectedFields()
    assert selected.length == 2
    assert selected[0].spaceId == "1"
    assert selected[0].fieldName == "title"
    assert selected[1].spaceId == "1"
    assert selected[1].fieldName == "author"

  it "should get target fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    
    fields = builder.getTargetFields "TestSpace"
    assert type(fields) == 'string'
