(function() {
  // Simple test to verify Playwright setup works
  var expect, test;

  ({test, expect} = require('@playwright/test'));

  test.describe('Simple Test', function() {
    return test('should load page', async function({page}) {
      var title;
      await page.goto('http://localhost:8081');
      
      // Just check if page loads without error
      title = (await page.title());
      console.log(`Page title: ${title}`);
      return expect(title).toBeTruthy();
    });
  });

}).call(this);
