(function() {
  // auth.coffee
  // Handles login, logout, and current-user state.
  var LOGIN_MUTATION, LOGOUT_MUTATION, ME_QUERY;

  LOGIN_MUTATION = `mutation Login($username: String!, $password: String!) {
  login(username: $username, password: $password) {
    token
    user { id username email }
  }
}`;

  LOGOUT_MUTATION = `mutation { logout }`;

  ME_QUERY = `query { me { id username email } }`;

  window.Auth = {
    currentUser: null,
    login: function(username, password) {
      return GQL.mutate(LOGIN_MUTATION, {username, password}).then(function(data) {
        GQL.setToken(data.login.token);
        Auth.currentUser = data.login.user;
        return Auth.currentUser;
      });
    },
    logout: function() {
      return GQL.mutate(LOGOUT_MUTATION).finally(function() {
        GQL.clearToken();
        Auth.currentUser = null;
        return App.showLogin();
      });
    },
    restoreSession: function() {
      // Try to fetch current user with any existing token
      return GQL.query(ME_QUERY).then(function(data) {
        if (data.me) {
          Auth.currentUser = data.me;
          return Auth.currentUser;
        } else {
          return null;
        }
      }).catch(function() {
        return null;
      });
    }
  };

}).call(this);
