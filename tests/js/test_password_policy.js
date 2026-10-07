(function() {
  // tests/js/test_password_policy.coffee
  // Forced default-password change, frontend side (spec §7 / audit 1.4):
  // - the warning banner depends on user.mustChangePassword (server-computed flag),
  //   not on the legacy localStorage shortcut nor on the username;
  // - a PASSWORD_CHANGE_REQUIRED GraphQL error opens the change-password dialog.
  var App, GQL, assert, describe, eq, i, id, it, len, localStorageStub, makeElement, ref, show, summary, warningVisible;

  ({makeElement, localStorageStub} = require('./dom_stub'));

  ({describe, it, eq, assert, summary} = require('./runner'));

  ref = ['login-overlay', 'main', 'current-user-btn', 'admin-sidebar-section', 'plugins-sidebar-section', 'default-password-warning'];
  // Register the DOM elements App.showMain touches.
  for (i = 0, len = ref.length; i < len; i++) {
    id = ref[i];
    document._setById(id, makeElement('div'));
  }

  global.GQL = {
    _token: null,
    loadToken: (function() {}),
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

  global.Auth = window.Auth;

  require('../../frontend/src/widget_plugins');

  require('../../frontend/src/app');

  App = window.App;

  warningVisible = function() {
    return !document.getElementById('default-password-warning').classList.contains('hidden');
  };

  show = function(user) {
    Auth.currentUser = user;
    return App.showMain(user);
  };

  describe('default password warning', function() {
    it('shows the banner when the server flag is true', function() {
      show({
        id: '1',
        username: 'alice',
        email: '',
        groups: [],
        mustChangePassword: true
      });
      return assert(warningVisible(), 'banner should be visible when mustChangePassword is true');
    });
    it('hides the banner when the server flag is false', function() {
      show({
        id: '1',
        username: 'admin',
        email: '',
        groups: [],
        mustChangePassword: false
      });
      return assert(!warningVisible(), 'banner should be hidden when mustChangePassword is false');
    });
    it('is not bypassed by the legacy localStorage flag', function() {
      localStorageStub.setItem('tdb_password_changed', '1');
      show({
        id: '1',
        username: 'admin',
        email: '',
        groups: [],
        mustChangePassword: true
      });
      assert(warningVisible(), 'localStorage must no longer hide the banner');
      return localStorageStub.removeItem('tdb_password_changed');
    });
    return it('no longer depends on the username', function() {
      show({
        id: '1',
        username: 'root',
        email: '',
        groups: [],
        mustChangePassword: false
      });
      return assert(!warningVisible(), 'a non-admin username with a false flag hides the banner');
    });
  });

  require('../../frontend/src/graphql_client');

  GQL = window.GQL;

  describe('PASSWORD_CHANGE_REQUIRED handling', function() {
    return it('opens the change-password dialog with a readable message', function() {
      var captured;
      captured = null;
      window.App._openChangePasswordDialog = function(message) {
        return captured = message;
      };
      global.fetch = function(url, opts) {
        return Promise.resolve({
          json: function() {
            return Promise.resolve({
              errors: [
                {
                  message: 'PASSWORD_CHANGE_REQUIRED: change the default password'
                }
              ]
            });
          }
        });
      };
      GQL.clearToken();
      return GQL.query('query { me { id } }').then(function() {
        throw new Error('the query should have been rejected');
      }, function(err) {
        eq(err.message.indexOf('PASSWORD_CHANGE_REQUIRED'), 0);
        return eq(captured, 'change the default password');
      });
    });
  });

  summary();

}).call(this);
