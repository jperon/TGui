# frontend/src/graphql_builder.coffee
# GraphQL Builder with support for list relations and field detection

class GraphQLBuilder
  constructor: ({@container, @allSpaces, @allRelations, @allFields, @onChange}) ->
    @_query = { type: 'Query', fields: {} }
    @_selectedFields = {}  # spaceId -> Set(fieldName)
    @_computedFields = {}   # fieldName -> formula
    @_aggregations = []     # configuration agrégations
    @_relationTypes = {}    # fieldName -> { type, targetSpace, targetField }
    @_sourceSpaceId = null

  # Load relation types and detect single vs multiple relations
  loadRelationTypes: (spaces, relations) ->
    @_relationTypes = {}
    
    for space in spaces
      for field in space.fields
        if field.fieldType == 'Relation'
          relation = relations.find (r) -> r.fromFieldId == field.id
          if relation
            # Detect if it's a multiple relation
            isMultiple = @detectMultipleRelation space, relation
            @_relationTypes["#{space.name}.#{field.name}"] = {
              type: if isMultiple then 'List' else 'Single'
              targetSpace: relation.toSpace.name
              targetField: relation.toField.name
              fromSpaceId: space.id
              fromFieldId: field.id
              toSpaceId: relation.toSpace.id
              toFieldId: relation.toField.id
            }

  # Detect if a relation is multiple by checking target space data
  detectMultipleRelation: (space, relation) ->
    # This would need to be implemented via GraphQL query to check data
    # For now, assume single unless we have specific metadata
    return false

  # Set the source space for the query
  setSourceSpace: (spaceId) ->
    @_sourceSpaceId = spaceId

  # Add a field to the selection
  selectField: (spaceId, fieldName) ->
    key = "#{spaceId}.#{fieldName}"
    @_selectedFields[key] = true unless @_selectedFields[key]
    @updateQuery()

  # Remove a field from selection
  removeField: (spaceId, fieldName) ->
    key = "#{spaceId}.#{fieldName}"
    delete @_selectedFields[key]
    @updateQuery()

  # Add a computed field
  addComputedField: (name, formula, language = 'moonscript') ->
    @_computedFields[name] = { formula, language }
    @updateQuery()

  # Add an aggregation
  addAggregation: (field, func, alias) ->
    table.insert @_aggregations, { field, func, as: alias }
    @updateQuery()

  # Check if we have list relations
  hasListRelations: ->
    for _, relation in pairs @_relationTypes
      if relation.type == 'List'
        return true
    return false

  # Get selected fields with their metadata
  getSelectedFields: ->
    selected = []
    for key, _ of @_selectedFields
      [spaceId, fieldName] = key.split('.')
      selected.push { spaceId, fieldName }
    return selected

  # Get target fields for a space
  getTargetFields: (spaceName) ->
    space = @_allSpaces.find (s) -> s.name == spaceName
    return [] unless space
    
    fields = space.fields.map (f) -> f.name
    return fields.join(' ')

  # Build standard GraphQL query
  buildStandardQuery: ->
    query = "query GetData {\n"
    query += "  records(spaceId: \"#{@_sourceSpaceId}\") {\n"
    
    for field in @getSelectedFields()
      relationType = @_relationTypes["#{field.spaceId}.#{field.fieldName}"]
      if relationType?.type == 'List'
        # Field of type list - include nested fields
        query += "    #{field.fieldName} {\n"
        query += "      id\n"
        query += "      #{@getTargetFields(relationType.targetSpace)}\n"
        query += "    }\n"
      else if relationType?.type == 'Single'
        # Single relation - include nested fields
        query += "    #{field.fieldName} {\n"
        query += "      id\n"
        query += "      #{@getTargetFields(relationType.targetSpace)}\n"
        query += "    }\n"
      else
        # Simple field
        query += "    #{field.fieldName}\n"
    
    query += "  }\n"
    query += "}"
    return query

  # Build query with list support
  buildQueryWithLists: ->
    query = "query GetDataWithLists {\n"
    query += "  records(spaceId: \"#{@_sourceSpaceId}\") {\n"
    
    for field in @getSelectedFields()
      relationType = @_relationTypes["#{field.spaceId}.#{field.fieldName}"]
      if relationType?.type == 'List'
        # List field - preserve structure
        query += "    #{field.fieldName} {\n"
        query += "      id\n"
        query += "      #{@getTargetFields(relationType.targetSpace)}\n"
        query += "    }\n"
      else if relationType?.type == 'Single'
        # Single relation
        query += "    #{field.fieldName} {\n"
        query += "      id\n"
        query += "      #{@getTargetFields(relationType.targetSpace)}\n"
        query += "    }\n"
      else
        # Simple field
        query += "    #{field.fieldName}\n"
    
    query += "  }\n"
    query += "}"
    return query

  # Build aggregated query
  buildAggregatedQuery: ->
    query = "query GetAggregatedData {\n"
    query += "  aggregatedRecords(spaceId: \"#{@_sourceSpaceId}\", config: {\n"
    query += "    groupBy: [#{@buildGroupBy()}]\n"
    query += "    aggregates: [#{@buildAggregates()}]\n"
    query += "    filter: #{@buildFilter()}\n"
    query += "  }) {\n"
    query += "    #{@buildSelectedFields()}\n"
    query += "  }\n"
    query += "}"
    return query

  # Build group by clause
  buildGroupBy: ->
    return "" if @_aggregations.length == 0
    
    groupFields = @_aggregations
      .filter((agg) -> agg.field)
      .map((agg) -> "\"#{agg.field}\"")
    
    return groupFields.join(', ')

  # Build aggregates clause
  buildAggregates: ->
    return "" if @_aggregations.length == 0
    
    aggregates = @_aggregations.map (agg) ->
      "{ field: \"#{agg.field}\", func: #{agg.func.toUpperCase()}, as: \"#{agg.as or agg.field}\" }"
    
    return aggregates.join(', ')

  # Build filter clause
  buildFilter: ->
    # For now, return empty filter
    return "{}"

  # Build selected fields for aggregated query
  buildSelectedFields: ->
    fields = []
    for field in @getSelectedFields()
      fields.push field.fieldName
    
    return fields.join('\n    ')

  # Main query building method
  buildQuery: ->
    if @_aggregations.length > 0
      @buildAggregatedQuery()
    else if @hasListRelations()
      @buildQueryWithLists()
    else
      @buildStandardQuery()

  # Update the query and notify change
  updateQuery: ->
    @_query = @buildQuery()
    @onChange(@_query) if @onChange

  # Get the current query
  getQuery: ->
    return @_query

  # Load configuration from a query string
  loadFromQuery: (queryString) ->
    # Parse the query and extract selected fields
    # This is a simplified implementation
    @_selectedFields = {}
    
    # Extract field names from the query
    fieldMatches = queryString.match(/(\w+)\s*{/g)
    if fieldMatches
      for match in fieldMatches
        fieldName = match.replace(/\s*{/, '')
        @_selectedFields["#{@_sourceSpaceId}.#{fieldName}"] = true
    
    @updateQuery()

  # Get field definitions for flattening
  getFieldDefinitions: ->
    definitions = {}
    
    for key, _ of @_selectedFields
      [spaceId, fieldName] = key.split('.')
      relationType = @_relationTypes[key]
      
      if relationType
        definitions[fieldName] = {
          type: relationType.type
          space: relationType.targetSpace
          isRelation: true
        }
      else
        # Find field metadata
        space = @_allSpaces.find (s) -> s.id == spaceId
        if space
          field = space.fields.find (f) -> f.name == fieldName
          if field
            definitions[fieldName] = {
              type: field.fieldType
              space: space.name
              isRelation: false
            }
    
    return definitions

# Export for use in other modules
window.GraphQLBuilder = GraphQLBuilder
