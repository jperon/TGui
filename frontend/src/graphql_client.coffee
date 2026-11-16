# graphql_client.coffee
# Minimal GraphQL client backed by the browser fetch API.
# Token persisted in localStorage.

window.GQL =
  _token: null
  _KEY: 'tdb_token'

  setToken: (token) ->
    @_token = token
    if token
      localStorage.setItem @_KEY, token
    else
      localStorage.removeItem @_KEY

  clearToken: ->
    @setToken null

  loadToken: ->
    saved = localStorage.getItem @_KEY
    @_token = saved if saved

  # Header marking a request relayed from a widget iframe: the backend then
  # only allows queries and data-record mutations for it (spec
  # docs/superpowers/specs/2026-11-16-custom-widgets-design.md paragraph 6,
  # graphql/executor.moon WIDGET_ALLOWED_MUTATIONS).
  WIDGET_HEADER: { 'X-TDB-Widget': '1' }

  # Execute a GraphQL operation.
  # `extraHeaders` adds per-call headers (see queryWidget).
  # Returns a promise resolving to { data, errors }.
  query: (query, variables = {}, operationName = null, extraHeaders = null) ->
    headers =
      'Content-Type': 'application/json'
    if extraHeaders
      for own name, value of extraHeaders
        headers[name] = value
    if @_token
      headers['Authorization'] = "Bearer #{@_token}"

    body = JSON.stringify { query, variables, operationName }

    fetch('/graphql', { method: 'POST', headers, body })
      .then (res) -> res.json()
      .then (result) ->
        if result.errors and result.errors.length > 0
          message = result.errors[0].message
          # The server refuses operations while the account still uses the
          # default password (spec §7 / audit 1.4). Open the change-password
          # dialog automatically, with a readable message.
          if message and message.indexOf('PASSWORD_CHANGE_REQUIRED') == 0
            clean = message.replace /^PASSWORD_CHANGE_REQUIRED:\s*/, ''
            if window.App and typeof window.App._openChangePasswordDialog == 'function'
              window.App._openChangePasswordDialog clean
          # Throw with first error message so callers can catch
          throw new Error(message)
        result.data

  # Run a GraphQL operation on behalf of a widget iframe. The request carries
  # the widget header, so the server refuses everything but queries and
  # data-record mutations; the iframe itself has neither the token nor direct
  # HTTP access, so it cannot bypass the restriction.
  queryWidget: (query, variables = {}, operationName = null) ->
    @query query, variables, operationName, @WIDGET_HEADER

  # Convenience: run a mutation
  mutate: (mutation, variables = {}) ->
    @query mutation, variables
