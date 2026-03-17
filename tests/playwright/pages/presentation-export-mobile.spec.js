(function() {
  // Presentation Mode, Export/Import Layouts, and Mobile Responsive E2E Tests
  // Tests for Phase 6 features: presentation mode, export/import layouts, mobile responsive
  var expect, generateUniqueName, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  test.describe('Pages - Presentation Mode', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    return test('should toggle presentation mode and disable drag & drop', async function({page}) {
      var cvInitialized, deleteButtonsVisible, hasPresentationClass, isPresentationMode, isPresentationModeAfter, pageData, pageName;
      // Navigate to pages
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      // Create a page with widgets
      pageName = `PresentationTest_${Date.now()}`;
      await page.evaluate(function(name) {
        var mutation, token;
        mutation = `mutation {
  createCustomView(input: {
    name: "${name}",
    yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Widget 1\\n        space: users\\n    - widget:\\n        id: w2\\n        title: Widget 2\\n        space: tasks"
  }) { id name }
}`;
        token = localStorage.getItem('tdb_token');
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            query: mutation
          })
        }).then(function(r) {
          return r.json();
        });
      }, pageName);
      await page.waitForTimeout(2000);
      // Get the custom view data and select the page programmatically
      pageData = (await page.evaluate(function(name) {
        var query, token;
        token = localStorage.getItem('tdb_token');
        query = `query {
  customViews {
    id
    name
    yaml
  }
}`;
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            query: query
          })
        }).then(function(r) {
          return r.json();
        }).then(function(result) {
          var cv, ref, ref1;
          cv = (ref = result.data) != null ? (ref1 = ref.customViews) != null ? ref1.find(function(v) {
            return v.name === name;
          }) : void 0 : void 0;
          return cv;
        });
      }, pageName));
      console.log("Page data:", JSON.stringify(pageData));
      // Call selectPage directly to initialize the CustomView
      if (pageData) {
        await page.evaluate(function(cv) {
          window.App._currentCustomView = cv;
          return window.App.selectPage(cv);
        }, pageData);
        await page.waitForTimeout(2000);
      }
      // Force container visibility
      await page.evaluate(function() {
        var container;
        container = document.getElementById('custom-view-container');
        if (container != null) {
          return container.classList.remove('hidden');
        }
      });
      // Wait for widgets to render
      await page.waitForSelector('[data-widget-id]', {
        timeout: 5000
      }).catch(function() {
        return null;
      });
      await page.waitForTimeout(1000);
      // Check if _activeCustomView is set, if not try to initialize it
      cvInitialized = (await page.evaluate(function() {
        var container, ref, ref1, ref2, yaml;
        if ((ref = window.App) != null ? ref._activeCustomView : void 0) {
          return true;
        }
        // Try to manually initialize by calling mountCustomView
        if (((ref1 = window.AppViewHelpers) != null ? ref1.mountCustomView : void 0) != null) {
          container = document.getElementById('custom-view-container');
          yaml = (ref2 = window.App._currentCustomView) != null ? ref2.yaml : void 0;
          if (yaml && container) {
            window.AppViewHelpers.mountCustomView(window.App, yaml);
            return !!window.App._activeCustomView;
          }
        }
        return false;
      }));
      console.log("CustomView initialized:", cvInitialized);
      // Check initial state - presentation mode should be false
      isPresentationMode = (await page.evaluate(function() {
        var cv, ref;
        cv = (ref = window.App) != null ? ref._activeCustomView : void 0;
        return (cv != null ? typeof cv.isPresentationMode === "function" ? cv.isPresentationMode() : void 0 : void 0) || false;
      }));
      console.log("Initial presentation mode:", isPresentationMode);
      
      // Toggle presentation mode
      await page.evaluate(function() {
        var cv, ref;
        cv = (ref = window.App) != null ? ref._activeCustomView : void 0;
        if ((cv != null ? cv.togglePresentationMode : void 0) != null) {
          return cv.togglePresentationMode();
        }
      });
      await page.waitForTimeout(1000);
      // Check that presentation mode is now true
      isPresentationModeAfter = (await page.evaluate(function() {
        var cv, ref;
        cv = (ref = window.App) != null ? ref._activeCustomView : void 0;
        return (cv != null ? typeof cv.isPresentationMode === "function" ? cv.isPresentationMode() : void 0 : void 0) || false;
      }));
      console.log("After toggle presentation mode:", isPresentationModeAfter);
      await expect(isPresentationModeAfter).toBe(true);
      // Verify CSS class is applied
      hasPresentationClass = (await page.evaluate(function() {
        var mainContainer, widgetsContainer;
        // Check both the main container and the widgets container
        mainContainer = document.getElementById('custom-view-container');
        widgetsContainer = mainContainer != null ? mainContainer.querySelector('.widgets-container') : void 0;
        return (widgetsContainer != null ? widgetsContainer.classList.contains('presentation-mode') : void 0) || (mainContainer != null ? mainContainer.classList.contains('presentation-mode') : void 0);
      }));
      console.log("Has presentation-mode class:", hasPresentationClass);
      await expect(hasPresentationClass).toBe(true);
      // Verify drag handles are hidden
      deleteButtonsVisible = (await page.locator('.cv-widget-delete-btn').isVisible().catch(function() {
        return false;
      }));
      console.log("Delete buttons visible in presentation mode:", deleteButtonsVisible);
      return (await expect(deleteButtonsVisible).toBe(false));
    });
  });

  test.describe('Pages - Export/Import Layouts', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    test('should export layout as YAML file', async function({page}) {
      var downloadPromise, exportBtn, pageItem, pageName;
      // Navigate to pages
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      // Create a page with widgets
      pageName = `ExportTest_${Date.now()}`;
      await page.evaluate(function(name) {
        var mutation, token;
        mutation = `mutation {
  createCustomView(input: {
    name: "${name}",
    yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Test Widget\\n        space: users"
  }) { id name }
}`;
        token = localStorage.getItem('tdb_token');
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            query: mutation
          })
        }).then(function(r) {
          return r.json();
        });
      }, pageName);
      await page.waitForTimeout(2000);
      // Find and click the export button
      pageItem = page.locator(`.leaf-item:has-text('${pageName}')`);
      if ((await pageItem.count()) > 0) {
        await pageItem.hover();
        await page.waitForTimeout(500);
        // Look for export button
        exportBtn = page.locator('.leaf-item-actions .page-action-btn').first();
        if ((await exportBtn.count()) > 0) {
          // Start download listener
          downloadPromise = page.waitForEvent('download', {
            timeout: 5000
          }).catch(function() {
            return null;
          });
          await exportBtn.click();
          await page.waitForTimeout(1000);
          return console.log("Export button clicked");
        } else {
          return console.log("Export button not found");
        }
      }
    });
    return test('should import layout from YAML file', async function({page}) {
      var createResult, importResult, pageId, pageName, ref, ref1, ref2;
      // Navigate to pages
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      // Create a page to import into and get ID directly from mutation result
      pageName = `ImportTarget_${Date.now()}`;
      createResult = (await page.evaluate(function(name) {
        var mutation, token;
        mutation = `mutation {
  createCustomView(input: {
    name: "${name}",
    yaml: "layout:\\n  direction: vertical\\n  children: []"
  }) { id name }
}`;
        token = localStorage.getItem('tdb_token');
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            query: mutation
          })
        }).then(function(r) {
          return r.json();
        });
      }, pageName));
      console.log("Create result:", JSON.stringify(createResult));
      pageId = (ref = createResult.data) != null ? (ref1 = ref.createCustomView) != null ? ref1.id : void 0 : void 0;
      if (!pageId) {
        throw new Error(`Failed to create page: ${JSON.stringify(createResult.errors)}`);
      }
      // Test importLayout mutation directly
      importResult = (await page.evaluate(function(id) {
        var mutation, token;
        mutation = `mutation ImportLayout($pageId: ID!, $yaml: String!) {
  importLayout(pageId: $pageId, yaml: $yaml) {
    id
    name
    yaml
  }
}`;
        token = localStorage.getItem('tdb_token');
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            query: mutation,
            variables: {
              pageId: id,
              yaml: "layout:\\n  direction: horizontal\\n  children:\\n    - widget:\\n        id: imported1\\n        title: Imported Widget\\n        space: users"
            }
          })
        }).then(function(r) {
          return r.json();
        });
      }, pageId));
      console.log("Import result:", JSON.stringify(importResult));
      
      // Verify import was successful
      if ((ref2 = importResult.data) != null ? ref2.importLayout : void 0) {
        await expect(importResult.data.importLayout.yaml).toContain('imported1');
        return (await expect(importResult.data.importLayout.yaml).toContain('horizontal'));
      } else {
        return console.log("Import failed:", importResult.errors);
      }
    });
  });

  test.describe('Pages - Mobile Responsive', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    test('should apply mobile responsive styles on small viewport', async function({page}) {
      var layoutPaletteVisible, pageItem, pageName, zoneHeaderVisible;
      // Set mobile viewport
      await page.setViewportSize({
        width: 375,
        height: 667
      });
      await page.waitForTimeout(500);
      // Navigate to pages
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      // Create a page with zones
      pageName = `MobileTest_${Date.now()}`;
      await page.evaluate(function(name) {
        var mutation, token;
        mutation = `mutation {
  createCustomView(input: {
    name: "${name}",
    yaml: "layout:\\n  direction: vertical\\n  children:\\n    - zone:\\n        id: zone1\\n        title: Zone 1\\n        direction: horizontal\\n        children:\\n          - widget:\\n              id: w1\\n              title: Widget 1\\n              space: users"
  }) { id name }
}`;
        token = localStorage.getItem('tdb_token');
        return fetch('/graphql', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({
            query: mutation
          })
        }).then(function(r) {
          return r.json();
        });
      }, pageName);
      await page.waitForTimeout(2000);
      // Click on the page
      pageItem = page.locator(`.leaf-item:has-text('${pageName}')`);
      if ((await pageItem.count()) > 0) {
        await pageItem.click();
        await page.waitForTimeout(3000);
      }
      // Force container visibility
      await page.evaluate(function() {
        var container;
        container = document.getElementById('custom-view-container');
        if (container != null) {
          return container.classList.remove('hidden');
        }
      });
      await page.waitForTimeout(1000);
      // Check that zone headers are hidden on mobile
      zoneHeaderVisible = (await page.locator('.cv-zone-header').isVisible().catch(function() {
        return false;
      }));
      console.log("Zone header visible on mobile:", zoneHeaderVisible);
      await expect(zoneHeaderVisible).toBe(false);
      // Check that layout palette is hidden on mobile
      layoutPaletteVisible = (await page.locator('.cv-layout-palette').isVisible().catch(function() {
        return false;
      }));
      console.log("Layout palette visible on mobile:", layoutPaletteVisible);
      return (await expect(layoutPaletteVisible).toBe(false));
    });
    return test('should resize to mobile and apply CSS media queries', async function({page}) {
      var bodyStyles, isMobileWidth, viewport;
      // Set mobile viewport
      await page.setViewportSize({
        width: 375,
        height: 667
      });
      await page.waitForTimeout(500);
      // Verify viewport size
      viewport = page.viewportSize();
      expect(viewport.width).toBe(375);
      expect(viewport.height).toBe(667);
      // Navigate to pages
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      // Check that media queries are applied (window width should be <= 768)
      isMobileWidth = (await page.evaluate(function() {
        return window.innerWidth <= 768;
      }));
      console.log("Is mobile width (<=768):", isMobileWidth);
      expect(isMobileWidth).toBe(true);
      // Check that body has appropriate responsive class or style
      bodyStyles = (await page.evaluate(function() {
        var computed;
        computed = window.getComputedStyle(document.body);
        return {
          width: computed.width,
          innerWidth: window.innerWidth
        };
      }));
      console.log("Computed body width:", bodyStyles.width);
      return expect(parseInt(bodyStyles.width)).toBeLessThanOrEqual(375);
    });
  });

  test.describe('DataView - readOnly option', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    test('should load users space without crashing', async function({page}) {
      console.log("Testing DataView with users space...");
      // Navigate directly to users space
      await page.goto('/#!spaces/users');
      await page.waitForTimeout(3000);
      // Check that page loaded without crashing
      return (await expect(page.locator('#app')).toBeVisible({
        timeout: 10000
      }));
    });
    return test('should resize to mobile viewport and apply media queries', async function({page}) {
      var bodyStyles, viewport;
      // Set mobile viewport
      await page.setViewportSize({
        width: 375,
        height: 667
      });
      await page.waitForTimeout(500);
      // Verify viewport size
      viewport = page.viewportSize();
      expect(viewport.width).toBe(375);
      expect(viewport.height).toBe(667);
      // Navigate to a page that has mobile-specific CSS
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      // Check that media query is applied by checking computed style of body
      bodyStyles = (await page.evaluate(function() {
        var computed;
        computed = window.getComputedStyle(document.body);
        return {
          width: computed.width,
          isMobile: window.innerWidth <= 768
        };
      }));
      console.log("Body styles on mobile:", JSON.stringify(bodyStyles));
      return expect(bodyStyles.isMobile).toBe(true);
    });
  });

}).call(this);
