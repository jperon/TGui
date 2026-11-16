(function() {
  // tests/playwright/pages/widget-lua.spec.coffee
  // Widgets personnalisés en Lua / MoonScript (spec
  // docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7) :
  //   - un widget MoonScript s'exécute via wasmoon dans son iframe, reçoit les
  //     lignes de la source par onRecords et les affiche ;
  //   - un widget Lua appelle gql (promesse attendue par :await()) ;
  //   - un widget Lua 5.4 (`//`, `&`, `<<`, `<const>`, `~`) s'exécute : sa syntaxe
  //     n'est pas vérifiée côté serveur (LuaJIT 5.1) mais à l'exécution ;
  //   - un widget Lua syntaxiquement faux affiche l'erreur de wasmoon dans le
  //     widget, avec le numéro de ligne ;
  //   - une page sans widget Lua ne charge jamais wasmoon (ni le .js, ni le .wasm).
  // Le test crée son espace, ses plugins et ses pages, et les supprime à la fin.
  var WASMOON_JS, WASMOON_WASM, createPage, expect, generateUniqueName, gql, openPage, performLogin, test, watchWasmoon;

  ({test, expect} = require('@playwright/test'));

  ({performLogin, generateUniqueName} = require('../config/parallel-helper'));

  WASMOON_JS = '/vendor/wasmoon.bundle.js';

  WASMOON_WASM = '/vendor/wasmoon.bundle.wasm';

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

  // Compte les requêtes réseau vers wasmoon (JS et binaire).
  watchWasmoon = function(page) {
    var hits;
    hits = [];
    page.on('request', function(req) {
      var url;
      url = req.url();
      if (url.includes(WASMOON_JS) || url.includes(WASMOON_WASM)) {
        return hits.push(url);
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

  createPage = async function(page, name, yaml) {
    var ref, ref1, res;
    res = (await gql(page, 'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id } }', {
      input: {
        name: name,
        yaml: yaml
      }
    }));
    expect(res != null ? (ref = res.data) != null ? (ref1 = ref.createCustomView) != null ? ref1.id : void 0 : void 0 : void 0, `createCustomView ${name}: ${JSON.stringify(res)}`).toBeTruthy();
    return res.data.createCustomView.id;
  };

  test.describe.serial('Widgets Lua / MoonScript (wasmoon)', function() {
    var badLuaPageName, badLuaPluginId, badLuaPluginName, badLuaScript, htmlTemplate, lua54PageName, lua54PluginId, lua54PluginName, lua54Script, luaPageName, luaPluginId, luaPluginName, luaScript, moonPageName, moonPluginId, moonPluginName, moonScript, pageIds, plainPageName, spaceId, spaceName, stamp;
    stamp = Date.now();
    spaceName = `wlua_space_${stamp}`;
    moonPluginName = `wlua_moon_${stamp}`;
    luaPluginName = `wlua_lua_${stamp}`;
    lua54PluginName = `wlua_lua54_${stamp}`;
    badLuaPluginName = `wlua_badlua_${stamp}`;
    plainPageName = generateUniqueName('LuaPlain');
    moonPageName = generateUniqueName('LuaMoon');
    luaPageName = generateUniqueName('LuaGql');
    lua54PageName = generateUniqueName('Lua54');
    badLuaPageName = generateUniqueName('LuaBad');
    spaceId = null;
    moonPluginId = null;
    luaPluginId = null;
    lua54PluginId = null;
    badLuaPluginId = null;
    pageIds = [];
    moonScript = `widget.render "<div id='moon-loading'>chargement…</div>"
widget.onRecords (rows) ->
  items = for row in *rows
    "<li class='moon-row'>" .. tostring(row.nom) .. "</li>"
  widget.render "<ul id='moon-list'>" .. table.concat(items) .. "</ul>"`;
    luaScript = `local data = widget.gql('query { spaces { id name } }'):await()
widget.render('<div id="lua-gql">' .. tostring(#data.spaces) .. ' espaces</div>')`;
    // Syntaxes valides en Lua 5.4 (wasmoon) et refusées par LuaJIT 5.1 : le
    // serveur doit les accepter et le widget doit afficher 7//2, 5&3, 1<<4, ~0.
    lua54Script = `local a = 7 // 2
local b = 5 & 3
local c = 1 << 4
local d <const> = 10
local e = ~0
widget.render('<div id="lua54">' .. a .. ',' .. b .. ',' .. c .. ',' .. d .. ',' .. e .. '</div>')`;
    // Enregistré tel quel (aucune vérification côté serveur) : l'erreur est
    // signalée par wasmoon à l'exécution, ligne 2.
    badLuaScript = `local ok = 1
if then
  widget.render('jamais')
end`;
    htmlTemplate = `<div class="plugin-root"></div>`;
    test.beforeAll(async function({browser}) {
      var badLuaYaml, created, ctx, i, len, lua54Yaml, luaYaml, moonYaml, nom, p, plainYaml, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      created = (await gql(p, 'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }', {
        input: {
          name: spaceName,
          description: 'Widgets Lua e2e'
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
      ref4 = ['Alpha', 'Beta'];
      for (i = 0, len = ref4.length; i < len; i++) {
        nom = ref4[i];
        res = (await gql(p, 'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }', {
          sid: spaceId,
          data: {
            nom: nom
          }
        }));
        expect(res != null ? (ref5 = res.data) != null ? (ref6 = ref5.insertRecord) != null ? ref6.id : void 0 : void 0 : void 0, `insertRecord ${nom}: ${JSON.stringify(res)}`).toBeTruthy();
      }
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name compiled } }', {
        input: {
          name: moonPluginName,
          description: 'widget MoonScript (e2e)',
          scriptLanguage: 'moonscript',
          templateLanguage: 'html',
          scriptCode: moonScript,
          templateCode: htmlTemplate
        }
      }));
      expect(res != null ? (ref7 = res.data) != null ? (ref8 = ref7.createWidgetPlugin) != null ? ref8.name : void 0 : void 0 : void 0, `createWidgetPlugin moonscript: ${JSON.stringify(res)}`).toBe(moonPluginName);
      expect(res.data.createWidgetPlugin.compiled, 'compiled doit contenir le Lua compilé').toContain('widget.render');
      moonPluginId = res.data.createWidgetPlugin.id;
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }', {
        input: {
          name: luaPluginName,
          description: 'widget Lua (e2e)',
          scriptLanguage: 'lua',
          templateLanguage: 'html',
          scriptCode: luaScript,
          templateCode: htmlTemplate
        }
      }));
      expect(res != null ? (ref9 = res.data) != null ? (ref10 = ref9.createWidgetPlugin) != null ? ref10.name : void 0 : void 0 : void 0, `createWidgetPlugin lua: ${JSON.stringify(res)}`).toBe(luaPluginName);
      luaPluginId = res.data.createWidgetPlugin.id;
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name compiled } }', {
        input: {
          name: lua54PluginName,
          description: 'widget Lua 5.4 (e2e)',
          scriptLanguage: 'lua',
          templateLanguage: 'html',
          scriptCode: lua54Script,
          templateCode: htmlTemplate
        }
      }));
      expect(res != null ? (ref11 = res.data) != null ? (ref12 = ref11.createWidgetPlugin) != null ? ref12.name : void 0 : void 0 : void 0, `createWidgetPlugin lua 5.4: ${JSON.stringify(res)}`).toBe(lua54PluginName);
      expect(res.data.createWidgetPlugin.compiled, 'un Lua 5.4 doit être accepté et stocké tel quel').toContain('7 // 2');
      lua54PluginId = res.data.createWidgetPlugin.id;
      res = (await gql(p, 'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name compiled } }', {
        input: {
          name: badLuaPluginName,
          description: 'widget Lua invalide (e2e)',
          scriptLanguage: 'lua',
          templateLanguage: 'html',
          scriptCode: badLuaScript,
          templateCode: htmlTemplate
        }
      }));
      expect(res != null ? (ref13 = res.data) != null ? (ref14 = ref13.createWidgetPlugin) != null ? ref14.name : void 0 : void 0 : void 0, `createWidgetPlugin lua invalide: ${JSON.stringify(res)}`).toBe(badLuaPluginName);
      expect(res.data.createWidgetPlugin.compiled, 'un Lua invalide doit être enregistré tel quel').toContain('if then');
      badLuaPluginId = res.data.createWidgetPlugin.id;
      plainYaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        title: 'Données'
        space: '${spaceName}'`;
      pageIds.push((await createPage(p, plainPageName, plainYaml)));
      moonYaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        title: 'MoonScript'
        type: '${moonPluginName}'
        space: '${spaceName}'`;
      pageIds.push((await createPage(p, moonPageName, moonYaml)));
      luaYaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        title: 'Lua gql'
        type: '${luaPluginName}'`;
      pageIds.push((await createPage(p, luaPageName, luaYaml)));
      lua54Yaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        title: 'Lua 5.4'
        type: '${lua54PluginName}'`;
      pageIds.push((await createPage(p, lua54PageName, lua54Yaml)));
      badLuaYaml = `layout:
  direction: vertical
  children:
    - widget:
        id: w1
        title: 'Lua invalide'
        type: '${badLuaPluginName}'`;
      pageIds.push((await createPage(p, badLuaPageName, badLuaYaml)));
      return (await ctx.close());
    });
    test.afterAll(async function({browser}) {
      var ctx, i, id, len, p;
      ctx = (await browser.newContext());
      p = (await ctx.newPage());
      await performLogin(p);
      for (i = 0, len = pageIds.length; i < len; i++) {
        id = pageIds[i];
        await gql(p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', {
          id: id
        });
      }
      if (moonPluginId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: moonPluginId
        });
      }
      if (luaPluginId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: luaPluginId
        });
      }
      if (lua54PluginId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: lua54PluginId
        });
      }
      if (badLuaPluginId) {
        await gql(p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', {
          id: badLuaPluginId
        });
      }
      if (spaceId) {
        await gql(p, 'mutation($id: ID!) { deleteSpace(id: $id) }', {
          id: spaceId
        });
      }
      return (await ctx.close());
    });
    test('une page sans widget Lua ne charge pas wasmoon', async function({page}) {
      var hits;
      hits = watchWasmoon(page);
      await performLogin(page);
      await openPage(page, plainPageName);
      await expect(page.locator('.cv-widget').first()).toBeVisible();
      await expect(page.locator('.cv-widget iframe')).toHaveCount(0);
      return expect(hits, `requêtes wasmoon inattendues : ${hits.join(', ')}`).toHaveLength(0);
    });
    test('un widget MoonScript rend les lignes de onRecords', async function({page}) {
      var frame, hits, list;
      hits = watchWasmoon(page);
      await performLogin(page);
      await openPage(page, moonPageName);
      frame = page.locator('.cv-widget iframe').first();
      await expect(frame).toHaveCount(1);
      list = frame.contentFrame().locator('#moon-list');
      await expect(list).toBeVisible({
        timeout: 20000
      });
      await expect(list.locator('.moon-row')).toHaveCount(2);
      await expect(list).toContainText('Alpha');
      await expect(list).toContainText('Beta');
      // wasmoon (glue JS + binaire) n'a été demandé que pour ce widget.
      expect(hits.some(function(u) {
        return u.includes(WASMOON_JS);
      }), `wasmoon.bundle.js attendu, vu : ${hits.join(', ')}`).toBe(true);
      return expect(hits.some(function(u) {
        return u.includes(WASMOON_WASM);
      }), `wasmoon.bundle.wasm attendu, vu : ${hits.join(', ')}`).toBe(true);
    });
    test('un widget Lua lit les données par gql', async function({page}) {
      var frame, out;
      await performLogin(page);
      await openPage(page, luaPageName);
      frame = page.locator('.cv-widget iframe').first();
      await expect(frame).toHaveCount(1);
      out = frame.contentFrame().locator('#lua-gql');
      await expect(out).toBeVisible({
        timeout: 20000
      });
      await expect(out).toContainText('espaces');
      // Au moins l'espace de ce test est visible pour l'admin.
      return (await expect(out).toHaveText(/[1-9][0-9]* espaces/));
    });
    test('un widget Lua 5.4 s’exécute (// & << <const> ~)', async function({page}) {
      var frame, out;
      await performLogin(page);
      await openPage(page, lua54PageName);
      frame = page.locator('.cv-widget iframe').first();
      await expect(frame).toHaveCount(1);
      out = frame.contentFrame().locator('#lua54');
      await expect(out).toBeVisible({
        timeout: 20000
      });
      return (await expect(out).toHaveText('3,1,16,10,-1'));
    });
    return test('un widget Lua invalide affiche l’erreur et sa ligne', async function({page}) {
      var body, frame;
      await performLogin(page);
      await openPage(page, badLuaPageName);
      frame = page.locator('.cv-widget iframe').first();
      await expect(frame).toHaveCount(1);
      body = frame.contentFrame().locator('body');
      await expect(body).toContainText('exécution lua invalide', {
        timeout: 20000
      });
      // Message wasmoon : `[string "..."]:2: ...` — la ligne fautive est visible.
      return (await expect(body).toContainText(/:2:/));
    });
  });

}).call(this);
