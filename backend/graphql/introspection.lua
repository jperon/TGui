local SDL = [[enum __TypeKind {
  SCALAR
  OBJECT
  INTERFACE
  UNION
  ENUM
  INPUT_OBJECT
  LIST
  NON_NULL
}

type __Schema {
  types: [__Type!]!
  queryType: __Type!
  mutationType: __Type
  subscriptionType: __Type
  directives: [__Directive!]!
}

type __Type {
  kind: __TypeKind!
  name: String
  description: String
  fields(includeDeprecated: Boolean): [__Field!]
  interfaces: [__Type!]
  possibleTypes: [__Type!]
  enumValues(includeDeprecated: Boolean): [__EnumValue!]
  inputFields: [__InputValue!]
  ofType: __Type
}

type __Field {
  name: String!
  description: String
  args: [__InputValue!]!
  type: __Type!
  isDeprecated: Boolean!
  deprecationReason: String
}

type __InputValue {
  name: String!
  description: String
  type: __Type!
  defaultValue: String
}

type __EnumValue {
  name: String!
  description: String
  isDeprecated: Boolean!
  deprecationReason: String
}

type __Directive {
  name: String!
  description: String
  locations: [String!]!
  args: [__InputValue!]!
}

extend type Query {
  __schema: __Schema!
  __type(name: String!): __Type
}
]]
local type_to_introspection = nil
local type_ref_to_introspection = nil
type_ref_to_introspection = function(type_ref, schema)
  if not (type_ref) then
    return nil
  end
  local _exp_0 = type_ref.kind
  if 'NonNullType' == _exp_0 then
    return {
      kind = 'NON_NULL',
      name = nil,
      ofType = type_ref_to_introspection(type_ref.ofType, schema)
    }
  elseif 'ListType' == _exp_0 then
    return {
      kind = 'LIST',
      name = nil,
      ofType = type_ref_to_introspection(type_ref.ofType, schema)
    }
  elseif 'NamedType' == _exp_0 then
    local t = schema.types[type_ref.name]
    if t then
      return type_to_introspection(t, schema)
    else
      return {
        kind = 'SCALAR',
        name = type_ref.name
      }
    end
  else
    return nil
  end
end
type_to_introspection = function(t, schema)
  if not (t) then
    return nil
  end
  return {
    kind = t.kind,
    name = t.name,
    description = t.description,
    ofType = nil,
    fields = function()
      if not (t.kind == 'OBJECT' or t.kind == 'INTERFACE') then
        return nil
      end
      local result = { }
      for fname, fdef in pairs((t.fields or { })) do
        if fname:sub(1, 2) ~= '__' then
          table.insert(result, {
            name = fdef.name or fname,
            description = fdef.description,
            isDeprecated = false,
            deprecationReason = nil,
            type = type_ref_to_introspection(fdef.type, schema),
            args = function()
              local aargs = { }
              local _list_0 = (fdef.arguments or { })
              for _index_0 = 1, #_list_0 do
                local adef = _list_0[_index_0]
                table.insert(aargs, {
                  name = adef.name,
                  description = adef.description,
                  type = type_ref_to_introspection(adef.type, schema),
                  defaultValue = adef.defaultValue and tostring(adef.defaultValue) or nil
                })
              end
              return aargs
            end
          })
        end
      end
      return result
    end,
    inputFields = function()
      if not (t.kind == 'INPUT_OBJECT') then
        return nil
      end
      local result = { }
      for fname, fdef in pairs((t.fields or { })) do
        table.insert(result, {
          name = fdef.name or fname,
          description = fdef.description,
          type = type_ref_to_introspection(fdef.type, schema),
          defaultValue = nil
        })
      end
      return result
    end,
    interfaces = function()
      if not (t.kind == 'OBJECT') then
        return nil
      end
      local result = { }
      local _list_0 = (t.interfaces or { })
      for _index_0 = 1, #_list_0 do
        local iname = _list_0[_index_0]
        local iface = schema.types[iname]
        if iface then
          table.insert(result, type_to_introspection(iface, schema))
        end
      end
      return result
    end,
    possibleTypes = function()
      if not (t.kind == 'INTERFACE' or t.kind == 'UNION') then
        return nil
      end
      local result = { }
      for tname, tdef in pairs(schema.types) do
        if tdef.kind == 'OBJECT' then
          local _list_0 = (tdef.interfaces or { })
          for _index_0 = 1, #_list_0 do
            local iname = _list_0[_index_0]
            if iname == t.name then
              table.insert(result, type_to_introspection(tdef, schema))
            end
          end
        end
      end
      return result
    end,
    enumValues = function()
      if not (t.kind == 'ENUM') then
        return nil
      end
      local result = { }
      local _list_0 = (t.values or { })
      for _index_0 = 1, #_list_0 do
        local ev = _list_0[_index_0]
        table.insert(result, {
          name = ev.name,
          description = ev.description,
          isDeprecated = false,
          deprecationReason = nil
        })
      end
      return result
    end
  }
end
local schema_resolver
schema_resolver = function(schema)
  local all_types = { }
  for tname, tdef in pairs(schema.types) do
    if tname:sub(1, 2) ~= '__' then
      table.insert(all_types, type_to_introspection(tdef, schema))
    end
  end
  return {
    types = all_types,
    queryType = type_to_introspection(schema.types[schema.query_type], schema),
    mutationType = schema.mutation_type and type_to_introspection(schema.types[schema.mutation_type], schema) or nil,
    subscriptionType = schema.subscription_type and type_to_introspection(schema.types[schema.subscription_type], schema) or nil,
    directives = { }
  }
end
local type_resolver
type_resolver = function(schema, name)
  local t = schema.types[name]
  if t then
    return type_to_introspection(t, schema)
  else
    return nil
  end
end
local lazy
lazy = function(fname)
  return function(obj)
    local v = obj[fname]
    if type(v) == 'function' then
      return v()
    else
      return v
    end
  end
end
local RESOLVERS = {
  Query = {
    __schema = function(obj, args, ctx, info)
      return schema_resolver(info.schema)
    end,
    __type = function(obj, args, ctx, info)
      return type_resolver(info.schema, args.name)
    end
  },
  __Type = {
    fields = lazy('fields'),
    inputFields = lazy('inputFields'),
    interfaces = lazy('interfaces'),
    possibleTypes = lazy('possibleTypes'),
    enumValues = lazy('enumValues')
  },
  __Field = {
    args = lazy('args')
  }
}
return {
  SDL = SDL,
  RESOLVERS = RESOLVERS,
  schema_resolver = schema_resolver,
  type_resolver = type_resolver,
  type_to_introspection = type_to_introspection,
  type_ref_to_introspection = type_ref_to_introspection
}
