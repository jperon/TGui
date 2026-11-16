(function() {
  // tests/js/test_view_presets_menu.coffee
  // Menu « Trier / Filtrer » : sérialisation du tri, application d'un préréglage
  // (filtre + tri), « Enregistrer sous », suppression, mise en évidence.
  var P_FILTERED, P_SORTED, VPM, assert, confirmAnswers, deepEq, describe, eq, it, makeDv, makeHarness, mutationCalls, promptAnswers, queries, serverPresets, summary;

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

  makeDv = function(entries = []) {
    var dv, e, state;
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
      var h, removeBtn, rows;
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
      removeBtn = rows[0].children[1];
      removeBtn._listeners.click[0]();
      deepEq(h.dv._state.sort, [
        {
          column: 'note',
          ascending: false
        }
      ]);
      return eq(h.api.elements.sortList.children.length, 1);
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
