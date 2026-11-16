(function() {
  // tests/playwright/pages/widget-plugin-security.spec.coffee
  // Sécurité des requêtes relayées depuis une iframe de widget :
  //   - un widget qui tente `createUser` reçoit une erreur GraphQL
  //     (« not allowed from a widget ») et aucun utilisateur n'est créé ;
  //   - un widget qui lit des données fonctionne encore.
  // Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §6.
  // Le test crée ses plugins et sa page, et les supprime à la fin.
  var expect, generateUniqueName, gql, performLogin, test;

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

  test.describe.serial('Widget plugin — requêtes relayées', function() {
    var evilName, evilScript, evilUser, pageId, pageName, readName, readScript, stamp;
    stamp = Date.now();
    evilName = `wsec_evil_${stamp}`;
    readName = `wsec_read_${stamp}`;
    pageName = generateUniqueName('WidgetSecu');
    evilUser = `wsec_evil_user_${stamp}`;
    pageId = null;
    evilScript = `module.exports = function (api) {
  api.gql('mutation { createUser(input: {username: "wsec_evil_user_${stamp}", email: "wsec@test.local", password: "pass1234"}) { id } }')
    .then(function () { api.render('<div id="res">ALLOWED</div>'); })
    .catch(function (e) { api.render('<div id="res">DENIED ' + e.message + '</div>'); });
};`;
    readScript = `module.exports = function (api) {
  api.gql('{ spaces { id name } }')
    .then(function (d) { api.render('<div id="res">SPACES ' + ((d.spaces || []).length) + '</div>'); })
    .catch(function (e) { api.render('<div id="res">ERR ' + e.message + '</div>'); });
};`;
    test.afterAll(async function({browser}) {
      var ctx, i, len, p, plugin, plugins, ref, ref1;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      if (pageId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: pageId
        });
      }
      plugins = (await gql(p, '{ widgetPlugins { id name } }'));
      ref1 = (plugins != null ? (ref = plugins.data) != null ? ref.widgetPlugins : void 0 : void 0) || [];
      for (i = 0, len = ref1.length; i < len; i++) {
        plugin = ref1[i];
        if (plugin.name === evilName || plugin.name === readName) {
          await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
            id: plugin.id
          });
        }
      }
      return (await ctx.close());
    });
    return test('createUser refusé dans l’iframe, lecture toujours possible', async function({page}) {
      var created, evilFrame, leaf, names, pageRes, readFrame, reader, ref, ref1, ref2, ref3, ref4, ref5, u, users, yaml;
      await performLogin(page);
      created = (await gql(page, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: evilName,
          description: 'security test',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: evilScript,
          templateCode: '<div id="res">init</div>'
        }
      }));
      expect(created != null ? (ref = created.data) != null ? (ref1 = ref.createWidgetPlugin) != null ? ref1.name : void 0 : void 0 : void 0, `createWidgetPlugin a échoué: ${JSON.stringify(created)}`).toBe(evilName);
      reader = (await gql(page, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: readName,
          description: 'security test (read)',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: readScript,
          templateCode: '<div id="res">init</div>'
        }
      }));
      expect(reader != null ? (ref2 = reader.data) != null ? (ref3 = ref2.createWidgetPlugin) != null ? ref3.name : void 0 : void 0 : void 0, `createWidgetPlugin (lecture) a échoué: ${JSON.stringify(reader)}`).toBe(readName);
      // Vraies fins de ligne : la valeur passe par les variables (JSON), pas par
      // un littéral GraphQL où il faudrait un échappement supplémentaire.
      yaml = "layout:\n  direction: vertical\n  children:\n" + `    - widget:\n        id: evil\n        title: Evil\n        type: ${evilName}\n` + `    - widget:\n        id: reader\n        title: Reader\n        type: ${readName}`;
      pageRes = (await gql(page, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: pageName,
          yaml: yaml
        }
      }));
      expect(pageRes != null ? (ref4 = pageRes.data) != null ? (ref5 = ref4.createCustomView) != null ? ref5.id : void 0 : void 0 : void 0, `createCustomView a échoué: ${JSON.stringify(pageRes)}`).toBeTruthy();
      pageId = pageRes.data.createCustomView.id;
      await page.goto('/');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      leaf = page.locator('#page-list .leaf-item', {
        hasText: pageName
      }).first();
      await expect(leaf).toBeVisible();
      await leaf.click();
      // Le widget fautif reçoit une erreur explicite dans son iframe.
      evilFrame = page.frameLocator('[data-widget-id="evil"] iframe');
      await expect(evilFrame.locator('#res')).toContainText('DENIED', {
        timeout: 15000
      });
      await expect(evilFrame.locator('#res')).toContainText('not allowed from a widget');
      // Le widget de lecture fonctionne encore (lecture autorisée).
      readFrame = page.frameLocator('[data-widget-id="reader"] iframe');
      await expect(readFrame.locator('#res')).toContainText('SPACES', {
        timeout: 15000
      });
      await expect(readFrame.locator('#res')).not.toContainText('ERR');
      // Aucun utilisateur n'a été créé côté serveur.
      users = (await gql(page, '{ users { username } }'));
      names = (function() {
        var i, len, ref6, ref7, results;
        ref7 = (users != null ? (ref6 = users.data) != null ? ref6.users : void 0 : void 0) || [];
        results = [];
        for (i = 0, len = ref7.length; i < len; i++) {
          u = ref7[i];
          results.push(u.username);
        }
        return results;
      })();
      return expect(names).not.toContain(evilUser);
    });
  });

}).call(this);
