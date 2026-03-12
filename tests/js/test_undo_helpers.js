(function() {
  var UH, assert, describe, eq, it, lastDeleteIds, lastRestorePayload, lastUpdatePayload, makeApp, store, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  // Minimal stubs for AppUndoHelpers
  store = {};

  lastUpdatePayload = null;

  lastRestorePayload = null;

  lastDeleteIds = null;

  global.GQL = {
    query: function(q, vars = {}) {
      var rec;
      if (/query Record/.test(q)) {
        rec = store[vars.id];
        return Promise.resolve({
          record: rec != null ? {
            id: vars.id,
            data: JSON.stringify(rec)
          } : null
        });
      } else {
        return Promise.resolve({});
      }
    },
    mutate: function(q, vars = {}) {
      var current, i, j, len, len1, patch, rec, ref, ref1;
      if (/updateRecords/.test(q)) {
        lastUpdatePayload = vars.records;
        ref = vars.records || [];
        for (i = 0, len = ref.length; i < len; i++) {
          rec = ref[i];
          current = store[String(rec.id)] || {};
          patch = JSON.parse(rec.data);
          store[String(rec.id)] = {...current, ...patch};
        }
        return Promise.resolve({
          updateRecords: vars.records.map(function(r) {
            return {
              id: r.id,
              data: r.data
            };
          })
        });
      } else if (/restoreRecords/.test(q)) {
        lastRestorePayload = vars.records;
        ref1 = vars.records || [];
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          rec = ref1[j];
          store[String(rec.id)] = JSON.parse(rec.data);
        }
        return Promise.resolve({
          restoreRecords: vars.records.map(function(r) {
            return {
              id: r.id,
              data: r.data
            };
          })
        });
      } else {
        return Promise.resolve({});
      }
    }
  };

  global.Spaces = {
    deleteRecords: function(spaceId, ids) {
      var i, id, len, ref;
      lastDeleteIds = ids;
      ref = ids || [];
      for (i = 0, len = ref.length; i < len; i++) {
        id = ref[i];
        delete store[String(id)];
      }
      return Promise.resolve(true);
    }
  };

  require('../../frontend/src/app_undo_helpers');

  UH = global.window.AppUndoHelpers;

  makeApp = function() {
    var app, redoBtn, undoBtn;
    undoBtn = global.document.createElement('button');
    redoBtn = global.document.createElement('button');
    app = {
      _allSpaces: [
        {
          id: 's1',
          name: 'Space1'
        }
      ],
      _currentSpace: {
        id: 's1',
        name: 'Space1'
      },
      _activeDataView: {
        load: function() {
          return Promise.resolve(true);
        }
      },
      el: {
        undoBtn: function() {
          return undoBtn;
        },
        redoBtn: function() {
          return redoBtn;
        },
        customViewList: function() {
          return {
            querySelector: function() {
              return null;
            }
          };
        }
      },
      selectSpace: function(sp) {
        return app._currentSpace = sp;
      },
      loadSpaces: function() {
        return Promise.resolve();
      },
      loadCustomViews: function() {
        return Promise.resolve();
      }
    };
    return {app, undoBtn, redoBtn};
  };

  describe('AppUndoHelpers', function() {
    return it('gère update, blocage conflit, et delete undo/redo', async function() {
      var app, okBlocked, okMulti, okRedo, okRedoDelete, okSubset, okUndo, okUndoDelete, undoBtn;
      // 1) Update undo/redo
      UH.clear();
      store = {
        '1': {
          nom: 'B'
        }
      };
      lastUpdatePayload = null;
      UH.pushAction({
        spaceId: 's1',
        context: {
          spaceId: 's1'
        },
        updates: [
          {
            id: '1',
            before: {
              nom: 'A'
            },
            after: {
              nom: 'B'
            }
          }
        ],
        inserts: [],
        deletes: []
      });
      ({app} = makeApp());
      okUndo = (await UH.undo(app));
      assert(okUndo, 'undo update doit réussir');
      eq(store['1'].nom, 'A');
      assert((lastUpdatePayload != null ? lastUpdatePayload.length : void 0) === 1, 'updateRecords doit être appelé');
      okRedo = (await UH.redo(app));
      assert(okRedo, 'redo update doit réussir');
      eq(store['1'].nom, 'B');
      // 2) Régression subset: un champ non modifié peut diverger sans bloquer undo
      UH.clear();
      store = {
        '1': {
          nom: 'B',
          prenom: 'Victor'
        }
      };
      UH.pushAction({
        spaceId: 's1',
        context: {
          spaceId: 's1'
        },
        updates: [
          {
            id: '1',
            before: {
              nom: 'A'
            },
            after: {
              nom: 'B'
            }
          }
        ],
        inserts: [],
        deletes: []
      });
      ({app} = makeApp());
      okSubset = (await UH.undo(app));
      assert(okSubset, 'undo subset doit réussir');
      eq(store['1'].nom, 'A');
      eq(store['1'].prenom, 'Victor');
      // 3) Multi-update dans une seule action
      UH.clear();
      store = {
        '1': {
          nom: 'B'
        },
        '2': {
          nom: 'Y'
        }
      };
      UH.pushAction({
        spaceId: 's1',
        context: {
          spaceId: 's1'
        },
        updates: [
          {
            id: '1',
            before: {
              nom: 'A'
            },
            after: {
              nom: 'B'
            }
          },
          {
            id: '2',
            before: {
              nom: 'X'
            },
            after: {
              nom: 'Y'
            }
          }
        ],
        inserts: [],
        deletes: []
      });
      ({app} = makeApp());
      okMulti = (await UH.undo(app));
      assert(okMulti, 'undo multi-update doit réussir');
      eq(store['1'].nom, 'A');
      eq(store['2'].nom, 'X');
      // 4) Conflit serveur bloque undo
      UH.clear();
      store = {
        '1': {
          nom: 'X'
        }
      };
      UH.pushAction({
        spaceId: 's1',
        context: {
          spaceId: 's1'
        },
        updates: [
          {
            id: '1',
            before: {
              nom: 'A'
            },
            after: {
              nom: 'B'
            }
          }
        ],
        inserts: [],
        deletes: []
      });
      ({app, undoBtn} = makeApp());
      okBlocked = (await UH.undo(app));
      assert(!okBlocked, 'undo doit être bloqué en conflit');
      await UH.refreshUI(app);
      assert(undoBtn.classList.contains('toolbar-btn--blocked'), 'le bouton undo doit être marqué bloqué');
      assert(String(undoBtn.title).includes('bloquée'), 'le tooltip doit expliquer le blocage');
      // 5) Delete undo/redo
      UH.clear();
      store = {};
      lastRestorePayload = null;
      lastDeleteIds = null;
      UH.pushAction({
        spaceId: 's1',
        context: {
          spaceId: 's1'
        },
        updates: [],
        inserts: [],
        deletes: [
          {
            id: '9',
            before: {
              nom: 'Supp'
            }
          }
        ]
      });
      ({app} = makeApp());
      okUndoDelete = (await UH.undo(app));
      assert(okUndoDelete, 'undo delete doit réussir');
      eq(store['9'].nom, 'Supp');
      assert((lastRestorePayload != null ? lastRestorePayload.length : void 0) === 1, 'restoreRecords doit être appelé');
      okRedoDelete = (await UH.redo(app));
      assert(okRedoDelete, 'redo delete doit réussir');
      assert(store['9'] == null, 'record doit être supprimé à nouveau');
      return assert((lastDeleteIds || []).includes('9'), 'deleteRecords doit être appelé');
    });
  });

  summary();

}).call(this);
