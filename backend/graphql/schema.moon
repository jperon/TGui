-- graphql/schema.moon
-- Type system: builds an executable schema from a parsed SDL document.
-- Supports scalars, objects, interfaces, unions, enums, input objects, lists, non-null.

{ :parse } = require 'graphql.parser'

-- ────────────────────────────────────────────────────────────────────────────
-- Built-in scalar coercers
-- ────────────────────────────────────────────────────────────────────────────

SCALARS =
  String:
    kind: 'SCALAR'
    name: 'String'
    coerce_input:  (v) -> tostring v
    coerce_output: (v) -> tostring v
  Int:
    kind: 'SCALAR'
    name: 'Int'
    coerce_input: (v) ->
      n = tonumber v
      if n != nil then math.floor n
    coerce_output: (v) ->
      n = tonumber v
      if n != nil then math.floor n
  Float:
    kind: 'SCALAR'
    name: 'Float'
    coerce_input:  (v) -> tonumber v
    coerce_output: (v) -> tonumber v
  Boolean:
    kind: 'SCALAR'
    name: 'Boolean'
    coerce_input:  (v) -> v == true or v == 'true'
    coerce_output: (v) -> v == true
  ID:
    kind: 'SCALAR'
    name: 'ID'
    coerce_input:  (v) -> tostring v
    coerce_output: (v) -> tostring v

-- ────────────────────────────────────────────────────────────────────────────
-- Schema builder
-- ────────────────────────────────────────────────────────────────────────────

class Schema
  new: (sdl_or_ast, resolvers = {}) =>
    @types      = {}  -- name -> type def
    @resolvers  = resolvers
    @query_type     = nil
    @mutation_type  = nil
    @subscription_type = nil

    -- Register built-in scalars
    for name, scalar in pairs SCALARS
      @types[name] = scalar

    -- Register built-in introspection types
    @types['__Schema']             = { name: '__Schema',             kind: 'OBJECT' }
    @types['__Type']               = { name: '__Type',               kind: 'OBJECT' }
    @types['__Field']              = { name: '__Field',              kind: 'OBJECT' }
    @types['__InputValue']         = { name: '__InputValue',         kind: 'OBJECT' }
    @types['__EnumValue']          = { name: '__EnumValue',          kind: 'OBJECT' }
    @types['__Directive']          = { name: '__Directive',          kind: 'OBJECT' }
    @types['__TypeKind']           = { name: '__TypeKind',           kind: 'ENUM'   }
    @types['__DirectiveLocation']  = { name: '__DirectiveLocation',  kind: 'ENUM'   }

    doc = if type(sdl_or_ast) == 'string' then parse sdl_or_ast else sdl_or_ast
    @_build doc

  -- Walk the SDL AST and register each type
  _build: (doc) =>
    -- First pass: register names
    for def in *doc.definitions
      switch def.kind
        when 'ObjectTypeDefinition'
          @types[def.name] = {
            kind:        'OBJECT'
            name:        def.name
            description: def.description
            interfaces:  def.interfaces
            fields:      {}
            directives:  def.directives
            _def:        def
          }
        when 'InterfaceTypeDefinition'
          @types[def.name] = {
            kind:        'INTERFACE'
            name:        def.name
            description: def.description
            fields:      {}
            directives:  def.directives
            _def:        def
          }
        when 'UnionTypeDefinition'
          @types[def.name] = {
            kind:        'UNION'
            name:        def.name
            description: def.description
            types:       def.types
            directives:  def.directives
          }
        when 'EnumTypeDefinition'
          @types[def.name] = {
            kind:        'ENUM'
            name:        def.name
            description: def.description
            values:      def.values
            directives:  def.directives
          }
        when 'InputObjectTypeDefinition'
          @types[def.name] = {
            kind:        'INPUT_OBJECT'
            name:        def.name
            description: def.description
            fields:      {}
            directives:  def.directives
            _def:        def
          }
        when 'ScalarTypeDefinition'
          @types[def.name] = {
            kind:        'SCALAR'
            name:        def.name
            description: def.description
            directives:  def.directives
          }
        when 'SchemaDefinition'
          for op in *def.operationTypes
            switch op.operation
              when 'query'        then @query_type        = op.type
              when 'mutation'     then @mutation_type     = op.type
              when 'subscription' then @subscription_type = op.type

    -- Second pass: resolve fields
    for def in *doc.definitions
      switch def.kind
        when 'ObjectTypeDefinition', 'InterfaceTypeDefinition'
          t = @types[def.name]
          for fdef in *def.fields
            t.fields[fdef.name] = @_build_field fdef
        when 'ObjectTypeExtension', 'InterfaceTypeExtension'
          -- Merge additional fields into an already-registered type
          t = @types[def.name]
          if t
            for fdef in *(def.fields or {})
              t.fields[fdef.name] = @_build_field fdef
        when 'InputObjectTypeDefinition', 'InputObjectTypeExtension'
          t = @types[def.name]
          if t
            for fdef in *(def.fields or {})
              t.fields[fdef.name] = {
                name:         fdef.name
                description:  fdef.description
                type:         fdef.type
                defaultValue: fdef.defaultValue
              }

    -- Default query/mutation names if no schema definition
    @query_type    = @query_type    or 'Query'
    @mutation_type = @mutation_type or 'Mutation'

  _build_field: (fdef) =>
    {
      name:        fdef.name
      description: fdef.description
      type:        fdef.type
      arguments:   fdef.arguments
      directives:  fdef.directives
    }

  -- Resolve a type name to its definition
  get_type: (name) =>
    @types[name] or error "Unknown type: #{name}"

  -- Returns a type by name, or nil if not found (no error)
  find_type: (name) =>
    @types[name]

  -- Get the resolver function for a field
  get_resolver: (type_name, field_name) =>
    type_resolvers = @resolvers[type_name]
    if type_resolvers
      fn = type_resolvers[field_name]
      if fn then return fn
    -- default resolver: field access on parent object
    (obj, args, ctx, info) -> if type(obj) == 'table' then obj[field_name]

  -- Check if a type name corresponds to a leaf type (scalar or enum)
  is_leaf: (type_name) =>
    t = @types[type_name]
    t and (t.kind == 'SCALAR' or t.kind == 'ENUM')

  -- Unwrap a type ref to its named base
  named_type: (type_ref) =>
    switch type_ref.kind
      when 'NamedType'   then type_ref.name
      when 'ListType'    then @named_type type_ref.ofType
      when 'NonNullType' then @named_type type_ref.ofType
      else error "Unknown type ref kind: #{type_ref.kind}"

  -- Coerce an input value according to its declared type
  coerce_input: (type_ref, value) =>
    if type_ref.kind == 'NonNullType'
      if value == nil then error "Non-null field received null"
      return @coerce_input type_ref.ofType, value
    if value == nil then return nil
    if type_ref.kind == 'ListType'
      if type(value) != 'table' then return { @coerce_input(type_ref.ofType, value) }
      result = {}
      for v in *value do table.insert result, @coerce_input(type_ref.ofType, v)
      return result
    -- NamedType
    t = @types[type_ref.name]
    if not t then error "Unknown type: #{type_ref.name}"
    if t.kind == 'SCALAR'
      if t.coerce_input then return t.coerce_input(value)
      return value
    if t.kind == 'ENUM'
      return value  -- validated by enum values list
    if t.kind == 'INPUT_OBJECT'
      if type(value) != 'table' then error "Expected object for input type #{t.name}"
      result = {}
      for fname, fdef in pairs t.fields
        result[fname] = @coerce_input fdef.type, value[fname]
      return result
    error "Cannot coerce input of kind #{t.kind}"

build_schema = (sdl, resolvers) ->
  Schema sdl, resolvers

{ :Schema, :build_schema, :SCALARS }
