(function() {
  // spaces.coffee
  // Space and field management.
  var ADD_FIELD, CREATE_RELATION, CREATE_SPACE, DELETE_RELATION, DELETE_SPACE, LIST_RELATIONS, LIST_SPACES, SPACE_FIELDS, UPDATE_FIELD, UPDATE_SPACE;

  LIST_SPACES = `query { spaces { id name description fields { id name fieldType notNull position description formula triggerFields language } } }`;

  CREATE_SPACE = `mutation CreateSpace($input: CreateSpaceInput!) {
  createSpace(input: $input) { id name description }
}`;

  DELETE_SPACE = `mutation DeleteSpace($id: ID!) {
  deleteSpace(id: $id)
}`;

  SPACE_FIELDS = `query SpaceFields($id: ID!) {
  space(id: $id) {
    id name description
    fields { id name fieldType notNull position description formula triggerFields language }
  }
}`;

  ADD_FIELD = `mutation AddField($spaceId: ID!, $input: FieldInput!) {
  addField(spaceId: $spaceId, input: $input) {
    id name fieldType notNull position
  }
}`;

  UPDATE_SPACE = `mutation UpdateSpace($id: ID!, $input: UpdateSpaceInput!) {
  updateSpace(id: $id, input: $input) { id name description }
}`;

  UPDATE_FIELD = `mutation UpdateField($fieldId: ID!, $input: UpdateFieldInput!) {
  updateField(fieldId: $fieldId, input: $input) {
    id name fieldType notNull position description formula triggerFields language
  }
}`;

  LIST_RELATIONS = `query Relations($spaceId: ID!) {
  relations(spaceId: $spaceId) { id name fromSpaceId fromFieldId toSpaceId toFieldId }
}`;

  CREATE_RELATION = `mutation CreateRelation($input: CreateRelationInput!) {
  createRelation(input: $input) { id name fromSpaceId fromFieldId toSpaceId toFieldId }
}`;

  DELETE_RELATION = `mutation DeleteRelation($id: ID!) {
  deleteRelation(id: $id)
}`;

  window.Spaces = {
    list: function() {
      return GQL.query(LIST_SPACES).then(function(d) {
        return d.spaces;
      });
    },
    create: function(name, description = '') {
      return GQL.mutate(CREATE_SPACE, {
        input: {name, description}
      }).then(function(d) {
        return d.createSpace;
      });
    },
    update: function(id, name, description) {
      var input;
      input = {};
      if (name != null) {
        input.name = name;
      }
      if (description != null) {
        input.description = description;
      }
      return GQL.mutate(UPDATE_SPACE, {id, input}).then(function(d) {
        return d.updateSpace;
      });
    },
    delete: function(id) {
      return GQL.mutate(DELETE_SPACE, {id}).then(function(d) {
        return d.deleteSpace;
      });
    },
    getWithFields: function(id) {
      return GQL.query(SPACE_FIELDS, {id}).then(function(d) {
        return d.space;
      });
    },
    addField: function(spaceId, name, fieldType, notNull = false, description = '', formula = null, triggerFields = null, language = 'lua') {
      var input;
      input = {name, fieldType, notNull, description};
      if (formula) {
        input.formula = formula;
      }
      if (triggerFields) {
        input.triggerFields = triggerFields;
      }
      if (language && language !== 'lua') {
        input.language = language;
      }
      return GQL.mutate(ADD_FIELD, {spaceId, input}).then(function(d) {
        return d.addField;
      });
    },
    updateField: function(fieldId, opts = {}) {
      var input;
      input = {};
      if (opts.name != null) {
        input.name = opts.name;
      }
      if (opts.notNull != null) {
        input.notNull = opts.notNull;
      }
      if (opts.description != null) {
        input.description = opts.description;
      }
      if (opts.formula != null) {
        input.formula = opts.formula;
      }
      if (opts.triggerFields != null) {
        input.triggerFields = opts.triggerFields;
      }
      if (opts.language != null) {
        input.language = opts.language;
      }
      return GQL.mutate(UPDATE_FIELD, {fieldId, input}).then(function(d) {
        return d.updateField;
      });
    },
    listRelations: function(spaceId) {
      return GQL.query(LIST_RELATIONS, {spaceId}).then(function(d) {
        return d.relations;
      });
    },
    createRelation: function(name, fromSpaceId, fromFieldId, toSpaceId, toFieldId) {
      return GQL.mutate(CREATE_RELATION, {
        input: {name, fromSpaceId, fromFieldId, toSpaceId, toFieldId}
      }).then(function(d) {
        return d.createRelation;
      });
    },
    deleteRelation: function(id) {
      return GQL.mutate(DELETE_RELATION, {id}).then(function(d) {
        return d.deleteRelation;
      });
    },
    aggregateSpace: function(spaceName, groupBy, aggregate) {
      var q;
      q = `query AggregateSpace($spaceName: String!, $groupBy: [String!]!, $aggregate: [AggregateInput!]!) {
  aggregateSpace(spaceName: $spaceName, groupBy: $groupBy, aggregate: $aggregate)
}`;
      return GQL.query(q, {spaceName, groupBy, aggregate}).then(function(d) {
        return d.aggregateSpace;
      });
    }
  };

}).call(this);
