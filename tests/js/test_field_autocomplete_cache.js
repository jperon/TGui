(function() {
  // tests/js/test_field_autocomplete_cache.coffee
  // Cache du module d'autocomplétion (filtre « λ ») :
  //  - une entrée dont le chargement échoue est retirée du cache (nouvel essai) ;
  //  - l'échec ne produit pas de rejet non géré et ferme la liste ;
  //  - une modification du schéma invalide le cache (syncSpaceFields).

  // Fichier séparé : ces tests pilotent un état de stub (échecs, compteurs) qui ne
  // doit pas interférer avec les tests de résolution de test_field_autocomplete.coffee.
  // Chaque test utilise son propre espace : les corps de `it` démarrent tous avant
  // la résolution des promesses, donc un drapeau global partagé les contaminerait.
  var FA, FAILING, RELS, SPACES, assert, calls, countFetches, deepEq, describe, eq, fire, flush, it, makeDv, makeInput, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  calls = {
    getIds: []
  };

  FAILING = {}; // id -> échec au prochain chargement (une seule fois)

  SPACES = {
    's1': {
      id: 's1',
      fields: [
        {
          id: 'f1',
          name: 'eleve',
          fieldType: 'Relation'
        }
      ]
    },
    's2': {
      id: 's2',
      fields: [
        {
          id: 'g1',
          name: 'niveau',
          fieldType: 'String'
        }
      ]
    },
    's6': {
      id: 's6',
      fields: [
        {
          id: 'i1',
          name: 'cache_field',
          fieldType: 'String'
        }
      ]
    },
    's8': {
      id: 's8',
      fields: [
        {
          id: 'j1',
          name: 'autre_cache',
          fieldType: 'String'
        }
      ]
    }
  };

  RELS = {
    's1': [
      {
        id: 'r1',
        fromFieldId: 'f1',
        toSpaceId: 's2'
      }
    ],
    's2': []
  };

  global.Spaces = {
    getWithFields: function(id) {
      calls.getIds.push(id);
      if (FAILING[id]) {
        FAILING[id] = false;
        return Promise.reject(new Error(`chargement impossible : ${id}`));
      }
      return Promise.resolve(SPACES[id]);
    },
    listRelations: function(id) {
      return Promise.resolve(RELS[id] || []);
    }
  };

  require('../../frontend/src/views/field_autocomplete');

  FA = global.window.FieldAutocomplete;

  makeDv = function() {
    return {
      space: {
        id: 's1',
        fields: [
          {
            id: 'f1',
            name: 'eleve',
            fieldType: 'Relation'
          }
        ]
      }
    };
  };

  flush = function() {
    return new Promise(function(r) {
      return setTimeout(r, 0);
    });
  };

  makeInput = function(value) {
    var el;
    el = global.document.createElement('input');
    el.value = value;
    el.selectionStart = value.length;
    el.selectionEnd = value.length;
    el.dispatchEvent = function(ev) {
      var fn, i, len, ref, results;
      ref = el._listeners[ev.type] || [];
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        fn = ref[i];
        results.push(fn(ev));
      }
      return results;
    };
    return el;
  };

  fire = function(el, type, ev = {}) {
    var fn, i, len, ref;
    ev.type = type;
    if (ev.preventDefault == null) {
      ev.preventDefault = function() {};
    }
    ref = el._listeners[type] || [];
    for (i = 0, len = ref.length; i < len; i++) {
      fn = ref[i];
      fn(ev);
    }
    return ev;
  };

  countFetches = function(id) {
    return calls.getIds.filter(function(x) {
      return x === id;
    }).length;
  };

  describe('FieldAutocomplete — cache et invalidation', function() {
    it('oublie une entrée dont le chargement a échoué (nouvel essai possible)', async function() {
      var before, e, err, f, res;
      before = countFetches('s6');
      FAILING.s6 = true;
      err = null;
      try {
        await FA._resolve({
          space: {
            id: 's6'
          }
        }, []);
      } catch (error) {
        e = error;
        err = e;
      }
      assert(err != null, 'un échec de chargement doit être propagé');
      eq(countFetches('s6') - before, 1);
      // Le cache ne doit pas garder la promesse rejetée : deuxième essai relancé.
      res = (await FA._resolve({
        space: {
          id: 's6'
        }
      }, []));
      deepEq((function() {
        var i, len, ref, results;
        ref = res.fields;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          f = ref[i];
          results.push(f.name);
        }
        return results;
      })(), ['cache_field']);
      return eq(countFetches('s6') - before, 2);
    });
    it('_reset vide les caches', async function() {
      var before;
      before = countFetches('s8');
      await FA._resolve({
        space: {
          id: 's8'
        }
      }, []);
      await FA._resolve({
        space: {
          id: 's8'
        }
      }, []);
      eq(countFetches('s8') - before, 1);
      FA._reset();
      await FA._resolve({
        space: {
          id: 's8'
        }
      }, []);
      return eq(countFetches('s8') - before, 2);
    });
    it('ne laisse pas de rejet non géré et ferme la liste quand la résolution échoue', async function() {
      var body, handler, input, unhandled;
      FAILING.s1 = true;
      unhandled = [];
      handler = function(reason) {
        return unhandled.push(reason);
      };
      process.on('unhandledRejection', handler);
      body = global.document.body = global.document.createElement('body');
      input = makeInput('@ele');
      FA.attach(input, function() {
        return makeDv();
      });
      fire(input, 'input');
      await flush();
      await flush();
      process.removeListener('unhandledRejection', handler);
      eq(unhandled.length, 0);
      return eq(body.children.length, 0); // aucune liste fantôme
    });
    return it('syncSpaceFields vide le cache de l’autocomplétion', function() {
      var app, realReset, resets;
      require('../../frontend/src/app_data_helpers');
      resets = 0;
      realReset = FA._reset;
      FA._reset = function() {
        return resets++;
      };
      app = {
        _allSpaces: [],
        _activeCustomView: null,
        _currentCustomView: null
      };
      try {
        global.window.AppDataHelpers.syncSpaceFields(app, {
          id: 's1',
          name: 's1'
        });
      } finally {
        FA._reset = realReset;
      }
      return eq(resets, 1);
    });
  });

  summary();

}).call(this);
