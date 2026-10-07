(function() {
  // graphql_client.coffee
  // Minimal GraphQL client backed by the browser fetch API.
  // Token persisted in localStorage.
  window.GQL = {
    _token: null,
    _KEY: 'tdb_token',
    setToken: function(token) {
      this._token = token;
      if (token) {
        return localStorage.setItem(this._KEY, token);
      } else {
        return localStorage.removeItem(this._KEY);
      }
    },
    clearToken: function() {
      return this.setToken(null);
    },
    loadToken: function() {
      var saved;
      saved = localStorage.getItem(this._KEY);
      if (saved) {
        return this._token = saved;
      }
    },
    // Execute a GraphQL operation.
    // Returns a promise resolving to { data, errors }.
    query: function(query, variables = {}, operationName = null) {
      var body, headers;
      headers = {
        'Content-Type': 'application/json'
      };
      if (this._token) {
        headers['Authorization'] = `Bearer ${this._token}`;
      }
      body = JSON.stringify({query, variables, operationName});
      return fetch('/graphql', {
        method: 'POST',
        headers,
        body
      }).then(function(res) {
        return res.json();
      }).then(function(result) {
        if (result.errors && result.errors.length > 0) {
          // Throw with first error message so callers can catch
          throw new Error(result.errors[0].message);
        }
        return result.data;
      });
    },
    // Convenience: run a mutation
    mutate: function(mutation, variables = {}) {
      return this.query(mutation, variables);
    }
  };

}).call(this);
