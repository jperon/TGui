# Authentication helper utilities for Playwright tests
# Provides login/logout functionality and token management
# Note: Uses test environment on port 8081

class AuthHelper
  constructor: ->
    @token = null
    @currentUser = null

  # Login to TGui and store authentication token
  login: ({page, username = 'admin', password = 'adminadmin'}) ->
    await page.goto '/login'

    # Fill login form
    await page.fill 'input[name="username"]', username
    await page.fill 'input[name="password"]', password

    # Submit form
    await page.click 'button[type="submit"]'

    # Wait for successful login (redirect to main app)
    await page.waitForURL '**/#!'

    # Store authentication info
    @currentUser = username

    # Get GraphQL token for API calls
    await @extractToken page

    console.log "✅ Logged in as #{username}"
    return @token

  # Extract authentication token from localStorage or cookies
  extractToken: ({page}) ->
    try
      # Try localStorage first
      @token = await page.evaluate -> localStorage.getItem 'auth_token'

      unless @token
        # Try cookies as fallback
        cookies = await page.context.cookies()
        authCookie = cookies.find (cookie) -> cookie.name is 'auth_token'
        @token = authCookie?.value if authCookie

      console.log '🔑 Authentication token extracted' if @token
    catch error
      console.warn '⚠️ Could not extract auth token:', error.message

  # Logout and clean up authentication
  logout: ({page}) ->
    try
      # Click logout button if present
      await page.click '[data-testid="logout-button"]'
      await page.waitForURL '**/login'

      # Clear stored auth
      @token = null
      @currentUser = null

      console.log '✅ Logged out successfully'
    catch error
      console.warn '⚠️ Logout failed:', error.message

  # Verify user is authenticated
  isAuthenticated: (page) ->
    try
      # Check if we're on main app page (not login)
      currentUrl = page.url()
      return not currentUrl.includes '/login'
    catch error
      return false

  # Make authenticated GraphQL request
  makeGraphQLRequest: ({page, query, variables = {}}) ->
    unless @token
      throw new Error 'Not authenticated - call login() first'

    response = await page.evaluate ({ token, query, variables }) ->
      fetch '/graphql',
        method: 'POST'
        headers:
          'Content-Type': 'application/json'
          'Authorization': "Bearer #{token}"
        body: JSON.stringify { query, variables }
      .then (res) -> res.json()

    if response.errors
      throw new Error "GraphQL Error: #{response.errors[0].message}"

    return response.data

module.exports = { AuthHelper }
