-- tests/test_executor.moon
-- Tests GraphQL executor behavior (graphql/executor.moon).
-- Uses a minimal mocked schema — no Tarantool dependency.

R = require 'tests.runner'
{ :build_schema }        = require 'graphql.schema'
{ :init, :execute }      = require 'graphql.executor'

-- ── Test schema ───────────────────────────────────────────────────────────────

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
    greet:     (_, args) -> "Hello #{args.name or 'unknown'}"
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

R.describe "Executor — simple queries", ->
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

  R.it "multiple fields", ->
    res = run "{ hello answer flag }"
    R.eq res.data.hello, 'world'
    R.eq res.data.answer, 42
    R.eq res.data.flag, true

  R.it "null field -> present as JSON null (not missing key)", ->
    -- Ensures {"data":{"nullField":null}} and not {"data":[]}.
    -- This bug previously broke login after session expiration.
    -- Note: in LuaJIT, cdata(NULL) == nil is true; validate via type() and JSON encoding.
    json = require 'json'
    res = run "{ nullField }"
    R.ok res.data
    R.eq type(res.data.nullField), 'cdata', "nullField must be cdata (json.NULL)"
    encoded = json.encode res.data
    R.matches encoded, '"nullField"'

  R.it "non-null field returning nil -> error", ->
    res = run "{ errField }"
    R.ok res.errors, "must return an error"
    R.ok #res.errors > 0
    R.matches tostring(res.errors[1].message), 'null'

  R.it "__typename returns type name", ->
    res = run "{ __typename }"
    R.eq res.data['__typename'], 'Query'

R.describe "Executor — arguments", ->
  R.it "argument simple", ->
    res = run '{ greet(name: "Alice") }'
    R.eq res.data.greet, 'Hello Alice'

  R.it "missing argument -> nil default value", ->
    res = run '{ greet }'
    R.eq res.data.greet, 'Hello unknown'

  R.it "addition avec arguments", ->
    res = run '{ add(a: 3, b: 4) }'
    R.eq res.data.add, 7

  R.it "echo chaîne", ->
    res = run '{ echo(value: "test") }'
    R.eq res.data.echo, 'test'

R.describe "Executor — variables", ->
  R.it "integer variable", ->
    res = run 'query($n: Int) { add(a: $n, b: 1) }', { n: 5 }
    R.eq res.data.add, 6

  R.it "string variable", ->
    res = run 'query($s: String) { greet(name: $s) }', { s: 'Bob' }
    R.eq res.data.greet, 'Hello Bob'

  R.it "variable non fournie → nil", ->
    res = run 'query($n: Int) { add(a: $n, b: 10) }', {}
    R.eq res.data.add, 10

R.describe "Executor — nested selection", ->
  R.it "nested object", ->
    res = run '{ user { id name age } }'
    R.eq res.data.user.name, 'Alice'
    R.eq res.data.user.age, 30

  R.it "__typename on nested type", ->
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
  R.it "named inline fragment", ->
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

R.describe "Executor — errors", ->
  R.it "result without error -> no errors key", ->
    res = run '{ hello }'
    R.nok res.errors

  R.it "parse error -> error returned", ->
    res = run '{ unclosed {'
    R.ok res.errors
    -- data is json.NULL (cdata) on fatal errors; type() == 'cdata' confirms it
    R.eq type(res.data), 'cdata', "data must be json.NULL on error"

  R.it "schema not initialized -> error", ->
    executor2 = require 'graphql.executor'
    -- Temporarily reset without schema
    executor2.init nil
    res = executor2.execute { query: '{ hello }' }
    R.ok res.errors
    -- Restore test schema
    executor2.init schema

  R.it "unknown field -> JSON null in data", ->
    -- Unknown field resolves to null (no error, key still present)
    json = require 'json'
    res = run '{ nonExistentField }'
    R.ok res.data
    R.eq res.data.nonExistentField, json.NULL

R.describe "Executor — operation selection", ->
  R.it "named operation selected", ->
    q = "query A { hello } query B { answer }"
    res = execute { query: q, operationName: 'B' }
    R.eq res.data.answer, 42
    R.is_nil res.data.hello

  R.it "named operation A", ->
    q = "query A { hello } query B { answer }"
    res = execute { query: q, operationName: 'A' }
    R.eq res.data.hello, 'world'
    R.is_nil res.data.answer
