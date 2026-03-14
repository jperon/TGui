-- graphql/sdl_generator.moon
-- Generates a passive SDL artifact from MoonScript registry metadata.

registry = require 'graphql.sdl_registry'

format_field = (f) ->
  args = if f.args and f.args != '' then "(#{f.args})" else ''
  "  #{f.name}#{args}: #{f.returns}"

emit_block = (type_name, fields) ->
  lines = {}
  for f in *fields
    table.insert lines, format_field f
  "type #{type_name} {\n#{table.concat(lines, '\n')}\n}"

generate = ->
  parts = {
    '# GENERATED FILE - passive SDL projection from MoonScript registry'
    '# Source: backend/graphql/sdl_registry.moon'
    ''
  }

  -- Ajouter les types d'input
  for input_type in *registry.InputTypes
    table.insert parts, input_type.definition
    table.insert parts, ''

  -- Ajouter les types d'objets
  for object_type in *registry.ObjectTypes
    table.insert parts, object_type.definition
    table.insert parts, ''

  -- Ajouter les types Query et Mutation
  table.insert parts, emit_block 'Query', registry.Query
  table.insert parts, ''
  table.insert parts, emit_block 'Mutation', registry.Mutation
  table.insert parts, ''

  table.concat parts, '\n'

write_file = (out_path) ->
  path = out_path or 'schema/tdb.generated.graphql'
  content = generate!
  f = io.open path, 'w'
  error "Cannot write generated SDL file: #{path}" unless f
  f\write content
  f\close!
  path

{ :generate, :write_file }
