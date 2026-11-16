(function() {
  // graphql_client.coffee
  // Minimal GraphQL client backed by the browser fetch API.
  // Token persisted in localStorage.
  var hasProp = {}.hasOwnProperty;

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
    // Header marking a request relayed from a widget iframe: the backend then
    // only allows queries and data-record mutations for it (spec
    // docs/superpowers/specs/2026-11-16-custom-widgets-design.md paragraph 6,
    // graphql/executor.moon WIDGET_ALLOWED_MUTATIONS).
    WIDGET_HEADER: {
      'X-TDB-Widget': '1'
    },
    // Execute a GraphQL operation.
    // `extraHeaders` adds per-call headers (see queryWidget).
    // Returns a promise resolving to { data, errors }.
    query: function(query, variables = {}, operationName = null, extraHeaders = null) {
      var body, headers, name, value;
      headers = {
        'Content-Type': 'application/json'
      };
      if (extraHeaders) {
        for (name in extraHeaders) {
          if (!hasProp.call(extraHeaders, name)) continue;
          value = extraHeaders[name];
          headers[name] = value;
        }
      }
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
        var clean, message;
        if (result.errors && result.errors.length > 0) {
          message = result.errors[0].message;
          // The server refuses operations while the account still uses the
          // default password (spec §7 / audit 1.4). Open the change-password
          // dialog automatically, with a readable message.
          if (message && message.indexOf('PASSWORD_CHANGE_REQUIRED') === 0) {
            clean = message.replace(/^PASSWORD_CHANGE_REQUIRED:\s*/, '');
            if (window.App && typeof window.App._openChangePasswordDialog === 'function') {
              window.App._openChangePasswordDialog(clean);
            }
          }
          // Throw with first error message so callers can catch
          throw new Error(message);
        }
        return result.data;
      });
    },
    // Run a GraphQL operation on behalf of a widget iframe. The request carries
    // the widget header, so the server refuses everything but queries and
    // data-record mutations; the iframe itself has neither the token nor direct
    // HTTP access, so it cannot bypass the restriction.
    queryWidget: function(query, variables = {}, operationName = null) {
      return this.query(query, variables, operationName, this.WIDGET_HEADER);
    },
    // Convenience: run a mutation
    mutate: function(mutation, variables = {}) {
      return this.query(mutation, variables);
    }
  };

}).call(this);
