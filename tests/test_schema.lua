local R = require('tests.runner')
local build_schema, SCALARS
do
  local _obj_0 = require('graphql.schema')
  build_schema, SCALARS = _obj_0.build_schema, _obj_0.SCALARS
end
local BASIC_SDL = [[  type Query {
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
local s = build_schema(BASIC_SDL, { })
R.describe("Schema — built-in scalars", function()
  R.it("String is a SCALAR", function()
    local t = s:get_type('String')
    R.eq(t.kind, 'SCALAR')
    return R.eq(t.name, 'String')
  end)
  R.it("Int is a SCALAR", function()
    return R.eq((s:get_type('Int')).kind, 'SCALAR')
  end)
  R.it("Float is a SCALAR", function()
    return R.eq((s:get_type('Float')).kind, 'SCALAR')
  end)
  R.it("Boolean is a SCALAR", function()
    return R.eq((s:get_type('Boolean')).kind, 'SCALAR')
  end)
  return R.it("ID is a SCALAR", function()
    return R.eq((s:get_type('ID')).kind, 'SCALAR')
  end)
end)
R.describe("Schema — types defined in SDL", function()
  R.it("Query is an OBJECT", function()
    local t = s:get_type('Query')
    R.eq(t.kind, 'OBJECT')
    return R.eq(t.name, 'Query')
  end)
  R.it("User is an OBJECT", function()
    return R.eq((s:get_type('User')).kind, 'OBJECT')
  end)
  R.it("Color is an ENUM", function()
    local t = s:get_type('Color')
    R.eq(t.kind, 'ENUM')
    R.eq(t.name, 'Color')
    return R.eq(#t.values, 3)
  end)
  R.it("Node is an INTERFACE", function()
    return R.eq((s:get_type('Node')).kind, 'INTERFACE')
  end)
  R.it("SearchResult is a UNION", function()
    local t = s:get_type('SearchResult')
    R.eq(t.kind, 'UNION')
    return R.eq(#t.types, 2)
  end)
  R.it("CreateUserInput is an INPUT_OBJECT", function()
    local t = s:get_type('CreateUserInput')
    R.eq(t.kind, 'INPUT_OBJECT')
    return R.eq(t.name, 'CreateUserInput')
  end)
  R.it("Date is a custom scalar", function()
    local t = s:get_type('Date')
    return R.eq(t.kind, 'SCALAR')
  end)
  R.it("unknown type -> error", function()
    return R.raises((function()
      return s:get_type('Unknown')
    end), 'Unknown type')
  end)
  return R.it("find_type unknown -> nil", function()
    return R.is_nil((s:find_type('Unknown')))
  end)
end)
R.describe("Schema — object type fields", function()
  R.it("Query.hello exists", function()
    local t = s:get_type('Query')
    return R.ok(t.fields['hello'])
  end)
  R.it("Query.count is non-null", function()
    local t = s:get_type('Query')
    return R.eq(t.fields['count'].type.kind, 'NonNullType')
  end)
  R.it("User has 5 fields", function()
    local t = s:get_type('User')
    local count = 0
    for _ in pairs(t.fields) do
      count = count + 1
    end
    return R.eq(count, 5)
  end)
  return R.it("CreateUserInput.name is non-null", function()
    local t = s:get_type('CreateUserInput')
    return R.eq(t.fields['name'].type.kind, 'NonNullType')
  end)
end)
R.describe("Schema — is_leaf", function()
  R.it("String is a leaf", function()
    return R.ok(s:is_leaf('String'))
  end)
  R.it("Int is a leaf", function()
    return R.ok(s:is_leaf('Int'))
  end)
  R.it("Color (enum) is a leaf", function()
    return R.ok(s:is_leaf('Color'))
  end)
  R.it("Date (custom scalar) is a leaf", function()
    return R.ok(s:is_leaf('Date'))
  end)
  R.it("Query (object) is not a leaf", function()
    return R.nok(s:is_leaf('Query'))
  end)
  R.it("User (object) is not a leaf", function()
    return R.nok(s:is_leaf('User'))
  end)
  return R.it("Node (interface) is not a leaf", function()
    return R.nok(s:is_leaf('Node'))
  end)
end)
R.describe("Schema — named_type (unwrapping)", function()
  local named
  named = function(type_ref)
    return s:named_type(type_ref)
  end
  R.it("NamedType -> its name", function()
    return R.eq(named({
      kind = 'NamedType',
      name = 'String'
    }), 'String')
  end)
  R.it("NonNullType -> inner type", function()
    return R.eq(named({
      kind = 'NonNullType',
      ofType = {
        kind = 'NamedType',
        name = 'Int'
      }
    }), 'Int')
  end)
  R.it("ListType -> inner type", function()
    return R.eq(named({
      kind = 'ListType',
      ofType = {
        kind = 'NamedType',
        name = 'User'
      }
    }), 'User')
  end)
  return R.it("NonNull(List(NamedType))", function()
    return R.eq(named({
      kind = 'NonNullType',
      ofType = {
        kind = 'ListType',
        ofType = {
          kind = 'NamedType',
          name = 'String'
        }
      }
    }), 'String')
  end)
end)
R.describe("Schema — coerce_input scalars", function()
  local mk
  mk = function(name)
    return {
      kind = 'NamedType',
      name = name
    }
  end
  R.it("String: string -> string", function()
    return R.eq((s:coerce_input(mk('String'), 'hello')), 'hello')
  end)
  R.it("String: number -> string", function()
    return R.eq((s:coerce_input(mk('String'), 42)), '42')
  end)
  R.it("Int: numeric string -> integer", function()
    return R.eq((s:coerce_input(mk('Int'), '7')), 7)
  end)
  R.it("Int: float -> integer (floor)", function()
    return R.eq((s:coerce_input(mk('Int'), 3.9)), 3)
  end)
  R.it("Float: string -> float", function()
    return R.eq((s:coerce_input(mk('Float'), '3.14')), 3.14)
  end)
  R.it("Boolean: true -> true", function()
    return R.eq((s:coerce_input(mk('Boolean'), true)), true)
  end)
  R.it("Boolean: 'true' -> true", function()
    return R.eq((s:coerce_input(mk('Boolean'), 'true')), true)
  end)
  R.it("Boolean: false -> false", function()
    return R.eq((s:coerce_input(mk('Boolean'), false)), false)
  end)
  return R.it("ID: number -> string", function()
    return R.eq((s:coerce_input(mk('ID'), 99)), '99')
  end)
end)
R.describe("Schema — coerce_input list", function()
  local list_str = {
    kind = 'ListType',
    ofType = {
      kind = 'NamedType',
      name = 'Int'
    }
  }
  R.it("list of numeric strings -> list of integers", function()
    local result = s:coerce_input(list_str, {
      '1',
      '2',
      '3'
    })
    R.eq(result[1], 1)
    R.eq(result[2], 2)
    return R.eq(result[3], 3)
  end)
  return R.it("scalar value -> single-item list", function()
    local result = s:coerce_input(list_str, '5')
    return R.eq(result[1], 5)
  end)
end)
return R.describe("Schema — resolvers", function()
  local sdl2 = "type Query { greet: String }"
  local resolvers2 = {
    Query = {
      greet = function(_, __, ___)
        return "bonjour"
      end
    }
  }
  local s2 = build_schema(sdl2, resolvers2)
  R.it("custom resolver registered", function()
    local fn = s2:get_resolver('Query', 'greet')
    return R.eq((fn({ }, { }, { })), "bonjour")
  end)
  return R.it("field without resolver -> parent key access", function()
    local fn = s:get_resolver('User', 'name')
    local parent = {
      name = 'Alice'
    }
    return R.eq((fn(parent, { }, { })), 'Alice')
  end)
end)
