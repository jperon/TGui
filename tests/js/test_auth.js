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

  global.Auth = A; // auth.js references Auth directly (browser global)

  describe('Auth.login', function() {
    it('calls GQL.mutate with correct arguments', function() {
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
              email: 'a@b.c',
              groups: []
            }
          }
        });
      };
      return A.login('alice', 'secret').then(function() {
        eq(captured != null ? captured.username : void 0, 'alice');
        return eq(captured != null ? captured.password : void 0, 'secret');
      });
    });
    it('returns resolved user', function() {
      GQL.mutate = function(q, v) {
        return Promise.resolve({
          login: {
            token: 't',
            user: {
              id: '2',
              username: 'bob',
              email: '',
              groups: []
            }
          }
        });
      };
      return A.login('bob', 'pass').then(function(user) {
        eq(user.username, 'bob');
        return eq(user.id, '2');
      });
    });
    return it('calls GQL.setToken with received token', function() {
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
              email: '',
              groups: []
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
    it('returns user when me is defined', function() {
      GQL.query = function() {
        return Promise.resolve({
          me: {
            id: '10',
            username: 'dan',
            email: '',
            groups: []
          }
        });
      };
      return A.restoreSession().then(function(u) {
        return eq(u != null ? u.username : void 0, 'dan');
      });
    });
    it('returns null when me is null', function() {
      GQL.query = function() {
        return Promise.resolve({
          me: null
        });
      };
      return A.restoreSession().then(function(u) {
        return eq(u, null);
      });
    });
    return it('returns null on network error', function() {
      GQL.query = function() {
        return Promise.reject(new Error('network error'));
      };
      return A.restoreSession().then(function(u) {
        return eq(u, null);
      });
    });
  });

  describe('Auth.isAdmin', function() {
    it('returns true when currentUser is in admin group', function() {
      A.currentUser = {
        id: '1',
        username: 'root',
        groups: [
          {
            id: 'g1',
            name: 'admin'
          }
        ]
      };
      return assert(A.isAdmin(), 'isAdmin should be true');
    });
    it('returns false when currentUser is not in admin', function() {
      A.currentUser = {
        id: '2',
        username: 'bob',
        groups: [
          {
            id: 'g2',
            name: 'users'
          }
        ]
      };
      return assert(!A.isAdmin(), 'isAdmin should be false');
    });
    return it('returns false when currentUser is null', function() {
      A.currentUser = null;
      return assert(!A.isAdmin(), 'isAdmin should be false when currentUser is null');
    });
  });

  describe('Auth.changePassword', function() {
    return it('calls mutate and returns changePassword value', function() {
      GQL.mutate = function(q, v) {
        return Promise.resolve({
          changePassword: true
        });
      };
      return A.changePassword('old', 'new').then(function(result) {
        return assert(result, 'changePassword devrait retourner true');
      });
    });
  });

  describe('Auth.isAdmin (sans groupes)', function() {
    return it('returns false when groups is undefined', function() {
      A.currentUser = {
        id: '3',
        username: 'ghost'
      };
      return assert(!A.isAdmin(), 'isAdmin should be false when groups is missing');
    });
  });

  summary();

}).call(this);
