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
      return "Bonjour " .. tostring(args.name or 'inconnu')
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
R.describe("Executor — requêtes simples", function()
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
  R.it("plusieurs champs", function()
    local res = run("{ hello answer flag }")
    R.eq(res.data.hello, 'world')
    R.eq(res.data.answer, 42)
    return R.eq(res.data.flag, true)
  end)
  R.it("champ null retourne nil", function()
    local res = run("{ nullField }")
    return R.is_nil(res.data.nullField)
  end)
  R.it("champ non-null retournant nil → erreur", function()
    local res = run("{ errField }")
    R.ok(res.errors, "doit retourner une erreur")
    R.ok(#res.errors > 0)
    return R.matches(tostring(res.errors[1].message), 'null')
  end)
  return R.it("__typename retourne le nom du type", function()
    local res = run("{ __typename }")
    return R.eq(res.data['__typename'], 'Query')
  end)
end)
R.describe("Executor — arguments", function()
  R.it("argument simple", function()
    local res = run('{ greet(name: "Alice") }')
    return R.eq(res.data.greet, 'Bonjour Alice')
  end)
  R.it("argument absent → valeur par défaut nil", function()
    local res = run('{ greet }')
    return R.eq(res.data.greet, 'Bonjour inconnu')
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
  R.it("variable entière", function()
    local res = run('query($n: Int) { add(a: $n, b: 1) }', {
      n = 5
    })
    return R.eq(res.data.add, 6)
  end)
  R.it("variable chaîne", function()
    local res = run('query($s: String) { greet(name: $s) }', {
      s = 'Bob'
    })
    return R.eq(res.data.greet, 'Bonjour Bob')
  end)
  return R.it("variable non fournie → nil", function()
    local res = run('query($n: Int) { add(a: $n, b: 10) }', { })
    return R.eq(res.data.add, 10)
  end)
end)
R.describe("Executor — sélection imbriquée", function()
  R.it("objet imbriqué", function()
    local res = run('{ user { id name age } }')
    R.eq(res.data.user.name, 'Alice')
    return R.eq(res.data.user.age, 30)
  end)
  R.it("__typename sur type imbriqué", function()
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
  R.it("fragment nommé inline", function()
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
R.describe("Executor — erreurs", function()
  R.it("résultat sans erreur → pas de clé errors", function()
    local res = run('{ hello }')
    return R.nok(res.errors)
  end)
  R.it("parse error → erreur retournée", function()
    local res = run('{ unclosed {')
    R.ok(res.errors)
    return R.is_nil(res.data)
  end)
  R.it("schéma non initialisé → erreur", function()
    local executor2 = require('graphql.executor')
    executor2.init(nil)
    local res = executor2.execute({
      query = '{ hello }'
    })
    R.ok(res.errors)
    return executor2.init(schema)
  end)
  return R.it("champ inexistant → nil dans data (pas d'erreur bloquante)", function()
    local res = run('{ nonExistentField }')
    local has_error = (res.errors and #res.errors > 0) or (res.data and res.data.nonExistentField == nil)
    return R.ok(has_error)
  end)
end)
return R.describe("Executor — sélection d'opération", function()
  R.it("opération nommée choisie", function()
    local q = "query A { hello } query B { answer }"
    local res = execute({
      query = q,
      operationName = 'B'
    })
    R.eq(res.data.answer, 42)
    return R.is_nil(res.data.hello)
  end)
  return R.it("opération nommée A", function()
    local q = "query A { hello } query B { answer }"
    local res = execute({
      query = q,
      operationName = 'A'
    })
    R.eq(res.data.hello, 'world')
    return R.is_nil(res.data.answer)
  end)
end)
