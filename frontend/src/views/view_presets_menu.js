(function() {
  // view_presets_menu.coffee — menu « Trier / Filtrer » avec préréglages nommés.

  // Module unique, réutilisé tel quel par la grille principale d'un espace et par
  // chaque widget dataView d'une page (DRY). Il affiche :
  //   - le tri courant (lu sur le DataView, qui le conserve après resetData) ;
  //   - les préréglages nommés de la portée (filtre + tri) ;
  //   - « Enregistrer sous… » (prompt du nom, puis saveViewPreset).

  // Portées : `space:<spaceId>` pour la grille principale,
  // `widget:<pageId>:<widgetId>` pour un widget de page.
  var DELETE_VIEW_PRESET_MUTATION, SAVE_VIEW_PRESET_MUTATION, VIEW_PRESETS_QUERY, applySortViaGrid, clearChildren, createEl, normalizeEntries, parseSort, serializeSort, sortEntriesFrom;

  VIEW_PRESETS_QUERY = `query ViewPresets($scope: String!, $spaceId: ID!) {
  viewPresets(scope: $scope, spaceId: $spaceId) {
    id scope spaceId name filter sort createdAt updatedAt
  }
}`;

  SAVE_VIEW_PRESET_MUTATION = `mutation SaveViewPreset($scope: String!, $spaceId: ID!, $name: String!, $filter: String, $sort: String) {
  saveViewPreset(scope: $scope, spaceId: $spaceId, name: $name, filter: $filter, sort: $sort) {
    id scope spaceId name filter sort createdAt updatedAt
  }
}`;

  DELETE_VIEW_PRESET_MUTATION = `mutation DeleteViewPreset($id: ID!) {
  deleteViewPreset(id: $id)
}`;

  createEl = function(tag, className, text) {
    var el;
    el = document.createElement(tag);
    if (className) {
      el.className = className;
    }
    if (text != null) {
      el.textContent = text;
    }
    return el;
  };

  clearChildren = function(el) {
    var results;
    results = [];
    while (el.children && el.children.length > 0) {
      results.push(el.removeChild(el.children[0]));
    }
    return results;
  };

  // Un tri est une liste de { column, ascending }. On ignore la colonne technique
  // `sortKey` que Toast UI Grid utilise pour représenter « aucun tri ».
  normalizeEntries = function(entries) {
    var entry, j, len, name, out, ref;
    out = [];
    if (!Array.isArray(entries)) {
      return out;
    }
    for (j = 0, len = entries.length; j < len; j++) {
      entry = entries[j];
      if (!entry) {
        continue;
      }
      name = (ref = entry.column) != null ? ref : entry.columnName;
      if (!name) {
        continue;
      }
      if (name === 'sortKey') {
        continue;
      }
      out.push({
        column: String(name),
        ascending: !!entry.ascending
      });
    }
    return out;
  };

  parseSort = function(jsonText) {
    var decoded, e;
    if (jsonText === void 0 || jsonText === null || jsonText === '') {
      return [];
    }
    decoded = null;
    try {
      decoded = typeof jsonText === 'string' ? JSON.parse(jsonText) : jsonText;
    } catch (error) {
      e = error;
      return [];
    }
    return normalizeEntries(decoded);
  };

  serializeSort = function(entries) {
    return JSON.stringify(normalizeEntries(entries));
  };

  // Lit le tri courant. On privilégie le cache du DataView (qui survit aux
  // resetData), et on retombe sur l'état brut de la grille pour un DataView
  // minimal (tests, anciens objets).
  sortEntriesFrom = function(dv) {
    var e, grid, state;
    if (!dv) {
      return [];
    }
    if (typeof dv.getSortEntries === 'function') {
      return normalizeEntries(dv.getSortEntries());
    }
    grid = dv._grid;
    if (!(grid && typeof grid.getSortState === 'function')) {
      return [];
    }
    state = null;
    try {
      state = grid.getSortState();
    } catch (error) {
      e = error;
      state = null;
    }
    return normalizeEntries(state != null ? state.columns : void 0);
  };

  // Repli quand le DataView n'expose pas applySortEntries (objet factice).
  applySortViaGrid = function(dv, entries) {
    var entry, grid, i, j, len, ref, results;
    grid = dv != null ? dv._grid : void 0;
    if (!grid) {
      return;
    }
    if (typeof grid.unsort === "function") {
      grid.unsort();
    }
    ref = normalizeEntries(entries);
    results = [];
    for (i = j = 0, len = ref.length; j < len; i = ++j) {
      entry = ref[i];
      results.push(typeof grid.sort === "function" ? grid.sort(entry.column, entry.ascending, i > 0) : void 0);
    }
    return results;
  };

  window.ViewPresetsMenu = {
    sortEntriesFrom: sortEntriesFrom,
    normalizeEntries: normalizeEntries,
    parseSort: parseSort,
    serializeSort: serializeSort,
    attach: function(wrapEl, opts = {}) {
      var actions, api, applyPreset, button, clearActive, clearError, close, dataView, deletePreset, destroy, ensureDataViewBinding, errorEl, isOpen, loadPresets, matchesActive, menu, onDocumentClick, onDocumentKey, onFilterInput, open, positionMenu, presetList, presetSection, ref, ref1, removeSortColumn, renderPresets, renderSort, saveBtn, saveCurrent, showError, sortList, sortSection, state, syncActive, toggle, updateButton;
      if (!wrapEl) {
        return null;
      }
      if ((ref = wrapEl._viewPresetsMenu) != null) {
        if (typeof ref.destroy === "function") {
          ref.destroy();
        }
      }
      wrapEl.classList.add('view-presets-host');
      button = createEl('button', 'toolbar-btn view-presets-btn no-drag', 'Trier / Filtrer');
      button.type = 'button';
      button.title = 'Trier / Filtrer — préréglages de vue';
      menu = createEl('div', 'view-presets-menu no-drag hidden');
      errorEl = createEl('div', 'view-presets-error hidden');
      sortSection = createEl('div', 'view-presets-section');
      sortSection.appendChild(createEl('div', 'view-presets-section-title', 'Tri courant'));
      sortList = createEl('div', 'view-presets-sort-list');
      sortSection.appendChild(sortList);
      presetSection = createEl('div', 'view-presets-section');
      presetSection.appendChild(createEl('div', 'view-presets-section-title', 'Préréglages'));
      presetList = createEl('div', 'view-presets-preset-list');
      presetSection.appendChild(presetList);
      actions = createEl('div', 'view-presets-actions');
      saveBtn = createEl('button', 'view-presets-save', 'Enregistrer sous…');
      saveBtn.type = 'button';
      actions.appendChild(saveBtn);
      menu.appendChild(errorEl);
      menu.appendChild(sortSection);
      menu.appendChild(presetSection);
      menu.appendChild(actions);
      wrapEl.appendChild(button);
      wrapEl.appendChild(menu);
      state = {
        presets: [],
        active: null,
        loaded: false
      };
      dataView = function() {
        return typeof opts.getDataView === "function" ? opts.getDataView() : void 0;
      };
      isOpen = function() {
        return !menu.classList.contains('hidden');
      };
      updateButton = function() {
        var ref1;
        if ((ref1 = state.active) != null ? ref1.name : void 0) {
          button.textContent = `Trier / Filtrer · ${state.active.name}`;
          return button.classList.add('active');
        } else {
          button.textContent = 'Trier / Filtrer';
          return button.classList.remove('active');
        }
      };
      showError = function(message) {
        errorEl.textContent = message;
        return errorEl.classList.remove('hidden');
      };
      clearError = function() {
        return errorEl.classList.add('hidden');
      };
      renderSort = function() {
        var entries, entry, j, label, len, removeBtn, results, row;
        clearChildren(sortList);
        entries = sortEntriesFrom(dataView());
        if (entries.length === 0) {
          sortList.appendChild(createEl('div', 'view-presets-empty', 'Aucun tri (cliquez un en-tête de colonne)'));
          return;
        }
        results = [];
        for (j = 0, len = entries.length; j < len; j++) {
          entry = entries[j];
          row = createEl('div', 'view-presets-sort-row');
          row.dataset.column = entry.column;
          label = createEl('span', 'view-presets-sort-label', `${entry.column} ${entry.ascending ? '↑' : '↓'}`);
          removeBtn = createEl('button', 'view-presets-remove', '✕');
          removeBtn.type = 'button';
          removeBtn.title = 'Retirer ce critère de tri';
          (function(entry) {
            return removeBtn.addEventListener('click', function(ev) {
              if (ev != null) {
                if (typeof ev.stopPropagation === "function") {
                  ev.stopPropagation();
                }
              }
              return removeSortColumn(entry.column);
            });
          })(entry);
          row.appendChild(label);
          row.appendChild(removeBtn);
          results.push(sortList.appendChild(row));
        }
        return results;
      };
      renderPresets = function() {
        var delBtn, j, len, preset, ref1, ref2, results, row;
        clearChildren(presetList);
        if (state.presets.length === 0) {
          presetList.appendChild(createEl('div', 'view-presets-empty', 'Aucun préréglage'));
          return;
        }
        ref1 = state.presets;
        results = [];
        for (j = 0, len = ref1.length; j < len; j++) {
          preset = ref1[j];
          row = createEl('div', 'view-presets-preset');
          row.dataset.id = preset.id;
          row.classList.toggle('active', ((ref2 = state.active) != null ? ref2.id : void 0) === preset.id);
          row.appendChild(createEl('span', 'view-presets-preset-name', preset.name));
          delBtn = createEl('button', 'view-presets-preset-delete', '✕');
          delBtn.type = 'button';
          delBtn.title = `Supprimer le préréglage « ${preset.name} »`;
          (function(preset, delBtn) {
            row.addEventListener('click', function() {
              return applyPreset(preset);
            });
            return delBtn.addEventListener('click', function(ev) {
              if (ev != null) {
                if (typeof ev.stopPropagation === "function") {
                  ev.stopPropagation();
                }
              }
              return deletePreset(preset);
            });
          })(preset, delBtn);
          row.appendChild(delBtn);
          results.push(presetList.appendChild(row));
        }
        return results;
      };
      matchesActive = function() {
        var currentFilter, dv, ref1, ref2, ref3;
        if (!state.active) {
          return false;
        }
        dv = dataView();
        if (!dv) {
          return false;
        }
        currentFilter = ((ref1 = (ref2 = opts.filterInput) != null ? ref2.value : void 0) != null ? ref1 : '').trim();
        if (currentFilter !== ((ref3 = state.active.filter) != null ? ref3 : '').trim()) {
          return false;
        }
        return serializeSort(sortEntriesFrom(dv)) === state.active.sort;
      };
      clearActive = function() {
        if (!state.active) {
          return;
        }
        state.active = null;
        updateButton();
        return renderPresets();
      };
      syncActive = function() {
        if (!state.active) {
          return;
        }
        if (!matchesActive()) {
          return clearActive();
        }
      };
      loadPresets = function() {
        var ref1;
        if (!((ref1 = window.GQL) != null ? ref1.query : void 0)) {
          showError('Client GraphQL indisponible');
          return Promise.resolve(state.presets);
        }
        if (!(opts.scope && opts.spaceId)) {
          showError('Portée du préréglage inconnue');
          return Promise.resolve(state.presets);
        }
        return window.GQL.query(VIEW_PRESETS_QUERY, {
          scope: opts.scope,
          spaceId: opts.spaceId
        }).then(function(data) {
          state.presets = ((data != null ? data.viewPresets : void 0) || []).slice();
          state.loaded = true;
          clearError();
          renderPresets();
          return state.presets;
        }).catch(function(err) {
          showError((err != null ? err.message : void 0) || String(err));
          return state.presets;
        });
      };
      applyPreset = function(preset) {
        var dv, entries, filter, ref1;
        if (!preset) {
          return;
        }
        dv = dataView();
        if (!dv) {
          return;
        }
        entries = parseSort(preset.sort);
        filter = (ref1 = preset.filter) != null ? ref1 : '';
        state.active = {
          id: preset.id,
          name: preset.name,
          filter: filter,
          sort: serializeSort(entries)
        };
        updateButton();
        if (opts.filterInput) {
          opts.filterInput.value = filter;
          opts.filterInput.classList.toggle('active', filter.trim() !== '');
        }
        // Le tri est posé AVANT le rechargement du filtre : _applyData le
        // réapplique après resetData, sinon Toast UI Grid le perdrait.
        if (typeof dv.applySortEntries === 'function') {
          dv.applySortEntries(entries);
        } else {
          applySortViaGrid(dv, entries);
        }
        if (typeof dv.setFormulaFilter === "function") {
          dv.setFormulaFilter(filter);
        }
        clearError();
        renderSort();
        renderPresets();
        return close();
      };
      removeSortColumn = function(column) {
        var dv, e, entries;
        dv = dataView();
        if (!dv) {
          return;
        }
        entries = (function() {
          var j, len, ref1, results;
          ref1 = sortEntriesFrom(dv);
          results = [];
          for (j = 0, len = ref1.length; j < len; j++) {
            e = ref1[j];
            if (e.column !== column) {
              results.push(e);
            }
          }
          return results;
        })();
        if (typeof dv.applySortEntries === 'function') {
          dv.applySortEntries(entries);
        } else {
          applySortViaGrid(dv, entries);
        }
        clearActive();
        return renderSort();
      };
      saveCurrent = function() {
        var dv, entered, filter, name, ref1, ref2, ref3, ref4, sort;
        dv = dataView();
        if (!dv) {
          showError('Aucune grille active');
          return Promise.resolve(null);
        }
        if (!((ref1 = window.GQL) != null ? ref1.mutate : void 0)) {
          showError('Client GraphQL indisponible');
          return Promise.resolve(null);
        }
        if (!(opts.scope && opts.spaceId)) {
          showError('Portée du préréglage inconnue');
          return Promise.resolve(null);
        }
        entered = typeof window.prompt === "function" ? window.prompt('Nom du préréglage', ((ref2 = state.active) != null ? ref2.name : void 0) || '') : void 0;
        if (!(entered != null ? entered.trim() : void 0)) {
          return Promise.resolve(null);
        }
        name = entered.trim();
        filter = ((ref3 = (ref4 = opts.filterInput) != null ? ref4.value : void 0) != null ? ref3 : '').trim();
        sort = serializeSort(sortEntriesFrom(dv));
        return window.GQL.mutate(SAVE_VIEW_PRESET_MUTATION, {
          scope: opts.scope,
          spaceId: opts.spaceId,
          name: name,
          filter: filter,
          sort: sort
        }).then(function(data) {
          var saved;
          saved = data != null ? data.saveViewPreset : void 0;
          state.active = {
            id: saved != null ? saved.id : void 0,
            name: (saved != null ? saved.name : void 0) || name,
            filter: filter,
            sort: sort
          };
          updateButton();
          clearError();
          return loadPresets();
        }).catch(function(err) {
          return showError(`Erreur d'enregistrement du préréglage : ${(err != null ? err.message : void 0) || err}`);
        });
      };
      deletePreset = function(preset) {
        var ref1;
        if (!preset) {
          return Promise.resolve(false);
        }
        if (!(typeof window.confirm === "function" ? window.confirm(`Supprimer le préréglage « ${preset.name} » ?`) : void 0)) {
          return Promise.resolve(false);
        }
        if (!((ref1 = window.GQL) != null ? ref1.mutate : void 0)) {
          showError('Client GraphQL indisponible');
          return Promise.resolve(false);
        }
        return window.GQL.mutate(DELETE_VIEW_PRESET_MUTATION, {
          id: preset.id
        }).then(function() {
          var p, ref2;
          state.presets = (function() {
            var j, len, ref2, results;
            ref2 = state.presets;
            results = [];
            for (j = 0, len = ref2.length; j < len; j++) {
              p = ref2[j];
              if (p.id !== preset.id) {
                results.push(p);
              }
            }
            return results;
          })();
          if (((ref2 = state.active) != null ? ref2.id : void 0) === preset.id) {
            state.active = null;
            updateButton();
          }
          clearError();
          renderPresets();
          return true;
        }).catch(function(err) {
          showError(`Erreur de suppression du préréglage : ${(err != null ? err.message : void 0) || err}`);
          return false;
        });
      };
      positionMenu = function() {
        var rect, ref1, ref2;
        if (!wrapEl.getBoundingClientRect) {
          return;
        }
        rect = wrapEl.getBoundingClientRect();
        menu.style.position = 'fixed';
        menu.style.left = `${(ref1 = rect != null ? rect.left : void 0) != null ? ref1 : 0}px`;
        return menu.style.top = `${((ref2 = rect != null ? rect.bottom : void 0) != null ? ref2 : 0) + 4}px`;
      };
      close = function() {
        menu.classList.add('hidden');
        return clearError();
      };
      open = function() {
        syncActive();
        renderSort();
        renderPresets();
        positionMenu();
        menu.classList.remove('hidden');
        return loadPresets();
      };
      toggle = function() {
        if (isOpen()) {
          return close();
        } else {
          return open();
        }
      };
      onDocumentClick = function(ev) {
        var target;
        if (!isOpen()) {
          return;
        }
        target = ev != null ? ev.target : void 0;
        if (target && (typeof wrapEl.contains === "function" ? wrapEl.contains(target) : void 0)) {
          return;
        }
        return close();
      };
      onDocumentKey = function(ev) {
        if ((ev != null ? ev.key : void 0) === 'Escape' && isOpen()) {
          return close();
        }
      };
      ensureDataViewBinding = function() {
        var dv;
        dv = dataView();
        if (!dv) {
          return;
        }
        if (dv._viewPresetsMenu === api) {
          return;
        }
        dv._viewPresetsMenu = api;
        return dv._onSortChanged = function() {
          syncActive();
          if (isOpen()) {
            renderSort();
            return renderPresets();
          }
        };
      };
      onFilterInput = function() {
        return clearActive();
      };
      destroy = function() {
        var dv, ref1, ref2, ref3;
        if (typeof document.removeEventListener === "function") {
          document.removeEventListener('click', onDocumentClick, true);
        }
        if (typeof document.removeEventListener === "function") {
          document.removeEventListener('keydown', onDocumentKey);
        }
        // La grille principale réattache le menu au même input à chaque changement
        // d'espace : sans ce retrait, les écouteurs s'accumuleraient.
        if ((ref1 = opts.filterInput) != null) {
          if (typeof ref1.removeEventListener === "function") {
            ref1.removeEventListener('input', onFilterInput);
          }
        }
        dv = dataView();
        if (dv && dv._viewPresetsMenu === api) {
          dv._viewPresetsMenu = null;
          dv._onSortChanged = null;
        }
        if ((ref2 = button.parentNode) != null) {
          if (typeof ref2.removeChild === "function") {
            ref2.removeChild(button);
          }
        }
        return (ref3 = menu.parentNode) != null ? typeof ref3.removeChild === "function" ? ref3.removeChild(menu) : void 0 : void 0;
      };
      api = {
        button: button,
        menu: menu,
        elements: {
          sortList: sortList,
          presetList: presetList,
          saveBtn: saveBtn,
          errorEl: errorEl
        },
        isOpen: isOpen,
        open: open,
        close: close,
        toggle: toggle,
        refresh: open,
        applyPreset: applyPreset,
        saveCurrent: saveCurrent,
        deletePreset: deletePreset,
        clearActive: clearActive,
        destroy: destroy
      };
      button.addEventListener('click', function(ev) {
        if (ev != null) {
          if (typeof ev.stopPropagation === "function") {
            ev.stopPropagation();
          }
        }
        return toggle();
      });
      saveBtn.addEventListener('click', function(ev) {
        if (ev != null) {
          if (typeof ev.stopPropagation === "function") {
            ev.stopPropagation();
          }
        }
        return saveCurrent();
      });
      if ((ref1 = opts.filterInput) != null) {
        if (typeof ref1.addEventListener === "function") {
          ref1.addEventListener('input', onFilterInput);
        }
      }
      wrapEl._viewPresetsMenu = api;
      ensureDataViewBinding();
      if (typeof document.addEventListener === "function") {
        document.addEventListener('click', onDocumentClick, true);
      }
      if (typeof document.addEventListener === "function") {
        document.addEventListener('keydown', onDocumentKey);
      }
      updateButton();
      return api;
    }
  };

}).call(this);
