(function() {
  // Widget definition scopes, end to end (spec
  // docs/superpowers/specs/2026-11-16-custom-widgets-design.md §5).

  // Scenario: an author exports an app whose page uses a library definition. The
  // package embeds only the referenced definition with `origin: library`. On the
  // instance, both the local definition and the delivered one have changed: the
  // install preview shows the conflict (with the affected pages and the access of
  // the delivered code) and defaults to "import under another name". Applying it
  // keeps the local definition, creates `<name>_imported` and rewrites the page's
  // `type:` so the page still renders.

  // Every run uses a unique stamp; the package is subset to this run's items (the
  // shared test DB holds the other suites' objects).
  var BASE, adminToken, confirmModal, expect, fs, generateUniqueName, gql, openAppsPanel, performLogin, test, yamlArg;

  fs = require('fs');

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  BASE = 'http://localhost:8081';

  gql = async function(query, variables, token) {
    var headers, json, ref, res;
    headers = {
      'Content-Type': 'application/json'
    };
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
    res = (await fetch(`${BASE}/graphql`, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify({query, variables})
    }));
    json = (await res.json());
    if ((ref = json.errors) != null ? ref.length : void 0) {
      throw new Error(`GraphQL error: ${JSON.stringify(json.errors)}`);
    }
    return json.data;
  };

  adminToken = async function() {
    var data;
    data = (await gql('mutation { login(username:"admin", password:"adminadmin") { token } }'));
    return data.login.token;
  };

  yamlArg = function(value) {
    return JSON.stringify(value);
  };

  // Opens Administration ▸ Applications (export / install panel).
  openAppsPanel = async function(page) {
    await expect(page.locator('#admin-toggle-btn')).toBeVisible();
    await page.click('#admin-toggle-btn');
    await page.click('#admin-nav-apps');
    return (await expect(page.locator('#admin-apps-section')).toBeVisible());
  };

  confirmModal = async function(page) {
    var primary;
    primary = page.locator('.tdb-modal-overlay:not(.hidden) .btn-primary');
    await expect(primary).toBeVisible();
    return (await primary.click());
  };

  test.describe.serial('Widget scopes — export then install under another name', function() {
    var appId, importedName, packageYaml, pageId, pageName, pluginId, pluginName, scriptCode, spaceName, stamp, templateCode;
    stamp = `${Date.now()}`;
    spaceName = generateUniqueName('E2EScope');
    pluginName = `e2e_scope_plugin_${stamp}`;
    importedName = `${pluginName}_imported`;
    pageName = generateUniqueName('E2EScopePage');
    appId = `org.test.e2e.scope.${stamp}`;
    pageId = null;
    pluginId = null;
    packageYaml = null;
    scriptCode = `module.exports = function (api) {
  var value = (api.params && api.params.valeur) || 'none';
  api.render('<div id="scope-res">IMPORTED ' + value + '</div>');
};`;
    templateCode = '<div id="scope-res">init</div>';
    test.beforeAll(async function() {
      var created, pageRes, pageYaml, plugin, spaceId, token;
      token = (await adminToken());
      created = (await gql('mutation($input: CreateSpaceInput!){ createSpace(input:$input){ id name } }', {
        input: {
          name: spaceName,
          description: 'Espace scopes'
        }
      }, token));
      spaceId = created.createSpace.id;
      await gql('mutation($sid: ID!, $input: FieldInput!){ addField(spaceId:$sid, input:$input){ id } }', {
        sid: spaceId,
        input: {
          name: 'nom',
          fieldType: 'String',
          notNull: false,
          description: 'Nom'
        }
      }, token);
      // Library definition (no appId) + a page whose widget references it by name.
      plugin = (await gql('mutation($input: CreateWidgetPluginInput!){ createWidgetPlugin(input:$input){ id name appId } }', {
        input: {
          name: pluginName,
          description: 'Définition de bibliothèque',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: scriptCode,
          templateCode: templateCode
        }
      }, token));
      pluginId = plugin.createWidgetPlugin.id;
      expect(plugin.createWidgetPlugin.appId).toBeNull();
      pageYaml = "layout:\n  direction: vertical\n  children:\n    - widget:\n" + `        title: Scope\n        space: ${spaceName}\n        type: '${pluginName}'\n` + "        params: {valeur: 'ok'}\n";
      pageRes = (await gql('mutation($input: CreateCustomViewInput!){ createCustomView(input:$input){ id name yaml } }', {
        input: {
          name: pageName,
          description: '',
          yaml: pageYaml
        }
      }, token));
      pageId = pageRes.createCustomView.id;
      return expect(pageId).toBeTruthy();
    });
    test.afterAll(async function() {
      var definitions, i, j, len, len1, p, ref, ref1, ref2, results, s, spaces, token;
      token = (await adminToken());
      if (pageId) {
        await gql('mutation($id: ID!){ deleteCustomView(id:$id) }', {
          id: pageId
        }, token);
      }
      definitions = (await gql('{ widgetPlugins { id name } }', {}, token));
      ref = definitions.widgetPlugins || [];
      for (i = 0, len = ref.length; i < len; i++) {
        p = ref[i];
        if ((ref1 = p.name) === pluginName || ref1 === importedName) {
          await gql('mutation($id: ID!){ deleteWidgetPlugin(id:$id) }', {
            id: p.id
          }, token);
        }
      }
      spaces = (await gql('{ spaces { id name } }', {}, token));
      ref2 = spaces.spaces || [];
      results = [];
      for (j = 0, len1 = ref2.length; j < len1; j++) {
        s = ref2[j];
        if (s.name === spaceName) {
          results.push((await gql('mutation($id: ID!){ deleteSpace(id:$id) }', {
            id: s.id
          }, token)));
        }
      }
      return results;
    });
    test('1. the export embeds the referenced library definition', async function({page}) {
      var decoded, token, yamlText;
      test.setTimeout(90000);
      await performLogin(page);
      token = (await adminToken());
      yamlText = ((await gql(`query($meta: AppMetaInput!){ exportApp(meta:$meta) }`, {
        meta: {
          id: appId,
          name: `E2E Scope ${stamp}`,
          version: '1.0.0',
          description: ''
        }
      }, token))).exportApp;
      // Keep only this run's items (space, fields, page, definition), as a real
      // minimal app would. Done in the browser: js-yaml is loaded by the app.
      packageYaml = (await page.evaluate(function({yamlText, stamp}) {
        var doc;
        doc = jsyaml.load(yamlText);
        doc.items = doc.items.filter(function(it) {
          return String(it.key).indexOf(stamp) >= 0;
        });
        doc.seed_keys = {};
        return jsyaml.dump(doc);
      }, {
        yamlText: yamlText,
        stamp: stamp
      }));
      decoded = (await page.evaluate(function({yamlText}) {
        var doc;
        doc = jsyaml.load(yamlText);
        return {
          keys: doc.items.map(function(it) {
            return it.key;
          }),
          plugins: doc.items.filter(function(it) {
            return it.type === 'plugin';
          })
        };
      }, {
        yamlText: packageYaml
      }));
      expect(decoded.keys).toContain(`space:${spaceName}`);
      expect(decoded.keys).toContain(`page:${pageName}`);
      expect(decoded.keys).toContain(`plugin:${pluginName}`);
      expect(decoded.plugins.length).toBe(1);
      return expect(decoded.plugins[0].origin).toBe('library');
    });
    test('2. conflict preview shows pages and access, defaults to a new name', async function({page}) {
      var changed, conflict, definitions, imported, local, names, p, renameRadio, saved, token;
      test.setTimeout(120000);
      expect(packageYaml).not.toBeNull();
      await performLogin(page);
      token = (await adminToken());
      // The author changes the delivered definition (v1.1.0)...
      changed = (await page.evaluate(function({yamlText}) {
        var doc, plugin;
        doc = jsyaml.load(yamlText);
        plugin = doc.items.find(function(it) {
          return it.type === 'plugin';
        });
        plugin.content.description = 'Définition livrée v1.1';
        doc.app.version = '1.1.0';
        return jsyaml.dump(doc);
      }, {
        yamlText: packageYaml
      }));
      packageYaml = changed;
      // ... and the instance modified its own copy: both sides differ -> conflict.
      await gql('mutation($id: ID!, $input: UpdateWidgetPluginInput!){ updateWidgetPlugin(id:$id, input:$input){ id } }', {
        id: pluginId,
        input: {
          description: 'Modifié localement'
        }
      }, token);
      await openAppsPanel(page);
      await page.setInputFiles('#apps-package-input', {
        name: `${appId}-1.1.0.tdbapp.yaml`,
        mimeType: 'text/yaml',
        buffer: Buffer.from(packageYaml)
      });
      await expect(page.locator('#apps-plan-box')).toBeVisible({
        timeout: 20000
      });
      conflict = page.locator('#apps-plan-box .apps-conflict', {
        hasText: `plugin:${pluginName}`
      });
      await expect(conflict).toBeVisible();
      // Affected pages and the access of the delivered code are displayed.
      await expect(conflict.locator('.apps-conflict-pages')).toContainText(pageName);
      await expect(conflict.locator('.apps-plugin-access')).toContainText(/complet|full/);
      // "Import under another name" is the default choice, with a prefilled name.
      renameRadio = conflict.locator('input[type="radio"][value="rename"]');
      await expect(renameRadio).toBeChecked();
      await expect(conflict.locator('.apps-conflict-newname-input')).toHaveValue(importedName);
      await page.click('#apps-apply-btn');
      await confirmModal(page);
      await expect(page.locator('#apps-apply-report')).toBeVisible();
      await expect(page.locator('#apps-apply-report')).toContainText(/1|créé|created/i);
      // The local definition is kept, the delivered copy is imported, the page
      // now references the imported name.
      definitions = (await gql('{ widgetPlugins { id name description appId } }', {}, token));
      names = (function() {
        var i, len, ref, results;
        ref = definitions.widgetPlugins;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          p = ref[i];
          results.push(p.name);
        }
        return results;
      })();
      expect(names).toContain(pluginName);
      expect(names).toContain(importedName);
      local = definitions.widgetPlugins.find(function(p) {
        return p.name === pluginName;
      });
      expect(local.description).toBe('Modifié localement');
      imported = definitions.widgetPlugins.find(function(p) {
        return p.name === importedName;
      });
      expect(imported.description).toBe('Définition livrée v1.1');
      expect(imported.appId).toBeNull();
      saved = ((await gql('query($id: ID!){ customView(id:$id){ yaml } }', {
        id: pageId
      }, token))).customView.yaml;
      return expect(saved).toContain(`type: '${importedName}'`);
    });
    return test('3. the page still renders through the imported definition', async function({page}) {
      var frame, leaf, widget;
      test.setTimeout(90000);
      await performLogin(page);
      await page.goto('/');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      leaf = page.locator('#page-list .leaf-item', {
        hasText: pageName
      }).first();
      await expect(leaf).toBeVisible();
      await leaf.click();
      await expect(page.locator('#custom-view-container')).toBeVisible();
      widget = page.locator(`.cv-widget[data-widget-type=\"${importedName}\"]`);
      await expect(widget).toBeVisible();
      frame = page.frameLocator(`.cv-widget[data-widget-type=\"${importedName}\"] iframe`);
      return (await expect(frame.locator('#scope-res')).toContainText('IMPORTED ok', {
        timeout: 15000
      }));
    });
  });

}).call(this);
