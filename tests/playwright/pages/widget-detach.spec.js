(function() {
  // tests/playwright/pages/widget-detach.spec.coffee
  // « Détacher » une instance de widget personnalisé depuis l'interface (spec
  // docs/superpowers/specs/2026-11-16-custom-widgets-design.md §4) :
  //   - le bouton apparaît sur chaque instance, en édition de page, pour un admin ;
  //   - le clic demande un nom (pré-rempli), détache l'instance choisie et la page
  //     continue d'afficher son widget ;
  //   - la copie prend le nom demandé, l'autre instance et l'autre page gardent la
  //     définition d'origine ; modifier la copie ne change que l'instance détachée.
  // Le test crée son plugin et ses pages, et les supprime à la fin.
  var expect, generateUniqueName, gql, performLogin, test, typeCount;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  gql = function(page, query, variables) {
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
    }, {
      query: query,
      variables: variables
    });
  };

  typeCount = function(text, name) {
    var escaped, matches;
    escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    matches = text.match(new RegExp(`type:\\s*'?${escaped}'?`, 'g'));
    return (matches || []).length;
  };

  test.describe.serial('Widget personnalisé — détacher une instance', function() {
    var copyId, copyName, copyScript, openPage, originalScript, pageOneId, pageOneName, pageTwoId, pageTwoName, pluginId, pluginName, stamp, yamlWith;
    stamp = Date.now();
    pluginName = `wdetach_src_${stamp}`;
    copyName = `wdetach_copy_${stamp}`;
    pageOneName = generateUniqueName('WidgetDetach');
    pageTwoName = generateUniqueName('WidgetDetachOther');
    pageOneId = null;
    pageTwoId = null;
    pluginId = null;
    copyId = null;
    originalScript = "module.exports = function (api) { " + "api.render('<div id=\"mark\">' + (api.params && api.params.label ? api.params.label : 'ORIGINAL') + '</div>'); };";
    copyScript = "module.exports = function (api) { " + "api.render('<div id=\"mark\">COPY:' + (api.params && api.params.label ? api.params.label : '') + '</div>'); };";
    yamlWith = function(ids) {
      var children, i, id;
      children = (function() {
        var j, len, results;
        results = [];
        for (i = j = 0, len = ids.length; j < len; i = ++j) {
          id = ids[i];
          results.push("    - widget:\n" + `        id: ${id}\n` + `        title: Widget ${i + 1}\n` + `        type: '${pluginName}'\n` + "        params:\n" + `          label: '${i === 0 ? 'Alpha' : 'Beta'}'\n`);
        }
        return results;
      })();
      return "layout:\n  direction: vertical\n  children:\n" + children.join('');
    };
    test.beforeAll(async function({browser}) {
      var ctx, p, ref, ref1, ref2, ref3, ref4, ref5, res;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: pluginName,
          description: 'détacher (source)',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: originalScript,
          templateCode: '<div>init</div>'
        }
      }));
      expect(res != null ? (ref = res.data) != null ? (ref1 = ref.createWidgetPlugin) != null ? ref1.name : void 0 : void 0 : void 0, `createWidgetPlugin a échoué: ${JSON.stringify(res)}`).toBe(pluginName);
      pluginId = res.data.createWidgetPlugin.id;
      // Page 1 : DEUX instances du même plugin (celle de gauche reste l'originale).
      res = (await gql(p, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: pageOneName,
          yaml: yamlWith(['w_detach_a', 'w_detach_b'])
        }
      }));
      expect(res != null ? (ref2 = res.data) != null ? (ref3 = ref2.createCustomView) != null ? ref3.id : void 0 : void 0 : void 0, `createCustomView (page 1): ${JSON.stringify(res)}`).toBeTruthy();
      pageOneId = res.data.createCustomView.id;
      // Page 2 : une autre page qui utilise la même définition.
      res = (await gql(p, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: pageTwoName,
          yaml: yamlWith(['w_detach_c'])
        }
      }));
      expect(res != null ? (ref4 = res.data) != null ? (ref5 = ref4.createCustomView) != null ? ref5.id : void 0 : void 0 : void 0, `createCustomView (page 2): ${JSON.stringify(res)}`).toBeTruthy();
      pageTwoId = res.data.createCustomView.id;
      return (await ctx.close());
    });
    test.afterAll(async function({browser}) {
      var ctx, id, j, len, p, ref;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      if (pageOneId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: pageOneId
        });
      }
      if (pageTwoId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: pageTwoId
        });
      }
      ref = [copyId, pluginId];
      for (j = 0, len = ref.length; j < len; j++) {
        id = ref[j];
        if (id) {
          await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
            id: id
          });
        }
      }
      return (await ctx.close());
    });
    openPage = async function(page, name) {
      var leaf;
      await page.goto('/');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      leaf = page.locator('#page-list .leaf-item', {
        hasText: name
      }).first();
      await expect(leaf).toBeVisible();
      await leaf.click();
      return (await expect(page.locator('#custom-view-container')).toBeVisible());
    };
    return test('détache la seconde instance depuis l’interface, sans toucher l’autre', async function({page}) {
      var copy, definitions, frameA, frameB, frameC, modal, nameInput, original, other, otherYaml, pluginModal, plugins, ref, ref1, ref2, ref3, ref4, res, saved, widgetA, widgetB, yamlText;
      await performLogin(page);
      await openPage(page, pageOneName);
      // Deux instances du plugin, chacune avec son bouton « Détacher ».
      widgetA = page.locator('.cv-widget[data-widget-id="w_detach_a"]');
      widgetB = page.locator('.cv-widget[data-widget-id="w_detach_b"]');
      await expect(widgetA).toBeVisible();
      await expect(widgetB).toBeVisible();
      await expect(page.locator('.cv-widget-detach-btn')).toHaveCount(2);
      await expect(widgetA.locator('.cv-widget-detach-btn')).toBeVisible();
      // Les deux widgets affichent leur contenu avant le détachement.
      frameA = widgetA.locator('iframe').contentFrame();
      frameB = widgetB.locator('iframe').contentFrame();
      await expect(frameA.locator('#mark')).toHaveText('Alpha', {
        timeout: 15000
      });
      await expect(frameB.locator('#mark')).toHaveText('Beta', {
        timeout: 15000
      });
      // Action « Détacher » sur la seconde instance : nom pré-rempli puis modifié.
      await widgetB.locator('.cv-widget-detach-btn').click();
      modal = page.locator('#tdb-modal-overlay');
      await expect(modal).toBeVisible();
      nameInput = modal.locator('.tdb-modal-input');
      await expect(nameInput).toHaveValue(new RegExp(pluginName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
      await expect(nameInput).toHaveValue(new RegExp(pageOneName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
      await nameInput.fill(copyName);
      await modal.locator('.tdb-modal-actions .btn-primary').click();
      // L'éditeur de définitions s'ouvre sur la copie.
      pluginModal = page.locator('#widget-plugin-modal');
      await expect(pluginModal).toBeVisible();
      await expect(page.locator('#widget-plugin-name')).toHaveValue(copyName);
      await page.click('#widget-plugin-modal-close-btn');
      await expect(pluginModal).toBeHidden();
      // La page affiche toujours ses deux widgets.
      await expect(page.locator('.cv-widget[data-widget-type]')).toHaveCount(2);
      await expect(page.locator('.cv-widget[data-widget-id="w_detach_a"] iframe')).toBeVisible();
      await expect(page.locator('.cv-widget[data-widget-id="w_detach_b"] iframe')).toBeVisible();
      // Une seule instance réécrite (params conservés), l'autre page est intacte.
      saved = (await gql(page, 'query($id: ID!) { customView(id: $id) { yaml } }', {
        id: pageOneId
      }));
      yamlText = (saved != null ? (ref = saved.data) != null ? (ref1 = ref.customView) != null ? ref1.yaml : void 0 : void 0 : void 0) || '';
      expect(typeCount(yamlText, pluginName), `une seule instance sur l'original: ${yamlText}`).toBe(1);
      expect(typeCount(yamlText, copyName), `une seule instance détachée: ${yamlText}`).toBe(1);
      expect(yamlText, 'params de l’instance détachée conservés').toContain("label: 'Beta'");
      other = (await gql(page, 'query($id: ID!) { customView(id: $id) { yaml } }', {
        id: pageTwoId
      }));
      otherYaml = (other != null ? (ref2 = other.data) != null ? (ref3 = ref2.customView) != null ? ref3.yaml : void 0 : void 0 : void 0) || '';
      expect(typeCount(otherYaml, pluginName), `l'autre page garde l'original: ${otherYaml}`).toBe(1);
      expect(typeCount(otherYaml, copyName)).toBe(0);
      // La copie est une définition distincte, dans la portée de la page (ici la
      // bibliothèque : la page n'appartient à aucune app).
      plugins = (await gql(page, 'query($pageId: ID!) { widgetPlugins(pageId: $pageId) { id name appId scriptCode } }', {
        pageId: pageOneId
      }));
      definitions = (plugins != null ? (ref4 = plugins.data) != null ? ref4.widgetPlugins : void 0 : void 0) || [];
      copy = definitions.find(function(def) {
        return def.name === copyName;
      });
      expect(copy, `la copie doit exister: ${JSON.stringify(definitions)}`).toBeTruthy();
      copyId = copy.id;
      expect(copy.appId).toBeNull();
      original = definitions.find(function(def) {
        return def.name === pluginName;
      });
      expect(original.scriptCode).toBe(originalScript);
      // Modifier la copie ne change que l'instance détachée.
      res = (await gql(page, 'mutation($id: ID!, $input: UpdateWidgetPluginInput!) { updateWidgetPlugin(id: $id, input: $input) { id } }', {
        id: copyId,
        input: {
          scriptCode: copyScript
        }
      }));
      expect(res != null ? res.errors : void 0, `updateWidgetPlugin: ${JSON.stringify(res)}`).toBeFalsy();
      await openPage(page, pageOneName);
      frameA = page.locator('.cv-widget[data-widget-id="w_detach_a"] iframe').contentFrame();
      frameB = page.locator('.cv-widget[data-widget-id="w_detach_b"] iframe').contentFrame();
      await expect(frameA.locator('#mark')).toHaveText('Alpha', {
        timeout: 15000
      });
      await expect(frameB.locator('#mark')).toHaveText('COPY:Beta', {
        timeout: 15000
      });
      // L'autre page n'est pas affectée non plus.
      await openPage(page, pageTwoName);
      frameC = page.locator('.cv-widget[data-widget-id="w_detach_c"] iframe').contentFrame();
      return (await expect(frameC.locator('#mark')).toHaveText('Alpha', {
        timeout: 15000
      }));
    });
  });

}).call(this);
