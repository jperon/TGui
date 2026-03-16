describe "GraphQL Builder Minimal", ->
  it "should export GraphQLBuilder class", ->
    assert type(GraphQLBuilder) == 'function'

  it "should create GraphQL Builder", ->
    container = document.createElement('div')
    builder = new GraphQLBuilder {
      container: container
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    assert builder instanceof GraphQLBuilder

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

  it "should set source space", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    builder.setSourceSpace "123"
    assert builder._sourceSpaceId == "123"

  it "should select fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    builder.setSourceSpace "1"
    builder.selectField "1", "title"
    assert builder._selectedFields["1.title"] == true

  it "should add computed fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: []
      allRelations: []
      onChange: ->
    }
    builder.addComputedField "display_name", "@name"
    assert builder._computedFields.display_name
    assert builder._computedFields.display_name.formula == "@name"

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
