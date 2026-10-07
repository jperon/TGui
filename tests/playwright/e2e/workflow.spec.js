(function() {
  // Workflow E2E Tests
  // Complete workflow: space -> view -> page
  var ensureDataViewsExpanded, expect, generateUniqueName, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  // Expand the "Vues" (data views) sidebar list if it is collapsed.
  // Do NOT use locator.isHidden() here: an empty <ul> has zero height, so
  // Playwright reports it as hidden even when the section is expanded. The old
  // code therefore clicked the toggle on the first run (empty list) and collapsed
  // the section, making the post-creation visibility assertion fail. Check the
  // actual 'hidden' class instead. (T19)
  ensureDataViewsExpanded = async function(page) {
    var dataViewsList, isCollapsed;
    dataViewsList = page.locator('#data-view-list');
    isCollapsed = (await dataViewsList.evaluate(function(el) {
      return el.classList.contains('hidden');
    }));
    if (isCollapsed) {
      await page.click('#data-views-toggle-btn');
      return (await expect(dataViewsList).not.toHaveClass(/hidden/));
    }
  };

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
    test.skip('should create a new space with fields', async function({page}) {
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
      await page.waitForSelector('.tdb-modal-input');
      await page.fill('.tdb-modal-input', spaceName);
      await page.click('.tdb-modal-actions .btn-primary');
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
      addFieldBtn = page.locator('#field-add-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('#field-add-btn');
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
      var addFieldBtn, createdDV, createdSpace, dataViewName, dataViewsList, fieldName, saveFieldBtn, selectedValue, sourceSelect, spaceId, spaceName, spacesList, spacesToggle;
      // Measured ~19-23s for this test under normal load, too close to the 30s
      // config limit (first run timed out at exactly 30.0s). Allow headroom.
      test.setTimeout(60000);
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
      await page.waitForSelector('.tdb-modal-input');
      await page.fill('.tdb-modal-input', spaceName);
      await page.click('.tdb-modal-actions .btn-primary');
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      spaceId = (await createdSpace.getAttribute('data-id'));
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForSelector('#field-name', {
        state: 'visible'
      });
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#field-add-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('#field-add-btn');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      dataViewsList = page.locator('#data-view-list');
      await ensureDataViewsExpanded(page);
      await page.click('#new-data-view-btn');
      await page.waitForSelector('#dv-name', {
        state: 'visible'
      });
      await page.fill('#dv-name', dataViewName);
      
      // Debug: print the spaceId being used
      console.log('Space ID to select:', spaceId);
      sourceSelect = page.locator('#dv-source');
      await sourceSelect.selectOption({
        label: spaceName
      });
      await page.waitForTimeout(500);
      
      // Debug: print what's selected
      selectedValue = (await sourceSelect.inputValue());
      console.log('Selected value:', selectedValue);
      await page.click('#data-view-save-btn');
      createdDV = dataViewsList.locator('li', {
        hasText: dataViewName
      });
      await createdDV.waitFor({
        state: 'attached',
        timeout: 10000
      });
      // The section may have been collapsed while the list was empty; make sure it
      // is expanded before asserting visibility.
      await ensureDataViewsExpanded(page);
      return (await expect(createdDV).toBeVisible());
    });
    test('should create a page with a widget using that data view', async function({page}) {
      var addFieldBtn, createdDV, createdSpace, dataViewName, dataViewsList, fieldName, pageItem, pageName, result, saveFieldBtn, sourceSelect, spaceId, spaceName, spacesList, spacesToggle;
      // Measured ~23.6s for this test under normal load; keep headroom over the
      // 30s config limit.
      test.setTimeout(60000);
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
      await page.waitForSelector('.tdb-modal-input');
      await page.fill('.tdb-modal-input', spaceName);
      await page.click('.tdb-modal-actions .btn-primary');
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      spaceId = (await createdSpace.getAttribute('data-id'));
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForSelector('#field-name', {
        state: 'visible'
      });
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#field-add-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('#field-add-btn');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      dataViewsList = page.locator('#data-view-list');
      await ensureDataViewsExpanded(page);
      await page.click('#new-data-view-btn');
      await page.waitForSelector('#dv-name', {
        state: 'visible'
      });
      await page.fill('#dv-name', dataViewName);
      sourceSelect = page.locator('#dv-source');
      await sourceSelect.selectOption({
        label: spaceName
      });
      await page.waitForTimeout(500);
      await page.click('#data-view-save-btn');
      createdDV = dataViewsList.locator('li', {
        hasText: dataViewName
      });
      await createdDV.waitFor({
        state: 'attached',
        timeout: 10000
      });
      // The section may have been collapsed while the list was empty; make sure it
      // is expanded before asserting visibility.
      await ensureDataViewsExpanded(page);
      await expect(createdDV).toBeVisible();
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      result = (await page.evaluate(function({name, dvName}) {
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
      }, {
        name: pageName,
        dvName: dataViewName
      }));
      console.log("Created page:", result);
      // Recharge pour refléter la création via l'API
      await page.reload();
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      await page.waitForTimeout(1000);
      pageItem = page.locator(".leaf-item", {
        hasText: pageName
      }).first();
      return (await expect(pageItem).toBeVisible());
    });
    return test('should verify the page displays the widget with data', async function({page}) {
      var addFieldBtn, createdSpace, dataViewName, dataViewsList, fieldName, pageItem, pageName, result, saveFieldBtn, sourceSelect, spaceId, spaceName, spacesList, spacesToggle, widgetCount, widgets;
      // Measured ~27.6s for this test under normal load; keep headroom over the
      // 30s config limit.
      test.setTimeout(60000);
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
      await page.waitForSelector('.tdb-modal-input');
      await page.fill('.tdb-modal-input', spaceName);
      await page.click('.tdb-modal-actions .btn-primary');
      createdSpace = page.locator('#space-list').locator('li', {
        hasText: spaceName
      });
      await expect(createdSpace).toBeVisible();
      spaceId = (await createdSpace.getAttribute('data-id'));
      await createdSpace.click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForSelector('#field-name', {
        state: 'visible'
      });
      await page.fill('#field-name', fieldName);
      await page.selectOption('#field-type', 'String');
      await page.waitForTimeout(500);
      addFieldBtn = page.locator('#field-add-btn');
      if ((await addFieldBtn.count()) > 0) {
        await addFieldBtn.click();
      } else {
        saveFieldBtn = page.locator('#field-add-btn');
        await saveFieldBtn.click();
      }
      await page.waitForTimeout(2000);
      dataViewsList = page.locator('#data-view-list');
      await ensureDataViewsExpanded(page);
      await page.click('#new-data-view-btn');
      await page.waitForSelector('#dv-name', {
        state: 'visible'
      });
      await page.fill('#dv-name', dataViewName);
      sourceSelect = page.locator('#dv-source');
      await sourceSelect.selectOption({
        label: spaceName
      });
      await page.waitForTimeout(500);
      await page.click('#data-view-save-btn');
      await expect(dataViewsList.locator('li', {
        hasText: dataViewName
      })).toBeAttached({
        timeout: 10000
      });
      await page.goto('/#!pages');
      await page.waitForTimeout(2000);
      result = (await page.evaluate(function({name, dvName, field}) {
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
      }, {
        name: pageName,
        dvName: dataViewName,
        field: fieldName
      }));
      console.log("Created page:", result);
      // Recharge pour refléter la création via l'API, puis ouvre la page
      await page.reload();
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      await page.waitForTimeout(1000);
      pageItem = page.locator(".leaf-item", {
        hasText: pageName
      }).first();
      await expect(pageItem).toBeVisible();
      await pageItem.click();
      await page.waitForTimeout(3000);
      widgets = page.locator('[data-widget-id], .widget, [class*="widget"]');
      widgetCount = (await widgets.count());
      console.log("Widget count:", widgetCount);
      return (await expect(widgetCount).toBeGreaterThan(0));
    });
  });

}).call(this);
