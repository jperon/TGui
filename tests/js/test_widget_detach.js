(function() {
  // tests/js/test_widget_detach.coffee
  // Action « Détacher » d'une instance de widget personnalisé (spec
  // docs/superpowers/specs/2026-11-16-custom-widgets-design.md §4) : le bouton
  // n'est ajouté qu'en édition de page, pour un admin, sur un widget personnalisé
  // (jamais pour « aggregate » / « table », ni pour un widget de données).
  var CV, DataView, PLUGIN, assert, describe, detachButtons, eq, it, makeCV, pluginLayout, summary, syncPlugin;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

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

    mount() {}

    refreshLayout() {}

    deleteSelected() {}

  };

  // Widget personnalisé minimal : javascript + html ne charge aucun compilateur.
  PLUGIN = {
    id: 'p1',
    name: 'sample_plugin',
    scriptLanguage: 'javascript',
    templateLanguage: 'html',
    scriptCode: '',
    templateCode: ''
  };

  syncPlugin = function(plugin) {
    return {
      then: function(cb) {
        return cb(plugin);
      },
      catch: function() {}
    };
  };

  global.WidgetPlugins = {
    getByName: function() {
      return syncPlugin(PLUGIN);
    }
  };

  require('../../frontend/src/views/plugin_runtimes');

  require('../../frontend/src/views/custom_view');

  require('../../frontend/src/views/custom_view_plugins');

  require('../../frontend/src/views/custom_view_aggregate');

  CV = global.window.CustomView;

  makeCV = function(layout, opts = {}) {
    var container, cv;
    container = global.document.createElement('div');
    if (opts.page) {
      container.setAttribute('data-page-id', 'page1');
    }
    cv = new CV(container, JSON.stringify(layout), [], []);
    cv.mount();
    return cv;
  };

  pluginLayout = function(extra = {}) {
    var k, v, widget;
    widget = {
      id: 'w_plugin',
      type: 'sample_plugin',
      title: 'Plugin'
    };
    for (k in extra) {
      v = extra[k];
      widget[k] = v;
    }
    return {
      layout: {widget}
    };
  };

  // Boutons « Détacher » de la barre de titre du premier widget monté.
  detachButtons = function(cv) {
    var el, i, len, ref, ref1, results, titleBar, wrapper;
    wrapper = (ref = cv._widgets[0]) != null ? ref.el : void 0;
    if (!wrapper) {
      return [];
    }
    titleBar = wrapper.children[0];
    if (!titleBar) {
      return [];
    }
    ref1 = titleBar.children;
    results = [];
    for (i = 0, len = ref1.length; i < len; i++) {
      el = ref1[i];
      if (el.classList.contains('cv-widget-detach-btn')) {
        results.push(el);
      }
    }
    return results;
  };

  describe('CustomView — action Détacher', function() {
    it('ajoute le bouton en édition de page pour un admin', function() {
      var btns, cv;
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      cv = makeCV(pluginLayout(), {
        page: true
      });
      btns = detachButtons(cv);
      eq(btns.length, 1);
      return eq(btns[0].textContent, 'Détacher');
    });
    it('n’ajoute rien pour un non-admin', function() {
      var cv;
      global.window.Auth = {
        isAdmin: function() {
          return false;
        }
      };
      cv = makeCV(pluginLayout(), {
        page: true
      });
      return eq(detachButtons(cv).length, 0);
    });
    it('n’ajoute rien hors édition de page (aucun id de page)', function() {
      var cv;
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      cv = makeCV(pluginLayout());
      return eq(detachButtons(cv).length, 0);
    });
    it('n’ajoute rien en mode présentation', function() {
      var container, cv;
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      container = global.document.createElement('div');
      container.setAttribute('data-page-id', 'page1');
      cv = new CV(container, JSON.stringify(pluginLayout()), [], [], {
        presentationMode: true
      });
      cv.mount();
      return eq(detachButtons(cv).length, 0);
    });
    it('n’ajoute rien pour un widget fourni par le programme', function() {
      var cv, cv2;
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      cv = makeCV({
        layout: {
          widget: {
            id: 'w_table',
            type: 'table',
            title: 'Tableau'
          }
        }
      }, {
        page: true
      });
      eq(detachButtons(cv).length, 0);
      cv2 = makeCV({
        layout: {
          widget: {
            id: 'w_agg',
            type: 'aggregate',
            title: 'Agrégat'
          }
        }
      }, {
        page: true
      });
      return eq(detachButtons(cv2).length, 0);
    });
    it('n’ajoute rien pour un widget de données (sans type)', function() {
      var cv;
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      cv = makeCV({
        layout: {
          widget: {
            id: 'w_data',
            space: 'personnes'
          }
        }
      }, {
        page: true
      });
      return eq(detachButtons(cv).length, 0);
    });
    return it('canDetachPluginWidget exige page, admin et type personnalisé', function() {
      var cv;
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      cv = makeCV(pluginLayout(), {
        page: true
      });
      eq(cv._canDetachPluginWidget({
        type: 'sample_plugin'
      }), true);
      eq(cv._canDetachPluginWidget({}), false);
      eq(cv._canDetachPluginWidget({
        type: 'aggregate'
      }), false);
      global.window.Auth = {
        isAdmin: function() {
          return false;
        }
      };
      return eq(cv._canDetachPluginWidget({
        type: 'sample_plugin'
      }), false);
    });
  });

  summary();

}).call(this);
