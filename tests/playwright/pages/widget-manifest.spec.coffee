# tests/playwright/pages/widget-manifest.spec.coffee
# Widget personnalisé avec manifest (spec 2026-11-16-custom-widgets-design.md
# §3, §6) : mappage de colonnes, API onRecords/onRecord renommée, updateRecord
# depuis l'iframe (access: full), et refus d'une mutation avec access: read.
# Le test crée son espace, ses plugins et sa page, et les supprime à la fin.

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

gql = (page, query, variables) ->
  page.evaluate ({ query, variables }) ->
    token = localStorage.getItem 'tdb_token'
    fetch('/graphql', {
      method: 'POST'
      headers: { 'Content-Type': 'application/json', 'Authorization': "Bearer #{token}" }
      body: JSON.stringify({ query: query, variables: variables })
    }).then (r) -> r.json()
  , { query: query, variables: variables }

test.describe.serial 'Widget personnalisé — manifest, mappage et API', ->
  stamp = Date.now()
  spaceName = "wman_ev_#{stamp}"
  fullName = "wman_cal_#{stamp}"
  readName = "wman_read_#{stamp}"
  pageName = generateUniqueName 'WidgetManifest'
  spaceId = null
  fullId = null
  readId = null
  pageId = null

  fullManifest = """
  access: full
  columns:
    - {name: titre, type: String}
    - {name: debut, type: Date}
    - {name: fin, type: Date, optional: true}
  options:
    - {name: couleur, type: color, default: '#36c'}
  """

  readManifest = """
  access: read
  columns:
    - {name: titre, type: String}
  """

  fullScript = """
  module.exports = function (api) {
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
  };
  """

  test.afterAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    if pageId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: pageId }
    if fullId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: fullId }
    if readId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: readId }
    if spaceId
      await gql p, 'mutation($id: ID!) { deleteSpace(id: $id) }', { id: spaceId }
    await ctx.close()

  test 'mappage + onRecords + updateRecord, et mutation refusée en lecture', ({ page }) ->
    await performLogin page

    # 1. Source : deux colonnes (nom, date_debut) et deux lignes.
    created = await gql page,
      'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }',
      { input: { name: spaceName, description: 'Widget manifest e2e' } }
    expect(created?.data?.createSpace?.id,
      "createSpace a échoué: #{JSON.stringify(created)}").toBeTruthy()
    spaceId = created.data.createSpace.id

    for input in [
      { name: 'nom', fieldType: 'String', notNull: true, description: '' }
      { name: 'date_debut', fieldType: 'Datetime', notNull: false, description: '' }
    ]
      res = await gql page,
        'mutation($sid: ID!, $input: FieldInput!) { addField(spaceId: $sid, input: $input) { id name } }',
        { sid: spaceId, input }
      expect(res?.data?.addField?.name, "addField: #{JSON.stringify(res)}").toBe input.name

    for row in [
      { nom: 'Alpha', date_debut: '2026-01-01T00:00:00Z' }
      { nom: 'Beta', date_debut: '2026-02-02T00:00:00Z' }
    ]
      res = await gql page,
        'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }',
        { sid: spaceId, data: row }
      expect(res?.data?.insertRecord?.id, "insertRecord: #{JSON.stringify(res)}").toBeTruthy()

    # 2. Deux définitions : accès full (écrit) et read (mutation refusée).
    fullScriptCode = fullScript
    res = await gql page,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: fullName, description: 'calendrier (manifest)', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: fullScriptCode, templateCode: '<div>init</div>',
                 manifest: fullManifest } }
    expect(res?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin (full): #{JSON.stringify(res)}").toBe fullName
    fullId = res.data.createWidgetPlugin.id

    readScript = """
    module.exports = function (api) {
      api.onRecords(function (rows) {
        if (!rows.length) return;
        api.gql('mutation { updateRecord(spaceId: "#{spaceId}", id: "' + rows[0].id + '", data: "{\\"nom\\":\\"HACK\\"}") { id } }')
          .then(function () { api.render('<div id="res">ALLOWED</div>'); })
          .catch(function (e) { api.render('<div id="res">DENIED ' + e.message + '</div>'); });
      });
    };
    """
    res = await gql page,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: readName, description: 'lecteur (read)', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: readScript, templateCode: '<div id="res">init</div>',
                 manifest: readManifest } }
    expect(res?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin (read): #{JSON.stringify(res)}").toBe readName
    readId = res.data.createWidgetPlugin.id

    # 3. Page avec mappage de colonnes (la fenêtre écrit la même chose).
    yaml = "layout:\n  direction: vertical\n  children:\n" +
      "    - widget:\n        id: cal\n        title: Calendrier\n" +
      "        space: #{spaceName}\n        type: '#{fullName}'\n" +
      "        columns:\n          titre: nom\n          debut: date_debut\n" +
      "        params:\n          couleur: '#c33'\n" +
      "    - widget:\n        id: reader\n        title: Lecteur\n" +
      "        space: #{spaceName}\n        type: '#{readName}'\n" +
      "        columns:\n          titre: nom\n"
    res = await gql page,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name yaml } }',
      { input: { name: pageName, yaml: yaml } }
    expect(res?.data?.createCustomView?.id,
      "createCustomView: #{JSON.stringify(res)}").toBeTruthy()
    pageId = res.data.createCustomView.id
    expect(res.data.createCustomView.yaml, 'mapping écrit').toContain 'titre: nom'

    # 4. Ouvrir la page.
    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    leaf = page.locator('#page-list .leaf-item', { hasText: pageName }).first()
    await expect(leaf).toBeVisible()
    await leaf.click()
    await expect(page.locator('#custom-view-container')).toBeVisible()

    # 5. Le widget full reçoit les lignes renommées (titre/debut) et l'option,
    #    puis son updateRecord modifie la donnée et recharge les lignes.
    frame = page.frameLocator '[data-widget-id="cal"] iframe'
    await expect(frame.locator('#param')).toHaveText '#c33', { timeout: 15000 }
    # L'écriture peut précéder la première assertion : la ligne mise à jour
    # (renommée `titre`) doit être là, avec la seconde ligne intacte.
    await expect(frame.locator('#status')).toHaveText 'UPDATED', { timeout: 15000 }
    await expect(frame.locator('#rows')).toContainText 'MODIFIÉ', { timeout: 15000 }
    await expect(frame.locator('#rows')).toContainText 'Beta'

    records = await gql page,
      'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }',
      { sid: spaceId, limit: 10 }
    items = records?.data?.records?.items or []
    names = for i in items
      if typeof i.data == 'string' then JSON.parse(i.data).nom else i.data.nom
    expect(names, "données en base: #{JSON.stringify(names)}").toContain 'MODIFIÉ'
    expect(names).toContain 'Beta'

    # 6. Le widget read voit les lignes mais sa mutation est refusée côté parent.
    readFrame = page.frameLocator '[data-widget-id="reader"] iframe'
    await expect(readFrame.locator('#res')).toContainText 'DENIED', { timeout: 15000 }
    await expect(readFrame.locator('#res')).toContainText 'lectures'

    # ... et la base n'a pas reçu « HACK ».
    records = await gql page,
      'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }',
      { sid: spaceId, limit: 10 }
    items = records?.data?.records?.items or []
    names = for i in items
      if typeof i.data == 'string' then JSON.parse(i.data).nom else i.data.nom
    expect(names, "aucune écriture HACK: #{JSON.stringify(names)}").not.toContain 'HACK'
