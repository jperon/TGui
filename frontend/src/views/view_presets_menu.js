(function() {
  // view_presets_menu.coffee — menu « Trier / Filtrer » avec préréglages nommés.

  // Module unique, réutilisé tel quel par la grille principale d'un espace et par
  // chaque widget dataView d'une page (DRY). Il affiche :
  //   - le tri courant (lu sur le DataView, qui le conserve après resetData) ;
  //   - les préréglages nommés de la portée (filtre + tri) ;
  //   - « Enregistrer sous… » (prompt du nom, puis saveViewPreset).

  // Portées : `space:<spaceId>` pour la grille principale,
  // `widget:<pageId>:<widgetId>` pour un widget de page.
  var DELETE_VIEW_PRESET_MUTATION, SAVE_VIEW_PRESET_MUTATION, VIEW_PRESETS_QUERY, applySortViaGrid, clearChildren, columnNamesFrom, createEl, moveEntry, normalizeEntries, parseSort, serializeSort, sortEntriesFrom;

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

  // Réordonne une liste de critères par glisser-déposer : `from` et `to` sont des
  // index de la liste finale. Fonction pure (l'entrée n'est pas mutée), isolée du
  // DOM pour être testable seule. Un déplacement identité ou hors bornes renvoie
  // une copie inchangée.
  moveEntry = function(entries, from, to) {
    var entry, j, len, list, moved;
    list = [];
    if (!Array.isArray(entries)) {
      return list;
    }
    for (j = 0, len = entries.length; j < len; j++) {
      entry = entries[j];
      list.push(entry);
    }
    if (from === to) {
      return list;
    }
    if (from < 0 || from >= list.length) {
      return list;
    }
    if (to < 0 || to >= list.length) {
      return list;
    }
    moved = list.splice(from, 1);
    list.splice(to, 0, moved[0]);
    return list;
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

  // Colonnes proposées par « + Ajouter un critère » : les champs de l'espace,
  // dans l'ordre de la grille. Un champ masqué n'a pas d'en-tête, donc pas de tri.
  columnNamesFrom = function(dv) {
    var col, columns, f, fields, j, k, len, len1, out, ref, ref1;
    out = [];
    fields = dv != null ? (ref = dv.space) != null ? ref.fields : void 0 : void 0;
    if (Array.isArray(fields) && fields.length > 0) {
      for (j = 0, len = fields.length; j < len; j++) {
        f = fields[j];
        if (!((f != null ? f.name : void 0) && !f.hidden)) {
          continue;
        }
        out.push(f.name);
      }
      return out;
    }
    columns = (dv != null ? (ref1 = dv._grid) != null ? typeof ref1.getColumns === "function" ? ref1.getColumns() : void 0 : void 0 : void 0) || [];
    for (k = 0, len1 = columns.length; k < len1; k++) {
      col = columns[k];
      if (!((col != null ? col.name : void 0) && !col.hidden)) {
        continue;
      }
      out.push(col.name);
    }
    return out;
  };

  window.ViewPresetsMenu = {
    sortEntriesFrom: sortEntriesFrom,
    normalizeEntries: normalizeEntries,
    moveEntry: moveEntry,
    parseSort: parseSort,
    serializeSort: serializeSort,
    columnNamesFrom: columnNamesFrom,
    attach: function(wrapEl, opts = {}) {
      var actions, addBtn, addColumnSelect, addDirectionSelect, addRow, addSortCriterion, api, applyEntries, applyPreset, ascOpt, buildSortRow, button, clearActive, clearDropMarks, clearError, close, dataView, deletePreset, descOpt, destroy, dragState, dropIndex, endDrag, ensureDataViewBinding, errorEl, isOpen, loadPresets, makeSortButton, matchesActive, menu, mutateSort, onDocumentClick, onDocumentKey, onFilterInput, onRowDragEnd, onRowDragOver, onRowDragStart, onRowDrop, open, positionMenu, presetList, presetSection, ref, ref1, removeSortColumn, renderAddSortRow, renderPresets, renderSort, reorderSortEntry, saveBtn, saveCurrent, showError, sortList, sortSection, state, suppressCloseUntil, syncActive, toggle, toggleSortDirection, updateButton;
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
      // « + Ajouter un critère » : colonne non encore triée + sens, ajouté en fin
      // de liste (priorité la plus faible).
      addRow = createEl('div', 'view-presets-add');
      addColumnSelect = document.createElement('select');
      addColumnSelect.className = 'view-presets-add-column';
      addColumnSelect.title = 'Colonne à ajouter au tri';
      addDirectionSelect = document.createElement('select');
      addDirectionSelect.className = 'view-presets-add-direction';
      addDirectionSelect.title = 'Sens du tri';
      ascOpt = createEl('option', null, '↑ croissant');
      ascOpt.value = 'asc';
      addDirectionSelect.appendChild(ascOpt);
      descOpt = createEl('option', null, '↓ décroissant');
      descOpt.value = 'desc';
      addDirectionSelect.appendChild(descOpt);
      addDirectionSelect.value = 'asc';
      addBtn = createEl('button', 'view-presets-add-btn', '+ Ajouter un critère');
      addBtn.type = 'button';
      addBtn.title = 'Ajouter un critère de tri en fin de liste';
      addRow.appendChild(addColumnSelect);
      addRow.appendChild(addDirectionSelect);
      addRow.appendChild(addBtn);
      sortSection.appendChild(addRow);
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
      // Applique une liste de critères au DataView (cache persistant) ou, à
      // défaut, à la grille. Retourne les critères normalisés.
      applyEntries = function(entries) {
        var clean, dv;
        dv = dataView();
        if (!dv) {
          return [];
        }
        clean = normalizeEntries(entries);
        if (typeof dv.applySortEntries === 'function') {
          dv.applySortEntries(clean);
        } else {
          applySortViaGrid(dv, clean);
        }
        return clean;
      };
      // Une seule voie d'écriture : transformer la liste courante, l'appliquer,
      // puis rafraîchir le menu et l'état « préréglage actif » (matchesActive).
      mutateSort = function(fn) {
        var dv, entries;
        dv = dataView();
        if (!dv) {
          return [];
        }
        entries = fn(sortEntriesFrom(dv));
        entries = applyEntries(entries);
        syncActive();
        renderSort();
        return entries;
      };
      toggleSortDirection = function(column) {
        return mutateSort(function(entries) {
          var entry, j, len;
          for (j = 0, len = entries.length; j < len; j++) {
            entry = entries[j];
            if (entry.column === column) {
              entry.ascending = !entry.ascending;
            }
          }
          return entries;
        });
      };
      // Réordonnancement : la source est l'index de départ, la cible l'index
      // d'arrivée dans la liste finale (cf. moveEntry).
      reorderSortEntry = function(from, to) {
        return mutateSort(function(entries) {
          return moveEntry(entries, from, to);
        });
      };
      addSortCriterion = function() {
        var ascending, name;
        if (addColumnSelect.disabled) {
          return;
        }
        name = addColumnSelect.value;
        if (!name) {
          return;
        }
        ascending = addDirectionSelect.value !== 'desc';
        return mutateSort(function(entries) {
          if (entries.some(function(e) {
            return e.column === name;
          })) {
            return entries;
          }
          entries.push({
            column: name,
            ascending: ascending
          });
          return entries;
        });
      };
      makeSortButton = function(className, text, title, action, handler) {
        var btn;
        btn = createEl('button', className, text);
        btn.type = 'button';
        btn.title = title;
        btn.setAttribute('data-action', action);
        btn.addEventListener('click', function(ev) {
          if (ev != null) {
            if (typeof ev.stopPropagation === "function") {
              ev.stopPropagation();
            }
          }
          return handler();
        });
        return btn;
      };
      // ── Glisser-déposer natif (HTML5) des critères ──────────────────────────
      // Chaque ligne est `draggable` ; la position de dépôt (avant/après la ligne
      // survolée) suit la moitié haute/basse du curseur et se voit via une barre
      // d'insertion (classes drop-before / drop-after). Aucun glisser ne doit
      // fermer le menu : le clic de fermeture global est neutralisé pendant le
      // glissement, et juste après le dépôt.
      dragState = {
        from: null,
        to: null,
        after: false
      };
      suppressCloseUntil = 0;
      clearDropMarks = function() {
        var el, j, len, ref1, results;
        ref1 = sortList.children || [];
        results = [];
        for (j = 0, len = ref1.length; j < len; j++) {
          el = ref1[j];
          el.classList.remove('drop-before');
          results.push(el.classList.remove('drop-after'));
        }
        return results;
      };
      endDrag = function() {
        var el, j, len, ref1;
        dragState.from = null;
        dragState.to = null;
        dragState.after = false;
        ref1 = sortList.children || [];
        for (j = 0, len = ref1.length; j < len; j++) {
          el = ref1[j];
          el.classList.remove('dragging');
        }
        return clearDropMarks();
      };
      onRowDragStart = function(row, index, ev) {
        var dt;
        dragState.from = index;
        dragState.to = index;
        dragState.after = false;
        row.classList.add('dragging');
        dt = ev != null ? ev.dataTransfer : void 0;
        if (dt) {
          dt.effectAllowed = 'move';
          if (typeof dt.setData === "function") {
            dt.setData('text/plain', `${index}`);
          }
        }
        return ev != null ? typeof ev.stopPropagation === "function" ? ev.stopPropagation() : void 0 : void 0;
      };
      onRowDragOver = function(row, index, ev) {
        var after, dt, rect, y;
        if (dragState.from == null) {
          return;
        }
        if (ev != null) {
          if (typeof ev.preventDefault === "function") {
            ev.preventDefault();
          }
        }
        dt = ev != null ? ev.dataTransfer : void 0;
        if (dt) {
          dt.dropEffect = 'move';
        }
        after = false;
        rect = typeof row.getBoundingClientRect === "function" ? row.getBoundingClientRect() : void 0;
        y = ev != null ? ev.clientY : void 0;
        if ((rect != null) && (y != null) && rect.height) {
          after = y > rect.top + rect.height / 2;
        }
        dragState.to = index;
        dragState.after = after;
        clearDropMarks();
        return row.classList.add(after ? 'drop-after' : 'drop-before');
      };
      // Index final du dépôt : insérer « après la ligne i » revient à i+1 dans la
      // liste d'origine, puis à i quand la ligne déplacée vient d'avant.
      dropIndex = function() {
        var insertAt;
        if (!((dragState.from != null) && (dragState.to != null))) {
          return null;
        }
        insertAt = dragState.after ? dragState.to + 1 : dragState.to;
        if (insertAt > dragState.from) {
          return insertAt - 1;
        } else {
          return insertAt;
        }
      };
      onRowDrop = function(row, index, ev) {
        var from, to;
        if (dragState.from == null) {
          return;
        }
        if (ev != null) {
          if (typeof ev.preventDefault === "function") {
            ev.preventDefault();
          }
        }
        if (ev != null) {
          if (typeof ev.stopPropagation === "function") {
            ev.stopPropagation();
          }
        }
        from = dragState.from;
        to = dropIndex();
        endDrag();
        suppressCloseUntil = Date.now() + 400;
        if (!((to != null) && to !== from)) {
          return;
        }
        return reorderSortEntry(from, to);
      };
      onRowDragEnd = function(row, ev) {
        endDrag();
        return suppressCloseUntil = Date.now() + 400;
      };
      buildSortRow = function(entry, index) {
        var dirText, dirTitle, handle, row;
        row = createEl('div', 'view-presets-sort-row');
        row.dataset.column = entry.column;
        row.dataset.rank = `${index + 1}`;
        row.draggable = true;
        handle = createEl('span', 'view-presets-sort-handle', '⠿');
        handle.title = 'Glisser pour changer la priorité du critère';
        handle.setAttribute('aria-hidden', 'true');
        row.appendChild(handle);
        row.appendChild(createEl('span', 'view-presets-sort-rank', `${index + 1}.`));
        row.appendChild(createEl('span', 'view-presets-sort-label', entry.column));
        dirText = entry.ascending ? '↑' : '↓';
        dirTitle = entry.ascending ? 'Croissant — cliquer pour trier en décroissant' : 'Décroissant — cliquer pour trier en croissant';
        row.appendChild(makeSortButton('view-presets-sort-dir', dirText, dirTitle, 'dir', function() {
          return toggleSortDirection(entry.column);
        }));
        row.appendChild(makeSortButton('view-presets-remove', '✕', 'Retirer ce critère de tri', 'remove', function() {
          return removeSortColumn(entry.column);
        }));
        row.addEventListener('dragstart', function(ev) {
          return onRowDragStart(row, index, ev);
        });
        row.addEventListener('dragover', function(ev) {
          return onRowDragOver(row, index, ev);
        });
        row.addEventListener('drop', function(ev) {
          return onRowDrop(row, index, ev);
        });
        row.addEventListener('dragend', function(ev) {
          return onRowDragEnd(row, ev);
        });
        return row;
      };
      // Options de « + Ajouter un critère » : uniquement les colonnes non triées.
      renderAddSortRow = function(entries) {
        var available, entry, j, k, l, len, len1, len2, name, names, opt, used;
        clearChildren(addColumnSelect);
        used = {};
        for (j = 0, len = entries.length; j < len; j++) {
          entry = entries[j];
          used[entry.column] = true;
        }
        names = columnNamesFrom(dataView());
        available = [];
        for (k = 0, len1 = names.length; k < len1; k++) {
          name = names[k];
          if (used[name]) {
            continue;
          }
          available.push(name);
        }
        if (available.length === 0) {
          addColumnSelect.appendChild(createEl('option', null, 'Toutes les colonnes sont triées'));
          addColumnSelect.disabled = true;
          addBtn.disabled = true;
          return;
        }
        addColumnSelect.disabled = false;
        addBtn.disabled = false;
        for (l = 0, len2 = available.length; l < len2; l++) {
          name = available[l];
          opt = createEl('option', null, name);
          opt.value = name;
          addColumnSelect.appendChild(opt);
        }
        return addColumnSelect.value = available[0];
      };
      renderSort = function() {
        var entries, entry, index, j, len;
        clearChildren(sortList);
        entries = sortEntriesFrom(dataView());
        if (entries.length === 0) {
          sortList.appendChild(createEl('div', 'view-presets-empty', "Aucun tri — ajoutez un critère ci-dessous, ou cliquez un en-tête de colonne (Maj+clic ou Ctrl/Cmd+clic pour en ajouter un autre)"));
        }
        for (index = j = 0, len = entries.length; j < len; index = ++j) {
          entry = entries[index];
          sortList.appendChild(buildSortRow(entry, index));
        }
        return renderAddSortRow(entries);
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
        applyEntries(entries);
        if (typeof dv.setFormulaFilter === "function") {
          dv.setFormulaFilter(filter);
        }
        clearError();
        renderSort();
        renderPresets();
        return close();
      };
      removeSortColumn = function(column) {
        return mutateSort(function(entries) {
          var e, j, len, results;
          results = [];
          for (j = 0, len = entries.length; j < len; j++) {
            e = entries[j];
            if (e.column !== column) {
              results.push(e);
            }
          }
          return results;
        });
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
        // Ne jamais fermer le menu pendant un glissement de critère, ni dans les
        // 400 ms qui suivent le dépôt (un navigateur peut émettre un clic tardif
        // sur le fond après un glisser-déposer).
        if (dragState.from != null) {
          return;
        }
        if (Date.now() < suppressCloseUntil) {
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
          addRow: addRow,
          addColumnSelect: addColumnSelect,
          addDirectionSelect: addDirectionSelect,
          addBtn: addBtn,
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
      addBtn.addEventListener('click', function(ev) {
        if (ev != null) {
          if (typeof ev.stopPropagation === "function") {
            ev.stopPropagation();
          }
        }
        return addSortCriterion();
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
