-- tests/test_schema.moon
-- Tests du système de types GraphQL (graphql/schema.moon).
-- Aucune dépendance Tarantool.

R = require 'tests.runner'
{ :build_schema, :SCALARS } = require 'graphql.schema'

-- SDL minimal pour la majorité des tests
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

R.describe "Schema — scalaires intégrés", ->
  R.it "String est un SCALAR", ->
    t = s\get_type 'String'
    R.eq t.kind, 'SCALAR'
    R.eq t.name, 'String'

  R.it "Int est un SCALAR", ->
    R.eq (s\get_type 'Int').kind, 'SCALAR'

  R.it "Float est un SCALAR", ->
    R.eq (s\get_type 'Float').kind, 'SCALAR'

  R.it "Boolean est un SCALAR", ->
    R.eq (s\get_type 'Boolean').kind, 'SCALAR'

  R.it "ID est un SCALAR", ->
    R.eq (s\get_type 'ID').kind, 'SCALAR'

R.describe "Schema — types définis dans le SDL", ->
  R.it "Query est un OBJECT", ->
    t = s\get_type 'Query'
    R.eq t.kind, 'OBJECT'
    R.eq t.name, 'Query'

  R.it "User est un OBJECT", ->
    R.eq (s\get_type 'User').kind, 'OBJECT'

  R.it "Color est un ENUM", ->
    t = s\get_type 'Color'
    R.eq t.kind, 'ENUM'
    R.eq t.name, 'Color'
    R.eq #t.values, 3

  R.it "Node est une INTERFACE", ->
    R.eq (s\get_type 'Node').kind, 'INTERFACE'

  R.it "SearchResult est une UNION", ->
    t = s\get_type 'SearchResult'
    R.eq t.kind, 'UNION'
    R.eq #t.types, 2

  R.it "CreateUserInput est un INPUT_OBJECT", ->
    t = s\get_type 'CreateUserInput'
    R.eq t.kind, 'INPUT_OBJECT'
    R.eq t.name, 'CreateUserInput'

  R.it "Date est un scalaire personnalisé", ->
    t = s\get_type 'Date'
    R.eq t.kind, 'SCALAR'

  R.it "type inexistant → erreur", ->
    R.raises (-> s\get_type 'Inexistant'), 'Unknown type'

  R.it "find_type inexistant → nil", ->
    R.is_nil (s\find_type 'Inexistant')

R.describe "Schema — champs des types objet", ->
  R.it "Query.hello existe", ->
    t = s\get_type 'Query'
    R.ok t.fields['hello']

  R.it "Query.count est non-nul", ->
    t = s\get_type 'Query'
    R.eq t.fields['count'].type.kind, 'NonNullType'

  R.it "User a 5 champs", ->
    t = s\get_type 'User'
    count = 0
    for _ in pairs t.fields do count += 1
    R.eq count, 5

  R.it "CreateUserInput.name est non-nul", ->
    t = s\get_type 'CreateUserInput'
    R.eq t.fields['name'].type.kind, 'NonNullType'

R.describe "Schema — is_leaf", ->
  R.it "String est une feuille", ->
    R.ok s\is_leaf 'String'

  R.it "Int est une feuille", ->
    R.ok s\is_leaf 'Int'

  R.it "Color (enum) est une feuille", ->
    R.ok s\is_leaf 'Color'

  R.it "Date (scalaire custom) est une feuille", ->
    R.ok s\is_leaf 'Date'

  R.it "Query (objet) n'est pas une feuille", ->
    R.nok s\is_leaf 'Query'

  R.it "User (objet) n'est pas une feuille", ->
    R.nok s\is_leaf 'User'

  R.it "Node (interface) n'est pas une feuille", ->
    R.nok s\is_leaf 'Node'

R.describe "Schema — named_type (déballage)", ->
  named = (type_ref) -> s\named_type type_ref

  R.it "NamedType → son nom", ->
    R.eq named({ kind: 'NamedType', name: 'String' }), 'String'

  R.it "NonNullType → type interne", ->
    R.eq named({ kind: 'NonNullType', ofType: { kind: 'NamedType', name: 'Int' } }), 'Int'

  R.it "ListType → type interne", ->
    R.eq named({ kind: 'ListType', ofType: { kind: 'NamedType', name: 'User' } }), 'User'

  R.it "NonNull(List(NamedType))", ->
    R.eq named({
      kind: 'NonNullType',
      ofType: { kind: 'ListType', ofType: { kind: 'NamedType', name: 'String' } }
    }), 'String'

R.describe "Schema — coerce_input scalaires", ->
  mk = (name) -> { kind: 'NamedType', name: name }

  R.it "String : chaîne → chaîne", ->
    R.eq (s\coerce_input mk('String'), 'hello'), 'hello'

  R.it "String : nombre → chaîne", ->
    R.eq (s\coerce_input mk('String'), 42), '42'

  R.it "Int : chaîne numérique → entier", ->
    R.eq (s\coerce_input mk('Int'), '7'), 7

  R.it "Int : flottant → entier (floor)", ->
    R.eq (s\coerce_input mk('Int'), 3.9), 3

  R.it "Float : chaîne → float", ->
    R.eq (s\coerce_input mk('Float'), '3.14'), 3.14

  R.it "Boolean : true → true", ->
    R.eq (s\coerce_input mk('Boolean'), true), true

  R.it "Boolean : 'true' → true", ->
    R.eq (s\coerce_input mk('Boolean'), 'true'), true

  R.it "Boolean : false → false", ->
    R.eq (s\coerce_input mk('Boolean'), false), false

  R.it "ID : nombre → chaîne", ->
    R.eq (s\coerce_input mk('ID'), 99), '99'

R.describe "Schema — coerce_input liste", ->
  list_str = { kind: 'ListType', ofType: { kind: 'NamedType', name: 'Int' } }

  R.it "liste de chaînes numériques → liste d'entiers", ->
    result = s\coerce_input list_str, {'1', '2', '3'}
    R.eq result[1], 1
    R.eq result[2], 2
    R.eq result[3], 3

  R.it "valeur scalaire → liste d'un élément", ->
    result = s\coerce_input list_str, '5'
    R.eq result[1], 5

R.describe "Schema — résolveurs", ->
  sdl2 = "type Query { greet: String }"
  resolvers2 = { Query: { greet: (_, __, ___) -> "bonjour" } }
  s2 = build_schema sdl2, resolvers2

  R.it "résolveur personnalisé enregistré", ->
    fn = s2\get_resolver 'Query', 'greet'
    R.eq (fn {}, {}, {}), "bonjour"

  R.it "champ sans résolveur → accès par clé sur parent", ->
    fn = s\get_resolver 'User', 'name'
    parent = { name: 'Alice' }
    R.eq (fn parent, {}, {}), 'Alice'
