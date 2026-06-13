(function() {
  // tests/js/test_view_helpers.coffee
  // Régression pour AppViewHelpers.renderCustomViewPreview.

  // Bug historique : renderCustomViewPreview construisait un CustomView mais
  // n'appelait jamais mount() et ne retirait pas la classe 'hidden' du conteneur
  // #custom-view-container — toute page s'ouvrait donc vide. Les tests unitaires
  // de CustomView appelaient mount() eux-mêmes et ne couvraient pas cet appelant.
  var AVH, CustomView, assert, describe, eq, it, lastCtorArgs, makeApp, mountCalls, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  // Stub global jsyaml (non utilisé ici mais requis au chargement éventuel)
  global.jsyaml = {
    load: function(s) {
      return JSON.parse(s);
    }
  };

  // Stub CustomView : enregistre les appels à mount()
  mountCalls = 0;

  lastCtorArgs = null;

  global.window.CustomView = CustomView = class CustomView {
    constructor(container1, yamlText, allSpaces, allDataViews) {
      this.container = container1;
      this.yamlText = yamlText;
      this.allSpaces = allSpaces;
      this.allDataViews = allDataViews;
      lastCtorArgs = {container: this.container, yamlText: this.yamlText, allSpaces: this.allSpaces, allDataViews: this.allDataViews};
    }

    mount() {
      return mountCalls++;
    }

    unmount() {}

  };

  global.CustomView = global.window.CustomView;

  // Pas de DragDropManager dans l'environnement de test (branche ignorée)
  delete global.DragDropManager;

  // Charge le module sous test (définit window.AppViewHelpers)
  require('../../frontend/src/app_view_helpers');

  AVH = global.window.AppViewHelpers;

  // Neutralise les dépendances annexes appelées par renderCustomViewPreview
  AVH._bindZoneEvents = function() {};

  global.window.AppUndoHelpers = {
    refreshUI: function() {}
  };

  // Conteneur #custom-view-container masqué au départ, comme dans index.moon
  makeApp = function() {
    var container;
    container = global.document.createElement('div');
    container.classList.add('hidden');
    return {
      el: {
        customViewContainer: function() {
          return container;
        }
      },
      _allSpaces: [],
      _allDataViews: [],
      _currentCustomView: null, // ignore la branche DragDropManager
      _activeCustomView: null
    };
  };

  describe('AppViewHelpers.renderCustomViewPreview', function() {
    it('appelle mount() sur le CustomView créé', function() {
      var app;
      mountCalls = 0;
      app = makeApp();
      AVH.renderCustomViewPreview(app, '{"layout":{"children":[]}}');
      eq(mountCalls, 1);
      return assert(app._activeCustomView != null, '_activeCustomView doit être défini');
    });
    it('retire la classe hidden du conteneur d’aperçu', function() {
      var app, container;
      app = makeApp();
      container = app.el.customViewContainer();
      assert(container.classList.contains('hidden'), 'pré-condition : caché');
      AVH.renderCustomViewPreview(app, '{"layout":{"children":[]}}');
      return assert(!container.classList.contains('hidden'), 'le conteneur doit être visible');
    });
    return it('transmet le YAML et les espaces au CustomView', function() {
      var app;
      app = makeApp();
      app._allSpaces = [
        {
          id: '1',
          name: 'livres'
        }
      ];
      AVH.renderCustomViewPreview(app, '{"layout":{"children":[]}}');
      return eq(lastCtorArgs.allSpaces.length, 1);
    });
  });

  summary();

}).call(this);
