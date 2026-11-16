(function() {
  // tests/js/test_page_widget_filter_focus.coffee — focus du champ λ d'un widget de page.
  // SortableJS a `preventOnFilter: true` par défaut : au mousedown sur un élément
  // filtré il appelle preventDefault(), ce qui empêche l'input de prendre le focus.
  // La zone du filtre λ d'un widget porte la classe `no-drag` (donc filtrée) :
  // toute configuration Sortable dont le filtre est `.no-drag` doit désactiver
  // `preventOnFilter`, sinon le clic dans le champ ne place jamais le curseur.
  var CV, DataView, PAGE_LAYOUT, SPACES, Sortable, assert, assertNoDragConfigsSafe, describe, eq, it, makePage, makeZoneContainer, noDragConfigs, resetConfigs, sortableConfigs, summary, tick;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  // Interception du constructeur Sortable : chaque configuration est conservée.
  sortableConfigs = [];

  resetConfigs = function() {
    return sortableConfigs = [];
  };

  global.Sortable = Sortable = class Sortable {
    constructor(el, opts) {
      this.el = el;
      this.opts = opts || {};
      sortableConfigs.push(this.opts);
    }

    option(key, value) {
      if (value !== void 0) {
        this.opts[key] = value;
      }
      return this.opts[key];
    }

    destroy() {}

  };

  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    }
  };

  global.DataView = DataView = class DataView {
    constructor(container1, space) {
      this.container = container1;
      this.space = space;
    }

    mount() {
      return Promise.resolve();
    }

    refreshLayout() {}

    unmount() {}

    deleteSelected() {}

  };

  require('../../frontend/src/drag_drop_manager');

  // dom_stub fait de `window` un objet distinct de `global` : exposer la classe
  // comme global, comme le fait le navigateur avec `window.DragDropManager`.
  global.DragDropManager = global.window.DragDropManager;

  require('../../frontend/src/views/custom_view');

  CV = global.window.CustomView;

  SPACES = [
    {
      id: 'sp-1',
      name: 'Emprunts',
      fields: [
        {
          id: 'f1',
          name: 'lecteur',
          fieldType: 'Str'
        }
      ]
    }
  ];

  PAGE_LAYOUT = {
    layout: {
      widget: {
        id: 'w1',
        space: 'Emprunts'
      }
    }
  };

  tick = function() {
    return new Promise(function(resolve) {
      return setTimeout(resolve, 0);
    });
  };

  makePage = function(layout = PAGE_LAYOUT) {
    var container, cv;
    container = global.document.createElement('div');
    container.setAttribute('data-page-id', 'page1');
    cv = new CV(container, JSON.stringify(layout), SPACES);
    cv.mount();
    return cv;
  };

  // Toutes les configurations Sortable qui filtrent `.no-drag`.
  noDragConfigs = function() {
    return sortableConfigs.filter(function(o) {
      return o.filter === '.no-drag';
    });
  };

  assertNoDragConfigsSafe = function(label) {
    var configs, i, j, len, opts;
    configs = noDragConfigs();
    assert(configs.length > 0, `${label} : aucune configuration Sortable avec filter '.no-drag'`);
    for (i = j = 0, len = configs.length; j < len; i = ++j) {
      opts = configs[i];
      assert(opts.preventOnFilter === false, `${label} : configuration Sortable #${i} filtre '.no-drag' sans preventOnFilter: false (reçu ${opts.preventOnFilter})`);
    }
    return configs.length;
  };

  // Container dont querySelectorAll renvoie une zone : scanZones() instancie alors
  // une seconde Sortable (config des zones).
  makeZoneContainer = function() {
    var container, zone;
    container = global.document.createElement('div');
    zone = global.document.createElement('div');
    zone.setAttribute('data-zone-id', 'zone1');
    container.querySelectorAll = function(sel) {
      if (sel === '[data-zone-id]') {
        return [zone];
      } else {
        return [];
      }
    };
    return container;
  };

  describe('Champ λ d’un widget de page — focus et Sortable preventOnFilter', function() {
    it('désactive preventOnFilter sur la configuration racine de DragDropManager', function() {
      resetConfigs();
      new global.window.DragDropManager(makeZoneContainer(), {
        pageId: 'page1'
      });
      return eq(assertNoDragConfigsSafe('DragDropManager racine'), 2);
    });
    it('désactive preventOnFilter sur les deux configurations (racine et zone)', function() {
      var handles;
      resetConfigs();
      new global.window.DragDropManager(makeZoneContainer(), {
        pageId: 'page1'
      });
      handles = sortableConfigs.map(function(o) {
        return o.handle;
      });
      eq(handles.length, 2);
      eq(handles[0], '.widget-header');
      eq(handles[1], '.widget-header');
      return assert(sortableConfigs.every(function(o) {
        return o.preventOnFilter === false;
      }), 'toutes les configurations Sortable doivent désactiver preventOnFilter');
    });
    it('désactive preventOnFilter pour la configuration créée par le montage d’une page', async function() {
      var cv;
      resetConfigs();
      cv = makePage();
      await tick();
      assert(cv._dragDropManager != null, 'un DragDropManager est attendu pour une page éditable');
      return eq(assertNoDragConfigsSafe('montage de page'), 1);
    });
    return it('conserve preventOnFilter: false après un aller-retour en mode présentation', async function() {
      var cv;
      resetConfigs();
      cv = makePage();
      await tick();
      cv.togglePresentationMode();
      eq(cv._dragDropManager, null);
      resetConfigs();
      cv.togglePresentationMode();
      assert(cv._dragDropManager != null, 'le DragDropManager doit être recréé en sortie de présentation');
      return eq(assertNoDragConfigsSafe('sortie de mode présentation'), 1);
    });
  });

  summary();

}).call(this);
