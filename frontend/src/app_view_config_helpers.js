(function() {
  // app_view_config_helpers.coffee — Data View configuration modal logic
  window.AppViewConfigHelpers = {
    _currentViewId: null,
    bindDataViewModal: function(app) {
      var tabs;
      app.el.dataViewModalCloseBtn().addEventListener('click', () => {
        return app.el.dataViewModal().classList.add('hidden');
      });
      app.el.dataViewSaveBtn().addEventListener('click', () => {
        return this.saveDataView(app);
      });
      // YAML Editor buttons
      app.el.dvFormatYamlBtn().addEventListener('click', () => {
        return this.formatYaml(app);
      });
      app.el.dvApplyYamlBtn().addEventListener('click', () => {
        return this.applyYamlToVisual(app);
      });
      // Tabs logic
      tabs = app.el.dataViewModal().querySelectorAll('.tab-btn');
      tabs.forEach(function(btn) {
        return btn.addEventListener('click', function() {
          var target;
          tabs.forEach(function(b) {
            return b.classList.remove('active');
          });
          btn.classList.add('active');
          target = btn.dataset.tab;
          return ['fields', 'filter', 'group'].forEach(function(t) {
            return document.getElementById(`dv-tab-${t}`).classList.toggle('hidden', t !== target);
          });
        });
      });
      // Note: dv-add-col-btn removed - now using field selection interface
      app.el.dvAddAggBtn().addEventListener('click', () => {
        return this._addAggregateRow(app);
      });
      // YAML editor change detection
      return app.el.dvYamlContent().addEventListener('input', () => {
        return this.markYamlAsChanged(app);
      });
    },
    openDataViewConfigModal: function(app, view = null) {
      var agg, i, j, len, len1, option, ref, ref1, ref2, ref3, ref4, ref5, select, sp;
      this._currentViewId = (view != null ? view.id : void 0) || null;
      app.el.dataViewModalTitle().textContent = view ? `Modifier la vue : ${view.name}` : "Nouvelle vue";
      app.el.dvName().value = (view != null ? view.name : void 0) || '';
      // Populate source select
      select = app.el.dvSource();
      select.innerHTML = '<option value="">Sélectionner un espace...</option>';
      ref = app._allSpaces || [];
      for (i = 0, len = ref.length; i < len; i++) {
        sp = ref[i];
        option = document.createElement('option');
        option.value = sp.id;
        option.textContent = sp.name;
        option.selected = sp.id === (view != null ? view.sourceSpace : void 0);
        select.appendChild(option);
      }
      // Reset dynamic lists
      this.resetDataViewFields(app);
      app.el.dvAggregatesList().innerHTML = '';
      app.el.dvFilterFormula().value = (view != null ? (ref1 = view.config) != null ? (ref2 = ref1.filter) != null ? ref2.formula : void 0 : void 0 : void 0) || '';
      // Initialize YAML editor
      this.initializeYamlEditor(app, view);
      // Initialize fields tab with ERD graph
      this.initializeFieldsTab(app);
      // Load existing data
      if (view != null ? (ref3 = view.config) != null ? ref3.columns : void 0 : void 0) {
        this.loadExistingColumns(app, view.config.columns);
      } else if (!view) {
        this.resetDataViewFields(app); // Start with empty fields for new view
      }
      if (view != null ? (ref4 = view.config) != null ? ref4.aggregates : void 0 : void 0) {
        ref5 = view.config.aggregates;
        for (j = 0, len1 = ref5.length; j < len1; j++) {
          agg = ref5[j];
          this._addAggregateRow(app, agg.field, agg.func, agg.alias);
        }
      }
      // Setup field selection when source changes
      app.el.dvSource().addEventListener('change', () => {
        this.loadSourceFields(app);
        // Reinitialize fields graph with new source
        return this.initializeFieldsGraph(app);
      });
      // Load initial fields if source is selected
      if (view != null ? view.sourceSpace : void 0) {
        this.loadSourceFields(app, view.sourceSpace);
      }
      return app.el.dataViewModal().classList.remove('hidden');
    },
    _addColumnRow: function(app, name = '', label = '') {
      var container, inputLabel, inputName, removeBtn, row;
      container = app.el.dvColumnsList();
      row = document.createElement('div');
      row.className = 'dv-row';
      inputName = document.createElement('input');
      inputName.type = 'text';
      inputName.placeholder = 'Nom du champ (ex: name)';
      inputName.value = name;
      inputName.className = 'dv-col-name';
      inputLabel = document.createElement('input');
      inputLabel.type = 'text';
      inputLabel.placeholder = 'Libellé (ex: Nom)';
      inputLabel.value = label;
      inputLabel.className = 'dv-col-label';
      removeBtn = document.createElement('button');
      removeBtn.className = 'remove-btn';
      removeBtn.textContent = '🗑';
      removeBtn.onclick = function() {
        return row.remove();
      };
      row.appendChild(inputName);
      row.appendChild(inputLabel);
      row.appendChild(removeBtn);
      return container.appendChild(row);
    },
    _addAggregateRow: function(app, field = '', func = 'SUM', alias = '') {
      var container, inputAlias, inputField, removeBtn, row, selectFunc;
      container = app.el.dvAggregatesList();
      row = document.createElement('div');
      row.className = 'dv-row';
      inputField = document.createElement('input');
      inputField.type = 'text';
      inputField.placeholder = 'Champ';
      inputField.value = field;
      inputField.className = 'dv-agg-field';
      selectFunc = document.createElement('select');
      selectFunc.className = 'dv-agg-func';
      ['SUM', 'AVG', 'COUNT', 'MIN', 'MAX'].forEach(function(f) {
        var opt;
        opt = document.createElement('option');
        opt.value = f;
        opt.textContent = f;
        opt.selected = f === func;
        return selectFunc.appendChild(opt);
      });
      inputAlias = document.createElement('input');
      inputAlias.type = 'text';
      inputAlias.placeholder = 'Alias';
      inputAlias.value = alias;
      inputAlias.className = 'dv-agg-alias';
      removeBtn = document.createElement('button');
      removeBtn.className = 'remove-btn';
      removeBtn.textContent = '🗑';
      removeBtn.onclick = function() {
        return row.remove();
      };
      row.appendChild(inputField);
      row.appendChild(selectFunc);
      row.appendChild(inputAlias);
      row.appendChild(removeBtn);
      return container.appendChild(row);
    },
    saveDataView: function(app) {
      var aggregates, columns, config, filter, filterFormula, groupBy, groupByContainer, i, input, joins, len, name, promise, ref, relation, selectedContainer, selectedRelations, sourceSpace;
      name = app.el.dvName().value.trim();
      sourceSpace = app.el.dvSource().value;
      if (!(name && sourceSpace)) {
        return tdbAlert("Le nom et l'espace source sont obligatoires", 'error');
      }
      // Gather columns from new unified interface
      columns = [];
      selectedContainer = document.getElementById('dv-selected-fields');
      if (selectedContainer) {
        selectedContainer.querySelectorAll('.selected-field-item').forEach(function(fieldItem) {
          return columns.push({
            name: fieldItem.dataset.fieldName,
            label: fieldItem.dataset.fieldName,
            spaceId: fieldItem.dataset.spaceId
          });
        });
      }
      // Gather groupBy from new interface
      groupBy = [];
      groupByContainer = document.getElementById('dv-groupby-selected');
      if (groupByContainer) {
        groupByContainer.querySelectorAll('.field-item').forEach(function(fieldItem) {
          return groupBy.push(fieldItem.dataset.fieldName);
        });
      }
      // Gather aggregates
      aggregates = [];
      app.el.dvAggregatesList().querySelectorAll('.dv-row').forEach(function(row) {
        var aAlias, aField, aFunc;
        aField = row.querySelector('.dv-agg-field').value.trim();
        aFunc = row.querySelector('.dv-agg-func').value;
        aAlias = row.querySelector('.dv-agg-alias').value.trim();
        if (aField) {
          return aggregates.push({
            field: aField,
            func: aFunc,
            alias: aAlias || `${aFunc.toLowerCase()}_${aField}`
          });
        }
      });
      filterFormula = app.el.dvFilterFormula().value.trim();
      filter = filterFormula ? {
        formula: filterFormula,
        language: 'moonscript'
      } : null;
      // Gather selected joins
      joins = [];
      selectedRelations = ((ref = this._joinsYamlBuilder) != null ? ref.getSelectedRelations() : void 0) || [];
      for (i = 0, len = selectedRelations.length; i < len; i++) {
        relation = selectedRelations[i];
        joins.push({
          fromSpace: relation.fromSpaceId,
          toSpace: relation.toSpaceId,
          fromField: relation.fromFieldId,
          toField: relation.toFieldId,
          relationType: relation.type || 'foreign_key'
        });
      }
      config = {
        columns: columns.length > 0 ? columns : null,
        filter: filter,
        groupBy: groupBy.length > 0 ? groupBy : null,
        aggregates: aggregates.length > 0 ? aggregates : null,
        joins: joins.length > 0 ? joins : null
      };
      input = {
        name: name,
        sourceSpace: sourceSpace,
        config: JSON.stringify(config)
      };
      promise = this._currentViewId ? DataViews.update(this._currentViewId, input) : DataViews.create(input);
      return promise.then((view) => {
        app.el.dataViewModal().classList.add('hidden');
        return app.loadDataViews().then(() => {
          return app.selectDataView(view);
        });
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    // Nouvelles fonctions pour l'interface unifiée de champs et jointures
    resetDataViewFields: function(app) {
      var selectedContainer;
      selectedContainer = document.getElementById('dv-selected-fields');
      if (selectedContainer) {
        return selectedContainer.innerHTML = '<div class="field-placeholder">Aucun champ sélectionné</div>';
      }
    },
    loadSourceFields: function(app, spaceId = null) {
      var space;
      if (!spaceId) {
        spaceId = app.el.dvSource().value;
      }
      if (!spaceId) {
        return;
      }
      // Find space data
      space = (app._allSpaces || []).find(function(sp) {
        return sp.id === spaceId;
      });
      if (!space) {
        return;
      }
      // Initialize YamlBuilder with field selection integration
      return this.initializeFieldsGraph(app, spaceId);
    },
    initializeFieldsTab: function(app) {
      var joinsContainer, selectedContainer;
      // Initialize fields tab with placeholder
      joinsContainer = document.getElementById('dv-joins-graph-container');
      selectedContainer = document.getElementById('dv-selected-fields');
      if (joinsContainer) {
        joinsContainer.innerHTML = '<div class="joins-placeholder">Sélectionnez un espace source pour voir les relations...</div>';
      }
      if (selectedContainer) {
        return selectedContainer.innerHTML = '<div class="field-placeholder">Aucun champ sélectionné</div>';
      }
    },
    initializeFieldsGraph: function(app, spaceId) {
      var joinsContainer;
      joinsContainer = document.getElementById('dv-joins-graph-container');
      if (!(joinsContainer && spaceId)) {
        return;
      }
      // Load all relations and initialize YamlBuilder
      return window.AppViewHelpers.loadAllRelations(app).then((relations) => {
        // Create a YamlBuilder for field selection and automatic joins
        this._fieldsYamlBuilder = new YamlBuilder({
          container: joinsContainer,
          allSpaces: app._allSpaces,
          allRelations: relations,
          onChange: (yaml) => { // Handle field selection changes
            return this.updateSelectedFields(app);
          },
          mode: 'field-selection', // Special mode for field selection
          focusSpaceId: spaceId, // Focus on the source space
          onFieldClick: (fieldInfo) => { // Handle field clicks
            return this.toggleFieldSelection(app, fieldInfo);
          }
        });
        this._fieldsYamlBuilder.mount();
        // Store current space for reference
        this._currentSourceSpaceId = spaceId;
        return console.log('Fields graph initialized for space:', spaceId);
      });
    },
    toggleFieldSelection: function(app, fieldInfo) {
      var existingField, fieldItem, removeBtn, selectedContainer;
      selectedContainer = document.getElementById('dv-selected-fields');
      if (!selectedContainer) {
        return;
      }
      // Check if field is already selected
      existingField = selectedContainer.querySelector(`[data-field-id='${fieldInfo.id}']`);
      if (existingField) {
        // Remove field from selection
        existingField.remove();
        return console.log('Field removed from selection:', fieldInfo.name);
      } else {
        // Add field to selection
        fieldItem = document.createElement('div');
        fieldItem.className = 'selected-field-item';
        fieldItem.dataset.fieldId = fieldInfo.id;
        fieldItem.dataset.spaceId = fieldInfo.spaceId;
        fieldItem.dataset.fieldName = fieldInfo.name;
        fieldItem.dataset.fieldType = fieldInfo.type;
        fieldItem.innerHTML = `<div class="field-info">
  <strong>${fieldInfo.spaceName}</strong>.${fieldInfo.name}
  <br>
  <small>Type: ${fieldInfo.type}</small>
</div>
<button class="remove-field-btn" data-field-id="${fieldInfo.id}">✕</button>`;
        // Add remove functionality
        removeBtn = fieldItem.querySelector('.remove-field-btn');
        removeBtn.addEventListener('click', () => {
          return this.toggleFieldSelection(app, fieldInfo);
        });
        selectedContainer.appendChild(fieldItem);
        return console.log('Field added to selection:', fieldInfo.name);
      }
    },
    updateSelectedFields: function(app) {
      // This will be called when YamlBuilder detects changes
      // For now, the field selection is handled by toggleFieldSelection
      return console.log('Field selection updated');
    },
    loadExistingColumns: function(app, columns) {
      var col, fieldInfo, i, len, results, selectedContainer;
      selectedContainer = document.getElementById('dv-selected-fields');
      if (!selectedContainer) {
        return;
      }
// Load existing columns as selected fields
      results = [];
      for (i = 0, len = columns.length; i < len; i++) {
        col = columns[i];
        // Find the corresponding field in all spaces
        fieldInfo = this.findFieldInfo(app, col.name);
        if (fieldInfo) {
          results.push(this.toggleFieldSelection(app, fieldInfo));
        } else {
          results.push(void 0);
        }
      }
      return results;
    },
    findFieldInfo: function(app, fieldName) {
      var field, i, j, len, len1, ref, ref1, space;
      ref = app._allSpaces || [];
      // Search through all spaces to find field info
      for (i = 0, len = ref.length; i < len; i++) {
        space = ref[i];
        ref1 = space.fields || [];
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          field = ref1[j];
          if (field.name === fieldName) {
            return {
              id: field.id,
              name: field.name,
              type: field.fieldType,
              spaceId: space.id,
              spaceName: space.name
            };
          }
        }
      }
      return null;
    },
    // ── Fields Tab Functions ─────────────────────────────────────────────────────
    initializeFieldsTab: function(app) {
      // Initialize the ERD graph container
      return this.initializeFieldsGraph(app);
    },
    initializeFieldsGraph: function(app) {
      var container, error, sourceId;
      container = document.getElementById('dv-joins-graph-container');
      if (!container) {
        return;
      }
      // Check if YamlBuilder is available
      if (typeof window.YamlBuilder === 'undefined') {
        container.innerHTML = '<div class="joins-placeholder">YamlBuilder non disponible</div>';
        return;
      }
      try {
        // Initialize YamlBuilder for field selection
        this._fieldsYamlBuilder = new YamlBuilder(container, {
          mode: 'field-selection',
          onFieldClick: (fieldData) => {
            return this.toggleFieldSelection(app, fieldData);
          },
          onRelationClick: (relationData) => {
            return this.handleRelationClick(app, relationData);
          }
        });
        // Load relations if source is selected
        sourceId = app.el.dvSource().value;
        if (sourceId) {
          return this.loadRelationsForSpace(app, sourceId);
        } else {
          return container.innerHTML = '<div class="joins-placeholder">Sélectionnez un espace source pour voir les relations...</div>';
        }
      } catch (error1) {
        error = error1;
        console.error('Error initializing fields graph:', error);
        return container.innerHTML = '<div class="joins-placeholder">Erreur lors du chargement du graphe</div>';
      }
    },
    loadRelationsForSpace: function(app, spaceId) {
      if (!this._fieldsYamlBuilder) {
        return;
      }
      // Load all relations for the selected space
      return window.GQL.query(`query {
  spaces {
    id
    name
    fields {
      id
      name
      fieldType
    }
    relations {
      id
      name
      sourceSpace {
        id
        name
      }
      targetSpace {
        id
        name
      }
      sourceField {
        id
        name
      }
      targetField {
        id
        name
      }
    }
  }
}`, (data) => {
        if (data != null ? data.spaces : void 0) {
          this._fieldsYamlBuilder.loadRelations(data.spaces);
          return console.log(`Fields graph initialized for space: ${spaceId}`);
        } else {
          return console.error('Failed to load relations');
        }
      });
    },
    toggleFieldSelection: function(app, fieldData) {
      var existingItem, fieldItem, selectedContainer;
      selectedContainer = document.getElementById('dv-selected-fields');
      if (!selectedContainer) {
        return;
      }
      // Check if field is already selected
      existingItem = selectedContainer.querySelector(`[data-field-id=\"${fieldData.id}\"]`);
      if (existingItem) {
        // Remove field from selection
        existingItem.remove();
      } else {
        // Add field to selection
        fieldItem = document.createElement('div');
        fieldItem.className = 'selected-field-item';
        fieldItem.dataset.fieldId = fieldData.id;
        fieldItem.dataset.fieldName = fieldData.name;
        fieldItem.dataset.spaceId = fieldData.spaceId;
        fieldItem.dataset.spaceName = fieldData.spaceName;
        fieldItem.dataset.fieldType = fieldData.type;
        fieldItem.innerHTML = `<div class="field-info">
  <strong>${fieldData.name}</strong>
  <small>${fieldData.spaceName}.${fieldData.name} (${fieldData.type})</small>
</div>
<button class="remove-field-btn" onclick="window.AppViewConfigHelpers.removeField(this)">✕</button>`;
        selectedContainer.appendChild(fieldItem);
      }
      // Update YAML editor
      return this.syncVisualToYaml(app);
    },
    removeField: function(button) {
      var fieldItem;
      fieldItem = button.closest('.selected-field-item');
      if (fieldItem != null) {
        fieldItem.remove();
      }
      return this.syncVisualToYaml(window.App);
    },
    handleRelationClick: function(app, relationData) {
      // Handle relation click for automatic joins
      return console.log('Relation clicked:', relationData);
    },
    // For now, just log - automatic join logic can be added later
    initializeYamlEditor: function(app, view = null) {
      var config, yaml, yamlContent;
      yamlContent = app.el.dvYamlContent();
      if (view != null ? view.config : void 0) {
        // Load existing configuration as YAML
        config = view.config;
        yaml = this.configToYaml(config);
        yamlContent.value = yaml;
      } else {
        // Default template
        yamlContent.value = this.getDefaultYamlTemplate();
      }
      return this._yamlChanged = false;
    },
    getDefaultYamlTemplate: function() {
      return `# Configuration de la vue
# Modifiez ce YAML ou utilisez les onglets visuels à droite

columns: []
  # Exemple:
  # - name: id
  # - name: titre
  # - name: prix

filter:
  formula: ""
  # Exemple:
  # formula: "@prix > 20 and @disponible == true"

groupBy: []
  # Exemple:
  # - genre
  # - annee_publication

aggregates: []
  # Exemple:
  # - field: prix
  #   func: AVG
  #   alias: prix_moyen`;
    },
    configToYaml: function(config) {
      var agg, col, field, i, j, k, len, len1, len2, lines, ref, ref1, ref2, ref3, ref4, ref5, ref6;
      lines = ['columns:'];
      // Add columns
      if ((config != null ? (ref = config.columns) != null ? ref.length : void 0 : void 0) > 0) {
        ref1 = config.columns;
        for (i = 0, len = ref1.length; i < len; i++) {
          col = ref1[i];
          lines.push(`  - name: ${col.name}`);
          if (col.label && col.label !== col.name) {
            lines.push(`    label: ${col.label || col.name}`);
          }
        }
      } else {
        lines.push('  []');
      }
      lines.push('');
      // Add filter
      if (config != null ? (ref2 = config.filter) != null ? ref2.formula : void 0 : void 0) {
        lines.push('filter:');
        lines.push(`  formula: \"${config.filter.formula}\"`);
        if (config.filter.language) {
          lines.push(`  language: ${config.filter.language || 'moonscript'}`);
        }
      } else {
        lines.push('filter:');
        lines.push('  formula: ""');
      }
      lines.push('');
      // Add groupBy
      if ((config != null ? (ref3 = config.groupBy) != null ? ref3.length : void 0 : void 0) > 0) {
        lines.push('groupBy:');
        ref4 = config.groupBy;
        for (j = 0, len1 = ref4.length; j < len1; j++) {
          field = ref4[j];
          lines.push(`  - ${field}`);
        }
      } else {
        lines.push('groupBy: []');
      }
      lines.push('');
      // Add aggregates
      if ((config != null ? (ref5 = config.aggregates) != null ? ref5.length : void 0 : void 0) > 0) {
        lines.push('aggregates:');
        ref6 = config.aggregates;
        for (k = 0, len2 = ref6.length; k < len2; k++) {
          agg = ref6[k];
          lines.push(`  - field: ${agg.field}`);
          lines.push(`    func: ${agg.func}`);
          if (agg.alias) {
            lines.push(`    alias: ${agg.alias}`);
          }
        }
      } else {
        lines.push('aggregates: []');
      }
      return lines.join('\n');
    },
    formatYaml: function(app) {
      var content, error, formatted, i, indent, len, line, lines, yaml, yamlContent;
      yamlContent = app.el.dvYamlContent();
      try {
        // Basic YAML formatting (could be enhanced with a proper YAML library)
        yaml = yamlContent.value;
        // Simple formatting - in a real implementation, use js-yaml
        lines = yaml.split('\n');
        formatted = [];
        for (i = 0, len = lines.length; i < len; i++) {
          line = lines[i];
          if (line.trim() === '') {
            formatted.push('');
          } else if (line.startsWith('#')) {
            formatted.push(line);
          } else {
            // Basic indentation fix
            indent = line.match(/^(\s*)/)[1];
            content = line.trim();
            if (content.includes(':') && !content.startsWith('-')) {
              formatted.push(`${indent}${content}`);
            } else {
              formatted.push(line);
            }
          }
        }
        yamlContent.value = formatted.join('\n');
        return tdbAlert('YAML formaté avec succès', 'success');
      } catch (error1) {
        error = error1;
        return tdbAlert('Erreur lors du formatage YAML', 'error');
      }
    },
    applyYamlToVisual: function(app) {
      var config, error, yamlContent;
      yamlContent = app.el.dvYamlContent();
      try {
        config = this.yamlToConfig(yamlContent.value);
        this.updateVisualFromConfig(app, config);
        this._yamlChanged = false;
        return tdbAlert('YAML appliqué à l\'interface visuelle', 'success');
      } catch (error1) {
        error = error1;
        return tdbAlert('Erreur dans le YAML: ' + error.message, 'error');
      }
    },
    yamlToConfig: function(yaml) {
      var config, currentArray, currentSection, field, formula, i, item, len, line, lines, name, ref, ref1, ref2, ref3, ref4, ref5, trimmed;
      // Simple YAML parsing (in production, use js-yaml library)
      config = {
        columns: [],
        filter: null,
        groupBy: [],
        aggregates: []
      };
      lines = yaml.split('\n');
      currentSection = null;
      currentArray = null;
      for (i = 0, len = lines.length; i < len; i++) {
        line = lines[i];
        trimmed = line.trim();
        if (trimmed === '' || trimmed.startsWith('#')) {
          continue;
        }
        if (trimmed.startsWith('columns:')) {
          currentSection = 'columns';
          currentArray = config.columns;
        } else if (trimmed.startsWith('filter:')) {
          currentSection = 'filter';
          config.filter = {
            formula: '',
            language: 'moonscript'
          };
        } else if (trimmed.startsWith('groupBy:')) {
          currentSection = 'groupBy';
          currentArray = config.groupBy;
        } else if (trimmed.startsWith('aggregates:')) {
          currentSection = 'aggregates';
          currentArray = config.aggregates;
        } else if (currentSection && trimmed.startsWith('-')) {
          item = trimmed.substring(1).trim();
          if (currentSection === 'columns' && item.includes('name:')) {
            name = (ref = item.match(/name:\s*(.+)/)) != null ? (ref1 = ref[1]) != null ? ref1.trim() : void 0 : void 0;
            config.columns.push({
              name: name,
              label: name
            });
          } else if (currentSection === 'groupBy') {
            config.groupBy.push(item);
          } else if (currentSection === 'aggregates' && item.includes('field:')) {
            field = (ref2 = item.match(/field:\s*(.+)/)) != null ? (ref3 = ref2[1]) != null ? ref3.trim() : void 0 : void 0;
            config.aggregates.push({
              field: field,
              func: 'SUM',
              alias: `${field.toLowerCase()}_sum`
            });
          }
        } else if (currentSection === 'filter' && trimmed.includes('formula:')) {
          formula = (ref4 = trimmed.match(/formula:\s*"(.+)"/)) != null ? (ref5 = ref4[1]) != null ? ref5.trim() : void 0 : void 0;
          if (formula) {
            config.filter.formula = formula;
          }
        }
      }
      return config;
    },
    updateVisualFromConfig: function(app, config) {
      var agg, i, len, ref, ref1, ref2, ref3, results;
      // Update fields tab
      this.resetDataViewFields(app);
      if (((ref = config.columns) != null ? ref.length : void 0) > 0) {
        this.loadExistingColumns(app, config.columns);
      }
      // Update filter tab
      app.el.dvFilterFormula().value = ((ref1 = config.filter) != null ? ref1.formula : void 0) || '';
      // Update aggregates
      app.el.dvAggregatesList().innerHTML = '';
      if (((ref2 = config.aggregates) != null ? ref2.length : void 0) > 0) {
        ref3 = config.aggregates;
        results = [];
        for (i = 0, len = ref3.length; i < len; i++) {
          agg = ref3[i];
          results.push(this._addAggregateRow(app, agg.field, agg.func, agg.alias));
        }
        return results;
      }
    },
    // Update groupBy (would need implementation)
    // This would update the groupby fields
    markYamlAsChanged: function(app) {
      return this._yamlChanged = true;
    },
    syncVisualToYaml: function(app) {
      var config, yaml;
      if (!this._yamlChanged) {
        return;
      }
      // Gather current visual state
      config = this.gatherVisualConfig(app);
      yaml = this.configToYaml(config);
      app.el.dvYamlContent().value = yaml;
      return this._yamlChanged = false;
    },
    gatherVisualConfig: function(app) {
      var aggregates, columns, filter, filterFormula, selectedContainer;
      // Gather columns
      columns = [];
      selectedContainer = document.getElementById('dv-selected-fields');
      if (selectedContainer) {
        selectedContainer.querySelectorAll('.field-item').forEach(function(fieldItem) {
          return columns.push({
            name: fieldItem.dataset.fieldName,
            label: fieldItem.dataset.fieldName
          });
        });
      }
      // Gather filter
      filterFormula = app.el.dvFilterFormula().value.trim();
      filter = filterFormula ? {
        formula: filterFormula,
        language: 'moonscript'
      } : null;
      // Gather aggregates
      aggregates = [];
      app.el.dvAggregatesList().querySelectorAll('.dv-row').forEach(function(row) {
        var aAlias, aField, aFunc;
        aField = row.querySelector('.dv-agg-field').value.trim();
        aFunc = row.querySelector('.dv-agg-func').value;
        aAlias = row.querySelector('.dv-agg-alias').value.trim();
        if (aField) {
          return aggregates.push({
            field: aField,
            func: aFunc,
            alias: aAlias || `${aFunc.toLowerCase()}_${aField}`
          });
        }
      });
      return {
        columns: columns.length > 0 ? columns : null,
        filter: filter,
        groupBy: [], // Would need implementation
        aggregates: aggregates.length > 0 ? aggregates : null
      };
    }
  };

}).call(this);
