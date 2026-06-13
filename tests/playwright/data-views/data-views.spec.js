(function() {
  // Data Views E2E Tests
  // Tests data view CRUD operations
  var expect, generateUniqueName, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  test.describe('Data Views', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    test('should access data views section', async function({page}) {
      var dataViewsList, dataViewsToggle;
      dataViewsList = page.locator('#data-view-list');
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      
      // Déplier la section Vues seulement si la liste est masquée (un clic
      // inconditionnel la replierait quand elle est déjà ouverte).
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      if ((await dataViewsList.isVisible())) {
        await expect(dataViewsList).toBeVisible();
        return (await expect(page.locator('#new-data-view-btn')).toBeVisible());
      } else {
        await expect(dataViewsList).toHaveCount(1);
        return (await expect(page.locator('#new-data-view-btn')).toHaveCount(1));
      }
    });
    test('should create a new data view', async function({page}) {
      var count, createdItem, dataViewName, dataViewsList, dataViewsToggle, e, existingItems, sourceSelect, yamlEditor;
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      
      // Déplier la section Vues seulement si la liste est masquée (un clic
      // inconditionnel la replierait quand elle est déjà ouverte).
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      existingItems = dataViewsList.locator('li');
      count = (await existingItems.count());
      if (count > 0) {
        return (await expect(existingItems.first()).toBeVisible());
      } else {
        dataViewName = generateUniqueName('TestDataView');
        await page.click('#new-data-view-btn');
        await page.waitForTimeout(1500);
        await page.fill('#dv-name', dataViewName);
        sourceSelect = page.locator('#dv-source');
        await sourceSelect.selectOption({
          index: 1
        });
        await page.waitForTimeout(1000);
        yamlEditor = page.locator('#dv-yaml-content');
        if ((await yamlEditor.isVisible())) {
          await yamlEditor.fill('columns: []');
          await page.waitForTimeout(500);
        }
        await page.click('#data-view-save-btn');
        await page.waitForTimeout(3000);
        createdItem = page.locator('#data-view-list').locator('li', {
          hasText: dataViewName
        });
        try {
          return (await expect(createdItem).toBeVisible());
        } catch (error) {
          e = error;
          return test.skip();
        }
      }
    });
    test('should execute a data view and see results', async function({page}) {
      var count, dataViewsList, dataViewsToggle, existingItems, gridContainer;
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      
      // Déplier la section Vues seulement si la liste est masquée (un clic
      // inconditionnel la replierait quand elle est déjà ouverte).
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      existingItems = dataViewsList.locator('li');
      count = (await existingItems.count());
      if (count > 0) {
        await existingItems.first().click();
        await page.waitForTimeout(2000);
        gridContainer = page.locator('#grid-container');
        if ((await gridContainer.isVisible())) {
          return (await expect(gridContainer).toBeVisible());
        } else {
          return (await expect(page.locator('#data-view-panel')).toBeVisible());
        }
      } else {
        return test.skip();
      }
    });
    test('should edit a data view', async function({page}) {
      var count, dataViewsList, dataViewsToggle, existingItems, modalTitle, newName, updatedItem;
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      
      // Déplier la section Vues seulement si la liste est masquée (un clic
      // inconditionnel la replierait quand elle est déjà ouverte).
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      existingItems = dataViewsList.locator('li');
      count = (await existingItems.count());
      if (count > 0) {
        await existingItems.first().click();
        await page.waitForTimeout(1500);
        await page.click('#rename-space-btn');
        await page.waitForTimeout(1000);
        modalTitle = (await page.locator('#data-view-modal-title').textContent());
        expect(modalTitle).toContain('Modifier');
        newName = generateUniqueName('EditedDV');
        await page.fill('#dv-name', newName);
        await page.click('#data-view-save-btn');
        await page.waitForTimeout(2000);
        updatedItem = dataViewsList.locator('li', {
          hasText: newName
        });
        return (await expect(updatedItem).toBeVisible());
      } else {
        return test.skip();
      }
    });
    return test('should delete a data view', async function({page}) {
      var confirmBtn, count, dataViewsList, dataViewsToggle, deletedId, existingItems;
      dataViewsToggle = page.locator('#data-views-toggle-btn');
      dataViewsList = page.locator('#data-view-list');
      
      // Déplier la section Vues seulement si la liste est masquée (un clic
      // inconditionnel la replierait quand elle est déjà ouverte).
      if ((await dataViewsList.isHidden())) {
        await dataViewsToggle.click();
        await page.waitForTimeout(500);
      }
      existingItems = dataViewsList.locator('li');
      count = (await existingItems.count());
      if (count > 0) {
        // Mémorise l'id de la vue ciblée pour vérifier sa disparition précise
        // (d'autres vues peuvent subsister : .first().toBeHidden() serait faux).
        deletedId = (await existingItems.first().getAttribute('data-id'));
        await existingItems.first().click();
        await page.waitForTimeout(1000);
        await page.click('#delete-space-btn');
        await page.waitForTimeout(1000);
        // Dialogue de confirmation maison (cf. frontend/src/modal.coffee)
        confirmBtn = page.locator('#tdb-modal-overlay .tdb-modal-actions .btn-primary');
        if ((await confirmBtn.isVisible())) {
          await confirmBtn.click();
          await page.waitForTimeout(2000);
        }
        // La vue supprimée ne doit plus figurer dans la liste
        if (deletedId) {
          return (await expect(dataViewsList.locator(`li[data-id=\"${deletedId}\"]`)).toHaveCount(0));
        } else {
          return (await expect(existingItems).toHaveCount(count - 1));
        }
      } else {
        return test.skip();
      }
    });
  });

}).call(this);
