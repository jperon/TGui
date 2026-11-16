(function() {
  // tests/playwright/pages/widget-manifest.spec.coffee
  // Widget personnalisé avec manifest (spec 2026-11-16-custom-widgets-design.md
  // §3, §3 bis, §6) :
  //   - le widget est ajouté par la fenêtre « ＋ Widget » : sélecteurs de champ
  //     par colonne déclarée, option pré-remplie, mappage écrit dans le YAML ;
  //   - l'iframe reçoit les lignes renommées et son updateRecord modifie la donnée ;
  //   - un plugin access: read voit les lignes mais sa mutation est refusée.
  // Le test crée son espace, ses plugins et ses pages, et les supprime à la fin.
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

  test.describe.serial('Widget personnalisé — manifest, mappage et API', function() {
    var fullId, fullManifest, fullName, fullScript, readId, readManifest, readName, readPageId, readPageName, spaceId, spaceName, stamp, windowPageId, windowPageName;
    stamp = Date.now();
    spaceName = `wman_ev_${stamp}`;
    fullName = `wman_cal_${stamp}`;
    readName = `wman_read_${stamp}`;
    windowPageName = generateUniqueName('WidgetManifest');
    readPageName = generateUniqueName('WidgetManifestRead');
    spaceId = null;
    fullId = null;
    readId = null;
    windowPageId = null;
    readPageId = null;
    fullManifest = `access: full
columns:
  - {name: titre, type: String}
  - {name: debut, type: Date}
  - {name: fin, type: Date, optional: true}
options:
  - {name: couleur, type: color, default: '#36c'}`;
    readManifest = `access: read
columns:
  - {name: titre, type: String}`;
    fullScript = `module.exports = function (api) {
  var wrote = false;
  api.onRecords(function (rows) {
    var html = rows.map(function (r) {
      return '<div class="rec">' + r.titre + '|' + r.debut + '</div>';
    }).join('');
    api.render(
      '<div id="rows">' + html + '</div>' +
      '<div id="status">' + (wrote ? 'UPDATED' : 'INIT') + '</div>' +
      '<div id="param">' + api.params.couleur + '</div>'
    );
    if (!wrote && rows.length) {
      wrote = true;
      api.updateRecord(rows[0].id, { titre: 'MODIFIÉ' });
    }
  });
};`;
    test.beforeAll(async function({browser}) {
      var created, ctx, input, j, k, len, len1, p, readScript, readYaml, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, row;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      // Source : deux colonnes (nom, date_debut) et deux lignes.
      created = (await gql(p, 'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }', {
        input: {
          name: spaceName,
          description: 'Widget manifest e2e'
        }
      }));
      expect(created != null ? (ref = created.data) != null ? (ref1 = ref.createSpace) != null ? ref1.id : void 0 : void 0 : void 0, `createSpace a échoué: ${JSON.stringify(created)}`).toBeTruthy();
      spaceId = created.data.createSpace.id;
      ref2 = [
        {
          name: 'nom',
          fieldType: 'String',
          notNull: true,
          description: ''
        },
        {
          name: 'date_debut',
          fieldType: 'Datetime',
          notNull: false,
          description: ''
        }
      ];
      for (j = 0, len = ref2.length; j < len; j++) {
        input = ref2[j];
        res = (await gql(p, 'mutation($sid: ID!, $input: FieldInput!) { addField(spaceId: $sid, input: $input) { id name } }', {
          sid: spaceId,
          input
        }));
        expect(res != null ? (ref3 = res.data) != null ? (ref4 = ref3.addField) != null ? ref4.name : void 0 : void 0 : void 0, `addField: ${JSON.stringify(res)}`).toBe(input.name);
      }
      ref5 = [
        {
          nom: 'Alpha',
          date_debut: '2026-01-01T00:00:00Z'
        },
        {
          nom: 'Beta',
          date_debut: '2026-02-02T00:00:00Z'
        }
      ];
      for (k = 0, len1 = ref5.length; k < len1; k++) {
        row = ref5[k];
        res = (await gql(p, 'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }', {
          sid: spaceId,
          data: row
        }));
        expect(res != null ? (ref6 = res.data) != null ? (ref7 = ref6.insertRecord) != null ? ref7.id : void 0 : void 0 : void 0, `insertRecord: ${JSON.stringify(res)}`).toBeTruthy();
      }
      // Deux définitions : accès full (écrit) et read (mutation refusée).
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: fullName,
          description: 'calendrier (manifest)',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: fullScript,
          templateCode: '<div>init</div>',
          manifest: fullManifest
        }
      }));
      expect(res != null ? (ref8 = res.data) != null ? (ref9 = ref8.createWidgetPlugin) != null ? ref9.name : void 0 : void 0 : void 0, `createWidgetPlugin (full): ${JSON.stringify(res)}`).toBe(fullName);
      fullId = res.data.createWidgetPlugin.id;
      readScript = `module.exports = function (api) {
  api.onRecords(function (rows) {
    if (!rows.length) return;
    api.gql('mutation { updateRecord(spaceId: "${spaceId}", id: "' + rows[0].id + '", data: "{\\"nom\\":\\"HACK\\"}") { id } }')
      .then(function () { api.render('<div id="res">ALLOWED</div>'); })
      .catch(function (e) { api.render('<div id="res">DENIED ' + e.message + '</div>'); });
  });
};`;
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: readName,
          description: 'lecteur (read)',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: readScript,
          templateCode: '<div id="res">init</div>',
          manifest: readManifest
        }
      }));
      expect(res != null ? (ref10 = res.data) != null ? (ref11 = ref10.createWidgetPlugin) != null ? ref11.name : void 0 : void 0 : void 0, `createWidgetPlugin (read): ${JSON.stringify(res)}`).toBe(readName);
      readId = res.data.createWidgetPlugin.id;
      // Page vide pour l'ajout par la fenêtre, et page du widget en lecture.
      res = (await gql(p, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: windowPageName,
          yaml: "layout:\n  direction: vertical\n  children: []"
        }
      }));
      expect(res != null ? (ref12 = res.data) != null ? (ref13 = ref12.createCustomView) != null ? ref13.id : void 0 : void 0 : void 0, `createCustomView (fenêtre): ${JSON.stringify(res)}`).toBeTruthy();
      windowPageId = res.data.createCustomView.id;
      readYaml = "layout:\n  direction: vertical\n  children:\n" + "    - widget:\n        id: reader\n        title: Lecteur\n" + `        space: ${spaceName}\n        type: '${readName}'\n` + "        columns:\n          titre: nom\n";
      res = (await gql(p, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }', {
        input: {
          name: readPageName,
          yaml: readYaml
        }
      }));
      expect(res != null ? (ref14 = res.data) != null ? (ref15 = ref14.createCustomView) != null ? ref15.id : void 0 : void 0 : void 0, `createCustomView (lecture): ${JSON.stringify(res)}`).toBeTruthy();
      readPageId = res.data.createCustomView.id;
      return (await ctx.close());
    });
    test.afterAll(async function({browser}) {
      var ctx, p;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      if (windowPageId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: windowPageId
        });
      }
      if (readPageId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: readPageId
        });
      }
      if (fullId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: fullId
        });
      }
      if (readId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: readId
        });
      }
      if (spaceId) {
        await gql(p, 'mutation($id: ID!) { deleteSpace(id: $id) }', {
          id: spaceId
        });
      }
      return (await ctx.close());
    });
    test('ajouté par la fenêtre : mappage, lignes renommées, updateRecord', async function({page}) {
      var debutSelect, frame, i, items, leaf, modal, names, pluginOption, records, ref, ref1, ref2, ref3, saved, savedYaml, titreSelect, widget;
      await performLogin(page);
      await page.goto('/');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      leaf = page.locator('#page-list .leaf-item', {
        hasText: windowPageName
      }).first();
      await expect(leaf).toBeVisible();
      await leaf.click();
      await expect(page.locator('#custom-view-container')).toBeVisible();
      // 1. Fenêtre « ＋ Widget » : choisir le widget personnalisé.
      await page.click('#yaml-add-widget-btn');
      modal = page.locator('#add-widget-modal');
      await expect(modal).toBeVisible();
      pluginOption = page.locator('#widget-type-plugin-list .widget-type-option', {
        hasText: fullName
      }).first();
      await expect(pluginOption).toBeVisible();
      await pluginOption.locator('label').click();
      await expect(pluginOption.locator('input[type="radio"]')).toBeChecked();
      await page.fill('#widget-title-input', 'Calendrier');
      await page.selectOption('#widget-space-select', {
        label: spaceName
      });
      // 2. Le formulaire du manifest remplace les paires clé/valeur.
      await expect(page.locator('#widget-params-pairs')).toBeHidden();
      titreSelect = page.locator('#widget-manifest-form .manifest-column-select[data-declared="titre"]');
      debutSelect = page.locator('#widget-manifest-form .manifest-column-select[data-declared="debut"]');
      await expect(titreSelect).toBeVisible();
      await expect(debutSelect).toBeVisible();
      // Les champs de la source sont proposés, filtrés par type (Datetime seulement).
      await expect(titreSelect.locator('option[value="nom"]')).toHaveCount(1);
      await expect(debutSelect.locator('option[value="date_debut"]')).toHaveCount(1);
      await expect(debutSelect.locator('option[value="nom"]')).toHaveCount(0);
      await titreSelect.selectOption('nom');
      await debutSelect.selectOption('date_debut');
      // Option color : la valeur par défaut du manifest est pré-remplie (le
      // navigateur normalise '#36c' en '#3366cc').
      await expect(page.locator('#widget-manifest-form input[data-option="couleur"]')).toHaveValue('#3366cc');
      await page.click('#add-widget-confirm-btn');
      await expect(modal).toBeHidden();
      // 3. Le YAML de page porte le mappage et l'option, l'iframe les lignes renommées.
      saved = (await gql(page, 'query($id: ID!) { customView(id: $id) { yaml } }', {
        id: windowPageId
      }));
      savedYaml = (saved != null ? (ref = saved.data) != null ? (ref1 = ref.customView) != null ? ref1.yaml : void 0 : void 0 : void 0) || '';
      expect(savedYaml, `YAML enregistré: ${savedYaml}`).toContain('columns:');
      expect(savedYaml, `YAML enregistré: ${savedYaml}`).toContain('titre: nom');
      expect(savedYaml, `YAML enregistré: ${savedYaml}`).toContain('debut: date_debut');
      expect(savedYaml, `YAML enregistré: ${savedYaml}`).toContain(`type: '${fullName}'`);
      widget = page.locator(`.cv-widget[data-widget-type=\"${fullName}\"]`);
      await expect(widget).toBeVisible();
      frame = widget.locator('iframe').contentFrame();
      await expect(frame.locator('#param')).toHaveText('#3366cc', {
        timeout: 15000
      });
      await expect(frame.locator('#status')).toHaveText('UPDATED', {
        timeout: 15000
      });
      await expect(frame.locator('#rows')).toContainText('MODIFIÉ', {
        timeout: 15000
      });
      await expect(frame.locator('#rows')).toContainText('Beta');
      // 4. L'écriture est bien en base ; la seconde ligne est intacte.
      records = (await gql(page, 'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }', {
        sid: spaceId,
        limit: 10
      }));
      items = (records != null ? (ref2 = records.data) != null ? (ref3 = ref2.records) != null ? ref3.items : void 0 : void 0 : void 0) || [];
      names = (function() {
        var j, len, results;
        results = [];
        for (j = 0, len = items.length; j < len; j++) {
          i = items[j];
          if (typeof i.data === 'string') {
            results.push(JSON.parse(i.data).nom);
          } else {
            results.push(i.data.nom);
          }
        }
        return results;
      })();
      expect(names, `données en base: ${JSON.stringify(names)}`).toContain('MODIFIÉ');
      return expect(names).toContain('Beta');
    });
    return test('access: read — mutation refusée, données inchangées', async function({page}) {
      var frame, i, items, leaf, names, records, ref, ref1;
      await performLogin(page);
      await page.goto('/');
      await page.waitForSelector('#main', {
        state: 'visible'
      });
      leaf = page.locator('#page-list .leaf-item', {
        hasText: readPageName
      }).first();
      await expect(leaf).toBeVisible();
      await leaf.click();
      await expect(page.locator('#custom-view-container')).toBeVisible();
      frame = page.frameLocator('[data-widget-id="reader"] iframe');
      await expect(frame.locator('#res')).toContainText('DENIED', {
        timeout: 15000
      });
      await expect(frame.locator('#res')).toContainText('lectures');
      records = (await gql(page, 'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }', {
        sid: spaceId,
        limit: 10
      }));
      items = (records != null ? (ref = records.data) != null ? (ref1 = ref.records) != null ? ref1.items : void 0 : void 0 : void 0) || [];
      names = (function() {
        var j, len, results;
        results = [];
        for (j = 0, len = items.length; j < len; j++) {
          i = items[j];
          if (typeof i.data === 'string') {
            results.push(JSON.parse(i.data).nom);
          } else {
            results.push(i.data.nom);
          }
        }
        return results;
      })();
      return expect(names, `aucune écriture HACK: ${JSON.stringify(names)}`).not.toContain('HACK');
    });
  });

}).call(this);
