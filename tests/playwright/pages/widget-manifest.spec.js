(function() {
  // tests/playwright/pages/widget-manifest.spec.coffee
  // Widget personnalisé avec manifest (spec 2026-11-16-custom-widgets-design.md
  // §3, §6) : mappage de colonnes, API onRecords/onRecord renommée, updateRecord
  // depuis l'iframe (access: full), et refus d'une mutation avec access: read.
  // Le test crée son espace, ses plugins et sa page, et les supprime à la fin.
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
    var fullId, fullManifest, fullName, fullScript, pageId, pageName, readId, readManifest, readName, spaceId, spaceName, stamp;
    stamp = Date.now();
    spaceName = `wman_ev_${stamp}`;
    fullName = `wman_cal_${stamp}`;
    readName = `wman_read_${stamp}`;
    pageName = generateUniqueName('WidgetManifest');
    spaceId = null;
    fullId = null;
    readId = null;
    pageId = null;
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
  api.onRecord(function (rec) {
    if (rec && !wrote) api.render('<div id="row">' + rec.titre + '</div>');
  });
};`;
    test.afterAll(async function({browser}) {
      var ctx, p;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      if (pageId) {
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: pageId
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
    return test('mappage + onRecords + updateRecord, et mutation refusée en lecture', async function({page}) {
      var created, frame, fullScriptCode, i, input, items, j, k, leaf, len, len1, names, readFrame, readScript, records, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, row, yaml;
      await performLogin(page);
      // 1. Source : deux colonnes (nom, date_debut) et deux lignes.
      created = (await gql(page, 'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }', {
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
        res = (await gql(page, 'mutation($sid: ID!, $input: FieldInput!) { addField(spaceId: $sid, input: $input) { id name } }', {
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
        res = (await gql(page, 'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }', {
          sid: spaceId,
          data: row
        }));
        expect(res != null ? (ref6 = res.data) != null ? (ref7 = ref6.insertRecord) != null ? ref7.id : void 0 : void 0 : void 0, `insertRecord: ${JSON.stringify(res)}`).toBeTruthy();
      }
      // 2. Deux définitions : accès full (écrit) et read (mutation refusée).
      fullScriptCode = fullScript;
      res = (await gql(page, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: fullName,
          description: 'calendrier (manifest)',
          scriptLanguage: 'javascript',
          templateLanguage: 'html',
          scriptCode: fullScriptCode,
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
      res = (await gql(page, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
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
      // 3. Page avec mappage de colonnes (la fenêtre écrit la même chose).
      yaml = "layout:\n  direction: vertical\n  children:\n" + "    - widget:\n        id: cal\n        title: Calendrier\n" + `        space: ${spaceName}\n        type: '${fullName}'\n` + "        columns:\n          titre: nom\n          debut: date_debut\n" + "        params:\n          couleur: '#c33'\n" + "    - widget:\n        id: reader\n        title: Lecteur\n" + `        space: ${spaceName}\n        type: '${readName}'\n` + "        columns:\n          titre: nom\n";
      res = (await gql(page, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name yaml } }', {
        input: {
          name: pageName,
          yaml: yaml
        }
      }));
      expect(res != null ? (ref12 = res.data) != null ? (ref13 = ref12.createCustomView) != null ? ref13.id : void 0 : void 0 : void 0, `createCustomView: ${JSON.stringify(res)}`).toBeTruthy();
      pageId = res.data.createCustomView.id;
      expect(res.data.createCustomView.yaml, 'mapping écrit').toContain('titre: nom');
      // 4. Ouvrir la page.
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
      // 5. Le widget full reçoit les lignes renommées (titre/debut) et l'option,
      //    puis son updateRecord modifie la donnée et recharge les lignes.
      frame = page.frameLocator('[data-widget-id="cal"] iframe');
      await expect(frame.locator('#param')).toHaveText('#c33', {
        timeout: 15000
      });
      // L'écriture peut précéder la première assertion : la ligne mise à jour
      // (renommée `titre`) doit être là, avec la seconde ligne intacte.
      await expect(frame.locator('#status')).toHaveText('UPDATED', {
        timeout: 15000
      });
      await expect(frame.locator('#rows')).toContainText('MODIFIÉ', {
        timeout: 15000
      });
      await expect(frame.locator('#rows')).toContainText('Beta');
      records = (await gql(page, 'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }', {
        sid: spaceId,
        limit: 10
      }));
      items = (records != null ? (ref14 = records.data) != null ? (ref15 = ref14.records) != null ? ref15.items : void 0 : void 0 : void 0) || [];
      names = (function() {
        var l, len2, results;
        results = [];
        for (l = 0, len2 = items.length; l < len2; l++) {
          i = items[l];
          if (typeof i.data === 'string') {
            results.push(JSON.parse(i.data).nom);
          } else {
            results.push(i.data.nom);
          }
        }
        return results;
      })();
      expect(names, `données en base: ${JSON.stringify(names)}`).toContain('MODIFIÉ');
      expect(names).toContain('Beta');
      // 6. Le widget read voit les lignes mais sa mutation est refusée côté parent.
      readFrame = page.frameLocator('[data-widget-id="reader"] iframe');
      await expect(readFrame.locator('#res')).toContainText('DENIED', {
        timeout: 15000
      });
      await expect(readFrame.locator('#res')).toContainText('lectures');
      // ... et la base n'a pas reçu « HACK ».
      records = (await gql(page, 'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }', {
        sid: spaceId,
        limit: 10
      }));
      items = (records != null ? (ref16 = records.data) != null ? (ref17 = ref16.records) != null ? ref17.items : void 0 : void 0 : void 0) || [];
      names = (function() {
        var l, len2, results;
        results = [];
        for (l = 0, len2 = items.length; l < len2; l++) {
          i = items[l];
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
