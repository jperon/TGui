-- tests/test_schema.moon
-- Tests for GraphQL type system (graphql/schema.moon).
-- No Tarantool dependency.

R = require 'tests.runner'
{ :build_schema, :SCALARS } = require 'graphql.schema'

-- Minimal SDL for most tests
BASIC_SDL = [[
  type Query {
    hello: String
    count: Int!
    flag:  Boolean
    ratio: Float
    uid:   ID
  }

  type User {
    id:    ID!
    name:  String!
    age:   Int
    score: Float
    active: Boolean
  }

  enum Color { RED GREEN BLUE }

  interface Node { id: ID! }

  union SearchResult = User | Color

  input CreateUserInput {
    name:  String!
    email: String
    age:   Int
  }

  scalar Date

  type Mutation {
    noop: Boolean
  }
]]

s = build_schema BASIC_SDL, {}

R.describe "Schema — built-in scalars", ->
  R.it "String is a SCALAR", ->
    t = s\get_type 'String'
    R.eq t.kind, 'SCALAR'
    R.eq t.name, 'String'

  R.it "Int is a SCALAR", ->
    R.eq (s\get_type 'Int').kind, 'SCALAR'

  R.it "Float is a SCALAR", ->
    R.eq (s\get_type 'Float').kind, 'SCALAR'

  R.it "Boolean is a SCALAR", ->
    R.eq (s\get_type 'Boolean').kind, 'SCALAR'

  R.it "ID is a SCALAR", ->
    R.eq (s\get_type 'ID').kind, 'SCALAR'

R.describe "Schema — types defined in SDL", ->
  R.it "Query is an OBJECT", ->
    t = s\get_type 'Query'
    R.eq t.kind, 'OBJECT'
    R.eq t.name, 'Query'

  R.it "User is an OBJECT", ->
    R.eq (s\get_type 'User').kind, 'OBJECT'

  R.it "Color is an ENUM", ->
    t = s\get_type 'Color'
    R.eq t.kind, 'ENUM'
    R.eq t.name, 'Color'
    R.eq #t.values, 3

  R.it "Node is an INTERFACE", ->
    R.eq (s\get_type 'Node').kind, 'INTERFACE'

  R.it "SearchResult is a UNION", ->
    t = s\get_type 'SearchResult'
    R.eq t.kind, 'UNION'
    R.eq #t.types, 2

  R.it "CreateUserInput is an INPUT_OBJECT", ->
    t = s\get_type 'CreateUserInput'
    R.eq t.kind, 'INPUT_OBJECT'
    R.eq t.name, 'CreateUserInput'

  R.it "Date is a custom scalar", ->
    t = s\get_type 'Date'
    R.eq t.kind, 'SCALAR'

  R.it "unknown type -> error", ->
    R.raises (-> s\get_type 'Unknown'), 'Unknown type'

  R.it "find_type unknown -> nil", ->
    R.is_nil (s\find_type 'Unknown')

R.describe "Schema — object type fields", ->
  R.it "Query.hello exists", ->
    t = s\get_type 'Query'
    R.ok t.fields['hello']

  R.it "Query.count is non-null", ->
    t = s\get_type 'Query'
    R.eq t.fields['count'].type.kind, 'NonNullType'

  R.it "User has 5 fields", ->
    t = s\get_type 'User'
    count = 0
    for _ in pairs t.fields do count += 1
    R.eq count, 5

  R.it "CreateUserInput.name is non-null", ->
    t = s\get_type 'CreateUserInput'
    R.eq t.fields['name'].type.kind, 'NonNullType'

R.describe "Schema — is_leaf", ->
  R.it "String is a leaf", ->
    R.ok s\is_leaf 'String'

  R.it "Int is a leaf", ->
    R.ok s\is_leaf 'Int'

  R.it "Color (enum) is a leaf", ->
    R.ok s\is_leaf 'Color'

  R.it "Date (custom scalar) is a leaf", ->
    R.ok s\is_leaf 'Date'

  R.it "Query (object) is not a leaf", ->
    R.nok s\is_leaf 'Query'

  R.it "User (object) is not a leaf", ->
    R.nok s\is_leaf 'User'

  R.it "Node (interface) is not a leaf", ->
    R.nok s\is_leaf 'Node'

R.describe "Schema — named_type (unwrapping)", ->
  named = (type_ref) -> s\named_type type_ref

  R.it "NamedType -> its name", ->
    R.eq named({ kind: 'NamedType', name: 'String' }), 'String'

  R.it "NonNullType -> inner type", ->
    R.eq named({ kind: 'NonNullType', ofType: { kind: 'NamedType', name: 'Int' } }), 'Int'

  R.it "ListType -> inner type", ->
    R.eq named({ kind: 'ListType', ofType: { kind: 'NamedType', name: 'User' } }), 'User'

  R.it "NonNull(List(NamedType))", ->
    R.eq named({
      kind: 'NonNullType',
      ofType: { kind: 'ListType', ofType: { kind: 'NamedType', name: 'String' } }
    }), 'String'

R.describe "Schema — coerce_input scalars", ->
  mk = (name) -> { kind: 'NamedType', name: name }

  R.it "String: string -> string", ->
    R.eq (s\coerce_input mk('String'), 'hello'), 'hello'

  R.it "String: number -> string", ->
    R.eq (s\coerce_input mk('String'), 42), '42'

  R.it "Int: numeric string -> integer", ->
    R.eq (s\coerce_input mk('Int'), '7'), 7

  R.it "Int: float -> integer (floor)", ->
    R.eq (s\coerce_input mk('Int'), 3.9), 3

  R.it "Float: string -> float", ->
    R.eq (s\coerce_input mk('Float'), '3.14'), 3.14

  R.it "Boolean: true -> true", ->
    R.eq (s\coerce_input mk('Boolean'), true), true

  R.it "Boolean: 'true' -> true", ->
    R.eq (s\coerce_input mk('Boolean'), 'true'), true

  R.it "Boolean: false -> false", ->
    R.eq (s\coerce_input mk('Boolean'), false), false

  R.it "ID: number -> string", ->
    R.eq (s\coerce_input mk('ID'), 99), '99'

R.describe "Schema — coerce_input list", ->
  list_str = { kind: 'ListType', ofType: { kind: 'NamedType', name: 'Int' } }

  R.it "list of numeric strings -> list of integers", ->
    result = s\coerce_input list_str, {'1', '2', '3'}
    R.eq result[1], 1
    R.eq result[2], 2
    R.eq result[3], 3

  R.it "scalar value -> single-item list", ->
    result = s\coerce_input list_str, '5'
    R.eq result[1], 5

R.describe "Schema — resolvers", ->
  sdl2 = "type Query { greet: String }"
  resolvers2 = { Query: { greet: (_, __, ___) -> "bonjour" } }
  s2 = build_schema sdl2, resolvers2

  R.it "custom resolver registered", ->
    fn = s2\get_resolver 'Query', 'greet'
    R.eq (fn {}, {}, {}), "bonjour"

  R.it "field without resolver -> parent key access", ->
    fn = s\get_resolver 'User', 'name'
    parent = { name: 'Alice' }
    R.eq (fn parent, {}, {}), 'Alice'
