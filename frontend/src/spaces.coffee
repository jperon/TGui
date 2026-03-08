# spaces.coffee
# Space and field management.

LIST_SPACES = """
  query { spaces { id name description fields { id name fieldType notNull position description formula triggerFields language } } }
"""

CREATE_SPACE = """
  mutation CreateSpace($input: CreateSpaceInput!) {
    createSpace(input: $input) { id name description }
  }
"""

DELETE_SPACE = """
  mutation DeleteSpace($id: ID!) {
    deleteSpace(id: $id)
  }
"""

SPACE_FIELDS = """
  query SpaceFields($id: ID!) {
    space(id: $id) {
      id name description
      fields { id name fieldType notNull position description formula triggerFields language }
    }
  }
"""

ADD_FIELD = """
  mutation AddField($spaceId: ID!, $input: FieldInput!) {
    addField(spaceId: $spaceId, input: $input) {
      id name fieldType notNull position
    }
  }
"""

UPDATE_SPACE = """
  mutation UpdateSpace($id: ID!, $input: UpdateSpaceInput!) {
    updateSpace(id: $id, input: $input) { id name description }
  }
"""

UPDATE_FIELD = """
  mutation UpdateField($fieldId: ID!, $input: UpdateFieldInput!) {
    updateField(fieldId: $fieldId, input: $input) {
      id name fieldType notNull position description formula triggerFields language
    }
  }
"""

LIST_RELATIONS = """
  query Relations($spaceId: ID!) {
    relations(spaceId: $spaceId) { id name fromSpaceId fromFieldId toSpaceId toFieldId }
  }
"""

CREATE_RELATION = """
  mutation CreateRelation($input: CreateRelationInput!) {
    createRelation(input: $input) { id name fromSpaceId fromFieldId toSpaceId toFieldId }
  }
"""

DELETE_RELATION = """
  mutation DeleteRelation($id: ID!) {
    deleteRelation(id: $id)
  }
"""

window.Spaces =
  list: ->
    GQL.query(LIST_SPACES).then (d) -> d.spaces

  create: (name, description = '') ->
    GQL.mutate(CREATE_SPACE, { input: { name, description } })
      .then (d) -> d.createSpace

  update: (id, name, description) ->
    input = {}
    input.name        = name        if name?
    input.description = description if description?
    GQL.mutate(UPDATE_SPACE, { id, input }).then (d) -> d.updateSpace

  delete: (id) ->
    GQL.mutate(DELETE_SPACE, { id }).then (d) -> d.deleteSpace

  getWithFields: (id) ->
    GQL.query(SPACE_FIELDS, { id }).then (d) -> d.space

  addField: (spaceId, name, fieldType, notNull = false, description = '', formula = null, triggerFields = null, language = 'lua') ->
    input = { name, fieldType, notNull, description }
    input.formula       = formula       if formula
    input.triggerFields = triggerFields if triggerFields
    input.language      = language      if language and language != 'lua'
    GQL.mutate(ADD_FIELD, { spaceId, input })
      .then (d) -> d.addField

  updateField: (fieldId, opts = {}) ->
    input = {}
    input.name          = opts.name          if opts.name?
    input.notNull       = opts.notNull       if opts.notNull?
    input.description   = opts.description   if opts.description?
    input.formula       = opts.formula       if opts.formula?
    input.triggerFields = opts.triggerFields if opts.triggerFields?
    input.language      = opts.language      if opts.language?
    GQL.mutate(UPDATE_FIELD, { fieldId, input }).then (d) -> d.updateField

  listRelations: (spaceId) ->
    GQL.query(LIST_RELATIONS, { spaceId }).then (d) -> d.relations

  createRelation: (name, fromSpaceId, fromFieldId, toSpaceId, toFieldId) ->
    GQL.mutate(CREATE_RELATION, { input: { name, fromSpaceId, fromFieldId, toSpaceId, toFieldId } })
      .then (d) -> d.createRelation

  deleteRelation: (id) ->
    GQL.mutate(DELETE_RELATION, { id }).then (d) -> d.deleteRelation
