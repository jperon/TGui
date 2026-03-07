-- graphql/executor.moon
-- Executes a parsed GraphQL operation against a schema and resolvers.

{ :parse }        = require 'graphql.parser'
{ :build_schema } = require 'graphql.schema'

-- Active schema (set via init)
_schema    = nil
_reinit_fn = nil

-- Helper: copy a list and append one item (for building path arrays)
extend = (t, item) ->
  r = {unpack t}
  table.insert r, item
  r

-- ────────────────────────────────────────────────────────────────────────────
-- Value coercion helpers
-- ────────────────────────────────────────────────────────────────────────────

-- Resolve a GraphQL value node against the variable map
resolve_value = (value_node, variables) ->
  switch value_node.kind
    when 'Variable'
      variables[value_node.name]
    when 'IntValue'
      tonumber value_node.value
    when 'FloatValue'
      tonumber value_node.value
    when 'StringValue'
      value_node.value
    when 'BooleanValue'
      value_node.value
    when 'NullValue'
      nil
    when 'EnumValue'
      value_node.value
    when 'ListValue'
      [resolve_value(v, variables) for v in *value_node.values]
    when 'ObjectValue'
      obj = {}
      for f in *value_node.fields
        obj[f.name] = resolve_value f.value, variables
      obj
    else
      nil

-- Build the args table for a field
collect_args = (field_node, field_def, variables, schema) ->
  args = {}
  if not field_def or not field_def.arguments then return args
  -- index declared arg definitions by name
  arg_defs = {}
  for adef in *(field_def.arguments or {})
    arg_defs[adef.name] = adef
  -- fill from the query's argument list
  for arg in *(field_node.arguments or {})
    adef = arg_defs[arg.name]
    raw  = resolve_value arg.value, variables
    args[arg.name] = if adef then schema\coerce_input(adef.type, raw) else raw
  -- apply defaults for missing args
  for aname, adef in pairs arg_defs
    if args[aname] == nil and adef.defaultValue != nil
      args[aname] = resolve_value adef.defaultValue, {}
  args

-- ────────────────────────────────────────────────────────────────────────────
-- Fragment handling
-- ────────────────────────────────────────────────────────────────────────────

collect_fragments = (document) ->
  frags = {}
  for def in *document.definitions
    if def.kind == 'FragmentDefinition'
      frags[def.name] = def
  frags

-- Collect all fields from a selection set, merging fragments
collect_fields = (type_name, selection_set, fragments, variables) ->
  fields = {}   -- ordered list of {name, alias, node}
  seen   = {}   -- dedup by response key

  for sel in *selection_set.selections
    switch sel.kind
      when 'Field'
        rkey = sel.alias or sel.name
        if not seen[rkey]
          seen[rkey] = true
          table.insert fields, { name: sel.name, alias: rkey, node: sel }
      when 'FragmentSpread'
        frag = fragments[sel.name]
        if frag
          sub = collect_fields type_name, frag.selectionSet, fragments, variables
          for f in *sub
            if not seen[f.alias]
              seen[f.alias] = true
              table.insert fields, f
      when 'InlineFragment'
        if not sel.typeCondition or sel.typeCondition == type_name
          sub = collect_fields type_name, sel.selectionSet, fragments, variables
          for f in *sub
            if not seen[f.alias]
              seen[f.alias] = true
              table.insert fields, f

  fields

-- ────────────────────────────────────────────────────────────────────────────
-- Core executor
-- ────────────────────────────────────────────────────────────────────────────

class Executor
  new: (schema, document, variables, operation_name, context) =>
    @schema         = schema
    @document       = document
    @variables      = variables or {}
    @operation_name = operation_name
    @context        = context or {}
    @fragments      = collect_fragments document
    @errors         = {}

  add_error: (msg, path) =>
    table.insert @errors, { message: msg, path: path }

  execute: =>
    -- Find the operation to execute
    op = @_find_operation!
    unless op
      return { data: nil, errors: { {message: 'No operation found'} } }

    root_type_name = switch op.operation
      when 'query'        then @schema.query_type
      when 'mutation'     then @schema.mutation_type
      when 'subscription' then @schema.subscription_type
      else @schema.query_type

    root_type = @schema.types[root_type_name]
    unless root_type
      return { data: nil, errors: { {message: "Root type '#{root_type_name}' not found"} } }

    data = @execute_selection_set op.selectionSet, root_type_name, {}, {}
    result = { data: data }
    if #@errors > 0 then result.errors = @errors
    result

  _find_operation: =>
    ops = {}
    for def in *@document.definitions
      if def.kind == 'OperationDefinition'
        table.insert ops, def

    if @operation_name
      for op in *ops
        if op.name == @operation_name then return op
      return nil

    if #ops == 1 then return ops[1]
    if #ops == 0 then return nil
    -- Multiple operations, no name specified
    @add_error 'Must provide operation name if query contains multiple operations', nil
    nil

  execute_selection_set: (selection_set, type_name, parent_obj, path) =>
    result = {}
    fields = collect_fields type_name, selection_set, @fragments, @variables
    for f in *fields
      rkey = f.alias
      ok, val = pcall ->
        @resolve_field type_name, f.name, f.node, parent_obj, path
      if ok
        result[rkey] = val
      else
        @add_error tostring(val), extend(path, rkey)
        result[rkey] = nil
    result

  resolve_field: (type_name, field_name, field_node, parent_obj, path) =>
    -- __typename is a meta-field, not in the schema
    if field_name == '__typename'
      return type_name

    type_def = @schema.types[type_name]
    unless type_def
      error "Unknown type: #{type_name}"

    field_def = type_def.fields and type_def.fields[field_name]
    resolver  = @schema\get_resolver type_name, field_name
    args      = collect_args field_node, field_def, @variables, @schema

    new_path = extend path, field_name
    raw_value = resolver parent_obj, args, @context, {
      field_name:     field_name
      field_def:      field_def
      parent_type:    type_name
      schema:         @schema
      fragments:      @fragments
      variables:      @variables
    }

    @complete_value field_def and field_def.type, raw_value, field_node, new_path

  complete_value: (type_ref, value, field_node, path) =>
    if type_ref == nil then return value

    if type_ref.kind == 'NonNullType'
      completed = @complete_value type_ref.ofType, value, field_node, path
      if completed == nil
        error "Non-null field returned null at #{table.concat(path, '.')}"
      return completed

    if value == nil then return nil

    if type_ref.kind == 'ListType'
      if type(value) != 'table'
        error "Expected list at #{table.concat(path, '.')}"
      result = {}
      for i, item in ipairs value
        item_path = extend path, i
        ok, completed = pcall @complete_value, @, type_ref.ofType, item, field_node, item_path
        if ok
          table.insert result, completed
        else
          @add_error tostring(completed), item_path
          table.insert result, nil
      return result

    -- NamedType
    type_name = type_ref.name
    t = @schema.types[type_name]

    if not t then return value  -- unknown type, pass through

    if t.kind == 'SCALAR'
      if t.coerce_output then return t.coerce_output value
      return value

    if t.kind == 'ENUM'
      return value

    -- Object / Interface / Union
    if t.kind == 'UNION' or t.kind == 'INTERFACE'
      -- need __resolveType
      resolve_type = @schema.resolver and @schema.resolver[type_name]
      concrete = if resolve_type then resolve_type(value, @context) else type(value) == 'table' and value.__typename
      unless concrete
        error "Cannot determine concrete type for #{type_name}"
      return @complete_value { kind: 'NamedType', name: concrete }, value, field_node, path

    -- OBJECT
    unless field_node.selectionSet
      error "Field #{type_name} is a composite type but has no selection set"
    @execute_selection_set field_node.selectionSet, type_name, value, path

-- ────────────────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────────────────

init = (schema) ->
  _schema = schema

set_reinit_fn = (fn) ->
  _reinit_fn = fn

reinit_schema = ->
  _reinit_fn! if _reinit_fn

execute = (opts) ->
  query         = opts[1] or opts.query or ''
  variables     = opts[2] or opts.variables or {}
  operation_name = opts[3] or opts.operationName
  context        = opts.context or {}

  unless _schema
    return { data: nil, errors: { {message: 'Schema not initialized'} } }

  ok, doc = pcall parse, query
  unless ok
    return { data: nil, errors: { {message: 'Parse error: ' .. tostring(doc)} } }

  exec = Executor _schema, doc, variables, operation_name, context
  exec\execute!

{ :init, :set_reinit_fn, :reinit_schema, :execute, :Executor }
