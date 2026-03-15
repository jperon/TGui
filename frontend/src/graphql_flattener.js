(function() {
  // frontend/src/graphql_flattener.coffee
  // GraphQL Flattener with intelligent list handling
  var GraphQLFlattener;

  GraphQLFlattener = class GraphQLFlattener {
    // Main flattening method
    static flatten(data, query, fieldDefinitions) {
      var flat, flattened, j, len, record, records;
      flattened = [];
      records = data.records || data;
      if (!records) {
        return flattened;
      }
      for (j = 0, len = records.length; j < len; j++) {
        record = records[j];
        flat = this.flattenRecord(record, query, fieldDefinitions, "");
        table.insert(flattened, flat);
      }
      return flattened;
    }

    // Flatten a single record
    static flattenRecord(record, query, fieldDefinitions, prefix = "") {
      var columnName, field, fieldDef, flat, nested, value;
      flat = {};
      for (field in record) {
        value = record[field];
        fieldDef = this.findFieldDefinition(field, fieldDefinitions, prefix);
        if (this.isListValue(value, fieldDef)) {
          // List of records - preserve as array
          flat[`${prefix}${field}`] = this.flattenList(value, query, fieldDefinitions, `${prefix}${field}_`);
        } else if (this.isObject(value) && !this.isDate(value) && !this.isSimpleType(value)) {
          // Object - flatten recursively
          nested = this.flattenRecord(value, query, fieldDefinitions, `${prefix}${field}_`);
          Object.assign(flat, nested);
        } else {
          // Simple field
          columnName = prefix !== "" ? `${prefix}${field}` : field;
          flat[columnName] = value;
        }
      }
      return flat;
    }

    // Flatten a list of records
    static flattenList(list, query, fieldDefinitions, prefix) {
      var flat_item, flattened_list, i, item, j, len, ref;
      flattened_list = [];
      ref = ipairs(list);
      for (item = j = 0, len = ref.length; j < len; item = ++j) {
        i = ref[item];
        if (this.isObject(item) && !this.isDate(item) && !this.isSimpleType(item)) {
          flat_item = this.flattenRecord(item, query, fieldDefinitions, `${prefix}${i}_`);
          table.insert(flattened_list, flat_item);
        } else {
          // Simple item in list
          flattened_list[`${prefix}${i}`] = item;
        }
      }
      return flattened_list;
    }

    // Find field definition by name
    static findFieldDefinition(fieldName, fieldDefinitions, prefix) {
      var baseName, prefixedName;
      // Try exact match first
      if (fieldDefinitions[fieldName]) {
        return fieldDefinitions[fieldName];
      }
      
      // Try with prefix
      prefixedName = prefix + fieldName;
      if (fieldDefinitions[prefixedName]) {
        return fieldDefinitions[prefixedName];
      }
      
      // Try without prefix for nested fields
      if (prefix !== "") {
        baseName = fieldName.replace(new RegExp(`^${prefix}`), '');
        if (fieldDefinitions[baseName]) {
          return fieldDefinitions[baseName];
        }
      }
      return null;
    }

    // Check if value is a list
    static isListValue(value, fieldDef) {
      var firstItem;
      if (!value) {
        return false;
      }
      
      // Check field definition type
      if ((fieldDef != null ? fieldDef.type : void 0) === 'List') {
        return true;
      }
      
      // Check if it's an array with objects
      if (this.isArray(value) && value.length > 0) {
        firstItem = value[1] || value[0];
        return this.isObject(firstItem) && !this.isSimpleType(firstItem);
      }
      return false;
    }

    // Check if value is an array
    static isArray(value) {
      return type(value) === 'table' && this.isNumericArray(value);
    }

    // Check if table is a numeric array (has consecutive numeric keys starting from 1)
    static isNumericArray(table) {
      var _, count, key, ref;
      if (!table) {
        return false;
      }
      count = 0;
      ref = pairs(table);
      for (key in ref) {
        _ = ref[key];
        if (type(key) !== 'number') {
          return false;
        }
        count += 1;
      }
      return count > 0;
    }

    // Check if value is an object (table with string keys)
    static isObject(value) {
      return type(value) === 'table' && !this.isNumericArray(value);
    }

    // Check if value is a date
    static isDate(value) {
      if (!value) {
        return false;
      }
      return type(value) === 'table' && value.year && value.month && value.day;
    }

    // Check if value is a simple type (string, number, boolean)
    static isSimpleType(value) {
      var typeValue;
      typeValue = type(value);
      return typeValue === 'string' || typeValue === 'number' || typeValue === 'boolean';
    }

    // Convert list to Lua-style array for computed fields
    static convertToList(luaTable) {
      var i, j, len, ref, result, v;
      result = {};
      ref = ipairs(luaTable);
      for (v = j = 0, len = ref.length; j < len; v = ++j) {
        i = ref[v];
        result[i] = v;
      }
      return result;
    }

    // Generate column names from query
    static generateColumnNames(query) {
      var columnNames, fieldMatches, fieldName, j, len, match;
      // Simple implementation - extract field names from query
      columnNames = [];
      
      // Match field selections
      fieldMatches = query.match(/(\w+)\s*(?:\{[^}]*\})?/g);
      if (fieldMatches) {
        for (j = 0, len = fieldMatches.length; j < len; j++) {
          match = fieldMatches[j];
          fieldName = match.match(/(\w+)/)[1];
          table.insert(columnNames, fieldName);
        }
      }
      return columnNames;
    }

    // Detect list fields in data
    static detectListFields(data) {
      var field, firstItem, firstRecord, listFields, records, ref, value;
      listFields = {};
      records = data.records || data;
      if (!(records && records.length > 0)) {
        return listFields;
      }
      
      // Check first record for list fields
      firstRecord = records[1];
      ref = pairs(firstRecord);
      for (field in ref) {
        value = ref[field];
        if (this.isArray(value) && value.length > 0) {
          firstItem = value[1] || value[0];
          if (this.isObject(firstItem)) {
            listFields[field] = true;
          }
        }
      }
      return listFields;
    }

  };

  // Export for use in other modules
  window.GraphQLFlattener = GraphQLFlattener;

}).call(this);
