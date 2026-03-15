-- tests/test_graphql_flattener.moon
-- Tests for GraphQL Flattener with list support

GraphQLFlattener = require 'core.graphql_flattener'

describe "GraphQL Flattener", ->
  it "should export GraphQLFlattener module", ->
    assert type(GraphQLFlattener) == 'table'
    assert type(GraphQLFlattener.flatten) == 'function'

  it "should flatten simple record", ->
    data = {
      records: {
        { id: "1", title: "Test Book", author: "John Doe" }
      }
    }
    
    fieldDefinitions = {
      id: { type: 'String', space: 'Books', isRelation: false }
      title: { type: 'String', space: 'Books', isRelation: false }
      author: { type: 'String', space: 'Books', isRelation: false }
    }
    
    flattened = GraphQLFlattener.flatten data, "", fieldDefinitions
    
    assert #flattened == 1
    assert flattened[1].id == "1"
    assert flattened[1].title == "Test Book"
    assert flattened[1].author == "John Doe"

  it "should flatten record with nested object", ->
    data = {
      records: {
        { 
          id: "1", 
          title: "Test Book", 
          author: { 
            id: "1", 
            name: "John Doe", 
            email: "john@example.com" 
          } 
        }
      }
    }
    
    fieldDefinitions = {
      id: { type: 'String', space: 'Books', isRelation: false }
      title: { type: 'String', space: 'Books', isRelation: false }
      author: { type: 'Single', space: 'Authors', isRelation: true }
    }
    
    flattened = GraphQLFlattener.flatten data, "", fieldDefinitions
    
    assert #flattened == 1
    assert flattened[1].id == "1"
    assert flattened[1].title == "Test Book"
    assert flattened[1].author_id == "1"
    assert flattened[1].author_name == "John Doe"
    assert flattened[1].author_email == "john@example.com"

  it "should flatten record with list of objects", ->
    data = {
      records: {
        { 
          id: "1", 
          title: "Test Book", 
          categories: { 
            { id: "1", name: "Fiction" },
            { id: "2", name: "Science" }
          } 
        }
      }
    }
    
    fieldDefinitions = {
      id: { type: 'String', space: 'Books', isRelation: false }
      title: { type: 'String', space: 'Books', isRelation: false }
      categories: { type: 'List', space: 'Categories', isRelation: true }
    }
    
    flattened = GraphQLFlattener.flatten data, "", fieldDefinitions
    
    assert #flattened == 1
    assert flattened[1].id == "1"
    assert flattened[1].title == "Test Book"
    
    -- Check list structure
    categories = flattened[1].categories
    assert type(categories) == 'table'
    assert #categories == 2
    assert categories[1].categories_1_id == "1"
    assert categories[1].categories_1_name == "Fiction"
    assert categories[2].categories_2_id == "2"
    assert categories[2].categories_2_name == "Science"

  it "should handle empty data", ->
    data = { records: {} }
    flattened = GraphQLFlattener.flatten data, "", {}
    assert #flattened == 0

  it "should handle null data", ->
    data = nil
    flattened = GraphQLFlattener.flatten data, "", {}
    assert #flattened == 0

  it "should detect list fields", ->
    data = {
      records: {
        { 
          id: "1", 
          title: "Test Book", 
          categories: { 
            { id: "1", name: "Fiction" }
          },
          author: { id: "1", name: "John Doe" }
        }
      }
    }
    
    listFields = GraphQLFlattener.detectListFields data
    
    assert listFields.categories == true
    assert listFields.author == nil

  it "should convert to list", ->
    luaTable = { "item1", "item2", "item3" }
    converted = GraphQLFlattener.convertToList luaTable
    
    assert type(converted) == 'table'
    assert converted[1] == "item1"
    assert converted[2] == "item2"
    assert converted[3] == "item3"

  it "should validate array detection", ->
    assert GraphQLFlattener.isArray { 1, 2, 3 }
    assert GraphQLFlattener.isArray { "a", "b", "c" }
    assert !GraphQLFlattener.isArray { name: "test", value: 123 }
    assert !GraphQLFlattener.isArray "string"
    assert !GraphQLFlattener.isArray 123

  it "should validate object detection", ->
    assert GraphQLFlattener.isObject { name: "test", value: 123 }
    assert GraphQLFlattener.isObject { nested: { value: 456 } }
    assert !GraphQLFlattener.isObject { 1, 2, 3 }
    assert !GraphQLFlattener.isObject "string"
    assert !GraphQLFlattener.isObject 123

  it "should validate simple type detection", ->
    assert GraphQLFlattener.isSimpleType "string"
    assert GraphQLFlattener.isSimpleType 123
    assert GraphQLFlattener.isSimpleType true
    assert !GraphQLFlattener.isSimpleType { name: "test" }
    assert !GraphQLFlattener.isSimpleType { 1, 2, 3 }

  it "should flatten with depth limit", ->
    data = {
      records: {
        { 
          id: "1", 
          nested: { 
            level1: { 
              level2: { 
                level3: { 
                  level4: { 
                    level5: "deep" 
                  } 
                } 
              } 
            } 
          } 
        }
      }
    }
    
    flattened = GraphQLFlattener.flattenOptimized data, "", {}, { maxDepth: 3 }
    
    assert #flattened == 1
    assert flattened[1].id == "1"
    assert flattened[1].nested_level1_level2_depth_limit == "MAX_DEPTH_REACHED"

  it "should validate flattened data", ->
    flattened = {
      { id: "1", title: "Test", price: 19.99 }
    }
    
    schema = {
      id: 'string'
      title: 'string'
      price: 'number'
    }
    
    errors = GraphQLFlattener.validateFlattened flattened, schema
    assert #errors == 0

  it "should detect validation errors", ->
    flattened = {
      { id: "1", title: "Test", price: "not_a_number" }
    }
    
    schema = {
      id: 'string'
      title: 'string'
      price: 'number'
    }
    
    errors = GraphQLFlattener.validateFlattened flattened, schema
    assert #errors > 0
    assert errors[1]\find "invalid type"

  it "should handle complex nested structures", ->
    data = {
      records: {
        { 
          id: "1", 
          title: "Complex Book",
          author: { id: "1", name: "John", books: { { id: "2", title: "Other Book" } } },
          categories: { 
            { id: "1", name: "Fiction", parent: { id: "0", name: "Root" } },
            { id: "2", name: "Science", parent: { id: "0", name: "Root" } }
          }
        }
      }
    }
    
    fieldDefinitions = {
      id: { type: 'String', space: 'Books', isRelation: false }
      title: { type: 'String', space: 'Books', isRelation: false }
      author: { type: 'Single', space: 'Authors', isRelation: true }
      categories: { type: 'List', space: 'Categories', isRelation: true }
    }
    
    flattened = GraphQLFlattener.flatten data, "", fieldDefinitions
    
    assert #flattened == 1
    assert flattened[1].id == "1"
    assert flattened[1].author_id == "1"
    assert flattened[1].author_name == "John"
    assert flattened[1].author_books_1_id == "2"
    assert flattened[1].author_books_1_title == "Other Book"
    
    categories = flattened[1].categories
    assert #categories == 2
    assert categories[1].categories_1_id == "1"
    assert categories[1].categories_1_name == "Fiction"
    assert categories[1].categories_1_parent_id == "0"
    assert categories[1].categories_1_parent_name == "Root"
