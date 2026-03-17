# Parallel-ready helper functions for E2E tests
# Provides robust login and cleanup functions for concurrent execution

{ test, expect } = require '@playwright/test'

# Helper function with retry logic for login
exports.performLogin = (page, username = 'admin', password = 'adminadmin') ->
  await page.goto '/'
  await page.fill '#login-username', username
  await page.fill '#login-password', password
  await page.click '#login-btn'

  # Wait for login with timeout and retry
  try
    await page.waitForSelector '#main', { state: 'visible', timeout: 10000 }
  catch error
    # If login fails, retry once (might be due to concurrent access)
    await page.goto '/'
    await page.fill '#login-username', username
    await page.fill '#login-password', password
    await page.click '#login-btn'
    await page.waitForSelector '#main', { state: 'visible', timeout: 10000 }

# Helper function for logout
exports.performLogout = (page) ->
  await page.evaluate(() -> localStorage.clear())
  await page.reload()
  await page.waitForSelector '#login-overlay', { state: 'visible', timeout: 5000 }

# Helper function to generate unique names
exports.generateUniqueName = (prefix = 'test') ->
  timestamp = Date.now()
  random = Math.floor(Math.random() * 1000)
  return "#{prefix}_#{timestamp}_#{random}"

# Helper function to wait for element with retry
exports.waitForElementWithRetry = (page, selector, timeout = 10000) ->
  try
    await page.waitForSelector selector, { state: 'visible', timeout }
  catch error
    # Retry once
    await page.waitForTimeout 1000
    await page.waitForSelector selector, { state: 'visible', timeout }

# Helper function to clean up with retry
exports.cleanupWithRetry = (page, cleanupFunction) ->
  try
    await cleanupFunction()
  catch error
    # If cleanup fails, try once more after delay
    await page.waitForTimeout 1000
    await cleanupFunction()

# Console error tracking
# Creates a console error listener that fails tests on console errors
exports.setupConsoleErrorTracking = (page) ->
  consoleErrors = []
  
  # Create the listener
  listener = (msg) ->
    if msg.type() is 'error'
      consoleErrors.push msg.text()
  
  # Attach the listener
  page.on 'console', listener
  
  # Return function to get errors and cleanup
  return {
    getErrors: -> consoleErrors.slice()
    hasErrors: -> consoleErrors.length > 0
    clearErrors: -> consoleErrors.length = 0
    listener: listener
  }

# Helper to check if SortableJS is loaded on the page
exports.checkSortableJS = (page) ->
  await page.evaluate(() ->
    if typeof Sortable is 'undefined'
      return { loaded: false, error: 'SortableJS is not defined on window' }
    
    if typeof Sortable.create isnt 'function'
      return { loaded: false, error: 'Sortable.create is not a function' }
    
    { loaded: true }
  )
