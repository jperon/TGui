(function() {
  // tests/js/test_sidebar_helpers.coffee
  // Handler « nouvel espace » de la barre latérale (AppSidebarHelpers.bindSidebar) :
  // après création, l'espace doit être sélectionné via app.selectSpace une fois
  // app._loadAll résolue (donc après _restoreFromHash, qui écraserait sinon la
  // sélection — app_data_helpers.coffee:5-12).
  var ASH, _queue, assert, deepEq, describe, dispatchClick, eq, it, makeApp, serialIt, sleep, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  require('../../frontend/src/app_sidebar_helpers');

  ASH = global.window.AppSidebarHelpers;

  sleep = function(ms) {
    return new Promise(function(r) {
      return setTimeout(r, ms);
    });
  };

  // Le runner exécute les `it` en parallèle, or les globals (Spaces, tdbPrompt,
  // tdbAlert) sont partagés : un handler encore en vol lirait le mock du
  // scénario suivant. On sérialise explicitement nos scénarios.
  _queue = Promise.resolve();

  serialIt = function(desc, fn) {
    return it(desc, function() {
      var run;
      run = _queue.then(fn, fn);
      _queue = run;
      return run;
    });
  };

  // Déclenche le listener 'click' enregistré sur un élément stub et renvoie
  // les promesses retournées par les handlers (handlers async en CoffeeScript 2).
  dispatchClick = function(el) {
    var fn, i, len, ref, results;
    ref = el._listeners['click'] || [];
    results = [];
    for (i = 0, len = ref.length; i < len; i++) {
      fn = ref[i];
      results.push(fn());
    }
    return results;
  };

  // Fake app : seuls les éléments consultés À L'ENREGISTREMENT du handler sont
  // nécessaires (app_sidebar_helpers.coffee:55-167) ; les méthodes appelées au
  // moment du clic sont fournies par chaque scénario via hooks.
  makeApp = function(hooks) {
    var app, elems, get;
    elems = {};
    get = function(id) {
      return elems[id] != null ? elems[id] : elems[id] = global.document.createElement('div');
    };
    app = {
      _t: function(key, vars = {}) {
        return key;
      },
      _err: function(e) {
        if (e && e.message) {
          return e.message;
        } else {
          return String(e);
        }
      },
      _applySidebarState: function() {},
      _bindChangePasswordDialog: function() {},
      _bindCreateUserDialog: function() {},
      _bindCreateGroupDialog: function() {},
      _bindSnapshotPanel: function() {},
      _bindAppsPanel: function() {},
      _loadAll: hooks.loadAll,
      selectSpace: hooks.selectSpace,
      el: {
        newSpaceBtn: function() {
          return get('new-space-btn');
        },
        newPageBtn: function() {
          return get('new-page-btn');
        },
        newDataViewBtn: function() {
          return get('new-data-view-btn');
        },
        currentUserBtn: function() {
          return get('current-user-btn');
        },
        userMenu: function() {
          return get('user-menu');
        },
        changePasswordBtn: function() {
          return get('change-password-btn');
        },
        logoutBtn: function() {
          return get('logout-btn');
        },
        langFrBtn: function() {
          return get('lang-fr-btn');
        },
        langEnBtn: function() {
          return get('lang-en-btn');
        },
        adminNavUsers: function() {
          return get('admin-nav-users');
        },
        adminNavGroups: function() {
          return get('admin-nav-groups');
        },
        adminNavSnapshot: function() {
          return get('admin-nav-snapshot');
        },
        adminNavApps: function() {
          return get('admin-nav-apps');
        },
        pluginsNavManage: function() {
          return get('plugins-nav-manage');
        },
        warningChangePasswordBtn: function() {
          return get('warning-change-password-btn');
        },
        spaceList: function() {
          return get('space-list');
        }
      }
    };
    return app;
  };

  // ---------------------------------------------------------------------------
  describe('AppSidebarHelpers.bindSidebar — bouton nouvel espace', function() {
    serialIt('sélectionne le nouvel espace APRÈS la résolution de _loadAll', async function() {
      var alerted, app, created, events, existing, inList, prompted, selected;
      events = [];
      selected = [];
      created = {
        id: 'sp-1',
        name: 'Livres',
        description: ''
      };
      existing = {
        id: 'sp-0',
        name: 'Ancien',
        description: ''
      };
      prompted = [];
      alerted = [];
      global.tdbPrompt = function(msg) {
        prompted.push(msg);
        return Promise.resolve('Livres');
      };
      global.tdbAlert = function(msg, kind) {
        alerted.push(kind);
        return events.push('alert');
      };
      global.Spaces = {
        create: function(name) {
          events.push('create');
          return Promise.resolve(created);
        }
      };
      app = makeApp({
        // _loadAll se résout sur un tour de boucle d'événements (setTimeout),
        // comme AppDataHelpers.loadAll (app_data_helpers.coffee:4-5) : c'est
        // lui qui peuple app._allSpaces.
        loadAll: function() {
          return new Promise(function(resolve) {
            return setTimeout(function() {
              app._allSpaces = [existing, created];
              events.push('loadAll');
              return resolve();
            }, 0);
          });
        },
        selectSpace: function(sp) {
          events.push('selectSpace');
          return selected.push(sp);
        }
      });
      ASH.bindSidebar(app);
      eq(prompted.length, 0, 'aucun prompt avant le clic');
      await Promise.all(dispatchClick(app.el.newSpaceBtn()));
      await sleep(40);
      eq(alerted.length, 0, `aucune alerte attendue (reçu : ${alerted})`);
      eq(prompted.length, 1, 'le prompt doit avoir été ouvert une fois');
      eq(prompted[0], 'ui.prompts.newSpace');
      deepEq(events, ['create', 'loadAll', 'selectSpace'], `selectSpace doit être appelé après la résolution de _loadAll — obtenu ${JSON.stringify(events)}`);
      eq(selected.length, 1, 'selectSpace doit être appelé une seule fois');
      eq(selected[0].id, 'sp-1');
      eq(selected[0], created, 'selectSpace doit recevoir l’espace créé');
      inList = (app._allSpaces || []).find(function(s) {
        return s.id === 'sp-1';
      });
      return assert(selected[0] === inList, 'selectSpace doit recevoir l’objet de app._allSpaces');
    });
    return serialIt('ne sélectionne rien si l’espace est introuvable dans _allSpaces', async function() {
      var alerted, app, created, events;
      events = [];
      alerted = [];
      created = {
        id: 'sp-9',
        name: 'Secret',
        description: ''
      };
      global.tdbPrompt = function() {
        return Promise.resolve('Secret');
      };
      global.tdbAlert = function(msg, kind) {
        alerted.push(kind);
        return events.push('alert');
      };
      global.Spaces = {
        create: function() {
          events.push('create');
          return Promise.resolve(created);
        }
      };
      app = makeApp({
        loadAll: function() {
          return new Promise(function(resolve) {
            return setTimeout(function() {
              // Droits de lecture insuffisants : le nouvel espace n'apparaît pas.
              app._allSpaces = [
                {
                  id: 'sp-0',
                  name: 'Ancien',
                  description: ''
                }
              ];
              events.push('loadAll');
              return resolve();
            }, 0);
          });
        },
        selectSpace: function(sp) {
          return events.push('selectSpace');
        }
      });
      ASH.bindSidebar(app);
      await Promise.all(dispatchClick(app.el.newSpaceBtn()));
      await sleep(40);
      deepEq(events, ['create', 'loadAll'], `selectSpace ne doit pas être appelé si l’espace est absent de _allSpaces — obtenu ${JSON.stringify(events)}`);
      return eq(alerted.length, 0, `aucune alerte attendue (reçu : ${alerted})`);
    });
  });

  summary();

}).call(this);
