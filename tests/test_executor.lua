local R = require('tests.runner')
local build_schema
build_schema = require('graphql.schema').build_schema
local init, execute
do
  local _obj_0 = require('graphql.executor')
  init, execute = _obj_0.init, _obj_0.execute
end
local TEST_SDL = [[  type Query {
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
local TEST_RESOLVERS = {
  Query = {
    hello = function()
      return "world"
    end,
    answer = function()
      return 42
    end,
    pi = function()
      return 3.14
    end,
    flag = function()
      return true
    end,
    greet = function(_, args)
      return "Hello " .. tostring(args.name or 'unknown')
    end,
    add = function(_, args)
      return (args.a or 0) + (args.b or 0)
    end,
    echo = function(_, args)
      return args.value
    end,
    user = function()
      return {
        id = '1',
        name = 'Alice',
        age = 30
      }
    end,
    users = function()
      local result = { }
      table.insert(result, {
        id = '1',
        name = 'Alice',
        age = 30
      })
      table.insert(result, {
        id = '2',
        name = 'Bob',
        age = 25
      })
      return result
    end,
    nullField = function()
      return nil
    end,
    errField = function()
      return nil
    end
  },
  Mutation = {
    setName = function(_, args)
      return args.name
    end
  }
}
local schema = build_schema(TEST_SDL, TEST_RESOLVERS)
init(schema)
local run
run = function(query, vars)
  return execute({
    query = query,
    variables = (vars or { })
  })
end
R.describe("Executor — simple queries", function()
  R.it("champ String", function()
    local res = run("{ hello }")
    return R.eq(res.data.hello, 'world')
  end)
  R.it("champ Int", function()
    local res = run("{ answer }")
    return R.eq(res.data.answer, 42)
  end)
  R.it("champ Float", function()
    local res = run("{ pi }")
    return R.eq(res.data.pi, 3.14)
  end)
  R.it("champ Boolean", function()
    local res = run("{ flag }")
    return R.eq(res.data.flag, true)
  end)
  R.it("multiple fields", function()
    local res = run("{ hello answer flag }")
    R.eq(res.data.hello, 'world')
    R.eq(res.data.answer, 42)
    return R.eq(res.data.flag, true)
  end)
  R.it("null field -> present as JSON null (not missing key)", function()
    local json = require('json')
    local res = run("{ nullField }")
    R.ok(res.data)
    R.eq(type(res.data.nullField), 'cdata', "nullField must be cdata (json.NULL)")
    local encoded = json.encode(res.data)
    return R.matches(encoded, '"nullField"')
  end)
  R.it("non-null field returning nil -> error", function()
    local res = run("{ errField }")
    R.ok(res.errors, "must return an error")
    R.ok(#res.errors > 0)
    return R.matches(tostring(res.errors[1].message), 'null')
  end)
  return R.it("__typename returns type name", function()
    local res = run("{ __typename }")
    return R.eq(res.data['__typename'], 'Query')
  end)
end)
R.describe("Executor — arguments", function()
  R.it("argument simple", function()
    local res = run('{ greet(name: "Alice") }')
    return R.eq(res.data.greet, 'Hello Alice')
  end)
  R.it("missing argument -> nil default value", function()
    local res = run('{ greet }')
    return R.eq(res.data.greet, 'Hello unknown')
  end)
  R.it("addition avec arguments", function()
    local res = run('{ add(a: 3, b: 4) }')
    return R.eq(res.data.add, 7)
  end)
  return R.it("echo chaîne", function()
    local res = run('{ echo(value: "test") }')
    return R.eq(res.data.echo, 'test')
  end)
end)
R.describe("Executor — variables", function()
  R.it("integer variable", function()
    local res = run('query($n: Int) { add(a: $n, b: 1) }', {
      n = 5
    })
    return R.eq(res.data.add, 6)
  end)
  R.it("string variable", function()
    local res = run('query($s: String) { greet(name: $s) }', {
      s = 'Bob'
    })
    return R.eq(res.data.greet, 'Hello Bob')
  end)
  return R.it("variable non fournie → nil", function()
    local res = run('query($n: Int) { add(a: $n, b: 10) }', { })
    return R.eq(res.data.add, 10)
  end)
end)
R.describe("Executor — nested selection", function()
  R.it("nested object", function()
    local res = run('{ user { id name age } }')
    R.eq(res.data.user.name, 'Alice')
    return R.eq(res.data.user.age, 30)
  end)
  R.it("__typename on nested type", function()
    local res = run('{ user { __typename name } }')
    return R.eq(res.data.user['__typename'], 'User')
  end)
  R.it("liste d'objets", function()
    local res = run('{ users { id name } }')
    R.eq(#res.data.users, 2)
    R.eq(res.data.users[1].name, 'Alice')
    return R.eq(res.data.users[2].name, 'Bob')
  end)
  return R.it("champ partiel dans liste", function()
    local res = run('{ users { name } }')
    R.eq(res.data.users[1].name, 'Alice')
    return R.is_nil(res.data.users[1].age)
  end)
end)
R.describe("Executor — fragments", function()
  R.it("named inline fragment", function()
    local q = [[      { user { ...F } }
      fragment F on User { name age }
    ]]
    local res = run(q)
    R.eq(res.data.user.name, 'Alice')
    return R.eq(res.data.user.age, 30)
  end)
  R.it("fragment inline", function()
    local res = run('{ user { ... on User { name } } }')
    return R.eq(res.data.user.name, 'Alice')
  end)
  return R.it("fragment inline sans type", function()
    local res = run('{ user { ... { name } } }')
    return R.eq(res.data.user.name, 'Alice')
  end)
end)
R.describe("Executor — mutations", function()
  return R.it("mutation avec argument", function()
    local res = run('mutation { setName(name: "Charlie") }')
    return R.eq(res.data.setName, 'Charlie')
  end)
end)
R.describe("Executor — errors", function()
  R.it("result without error -> no errors key", function()
    local res = run('{ hello }')
    return R.nok(res.errors)
  end)
  R.it("parse error -> error returned", function()
    local res = run('{ unclosed {')
    R.ok(res.errors)
    return R.eq(type(res.data), 'cdata', "data must be json.NULL on error")
  end)
  R.it("schema not initialized -> error", function()
    local executor2 = require('graphql.executor')
    executor2.init(nil)
    local res = executor2.execute({
      query = '{ hello }'
    })
    R.ok(res.errors)
    return executor2.init(schema)
  end)
  return R.it("unknown field -> JSON null in data", function()
    local json = require('json')
    local res = run('{ nonExistentField }')
    R.ok(res.data)
    return R.eq(res.data.nonExistentField, json.NULL)
  end)
end)
return R.describe("Executor — operation selection", function()
  R.it("named operation selected", function()
    local q = "query A { hello } query B { answer }"
    local res = execute({
      query = q,
      operationName = 'B'
    })
    R.eq(res.data.answer, 42)
    return R.is_nil(res.data.hello)
  end)
  return R.it("named operation A", function()
    local q = "query A { hello } query B { answer }"
    local res = execute({
      query = q,
      operationName = 'A'
    })
    R.eq(res.data.hello, 'world')
    return R.is_nil(res.data.answer)
  end)
end)
