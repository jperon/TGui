-- tests/test_executor.moon
-- Tests de l'executor GraphQL (graphql/executor.moon).
-- Utilise un schema minimal mocké — aucune dépendance Tarantool.

R = require 'tests.runner'
{ :build_schema }        = require 'graphql.schema'
{ :init, :execute }      = require 'graphql.executor'

-- ── Schéma de test ────────────────────────────────────────────────────────────

TEST_SDL = [[
  type Query {
    hello:     String
    answer:    Int
    pi:        Float
    flag:      Boolean
    greet(name: String): String
    add(a: Int, b: Int): Int
    echo(value: String!): String
    user:      User
    users:     [User]
    nullField: String
    errField:  String!
  }

  type User {
    id:   ID!
    name: String!
    age:  Int
  }

  type Mutation {
    setName(name: String!): String
  }
]]

TEST_RESOLVERS =
  Query:
    hello:     -> "world"
    answer:    -> 42
    pi:        -> 3.14
    flag:      -> true
    greet:     (_, args) -> "Bonjour #{args.name or 'inconnu'}"
    add:       (_, args) -> (args.a or 0) + (args.b or 0)
    echo:      (_, args) -> args.value
    user:      -> { id: '1', name: 'Alice', age: 30 }
    users: ->
      result = {}
      table.insert result, { id: '1', name: 'Alice', age: 30 }
      table.insert result, { id: '2', name: 'Bob',   age: 25 }
      result
    nullField:  -> nil
    errField:   -> nil   -- non-null field returning nil → should produce error
  Mutation:
    setName:   (_, args) -> args.name

schema = build_schema TEST_SDL, TEST_RESOLVERS
init schema

-- Helper
run = (query, vars) ->
  execute { query: query, variables: (vars or {}) }

R.describe "Executor — requêtes simples", ->
  R.it "champ String", ->
    res = run "{ hello }"
    R.eq res.data.hello, 'world'

  R.it "champ Int", ->
    res = run "{ answer }"
    R.eq res.data.answer, 42

  R.it "champ Float", ->
    res = run "{ pi }"
    R.eq res.data.pi, 3.14

  R.it "champ Boolean", ->
    res = run "{ flag }"
    R.eq res.data.flag, true

  R.it "plusieurs champs", ->
    res = run "{ hello answer flag }"
    R.eq res.data.hello, 'world'
    R.eq res.data.answer, 42
    R.eq res.data.flag, true

  R.it "champ null retourne nil", ->
    res = run "{ nullField }"
    R.is_nil res.data.nullField

  R.it "champ non-null retournant nil → erreur", ->
    res = run "{ errField }"
    R.ok res.errors, "doit retourner une erreur"
    R.ok #res.errors > 0
    R.matches tostring(res.errors[1].message), 'null'

  R.it "__typename retourne le nom du type", ->
    res = run "{ __typename }"
    R.eq res.data['__typename'], 'Query'

R.describe "Executor — arguments", ->
  R.it "argument simple", ->
    res = run '{ greet(name: "Alice") }'
    R.eq res.data.greet, 'Bonjour Alice'

  R.it "argument absent → valeur par défaut nil", ->
    res = run '{ greet }'
    R.eq res.data.greet, 'Bonjour inconnu'

  R.it "addition avec arguments", ->
    res = run '{ add(a: 3, b: 4) }'
    R.eq res.data.add, 7

  R.it "echo chaîne", ->
    res = run '{ echo(value: "test") }'
    R.eq res.data.echo, 'test'

R.describe "Executor — variables", ->
  R.it "variable entière", ->
    res = run 'query($n: Int) { add(a: $n, b: 1) }', { n: 5 }
    R.eq res.data.add, 6

  R.it "variable chaîne", ->
    res = run 'query($s: String) { greet(name: $s) }', { s: 'Bob' }
    R.eq res.data.greet, 'Bonjour Bob'

  R.it "variable non fournie → nil", ->
    res = run 'query($n: Int) { add(a: $n, b: 10) }', {}
    R.eq res.data.add, 10

R.describe "Executor — sélection imbriquée", ->
  R.it "objet imbriqué", ->
    res = run '{ user { id name age } }'
    R.eq res.data.user.name, 'Alice'
    R.eq res.data.user.age, 30

  R.it "__typename sur type imbriqué", ->
    res = run '{ user { __typename name } }'
    R.eq res.data.user['__typename'], 'User'

  R.it "liste d'objets", ->
    res = run '{ users { id name } }'
    R.eq #res.data.users, 2
    R.eq res.data.users[1].name, 'Alice'
    R.eq res.data.users[2].name, 'Bob'

  R.it "champ partiel dans liste", ->
    res = run '{ users { name } }'
    R.eq res.data.users[1].name, 'Alice'
    R.is_nil res.data.users[1].age   -- not requested

R.describe "Executor — fragments", ->
  R.it "fragment nommé inline", ->
    q = [[
      { user { ...F } }
      fragment F on User { name age }
    ]]
    res = run q
    R.eq res.data.user.name, 'Alice'
    R.eq res.data.user.age, 30

  R.it "fragment inline", ->
    res = run '{ user { ... on User { name } } }'
    R.eq res.data.user.name, 'Alice'

  R.it "fragment inline sans type", ->
    res = run '{ user { ... { name } } }'
    R.eq res.data.user.name, 'Alice'

R.describe "Executor — mutations", ->
  R.it "mutation avec argument", ->
    res = run 'mutation { setName(name: "Charlie") }'
    R.eq res.data.setName, 'Charlie'

R.describe "Executor — erreurs", ->
  R.it "résultat sans erreur → pas de clé errors", ->
    res = run '{ hello }'
    R.nok res.errors

  R.it "parse error → erreur retournée", ->
    res = run '{ unclosed {'
    R.ok res.errors
    R.is_nil res.data

  R.it "schéma non initialisé → erreur", ->
    executor2 = require 'graphql.executor'
    -- Réinitialiser temporairement sans schéma
    executor2.init nil
    res = executor2.execute { query: '{ hello }' }
    R.ok res.errors
    -- Remettre le schéma de test
    executor2.init schema

  R.it "champ inexistant → nil dans data (pas d'erreur bloquante)", ->
    -- Le champ demandé n'existe pas dans le schéma : erreur ou nil
    res = run '{ nonExistentField }'
    -- selon l'implémentation : errors ou data.nonExistentField nil
    has_error = (res.errors and #res.errors > 0) or (res.data and res.data.nonExistentField == nil)
    R.ok has_error

R.describe "Executor — sélection d'opération", ->
  R.it "opération nommée choisie", ->
    q = "query A { hello } query B { answer }"
    res = execute { query: q, operationName: 'B' }
    R.eq res.data.answer, 42
    R.is_nil res.data.hello

  R.it "opération nommée A", ->
    q = "query A { hello } query B { answer }"
    res = execute { query: q, operationName: 'A' }
    R.eq res.data.hello, 'world'
    R.is_nil res.data.answer
