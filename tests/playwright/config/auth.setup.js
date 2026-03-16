(function() {
  // Authentication helper utilities for Playwright tests
  // Provides login/logout functionality and token management
  // Note: Uses test environment on port 8081
  var AuthHelper;

  AuthHelper = class AuthHelper {
    constructor() {
      this.token = null;
      this.currentUser = null;
    }

    // Login to TGui and store authentication token
    async login({page, username = 'admin', password = 'adminadmin'}) {
      await page.goto('/login');
      // Fill login form
      await page.fill('input[name="username"]', username);
      await page.fill('input[name="password"]', password);
      // Submit form
      await page.click('button[type="submit"]');
      // Wait for successful login (redirect to main app)
      await page.waitForURL('**/#!');
      // Store authentication info
      this.currentUser = username;
      // Get GraphQL token for API calls
      await this.extractToken(page);
      console.log(`✅ Logged in as ${username}`);
      return this.token;
    }

    // Extract authentication token from localStorage or cookies
    async extractToken({page}) {
      var authCookie, cookies, error;
      try {
        // Try localStorage first
        this.token = (await page.evaluate(function() {
          return localStorage.getItem('auth_token');
        }));
        if (!this.token) {
          // Try cookies as fallback
          cookies = (await page.context.cookies());
          authCookie = cookies.find(function(cookie) {
            return cookie.name === 'auth_token';
          });
          if (authCookie) {
            this.token = authCookie != null ? authCookie.value : void 0;
          }
        }
        if (this.token) {
          return console.log('🔑 Authentication token extracted');
        }
      } catch (error1) {
        error = error1;
        return console.warn('⚠️ Could not extract auth token:', error.message);
      }
    }

    // Logout and clean up authentication
    async logout({page}) {
      var error;
      try {
        // Click logout button if present
        await page.click('[data-testid="logout-button"]');
        await page.waitForURL('**/login');
        // Clear stored auth
        this.token = null;
        this.currentUser = null;
        return console.log('✅ Logged out successfully');
      } catch (error1) {
        error = error1;
        return console.warn('⚠️ Logout failed:', error.message);
      }
    }

    // Verify user is authenticated
    isAuthenticated(page) {
      var currentUrl, error;
      try {
        // Check if we're on main app page (not login)
        currentUrl = page.url();
        return !currentUrl.includes('/login');
      } catch (error1) {
        error = error1;
        return false;
      }
    }

    // Make authenticated GraphQL request
    async makeGraphQLRequest({page, query, variables = {}}) {
      var response;
      if (!this.token) {
        throw new Error('Not authenticated - call login() first');
      }
      response = (await page.evaluate(function({token, query, variables}) {
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({query, variables})
        }).then(function(res) {
          return res.json();
        });
      }));
      if (response.errors) {
        throw new Error(`GraphQL Error: ${response.errors[0].message}`);
      }
      return response.data;
    }

  };

  module.exports = {AuthHelper};

}).call(this);
