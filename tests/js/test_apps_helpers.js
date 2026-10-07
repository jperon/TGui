(function() {
  // tests/js/test_apps_helpers.coffee — tests de AppAppsHelpers (app_apps_helpers.js)
  // Fonctions pures du versionnage des apps + rendu sécurisé (pas d'innerHTML).
  var EH, assert, collectTags, deepEq, describe, eq, it, makeApp, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  require('../../frontend/src/app_apps_helpers');

  EH = global.window.AppAppsHelpers;

  // --- fake app ---------------------------------------------------------------
  makeApp = function() {
    var app, elems, get;
    elems = {};
    get = function(id) {
      if (elems[id] == null) {
        elems[id] = global.document.createElement('div');
      }
      return elems[id];
    };
    app = {
      _t: function(key, vars = {}) {
        return key;
      },
      _appChoices: {},
      el: {
        appsList: function() {
          return get('apps-list');
        },
        appsPurgeOpenBtn: function() {
          return get('apps-purge-open-btn');
        },
        appsPlanBox: function() {
          return get('apps-plan-box');
        },
        appsPlanErrors: function() {
          return get('apps-plan-errors');
        },
        appsApplyBtn: function() {
          return get('apps-apply-btn');
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

  // Collecte récursive des tagName (pour vérifier l'absence d'éléments injectés).
  collectTags = function(node) {
    var tags, walk;
    tags = [];
    walk = function(n) {
      var c, i, len, ref, results;
      if (n && n.tagName) {
        tags.push(n.tagName);
      }
      if (n && n._children) {
        ref = n._children;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          c = ref[i];
          results.push(walk(c));
        }
        return results;
      }
    };
    walk(node);
    return tags;
  };

  // ---------------------------------------------------------------------------
  describe('AppAppsHelpers.isSemver', function() {
    it('accepte x.y.z numérique', function() {
      assert(EH.isSemver('1.2.3'), '1.2.3');
      return assert(EH.isSemver('10.0.42'), '10.0.42');
    });
    return it('refuse les formes invalides', function() {
      assert(!EH.isSemver('1.2'), '1.2');
      assert(!EH.isSemver('v1.2.3'), 'v1.2.3');
      assert(!EH.isSemver('1.2.3-beta'), 'préfixe');
      assert(!EH.isSemver('1.2.x'), 'non numérique');
      assert(!EH.isSemver(''), 'vide');
      return assert(!EH.isSemver(null), 'null');
    });
  });

  describe('AppAppsHelpers.buildDecisions', function() {
    it('défaut « local » pour un conflit sans choix', function() {
      var d;
      d = EH.buildDecisions([
        {
          key: 'space:a'
        }
      ], {});
      return deepEq(d, [
        {
          key: 'space:a',
          choice: 'local'
        }
      ]);
    });
    it('respecte les choix fournis', function() {
      var d;
      d = EH.buildDecisions([
        {
          key: 'a'
        },
        {
          key: 'b'
        }
      ], {
        b: 'delivered'
      });
      return deepEq(d, [
        {
          key: 'a',
          choice: 'local'
        },
        {
          key: 'b',
          choice: 'delivered'
        }
      ]);
    });
    return it('retourne un tableau vide sans conflit', function() {
      return deepEq(EH.buildDecisions(null, null), []);
    });
  });

  describe('AppAppsHelpers.confirmationTarget', function() {
    it('un seul élément → partie après le dernier « : »', function() {
      eq(EH.confirmationTarget(['space:livres'], 'org.app'), 'livres');
      return eq(EH.confirmationTarget(['field:livres.titre'], 'org.app'), 'livres.titre');
    });
    it('plusieurs éléments → identifiant de l’app', function() {
      return eq(EH.confirmationTarget(['space:a', 'space:b'], 'org.app'), 'org.app');
    });
    return it('clé sans « : » → clé entière', function() {
      return eq(EH.confirmationTarget(['solitaire'], 'org.app'), 'solitaire');
    });
  });

  describe('AppAppsHelpers.summarizePlan', function() {
    it('compte chaque catégorie', function() {
      var plan, s;
      plan = {
        create: [
          {
            key: 'a'
          }
        ],
        update: [
          {
            key: 'b'
          },
          {
            key: 'c'
          }
        ],
        conflict: [
          {
            key: 'd'
          }
        ],
        keepLocal: [
          {
            key: 'e'
          }
        ],
        obsolete: ['f'],
        rename: [
          {
            from: 'g',
            to: 'h'
          }
        ],
        unchanged: ['i', 'j', 'k'],
        errors: []
      };
      s = EH.summarizePlan(plan);
      eq(s.create, 1);
      eq(s.update, 2);
      eq(s.conflict, 1);
      eq(s.keepLocal, 1);
      eq(s.obsolete, 1);
      eq(s.rename, 1);
      eq(s.unchanged, 3);
      return eq(s.errors, 0);
    });
    return it('tolère un plan vide', function() {
      var s;
      s = EH.summarizePlan({});
      eq(s.create, 0);
      return eq(s.conflict, 0);
    });
  });

  describe('AppAppsHelpers.hasCodeChanges', function() {
    it('vrai si un item isCode', function() {
      return assert(EH.hasCodeChanges({
        create: [
          {
            key: 'a',
            isCode: true
          }
        ]
      }));
    });
    it('vrai si le type est plugin/page/dataview', function() {
      assert(EH.hasCodeChanges({
        update: [
          {
            key: 'a',
            type: 'plugin'
          }
        ]
      }));
      return assert(EH.hasCodeChanges({
        conflict: [
          {
            key: 'a',
            type: 'page'
          }
        ]
      }));
    });
    return it('faux si aucun code tiers', function() {
      assert(!EH.hasCodeChanges({
        create: [
          {
            key: 'a',
            type: 'space'
          }
        ]
      }));
      return assert(!EH.hasCodeChanges({}));
    });
  });

  describe('AppAppsHelpers.renderAppsList — sécurité', function() {
    it('n’injecte pas de HTML depuis un nom de paquet', function() {
      var app, malicious, tags;
      app = makeApp();
      malicious = '<img src=x onerror=alert(1)>';
      EH.renderAppsList(app, [
        {
          appId: 'x',
          name: malicious,
          version: '1.0.0',
          activeCount: 2,
          obsoleteCount: 0
        }
      ]);
      tags = collectTags(app.el.appsList());
      assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
      return assert(tags.indexOf('DIV') >= 0, 'le nom doit être rendu comme texte');
    });
    it('désactive le bouton de purge sans élément obsolète', function() {
      var app;
      app = makeApp();
      EH.renderAppsList(app, [
        {
          appId: 'x',
          name: 'App',
          version: '1.0.0',
          activeCount: 2,
          obsoleteCount: 0
        }
      ]);
      return assert(app.el.appsPurgeOpenBtn().disabled, 'désactivé quand obsoleteCount = 0');
    });
    return it('active le bouton de purge s’il existe des obsolètes', function() {
      var app;
      app = makeApp();
      EH.renderAppsList(app, [
        {
          appId: 'x',
          name: 'App',
          version: '1.0.0',
          activeCount: 1,
          obsoleteCount: 3
        }
      ]);
      return assert(!app.el.appsPurgeOpenBtn().disabled, 'activé quand obsoleteCount > 0');
    });
  });

  describe('AppAppsHelpers.renderPlan', function() {
    it('rend un plan simulé avec conflit et code tiers', function() {
      var app, plan, tags, text;
      app = makeApp();
      plan = {
        create: [
          {
            key: 'plugin:demo',
            type: 'plugin',
            content: {
              name: 'demo'
            },
            isCode: true
          }
        ],
        update: [
          {
            key: 'space:livres',
            type: 'space',
            content: {},
            isCode: false
          }
        ],
        keepLocal: [
          {
            key: 'field:livres.titre',
            type: 'field',
            content: {}
          }
        ],
        conflict: [
          {
            key: 'view:livres.vue',
            type: 'view',
            local: {
              a: 1
            },
            delivered: {
              a: 2
            }
          }
        ],
        obsolete: ['page:ancienne'],
        rename: [
          {
            from: 'space:old',
            to: 'space:new'
          }
        ],
        unchanged: ['group:admin'],
        errors: []
      };
      EH.renderPlan(app, plan);
      tags = collectTags(app.el.appsPlanBox());
      eq(app.el.appsApplyBtn().disabled, false);
      assert(app.el.appsPlanErrors().classList.contains('hidden'), 'pas d’erreurs affichées');
      assert(tags.indexOf('DETAILS') >= 0, 'détails dépliables pour le code tiers');
      assert(tags.indexOf('TABLE') < 0, 'aucun tableau dans le plan');
      text = JSON.stringify(app.el.appsPlanBox());
      assert(text.indexOf('ui.apps.conflicts') >= 0, 'section conflits');
      assert(text.indexOf('ui.apps.codeBadge') >= 0, 'badge code tiers');
      assert(text.indexOf('ui.apps.localVersion') >= 0, 'version locale');
      return assert(text.indexOf('ui.apps.deliveredVersion') >= 0, 'version livrée');
    });
    return it('désactive Appliquer si plan.errors est non vide', function() {
      var app, errEl;
      app = makeApp();
      EH.renderPlan(app, {
        errors: ['version trop ancienne'],
        create: []
      });
      eq(app.el.appsApplyBtn().disabled, true);
      errEl = app.el.appsPlanErrors();
      return assert(!errEl.classList.contains('hidden'), 'erreurs visibles');
    });
  });

  describe('AppAppsHelpers purge', function() {
    it('confirmation désactivée sans aperçu', function() {
      var app;
      app = makeApp();
      app._appPurgeTarget = 'livres';
      EH.refreshPurgeConfirm(app);
      return assert(app.el.appsPurgeConfirmBtn().disabled, 'désactivé sans aperçu');
    });
    it('confirmation activée seulement après aperçu et saisie exacte', function() {
      var app;
      app = makeApp();
      app._appPurgeAppId = 'org.app';
      app._appPurgePreview = {
        keys: ['space:livres']
      };
      EH.renderPurgePreview(app, {
        losses: [
          {
            key: 'space:livres',
            type: 'space',
            records: 3,
            fields: 2,
            relations: 0,
            views: 1
          }
        ],
        totalRecords: 3
      });
      eq(app._appPurgeTarget, 'livres');
      app.el.appsPurgeConfirmInput().value = 'livres';
      EH.refreshPurgeConfirm(app);
      assert(!app.el.appsPurgeConfirmBtn().disabled, 'activé quand la saisie correspond');
      app.el.appsPurgeConfirmInput().value = 'mauvais';
      EH.refreshPurgeConfirm(app);
      return assert(app.el.appsPurgeConfirmBtn().disabled, 'désactivé quand la saisie diffère');
    });
    return it('n’injecte pas de HTML depuis une clé de perte', function() {
      var app, tags;
      app = makeApp();
      app._appPurgeAppId = 'org.app';
      app._appPurgePreview = {
        keys: ['space:x']
      };
      EH.renderPurgePreview(app, {
        losses: [
          {
            key: '<img src=x onerror=alert(1)>',
            type: 'space',
            records: 1,
            fields: 0,
            relations: 0,
            views: 0
          }
        ],
        totalRecords: 1
      });
      tags = collectTags(app.el.appsPurgePreview());
      return assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
    });
  });

  summary();

}).call(this);
