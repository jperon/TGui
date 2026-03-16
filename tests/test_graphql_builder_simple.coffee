# tests/test_graphql_builder_simple.coffee
# Tests for GraphQL Builder with list support

describe "GraphQL Builder", ->
  beforeEach ->
    @spaces = [
      {
        id: "1"
        name: "Books"
        fields: [
          { id: "1", name: "id", fieldType: "String" }
          { id: "2", name: "title", fieldType: "String" }
          { id: "3", name: "author", fieldType: "Relation" }
        ]
      }
      {
        id: "2"
        name: "Authors"
        fields: [
          { id: "4", name: "id", fieldType: "String" }
          { id: "5", name: "name", fieldType: "String" }
        ]
      }
    ]
    
    @relations = [
      {
        fromFieldId: "3"
        toSpaceId: "2"
        toFieldId: "4"
        fromSpace: { name: "Books", id: "1" }
        toSpace: { name: "Authors", id: "2" }
        fromField: { name: "author", id: "3" }
        toField: { name: "id", id: "4" }
      }
    ]

  it "should create GraphQL Builder instance", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    assert builder instanceof GraphQLBuilder
    assert type(builder._selectedFields) == 'table'
    assert type(builder._computedFields) == 'table'
    assert type(builder._aggregations) == 'table'

  it "should load relation types correctly", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.loadRelationTypes @spaces, @relations
    
    # Should detect author relation
    authorRelation = builder._relationTypes["Books.author"]
    assert authorRelation
    assert authorRelation.type == 'Single'
    assert authorRelation.targetSpace == 'Authors'
    assert authorRelation.targetField == 'id'

  it "should select and remove fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.loadRelationTypes @spaces, @relations
    
    # Select fields
    builder.selectField "1", "title"
    builder.selectField "1", "author"
    
    selected = builder.getSelectedFields()
    assert selected.length == 2
    assert selected[0].spaceId == "1"
    assert selected[0].fieldName == "title"
    
    # Remove field
    builder.removeField "1", "title"
    
    selected = builder.getSelectedFields()
    assert selected.length == 1
    assert selected[0].fieldName == "author"

  it "should build standard GraphQL query", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.loadRelationTypes @spaces, @relations
    
    # Select fields
    builder.selectField "1", "title"
    builder.selectField "1", "author"
    
    query = builder.buildQuery()
    
    assert type(query) == 'string'
    assert query.includes('query GetData')
    assert query.includes('records(spaceId: "1")')
    assert query.includes('title')
    assert query.includes('author')

  it "should add computed fields", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.addComputedField "display_title", "@title .. ' test'"
    
    assert builder._computedFields.display_title
    assert builder._computedFields.display_title.formula == "@title .. ' test'"

  it "should add aggregations", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.addAggregation "price", "AVG", "avg_price"
    
    assert builder._aggregations.length == 1
    assert builder._aggregations[0].field == "price"
    assert builder._aggregations[0].func == "AVG"
    assert builder._aggregations[0].as == "avg_price"

  it "should build aggregated query", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.loadRelationTypes @spaces, @relations
    
    # Add aggregation
    builder.addAggregation "title", "COUNT", "book_count"
    
    query = builder.buildQuery()
    
    assert type(query) == 'string'
    assert query.includes('query GetAggregatedData')
    assert query.includes('aggregatedRecords')
    assert query.includes('COUNT')

  it "should get target fields for space", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    targetFields = builder.getTargetFields "Authors"
    
    assert type(targetFields) == 'string'
    assert targetFields.includes('id')
    assert targetFields.includes('name')

  it "should get field definitions", ->
    builder = new GraphQLBuilder {
      container: document.createElement('div')
      allSpaces: @spaces
      allRelations: @relations
      onChange: ->
    }
    
    builder.setSourceSpace "1"
    builder.loadRelationTypes @spaces, @relations
    
    # Select fields
    builder.selectField "1", "title"
    builder.selectField "1", "author"
    
    definitions = builder.getFieldDefinitions()
    
    assert type(definitions) == 'table'
    assert definitions.title
    assert definitions.author
    
    assert definitions.title.type == 'String'
    assert !definitions.title.isRelation
    
    assert definitions.author.type == 'Single'
    assert definitions.author.isRelation
