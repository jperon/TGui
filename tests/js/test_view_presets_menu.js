(function() {
  // tests/js/test_view_presets_menu.coffee
  // Menu « Trier / Filtrer » : sérialisation du tri, application d'un préréglage
  // (filtre + tri), « Enregistrer sous », suppression, mise en évidence.
  var P_FILTERED, P_SORTED, VPM, assert, confirmAnswers, deepEq, describe, dragRow, eq, it, makeDv, makeHarness, mutationCalls, promptAnswers, queries, serverPresets, sortButton, sortRow, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  queries = [];

  mutationCalls = [];

  serverPresets = [];

  promptAnswers = [];

  confirmAnswers = [];

  global.window.prompt = function() {
    var ref;
    return (ref = promptAnswers.shift()) != null ? ref : null;
  };

  global.window.confirm = function() {
    var ref;
    return (ref = confirmAnswers.shift()) != null ? ref : false;
  };

  global.window.GQL = {
    query: function(q, vars) {
      var p;
      queries.push({q, vars});
      return Promise.resolve({
        viewPresets: (function() {
          var i, len, results;
          results = [];
          for (i = 0, len = serverPresets.length; i < len; i++) {
            p = serverPresets[i];
            results.push(Object.assign({}, p));
          }
          return results;
        })()
      });
    },
    mutate: function(m, vars) {
      var saved;
      mutationCalls.push({m, vars});
      if (/deleteViewPreset/.test(m)) {
        return Promise.resolve({
          deleteViewPreset: true
        });
      } else {
        saved = Object.assign({
          id: 'saved-id',
          scope: vars.scope,
          spaceId: vars.spaceId,
          name: vars.name,
          filter: vars.filter,
          sort: vars.sort
        }, {});
        return Promise.resolve({
          saveViewPreset: saved
        });
      }
    }
  };

  require('../../frontend/src/views/view_presets_menu');

  VPM = global.window.ViewPresetsMenu;

  P_SORTED = {
    id: 'p2',
    scope: 'widget:page1:w1',
    spaceId: 's1',
    name: 'Récents',
    filter: '',
    sort: '[{"column":"date","ascending":false}]'
  };

  P_FILTERED = {
    id: 'p1',
    scope: 'widget:page1:w1',
    spaceId: 's1',
    name: 'Actifs',
    filter: 'self.actif',
    sort: '[]'
  };

  makeDv = function(entries = [], fieldNames = ['date', 'titre', 'note', 'nom', 'age']) {
    var dv, e, n, state;
    state = {
      sort: (function() {
        var i, len, results;
        results = [];
        for (i = 0, len = entries.length; i < len; i++) {
          e = entries[i];
          results.push(Object.assign({}, e));
        }
        return results;
      })(),
      filters: [],
      applied: []
    };
    dv = {
      _state: state,
      space: {
        id: 's1',
        name: 'test',
        fields: (function() {
          var i, len, results;
          results = [];
          for (i = 0, len = fieldNames.length; i < len; i++) {
            n = fieldNames[i];
            results.push({
              name: n,
              fieldType: 'Str'
            });
          }
          return results;
        })()
      },
      _grid: {
        getSortState: function() {
          return {
            columns: [
              {
                columnName: 'sortKey',
                ascending: true
              }
            ].concat((function() {
              var i, len, ref, results;
              ref = state.sort;
              results = [];
              for (i = 0, len = ref.length; i < len; i++) {
                e = ref[i];
                results.push({
                  columnName: e.column,
                  ascending: e.ascending
                });
              }
              return results;
            })())
          };
        },
        sort: function() {
          return null;
        },
        unsort: function() {
          return null;
        }
      },
      getSortEntries: function() {
        var i, len, ref, results;
        ref = state.sort;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          e = ref[i];
          results.push(Object.assign({}, e));
        }
        return results;
      },
      applySortEntries: function(entries) {
        var clean;
        clean = VPM.normalizeEntries(entries);
        state.applied.push(clean);
        state.sort = (function() {
          var i, len, results;
          results = [];
          for (i = 0, len = clean.length; i < len; i++) {
            e = clean[i];
            results.push(Object.assign({}, e));
          }
          return results;
        })();
        return clean;
      },
      setFormulaFilter: function(formula) {
        return state.filters.push(formula);
      }
    };
    return dv;
  };

  makeHarness = function(scope = 'widget:page1:w1', spaceId = 's1', entries = []) {
    var api, dv, input, wrap;
    wrap = global.document.createElement('div');
    input = global.document.createElement('input');
    wrap.appendChild(input);
    dv = makeDv(entries);
    api = VPM.attach(wrap, {
      getDataView: function() {
        return dv;
      },
      scope: scope,
      spaceId: spaceId,
      filterInput: input
    });
    return {wrap, input, dv, api};
  };

  // Bouton d'une ligne de critère (le rang et le libellé ne sont pas des boutons).
  sortButton = function(row, action) {
    var btn, i, len, ref;
    ref = row.children;
    for (i = 0, len = ref.length; i < len; i++) {
      btn = ref[i];
      if (btn.dataset.action === action) {
        return btn;
      }
    }
    return null;
  };

  sortRow = function(api, index) {
    return api.elements.sortList.children[index];
  };

  // Simule un glisser-déposer natif : dragstart sur la source, dragover sur la
  // cible (moitié haute → insérer avant, moitié basse → insérer après), drop.
  // `getBoundingClientRect` du stub renvoie top 0 / height 100 : clientY 10 = haut.
  dragRow = function(api, from, to, after = false) {
    var dt, ref, rows, source, target;
    rows = api.elements.sortList.children;
    source = rows[from];
    target = rows[to];
    dt = {
      types: ['text/plain'],
      setData: (function() {}),
      getData: (function() {
        return '';
      })
    };
    source._listeners.dragstart[0]({
      dataTransfer: dt,
      stopPropagation: function() {}
    });
    target._listeners.dragover[0]({
      dataTransfer: dt,
      preventDefault: function() {},
      clientY: after ? 80 : 10
    });
    target._listeners.drop[0]({
      dataTransfer: dt,
      preventDefault: function() {},
      stopPropagation: function() {}
    });
    return (ref = source._listeners.dragend) != null ? ref[0]({}) : void 0;
  };

  describe('ViewPresetsMenu — sérialisation du tri', function() {
    it('lit getSortState et ignore la colonne technique sortKey', function() {
      var dv;
      dv = {
        _grid: {
          getSortState: function() {
            return {
              useClient: true,
              columns: [
                {
                  columnName: 'sortKey',
                  ascending: true
                },
                {
                  columnName: 'nom',
                  ascending: false
                },
                {
                  column: 'age',
                  ascending: true
                }
              ]
            };
          }
        }
      };
      return deepEq(VPM.sortEntriesFrom(dv), [
        {
          column: 'nom',
          ascending: false
        },
        {
          column: 'age',
          ascending: true
        }
      ]);
    });
    it('sérialise au format texte JSON attendu par le backend', function() {
      var entries;
      entries = [
        {
          column: 'nom',
          ascending: true
        }
      ];
      return eq(VPM.serializeSort(entries), '[{"column":"nom","ascending":true}]');
    });
    return it('parse un tri stocké et tolère le JSON invalide', function() {
      deepEq(VPM.parseSort('[{"column":"date","ascending":false}]'), [
        {
          column: 'date',
          ascending: false
        }
      ]);
      return deepEq(VPM.parseSort('pas du json'), []);
    });
  });

  describe('ViewPresetsMenu — réordonnancement pur (moveEntry)', function() {
    var entries;
    entries = [
      {
        column: 'a',
        ascending: true
      },
      {
        column: 'b',
        ascending: false
      },
      {
        column: 'c',
        ascending: true
      }
    ];
    it('déplace un critère vers un index plus grand', function() {
      return deepEq(VPM.moveEntry(entries, 0, 2), [
        {
          column: 'b',
          ascending: false
        },
        {
          column: 'c',
          ascending: true
        },
        {
          column: 'a',
          ascending: true
        }
      ]);
    });
    it('déplace un critère vers un index plus petit', function() {
      return deepEq(VPM.moveEntry(entries, 2, 0), [
        {
          column: 'c',
          ascending: true
        },
        {
          column: 'a',
          ascending: true
        },
        {
          column: 'b',
          ascending: false
        }
      ]);
    });
    it('ne mute pas la liste d’origine', function() {
      var before, e;
      before = (function() {
        var i, len, results;
        results = [];
        for (i = 0, len = entries.length; i < len; i++) {
          e = entries[i];
          results.push(Object.assign({}, e));
        }
        return results;
      })();
      VPM.moveEntry(entries, 0, 2);
      return deepEq(entries, before);
    });
    return it('renvoie une copie inchangée pour un déplacement identité ou hors bornes', function() {
      deepEq(VPM.moveEntry(entries, 1, 1), entries);
      deepEq(VPM.moveEntry(entries, -1, 1), entries);
      deepEq(VPM.moveEntry(entries, 0, 9), entries);
      return deepEq(VPM.moveEntry(null, 0, 1), []);
    });
  });

  describe('ViewPresetsMenu — application d’un préréglage', function() {
    it('applique le filtre et le tri du préréglage', function() {
      var h;
      h = makeHarness();
      h.api.applyPreset(P_SORTED);
      eq(h.input.value, '');
      eq(h.input.classList.contains('active'), false);
      deepEq(h.dv._state.filters, ['']);
      return deepEq(h.dv._state.applied, [
        [
          {
            column: 'date',
            ascending: false
          }
        ]
      ]);
    });
    it('remplit le champ filtre et le marque actif', function() {
      var h;
      h = makeHarness();
      h.api.applyPreset(P_FILTERED);
      eq(h.input.value, 'self.actif');
      eq(h.input.classList.contains('active'), true);
      return deepEq(h.dv._state.filters, ['self.actif']);
    });
    it('affiche le nom du préréglage actif sur le bouton', function() {
      var h;
      h = makeHarness();
      h.api.applyPreset(P_FILTERED);
      return eq(h.api.button.textContent, 'Trier / Filtrer · Actifs');
    });
    it('retire la mise en évidence à la moindre frappe dans le filtre', function() {
      var h;
      h = makeHarness();
      h.api.applyPreset(P_FILTERED);
      h.input._listeners.input[0]({
        target: h.input
      });
      return eq(h.api.button.textContent, 'Trier / Filtrer');
    });
    it('met en évidence le préréglage actif dans la liste', function() {
      var h;
      serverPresets = [P_FILTERED, P_SORTED];
      h = makeHarness();
      return h.api.open().then(function() {
        var rows;
        h.api.applyPreset(P_SORTED);
        rows = h.api.elements.presetList.children;
        eq(rows.length, 2);
        eq(rows[0].classList.contains('active'), false);
        return eq(rows[1].classList.contains('active'), true);
      });
    });
    it('retire la mise en évidence quand le tri change à la main', function() {
      var h;
      h = makeHarness();
      h.api.applyPreset(P_SORTED);
      eq(h.api.button.textContent, 'Trier / Filtrer · Récents');
      h.dv._state.sort = [
        {
          column: 'titre',
          ascending: true
        }
      ];
      h.dv._onSortChanged();
      return eq(h.api.button.textContent, 'Trier / Filtrer');
    });
    return it('permet de retirer un critère de tri', function() {
      var h, rows;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      rows = h.api.elements.sortList.children;
      eq(rows.length, 2);
      sortButton(rows[0], 'remove')._listeners.click[0]();
      deepEq(h.dv._state.sort, [
        {
          column: 'note',
          ascending: false
        }
      ]);
      return eq(h.api.elements.sortList.children.length, 1);
    });
  });

  describe('ViewPresetsMenu — tri multicritère', function() {
    it('affiche la poignée, le rang, la colonne, le sens et le retrait', function() {
      var h, row;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      row = sortRow(h.api, 0);
      eq(row.dataset.rank, '1');
      eq(sortRow(h.api, 1).dataset.rank, '2');
      eq(row.draggable, true);
      eq(row.children[0].className, 'view-presets-sort-handle');
      eq(row.children[0].textContent, '⠿');
      eq(row.children[1].textContent, '1.');
      eq(row.children[2].textContent, 'titre');
      eq(sortButton(row, 'dir').textContent, '↑');
      eq(sortButton(sortRow(h.api, 1), 'dir').textContent, '↓');
      return eq(sortButton(row, 'remove').textContent, '✕');
    });
    it('n’a plus de boutons monter/descendre', function() {
      var child, h, i, len, ref, results, row;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      ref = h.api.elements.sortList.children;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        row = ref[i];
        eq(sortButton(row, 'up'), null);
        eq(sortButton(row, 'down'), null);
        results.push((function() {
          var j, len1, ref1, results1;
          ref1 = row.children;
          results1 = [];
          for (j = 0, len1 = ref1.length; j < len1; j++) {
            child = ref1[j];
            results1.push(assert(child.className.indexOf('view-presets-sort-move') === -1, `bouton de priorité encore présent : ${child.className}`));
          }
          return results1;
        })());
      }
      return results;
    });
    it('rappelle l’astuce Maj/Ctrl+clic dans le texte vide', function() {
      var h, txt;
      h = makeHarness();
      h.api.open();
      txt = h.api.elements.sortList.children[0].textContent;
      return assert(/Maj\+clic/.test(txt), `astuce absente : ${txt}`);
    });
    it('ajoute un critère non trié en fin de liste', function() {
      var h, opt, select, values;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        }
      ]);
      h.api.open();
      select = h.api.elements.addColumnSelect;
      values = (function() {
        var i, len, ref, results;
        ref = select.children;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          opt = ref[i];
          results.push(opt.value);
        }
        return results;
      })();
      assert(values.indexOf('titre') === -1, `la colonne déjà triée ne doit pas être proposée : ${values}`);
      assert(values.indexOf('note') !== -1, `la colonne note doit être proposée : ${values}`);
      select.value = 'note';
      h.api.elements.addDirectionSelect.value = 'desc';
      h.api.elements.addBtn._listeners.click[0]();
      deepEq(h.dv._state.applied[h.dv._state.applied.length - 1], [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      eq(h.api.elements.sortList.children.length, 2);
      return eq(sortRow(h.api, 1).dataset.column, 'note');
    });
    it('réordonne les critères par glisser-déposer', function() {
      var h;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        },
        {
          column: 'nom',
          ascending: true
        }
      ]);
      h.api.open();
      // Dépose le 1er critère après le 3e : il devient le dernier.
      dragRow(h.api, 0, 2, true);
      deepEq(h.dv._state.sort, [
        {
          column: 'note',
          ascending: false
        },
        {
          column: 'nom',
          ascending: true
        },
        {
          column: 'titre',
          ascending: true
        }
      ]);
      eq(sortRow(h.api, 0).dataset.column, 'note');
      eq(sortRow(h.api, 2).dataset.column, 'titre');
      // Puis le dernier avant le premier : il reprend la priorité maximale.
      dragRow(h.api, 2, 0, false);
      deepEq(h.dv._state.sort, [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        },
        {
          column: 'nom',
          ascending: true
        }
      ]);
      return eq(sortRow(h.api, 0).dataset.column, 'titre');
    });
    it('affiche une barre d’insertion sur la ligne survolée, effacée au dépôt', function() {
      var dt, h, i, len, ref, results, row, rows;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      rows = h.api.elements.sortList.children;
      dt = {
        setData: (function() {}),
        getData: (function() {
          return '';
        }),
        types: []
      };
      rows[0]._listeners.dragstart[0]({
        dataTransfer: dt,
        stopPropagation: function() {}
      });
      rows[1]._listeners.dragover[0]({
        dataTransfer: dt,
        preventDefault: function() {},
        clientY: 80
      });
      eq(rows[1].classList.contains('drop-after'), true);
      eq(rows[1].classList.contains('drop-before'), false);
      eq(rows[0].classList.contains('dragging'), true);
      rows[1]._listeners.dragover[0]({
        dataTransfer: dt,
        preventDefault: function() {},
        clientY: 10
      });
      eq(rows[1].classList.contains('drop-before'), true);
      eq(rows[1].classList.contains('drop-after'), false);
      rows[1]._listeners.drop[0]({
        dataTransfer: dt,
        preventDefault: function() {},
        stopPropagation: function() {}
      });
      ref = h.api.elements.sortList.children;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        row = ref[i];
        eq(row.classList.contains('drop-before'), false);
        eq(row.classList.contains('drop-after'), false);
        results.push(eq(row.classList.contains('dragging'), false));
      }
      return results;
    });
    it('laisse le menu ouvert pendant et après un glissement', function() {
      var h;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      dragRow(h.api, 0, 1, true);
      eq(h.api.isOpen(), true);
      return eq(h.api.menu.classList.contains('hidden'), false);
    });
    it('bascule le sens d’un critère sans changer sa priorité', function() {
      var h;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      sortButton(sortRow(h.api, 1), 'dir')._listeners.click[0]();
      deepEq(h.dv._state.sort, [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: true
        }
      ]);
      return eq(sortButton(sortRow(h.api, 1), 'dir').textContent, '↑');
    });
    it('sérialise les critères dans l’ordre de priorité', function() {
      var h;
      h = makeHarness('space:s1', 's1', [
        {
          column: 'titre',
          ascending: true
        },
        {
          column: 'note',
          ascending: false
        }
      ]);
      h.api.open();
      dragRow(h.api, 1, 0, false);
      promptAnswers.push('Priorité');
      return h.api.saveCurrent().then(function() {
        var c, call;
        call = ((function() {
          var i, len, results;
          results = [];
          for (i = 0, len = mutationCalls.length; i < len; i++) {
            c = mutationCalls[i];
            if (c.vars.name === 'Priorité') {
              results.push(c);
            }
          }
          return results;
        })())[0];
        assert(call, 'mutation saveViewPreset attendue');
        return eq(call.vars.sort, '[{"column":"note","ascending":false},{"column":"titre","ascending":true}]');
      });
    });
    return it('retire la mise en évidence du préréglage actif quand le tri change', function() {
      var h;
      h = makeHarness();
      h.api.applyPreset(P_SORTED);
      eq(h.api.button.textContent, 'Trier / Filtrer · Récents');
      h.api.open();
      h.api.elements.addColumnSelect.value = 'titre';
      h.api.elements.addBtn._listeners.click[0]();
      return eq(h.api.button.textContent, 'Trier / Filtrer');
    });
  });

  describe('ViewPresetsMenu — enregistrement et suppression', function() {
    it('« Enregistrer sous… » envoie la portée du widget, le filtre et le tri', function() {
      var h;
      h = makeHarness('widget:page1:w1', 's1', [
        {
          column: 'nom',
          ascending: true
        }
      ]);
      h.input.value = 'self.actif';
      promptAnswers.push('Mon préréglage');
      return h.api.saveCurrent().then(function() {
        var c, call, calls;
        calls = (function() {
          var i, len, results;
          results = [];
          for (i = 0, len = mutationCalls.length; i < len; i++) {
            c = mutationCalls[i];
            if (c.vars.name === 'Mon préréglage') {
              results.push(c);
            }
          }
          return results;
        })();
        eq(calls.length, 1);
        call = calls[0];
        assert(/saveViewPreset/.test(call.m), 'mutation saveViewPreset attendue');
        eq(call.vars.scope, 'widget:page1:w1');
        eq(call.vars.spaceId, 's1');
        eq(call.vars.filter, 'self.actif');
        eq(call.vars.sort, '[{"column":"nom","ascending":true}]');
        return eq(h.api.button.textContent, 'Trier / Filtrer · Mon préréglage');
      });
    });
    it('« Enregistrer sous… » utilise la portée de la grille principale', function() {
      var h;
      h = makeHarness('space:s1', 's1');
      promptAnswers.push('Espace');
      return h.api.saveCurrent().then(function() {
        var c, calls;
        calls = (function() {
          var i, len, results;
          results = [];
          for (i = 0, len = mutationCalls.length; i < len; i++) {
            c = mutationCalls[i];
            if (c.vars.name === 'Espace') {
              results.push(c);
            }
          }
          return results;
        })();
        eq(calls[0].vars.scope, 'space:s1');
        return eq(calls[0].vars.spaceId, 's1');
      });
    });
    it('supprime le préréglage après confirmation', function() {
      var h;
      serverPresets = [P_FILTERED, P_SORTED];
      h = makeHarness();
      return h.api.open().then(function() {
        confirmAnswers.push(true);
        return h.api.deletePreset(P_FILTERED).then(function() {
          var c, calls;
          calls = (function() {
            var i, len, results;
            results = [];
            for (i = 0, len = mutationCalls.length; i < len; i++) {
              c = mutationCalls[i];
              if (/deleteViewPreset/.test(c.m)) {
                results.push(c);
              }
            }
            return results;
          })();
          eq(calls.length, 1);
          eq(calls[0].vars.id, 'p1');
          return eq(h.api.elements.presetList.children.length, 1);
        });
      });
    });
    return it('ne supprime rien sans confirmation', function() {
      var h;
      serverPresets = [P_FILTERED];
      h = makeHarness();
      return h.api.open().then(function() {
        var before;
        confirmAnswers.push(false);
        before = mutationCalls.length;
        return h.api.deletePreset(P_FILTERED).then(function() {
          eq(mutationCalls.length, before);
          return eq(h.api.elements.presetList.children.length, 1);
        });
      });
    });
  });

  describe('ViewPresetsMenu — cycle de vie', function() {
    it('retire son écouteur input à la destruction', function() {
      var api, dv, input, wrap;
      wrap = global.document.createElement('div');
      input = global.document.createElement('input');
      wrap.appendChild(input);
      dv = makeDv();
      api = VPM.attach(wrap, {
        getDataView: (function() {
          return dv;
        }),
        scope: 'space:s1',
        spaceId: 's1',
        filterInput: input
      });
      eq((input._listeners.input || []).length, 1);
      api.destroy();
      return eq((input._listeners.input || []).length, 0);
    });
    return it('ne les accumule pas quand la grille réattache le menu au même input', function() {
      var api1, api2, dv, input, opts, wrap;
      wrap = global.document.createElement('div');
      input = global.document.createElement('input');
      wrap.appendChild(input);
      dv = makeDv();
      opts = {
        getDataView: (function() {
          return dv;
        }),
        scope: 'space:s1',
        spaceId: 's1',
        filterInput: input
      };
      api1 = VPM.attach(wrap, opts);
      eq((input._listeners.input || []).length, 1);
      // Changement d'espace : la grille principale réattache sur le même input.
      api2 = VPM.attach(wrap, opts);
      eq((input._listeners.input || []).length, 1);
      api2.destroy();
      return eq((input._listeners.input || []).length, 0);
    });
  });

  summary();

}).call(this);
