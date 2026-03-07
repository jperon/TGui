local parse
parse = require('graphql.parser').parse
local SCALARS = {
  String = {
    kind = 'SCALAR',
    name = 'String',
    coerce_input = function(v)
      return tostring(v)
    end,
    coerce_output = function(v)
      return tostring(v)
    end
  },
  Int = {
    kind = 'SCALAR',
    name = 'Int',
    coerce_input = function(v)
      local n = tonumber(v)
      if n ~= nil then
        return math.floor(n)
      end
    end,
    coerce_output = function(v)
      local n = tonumber(v)
      if n ~= nil then
        return math.floor(n)
      end
    end
  },
  Float = {
    kind = 'SCALAR',
    name = 'Float',
    coerce_input = function(v)
      return tonumber(v)
    end,
    coerce_output = function(v)
      return tonumber(v)
    end
  },
  Boolean = {
    kind = 'SCALAR',
    name = 'Boolean',
    coerce_input = function(v)
      return v == true or v == 'true'
    end,
    coerce_output = function(v)
      return v == true
    end
  },
  ID = {
    kind = 'SCALAR',
    name = 'ID',
    coerce_input = function(v)
      return tostring(v)
    end,
    coerce_output = function(v)
      return tostring(v)
    end
  }
}
local Schema
do
  local _class_0
  local _base_0 = {
    _build = function(self, doc)
      local _list_0 = doc.definitions
      for _index_0 = 1, #_list_0 do
        local def = _list_0[_index_0]
        local _exp_0 = def.kind
        if 'ObjectTypeDefinition' == _exp_0 then
          self.types[def.name] = {
            kind = 'OBJECT',
            name = def.name,
            description = def.description,
            interfaces = def.interfaces,
            fields = { },
            directives = def.directives,
            _def = def
          }
        elseif 'InterfaceTypeDefinition' == _exp_0 then
          self.types[def.name] = {
            kind = 'INTERFACE',
            name = def.name,
            description = def.description,
            fields = { },
            directives = def.directives,
            _def = def
          }
        elseif 'UnionTypeDefinition' == _exp_0 then
          self.types[def.name] = {
            kind = 'UNION',
            name = def.name,
            description = def.description,
            types = def.types,
            directives = def.directives
          }
        elseif 'EnumTypeDefinition' == _exp_0 then
          self.types[def.name] = {
            kind = 'ENUM',
            name = def.name,
            description = def.description,
            values = def.values,
            directives = def.directives
          }
        elseif 'InputObjectTypeDefinition' == _exp_0 then
          self.types[def.name] = {
            kind = 'INPUT_OBJECT',
            name = def.name,
            description = def.description,
            fields = { },
            directives = def.directives,
            _def = def
          }
        elseif 'ScalarTypeDefinition' == _exp_0 then
          self.types[def.name] = {
            kind = 'SCALAR',
            name = def.name,
            description = def.description,
            directives = def.directives
          }
        elseif 'SchemaDefinition' == _exp_0 then
          local _list_1 = def.operationTypes
          for _index_1 = 1, #_list_1 do
            local op = _list_1[_index_1]
            local _exp_1 = op.operation
            if 'query' == _exp_1 then
              self.query_type = op.type
            elseif 'mutation' == _exp_1 then
              self.mutation_type = op.type
            elseif 'subscription' == _exp_1 then
              self.subscription_type = op.type
            end
          end
        end
      end
      local _list_1 = doc.definitions
      for _index_0 = 1, #_list_1 do
        local def = _list_1[_index_0]
        local _exp_0 = def.kind
        if 'ObjectTypeDefinition' == _exp_0 or 'InterfaceTypeDefinition' == _exp_0 then
          local t = self.types[def.name]
          local _list_2 = def.fields
          for _index_1 = 1, #_list_2 do
            local fdef = _list_2[_index_1]
            t.fields[fdef.name] = self:_build_field(fdef)
          end
        elseif 'ObjectTypeExtension' == _exp_0 or 'InterfaceTypeExtension' == _exp_0 then
          local t = self.types[def.name]
          if t then
            local _list_2 = (def.fields or { })
            for _index_1 = 1, #_list_2 do
              local fdef = _list_2[_index_1]
              t.fields[fdef.name] = self:_build_field(fdef)
            end
          end
        elseif 'InputObjectTypeDefinition' == _exp_0 or 'InputObjectTypeExtension' == _exp_0 then
          local t = self.types[def.name]
          if t then
            local _list_2 = (def.fields or { })
            for _index_1 = 1, #_list_2 do
              local fdef = _list_2[_index_1]
              t.fields[fdef.name] = {
                name = fdef.name,
                description = fdef.description,
                type = fdef.type,
                defaultValue = fdef.defaultValue
              }
            end
          end
        end
      end
      self.query_type = self.query_type or 'Query'
      self.mutation_type = self.mutation_type or 'Mutation'
    end,
    _build_field = function(self, fdef)
      return {
        name = fdef.name,
        description = fdef.description,
        type = fdef.type,
        arguments = fdef.arguments,
        directives = fdef.directives
      }
    end,
    get_type = function(self, name)
      return self.types[name] or error("Unknown type: " .. tostring(name))
    end,
    find_type = function(self, name)
      return self.types[name]
    end,
    get_resolver = function(self, type_name, field_name)
      local type_resolvers = self.resolvers[type_name]
      if type_resolvers then
        local fn = type_resolvers[field_name]
        if fn then
          return fn
        end
      end
      return function(obj, args, ctx, info)
        if type(obj) == 'table' then
          return obj[field_name]
        end
      end
    end,
    is_leaf = function(self, type_name)
      local t = self.types[type_name]
      return t and (t.kind == 'SCALAR' or t.kind == 'ENUM')
    end,
    named_type = function(self, type_ref)
      local _exp_0 = type_ref.kind
      if 'NamedType' == _exp_0 then
        return type_ref.name
      elseif 'ListType' == _exp_0 then
        return self:named_type(type_ref.ofType)
      elseif 'NonNullType' == _exp_0 then
        return self:named_type(type_ref.ofType)
      else
        return error("Unknown type ref kind: " .. tostring(type_ref.kind))
      end
    end,
    coerce_input = function(self, type_ref, value)
      if type_ref.kind == 'NonNullType' then
        if value == nil then
          error("Non-null field received null")
        end
        return self:coerce_input(type_ref.ofType, value)
      end
      if value == nil then
        return nil
      end
      if type_ref.kind == 'ListType' then
        if type(value) ~= 'table' then
          return {
            self:coerce_input(type_ref.ofType, value)
          }
        end
        local result = { }
        for _index_0 = 1, #value do
          local v = value[_index_0]
          table.insert(result, self:coerce_input(type_ref.ofType, v))
        end
        return result
      end
      local t = self.types[type_ref.name]
      if not t then
        error("Unknown type: " .. tostring(type_ref.name))
      end
      if t.kind == 'SCALAR' then
        if t.coerce_input then
          return t.coerce_input(value)
        end
        return value
      end
      if t.kind == 'ENUM' then
        return value
      end
      if t.kind == 'INPUT_OBJECT' then
        if type(value) ~= 'table' then
          error("Expected object for input type " .. tostring(t.name))
        end
        local result = { }
        for fname, fdef in pairs(t.fields) do
          result[fname] = self:coerce_input(fdef.type, value[fname])
        end
        return result
      end
      return error("Cannot coerce input of kind " .. tostring(t.kind))
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, sdl_or_ast, resolvers)
      if resolvers == nil then
        resolvers = { }
      end
      self.types = { }
      self.resolvers = resolvers
      self.query_type = nil
      self.mutation_type = nil
      self.subscription_type = nil
      for name, scalar in pairs(SCALARS) do
        self.types[name] = scalar
      end
      self.types['__Schema'] = {
        name = '__Schema',
        kind = 'OBJECT'
      }
      self.types['__Type'] = {
        name = '__Type',
        kind = 'OBJECT'
      }
      self.types['__Field'] = {
        name = '__Field',
        kind = 'OBJECT'
      }
      self.types['__InputValue'] = {
        name = '__InputValue',
        kind = 'OBJECT'
      }
      self.types['__EnumValue'] = {
        name = '__EnumValue',
        kind = 'OBJECT'
      }
      self.types['__Directive'] = {
        name = '__Directive',
        kind = 'OBJECT'
      }
      self.types['__TypeKind'] = {
        name = '__TypeKind',
        kind = 'ENUM'
      }
      self.types['__DirectiveLocation'] = {
        name = '__DirectiveLocation',
        kind = 'ENUM'
      }
      local doc
      if type(sdl_or_ast) == 'string' then
        doc = parse(sdl_or_ast)
      else
        doc = sdl_or_ast
      end
      return self:_build(doc)
    end,
    __base = _base_0,
    __name = "Schema"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Schema = _class_0
end
local build_schema
build_schema = function(sdl, resolvers)
  return Schema(sdl, resolvers)
end
return {
  Schema = Schema,
  build_schema = build_schema,
  SCALARS = SCALARS
}
