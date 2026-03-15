return describe("GraphQL Builder", function()
  it("should export GraphQLBuilder class", function()
    return assert(type(GraphQLBuilder) == 'function')
  end)
  it("should create GraphQL Builder instance", function()
    local container = { }
    local builder = GraphQLBuilder({
      container = container,
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    assert(type(builder) == 'table')
    return assert(builder.container == container)
  end)
  it("should initialize with empty state", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    assert(type(builder._selectedFields) == 'table')
    assert(type(builder._computedFields) == 'table')
    return assert(type(builder._aggregations) == 'table')
  end)
  it("should set source space", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.setSourceSpace("123")
    return assert(builder._sourceSpaceId == "123")
  end)
  it("should select fields", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.setSourceSpace("1")
    builder.selectField("1", "title")
    return assert(builder._selectedFields["1.title"] == true)
  end)
  it("should remove fields", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.setSourceSpace("1")
    builder.selectField("1", "title")
    builder.removeField("1", "title")
    return assert(builder._selectedFields["1.title"] == nil)
  end)
  it("should add computed fields", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.addComputedField("display_name", "@name")
    assert(builder._computedFields.display_name)
    return assert(builder._computedFields.display_name.formula == "@name")
  end)
  it("should add aggregations", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.addAggregation("price", "AVG", "avg_price")
    assert(#builder._aggregations == 1)
    return assert(builder._aggregations[1].field == "price")
  end)
  it("should build basic query", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.setSourceSpace("1")
    builder.selectField("1", "title")
    local query = builder.buildQuery()
    assert(type(query) == 'string')
    return assert(query:find('query GetData'))
  end)
  it("should build aggregated query", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.setSourceSpace("1")
    builder.addAggregation("title", "COUNT", "book_count")
    local query = builder.buildQuery()
    assert(type(query) == 'string')
    return assert(query:find('query GetAggregatedData'))
  end)
  it("should detect list relations", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    assert(builder.hasListRelations() == false)
    builder._relationTypes["test.field"] = {
      type = 'List'
    }
    return assert(builder.hasListRelations() == true)
  end)
  return it("should get selected fields", function()
    local builder = GraphQLBuilder({
      container = { },
      allSpaces = { },
      allRelations = { },
      onChange = function() end
    })
    builder.setSourceSpace("1")
    builder.selectField("1", "title")
    builder.selectField("1", "author")
    local selected = builder.getSelectedFields()
    assert(#selected == 2)
    assert(selected[1].spaceId == "1")
    return assert(selected[1].fieldName == "title")
  end)
end)
