(function() {
  // tests/playwright/pages/lazy-plugin-runtime.spec.coffee
  // Chargement à la demande des compilateurs de widgets (spec
  // docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7, L6) :
  //   - une page sans widget personnalisé ne demande jamais
  //     /vendor/plugin-runtime.bundle.js (il n'est plus dans SCRIPT_SRCS) ;
  //   - une page avec un widget CoffeeScript/pug charge le bundle une seule fois
  //     (deux widgets simultanés partagent la promesse) et s'affiche.
  // Le test crée son espace, son plugin et ses pages, et les supprime à la fin.
  var RUNTIME_URL, expect, generateUniqueName, gql, openPage, performLogin, test, watchRuntime;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  RUNTIME_URL = '/vendor/plugin-runtime.bundle.js';

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

  // Compte les requêtes réseau vers le bundle des compilateurs.
  watchRuntime = function(page) {
    var hits;
    hits = [];
    page.on('request', function(req) {
      if (req.url().includes(RUNTIME_URL)) {
        return hits.push(req.url());
      }
    });
    return hits;
  };

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

  test.describe.serial('Compilateurs de widgets chargés à la demande', function() {
    var csPageId, csPageName, csScript, csTemplate, plainPageId, plainPageName, pluginId, pluginName, spaceId, spaceName, stamp;
    stamp = Date.now();
    spaceName = `lazy_ev_${stamp}`;
    pluginName = `lazy_cs_${stamp}`;
    plainPageName = generateUniqueName('LazyPlain');
    csPageName = generateUniqueName('LazyCoffee');
    spaceId = null;
    pluginId = null;
    plainPageId = null;
    csPageId = null;
    csScript = `module.exports = (api) ->
  titre = if api.params and api.params.titre then api.params.titre else 'sans-titre'
  api.render "<div id='res'>CS \#{titre}</div>"`;
    csTemplate = `div#tpl= params.title`;
    test.beforeAll(async function({browser}) {
      var created, csYaml, ctx, p, plainYaml, ref, ref1, ref10, ref11, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      created = (await gql(p, 'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }', {
        input: {
          name: spaceName,
          description: 'Lazy runtime e2e'
        }
      }));
      expect(created != null ? (ref = created.data) != null ? (ref1 = ref.createSpace) != null ? ref1.id : void 0 : void 0 : void 0, `createSpace a échoué: ${JSON.stringify(created)}`).toBeTruthy();
      spaceId = created.data.createSpace.id;
      res = (await gql(p, 'mutation($sid: ID!, $input: FieldInput!) { addField(spaceId: $sid, input: $input) { id name } }', {
        sid: spaceId,
        input: {
          name: 'nom',
          fieldType: 'String',
          notNull: false,
          description: ''
        }
      }));
      expect(res != null ? (ref2 = res.data) != null ? (ref3 = ref2.addField) != null ? ref3.name : void 0 : void 0 : void 0, `addField: ${JSON.stringify(res)}`).toBe('nom');
      res = (await gql(p, 'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }', {
        sid: spaceId,
        data: {
          nom: 'Alpha'
        }
      }));
      expect(res != null ? (ref4 = res.data) != null ? (ref5 = ref4.insertRecord) != null ? ref5.id : void 0 : void 0 : void 0, `insertRecord: ${JSON.stringify(res)}`).toBeTruthy();
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: pluginName,
          description: 'widget CoffeeScript (lazy)',
          scriptLanguage: 'coffeescript',
          templateLanguage: 'pug',
          scriptCode: csScript,
          templateCode: csTemplate
        }
      }));
      expect(res != null ? (ref6 = res.data) != null ? (ref7 = ref6.createWidgetPlugin) != null ? ref7.name : void 0 : void 0 : void 0, `createWidgetPlugin: ${JSON.stringify(res)}`).toBe(pluginName);
      pluginId = res.data.createWidgetPlugin.id;
      plainYaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        title: 'Données'
        space: '${spaceName}'`;
      res = (await gql(p, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: plainPageName,
          yaml: plainYaml
        }
      }));
      expect(res != null ? (ref8 = res.data) != null ? (ref9 = ref8.createCustomView) != null ? ref9.id : void 0 : void 0 : void 0, `createCustomView (plain): ${JSON.stringify(res)}`).toBeTruthy();
      plainPageId = res.data.createCustomView.id;
      csYaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        type: '${pluginName}'
        params:
          titre: 'Un'
    - widget:
        id: w2
        type: '${pluginName}'
        params:
          titre: 'Deux'`;
      res = (await gql(p, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: csPageName,
          yaml: csYaml
        }
      }));
      expect(res != null ? (ref10 = res.data) != null ? (ref11 = ref10.createCustomView) != null ? ref11.id : void 0 : void 0 : void 0, `createCustomView (coffee): ${JSON.stringify(res)}`).toBeTruthy();
      csPageId = res.data.createCustomView.id;
      return (await ctx.close());
    });
    test.afterAll(async function({browser}) {
      var ctx, p;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      if (plainPageId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: plainPageId
        });
      }
      if (csPageId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: csPageId
        });
      }
      if (pluginId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: pluginId
        });
      }
      if (spaceId) {
        await gql(p, 'mutation($id: ID!) { deleteSpace(id: $id) }', {
          id: spaceId
        });
      }
      return (await ctx.close());
    });
    test('une page sans widget personnalisé ne charge aucun compilateur', async function({page}) {
      var hits, widget;
      hits = watchRuntime(page);
      await performLogin(page);
      await openPage(page, plainPageName);
      // Un widget de données normal est bien rendu…
      widget = page.locator('.cv-widget');
      await expect(widget.first()).toBeVisible();
      await expect(page.locator('.cv-widget iframe')).toHaveCount(0);
      // …et aucun compilateur n'a été demandé (le bundle n'est plus un script de
      // page : la moindre requête signalerait une régression du découpage).
      return expect(hits, `requêtes inattendues : ${hits.join(', ')}`).toHaveLength(0);
    });
    test('l’éditeur de plugins affiche le code sans charger les compilateurs', async function({page}) {
      var hits, modal, option;
      hits = watchRuntime(page);
      await performLogin(page);
      await page.click('#plugins-nav-manage');
      modal = page.locator('#widget-plugin-modal');
      await expect(modal).toBeVisible();
      // Le plugin CoffeeScript est sélectionnable et son script s'affiche : la
      // compilation n'a lieu qu'au rendu d'un widget, pas dans l'éditeur.
      // Le libellé des options est « <nom> — <portée> » : on sélectionne par
      // valeur (id du plugin, connu depuis la création) pour ne pas dépendre du
      // libellé exact, et on vérifie au passage que le nom y figure.
      option = page.locator(`#widget-plugin-select option[value='${pluginId}']`);
      await expect(option).toContainText(pluginName);
      await page.selectOption('#widget-plugin-select', pluginId);
      // CodeMirror rend le script dans le DOM du modal (pas de compilation).
      await expect(modal).toContainText('module.exports', {
        timeout: 10000
      });
      return expect(hits, `requêtes inattendues : ${hits.join(', ')}`).toHaveLength(0);
    });
    return test('une page avec un widget CoffeeScript charge le bundle une seule fois', async function({page}) {
      var frames, hits;
      hits = watchRuntime(page);
      await performLogin(page);
      await openPage(page, csPageName);
      frames = page.locator('.cv-widget iframe');
      await expect(frames).toHaveCount(2);
      await expect(frames.nth(0).contentFrame().locator('#res')).toContainText('CS Un', {
        timeout: 15000
      });
      await expect(frames.nth(1).contentFrame().locator('#res')).toContainText('CS Deux', {
        timeout: 15000
      });
      return expect(hits.length, `un seul chargement attendu, vu : ${hits.join(', ')}`).toBe(1);
    });
  });

}).call(this);
