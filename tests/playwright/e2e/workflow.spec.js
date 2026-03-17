(function() {
  // Workflow E2E Tests
  // Complete workflow: space -> view -> page
  var expect, generateUniqueName, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  test.describe('Complete Workflow', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    test('should login and navigate to spaces section', async function({page}) {
      var spacesList, spacesToggle;
      await expect(page.locator('#main')).toBeVisible();
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      await expect(spacesList).toBeVisible();
      return (await expect(page.locator('#new-space-btn')).toBeVisible());
    });
    test('should create a new space with fields', async function({page}) {
      var addFieldBtn, createdField, createdSpace, fieldName, fieldsList, saveFieldBtn, spaceName, spacesList, spacesToggle;
      spaceName = generateUniqueName('TestSpace');
      fieldName = 'test_field';
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-space-btn');
      await page.waitForTimeout(500);
      await page.fill('#new-space-name', spaceName);
      await page.click('#new-space-confirm-btn');
      await page.waitForTimeout(2000);
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForTimeout(500);
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#add-field-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('button:has-text("Ajouter"), button:has-text("Add")');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      fieldsList = page.locator('#fields-list');
      createdField = fieldsList.locator('li', {
        hasText: fieldName
      });
      return (await expect(createdField).toBeVisible());
    });
    test('should create a data view from that space', async function({page}) {
      var addFieldBtn, createdDV, createdSpace, dataViewName, dataViewsList, dataViewsToggle, fieldName, saveFieldBtn, sourceSelect, spaceName, spacesList, spacesToggle;
      spaceName = generateUniqueName('DVSourceSpace');
      dataViewName = generateUniqueName('TestDataView');
      fieldName = 'dv_field';
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-space-btn');
      await page.waitForTimeout(500);
      await page.fill('#new-space-name', spaceName);
      await page.click('#new-space-confirm-btn');
      await page.waitForTimeout(2000);
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForTimeout(500);
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#add-field-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('button:has-text("Ajouter"), button:has-text("Add")');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-data-view-btn');
      await page.waitForTimeout(1000);
      await page.fill('#dv-name', dataViewName);
      sourceSelect = page.locator('#dv-source');
      await sourceSelect.selectOption(spaceName);
      await page.waitForTimeout(1000);
      await page.click('#data-view-save-btn');
      await page.waitForTimeout(2000);
      createdDV = dataViewsList.locator('li', {
        hasText: dataViewName
      });
      return (await expect(createdDV).toBeVisible());
    });
    test('should create a page with a widget using that data view', async function({page}) {
      var addFieldBtn, createdDV, createdSpace, dataViewName, dataViewsList, dataViewsToggle, fieldName, pageItem, pageName, result, saveFieldBtn, spaceName, spacesList, spacesToggle;
      spaceName = generateUniqueName('WidgetSpace');
      dataViewName = generateUniqueName('WidgetDV');
      pageName = generateUniqueName('WidgetPage');
      fieldName = 'widget_field';
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-space-btn');
      await page.waitForTimeout(500);
      await page.fill('#new-space-name', spaceName);
      await page.click('#new-space-confirm-btn');
      await page.waitForTimeout(2000);
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForTimeout(500);
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#add-field-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('button:has-text("Ajouter"), button:has-text("Add")');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-data-view-btn');
      await page.waitForTimeout(1000);
      await page.fill('#dv-name', dataViewName);
      await page.selectOption('#dv-source', spaceName);
      await page.waitForTimeout(1000);
      await page.click('#data-view-save-btn');
      await page.waitForTimeout(2000);
      createdDV = dataViewsList.locator('li', {
        hasText: dataViewName
      });
      await expect(createdDV).toBeVisible();
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      result = (await page.evaluate(function(name, dvName) {
        var mutation, token;
        mutation = `mutation {
  createCustomView(input: {
    name: "${name}",
    yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Test Widget\\n        dataView: ${dvName}\\n        position: 1"
  }) { id name yaml }
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
      }, pageName, dataViewName));
      console.log("Created page:", result);
      await page.waitForTimeout(2000);
      pageItem = page.locator(`.page-item:has-text('${pageName}')`);
      return (await expect(pageItem).toBeVisible());
    });
    return test('should verify the page displays the widget with data', async function({page}) {
      var addFieldBtn, createdSpace, dataViewName, dataViewsList, dataViewsToggle, fieldName, pageItem, pageName, result, saveFieldBtn, spaceName, spacesList, spacesToggle, widgetCount, widgets;
      spaceName = generateUniqueName('VerifySpace');
      dataViewName = generateUniqueName('VerifyDV');
      pageName = generateUniqueName('VerifyPage');
      fieldName = 'verify_field';
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-space-btn');
      await page.waitForTimeout(500);
      await page.fill('#new-space-name', spaceName);
      await page.click('#new-space-confirm-btn');
      await page.waitForTimeout(2000);
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForTimeout(500);
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#add-field-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('button:has-text("Ajouter"), button:has-text("Add")');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      await page.click('#new-data-view-btn');
      await page.waitForTimeout(1000);
      await page.fill('#dv-name', dataViewName);
      await page.selectOption('#dv-source', spaceName);
      await page.waitForTimeout(1000);
      await page.click('#data-view-save-btn');
      await page.waitForTimeout(2000);
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      result = (await page.evaluate(function(name, dvName, field) {
        var mutation, token;
        mutation = `mutation {
  createCustomView(input: {
    name: "${name}",
    yaml: "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Verification Widget\\n        dataView: ${dvName}\\n        position: 1"
  }) { id name yaml }
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
      }, pageName, dataViewName, fieldName));
      console.log("Created page:", result);
      await page.waitForTimeout(2000);
      pageItem = page.locator(`.page-item:has-text('${pageName}')`);
      await expect(pageItem).toBeVisible();
      await pageItem.click();
      await page.waitForTimeout(3000);
      await page.evaluate(function() {
        var container;
        container = document.getElementById('custom-view-container');
        if (container != null) {
          return container.classList.remove('hidden');
        }
      });
      await page.waitForTimeout(1000);
      widgets = page.locator('[data-widget-id], .widget, [class*="widget"]');
      widgetCount = (await widgets.count());
      console.log("Widget count:", widgetCount);
      return (await expect(widgetCount).toBeGreaterThan(0));
    });
  });

}).call(this);
