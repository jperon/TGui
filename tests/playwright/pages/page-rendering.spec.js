(function() {
  // tests/playwright/pages/page-rendering.spec.coffee
  // Régression navigateur : une page (custom view) doit AFFICHER ses widgets.

  // Garde trois bugs corrigés ensemble :
  //   - sortablejs.bundle.js absent de la page (drag & drop / pages cassés)
  //   - renderCustomViewPreview n'appelait pas CustomView.mount()
  //   - #custom-view-container restait masqué (classe 'hidden')
  // Le test est autonome : il crée sa page via l'API et la supprime à la fin.
  var expect, generateUniqueName, gql, performLogin, test;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  gql = function(page, query) {
    return page.evaluate(function(q) {
      var token;
      token = localStorage.getItem('tdb_token');
      return fetch('/graphql', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          query: q
        })
      }).then(function(r) {
        return r.json();
      });
    }, query);
  };

  test.describe('Page rendering', function() {
    var createdId, pageName;
    pageName = generateUniqueName('RenderPage');
    createdId = null;
    test.afterAll(async function({browser}) {
      var ctx, p;
      if (!createdId) {
        return;
      }
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      await gql(p, `mutation { deleteCustomView(id: \"${createdId}\") }`);
      return (await ctx.close());
    });
    return test('a page displays its widget grid with data', async function({page}) {
      var container, grid, pageLeaf, ref, ref1, res, sortableLoaded, yaml;
      await performLogin(page);
      // SortableJS doit être chargé (sinon les pages avec zones cassent)
      sortableLoaded = (await page.evaluate(function() {
        return typeof Sortable !== 'undefined';
      }));
      expect(sortableLoaded, 'SortableJS doit être chargé').toBe(true);
      // Crée une page avec un widget sur l'espace de démo "Livres"
      yaml = "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Catalogue\\n        space: Livres\\n        columns: [titre, isbn]";
      res = (await gql(page, `mutation { createCustomView(input: { name: \"${pageName}\", yaml: \"${yaml}\" }) { id name } }`));
      expect(res != null ? (ref = res.data) != null ? (ref1 = ref.createCustomView) != null ? ref1.id : void 0 : void 0 : void 0, `createCustomView a échoué: ${JSON.stringify(res)}`).toBeTruthy();
      createdId = res.data.createCustomView.id;
      // Recharge complètement l'app (session déjà active) puis ouvre la page
      await page.goto('/');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      pageLeaf = page.locator('#page-list .leaf-item', {
        hasText: pageName
      }).first();
      await expect(pageLeaf).toBeVisible();
      await pageLeaf.click();
      // Le conteneur d'aperçu doit devenir visible et contenir une grille avec des lignes
      container = page.locator('#custom-view-container');
      await expect(container).toBeVisible();
      grid = container.locator('.tui-grid-container, [class*="tui-grid"]');
      await expect(grid.first()).toBeVisible();
      // Au moins une ligne de données (les livres de démo)
      return (await expect(container.locator('.tui-grid-cell').first()).toBeVisible());
    });
  });

}).call(this);
