(function() {
  // tests/playwright/data-views/multi-sort.spec.coffee
  // Tri multicritère hiérarchisé (menu « Trier / Filtrer » et en-têtes).

  // Le test crée son propre espace (deux colonnes, doublons sur la première) via
  // l'API GraphQL puis vérifie l'ordre RÉEL des lignes de la grille :
  //   - deux critères ajoutés par le menu : le premier décide, le second départage ;
  //   - glisser le second critère au-dessus du premier change l'ordre (priorité) ;
  //   - un préréglage enregistré puis réappliqué restitue les deux critères ;
  //   - Maj+clic et Ctrl+clic sur un en-tête ajoutent un critère sans effacer l'autre.
  var addCriterion, criterionColumns, expect, generateUniqueName, gql, gridPairs, openMenu, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  gql = function(page, query, variables = null) {
    return page.evaluate(function({query, variables}) {
      var token;
      token = localStorage.getItem('tdb_token');
      return fetch('/graphql', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          query: query,
          variables: variables
        })
      }).then(function(r) {
        return r.json();
      });
    }, {query, variables});
  };

  // Ordre réel des lignes (sentinelle exclue), lu sur le DataView de la grille
  // principale : c'est l'ordre trié que Toast UI Grid affiche.
  gridPairs = function(page) {
    return page.evaluate(function() {
      var dv, i, len, ref, ref1, ref2, ref3, results, row, rows;
      dv = (ref = window.App) != null ? ref._activeDataView : void 0;
      rows = (dv != null ? (ref1 = dv._grid) != null ? typeof ref1.getData === "function" ? ref1.getData() : void 0 : void 0 : void 0) || [];
      results = [];
      for (i = 0, len = rows.length; i < len; i++) {
        row = rows[i];
        if (!row.__isNew) {
          results.push([String((ref2 = row.groupe) != null ? ref2 : ''), String((ref3 = row.nom) != null ? ref3 : '')]);
        }
      }
      return results;
    });
  };

  criterionColumns = function(page) {
    return page.locator('.view-presets-sort-row .view-presets-sort-label').allTextContents();
  };

  openMenu = async function(page) {
    await page.click('.view-presets-btn');
    return (await expect(page.locator('.view-presets-menu')).toBeVisible());
  };

  addCriterion = async function(page, column, direction = 'asc') {
    await page.selectOption('.view-presets-add-column', {
      label: column
    });
    await page.selectOption('.view-presets-add-direction', direction);
    await page.click('.view-presets-add-btn');
    return (await page.waitForTimeout(300));
  };

  test.describe.serial('Tri multicritère', function() {
    var spaceId, spaceName;
    spaceName = generateUniqueName('TriMulti');
    spaceId = null;
    test.beforeAll(async function({browser}) {
      var created, ctx, fields, p, ref, ref1, ref2, ref3, ref4, ref5, rows;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      created = (await gql(p, 'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }', {
        input: {
          name: spaceName
        }
      }));
      expect(created != null ? (ref = created.data) != null ? (ref1 = ref.createSpace) != null ? ref1.id : void 0 : void 0 : void 0, `createSpace a échoué : ${JSON.stringify(created)}`).toBeTruthy();
      spaceId = created.data.createSpace.id;
      fields = (await gql(p, 'mutation($spaceId: ID!, $inputs: [FieldInput!]!) { addFields(spaceId: $spaceId, inputs: $inputs) { id name } }', {
        spaceId: spaceId,
        inputs: [
          {
            name: 'groupe',
            fieldType: 'String'
          },
          {
            name: 'nom',
            fieldType: 'String'
          }
        ]
      }));
      expect(fields != null ? (ref2 = fields.data) != null ? (ref3 = ref2.addFields) != null ? ref3.length : void 0 : void 0 : void 0, `addFields a échoué : ${JSON.stringify(fields)}`).toBe(2);
      rows = (await gql(p, 'mutation($spaceId: ID!, $data: [JSON!]!) { insertRecords(spaceId: $spaceId, data: $data) { id } }', {
        spaceId: spaceId,
        data: [
          {
            groupe: 'B',
            nom: 'a'
          },
          {
            groupe: 'A',
            nom: 'b'
          },
          {
            groupe: 'B',
            nom: 'b'
          },
          {
            groupe: 'A',
            nom: 'a'
          }
        ]
      }));
      expect(rows != null ? (ref4 = rows.data) != null ? (ref5 = ref4.insertRecords) != null ? ref5.length : void 0 : void 0 : void 0, `insertRecords a échoué : ${JSON.stringify(rows)}`).toBe(4);
      return (await ctx.close());
    });
    test.afterAll(async function({browser}) {
      var ctx, p;
      if (!spaceId) {
        return;
      }
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      await gql(p, 'mutation($id: ID!) { deleteSpace(id: $id) }', {
        id: spaceId
      });
      return (await ctx.close());
    });
    test.beforeEach(async function({page}) {
      var spacesList;
      await performLogin(page);
      spacesList = page.locator('#space-list');
      if ((await spacesList.isHidden())) {
        await page.click('#spaces-toggle-btn');
        await page.waitForTimeout(300);
      }
      await page.click(`#space-list li[data-id=\"${spaceId}\"]`);
      await expect(page.locator('.view-presets-btn')).toBeVisible();
      await expect(page.locator('#grid-container .tui-grid-cell').first()).toBeVisible();
      return (await page.waitForTimeout(500));
    });
    test('deux critères via le menu : égalités départagées par le second, puis priorité inversée', async function({page}) {
      await openMenu(page);
      await addCriterion(page, 'groupe', 'asc');
      await addCriterion(page, 'nom', 'asc');
      expect((await criterionColumns(page))).toEqual(['groupe', 'nom']);
      expect((await gridPairs(page))).toEqual([['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]);
      // Glisser le second critère au-dessus du premier (moitié haute de la ligne) :
      // il devient prioritaire et change l'ordre réel des lignes.
      await page.locator('.view-presets-sort-row').nth(1).dragTo(page.locator('.view-presets-sort-row').nth(0), {
        targetPosition: {
          x: 40,
          y: 4
        }
      });
      await page.waitForTimeout(300);
      // Le menu ne doit pas s'être fermé pendant le glissement.
      await expect(page.locator('.view-presets-menu')).toBeVisible();
      expect((await criterionColumns(page))).toEqual(['nom', 'groupe']);
      expect((await gridPairs(page))).toEqual([['A', 'a'], ['B', 'a'], ['A', 'b'], ['B', 'b']]);
      // Bascule du sens du premier critère (nom décroissant, groupe départage).
      await page.locator('.view-presets-sort-row').nth(0).locator('[data-action="dir"]').click();
      await page.waitForTimeout(300);
      return expect((await gridPairs(page))).toEqual([['A', 'b'], ['B', 'b'], ['A', 'a'], ['B', 'a']]);
    });
    test('préréglage : enregistrer puis réappliquer restitue les deux critères', async function({page}) {
      var presetName;
      presetName = `Deux critères ${Date.now()}`;
      await openMenu(page);
      await addCriterion(page, 'groupe', 'asc');
      await addCriterion(page, 'nom', 'asc');
      expect((await gridPairs(page))).toEqual([['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]);
      page.once('dialog', function(dialog) {
        return dialog.accept(presetName);
      });
      await page.click('.view-presets-save');
      await expect(page.locator('.view-presets-preset', {
        hasText: presetName
      })).toBeVisible();
      await expect(page.locator('.view-presets-btn')).toContainText(presetName);
      // Tri simple sur un en-tête : un seul critère, l'ordre change.
      await page.keyboard.press('Escape');
      await page.locator('#grid-container th[data-column-name="nom"] .tui-grid-btn-sorting').click();
      await page.waitForTimeout(500);
      await openMenu(page);
      expect((await criterionColumns(page))).toEqual(['nom']);
      // Réapplique le préréglage : les deux critères reviennent, dans l'ordre.
      await page.locator('.view-presets-preset', {
        hasText: presetName
      }).click();
      await page.waitForTimeout(500);
      expect((await gridPairs(page))).toEqual([['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']]);
      await openMenu(page);
      expect((await criterionColumns(page))).toEqual(['groupe', 'nom']);
      return (await page.keyboard.press('Escape'));
    });
    return test('Maj+clic et Ctrl+clic sur un en-tête ajoutent un critère sans effacer l’autre', async function({page}) {
      // Clic simple : tri unique (comportement inchangé).
      await page.locator('#grid-container th[data-column-name="groupe"] .tui-grid-btn-sorting').click();
      await page.waitForTimeout(500);
      await openMenu(page);
      expect((await criterionColumns(page))).toEqual(['groupe']);
      await page.keyboard.press('Escape');
      // Maj+clic ajoute le second critère en fin de liste.
      await page.locator('#grid-container th[data-column-name="nom"] .tui-grid-btn-sorting').click({
        modifiers: ['Shift']
      });
      await page.waitForTimeout(500);
      await openMenu(page);
      expect((await criterionColumns(page))).toEqual(['groupe', 'nom']);
      await page.keyboard.press('Escape');
      // Ctrl+clic : multi-tri natif de Toast UI Grid, même résultat.
      await page.locator('#grid-container th[data-column-name="groupe"] .tui-grid-btn-sorting').click();
      await page.waitForTimeout(400);
      await page.locator('#grid-container th[data-column-name="nom"] .tui-grid-btn-sorting').click({
        modifiers: ['Control']
      });
      await page.waitForTimeout(500);
      await openMenu(page);
      return expect((await criterionColumns(page))).toEqual(['groupe', 'nom']);
    });
  });

}).call(this);
