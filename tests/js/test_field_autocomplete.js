(function() {
  // tests/js/test_field_autocomplete.coffee
  // Autocomplete des noms de champs dans le filtre MoonScript ("λ") :
  // détection du jeton, résolution des relations (profondeur quelconque),
  // filtrage par préfixe et insertion.
  var FA, RELS, SPACES, assert, calls, deepEq, describe, eq, fire, flush, it, makeDv, makeInput, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, deepEq, summary} = require('./runner'));

  // Stubs des appels réseau utilisés pour les espaces autres que celui affiché.
  calls = {
    get: 0,
    rels: 0,
    getIds: []
  };

  SPACES = {
    's2': {
      id: 's2',
      fields: [
        {
          id: 'g1',
          name: 'classe',
          fieldType: 'Relation'
        },
        {
          id: 'g2',
          name: 'nom',
          fieldType: 'String'
        },
        {
          id: 'g3',
          name: 'age',
          fieldType: 'Number'
        }
      ]
    },
    's3': {
      id: 's3',
      fields: [
        {
          id: 'h1',
          name: 'niveau',
          fieldType: 'String'
        }
      ]
    },
    // Espaces dédiés au test de cache, non touchés par les autres tests.
    's6': {
      id: 's6',
      fields: [
        {
          id: 'i1',
          name: 'cache_field',
          fieldType: 'String'
        }
      ]
    }
  };

  RELS = {
    's2': [
      {
        id: 'r2',
        fromFieldId: 'g1',
        toSpaceId: 's3'
      }
    ],
    's1': [],
    's5': [
      {
        id: 'r5',
        fromFieldId: 'fc',
        toSpaceId: 's6'
      }
    ],
    's6': []
  };

  global.Spaces = {
    getWithFields: function(id) {
      calls.get++;
      calls.getIds.push(id);
      return Promise.resolve(SPACES[id]);
    },
    listRelations: function(id) {
      calls.rels++;
      return Promise.resolve(RELS[id] || []);
    }
  };

  require('../../frontend/src/views/field_autocomplete');

  FA = global.window.FieldAutocomplete;

  // DataView minimale : espace affiché s1 avec un champ relation `eleve` → s2.
  makeDv = function() {
    return {
      space: {
        id: 's1',
        fields: [
          {
            id: 'f1',
            name: 'eleve',
            fieldType: 'Relation'
          },
          {
            id: 'f2',
            name: 'eleves',
            fieldType: 'Relation'
          },
          {
            id: 'f3',
            name: 'date',
            fieldType: 'Date'
          }
        ]
      },
      _relations: [
        {
          id: 'r1',
          fromFieldId: 'f1',
          toSpaceId: 's2'
        }
      ]
    };
  };

  describe('FieldAutocomplete._token', function() {
    it('détecte un @ seul', function() {
      return deepEq(FA._token('@'), {
        path: [],
        prefix: ''
      });
    });
    it('détecte @eleve.de', function() {
      return deepEq(FA._token('self.x == 1 and @eleve.de'), {
        path: ['eleve'],
        prefix: 'de'
      });
    });
    it('détecte un chemin profond terminé par un point', function() {
      return deepEq(FA._token('@a.b.'), {
        path: ['a', 'b'],
        prefix: ''
      });
    });
    return it('ne détecte rien sans @', function() {
      return eq(FA._token('self.nom'), null);
    });
  });

  describe('FieldAutocomplete._filter', function() {
    var fields;
    fields = [
      {
        name: 'Nom'
      },
      {
        name: 'nombre'
      },
      {
        name: 'date'
      },
      {
        name: 'nom_secours'
      }
    ];
    it('filtre par préfixe sans tenir compte de la casse', function() {
      var f;
      return deepEq((function() {
        var j, len, ref, results;
        ref = FA._filter(fields, 'NO');
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          results.push(f.name);
        }
        return results;
      })(), ['Nom', 'nom_secours', 'nombre']);
    });
    it('renvoie tout, trié, sans préfixe', function() {
      var f;
      return deepEq((function() {
        var j, len, ref, results;
        ref = FA._filter(fields, '');
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          results.push(f.name);
        }
        return results;
      })(), ['date', 'Nom', 'nom_secours', 'nombre']);
    });
    it('renvoie un tableau vide si aucun préfixe ne correspond', function() {
      return deepEq(FA._filter(fields, 'zzz'), []);
    });
    return it('plafonne à 12 entrées', function() {
      var i, many;
      many = (function() {
        var j, results;
        results = [];
        for (i = j = 0; j <= 30; i = ++j) {
          results.push({
            name: `f${i}`
          });
        }
        return results;
      })();
      return eq(FA._filter(many, 'f').length, 12);
    });
  });

  describe('FieldAutocomplete._resolve', function() {
    it('niveau 1 : propose les champs de l\'espace cible', function() {
      return FA._resolve(makeDv(), ['eleve']).then(function(res) {
        var f;
        deepEq((function() {
          var j, len, ref, results;
          ref = res.fields;
          results = [];
          for (j = 0, len = ref.length; j < len; j++) {
            f = ref[j];
            results.push(f.name);
          }
          return results;
        })(), ['classe', 'nom', 'age']);
        return eq(res.relations.length, 1);
      });
    });
    it('niveau 2 : suit la relation de l\'espace cible', function() {
      return FA._resolve(makeDv(), ['eleve', 'classe']).then(function(res) {
        var f;
        return deepEq((function() {
          var j, len, ref, results;
          ref = res.fields;
          results = [];
          for (j = 0, len = ref.length; j < len; j++) {
            f = ref[j];
            results.push(f.name);
          }
          return results;
        })(), ['niveau']);
      });
    });
    it('segment inconnu : aucune proposition', function() {
      return FA._resolve(makeDv(), ['inconnu']).then(function(res) {
        return deepEq(res.fields, []);
      });
    });
    it('champ sans relation : aucune proposition', function() {
      return FA._resolve(makeDv(), ['date', 'x']).then(function(res) {
        return deepEq(res.fields, []);
      });
    });
    return it('met les champs d\'un espace en cache', function() {
      var cacheDv;
      cacheDv = function() {
        return {
          space: {
            id: 's5',
            fields: [
              {
                id: 'fc',
                name: 'ref',
                fieldType: 'Relation'
              }
            ]
          },
          _relations: [
            {
              id: 'r5',
              fromFieldId: 'fc',
              toSpaceId: 's6'
            }
          ]
        };
      };
      FA._reset();
      calls.getIds = [];
      return FA._resolve(cacheDv(), ['ref']).then(function() {
        return FA._resolve(cacheDv(), ['ref']).then(function(res) {
          var f;
          deepEq((function() {
            var j, len, ref, results;
            ref = res.fields;
            results = [];
            for (j = 0, len = ref.length; j < len; j++) {
              f = ref[j];
              results.push(f.name);
            }
            return results;
          })(), ['cache_field']);
          return eq((calls.getIds.filter(function(id) {
            return id === 's6';
          })).length, 1);
        });
      });
    });
  });

  describe('FieldAutocomplete._insert', function() {
    it('remplace le préfixe par le nom et place le curseur après', function() {
      var res;
      res = FA._insert('@eleve.no and 1', 9, {
        name: 'nom'
      });
      eq(res.value, '@eleve.nom and 1');
      return eq(res.caret, 10);
    });
    return it('remplace le jeton entier pour une proposition du premier niveau', function() {
      return deepEq(FA._insert('@da', 3, {
        name: 'date'
      }), {
        value: '@date',
        caret: 5
      });
    });
  });

  // --- intégration attach() : liste ouverte, non vide, insertion par Entrée ------
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
      var fn, j, len, ref, results;
      ref = el._listeners[ev.type] || [];
      results = [];
      for (j = 0, len = ref.length; j < len; j++) {
        fn = ref[j];
        results.push(fn(ev));
      }
      return results;
    };
    return el;
  };

  fire = function(el, type, ev = {}) {
    var fn, j, len, ref;
    ev.type = type;
    if (ev.preventDefault == null) {
      ev.preventDefault = function() {};
    }
    ref = el._listeners[type] || [];
    for (j = 0, len = ref.length; j < len; j++) {
      fn = ref[j];
      fn(ev);
    }
    return ev;
  };

  describe('FieldAutocomplete.attach', function() {
    return it('ouvre une liste non vide, insère au clavier, puis ferme', function() {
      var Event, body, input;
      global.Event = Event = class Event {
        constructor(type1, opts) {
          this.type = type1;
          this.opts = opts;
        }

      };
      body = global.document.body = global.document.createElement('body');
      input = makeInput('@ele');
      FA.attach(input, function() {
        return makeDv();
      });
      fire(input, 'input');
      return flush().then(function() {
        var list;
        list = body.children[0];
        assert(list != null, 'la liste .field-ac doit être attachée à document.body');
        eq(list.className, 'field-ac');
        // `eleve` et `eleves` commencent par « ele », tri alphabétique.
        eq(list.children.length, 2);
        eq(list.children[0].children[0].textContent, '→ eleve');
        fire(input, 'keydown', {
          key: 'Enter'
        });
        eq(input.value, '@eleve');
        eq(body.children.length, 0, 'la liste doit être fermée après insertion');
        // Le jeton disparaît : plus aucune liste.
        input.value = 'self.nom';
        input.selectionStart = input.value.length;
        fire(input, 'input');
        return flush().then(function() {
          return eq(body.children.length, 0, 'aucune liste sans jeton @');
        });
      });
    });
  });

  summary();

}).call(this);
