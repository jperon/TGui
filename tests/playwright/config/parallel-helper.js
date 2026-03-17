(function() {
  // Parallel-ready helper functions for E2E tests
  // Provides robust login and cleanup functions for concurrent execution
  var expect, test;

  ({test, expect} = require('@playwright/test'));

  // Helper function with retry logic for login
  exports.performLogin = async function(page, username = 'admin', password = 'adminadmin') {
    var error;
    await page.goto('/');
    await page.fill('#login-username', username);
    await page.fill('#login-password', password);
    await page.click('#login-btn');
    try {
      // Wait for login with timeout and retry
      return (await page.waitForSelector('#main', {
        state: 'visible',
        timeout: 10000
      }));
    } catch (error1) {
      error = error1;
      // If login fails, retry once (might be due to concurrent access)
      await page.goto('/');
      await page.fill('#login-username', username);
      await page.fill('#login-password', password);
      await page.click('#login-btn');
      return (await page.waitForSelector('#main', {
        state: 'visible',
        timeout: 10000
      }));
    }
  };

  // Helper function for logout
  exports.performLogout = async function(page) {
    await page.evaluate(function() {
      return localStorage.clear();
    });
    await page.reload();
    return (await page.waitForSelector('#login-overlay', {
      state: 'visible',
      timeout: 5000
    }));
  };

  // Helper function to generate unique names
  exports.generateUniqueName = function(prefix = 'test') {
    var random, timestamp;
    timestamp = Date.now();
    random = Math.floor(Math.random() * 1000);
    return `${prefix}_${timestamp}_${random}`;
  };

  // Helper function to wait for element with retry
  exports.waitForElementWithRetry = async function(page, selector, timeout = 10000) {
    var error;
    try {
      return (await page.waitForSelector(selector, {
        state: 'visible',
        timeout
      }));
    } catch (error1) {
      error = error1;
      // Retry once
      await page.waitForTimeout(1000);
      return (await page.waitForSelector(selector, {
        state: 'visible',
        timeout
      }));
    }
  };

  // Helper function to clean up with retry
  exports.cleanupWithRetry = async function(page, cleanupFunction) {
    var error;
    try {
      return (await cleanupFunction());
    } catch (error1) {
      error = error1;
      // If cleanup fails, try once more after delay
      await page.waitForTimeout(1000);
      return (await cleanupFunction());
    }
  };

  // Console error tracking
  // Creates a console error listener that fails tests on console errors
  exports.setupConsoleErrorTracking = function(page) {
    var consoleErrors, listener;
    consoleErrors = [];
    
    // Create the listener
    listener = function(msg) {
      if (msg.type() === 'error') {
        return consoleErrors.push(msg.text());
      }
    };
    
    // Attach the listener
    page.on('console', listener);
    return {
      
      // Return function to get errors and cleanup
      getErrors: function() {
        return consoleErrors.slice();
      },
      hasErrors: function() {
        return consoleErrors.length > 0;
      },
      clearErrors: function() {
        return consoleErrors.length = 0;
      },
      listener: listener
    };
  };

  // Helper to check if SortableJS is loaded on the page
  exports.checkSortableJS = async function(page) {
    return (await page.evaluate(function() {
      if (typeof Sortable === 'undefined') {
        return {
          loaded: false,
          error: 'SortableJS is not defined on window'
        };
      }
      if (typeof Sortable.create !== 'function') {
        return {
          loaded: false,
          error: 'Sortable.create is not a function'
        };
      }
      return {
        loaded: true
      };
    }));
  };

}).call(this);
