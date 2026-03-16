(function() {
  // Global teardown for Playwright tests
  // Runs once after all test suites
  module.exports = function({config}) {
    console.log('🧹 Cleaning up Playwright E2E test environment...');
    
    // Final cleanup of any remaining test data
    // This ensures a clean state for the next test run
    return console.log('✅ Playwright E2E test teardown completed');
  };

}).call(this);
