-- tests/test_parser.moon
-- Tests for GraphQL parser (graphql/parser.moon).
-- No Tarantool dependency.

R = require 'tests.runner'
{ :parse } = require 'graphql.parser'

-- Helper: first definition node in a document
first_def = (src) -> parse(src).definitions[1]

-- Helper: first field in the first definition selection
first_field = (src) -> first_def(src).selectionSet.selections[1]

R.describe "Parser — document", ->
  R.it "produces a Document node", ->
    doc = parse "{ hello }"
    R.eq doc.kind, 'Document'
    R.ok doc.definitions

  R.it "one definition for an anonymous operation", ->
    doc = parse "{ hello }"
    R.eq #doc.definitions, 1

  R.it "multiple definitions", ->
    doc = parse "query A { a } query B { b }"
    R.eq #doc.definitions, 2

R.describe "Parser — operations", ->
  R.it "short selection -> anonymous query", ->
    def = first_def "{ hello }"
    R.eq def.kind, 'OperationDefinition'
    R.eq def.operation, 'query'
    R.is_nil def.name

  R.it "explicit query keyword", ->
    def = first_def "query { hello }"
    R.eq def.operation, 'query'

  R.it "named query", ->
    def = first_def "query MonQuery { hello }"
    R.eq def.name, 'MonQuery'

  R.it "mutation", ->
    def = first_def "mutation { doSomething }"
    R.eq def.operation, 'mutation'

  R.it "named mutation", ->
    def = first_def "mutation DoIt { doSomething }"
    R.eq def.name, 'DoIt'

R.describe "Parser — SelectionSet and fields", ->
  R.it "simple field", ->
    f = first_field "{ hello }"
    R.eq f.kind, 'Field'
    R.eq f.name, 'hello'

  R.it "multiple fields", ->
    def = first_def "{ a b c }"
    R.eq #def.selectionSet.selections, 3

  R.it "field with alias", ->
    f = first_field "{ myAlias: hello }"
    R.eq f.alias, 'myAlias'
    R.eq f.name, 'hello'

  R.it "nested SelectionSet", ->
    f = first_field "{ outer { inner } }"
    R.eq f.name, 'outer'
    R.ok f.selectionSet
    R.eq f.selectionSet.selections[1].name, 'inner'

  R.it "deep nesting", ->
    f = first_field "{ a { b { c } } }"
    inner = f.selectionSet.selections[1].selectionSet.selections[1]
    R.eq inner.name, 'c'

R.describe "Parser — arguments", ->
  R.it "integer argument", ->
    f = first_field "{ f(x: 42) }"
    R.eq #f.arguments, 1
    R.eq f.arguments[1].name, 'x'
    R.eq f.arguments[1].value.kind, 'IntValue'
    R.eq f.arguments[1].value.value, '42'

  R.it "string argument", ->
    f = first_field '{ f(s: "hello") }'
    arg = f.arguments[1]
    R.eq arg.value.kind, 'StringValue'
    R.eq arg.value.value, 'hello'

  R.it "float argument", ->
    f = first_field "{ f(n: 3.14) }"
    R.eq f.arguments[1].value.kind, 'FloatValue'

  R.it "boolean argument true", ->
    f = first_field "{ f(b: true) }"
    R.eq f.arguments[1].value.kind, 'BooleanValue'
    R.eq f.arguments[1].value.value, true

  R.it "boolean argument false", ->
    f = first_field "{ f(b: false) }"
    R.eq f.arguments[1].value.value, false

  R.it "argument null", ->
    f = first_field "{ f(x: null) }"
    R.eq f.arguments[1].value.kind, 'NullValue'

  R.it "list argument", ->
    f = first_field "{ f(l: [1, 2, 3]) }"
    R.eq f.arguments[1].value.kind, 'ListValue'
    R.eq #f.arguments[1].value.values, 3

  R.it "object argument", ->
    f = first_field '{ f(o: {a: 1, b: "x"}) }'
    R.eq f.arguments[1].value.kind, 'ObjectValue'
    R.eq #f.arguments[1].value.fields, 2

  R.it "argument enum", ->
    f = first_field "{ f(dir: ASC) }"
    R.eq f.arguments[1].value.kind, 'EnumValue'
    R.eq f.arguments[1].value.value, 'ASC'

  R.it "variable argument", ->
    f = first_field "{ f(x: $myVar) }"
    R.eq f.arguments[1].value.kind, 'Variable'
    R.eq f.arguments[1].value.name, 'myVar'

  R.it "multiple arguments", ->
    f = first_field "{ f(a: 1, b: 2, c: 3) }"
    R.eq #f.arguments, 3

R.describe "Parser — operation variables", ->
  R.it "one variable", ->
    def = first_def "query($id: ID!) { f(x: $id) }"
    R.eq #def.variableDefs, 1
    vd = def.variableDefs[1]
    R.eq vd.name, 'id'
    R.eq vd.type.kind, 'NonNullType'
    R.eq vd.type.ofType.name, 'ID'

  R.it "multiple variables", ->
    def = first_def "query($a: Int, $b: String) { f }"
    R.eq #def.variableDefs, 2

  R.it "variable with default value", ->
    def = first_def "query($n: Int = 0) { f }"
    vd = def.variableDefs[1]
    R.eq vd.defaultValue.value, '0'

R.describe "Parser — type references", ->
  R.it "named type", ->
    -- via SDL
    def = first_def "type T { f: String }"
    field_type = def.fields[1].type
    R.eq field_type.kind, 'NamedType'
    R.eq field_type.name, 'String'

  R.it "non-null type", ->
    def = first_def "type T { f: String! }"
    R.eq def.fields[1].type.kind, 'NonNullType'
    R.eq def.fields[1].type.ofType.name, 'String'

  R.it "list type", ->
    def = first_def "type T { f: [String] }"
    R.eq def.fields[1].type.kind, 'ListType'
    R.eq def.fields[1].type.ofType.name, 'String'

  R.it "non-null list type", ->
    def = first_def "type T { f: [String!]! }"
    outer = def.fields[1].type
    R.eq outer.kind, 'NonNullType'
    inner = outer.ofType
    R.eq inner.kind, 'ListType'
    R.eq inner.ofType.kind, 'NonNullType'

R.describe "Parser — fragments", ->
  R.it "fragment definition", ->
    doc = parse "fragment Fields on User { name email }"
    def = doc.definitions[1]
    R.eq def.kind, 'FragmentDefinition'
    R.eq def.name, 'Fields'
    R.eq def.typeCondition, 'User'
    R.eq #def.selectionSet.selections, 2

  R.it "fragment spread", ->
    f = first_field "{ ...MyFrag }"
    R.eq f.kind, 'FragmentSpread'
    R.eq f.name, 'MyFrag'

  R.it "fragment inline", ->
    f = first_field "{ ... on User { name } }"
    R.eq f.kind, 'InlineFragment'
    R.eq f.typeCondition, 'User'

  R.it "inline fragment without type", ->
    f = first_field "{ ... { name } }"
    R.eq f.kind, 'InlineFragment'
    R.is_nil f.typeCondition

R.describe "Parser — SDL: object types", ->
  R.it "simple object type", ->
    def = first_def "type User { name: String! }"
    R.eq def.kind, 'ObjectTypeDefinition'
    R.eq def.name, 'User'
    R.eq #def.fields, 1
    R.eq def.fields[1].name, 'name'

  R.it "multiple fields", ->
    def = first_def "type User { id: ID! name: String email: String }"
    R.eq #def.fields, 3

  R.it "type description", ->
    def = first_def '"""Mon type""" type Foo { x: Int }'
    R.ok def.description
    R.matches def.description, 'Mon type'

  R.it "field with SDL argument", ->
    def = first_def "type Q { f(limit: Int = 10): [String] }"
    arg = def.fields[1].arguments[1]
    R.eq arg.name, 'limit'
    R.eq arg.defaultValue.value, '10'

R.describe "Parser — SDL: scalars, enums, unions, inputs", ->
  R.it "scalar", ->
    def = first_def "scalar Date"
    R.eq def.kind, 'ScalarTypeDefinition'
    R.eq def.name, 'Date'

  R.it "enum", ->
    def = first_def "enum Color { RED GREEN BLUE }"
    R.eq def.kind, 'EnumTypeDefinition'
    R.eq #def.values, 3
    R.eq def.values[1].name, 'RED'

  R.it "union", ->
    def = first_def "union Result = Foo | Bar"
    R.eq def.kind, 'UnionTypeDefinition'
    R.eq #def.types, 2

  R.it "input object", ->
    def = first_def "input CreateUser { name: String! email: String }"
    R.eq def.kind, 'InputObjectTypeDefinition'
    R.eq #def.fields, 2

  R.it "interface", ->
    def = first_def "interface Node { id: ID! }"
    R.eq def.kind, 'InterfaceTypeDefinition'

R.describe "Parser — errors", ->
  R.it "missing closing brace", ->
    R.raises (-> parse "{ hello "), nil, 'expected syntax error'

  R.it "empty source -> empty document", ->
    doc = parse ""
    R.eq doc.kind, 'Document'
    R.eq #doc.definitions, 0
