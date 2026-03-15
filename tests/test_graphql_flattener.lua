local GraphQLFlattener = require('core.graphql_flattener')
return describe("GraphQL Flattener", function()
  it("should export GraphQLFlattener module", function()
    assert(type(GraphQLFlattener) == 'table')
    return assert(type(GraphQLFlattener.flatten) == 'function')
  end)
  it("should flatten simple record", function()
    local data = {
      records = {
        {
          id = "1",
          title = "Test Book",
          author = "John Doe"
        }
      }
    }
    local fieldDefinitions = {
      id = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      title = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      author = {
        type = 'String',
        space = 'Books',
        isRelation = false
      }
    }
    local flattened = GraphQLFlattener.flatten(data, "", fieldDefinitions)
    assert(#flattened == 1)
    assert(flattened[1].id == "1")
    assert(flattened[1].title == "Test Book")
    return assert(flattened[1].author == "John Doe")
  end)
  it("should flatten record with nested object", function()
    local data = {
      records = {
        {
          id = "1",
          title = "Test Book",
          author = {
            id = "1",
            name = "John Doe",
            email = "john@example.com"
          }
        }
      }
    }
    local fieldDefinitions = {
      id = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      title = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      author = {
        type = 'Single',
        space = 'Authors',
        isRelation = true
      }
    }
    local flattened = GraphQLFlattener.flatten(data, "", fieldDefinitions)
    assert(#flattened == 1)
    assert(flattened[1].id == "1")
    assert(flattened[1].title == "Test Book")
    assert(flattened[1].author_id == "1")
    assert(flattened[1].author_name == "John Doe")
    return assert(flattened[1].author_email == "john@example.com")
  end)
  it("should flatten record with list of objects", function()
    local data = {
      records = {
        {
          id = "1",
          title = "Test Book",
          categories = {
            {
              id = "1",
              name = "Fiction"
            },
            {
              id = "2",
              name = "Science"
            }
          }
        }
      }
    }
    local fieldDefinitions = {
      id = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      title = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      categories = {
        type = 'List',
        space = 'Categories',
        isRelation = true
      }
    }
    local flattened = GraphQLFlattener.flatten(data, "", fieldDefinitions)
    assert(#flattened == 1)
    assert(flattened[1].id == "1")
    assert(flattened[1].title == "Test Book")
    local categories = flattened[1].categories
    assert(type(categories) == 'table')
    assert(#categories == 2)
    assert(categories[1].categories_1_id == "1")
    assert(categories[1].categories_1_name == "Fiction")
    assert(categories[2].categories_2_id == "2")
    return assert(categories[2].categories_2_name == "Science")
  end)
  it("should handle empty data", function()
    local data = {
      records = { }
    }
    local flattened = GraphQLFlattener.flatten(data, "", { })
    return assert(#flattened == 0)
  end)
  it("should handle null data", function()
    local data = nil
    local flattened = GraphQLFlattener.flatten(data, "", { })
    return assert(#flattened == 0)
  end)
  it("should detect list fields", function()
    local data = {
      records = {
        {
          id = "1",
          title = "Test Book",
          categories = {
            {
              id = "1",
              name = "Fiction"
            }
          },
          author = {
            id = "1",
            name = "John Doe"
          }
        }
      }
    }
    local listFields = GraphQLFlattener.detectListFields(data)
    assert(listFields.categories == true)
    return assert(listFields.author == nil)
  end)
  it("should convert to list", function()
    local luaTable = {
      "item1",
      "item2",
      "item3"
    }
    local converted = GraphQLFlattener.convertToList(luaTable)
    assert(type(converted) == 'table')
    assert(converted[1] == "item1")
    assert(converted[2] == "item2")
    return assert(converted[3] == "item3")
  end)
  it("should validate array detection", function()
    assert(GraphQLFlattener.isArray({
      1,
      2,
      3
    }))
    assert(GraphQLFlattener.isArray({
      "a",
      "b",
      "c"
    }))
    assert()(GraphQLFlattener.isArray({
      name = "test",
      value = 123
    }))
    assert()(GraphQLFlattener.isArray("string"))
    return assert()(GraphQLFlattener.isArray(123))
  end)
  it("should validate object detection", function()
    assert(GraphQLFlattener.isObject({
      name = "test",
      value = 123
    }))
    assert(GraphQLFlattener.isObject({
      nested = {
        value = 456
      }
    }))
    assert()(GraphQLFlattener.isObject({
      1,
      2,
      3
    }))
    assert()(GraphQLFlattener.isObject("string"))
    return assert()(GraphQLFlattener.isObject(123))
  end)
  it("should validate simple type detection", function()
    assert(GraphQLFlattener.isSimpleType("string"))
    assert(GraphQLFlattener.isSimpleType(123))
    assert(GraphQLFlattener.isSimpleType(true))
    assert()(GraphQLFlattener.isSimpleType({
      name = "test"
    }))
    return assert()(GraphQLFlattener.isSimpleType({
      1,
      2,
      3
    }))
  end)
  it("should flatten with depth limit", function()
    local data = {
      records = {
        {
          id = "1",
          nested = {
            level1 = {
              level2 = {
                level3 = {
                  level4 = {
                    level5 = "deep"
                  }
                }
              }
            }
          }
        }
      }
    }
    local flattened = GraphQLFlattener.flattenOptimized(data, "", { }, {
      maxDepth = 3
    })
    assert(#flattened == 1)
    assert(flattened[1].id == "1")
    return assert(flattened[1].nested_level1_level2_depth_limit == "MAX_DEPTH_REACHED")
  end)
  it("should validate flattened data", function()
    local flattened = {
      {
        id = "1",
        title = "Test",
        price = 19.99
      }
    }
    local schema = {
      id = 'string',
      title = 'string',
      price = 'number'
    }
    local errors = GraphQLFlattener.validateFlattened(flattened, schema)
    return assert(#errors == 0)
  end)
  it("should detect validation errors", function()
    local flattened = {
      {
        id = "1",
        title = "Test",
        price = "not_a_number"
      }
    }
    local schema = {
      id = 'string',
      title = 'string',
      price = 'number'
    }
    local errors = GraphQLFlattener.validateFlattened(flattened, schema)
    assert(#errors > 0)
    return assert(errors[1]:find("invalid type"))
  end)
  return it("should handle complex nested structures", function()
    local data = {
      records = {
        {
          id = "1",
          title = "Complex Book",
          author = {
            id = "1",
            name = "John",
            books = {
              {
                id = "2",
                title = "Other Book"
              }
            }
          },
          categories = {
            {
              id = "1",
              name = "Fiction",
              parent = {
                id = "0",
                name = "Root"
              }
            },
            {
              id = "2",
              name = "Science",
              parent = {
                id = "0",
                name = "Root"
              }
            }
          }
        }
      }
    }
    local fieldDefinitions = {
      id = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      title = {
        type = 'String',
        space = 'Books',
        isRelation = false
      },
      author = {
        type = 'Single',
        space = 'Authors',
        isRelation = true
      },
      categories = {
        type = 'List',
        space = 'Categories',
        isRelation = true
      }
    }
    local flattened = GraphQLFlattener.flatten(data, "", fieldDefinitions)
    assert(#flattened == 1)
    assert(flattened[1].id == "1")
    assert(flattened[1].author_id == "1")
    assert(flattened[1].author_name == "John")
    assert(flattened[1].author_books_1_id == "2")
    assert(flattened[1].author_books_1_title == "Other Book")
    local categories = flattened[1].categories
    assert(#categories == 2)
    assert(categories[1].categories_1_id == "1")
    assert(categories[1].categories_1_name == "Fiction")
    assert(categories[1].categories_1_parent_id == "0")
    return assert(categories[1].categories_1_parent_name == "Root")
  end)
end)
