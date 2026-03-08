(function() {
  // tests/js/test_custom_view.coffee — tests pour CustomView (custom_view.js)
  // Teste : parsing YAML, structure du DOM produit, factor flex, filtrage colonnes, depends_on.
  var CV, DataView, assert, deepEq, describe, eq, it, makeContainer, makeSpaces, summary, yamlJSON;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // --- stubs ------------------------------------------------------------------
  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src); // les YAML de test seront du JSON valide
    }
  };

  global.DataView = DataView = class DataView {
    constructor(container, space) {
      this.container = container;
      this.space = space;
      this._currentData = {};
      this.mounted = false;
    }

    mount() {
      return this.mounted = true;
    }

    refreshLayout() {}

    setFilter() {}

    setDefaultValues() {}

    deleteSelected() {}

  };

  // Chargement du module sous test (expose window.CustomView)
  require('../../frontend/src/views/custom_view');

  CV = global.window.CustomView;

  // --- helper -----------------------------------------------------------------
  makeSpaces = function() {
    return [
      {
        id: '1',
        name: 'personnes',
        fields: [
          {
            id: 'f1',
            name: 'nom',
            fieldType: 'Str'
          },
          {
            id: 'f2',
            name: 'age',
            fieldType: 'Int'
          },
          {
            id: 'f3',
            name: 'ville',
            fieldType: 'Str'
          }
        ]
      },
      {
        id: '2',
        name: 'groupes',
        fields: [
          {
            id: 'g1',
            name: 'titre',
            fieldType: 'Str'
          },
          {
            id: 'g2',
            name: 'code',
            fieldType: 'Str'
          }
        ]
      }
    ];
  };

  makeContainer = function() {
    return global.document.createElement('div');
  };

  yamlJSON = function(obj) {
    return JSON.stringify(obj);
  };

  // ---------------------------------------------------------------------------
  describe('CustomView — layout vertical simple', function() {
    it('monte un widget sans erreur', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            id: 'w1',
            title: 'Gens',
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets.length, 1);
      return assert(cv._widgets[0].dataView.mounted, 'DataView doit être monté');
    });
    it('_widgetsById indexé par id', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            id: 'mon_widget',
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return assert(cv._widgetsById['mon_widget'] != null, 'index par id');
    });
    return it('espace introuvable → dataView null', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'inexistant'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets[0].dataView, null);
    });
  });

  describe('CustomView — zone avec enfants', function() {
    return it('crée un enfant par widget enfant', function() {
      var cv, layout;
      layout = {
        layout: {
          direction: 'horizontal',
          children: [
            {
              widget: {
                space: 'personnes'
              }
            },
            {
              widget: {
                space: 'groupes'
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets.length, 2);
    });
  });

  describe('CustomView — factor', function() {
    it('applique factor comme flex', function() {
      var cv, entries, layout;
      layout = {
        layout: {
          direction: 'vertical',
          children: [
            {
              factor: 3,
              widget: {
                space: 'personnes'
              }
            },
            {
              factor: 1,
              widget: {
                space: 'groupes'
              }
            }
          ]
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      // Le container principal a flex appliqué par _renderZoneOrWidget (nœud racine)
      // Les enfants ont leur flex dans l'élément rendu
      entries = cv._widgets;
      eq(entries[0].el.style.flex, '3');
      return eq(entries[1].el.style.flex, '1');
    });
    return it('factor absent → flex par défaut à "1"', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets[0].el.style.flex, '1');
    });
  });

  describe('CustomView — columns', function() {
    it('filtre les colonnes spécifiées', function() {
      var cv, dv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes',
            columns: ['age', 'nom']
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      dv = cv._widgets[0].dataView;
      eq(dv.space.fields.length, 2);
      eq(dv.space.fields[0].name, 'age');
      return eq(dv.space.fields[1].name, 'nom');
    });
    it('ignore les colonnes inconnues silencieusement', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes',
            columns: ['nom', 'inconnu']
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets[0].dataView.space.fields.length, 1);
      return eq(cv._widgets[0].dataView.space.fields[0].name, 'nom');
    });
    it('sans columns → tous les champs', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      return eq(cv._widgets[0].dataView.space.fields.length, 3);
    });
    return it('ne modifie pas l\'espace original (clone)', function() {
      var cv, layout, spaces;
      spaces = makeSpaces();
      layout = {
        layout: {
          widget: {
            space: 'personnes',
            columns: ['nom']
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), spaces);
      cv.mount();
      return eq(spaces[0].fields.length, 3); // original inchangé
    });
  });

  describe('CustomView — YAML invalide', function() {
    return it('affiche une erreur sans lever d\'exception', function() {
      var badYaml, cv;
      badYaml = '{ not valid json !!!!';
      global.jsyaml.load = function(s) {
        throw new Error('YAML parse error');
      };
      cv = new CV(makeContainer(), badYaml, makeSpaces());
      cv.mount();
      eq(cv._widgets.length, 0);
      return global.jsyaml.load = function(s) {
        return JSON.parse(s); // restore
      };
    });
  });

  describe('CustomView — unmount', function() {
    return it('vide _widgets et _widgetsById', function() {
      var cv, layout;
      layout = {
        layout: {
          widget: {
            id: 'w',
            space: 'personnes'
          }
        }
      };
      cv = new CV(makeContainer(), yamlJSON(layout), makeSpaces());
      cv.mount();
      eq(cv._widgets.length, 1);
      cv.unmount();
      eq(cv._widgets.length, 0);
      return eq(Object.keys(cv._widgetsById).length, 0);
    });
  });

  summary();

}).call(this);
