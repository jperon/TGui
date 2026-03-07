-- graphql/introspection.moon
-- Implements GraphQL introspection: __schema, __type, __typename.
-- Exports SDL (type definitions) and RESOLVERS to be merged into the schema.

-- ─────────────────────────────────────────────────────────────────────────────
-- SDL – introspection type definitions
-- ─────────────────────────────────────────────────────────────────────────────

SDL = [[
enum __TypeKind {
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Forward declarations (mutual recursion: type_ref_to_introspection ↔ type_to_introspection)
type_to_introspection     = nil
type_ref_to_introspection = nil

-- Return an introspection object for a type-ref node (NonNull, List, NamedType)
type_ref_to_introspection = (type_ref, schema) ->
  return nil unless type_ref
  switch type_ref.kind
    when 'NonNullType'
      { kind: 'NON_NULL', name: nil, ofType: type_ref_to_introspection(type_ref.ofType, schema) }
    when 'ListType'
      { kind: 'LIST', name: nil, ofType: type_ref_to_introspection(type_ref.ofType, schema) }
    when 'NamedType'
      t = schema.types[type_ref.name]
      if t then type_to_introspection(t, schema)
      else { kind: 'SCALAR', name: type_ref.name }
    else nil

-- Return an introspection object for a type definition.
-- Lazy functions break potential cycles between mutually-referencing types.
type_to_introspection = (t, schema) ->
  return nil unless t
  {
    kind:        t.kind
    name:        t.name
    description: t.description
    ofType:      nil   -- only NonNull/List wrappers set this (see type_ref_to_introspection)

    fields: ->
      return nil unless t.kind == 'OBJECT' or t.kind == 'INTERFACE'
      result = {}
      for fname, fdef in pairs (t.fields or {})
        if fname\sub(1, 2) != '__'
          table.insert result, {
            name:              fdef.name or fname
            description:       fdef.description
            isDeprecated:      false
            deprecationReason: nil
            type:              type_ref_to_introspection fdef.type, schema
            args: ->
              aargs = {}
              for adef in *(fdef.arguments or {})
                table.insert aargs, {
                  name:         adef.name
                  description:  adef.description
                  type:         type_ref_to_introspection adef.type, schema
                  defaultValue: adef.defaultValue and tostring(adef.defaultValue) or nil
                }
              aargs
          }
      result

    inputFields: ->
      return nil unless t.kind == 'INPUT_OBJECT'
      result = {}
      for fname, fdef in pairs (t.fields or {})
        table.insert result, {
          name:         fdef.name or fname
          description:  fdef.description
          type:         type_ref_to_introspection fdef.type, schema
          defaultValue: nil
        }
      result

    interfaces: ->
      return nil unless t.kind == 'OBJECT'
      result = {}
      for iname in *(t.interfaces or {})
        iface = schema.types[iname]
        if iface then table.insert result, type_to_introspection(iface, schema)
      result

    possibleTypes: ->
      return nil unless t.kind == 'INTERFACE' or t.kind == 'UNION'
      result = {}
      for tname, tdef in pairs schema.types
        if tdef.kind == 'OBJECT'
          for iname in *(tdef.interfaces or {})
            if iname == t.name
              table.insert result, type_to_introspection(tdef, schema)
      result

    enumValues: ->
      return nil unless t.kind == 'ENUM'
      result = {}
      for ev in *(t.values or {})
        table.insert result, {
          name:              ev.name
          description:       ev.description
          isDeprecated:      false
          deprecationReason: nil
        }
      result
  }

schema_resolver = (schema) ->
  all_types = {}
  for tname, tdef in pairs schema.types
    if tname\sub(1, 2) != '__'
      table.insert all_types, type_to_introspection(tdef, schema)
  {
    types:            all_types
    queryType:        type_to_introspection schema.types[schema.query_type], schema
    mutationType:     schema.mutation_type and type_to_introspection(schema.types[schema.mutation_type], schema) or nil
    subscriptionType: schema.subscription_type and type_to_introspection(schema.types[schema.subscription_type], schema) or nil
    directives:       {}
  }

type_resolver = (schema, name) ->
  t = schema.types[name]
  if t then type_to_introspection(t, schema) else nil

-- ─────────────────────────────────────────────────────────────────────────────
-- Resolvers
-- ─────────────────────────────────────────────────────────────────────────────

-- Resolve a field whose value may be a lazy function
lazy = (fname) ->
  (obj) ->
    v = obj[fname]
    if type(v) == 'function' then v() else v

RESOLVERS = {
  Query: {
    __schema: (obj, args, ctx, info) -> schema_resolver info.schema
    __type:   (obj, args, ctx, info) -> type_resolver info.schema, args.name
  }
  -- __Type fields that are lazy functions
  __Type: {
    fields:        lazy 'fields'
    inputFields:   lazy 'inputFields'
    interfaces:    lazy 'interfaces'
    possibleTypes: lazy 'possibleTypes'
    enumValues:    lazy 'enumValues'
  }
  -- __Field: args is a lazy function
  __Field: {
    args: lazy 'args'
  }
}

{ :SDL, :RESOLVERS, :schema_resolver, :type_resolver, :type_to_introspection, :type_ref_to_introspection }

