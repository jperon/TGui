(function() {
  // app_view_config_helpers.coffee — Data View configuration modal logic
  window.AppViewConfigHelpers = {
    _currentViewId: null,
    bindDataViewModal: function(app) {
      var tabs;
      app.el.dataViewModalCloseBtn().addEventListener('click', function() {
        return app.el.dataViewModal().classList.add('hidden');
      });
      app.el.dataViewSaveBtn().addEventListener('click', () => {
        return this.saveDataView(app);
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
          return ['columns', 'filter', 'group'].forEach(function(t) {
            return document.getElementById(`dv-tab-${t}`).classList.toggle('hidden', t !== target);
          });
        });
      });
      app.el.dvAddColBtn().addEventListener('click', () => {
        return this._addColumnRow(app);
      });
      return app.el.dvAddAggBtn().addEventListener('click', () => {
        return this._addAggregateRow(app);
      });
    },
    openDataViewConfigModal: function(app, view = null) {
      var agg, col, i, j, k, len, len1, len2, option, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, select, sp;
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
      app.el.dvColumnsList().innerHTML = '';
      app.el.dvAggregatesList().innerHTML = '';
      app.el.dvFilterFormula().value = (view != null ? (ref1 = view.config) != null ? (ref2 = ref1.filter) != null ? ref2.formula : void 0 : void 0 : void 0) || '';
      app.el.dvGroupBy().value = ((view != null ? (ref3 = view.config) != null ? ref3.groupBy : void 0 : void 0) || []).join(', ');
      if (view != null ? (ref4 = view.config) != null ? ref4.columns : void 0 : void 0) {
        ref5 = view.config.columns;
        for (j = 0, len1 = ref5.length; j < len1; j++) {
          col = ref5[j];
          this._addColumnRow(app, col.name, col.label);
        }
      } else if (!view) {
        this._addColumnRow(app); // Start with one empty col for new view
      }
      if (view != null ? (ref6 = view.config) != null ? ref6.aggregates : void 0 : void 0) {
        ref7 = view.config.aggregates;
        for (k = 0, len2 = ref7.length; k < len2; k++) {
          agg = ref7[k];
          this._addAggregateRow(app, agg.field, agg.func, agg.alias);
        }
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
      var aggregates, columns, config, filter, filterFormula, groupBy, groupByRaw, input, name, promise, sourceSpace;
      name = app.el.dvName().value.trim();
      sourceSpace = app.el.dvSource().value;
      if (!(name && sourceSpace)) {
        return tdbAlert("Le nom et l'espace source sont obligatoires", 'error');
      }
      // Gather columns
      columns = [];
      app.el.dvColumnsList().querySelectorAll('.dv-row').forEach(function(row) {
        var cLabel, cName;
        cName = row.querySelector('.dv-col-name').value.trim();
        cLabel = row.querySelector('.dv-col-label').value.trim();
        if (cName) {
          return columns.push({
            name: cName,
            label: cLabel || cName
          });
        }
      });
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
      groupByRaw = app.el.dvGroupBy().value.trim();
      groupBy = groupByRaw ? groupByRaw.split(',').map(function(s) {
        return s.trim();
      }).filter(function(s) {
        return s;
      }) : [];
      filterFormula = app.el.dvFilterFormula().value.trim();
      filter = filterFormula ? {
        formula: filterFormula,
        language: 'moonscript'
      } : null;
      config = {
        columns: columns.length > 0 ? columns : null,
        filter: filter,
        groupBy: groupBy.length > 0 ? groupBy : null,
        aggregates: aggregates.length > 0 ? aggregates : null
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
    }
  };

}).call(this);
