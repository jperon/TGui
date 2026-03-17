(function() {
  // Relations E2E Tests
  // Tests relation operations between spaces through fields panel
  var expect, generateUniqueName, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  test.describe('Relations', function() {
    test.beforeEach(async function({page}) {
      await performLogin(page);
      return (await page.waitForTimeout(2000));
    });
    test('should access relations section in fields panel', async function({page}) {
      var fieldsAddForm, fieldsBtn, fieldsList, fieldsPanel, firstSpace, spacesList, spacesToggle;
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      firstSpace = page.locator('#space-list li').first();
      if ((await firstSpace.count()) > 0) {
        await firstSpace.click();
        await page.waitForTimeout(1000);
      }
      fieldsBtn = page.locator('#fields-btn');
      await fieldsBtn.click();
      await page.waitForTimeout(500);
      fieldsPanel = page.locator('#fields-panel');
      await expect(fieldsPanel).toBeVisible();
      fieldsList = page.locator('#fields-list');
      await expect(fieldsList).toBeVisible();
      fieldsAddForm = page.locator('.fields-add-form');
      return (await expect(fieldsAddForm).toBeVisible());
    });
    test('should create a new relation between two spaces', async function({page}) {
      var fieldAddBtn, fieldName, fieldType, fieldsList, firstSpaceName, options, relReprRow, relTargetRow, relToSpace, secondSpaceName, spaceCount, spaceItems, spacesList, spacesToggle;
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      spaceItems = page.locator('#space-list li');
      spaceCount = (await spaceItems.count());
      if (spaceCount < 2) {
        firstSpaceName = generateUniqueName('TestSpace');
        await page.click('#new-space-btn');
        await page.waitForTimeout(500);
        await page.fill('#new-space-name', firstSpaceName);
        await page.click('#new-space-confirm-btn');
        await page.waitForTimeout(2000);
        secondSpaceName = generateUniqueName('TargetSpace');
        await page.click('#new-space-btn');
        await page.waitForTimeout(500);
        await page.fill('#new-space-name', secondSpaceName);
        await page.click('#new-space-confirm-btn');
        await page.waitForTimeout(2000);
      }
      await page.locator('#space-list li').first().click();
      await page.waitForTimeout(1000);
      await page.click('#fields-btn');
      await page.waitForTimeout(500);
      fieldName = page.locator('#field-name');
      await fieldName.fill('test_relation');
      await page.waitForTimeout(300);
      fieldType = page.locator('#field-type');
      await fieldType.selectOption('Relation');
      await page.waitForTimeout(500);
      relTargetRow = page.locator('#rel-target-row');
      await expect(relTargetRow).toBeVisible();
      relToSpace = page.locator('#rel-to-space');
      options = (await relToSpace.locator('option').count());
      if (options > 1) {
        await relToSpace.selectOption({
          index: 1
        });
        await page.waitForTimeout(500);
        relReprRow = page.locator('#rel-repr-row');
        await expect(relReprRow).toBeVisible();
        fieldAddBtn = page.locator('#field-add-btn');
        await fieldAddBtn.click();
        await page.waitForTimeout(2000);
        fieldsList = page.locator('#fields-list');
        return (await expect(fieldsList).toContainText('test_relation'));
      }
    });
    test('should edit a relation', async function({page}) {
      var editBtn, fieldAddBtn, firstRelation, relReprFormula, relationCount, relationFields, spaceItems, spacesList, spacesToggle;
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      spaceItems = page.locator('#space-list li');
      if ((await spaceItems.count()) > 0) {
        await spaceItems.first().click();
        await page.waitForTimeout(1000);
        await page.click('#fields-btn');
        await page.waitForTimeout(500);
        relationFields = page.locator('#fields-list li');
        relationCount = (await relationFields.count());
        if (relationCount > 0) {
          firstRelation = relationFields.first();
          editBtn = firstRelation.locator('button[title="Modifier ce champ"]');
          await editBtn.click();
          await page.waitForTimeout(500);
          relReprFormula = page.locator('#rel-repr-formula');
          await relReprFormula.fill('self.id');
          await page.waitForTimeout(300);
          fieldAddBtn = page.locator('#field-add-btn');
          await fieldAddBtn.click();
          return (await page.waitForTimeout(2000));
        }
      }
    });
    return test('should delete a relation', async function({page}) {
      var deleteBtn, firstRelation, relationCount, relationFields, spaceItems, spacesList, spacesToggle;
      spacesList = page.locator('#space-list');
      spacesToggle = page.locator('#spaces-toggle-btn');
      if ((await spacesList.isHidden())) {
        await spacesToggle.click();
        await page.waitForTimeout(500);
      }
      spaceItems = page.locator('#space-list li');
      if ((await spaceItems.count()) > 0) {
        await spaceItems.first().click();
        await page.waitForTimeout(1000);
        await page.click('#fields-btn');
        await page.waitForTimeout(500);
        relationFields = page.locator('#fields-list li');
        relationCount = (await relationFields.count());
        if (relationCount > 0) {
          firstRelation = relationFields.first();
          deleteBtn = firstRelation.locator('button[title="Supprimer ce champ"]');
          page.on('dialog', function(dialog) {
            return dialog.accept();
          });
          await deleteBtn.click();
          return (await page.waitForTimeout(2000));
        }
      }
    });
  });

}).call(this);
