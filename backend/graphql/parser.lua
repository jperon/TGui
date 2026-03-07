local T, tokenize
do
  local _obj_0 = require('graphql.lexer')
  T, tokenize = _obj_0.TOKEN_TYPES, _obj_0.tokenize
end
local Parser
do
  local _class_0
  local _base_0 = {
    peek = function(self, offset)
      if offset == nil then
        offset = 0
      end
      return self.tokens[self.pos + offset] or {
        type = T.EOF
      }
    end,
    consume = function(self, expected_type)
      local tok = self.tokens[self.pos]
      if not tok or tok.type == T.EOF then
        error("Unexpected EOF, expected " .. tostring(expected_type))
      end
      if expected_type and tok.type ~= expected_type then
        error("Expected " .. tostring(expected_type) .. ", got " .. tostring(tok.type) .. " (" .. tostring(tok.value) .. ")")
      end
      self.pos = self.pos + 1
      return tok
    end,
    consume_keyword = function(self, kw)
      local tok = self:peek()
      if tok.type == T.NAME and tok.value == kw then
        self.pos = self.pos + 1
        return tok
      end
    end,
    expect_keyword = function(self, kw)
      local tok = self:consume_keyword(kw)
      if not (tok) then
        error("Expected keyword '" .. tostring(kw) .. "', got " .. tostring(self:peek().value))
      end
      return tok
    end,
    peek_keyword = function(self, kw)
      local tok = self:peek()
      return tok.type == T.NAME and tok.value == kw
    end,
    parse_document = function(self)
      local definitions = { }
      while self:peek().type ~= T.EOF do
        table.insert(definitions, self:parse_definition())
      end
      return {
        kind = 'Document',
        definitions = definitions
      }
    end,
    parse_definition = function(self)
      local tok = self:peek()
      if tok.type == T.BRACE_L then
        return self:parse_operation_definition()
      end
      local description = nil
      if tok.type == T.BLOCK_STRING or tok.type == T.STRING then
        description = self:consume(self:peek().type).value
        tok = self:peek()
      end
      if tok.type == T.NAME then
        local _exp_0 = tok.value
        if 'query' == _exp_0 or 'mutation' == _exp_0 or 'subscription' == _exp_0 then
          return self:parse_operation_definition()
        elseif 'fragment' == _exp_0 then
          return self:parse_fragment_definition()
        elseif 'type' == _exp_0 or 'interface' == _exp_0 or 'union' == _exp_0 or 'enum' == _exp_0 or 'input' == _exp_0 or 'scalar' == _exp_0 or 'directive' == _exp_0 or 'schema' == _exp_0 or 'extend' == _exp_0 then
          return self:parse_type_system_definition(description)
        end
      end
      return error("Unexpected token: " .. tostring(tok.type) .. " " .. tostring(tok.value))
    end,
    parse_operation_definition = function(self)
      local op_tok = self:peek()
      local operation = 'query'
      local name = nil
      local var_defs = { }
      local directives = { }
      if op_tok.type ~= T.BRACE_L then
        operation = self:consume(T.NAME).value
        if self:peek().type == T.NAME then
          name = self:consume(T.NAME).value
        end
        var_defs = self:parse_variable_definitions()
        directives = self:parse_directives()
      end
      local selection_set = self:parse_selection_set()
      return {
        kind = 'OperationDefinition',
        operation = operation,
        name = name,
        variableDefs = var_defs,
        directives = directives,
        selectionSet = selection_set
      }
    end,
    parse_variable_definitions = function(self)
      local defs = { }
      if self:peek().type ~= T.PAREN_L then
        return defs
      end
      self:consume(T.PAREN_L)
      while self:peek().type ~= T.PAREN_R do
        table.insert(defs, self:parse_variable_definition())
      end
      self:consume(T.PAREN_R)
      return defs
    end,
    parse_variable_definition = function(self)
      self:consume(T.DOLLAR)
      local name = self:consume(T.NAME).value
      self:consume(T.COLON)
      local type_ref = self:parse_type_ref()
      local default_value = nil
      if self:peek().type == T.EQUALS then
        self:consume(T.EQUALS)
        default_value = self:parse_value(true)
      end
      return {
        kind = 'VariableDefinition',
        name = name,
        type = type_ref,
        defaultValue = default_value
      }
    end,
    parse_selection_set = function(self)
      self:consume(T.BRACE_L)
      local selections = { }
      while self:peek().type ~= T.BRACE_R do
        table.insert(selections, self:parse_selection())
      end
      self:consume(T.BRACE_R)
      return {
        kind = 'SelectionSet',
        selections = selections
      }
    end,
    parse_selection = function(self)
      if self:peek().type == T.SPREAD then
        return self:parse_fragment_or_inline()
      end
      return self:parse_field()
    end,
    parse_field = function(self)
      local tok = self:consume(T.NAME)
      local alias = nil
      local name = tok.value
      if self:peek().type == T.COLON then
        self:consume(T.COLON)
        alias = name
        name = self:consume(T.NAME).value
      end
      local args = self:parse_arguments(false)
      local directives = self:parse_directives()
      local sel_set = nil
      if self:peek().type == T.BRACE_L then
        sel_set = self:parse_selection_set()
      end
      return {
        kind = 'Field',
        alias = alias,
        name = name,
        arguments = args,
        directives = directives,
        selectionSet = sel_set
      }
    end,
    parse_fragment_or_inline = function(self)
      self:consume(T.SPREAD)
      if self:peek().type == T.NAME and self:peek().value ~= 'on' then
        local name = self:consume(T.NAME).value
        local dirs = self:parse_directives()
        return {
          kind = 'FragmentSpread',
          name = name,
          directives = dirs
        }
      end
      local type_condition = nil
      if self:peek_keyword('on') then
        self:consume_keyword('on')
        type_condition = self:consume(T.NAME).value
      end
      local dirs = self:parse_directives()
      local sel_set = self:parse_selection_set()
      return {
        kind = 'InlineFragment',
        typeCondition = type_condition,
        directives = dirs,
        selectionSet = sel_set
      }
    end,
    parse_fragment_definition = function(self)
      self:expect_keyword('fragment')
      local name = self:consume(T.NAME).value
      self:expect_keyword('on')
      local type_condition = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local sel_set = self:parse_selection_set()
      return {
        kind = 'FragmentDefinition',
        name = name,
        typeCondition = type_condition,
        directives = dirs,
        selectionSet = sel_set
      }
    end,
    parse_arguments = function(self, is_const)
      local args = { }
      if self:peek().type ~= T.PAREN_L then
        return args
      end
      self:consume(T.PAREN_L)
      while self:peek().type ~= T.PAREN_R do
        local name = self:consume(T.NAME).value
        self:consume(T.COLON)
        local value = self:parse_value(is_const)
        table.insert(args, {
          name = name,
          value = value
        })
      end
      self:consume(T.PAREN_R)
      return args
    end,
    parse_value = function(self, is_const)
      local tok = self:peek()
      local _exp_0 = tok.type
      if T.BRACKET_L == _exp_0 then
        return self:parse_list_value(is_const)
      elseif T.BRACE_L == _exp_0 then
        return self:parse_object_value(is_const)
      elseif T.INT == _exp_0 then
        self:consume(T.INT)
        return {
          kind = 'IntValue',
          value = tok.value
        }
      elseif T.FLOAT == _exp_0 then
        self:consume(T.FLOAT)
        return {
          kind = 'FloatValue',
          value = tok.value
        }
      elseif T.STRING == _exp_0 then
        self:consume(T.STRING)
        return {
          kind = 'StringValue',
          value = tok.value
        }
      elseif T.BLOCK_STRING == _exp_0 then
        self:consume(T.BLOCK_STRING)
        return {
          kind = 'StringValue',
          value = tok.value,
          block = true
        }
      elseif T.NAME == _exp_0 then
        local _exp_1 = tok.value
        if 'true' == _exp_1 then
          self:consume(T.NAME)
          return {
            kind = 'BooleanValue',
            value = true
          }
        elseif 'false' == _exp_1 then
          self:consume(T.NAME)
          return {
            kind = 'BooleanValue',
            value = false
          }
        elseif 'null' == _exp_1 then
          self:consume(T.NAME)
          return {
            kind = 'NullValue'
          }
        else
          self:consume(T.NAME)
          return {
            kind = 'EnumValue',
            value = tok.value
          }
        end
      elseif T.DOLLAR == _exp_0 then
        if is_const then
          error("Variable not allowed in constant context")
        end
        self:consume(T.DOLLAR)
        local name = self:consume(T.NAME).value
        return {
          kind = 'Variable',
          name = name
        }
      else
        return error("Unexpected value token: " .. tostring(tok.type))
      end
    end,
    parse_list_value = function(self, is_const)
      self:consume(T.BRACKET_L)
      local values = { }
      while self:peek().type ~= T.BRACKET_R do
        table.insert(values, self:parse_value(is_const))
      end
      self:consume(T.BRACKET_R)
      return {
        kind = 'ListValue',
        values = values
      }
    end,
    parse_object_value = function(self, is_const)
      self:consume(T.BRACE_L)
      local fields = { }
      while self:peek().type ~= T.BRACE_R do
        local name = self:consume(T.NAME).value
        self:consume(T.COLON)
        local value = self:parse_value(is_const)
        table.insert(fields, {
          name = name,
          value = value
        })
      end
      self:consume(T.BRACE_R)
      return {
        kind = 'ObjectValue',
        fields = fields
      }
    end,
    parse_type_ref = function(self)
      local type_ref
      if self:peek().type == T.BRACKET_L then
        self:consume(T.BRACKET_L)
        local inner = self:parse_type_ref()
        self:consume(T.BRACKET_R)
        type_ref = {
          kind = 'ListType',
          ofType = inner
        }
      else
        local name = self:consume(T.NAME).value
        type_ref = {
          kind = 'NamedType',
          name = name
        }
      end
      if self:peek().type == T.BANG then
        self:consume(T.BANG)
        type_ref = {
          kind = 'NonNullType',
          ofType = type_ref
        }
      end
      return type_ref
    end,
    parse_directives = function(self)
      local dirs = { }
      while self:peek().type == T.AT do
        table.insert(dirs, self:parse_directive())
      end
      return dirs
    end,
    parse_directive = function(self)
      self:consume(T.AT)
      local name = self:consume(T.NAME).value
      local args = self:parse_arguments(false)
      return {
        kind = 'Directive',
        name = name,
        arguments = args
      }
    end,
    parse_type_system_definition = function(self, description)
      description = description or nil
      local kw = self:peek().value
      local _exp_0 = kw
      if 'schema' == _exp_0 then
        return self:parse_schema_definition(description)
      elseif 'scalar' == _exp_0 then
        return self:parse_scalar_type(description)
      elseif 'type' == _exp_0 then
        return self:parse_object_type(description)
      elseif 'interface' == _exp_0 then
        return self:parse_interface_type(description)
      elseif 'union' == _exp_0 then
        return self:parse_union_type(description)
      elseif 'enum' == _exp_0 then
        return self:parse_enum_type(description)
      elseif 'input' == _exp_0 then
        return self:parse_input_type(description)
      elseif 'directive' == _exp_0 then
        return self:parse_directive_definition(description)
      elseif 'extend' == _exp_0 then
        return self:parse_type_extension()
      else
        return error("Unknown type system keyword: " .. tostring(kw))
      end
    end,
    parse_schema_definition = function(self, description)
      self:expect_keyword('schema')
      local dirs = self:parse_directives()
      self:consume(T.BRACE_L)
      local ops = { }
      while self:peek().type ~= T.BRACE_R do
        local op = self:consume(T.NAME).value
        self:consume(T.COLON)
        local type_name = self:consume(T.NAME).value
        table.insert(ops, {
          operation = op,
          type = type_name
        })
      end
      self:consume(T.BRACE_R)
      return {
        kind = 'SchemaDefinition',
        description = description,
        directives = dirs,
        operationTypes = ops
      }
    end,
    parse_scalar_type = function(self, description)
      self:expect_keyword('scalar')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      return {
        kind = 'ScalarTypeDefinition',
        description = description,
        name = name,
        directives = dirs
      }
    end,
    parse_object_type = function(self, description)
      self:expect_keyword('type')
      local name = self:consume(T.NAME).value
      local interfaces = self:parse_implements()
      local dirs = self:parse_directives()
      local fields = self:parse_fields_definition()
      return {
        kind = 'ObjectTypeDefinition',
        description = description,
        name = name,
        interfaces = interfaces,
        directives = dirs,
        fields = fields
      }
    end,
    parse_implements = function(self)
      local ifaces = { }
      if not self:peek_keyword('implements') then
        return ifaces
      end
      self:consume_keyword('implements')
      self:consume_keyword('and')
      while self:peek().type == T.NAME and self:peek().value ~= 'implements' do
        table.insert(ifaces, self:consume(T.NAME).value)
        if self:peek().type == T.AMP then
          self:consume(T.AMP)
        end
      end
      return ifaces
    end,
    parse_interface_type = function(self, description)
      self:expect_keyword('interface')
      local name = self:consume(T.NAME).value
      local interfaces = self:parse_implements()
      local dirs = self:parse_directives()
      local fields = self:parse_fields_definition()
      return {
        kind = 'InterfaceTypeDefinition',
        description = description,
        name = name,
        interfaces = interfaces,
        directives = dirs,
        fields = fields
      }
    end,
    parse_union_type = function(self, description)
      self:expect_keyword('union')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local types = { }
      if self:peek().type == T.EQUALS then
        self:consume(T.EQUALS)
        if self:peek().type == T.PIPE then
          self:consume(T.PIPE)
        end
        table.insert(types, self:consume(T.NAME).value)
        while self:peek().type == T.PIPE do
          self:consume(T.PIPE)
          table.insert(types, self:consume(T.NAME).value)
        end
      end
      return {
        kind = 'UnionTypeDefinition',
        description = description,
        name = name,
        directives = dirs,
        types = types
      }
    end,
    parse_enum_type = function(self, description)
      self:expect_keyword('enum')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      self:consume(T.BRACE_L)
      local values = { }
      while self:peek().type ~= T.BRACE_R do
        local vdesc = nil
        if self:peek().type == T.STRING or self:peek().type == T.BLOCK_STRING then
          vdesc = self:consume(self:peek().type).value
        end
        local vname = self:consume(T.NAME).value
        local vdirs = self:parse_directives()
        table.insert(values, {
          kind = 'EnumValueDefinition',
          description = vdesc,
          name = vname,
          directives = vdirs
        })
      end
      self:consume(T.BRACE_R)
      return {
        kind = 'EnumTypeDefinition',
        description = description,
        name = name,
        directives = dirs,
        values = values
      }
    end,
    parse_input_type = function(self, description)
      self:expect_keyword('input')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local fields = self:parse_input_fields_definition()
      return {
        kind = 'InputObjectTypeDefinition',
        description = description,
        name = name,
        directives = dirs,
        fields = fields
      }
    end,
    parse_fields_definition = function(self)
      self:consume(T.BRACE_L)
      local fields = { }
      while self:peek().type ~= T.BRACE_R do
        local fdesc = nil
        if self:peek().type == T.STRING or self:peek().type == T.BLOCK_STRING then
          fdesc = self:consume(self:peek().type).value
        end
        local fname = self:consume(T.NAME).value
        local fargs = self:parse_arguments_definition()
        self:consume(T.COLON)
        local ftype = self:parse_type_ref()
        local fdirs = self:parse_directives()
        table.insert(fields, {
          kind = 'FieldDefinition',
          description = fdesc,
          name = fname,
          arguments = fargs,
          type = ftype,
          directives = fdirs
        })
      end
      self:consume(T.BRACE_R)
      return fields
    end,
    parse_arguments_definition = function(self)
      local args = { }
      if self:peek().type ~= T.PAREN_L then
        return args
      end
      self:consume(T.PAREN_L)
      while self:peek().type ~= T.PAREN_R do
        local adesc = nil
        if self:peek().type == T.STRING or self:peek().type == T.BLOCK_STRING then
          adesc = self:consume(self:peek().type).value
        end
        local aname = self:consume(T.NAME).value
        self:consume(T.COLON)
        local atype = self:parse_type_ref()
        local adefault = nil
        if self:peek().type == T.EQUALS then
          self:consume(T.EQUALS)
          adefault = self:parse_value(true)
        end
        local adirs = self:parse_directives()
        table.insert(args, {
          kind = 'InputValueDefinition',
          description = adesc,
          name = aname,
          type = atype,
          defaultValue = adefault,
          directives = adirs
        })
      end
      self:consume(T.PAREN_R)
      return args
    end,
    parse_input_fields_definition = function(self)
      self:consume(T.BRACE_L)
      local fields = { }
      while self:peek().type ~= T.BRACE_R do
        local fdesc = nil
        if self:peek().type == T.STRING or self:peek().type == T.BLOCK_STRING then
          fdesc = self:consume(self:peek().type).value
        end
        local fname = self:consume(T.NAME).value
        self:consume(T.COLON)
        local ftype = self:parse_type_ref()
        local fdefault = nil
        if self:peek().type == T.EQUALS then
          self:consume(T.EQUALS)
          fdefault = self:parse_value(true)
        end
        local fdirs = self:parse_directives()
        table.insert(fields, {
          kind = 'InputValueDefinition',
          description = fdesc,
          name = fname,
          type = ftype,
          defaultValue = fdefault,
          directives = fdirs
        })
      end
      self:consume(T.BRACE_R)
      return fields
    end,
    parse_directive_definition = function(self, description)
      self:expect_keyword('directive')
      self:consume(T.AT)
      local name = self:consume(T.NAME).value
      local args = self:parse_arguments_definition()
      self:consume_keyword('repeatable')
      self:expect_keyword('on')
      local locations = { }
      if self:peek().type == T.PIPE then
        self:consume(T.PIPE)
      end
      while self:peek().type == T.NAME do
        table.insert(locations, self:consume(T.NAME).value)
        if self:peek().type == T.PIPE then
          self:consume(T.PIPE)
        end
      end
      return {
        kind = 'DirectiveDefinition',
        description = description,
        name = name,
        arguments = args,
        locations = locations
      }
    end,
    parse_type_extension = function(self)
      self:expect_keyword('extend')
      local kw = self:peek().value
      local _exp_0 = kw
      if 'type' == _exp_0 then
        return self:parse_object_type_extension()
      elseif 'interface' == _exp_0 then
        return self:parse_interface_type_extension()
      elseif 'enum' == _exp_0 then
        return self:parse_enum_type_extension()
      elseif 'input' == _exp_0 then
        return self:parse_input_type_extension()
      elseif 'union' == _exp_0 then
        return self:parse_union_type_extension()
      elseif 'scalar' == _exp_0 then
        return self:parse_scalar_type_extension()
      elseif 'schema' == _exp_0 then
        return self:parse_schema_extension()
      else
        return error("Unknown extend keyword: " .. tostring(kw))
      end
    end,
    parse_object_type_extension = function(self)
      self:expect_keyword('type')
      local name = self:consume(T.NAME).value
      local interfaces = self:parse_implements()
      local dirs = self:parse_directives()
      local fields
      if self:peek().type == T.BRACE_L then
        fields = self:parse_fields_definition()
      else
        fields = { }
      end
      return {
        kind = 'ObjectTypeExtension',
        name = name,
        interfaces = interfaces,
        directives = dirs,
        fields = fields
      }
    end,
    parse_interface_type_extension = function(self)
      self:expect_keyword('interface')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local fields
      if self:peek().type == T.BRACE_L then
        fields = self:parse_fields_definition()
      else
        fields = { }
      end
      return {
        kind = 'InterfaceTypeExtension',
        name = name,
        directives = dirs,
        fields = fields
      }
    end,
    parse_enum_type_extension = function(self)
      self:expect_keyword('enum')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local values
      if self:peek().type == T.BRACE_L then
        self:consume(T.BRACE_L)
        local vs = { }
        while self:peek().type ~= T.BRACE_R do
          local vname = self:consume(T.NAME).value
          local vdirs = self:parse_directives()
          table.insert(vs, {
            kind = 'EnumValueDefinition',
            name = vname,
            directives = vdirs
          })
        end
        self:consume(T.BRACE_R)
        values = vs
      else
        values = { }
      end
      return {
        kind = 'EnumTypeExtension',
        name = name,
        directives = dirs,
        values = values
      }
    end,
    parse_input_type_extension = function(self)
      self:expect_keyword('input')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local fields
      if self:peek().type == T.BRACE_L then
        fields = self:parse_input_fields_definition()
      else
        fields = { }
      end
      return {
        kind = 'InputObjectTypeExtension',
        name = name,
        directives = dirs,
        fields = fields
      }
    end,
    parse_union_type_extension = function(self)
      self:expect_keyword('union')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      local types = { }
      if self:peek().type == T.EQUALS then
        self:consume(T.EQUALS)
        if self:peek().type == T.PIPE then
          self:consume(T.PIPE)
        end
        table.insert(types, self:consume(T.NAME).value)
        while self:peek().type == T.PIPE do
          self:consume(T.PIPE)
          table.insert(types, self:consume(T.NAME).value)
        end
      end
      return {
        kind = 'UnionTypeExtension',
        name = name,
        directives = dirs,
        types = types
      }
    end,
    parse_scalar_type_extension = function(self)
      self:expect_keyword('scalar')
      local name = self:consume(T.NAME).value
      local dirs = self:parse_directives()
      return {
        kind = 'ScalarTypeExtension',
        name = name,
        directives = dirs
      }
    end,
    parse_schema_extension = function(self)
      self:expect_keyword('schema')
      local dirs = self:parse_directives()
      local ops = { }
      if self:peek().type == T.BRACE_L then
        self:consume(T.BRACE_L)
        while self:peek().type ~= T.BRACE_R do
          local op = self:consume(T.NAME).value
          self:consume(T.COLON)
          local type_name = self:consume(T.NAME).value
          table.insert(ops, {
            operation = op,
            type = type_name
          })
        end
        self:consume(T.BRACE_R)
      end
      return {
        kind = 'SchemaExtension',
        directives = dirs,
        operationTypes = ops
      }
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, source)
      self.tokens = tokenize(source)
      self.pos = 1
    end,
    __base = _base_0,
    __name = "Parser"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Parser = _class_0
end
local parse
parse = function(source)
  return Parser(source):parse_document()
end
return {
  Parser = Parser,
  parse = parse
}
