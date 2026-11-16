(function() {
  // tests/js/test_custom_view_widget_menu.coffee
  // Menu « Trier / Filtrer » d'un widget de page : il ne doit PAS être attaché
  // quand la source du widget est une Data View. `_findSpace` renvoie alors
  // `{ id: <id de la data view>, isView: true }` ; cet id n'est pas un espace et
  // `saveViewPreset` le refuse (« Space not found »).
  var CV, DataView, SOURCE, VIEW, assert, attachCalls, deepEq, describe, eq, it, makePage, makeReadOnly, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    }
  };

  attachCalls = [];

  global.window.ViewPresetsMenu = {
    attach: function(wrap, opts) {
      attachCalls.push(opts);
      return {
        destroy: function() {}
      };
    }
  };

  global.DataView = DataView = class DataView {
    constructor(container1, space) {
      this.container = container1;
      this.space = space;
      this.mounted = false;
    }

    mount() {
      return this.mounted = true;
    }

    refreshLayout() {}

    unmount() {}

    deleteSelected() {}

  };

  require('../../frontend/src/views/custom_view');

  CV = global.window.CustomView;

  SOURCE = {
    id: 'sp-1',
    name: 'Emprunts',
    fields: [
      {
        name: 'lecteur',
        fieldType: 'Str'
      },
      {
        name: 'montant',
        fieldType: 'Int'
      }
    ]
  };

  VIEW = {
    id: 'dv-1',
    name: 'Vue emprunts',
    sourceSpace: 'sp-1',
    config: JSON.stringify({
      columns: ['lecteur', 'montant']
    })
  };

  // Page éditable : c'est `data-page-id` qui autorise le menu des widgets.
  makePage = function(layout, spaces = [SOURCE], views = []) {
    var container, cv;
    container = global.document.createElement('div');
    container.setAttribute('data-page-id', 'page1');
    cv = new CV(container, JSON.stringify(layout), spaces, views);
    cv.mount();
    return cv;
  };

  // Sans page (lecture seule), le menu n'est jamais attaché non plus.
  makeReadOnly = function(layout) {
    var cv;
    cv = new CV(global.document.createElement('div'), JSON.stringify(layout), [SOURCE], []);
    cv.mount();
    return cv;
  };

  describe('CustomView — menu de widget et Data View', function() {
    it('n’attache pas le menu quand la source du widget est une Data View', function() {
      var cv, layout;
      attachCalls = [];
      layout = {
        layout: {
          widget: {
            id: 'w1',
            space: 'Vue emprunts'
          }
        }
      };
      cv = makePage(layout, [SOURCE], [VIEW]);
      eq(cv._widgets.length, 1);
      assert(cv._widgets[0].dataView.space.isView, 'la source doit être une vue');
      return eq(attachCalls.length, 0);
    });
    it('attache le menu pour un widget sur un vrai espace', function() {
      var layout;
      attachCalls = [];
      layout = {
        layout: {
          widget: {
            id: 'w2',
            space: 'Emprunts'
          }
        }
      };
      makePage(layout);
      eq(attachCalls.length, 1);
      eq(attachCalls[0].scope, 'widget:page1:w2');
      return eq(attachCalls[0].spaceId, 'sp-1');
    });
    return it('n’attache rien hors page éditable', function() {
      var layout;
      attachCalls = [];
      layout = {
        layout: {
          widget: {
            id: 'w3',
            space: 'Emprunts'
          }
        }
      };
      makeReadOnly(layout);
      return eq(attachCalls.length, 0);
    });
  });

  summary();

}).call(this);
