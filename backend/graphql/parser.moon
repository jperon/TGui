-- graphql/parser.moon
-- Parses a GraphQL document (query or SDL) into an AST.

{ TOKEN_TYPES: T, :tokenize } = require 'graphql.lexer'

class Parser
  new: (source) =>
    @tokens = tokenize source
    @pos    = 1

  peek: (offset = 0) =>
    @tokens[@pos + offset] or { type: T.EOF }

  consume: (expected_type) =>
    tok = @tokens[@pos]
    if not tok or tok.type == T.EOF
      error "Unexpected EOF, expected #{expected_type}"
    if expected_type and tok.type != expected_type
      error "Expected #{expected_type}, got #{tok.type} (#{tok.value})"
    @pos += 1
    tok

  -- Attempt to consume a NAME token with a specific value; returns tok or nil
  consume_keyword: (kw) =>
    tok = @peek!
    if tok.type == T.NAME and tok.value == kw
      @pos += 1
      return tok

  expect_keyword: (kw) =>
    tok = @consume_keyword kw
    unless tok
      error "Expected keyword '#{kw}', got #{@peek!.value}"
    tok

  peek_keyword: (kw) =>
    tok = @peek!
    tok.type == T.NAME and tok.value == kw

  -- ────────────────────────────────────────────────────────────────────────
  -- Document
  -- ────────────────────────────────────────────────────────────────────────

  parse_document: =>
    definitions = {}
    while @peek!.type != T.EOF
      table.insert definitions, @parse_definition!
    { kind: 'Document', definitions: definitions }

  parse_definition: =>
    tok = @peek!
    if tok.type == T.BRACE_L
      return @parse_operation_definition!

    -- Skip leading description strings (block or regular) before SDL definitions
    if tok.type == T.BLOCK_STRING or tok.type == T.STRING
      @pos += 1
      tok = @peek!

    if tok.type == T.NAME
      switch tok.value
        when 'query', 'mutation', 'subscription'
          return @parse_operation_definition!
        when 'fragment'
          return @parse_fragment_definition!
        -- SDL definitions
        when 'type', 'interface', 'union', 'enum', 'input', 'scalar', 'directive', 'schema', 'extend'
          return @parse_type_system_definition!

    error "Unexpected token: #{tok.type} #{tok.value}"

  -- ────────────────────────────────────────────────────────────────────────
  -- Operations
  -- ────────────────────────────────────────────────────────────────────────

  parse_operation_definition: =>
    op_tok = @peek!
    operation = 'query'
    name = nil
    var_defs = {}
    directives = {}

    if op_tok.type != T.BRACE_L
      operation = @consume(T.NAME).value
      if @peek!.type == T.NAME
        name = @consume(T.NAME).value
      var_defs   = @parse_variable_definitions!
      directives = @parse_directives!

    selection_set = @parse_selection_set!
    {
      kind:         'OperationDefinition'
      operation:    operation
      name:         name
      variableDefs: var_defs
      directives:   directives
      selectionSet: selection_set
    }

  parse_variable_definitions: =>
    defs = {}
    if @peek!.type != T.PAREN_L then return defs
    @consume T.PAREN_L
    while @peek!.type != T.PAREN_R
      table.insert defs, @parse_variable_definition!
    @consume T.PAREN_R
    defs

  parse_variable_definition: =>
    @consume T.DOLLAR
    name = @consume(T.NAME).value
    @consume T.COLON
    type_ref = @parse_type_ref!
    default_value = nil
    if @peek!.type == T.EQUALS
      @consume T.EQUALS
      default_value = @parse_value true
    { kind: 'VariableDefinition', name: name, type: type_ref, defaultValue: default_value }

  parse_selection_set: =>
    @consume T.BRACE_L
    selections = {}
    while @peek!.type != T.BRACE_R
      table.insert selections, @parse_selection!
    @consume T.BRACE_R
    { kind: 'SelectionSet', selections: selections }

  parse_selection: =>
    if @peek!.type == T.SPREAD
      return @parse_fragment_or_inline!
    @parse_field!

  parse_field: =>
    tok = @consume T.NAME
    alias = nil
    name = tok.value
    if @peek!.type == T.COLON
      @consume T.COLON
      alias = name
      name  = @consume(T.NAME).value
    args       = @parse_arguments false
    directives = @parse_directives!
    sel_set    = nil
    if @peek!.type == T.BRACE_L
      sel_set = @parse_selection_set!
    { kind: 'Field', alias: alias, name: name, arguments: args, directives: directives, selectionSet: sel_set }

  parse_fragment_or_inline: =>
    @consume T.SPREAD
    if @peek!.type == T.NAME and @peek!.value != 'on'
      name = @consume(T.NAME).value
      dirs = @parse_directives!
      return { kind: 'FragmentSpread', name: name, directives: dirs }
    -- inline fragment
    type_condition = nil
    if @peek_keyword 'on'
      @consume_keyword 'on'
      type_condition = @consume(T.NAME).value
    dirs   = @parse_directives!
    sel_set = @parse_selection_set!
    { kind: 'InlineFragment', typeCondition: type_condition, directives: dirs, selectionSet: sel_set }

  parse_fragment_definition: =>
    @expect_keyword 'fragment'
    name = @consume(T.NAME).value
    @expect_keyword 'on'
    type_condition = @consume(T.NAME).value
    dirs   = @parse_directives!
    sel_set = @parse_selection_set!
    { kind: 'FragmentDefinition', name: name, typeCondition: type_condition, directives: dirs, selectionSet: sel_set }

  -- ────────────────────────────────────────────────────────────────────────
  -- Arguments & values
  -- ────────────────────────────────────────────────────────────────────────

  parse_arguments: (is_const) =>
    args = {}
    if @peek!.type != T.PAREN_L then return args
    @consume T.PAREN_L
    while @peek!.type != T.PAREN_R
      name = @consume(T.NAME).value
      @consume T.COLON
      value = @parse_value is_const
      table.insert args, { name: name, value: value }
    @consume T.PAREN_R
    args

  parse_value: (is_const) =>
    tok = @peek!
    switch tok.type
      when T.BRACKET_L then @parse_list_value is_const
      when T.BRACE_L   then @parse_object_value is_const
      when T.INT
        @consume T.INT
        { kind: 'IntValue', value: tonumber tok.value }
      when T.FLOAT
        @consume T.FLOAT
        { kind: 'FloatValue', value: tonumber tok.value }
      when T.STRING
        @consume T.STRING
        { kind: 'StringValue', value: tok.value }
      when T.BLOCK_STRING
        @consume T.BLOCK_STRING
        { kind: 'StringValue', value: tok.value, block: true }
      when T.NAME
        switch tok.value
          when 'true'
            @consume T.NAME
            { kind: 'BooleanValue', value: true }
          when 'false'
            @consume T.NAME
            { kind: 'BooleanValue', value: false }
          when 'null'
            @consume T.NAME
            { kind: 'NullValue' }
          else
            @consume T.NAME
            { kind: 'EnumValue', value: tok.value }
      when T.DOLLAR
        if is_const then error "Variable not allowed in constant context"
        @consume T.DOLLAR
        name = @consume(T.NAME).value
        { kind: 'Variable', name: name }
      else
        error "Unexpected value token: #{tok.type}"

  parse_list_value: (is_const) =>
    @consume T.BRACKET_L
    values = {}
    while @peek!.type != T.BRACKET_R
      table.insert values, @parse_value is_const
    @consume T.BRACKET_R
    { kind: 'ListValue', values: values }

  parse_object_value: (is_const) =>
    @consume T.BRACE_L
    fields = {}
    while @peek!.type != T.BRACE_R
      name = @consume(T.NAME).value
      @consume T.COLON
      value = @parse_value is_const
      table.insert fields, { name: name, value: value }
    @consume T.BRACE_R
    { kind: 'ObjectValue', fields: fields }

  -- ────────────────────────────────────────────────────────────────────────
  -- Type references
  -- ────────────────────────────────────────────────────────────────────────

  parse_type_ref: =>
    local type_ref
    if @peek!.type == T.BRACKET_L
      @consume T.BRACKET_L
      inner = @parse_type_ref!
      @consume T.BRACKET_R
      type_ref = { kind: 'ListType', ofType: inner }
    else
      name = @consume(T.NAME).value
      type_ref = { kind: 'NamedType', name: name }
    if @peek!.type == T.BANG
      @consume T.BANG
      type_ref = { kind: 'NonNullType', ofType: type_ref }
    type_ref

  -- ────────────────────────────────────────────────────────────────────────
  -- Directives
  -- ────────────────────────────────────────────────────────────────────────

  parse_directives: =>
    dirs = {}
    while @peek!.type == T.AT
      table.insert dirs, @parse_directive!
    dirs

  parse_directive: =>
    @consume T.AT
    name = @consume(T.NAME).value
    args = @parse_arguments false
    { kind: 'Directive', name: name, arguments: args }

  -- ────────────────────────────────────────────────────────────────────────
  -- SDL / Type system definitions
  -- ────────────────────────────────────────────────────────────────────────

  parse_type_system_definition: =>
    -- optional description (block string or string before keyword)
    description = nil
    if @peek!.type == T.STRING or @peek!.type == T.BLOCK_STRING
      description = @consume(@peek!.type).value

    kw = @peek!.value
    switch kw
      when 'schema'    then @parse_schema_definition description
      when 'scalar'    then @parse_scalar_type description
      when 'type'      then @parse_object_type description
      when 'interface' then @parse_interface_type description
      when 'union'     then @parse_union_type description
      when 'enum'      then @parse_enum_type description
      when 'input'     then @parse_input_type description
      when 'directive' then @parse_directive_definition description
      when 'extend'    then @parse_type_extension!
      else error "Unknown type system keyword: #{kw}"

  parse_schema_definition: (description) =>
    @expect_keyword 'schema'
    dirs = @parse_directives!
    @consume T.BRACE_L
    ops = {}
    while @peek!.type != T.BRACE_R
      op = @consume(T.NAME).value
      @consume T.COLON
      type_name = @consume(T.NAME).value
      table.insert ops, { operation: op, type: type_name }
    @consume T.BRACE_R
    { kind: 'SchemaDefinition', description: description, directives: dirs, operationTypes: ops }

  parse_scalar_type: (description) =>
    @expect_keyword 'scalar'
    name = @consume(T.NAME).value
    dirs = @parse_directives!
    { kind: 'ScalarTypeDefinition', description: description, name: name, directives: dirs }

  parse_object_type: (description) =>
    @expect_keyword 'type'
    name       = @consume(T.NAME).value
    interfaces = @parse_implements!
    dirs       = @parse_directives!
    fields     = @parse_fields_definition!
    { kind: 'ObjectTypeDefinition', description: description, name: name, interfaces: interfaces, directives: dirs, fields: fields }

  parse_implements: =>
    ifaces = {}
    if not @peek_keyword 'implements' then return ifaces
    @consume_keyword 'implements'
    @consume_keyword 'and' -- optional
    while @peek!.type == T.NAME and @peek!.value != 'implements'
      table.insert ifaces, @consume(T.NAME).value
      if @peek!.type == T.AMP then @consume T.AMP
    ifaces

  parse_interface_type: (description) =>
    @expect_keyword 'interface'
    name       = @consume(T.NAME).value
    interfaces = @parse_implements!
    dirs       = @parse_directives!
    fields     = @parse_fields_definition!
    { kind: 'InterfaceTypeDefinition', description: description, name: name, interfaces: interfaces, directives: dirs, fields: fields }

  parse_union_type: (description) =>
    @expect_keyword 'union'
    name = @consume(T.NAME).value
    dirs = @parse_directives!
    types = {}
    if @peek!.type == T.EQUALS
      @consume T.EQUALS
      if @peek!.type == T.PIPE then @consume T.PIPE
      while @peek!.type == T.NAME
        table.insert types, @consume(T.NAME).value
        if @peek!.type == T.PIPE then @consume T.PIPE
    { kind: 'UnionTypeDefinition', description: description, name: name, directives: dirs, types: types }

  parse_enum_type: (description) =>
    @expect_keyword 'enum'
    name   = @consume(T.NAME).value
    dirs   = @parse_directives!
    @consume T.BRACE_L
    values = {}
    while @peek!.type != T.BRACE_R
      vdesc = nil
      if @peek!.type == T.STRING or @peek!.type == T.BLOCK_STRING
        vdesc = @consume(@peek!.type).value
      vname = @consume(T.NAME).value
      vdirs = @parse_directives!
      table.insert values, { kind: 'EnumValueDefinition', description: vdesc, name: vname, directives: vdirs }
    @consume T.BRACE_R
    { kind: 'EnumTypeDefinition', description: description, name: name, directives: dirs, values: values }

  parse_input_type: (description) =>
    @expect_keyword 'input'
    name   = @consume(T.NAME).value
    dirs   = @parse_directives!
    fields = @parse_input_fields_definition!
    { kind: 'InputObjectTypeDefinition', description: description, name: name, directives: dirs, fields: fields }

  parse_fields_definition: =>
    @consume T.BRACE_L
    fields = {}
    while @peek!.type != T.BRACE_R
      fdesc = nil
      if @peek!.type == T.STRING or @peek!.type == T.BLOCK_STRING
        fdesc = @consume(@peek!.type).value
      fname = @consume(T.NAME).value
      fargs = @parse_arguments_definition!
      @consume T.COLON
      ftype = @parse_type_ref!
      fdirs = @parse_directives!
      table.insert fields, {
        kind:        'FieldDefinition'
        description: fdesc
        name:        fname
        arguments:   fargs
        type:        ftype
        directives:  fdirs
      }
    @consume T.BRACE_R
    fields

  parse_arguments_definition: =>
    args = {}
    if @peek!.type != T.PAREN_L then return args
    @consume T.PAREN_L
    while @peek!.type != T.PAREN_R
      adesc = nil
      if @peek!.type == T.STRING or @peek!.type == T.BLOCK_STRING
        adesc = @consume(@peek!.type).value
      aname = @consume(T.NAME).value
      @consume T.COLON
      atype = @parse_type_ref!
      adefault = nil
      if @peek!.type == T.EQUALS
        @consume T.EQUALS
        adefault = @parse_value true
      adirs = @parse_directives!
      table.insert args, {
        kind:         'InputValueDefinition'
        description:  adesc
        name:         aname
        type:         atype
        defaultValue: adefault
        directives:   adirs
      }
    @consume T.PAREN_R
    args

  parse_input_fields_definition: =>
    @consume T.BRACE_L
    fields = {}
    while @peek!.type != T.BRACE_R
      fdesc = nil
      if @peek!.type == T.STRING or @peek!.type == T.BLOCK_STRING
        fdesc = @consume(@peek!.type).value
      fname = @consume(T.NAME).value
      @consume T.COLON
      ftype = @parse_type_ref!
      fdefault = nil
      if @peek!.type == T.EQUALS
        @consume T.EQUALS
        fdefault = @parse_value true
      fdirs = @parse_directives!
      table.insert fields, {
        kind:         'InputValueDefinition'
        description:  fdesc
        name:         fname
        type:         ftype
        defaultValue: fdefault
        directives:   fdirs
      }
    @consume T.BRACE_R
    fields

  parse_directive_definition: (description) =>
    @expect_keyword 'directive'
    @consume T.AT
    name = @consume(T.NAME).value
    args = @parse_arguments_definition!
    @consume_keyword 'repeatable'
    @expect_keyword 'on'
    locations = {}
    if @peek!.type == T.PIPE then @consume T.PIPE
    while @peek!.type == T.NAME
      table.insert locations, @consume(T.NAME).value
      if @peek!.type == T.PIPE then @consume T.PIPE
    { kind: 'DirectiveDefinition', description: description, name: name, arguments: args, locations: locations }

  parse_type_extension: =>
    @expect_keyword 'extend'
    kw = @peek!.value
    switch kw
      when 'type'      then @parse_object_type_extension!
      when 'interface' then @parse_interface_type_extension!
      when 'enum'      then @parse_enum_type_extension!
      when 'input'     then @parse_input_type_extension!
      when 'union'     then @parse_union_type_extension!
      when 'scalar'    then @parse_scalar_type_extension!
      when 'schema'    then @parse_schema_extension!
      else error "Unknown extend keyword: #{kw}"

  parse_object_type_extension: =>
    @expect_keyword 'type'
    name       = @consume(T.NAME).value
    interfaces = @parse_implements!
    dirs       = @parse_directives!
    fields     = if @peek!.type == T.BRACE_L then @parse_fields_definition! else {}
    { kind: 'ObjectTypeExtension', name: name, interfaces: interfaces, directives: dirs, fields: fields }

  parse_interface_type_extension: =>
    @expect_keyword 'interface'
    name  = @consume(T.NAME).value
    dirs  = @parse_directives!
    fields = if @peek!.type == T.BRACE_L then @parse_fields_definition! else {}
    { kind: 'InterfaceTypeExtension', name: name, directives: dirs, fields: fields }

  parse_enum_type_extension: =>
    @expect_keyword 'enum'
    name = @consume(T.NAME).value
    dirs = @parse_directives!
    values = if @peek!.type == T.BRACE_L then
      @consume T.BRACE_L
      vs = {}
      while @peek!.type != T.BRACE_R
        vname = @consume(T.NAME).value
        vdirs = @parse_directives!
        table.insert vs, { kind: 'EnumValueDefinition', name: vname, directives: vdirs }
      @consume T.BRACE_R
      vs
    else {}
    { kind: 'EnumTypeExtension', name: name, directives: dirs, values: values }

  parse_input_type_extension: =>
    @expect_keyword 'input'
    name   = @consume(T.NAME).value
    dirs   = @parse_directives!
    fields = if @peek!.type == T.BRACE_L then @parse_input_fields_definition! else {}
    { kind: 'InputObjectTypeExtension', name: name, directives: dirs, fields: fields }

  parse_union_type_extension: =>
    @expect_keyword 'union'
    name = @consume(T.NAME).value
    dirs = @parse_directives!
    types = {}
    if @peek!.type == T.EQUALS
      @consume T.EQUALS
      if @peek!.type == T.PIPE then @consume T.PIPE
      while @peek!.type == T.NAME
        table.insert types, @consume(T.NAME).value
        if @peek!.type == T.PIPE then @consume T.PIPE
    { kind: 'UnionTypeExtension', name: name, directives: dirs, types: types }

  parse_scalar_type_extension: =>
    @expect_keyword 'scalar'
    name = @consume(T.NAME).value
    dirs = @parse_directives!
    { kind: 'ScalarTypeExtension', name: name, directives: dirs }

  parse_schema_extension: =>
    @expect_keyword 'schema'
    dirs = @parse_directives!
    ops = {}
    if @peek!.type == T.BRACE_L
      @consume T.BRACE_L
      while @peek!.type != T.BRACE_R
        op   = @consume(T.NAME).value
        @consume T.COLON
        type_name = @consume(T.NAME).value
        table.insert ops, { operation: op, type: type_name }
      @consume T.BRACE_R
    { kind: 'SchemaExtension', directives: dirs, operationTypes: ops }

parse = (source) ->
  Parser(source)\parse_document!

{ :Parser, :parse }
