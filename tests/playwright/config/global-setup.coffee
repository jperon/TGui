# Global setup for Playwright tests
# Runs once before all test suites

module.exports = ({config}) ->
  console.log '🚀 Starting Playwright E2E test setup...'

  # Verify TGui is running on test port
  try
    response = await fetch 'http://localhost:8081'
    unless response.ok
      throw new Error "TGui not responding: #{response.status}"

    console.log '✅ TGui is running and accessible on test port 8081'
  catch error
    console.error '❌ TGui setup failed:', error.message
    console.error '💡 Make sure TGui test instance is running with: make test-up'
    process.exit 1

  # Clean up any existing test data
  console.log '🧹 Cleaning up existing test data...'

  return config
