-- tests/test_parser.moon
-- Tests du parser GraphQL (graphql/parser.moon).
-- Aucune dépendance Tarantool.

R = require 'tests.runner'
{ :parse } = require 'graphql.parser'

-- Helper : premier nœud de définition du document
first_def = (src) -> parse(src).definitions[1]

-- Helper : premier champ de la sélection de la première définition
first_field = (src) -> first_def(src).selectionSet.selections[1]

R.describe "Parser — document", ->
  R.it "produit un nœud Document", ->
    doc = parse "{ hello }"
    R.eq doc.kind, 'Document'
    R.ok doc.definitions

  R.it "une définition pour une opération anonyme", ->
    doc = parse "{ hello }"
    R.eq #doc.definitions, 1

  R.it "plusieurs définitions", ->
    doc = parse "query A { a } query B { b }"
    R.eq #doc.definitions, 2

R.describe "Parser — opérations", ->
  R.it "sélection courte → query anonyme", ->
    def = first_def "{ hello }"
    R.eq def.kind, 'OperationDefinition'
    R.eq def.operation, 'query'
    R.is_nil def.name

  R.it "mot-clé query explicite", ->
    def = first_def "query { hello }"
    R.eq def.operation, 'query'

  R.it "query nommé", ->
    def = first_def "query MonQuery { hello }"
    R.eq def.name, 'MonQuery'

  R.it "mutation", ->
    def = first_def "mutation { doSomething }"
    R.eq def.operation, 'mutation'

  R.it "mutation nommée", ->
    def = first_def "mutation DoIt { doSomething }"
    R.eq def.name, 'DoIt'

R.describe "Parser — SelectionSet et Fields", ->
  R.it "champ simple", ->
    f = first_field "{ hello }"
    R.eq f.kind, 'Field'
    R.eq f.name, 'hello'

  R.it "plusieurs champs", ->
    def = first_def "{ a b c }"
    R.eq #def.selectionSet.selections, 3

  R.it "champ avec alias", ->
    f = first_field "{ myAlias: hello }"
    R.eq f.alias, 'myAlias'
    R.eq f.name, 'hello'

  R.it "SelectionSet imbriqué", ->
    f = first_field "{ outer { inner } }"
    R.eq f.name, 'outer'
    R.ok f.selectionSet
    R.eq f.selectionSet.selections[1].name, 'inner'

  R.it "imbrication profonde", ->
    f = first_field "{ a { b { c } } }"
    inner = f.selectionSet.selections[1].selectionSet.selections[1]
    R.eq inner.name, 'c'

R.describe "Parser — arguments", ->
  R.it "argument entier", ->
    f = first_field "{ f(x: 42) }"
    R.eq #f.arguments, 1
    R.eq f.arguments[1].name, 'x'
    R.eq f.arguments[1].value.kind, 'IntValue'
    R.eq f.arguments[1].value.value, '42'

  R.it "argument chaîne", ->
    f = first_field '{ f(s: "hello") }'
    arg = f.arguments[1]
    R.eq arg.value.kind, 'StringValue'
    R.eq arg.value.value, 'hello'

  R.it "argument flottant", ->
    f = first_field "{ f(n: 3.14) }"
    R.eq f.arguments[1].value.kind, 'FloatValue'

  R.it "argument booléen true", ->
    f = first_field "{ f(b: true) }"
    R.eq f.arguments[1].value.kind, 'BooleanValue'
    R.eq f.arguments[1].value.value, true

  R.it "argument booléen false", ->
    f = first_field "{ f(b: false) }"
    R.eq f.arguments[1].value.value, false

  R.it "argument null", ->
    f = first_field "{ f(x: null) }"
    R.eq f.arguments[1].value.kind, 'NullValue'

  R.it "argument liste", ->
    f = first_field "{ f(l: [1, 2, 3]) }"
    R.eq f.arguments[1].value.kind, 'ListValue'
    R.eq #f.arguments[1].value.values, 3

  R.it "argument objet", ->
    f = first_field '{ f(o: {a: 1, b: "x"}) }'
    R.eq f.arguments[1].value.kind, 'ObjectValue'
    R.eq #f.arguments[1].value.fields, 2

  R.it "argument enum", ->
    f = first_field "{ f(dir: ASC) }"
    R.eq f.arguments[1].value.kind, 'EnumValue'
    R.eq f.arguments[1].value.value, 'ASC'

  R.it "argument variable", ->
    f = first_field "{ f(x: $myVar) }"
    R.eq f.arguments[1].value.kind, 'Variable'
    R.eq f.arguments[1].value.name, 'myVar'

  R.it "plusieurs arguments", ->
    f = first_field "{ f(a: 1, b: 2, c: 3) }"
    R.eq #f.arguments, 3

R.describe "Parser — variables de l'opération", ->
  R.it "une variable", ->
    def = first_def "query($id: ID!) { f(x: $id) }"
    R.eq #def.variableDefs, 1
    vd = def.variableDefs[1]
    R.eq vd.name, 'id'
    R.eq vd.type.kind, 'NonNullType'
    R.eq vd.type.ofType.name, 'ID'

  R.it "plusieurs variables", ->
    def = first_def "query($a: Int, $b: String) { f }"
    R.eq #def.variableDefs, 2

  R.it "variable avec valeur par défaut", ->
    def = first_def "query($n: Int = 0) { f }"
    vd = def.variableDefs[1]
    R.eq vd.defaultValue.value, '0'

R.describe "Parser — références de types", ->
  R.it "type nommé", ->
    -- via SDL
    def = first_def "type T { f: String }"
    field_type = def.fields[1].type
    R.eq field_type.kind, 'NamedType'
    R.eq field_type.name, 'String'

  R.it "type non-nul", ->
    def = first_def "type T { f: String! }"
    R.eq def.fields[1].type.kind, 'NonNullType'
    R.eq def.fields[1].type.ofType.name, 'String'

  R.it "type liste", ->
    def = first_def "type T { f: [String] }"
    R.eq def.fields[1].type.kind, 'ListType'
    R.eq def.fields[1].type.ofType.name, 'String'

  R.it "type liste non-nul", ->
    def = first_def "type T { f: [String!]! }"
    outer = def.fields[1].type
    R.eq outer.kind, 'NonNullType'
    inner = outer.ofType
    R.eq inner.kind, 'ListType'
    R.eq inner.ofType.kind, 'NonNullType'

R.describe "Parser — fragments", ->
  R.it "définition de fragment", ->
    doc = parse "fragment Fields on User { name email }"
    def = doc.definitions[1]
    R.eq def.kind, 'FragmentDefinition'
    R.eq def.name, 'Fields'
    R.eq def.typeCondition, 'User'
    R.eq #def.selectionSet.selections, 2

  R.it "spread de fragment", ->
    f = first_field "{ ...MyFrag }"
    R.eq f.kind, 'FragmentSpread'
    R.eq f.name, 'MyFrag'

  R.it "fragment inline", ->
    f = first_field "{ ... on User { name } }"
    R.eq f.kind, 'InlineFragment'
    R.eq f.typeCondition, 'User'

  R.it "fragment inline sans type", ->
    f = first_field "{ ... { name } }"
    R.eq f.kind, 'InlineFragment'
    R.is_nil f.typeCondition

R.describe "Parser — SDL : types objet", ->
  R.it "type objet simple", ->
    def = first_def "type User { name: String! }"
    R.eq def.kind, 'ObjectTypeDefinition'
    R.eq def.name, 'User'
    R.eq #def.fields, 1
    R.eq def.fields[1].name, 'name'

  R.it "plusieurs champs", ->
    def = first_def "type User { id: ID! name: String email: String }"
    R.eq #def.fields, 3

  R.it "description de type", ->
    def = first_def '"""Mon type""" type Foo { x: Int }'
    R.ok def.description
    R.matches def.description, 'Mon type'

  R.it "champ avec argument SDL", ->
    def = first_def "type Q { f(limit: Int = 10): [String] }"
    arg = def.fields[1].arguments[1]
    R.eq arg.name, 'limit'
    R.eq arg.defaultValue.value, '10'

R.describe "Parser — SDL : scalaires, enums, unions, inputs", ->
  R.it "scalaire", ->
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

R.describe "Parser — erreurs", ->
  R.it "accolade fermante manquante", ->
    R.raises (-> parse "{ hello "), nil, 'erreur syntaxique attendue'

  R.it "source vide → document vide", ->
    doc = parse ""
    R.eq doc.kind, 'Document'
    R.eq #doc.definitions, 0
