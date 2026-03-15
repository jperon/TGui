(function() {
  // frontend/src/graphql_builder.coffee
  // GraphQL Builder with support for list relations and field detection
  var GraphQLBuilder;

  GraphQLBuilder = class GraphQLBuilder {
    constructor({container, allSpaces, allRelations, allFields, onChange}) {
      this.container = container;
      this.allSpaces = allSpaces;
      this.allRelations = allRelations;
      this.allFields = allFields;
      this.onChange = onChange;
      this._query = {
        type: 'Query',
        fields: {}
      };
      this._selectedFields = {}; // spaceId -> Set(fieldName)
      this._computedFields = {}; // fieldName -> formula
      this._aggregations = []; // configuration agrégations
      this._relationTypes = {}; // fieldName -> { type, targetSpace, targetField }
      this._sourceSpaceId = null;
    }

    // Load relation types and detect single vs multiple relations
    loadRelationTypes(spaces, relations) {
      var field, i, isMultiple, len, relation, results, space;
      this._relationTypes = {};
      results = [];
      for (i = 0, len = spaces.length; i < len; i++) {
        space = spaces[i];
        results.push((function() {
          var j, len1, ref, results1;
          ref = space.fields;
          results1 = [];
          for (j = 0, len1 = ref.length; j < len1; j++) {
            field = ref[j];
            if (field.fieldType === 'Relation') {
              relation = relations.find(function(r) {
                return r.fromFieldId === field.id;
              });
              if (relation) {
                // Detect if it's a multiple relation
                isMultiple = this.detectMultipleRelation(space, relation);
                results1.push(this._relationTypes[`${space.name}.${field.name}`] = {
                  type: isMultiple ? 'List' : 'Single',
                  targetSpace: relation.toSpace.name,
                  targetField: relation.toField.name,
                  fromSpaceId: space.id,
                  fromFieldId: field.id,
                  toSpaceId: relation.toSpace.id,
                  toFieldId: relation.toField.id
                });
              } else {
                results1.push(void 0);
              }
            } else {
              results1.push(void 0);
            }
          }
          return results1;
        }).call(this));
      }
      return results;
    }

    // Detect if a relation is multiple by checking target space data
    detectMultipleRelation(space, relation) {
      // This would need to be implemented via GraphQL query to check data
      // For now, assume single unless we have specific metadata
      return false;
    }

    // Set the source space for the query
    setSourceSpace(spaceId) {
      return this._sourceSpaceId = spaceId;
    }

    // Add a field to the selection
    selectField(spaceId, fieldName) {
      var key;
      key = `${spaceId}.${fieldName}`;
      if (!this._selectedFields[key]) {
        this._selectedFields[key] = true;
      }
      return this.updateQuery();
    }

    // Remove a field from selection
    removeField(spaceId, fieldName) {
      var key;
      key = `${spaceId}.${fieldName}`;
      delete this._selectedFields[key];
      return this.updateQuery();
    }

    // Add a computed field
    addComputedField(name, formula, language = 'moonscript') {
      this._computedFields[name] = {formula, language};
      return this.updateQuery();
    }

    // Add an aggregation
    addAggregation(field, func, alias) {
      table.insert(this._aggregations, {
        field,
        func,
        as: alias
      });
      return this.updateQuery();
    }

    // Check if we have list relations
    hasListRelations() {
      var _, i, len, ref, relation;
      ref = pairs(this._relationTypes);
      for (relation = i = 0, len = ref.length; i < len; relation = ++i) {
        _ = ref[relation];
        if (relation.type === 'List') {
          return true;
        }
      }
      return false;
    }

    // Get selected fields with their metadata
    getSelectedFields() {
      var _, fieldName, key, ref, selected, spaceId;
      selected = [];
      ref = this._selectedFields;
      for (key in ref) {
        _ = ref[key];
        [spaceId, fieldName] = key.split('.');
        selected.push({spaceId, fieldName});
      }
      return selected;
    }

    // Get target fields for a space
    getTargetFields(spaceName) {
      var fields, space;
      space = this._allSpaces.find(function(s) {
        return s.name === spaceName;
      });
      if (!space) {
        return [];
      }
      fields = space.fields.map(function(f) {
        return f.name;
      });
      return fields.join(' ');
    }

    // Build standard GraphQL query
    buildStandardQuery() {
      var field, i, len, query, ref, relationType;
      query = "query GetData {\n";
      query += `  records(spaceId: \"${this._sourceSpaceId}\") {\n`;
      ref = this.getSelectedFields();
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        relationType = this._relationTypes[`${field.spaceId}.${field.fieldName}`];
        if ((relationType != null ? relationType.type : void 0) === 'List') {
          // Field of type list - include nested fields
          query += `    ${field.fieldName} {\n`;
          query += "      id\n";
          query += `      ${this.getTargetFields(relationType.targetSpace)}\n`;
          query += "    }\n";
        } else if ((relationType != null ? relationType.type : void 0) === 'Single') {
          // Single relation - include nested fields
          query += `    ${field.fieldName} {\n`;
          query += "      id\n";
          query += `      ${this.getTargetFields(relationType.targetSpace)}\n`;
          query += "    }\n";
        } else {
          // Simple field
          query += `    ${field.fieldName}\n`;
        }
      }
      query += "  }\n";
      query += "}";
      return query;
    }

    // Build query with list support
    buildQueryWithLists() {
      var field, i, len, query, ref, relationType;
      query = "query GetDataWithLists {\n";
      query += `  records(spaceId: \"${this._sourceSpaceId}\") {\n`;
      ref = this.getSelectedFields();
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        relationType = this._relationTypes[`${field.spaceId}.${field.fieldName}`];
        if ((relationType != null ? relationType.type : void 0) === 'List') {
          // List field - preserve structure
          query += `    ${field.fieldName} {\n`;
          query += "      id\n";
          query += `      ${this.getTargetFields(relationType.targetSpace)}\n`;
          query += "    }\n";
        } else if ((relationType != null ? relationType.type : void 0) === 'Single') {
          // Single relation
          query += `    ${field.fieldName} {\n`;
          query += "      id\n";
          query += `      ${this.getTargetFields(relationType.targetSpace)}\n`;
          query += "    }\n";
        } else {
          // Simple field
          query += `    ${field.fieldName}\n`;
        }
      }
      query += "  }\n";
      query += "}";
      return query;
    }

    // Build aggregated query
    buildAggregatedQuery() {
      var query;
      query = "query GetAggregatedData {\n";
      query += `  aggregatedRecords(spaceId: \"${this._sourceSpaceId}\", config: {\n`;
      query += `    groupBy: [${this.buildGroupBy()}]\n`;
      query += `    aggregates: [${this.buildAggregates()}]\n`;
      query += `    filter: ${this.buildFilter()}\n`;
      query += "  }) {\n";
      query += `    ${this.buildSelectedFields()}\n`;
      query += "  }\n";
      query += "}";
      return query;
    }

    // Build group by clause
    buildGroupBy() {
      var groupFields;
      if (this._aggregations.length === 0) {
        return "";
      }
      groupFields = this._aggregations.filter(function(agg) {
        return agg.field;
      }).map(function(agg) {
        return `\"${agg.field}\"`;
      });
      return groupFields.join(', ');
    }

    // Build aggregates clause
    buildAggregates() {
      var aggregates;
      if (this._aggregations.length === 0) {
        return "";
      }
      aggregates = this._aggregations.map(function(agg) {
        return `{ field: \"${agg.field}\", func: ${agg.func.toUpperCase()}, as: \"${agg.as || agg.field}\" }`;
      });
      return aggregates.join(', ');
    }

    // Build filter clause
    buildFilter() {
      // For now, return empty filter
      return "{}";
    }

    // Build selected fields for aggregated query
    buildSelectedFields() {
      var field, fields, i, len, ref;
      fields = [];
      ref = this.getSelectedFields();
      for (i = 0, len = ref.length; i < len; i++) {
        field = ref[i];
        fields.push(field.fieldName);
      }
      return fields.join('\n    ');
    }

    // Main query building method
    buildQuery() {
      if (this._aggregations.length > 0) {
        return this.buildAggregatedQuery();
      } else if (this.hasListRelations()) {
        return this.buildQueryWithLists();
      } else {
        return this.buildStandardQuery();
      }
    }

    // Update the query and notify change
    updateQuery() {
      this._query = this.buildQuery();
      if (this.onChange) {
        return this.onChange(this._query);
      }
    }

    // Get the current query
    getQuery() {
      return this._query;
    }

    // Load configuration from a query string
    loadFromQuery(queryString) {
      var fieldMatches, fieldName, i, len, match;
      // Parse the query and extract selected fields
      // This is a simplified implementation
      this._selectedFields = {};
      
      // Extract field names from the query
      fieldMatches = queryString.match(/(\w+)\s*{/g);
      if (fieldMatches) {
        for (i = 0, len = fieldMatches.length; i < len; i++) {
          match = fieldMatches[i];
          fieldName = match.replace(/\s*{/, '');
          this._selectedFields[`${this._sourceSpaceId}.${fieldName}`] = true;
        }
      }
      return this.updateQuery();
    }

    // Get field definitions for flattening
    getFieldDefinitions() {
      var _, definitions, field, fieldName, key, ref, relationType, space, spaceId;
      definitions = {};
      ref = this._selectedFields;
      for (key in ref) {
        _ = ref[key];
        [spaceId, fieldName] = key.split('.');
        relationType = this._relationTypes[key];
        if (relationType) {
          definitions[fieldName] = {
            type: relationType.type,
            space: relationType.targetSpace,
            isRelation: true
          };
        } else {
          // Find field metadata
          space = this._allSpaces.find(function(s) {
            return s.id === spaceId;
          });
          if (space) {
            field = space.fields.find(function(f) {
              return f.name === fieldName;
            });
            if (field) {
              definitions[fieldName] = {
                type: field.fieldType,
                space: space.name,
                isRelation: false
              };
            }
          }
        }
      }
      return definitions;
    }

  };

  // Export for use in other modules
  window.GraphQLBuilder = GraphQLBuilder;

}).call(this);
