(function() {
  // tests/js/test_widget_relay_header.coffee
  // Le relais des requêtes d'un widget (custom_view_plugins.coffee) doit passer
  // par GQL.queryWidget, c'est-à-dire envoyer l'en-tête `X-TDB-Widget`. Le
  // serveur n'autorise alors que les lectures et les mutations d'enregistrements
  // de données (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md
  // §6) ; l'iframe sandboxée n'a ni jeton ni accès HTTP direct, elle ne peut donc
  // pas contourner la restriction.
  var G, assert, describe, eq, it, localStorageStub, relayed, summary;

  ({localStorageStub} = require('./dom_stub'));

  ({describe, it, eq, assert, summary} = require('./runner'));

  localStorageStub.clear();

  require('../../frontend/src/graphql_client');

  G = global.window.GQL;

  describe('GQL.queryWidget', function() {
    it('envoie l’en-tête X-TDB-Widget', function() {
      var sent;
      sent = null;
      global.fetch = function(url, opts) {
        sent = opts.headers;
        return Promise.resolve({
          json: function() {
            return Promise.resolve({
              data: {
                ok: true
              }
            });
          }
        });
      };
      G.setToken('tok42');
      return G.queryWidget('query { spaces { id } }', {
        a: 1
      }).then(function() {
        var ref;
        eq(sent['X-TDB-Widget'], '1');
        assert((ref = sent['Authorization']) != null ? ref.includes('tok42') : void 0, 'jeton attendu avec widgetQuery');
        return G.setToken(null);
      });
    });
    return it('GQL.query simple n’envoie pas l’en-tête widget', function() {
      var sent;
      sent = null;
      global.fetch = function(url, opts) {
        sent = opts.headers;
        return Promise.resolve({
          json: function() {
            return Promise.resolve({
              data: {}
            });
          }
        });
      };
      G.setToken(null);
      return G.query('query { spaces { id } }').then(function() {
        return assert(sent['X-TDB-Widget'] === void 0, 'en-tête widget inattendu');
      });
    });
  });

  // Le relais lui-même : custom_view_plugins étend CustomView par son prototype.
  global.window.CustomView = function() {
    return null;
  };

  relayed = [];

  global.GQL = {
    query: function() {
      return Promise.resolve({});
    },
    queryWidget: function(q, v) {
      relayed.push({
        query: q,
        variables: v
      });
      return Promise.resolve({
        data: {}
      });
    }
  };

  require('../../frontend/src/views/custom_view_plugins');

  describe('CustomView._relayWidgetQuery', function() {
    it('passe par GQL.queryWidget (en-tête widget), jamais GQL.query', function() {
      var fn;
      fn = global.window.CustomView.prototype._relayWidgetQuery;
      eq(typeof fn, 'function');
      fn.call({}, 'query { spaces { id } }', {
        x: 2
      });
      eq(relayed.length, 1);
      eq(relayed[0].query, 'query { spaces { id } }');
      return eq(relayed[0].variables.x, 2);
    });
    return it('remplace des variables absentes par un objet vide', function() {
      var fn;
      fn = global.window.CustomView.prototype._relayWidgetQuery;
      fn.call({}, 'query { me { id } }', null);
      eq(relayed.length, 2);
      return eq(typeof relayed[1].variables, 'object');
    });
  });

  summary();

}).call(this);
