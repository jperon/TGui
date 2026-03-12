(function() {
  // tests/js/test_graphql_client.coffee — tests pour GQL (graphql_client.js)
  var G, assert, describe, eq, it, localStorageStub, summary;

  ({localStorageStub} = require('./dom_stub'));

  ({describe, it, eq, assert, summary} = require('./runner'));

  localStorageStub.clear();

  require('../../frontend/src/graphql_client');

  G = global.window.GQL;

  describe('GQL.setToken', function() {
    it('persiste le token dans localStorage', function() {
      G.setToken('abc123');
      eq(localStorageStub.getItem('tdb_token'), 'abc123');
      return eq(G._token, 'abc123');
    });
    return it('clearToken removes token', function() {
      G.setToken('xyz');
      G.clearToken();
      eq(G._token, null);
      return eq(localStorageStub.getItem('tdb_token'), null);
    });
  });

  describe('GQL.loadToken', function() {
    it('restaure le token depuis localStorage', function() {
      localStorageStub.setItem('tdb_token', 'restored');
      G._token = null;
      G.loadToken();
      return eq(G._token, 'restored');
    });
    return it('ne plante pas si localStorage vide', function() {
      localStorageStub.clear();
      G._token = null;
      G.loadToken();
      return eq(G._token, null);
    });
  });

  describe('GQL.query — request body', function() {
    it('sends query and variables as JSON', function() {
      var body;
      body = null;
      global.fetch = function(url, opts) {
        body = JSON.parse(opts.body);
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
      G.setToken(null);
      return G.query('query { me { id } }', {
        x: 1
      }).then(function() {
        eq(body.query, 'query { me { id } }');
        return eq(body.variables.x, 1);
      });
    });
    it('adds Authorization header when token is present', function() {
      var sentHeaders;
      sentHeaders = null;
      global.fetch = function(url, opts) {
        sentHeaders = opts.headers;
        return Promise.resolve({
          json: function() {
            return Promise.resolve({
              data: {}
            });
          }
        });
      };
      G.setToken('tok42');
      return G.query('query { me { id } }').then(function() {
        var ref;
        assert((ref = sentHeaders['Authorization']) != null ? ref.includes('tok42') : void 0, 'missing Authorization');
        return G.setToken(null);
      });
    });
    return it('throws an error when result.errors is non-empty', function() {
      global.fetch = function(url, opts) {
        return Promise.resolve({
          json: function() {
            return Promise.resolve({
              errors: [
                {
                  message: 'not authorized'
                }
              ]
            });
          }
        });
      };
      return G.query('query { me { id } }').then(function() {
        throw new Error('aurait dû rejeter');
      }).catch(function(e) {
        return assert(e.message.includes('not authorized'), `unexpected message: ${e.message}`);
      });
    });
  });

  describe('GQL.mutate', function() {
    return it('delegates to query', function() {
      var called, orig;
      called = null;
      orig = G.query.bind(G);
      G.query = function(q, v) {
        called = {q, v};
        return Promise.resolve({});
      };
      G.mutate('mutation { logout }', {
        a: 1
      });
      eq(called.q, 'mutation { logout }');
      eq(called.v.a, 1);
      return G.query = orig;
    });
  });

  summary();

}).call(this);
