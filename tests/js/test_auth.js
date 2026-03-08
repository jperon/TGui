(function() {
  // tests/js/test_auth.coffee — tests pour Auth (auth.js)
  var A, assert, describe, eq, it, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  global.App = {
    showLogin: function() {}
  };

  global.GQL = {
    _token: null,
    setToken: function(t) {
      return this._token = t;
    },
    clearToken: function() {
      return this._token = null;
    },
    query: function() {
      return Promise.resolve({});
    },
    mutate: function() {
      return Promise.resolve({});
    }
  };

  require('../../frontend/src/auth');

  A = global.window.Auth;

  global.Auth = A; // auth.js référence Auth directement (global navigateur)

  describe('Auth.login', function() {
    it('appelle GQL.mutate avec les bons arguments', function() {
      var captured;
      captured = null;
      GQL.mutate = function(q, v) {
        captured = v;
        return Promise.resolve({
          login: {
            token: 'tok99',
            user: {
              id: '1',
              username: 'alice',
              email: 'a@b.c'
            }
          }
        });
      };
      return A.login('alice', 'secret').then(function() {
        eq(captured != null ? captured.username : void 0, 'alice');
        return eq(captured != null ? captured.password : void 0, 'secret');
      });
    });
    it('retourne l\'utilisateur résolu', function() {
      GQL.mutate = function(q, v) {
        return Promise.resolve({
          login: {
            token: 't',
            user: {
              id: '2',
              username: 'bob',
              email: ''
            }
          }
        });
      };
      return A.login('bob', 'pass').then(function(user) {
        eq(user.username, 'bob');
        return eq(user.id, '2');
      });
    });
    return it('appelle GQL.setToken avec le token reçu', function() {
      var tokReceived;
      tokReceived = null;
      GQL.setToken = function(t) {
        tokReceived = t;
        return GQL._token = t;
      };
      GQL.mutate = function(q, v) {
        return Promise.resolve({
          login: {
            token: 'secret-tok',
            user: {
              id: '3',
              username: 'carol',
              email: ''
            }
          }
        });
      };
      return A.login('carol', 'pw').then(function() {
        return eq(tokReceived, 'secret-tok');
      });
    });
  });

  describe('Auth.restoreSession', function() {
    it('retourne l\'utilisateur si me est défini', function() {
      GQL.query = function() {
        return Promise.resolve({
          me: {
            id: '10',
            username: 'dan',
            email: ''
          }
        });
      };
      return A.restoreSession().then(function(u) {
        return eq(u != null ? u.username : void 0, 'dan');
      });
    });
    it('retourne null si me est null', function() {
      GQL.query = function() {
        return Promise.resolve({
          me: null
        });
      };
      return A.restoreSession().then(function(u) {
        return eq(u, null);
      });
    });
    return it('retourne null sur erreur réseau', function() {
      GQL.query = function() {
        return Promise.reject(new Error('network error'));
      };
      return A.restoreSession().then(function(u) {
        return eq(u, null);
      });
    });
  });

  summary();

}).call(this);
