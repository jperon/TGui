(function() {
  // tests/js/test_widget_scope_label.coffee
  // Portées des widgets personnalisés côté frontend (spec
  // 2026-11-16-custom-widgets-design.md §5) : libellé de portée dans la fenêtre
  // « ＋ Widget », résolution par pageId, et conflits d'import de définition
  // (trois choix, access affiché, nom d'import par défaut).
  var AAH, AVH, WP, assert, describe, document, eq, it, ok, summary;

  require('./dom_stub');

  ({describe, it, eq, ok, assert, summary} = require('./runner'));

  // js-yaml est chargé par la page en production (vendor) ; stub minimal ici.
  global.window.jsyaml = {
    load: function(text) {
      var m;
      if (text.indexOf('[') >= 0) {
        throw new Error('invalid');
      }
      m = text.match(/access:\s*(\w+)/);
      if (m) {
        return {
          access: m[1]
        };
      } else {
        return null;
      }
    }
  };

  global.GQL = {
    query: function(query, variables) {
      if (query.indexOf('widgetPlugin(') >= 0) {
        return Promise.resolve({
          widgetPlugin: {
            name: variables.name,
            appId: null
          }
        });
      } else {
        return Promise.resolve({
          widgetPlugins: []
        });
      }
    },
    mutate: (function() {
      return Promise.resolve({});
    }),
    loadToken: (function() {})
  };

  // Le module sous test étend window.AppViewHelpers (défini ailleurs en prod).
  global.window.AppViewHelpers = {};

  require('../../frontend/src/widget_plugins');

  require('../../frontend/src/app_view_helpers_add_widget');

  require('../../frontend/src/app_apps_helpers');

  WP = global.window.WidgetPlugins;

  AVH = global.window.AppViewHelpers;

  AAH = global.window.AppAppsHelpers;

  document = global.document;

  describe('WidgetPlugins — portée', function() {
    it('libelle la bibliothèque et les apps', function() {
      eq(WP.scopeLabel({
        name: 'a'
      }), 'bibliothèque');
      eq(WP.scopeLabel({
        name: 'a',
        appId: null
      }), 'bibliothèque');
      return eq(WP.scopeLabel({
        name: 'a',
        appId: 'org.exemple.biblio'
      }), 'app org.exemple.biblio');
    });
    // Un seul it : deux it asynchrones s'entrelacent (le runner les lance tous,
    // puis attend les promesses) et se voleraient le stub GQL global.
    return it('transmet pageId à la résolution et à la liste', async function() {
      var saved, seen;
      seen = [];
      saved = global.GQL;
      global.GQL = {
        query: function(query, variables) {
          seen.push({query, variables});
          if (query.indexOf('widgetPlugin(') >= 0) {
            return Promise.resolve({
              widgetPlugin: null
            });
          } else {
            return Promise.resolve({
              widgetPlugins: []
            });
          }
        }
      };
      await WP.getByName('calendrier', 'page-1');
      await WP.list({
        pageId: 'page-1'
      });
      await WP.list({});
      global.GQL = saved;
      eq(seen[0].variables.pageId, 'page-1');
      eq(seen[0].variables.name, 'calendrier');
      eq(seen[1].variables.pageId, 'page-1');
      return eq(seen[2].variables.pageId, void 0);
    });
  });

  describe('Fenêtre ＋ Widget — portée affichée', function() {
    return it('ajoute la portée dans le libellé de l’option', function() {
      var first, list, second;
      list = document.createElement('div');
      list.id = 'widget-type-plugin-list';
      document._setById('widget-type-plugin-list', list);
      AVH._renderWidgetTypePlugins([
        {
          name: 'calendrier',
          description: 'Vue calendrier',
          appId: 'org.exemple.biblio'
        },
        {
          name: 'carte'
        }
      ]);
      first = list._children[0]._children[1];
      assert(first._children[0].classList.contains('widget-type-option-scope'), 'span de portée');
      eq(first._children[0].textContent, ' (app org.exemple.biblio)');
      second = list._children[1]._children[1];
      eq(second._children[0].textContent, ' (bibliothèque)');
      return eq(second._children[0].classList.contains('widget-type-option-scope'), true);
    });
  });

  describe('Import d’app — conflits de définition', function() {
    var conflicts;
    conflicts = [
      {
        key: 'plugin:calendrier',
        type: 'plugin'
      },
      {
        key: 'field:livres.titre',
        type: 'field'
      }
    ];
    it('propose « importer sous un autre nom » par défaut pour une définition', function() {
      var decisions;
      decisions = AAH.buildDecisions(conflicts, {});
      eq(decisions[0].choice, 'rename');
      return eq(decisions[1].choice, 'local');
    });
    it('garde le choix explicite et transmet le nouveau nom', function() {
      var decisions;
      decisions = AAH.buildDecisions(conflicts, {
        'plugin:calendrier': 'rename'
      }, {
        'plugin:calendrier': 'calendrier_bis'
      });
      eq(decisions[0].choice, 'rename');
      return eq(decisions[0].newName, 'calendrier_bis');
    });
    it('n’envoie pas de nouveau nom pour « garder le local »', function() {
      var decisions;
      decisions = AAH.buildDecisions(conflicts, {
        'plugin:calendrier': 'local'
      }, {
        'plugin:calendrier': 'calendrier_bis'
      });
      eq(decisions[0].choice, 'local');
      return eq(decisions[0].newName, void 0);
    });
    it('nom d’import par défaut : <nom>_imported', function() {
      eq(AAH.defaultImportName('plugin:calendrier'), 'calendrier_imported');
      return eq(AAH.defaultImportName('calendrier'), 'calendrier_imported');
    });
    return it('lit l’access effectif du manifest livré', function() {
      eq(AAH.pluginAccessOf({
        manifest: ''
      }), 'full');
      eq(AAH.pluginAccessOf({}), 'full');
      eq(AAH.pluginAccessOf({
        manifest: 'access: read\n'
      }), 'read');
      eq(AAH.pluginAccessOf({
        manifest: 'access: none\n'
      }), 'none');
      eq(AAH.pluginAccessOf({
        manifest: 'access: write\n'
      }), 'read');
      eq(AAH.pluginAccessOf({
        manifest: 'columns: [\n'
      }), 'read');
      return eq(AAH.pluginAccessOf({
        manifest: '# seulement un commentaire\n'
      }), 'full');
    });
  });

  summary();

}).call(this);
