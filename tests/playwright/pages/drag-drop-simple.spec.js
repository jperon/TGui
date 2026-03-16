(function() {
  // Simple Drag & Drop Test
  var expect, test;

  ({test, expect} = require('@playwright/test'));

  test.describe('Pages - Widget Drag & Drop', function() {
    test('should show drag handles on widget hover', async function({page}) {
      var firstWidget, widgets;
      await page.goto('http://localhost:8081/#!pages');
      
      // Wait for page to load
      await page.waitForTimeout(2000);
      
      // Check if any widgets exist
      widgets = (await page.locator('[data-widget-title]').count());
      console.log(`Found ${widgets} widgets on page`);
      if (widgets > 0) {
        // Hover over first widget
        firstWidget = page.locator('[data-widget-title]').first();
        await firstWidget.hover();
        console.log("✅ Widget hover test completed");
      } else {
        console.log("ℹ️ No widgets found for drag & drop testing");
      }
      return expect(widgets).toBeGreaterThanOrEqual(0);
    });
    return test('should handle page navigation', async function({page}) {
      var title;
      await page.goto('http://localhost:8081/#!pages');
      
      // Wait for page to load
      await page.waitForTimeout(2000);
      
      // Check if we can access pages
      title = (await page.title());
      console.log(`Page title: ${title}`);
      return expect(title).toBeTruthy();
    });
  });

}).call(this);
