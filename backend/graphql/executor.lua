local parse
parse = require('graphql.parser').parse
local build_schema
build_schema = require('graphql.schema').build_schema
local json_null = (require('json')).NULL
local _schema = nil
local _reinit_fn = nil
local extend
extend = function(t, item)
  local r = {
    unpack(t)
  }
  table.insert(r, item)
  return r
end
local resolve_value
resolve_value = function(value_node, variables)
  local _exp_0 = value_node.kind
  if 'Variable' == _exp_0 then
    return variables[value_node.name]
  elseif 'IntValue' == _exp_0 then
    return tonumber(value_node.value)
  elseif 'FloatValue' == _exp_0 then
    return tonumber(value_node.value)
  elseif 'StringValue' == _exp_0 then
    return value_node.value
  elseif 'BooleanValue' == _exp_0 then
    return value_node.value
  elseif 'NullValue' == _exp_0 then
    return nil
  elseif 'EnumValue' == _exp_0 then
    return value_node.value
  elseif 'ListValue' == _exp_0 then
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = value_node.values
    for _index_0 = 1, #_list_0 do
      local v = _list_0[_index_0]
      _accum_0[_len_0] = resolve_value(v, variables)
      _len_0 = _len_0 + 1
    end
    return _accum_0
  elseif 'ObjectValue' == _exp_0 then
    local obj = { }
    local _list_0 = value_node.fields
    for _index_0 = 1, #_list_0 do
      local f = _list_0[_index_0]
      obj[f.name] = resolve_value(f.value, variables)
    end
    return obj
  else
    return nil
  end
end
local collect_args
collect_args = function(field_node, field_def, variables, schema)
  local args = { }
  if not field_def or not field_def.arguments then
    return args
  end
  local arg_defs = { }
  local _list_0 = (field_def.arguments or { })
  for _index_0 = 1, #_list_0 do
    local adef = _list_0[_index_0]
    arg_defs[adef.name] = adef
  end
  local _list_1 = (field_node.arguments or { })
  for _index_0 = 1, #_list_1 do
    local arg = _list_1[_index_0]
    local adef = arg_defs[arg.name]
    local raw = resolve_value(arg.value, variables)
    if adef then
      args[arg.name] = schema:coerce_input(adef.type, raw)
    else
      args[arg.name] = raw
    end
  end
  for aname, adef in pairs(arg_defs) do
    if args[aname] == nil and adef.defaultValue ~= nil then
      args[aname] = resolve_value(adef.defaultValue, { })
    end
  end
  return args
end
local collect_fragments
collect_fragments = function(document)
  local frags = { }
  local _list_0 = document.definitions
  for _index_0 = 1, #_list_0 do
    local def = _list_0[_index_0]
    if def.kind == 'FragmentDefinition' then
      frags[def.name] = def
    end
  end
  return frags
end
local collect_fields
collect_fields = function(type_name, selection_set, fragments, variables)
  local fields = { }
  local seen = { }
  local _list_0 = selection_set.selections
  for _index_0 = 1, #_list_0 do
    local sel = _list_0[_index_0]
    local _exp_0 = sel.kind
    if 'Field' == _exp_0 then
      local rkey = sel.alias or sel.name
      if not seen[rkey] then
        seen[rkey] = true
        table.insert(fields, {
          name = sel.name,
          alias = rkey,
          node = sel
        })
      end
    elseif 'FragmentSpread' == _exp_0 then
      local frag = fragments[sel.name]
      if frag then
        local sub = collect_fields(type_name, frag.selectionSet, fragments, variables)
        for _index_1 = 1, #sub do
          local f = sub[_index_1]
          if not seen[f.alias] then
            seen[f.alias] = true
            table.insert(fields, f)
          end
        end
      end
    elseif 'InlineFragment' == _exp_0 then
      if not sel.typeCondition or sel.typeCondition == type_name then
        local sub = collect_fields(type_name, sel.selectionSet, fragments, variables)
        for _index_1 = 1, #sub do
          local f = sub[_index_1]
          if not seen[f.alias] then
            seen[f.alias] = true
            table.insert(fields, f)
          end
        end
      end
    end
  end
  return fields
end
local Executor
do
  local _class_0
  local _base_0 = {
    add_error = function(self, msg, path)
      return table.insert(self.errors, {
        message = msg,
        path = path
      })
    end,
    execute = function(self)
      local op = self:_find_operation()
      if not (op) then
        return {
          data = json_null,
          errors = {
            {
              message = 'No operation found'
            }
          }
        }
      end
      local root_type_name
      local _exp_0 = op.operation
      if 'query' == _exp_0 then
        root_type_name = self.schema.query_type
      elseif 'mutation' == _exp_0 then
        root_type_name = self.schema.mutation_type
      elseif 'subscription' == _exp_0 then
        root_type_name = self.schema.subscription_type
      else
        root_type_name = self.schema.query_type
      end
      local root_type = self.schema.types[root_type_name]
      if not (root_type) then
        return {
          data = json_null,
          errors = {
            {
              message = "Root type '" .. tostring(root_type_name) .. "' not found"
            }
          }
        }
      end
      local data = self:execute_selection_set(op.selectionSet, root_type_name, { }, { })
      local result = {
        data = data
      }
      if #self.errors > 0 then
        result.errors = self.errors
      end
      return result
    end,
    _find_operation = function(self)
      local ops = { }
      local _list_0 = self.document.definitions
      for _index_0 = 1, #_list_0 do
        local def = _list_0[_index_0]
        if def.kind == 'OperationDefinition' then
          table.insert(ops, def)
        end
      end
      if self.operation_name then
        for _index_0 = 1, #ops do
          local op = ops[_index_0]
          if op.name == self.operation_name then
            return op
          end
        end
        return nil
      end
      if #ops == 1 then
        return ops[1]
      end
      if #ops == 0 then
        return nil
      end
      self:add_error('Must provide operation name if query contains multiple operations', nil)
      return nil
    end,
    execute_selection_set = function(self, selection_set, type_name, parent_obj, path)
      local result = { }
      local fields = collect_fields(type_name, selection_set, self.fragments, self.variables)
      for _index_0 = 1, #fields do
        local f = fields[_index_0]
        local rkey = f.alias
        local ok, val = pcall(function()
          return self:resolve_field(type_name, f.name, f.node, parent_obj, path)
        end)
        if ok then
          if val == nil then
            result[rkey] = json_null
          else
            result[rkey] = val
          end
        else
          self:add_error(tostring(val), extend(path, rkey))
          result[rkey] = json_null
        end
      end
      return result
    end,
    resolve_field = function(self, type_name, field_name, field_node, parent_obj, path)
      if field_name == '__typename' then
        return type_name
      end
      local type_def = self.schema.types[type_name]
      if not (type_def) then
        error("Unknown type: " .. tostring(type_name))
      end
      local field_def = type_def.fields and type_def.fields[field_name]
      local resolver = self.schema:get_resolver(type_name, field_name)
      local args = collect_args(field_node, field_def, self.variables, self.schema)
      local new_path = extend(path, field_name)
      if field_def and not field_node.selectionSet then
        local named = field_def.type
        while named and (named.kind == 'NonNullType' or named.kind == 'ListType') do
          named = named.ofType
        end
        if named then
          local t = self.schema.types[named.name]
          if t and (t.kind == 'OBJECT' or t.kind == 'INTERFACE' or t.kind == 'UNION') then
            return nil
          end
        end
      end
      local raw_value = resolver(parent_obj, args, self.context, {
        field_name = field_name,
        field_def = field_def,
        parent_type = type_name,
        schema = self.schema,
        fragments = self.fragments,
        variables = self.variables
      })
      return self:complete_value(field_def and field_def.type, raw_value, field_node, new_path)
    end,
    complete_value = function(self, type_ref, value, field_node, path)
      if type_ref == nil then
        return value
      end
      if type_ref.kind == 'NonNullType' then
        local completed = self:complete_value(type_ref.ofType, value, field_node, path)
        if completed == nil then
          error("Non-null field returned null at " .. tostring(table.concat(path, '.')))
        end
        return completed
      end
      if value == nil then
        return nil
      end
      if type_ref.kind == 'ListType' then
        if type(value) ~= 'table' then
          error("Expected list at " .. tostring(table.concat(path, '.')))
        end
        local result = { }
        for i, item in ipairs(value) do
          local item_path = extend(path, i)
          local ok, completed = pcall(self.complete_value, self, type_ref.ofType, item, field_node, item_path)
          if ok then
            table.insert(result, completed)
          else
            self:add_error(tostring(completed), item_path)
            table.insert(result, nil)
          end
        end
        return result
      end
      local type_name = type_ref.name
      local t = self.schema.types[type_name]
      if not t then
        return value
      end
      if t.kind == 'SCALAR' then
        if t.coerce_output then
          return t.coerce_output(value)
        end
        return value
      end
      if t.kind == 'ENUM' then
        return value
      end
      if t.kind == 'UNION' or t.kind == 'INTERFACE' then
        local resolve_type = self.schema.resolver and self.schema.resolver[type_name]
        local concrete
        if resolve_type then
          concrete = resolve_type(value, self.context)
        else
          concrete = type(value) == 'table' and value.__typename
        end
        if not (concrete) then
          error("Cannot determine concrete type for " .. tostring(type_name))
        end
        return self:complete_value({
          kind = 'NamedType',
          name = concrete
        }, value, field_node, path)
      end
      if not field_node.selectionSet then
        return nil
      end
      return self:execute_selection_set(field_node.selectionSet, type_name, value, path)
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, schema, document, variables, operation_name, context)
      self.schema = schema
      self.document = document
      self.variables = variables or { }
      self.operation_name = operation_name
      self.context = context or { }
      self.fragments = collect_fragments(document)
      self.errors = { }
    end,
    __base = _base_0,
    __name = "Executor"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Executor = _class_0
end
local init
init = function(schema)
  _schema = schema
end
local set_reinit_fn
set_reinit_fn = function(fn)
  _reinit_fn = fn
end
local reinit_schema
reinit_schema = function()
  if _reinit_fn then
    return _reinit_fn()
  end
end
local execute
execute = function(opts)
  local query = opts[1] or opts.query or ''
  local variables = opts[2] or opts.variables or { }
  local operation_name = opts[3] or opts.operationName
  local context = opts.context or { }
  if not (_schema) then
    return {
      data = json_null,
      errors = {
        {
          message = 'Schema not initialized'
        }
      }
    }
  end
  local ok, doc = pcall(parse, query)
  if not (ok) then
    return {
      data = json_null,
      errors = {
        {
          message = 'Parse error: ' .. tostring(doc)
        }
      }
    }
  end
  local exec = Executor(_schema, doc, variables, operation_name, context)
  return exec:execute()
end
return {
  init = init,
  set_reinit_fn = set_reinit_fn,
  reinit_schema = reinit_schema,
  execute = execute,
  Executor = Executor
}
