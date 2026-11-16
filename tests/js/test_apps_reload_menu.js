(function() {
  // tests/js/test_apps_reload_menu.coffee — T14
  // Après une installation ou une purge de paquet, le MENU (espaces, pages,
  // vues de données) doit être rechargé via app._loadAll, pas seulement la
  // liste des applications (app._loadApps) — sinon il faut recharger la page
  // pour voir les nouveaux éléments.
  var EH, _queue, applyResult, assert, deepEq, describe, eq, it, makeApp, serialIt, sleep, stubGql, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  require('../../frontend/src/app_apps_helpers');

  EH = global.window.AppAppsHelpers;

  sleep = function(ms) {
    return new Promise(function(r) {
      return setTimeout(r, ms);
    });
  };

  // Les globals (GQL, tdbConfirm, tdbAlert) sont partagés : on sérialise les
  // scénarios, comme dans test_sidebar_helpers.coffee.
  _queue = Promise.resolve();

  serialIt = function(desc, fn) {
    return it(desc, function() {
      var run;
      run = _queue.then(fn, fn);
      _queue = run;
      return run;
    });
  };

  // Fake app : éléments consultés par renderApplyReport / confirmPurge, plus
  // les deux spies de rechargement.
  makeApp = function(events) {
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
      _appPlan: {
        conflict: []
      },
      _appPackageYaml: "name: demo\n",
      _appChoices: {},
      _loadApps: function() {
        return events.push('loadApps');
      },
      _loadAll: function() {
        return events.push('loadAll');
      },
      el: {
        appsApplyBtn: function() {
          return get('apps-apply-btn');
        },
        appsApplyReport: function() {
          return get('apps-apply-report');
        },
        appsAllowDowngrade: function() {
          return get('apps-allow-downgrade');
        },
        appsPurgeBox: function() {
          return get('apps-purge-box');
        },
        appsPurgeReport: function() {
          return get('apps-purge-report');
        },
        appsPurgePreview: function() {
          return get('apps-purge-preview');
        },
        appsPurgeConfirmInput: function() {
          return get('apps-purge-confirm-input');
        },
        appsPurgeConfirmBtn: function() {
          return get('apps-purge-confirm-btn');
        },
        appsPurgeConfirmHint: function() {
          return get('apps-purge-confirm-hint');
        }
      }
    };
    return app;
  };

  // GQL.mutate simulé : trace 'mutate' à l'appel puis 'mutate-resolved' quand
  // la promesse se résout — pour prouver l'ordre par rapport au rechargement.
  stubGql = function(result, events) {
    return global.GQL = {
      mutate: function(query, vars) {
        events.push('mutate');
        return Promise.resolve(result).then(function(r) {
          events.push('mutate-resolved');
          return r;
        });
      }
    };
  };

  applyResult = function(over = {}) {
    var base;
    base = {
      ok: true,
      created: ['space:livres'],
      updated: [],
      kept: [],
      unchanged: [],
      obsolete: [],
      skipped: [],
      error: null
    };
    return Object.assign(base, over);
  };

  // ---------------------------------------------------------------------------
  describe('AppAppsHelpers.applyPackage — rechargement du menu (T14)', function() {
    serialIt('(a) après installation réussie, _loadAll est appelé APRÈS la résolution de la mutation', async function() {
      var app, events;
      events = [];
      global.tdbConfirm = function() {
        return Promise.resolve(true);
      };
      global.tdbAlert = function(msg, kind) {
        return events.push('alert');
      };
      stubGql({
        applyAppUpdate: applyResult()
      }, events);
      app = makeApp(events);
      await EH.applyPackage(app);
      await sleep(40);
      return deepEq(events, ['mutate', 'mutate-resolved', 'loadApps', 'loadAll'], `_loadAll doit suivre la résolution de la mutation — obtenu ${JSON.stringify(events)}`);
    });
    serialIt('(d) les deux appels (_loadApps et _loadAll) ont lieu', async function() {
      var app, events;
      events = [];
      global.tdbConfirm = function() {
        return Promise.resolve(true);
      };
      global.tdbAlert = function(msg, kind) {
        return events.push('alert');
      };
      stubGql({
        applyAppUpdate: applyResult()
      }, events);
      app = makeApp(events);
      await EH.applyPackage(app);
      await sleep(40);
      assert(events.indexOf('loadApps') >= 0, '_loadApps doit être appelé');
      return assert(events.indexOf('loadAll') >= 0, '_loadAll doit être appelé');
    });
    serialIt('installation partielle (ok faux mais created non vide) recharge aussi le menu', async function() {
      var app, events;
      events = [];
      global.tdbConfirm = function() {
        return Promise.resolve(true);
      };
      global.tdbAlert = function(msg, kind) {
        return events.push('alert');
      };
      stubGql({
        applyAppUpdate: applyResult({
          ok: false,
          created: ['space:x'],
          error: 'partiel'
        })
      }, events);
      app = makeApp(events);
      await EH.applyPackage(app);
      await sleep(40);
      return assert(events.indexOf('loadAll') >= 0, `_loadAll doit être appelé si created n'est pas vide — obtenu ${JSON.stringify(events)}`);
    });
    return serialIt('(c) échec complet : _loadAll n’est PAS appelé', async function() {
      var app, events;
      events = [];
      global.tdbConfirm = function() {
        return Promise.resolve(true);
      };
      global.tdbAlert = function(msg, kind) {
        return events.push('alert');
      };
      stubGql({
        applyAppUpdate: applyResult({
          ok: false,
          created: [],
          updated: [],
          error: 'boom'
        })
      }, events);
      app = makeApp(events);
      await EH.applyPackage(app);
      await sleep(40);
      return deepEq(events, ['mutate', 'mutate-resolved'], `ni _loadApps ni _loadAll en cas d'échec complet — obtenu ${JSON.stringify(events)}`);
    });
  });

  // ---------------------------------------------------------------------------
  describe('AppAppsHelpers.confirmPurge — rechargement du menu (T14)', function() {
    var _purgeApp;
    _purgeApp = function(events) {
      var app;
      app = makeApp(events);
      app._appPurgeAppId = 'org.demo';
      app._appPurgePreview = {
        keys: ['space:livres']
      };
      app._appPurgeTarget = 'livres';
      app.el.appsPurgeConfirmInput().value = 'livres';
      return app;
    };
    serialIt('(b) après purge réussie, _loadAll est appelé après la résolution', async function() {
      var app, events;
      events = [];
      global.tdbConfirm = function() {
        return Promise.resolve(true);
      };
      global.tdbAlert = function(msg, kind) {
        return events.push('alert');
      };
      stubGql({
        purgeAppObsolete: {
          ok: true,
          purged: ['space:livres'],
          error: null
        }
      }, events);
      app = _purgeApp(events);
      await EH.confirmPurge(app);
      await sleep(40);
      return deepEq(events, ['mutate', 'mutate-resolved', 'loadApps', 'loadAll'], `purge réussie → _loadApps puis _loadAll — obtenu ${JSON.stringify(events)}`);
    });
    return serialIt('purge en échec : aucun rechargement', async function() {
      var app, events;
      events = [];
      global.tdbConfirm = function() {
        return Promise.resolve(true);
      };
      global.tdbAlert = function(msg, kind) {
        return events.push('alert');
      };
      stubGql({
        purgeAppObsolete: {
          ok: false,
          purged: [],
          error: 'nope'
        }
      }, events);
      app = _purgeApp(events);
      await EH.confirmPurge(app);
      await sleep(40);
      return deepEq(events, ['mutate', 'mutate-resolved'], `aucun rechargement en cas d'échec — obtenu ${JSON.stringify(events)}`);
    });
  });

  summary();

}).call(this);
