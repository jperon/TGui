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

  # Execute a GraphQL operation.
  # Returns a promise resolving to { data, errors }.
  query: (query, variables = {}, operationName = null) ->
    headers =
      'Content-Type': 'application/json'
    if @_token
      headers['Authorization'] = "Bearer #{@_token}"

    body = JSON.stringify { query, variables, operationName }

    fetch('/graphql', { method: 'POST', headers, body })
      .then (res) -> res.json()
      .then (result) ->
        if result.errors and result.errors.length > 0
          # Throw with first error message so callers can catch
          throw new Error(result.errors[0].message)
        result.data

  # Convenience: run a mutation
  mutate: (mutation, variables = {}) ->
    @query mutation, variables
