(function() {
  // tests/js/test_yaml_builder.coffee — tests pour YamlBuilder (yaml_builder.js)
  // Teste : génération YAML, clic champ, clic en-tête (aggregate), badges, dépendances.
  var YB, assert, deepEq, describe, eq, it, makeContainer, makeRelations, makeSpaces, makeYB, summary,
    indexOf = [].indexOf;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // --- stubs ------------------------------------------------------------------
  global.jsyaml = {
    dump: function(obj) {
      return JSON.stringify(obj); // simplifie les comparaisons
    }
  };

  
  // Chargement du module sous test (expose window.YamlBuilder)
  require('../../frontend/src/yaml_builder');

  YB = global.window.YamlBuilder;

  // --- helpers ----------------------------------------------------------------
  makeSpaces = function() {
    return [
      {
        id: 'sp1',
        name: 'personnes',
        fields: [
          {
            id: 'f_nom',
            name: 'nom',
            fieldType: 'String'
          },
          {
            id: 'f_prenom',
            name: 'prenom',
            fieldType: 'String'
          },
          {
            id: 'f_age',
            name: 'age',
            fieldType: 'Int'
          }
        ]
      },
      {
        id: 'sp2',
        name: 'commandes',
        fields: [
          {
            id: 'f_client',
            name: 'client_id',
            fieldType: 'Int'
          },
          {
            id: 'f_total',
            name: 'total',
            fieldType: 'Int'
          }
        ]
      }
    ];
  };

  makeRelations = function() {
    return [
      {
        id: 'r1',
        fromSpaceId: 'sp2',
        fromFieldId: 'f_client',
        toSpaceId: 'sp1',
        toFieldId: 'f_nom'
      }
    ];
  };

  makeContainer = function() {
    return global.document.createElement('div');
  };

  makeYB = function(opts = {}) {
    var yb;
    yb = new YB({
      container: makeContainer(),
      allSpaces: opts.spaces || makeSpaces(),
      allRelations: opts.relations || [],
      onChange: opts.onChange || function() {}
    });
    yb._render = function() {}; // no-op: tests d'état uniquement, pas de DOM SVG
    return yb;
  };

  // --- YamlBuilder : état initial ---------------------------------------------
  describe('YamlBuilder — initial', function() {
    it('pas de widgets au démarrage', function() {
      var yb;
      yb = makeYB();
      return eq(yb._widgets.length, 0);
    });
    return it('toYaml() vide retourne squelette', function() {
      var yaml, yb;
      yb = makeYB();
      yaml = yb.toYaml();
      assert(yaml.indexOf('layout') !== -1, 'contient layout');
      return assert(yaml.indexOf('children') !== -1, 'contient children');
    });
  });

  // --- YamlBuilder : clic champ -----------------------------------------------
  describe('YamlBuilder — clic champ', function() {
    it('ajouter un champ crée un widget régulier', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      eq(yb._widgets.length, 1);
      eq(yb._widgets[0].spaceName, 'personnes');
      eq(yb._widgets[0].columns.length, 1);
      return eq(yb._widgets[0].columns[0], 'nom');
    });
    it('clic * crée un widget sans restriction de colonnes', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', '*');
      eq(yb._widgets[0].columns.length, 0);
      return assert(yb._widgets[0].type !== 'aggregate', 'widget régulier, pas agrégat');
    });
    it('reclic * en mode all-columns supprime le widget', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', '*');
      yb._onFieldClick('sp1', '*');
      return eq(yb._widgets.length, 0);
    });
    it('reclic même champ le retire', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      yb._onFieldClick('sp1', 'nom');
      return eq(yb._widgets.length, 0);
    });
    return it('plusieurs champs dans un même widget', function() {
      var yb;
      yb = makeYB();
      yb._onFieldClick('sp1', 'nom');
      yb._onFieldClick('sp1', 'age');
      eq(yb._widgets.length, 1);
      return eq(yb._widgets[0].columns.length, 2);
    });
  });

  // --- YamlBuilder : clic en-tête (aggregate) ---------------------------------
  describe('YamlBuilder — clic en-tête (aggregate)', function() {
    it('crée un widget de type aggregate', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      eq(yb._widgets.length, 1);
      eq(yb._widgets[0].type, 'aggregate');
      return eq(yb._widgets[0].spaceName, 'personnes');
    });
    it('groupBy contient tous les champs (pas de FK pour sp1)', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      return deepEq(yb._widgets[0].groupBy, [
        'age',
        'nom',
        'prenom' // alphabetical
      ]);
    });
    it('groupBy exclut les champs FK', function() {
      var yb;
      yb = makeYB({
        spaces: makeSpaces(),
        relations: makeRelations()
      });
      yb._onHeaderClick('sp2');
      // client_id est FK → exclus ; seul total reste
      return deepEq(yb._widgets[0].groupBy, ['total']);
    });
    it('deuxième clic en-tête supprime le widget agrégat', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      yb._onHeaderClick('sp1');
      return eq(yb._widgets.length, 0);
    });
    it('widget agrégat et widget régulier peuvent coexister', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1'); // aggregate
      yb._onFieldClick('sp2', 'total'); // regular
      eq(yb._widgets.length, 2);
      eq((yb._widgets.filter(function(w) {
        return w.type === 'aggregate';
      })).length, 1);
      return eq((yb._widgets.filter(function(w) {
        return w.type !== 'aggregate';
      })).length, 1);
    });
    return it('_widgetForSpace n\'est pas sensible aux widgets agrégats', function() {
      var yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      assert(!yb._widgetForSpace('sp1'), 'pas de widget régulier pour sp1');
      return assert(yb._aggWidgetForSpace('sp1'), 'widget agrégat présent');
    });
  });

  // --- YamlBuilder : toYaml avec aggregate ------------------------------------
  describe('YamlBuilder — toYaml aggregate', function() {
    it('génère type:aggregate avec groupBy', function() {
      var parsed, ref, wObj, yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      parsed = JSON.parse(yb.toYaml());
      wObj = parsed.layout.children[0].widget;
      eq(wObj.type, 'aggregate');
      eq(wObj.space, 'personnes');
      assert(Array.isArray(wObj.groupBy), 'groupBy est un tableau');
      assert(((ref = wObj.aggregate) != null ? ref.length : void 0) > 0, 'aggregate a au moins une entrée');
      return eq(wObj.aggregate[0].fn, 'count');
    });
    return it('génère le widget régulier correctement en présence d\'un agrégat', function() {
      var parsed, types, yb;
      yb = makeYB();
      yb._onHeaderClick('sp1');
      yb._onFieldClick('sp2', 'total');
      parsed = JSON.parse(yb.toYaml());
      eq(parsed.layout.children.length, 2);
      types = parsed.layout.children.map(function(c) {
        return c.widget.type;
      });
      return assert(indexOf.call(types, 'aggregate') >= 0, 'agrégat présent');
    });
  });

  // --- YamlBuilder : depends_on automatique -----------------------------------
  describe('YamlBuilder — depends_on', function() {
    return it('détecte FK et génère depends_on', function() {
      var child, yb;
      yb = makeYB({
        spaces: makeSpaces(),
        relations: makeRelations()
      });
      yb._onFieldClick('sp1', 'nom'); // parent
      yb._onFieldClick('sp2', 'total'); // enfant (a FK vers sp1)
      child = yb._widgets[1];
      assert(child.dependsOn != null, 'depends_on détecté');
      return eq(child.dependsOn.field, 'client_id');
    });
  });

  summary();

}).call(this);
