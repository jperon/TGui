# tests/playwright/pages/widget-manifest.spec.coffee
# Widget personnalisé avec manifest (spec 2026-11-16-custom-widgets-design.md
# §3, §3 bis, §6) :
#   - le widget est ajouté par la fenêtre « ＋ Widget » : sélecteurs de champ
#     par colonne déclarée, option pré-remplie, mappage écrit dans le YAML ;
#   - l'iframe reçoit les lignes renommées et son updateRecord modifie la donnée ;
#   - un plugin access: read voit les lignes mais sa mutation est refusée.
# Le test crée son espace, ses plugins et ses pages, et les supprime à la fin.

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
  windowPageName = generateUniqueName 'WidgetManifest'
  readPageName = generateUniqueName 'WidgetManifestRead'
  spaceId = null
  fullId = null
  readId = null
  windowPageId = null
  readPageId = null

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
  };
  """

  test.beforeAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p

    # Source : deux colonnes (nom, date_debut) et deux lignes.
    created = await gql p,
      'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }',
      { input: { name: spaceName, description: 'Widget manifest e2e' } }
    expect(created?.data?.createSpace?.id,
      "createSpace a échoué: #{JSON.stringify(created)}").toBeTruthy()
    spaceId = created.data.createSpace.id

    for input in [
      { name: 'nom', fieldType: 'String', notNull: true, description: '' }
      { name: 'date_debut', fieldType: 'Datetime', notNull: false, description: '' }
    ]
      res = await gql p,
        'mutation($sid: ID!, $input: FieldInput!) { addField(spaceId: $sid, input: $input) { id name } }',
        { sid: spaceId, input }
      expect(res?.data?.addField?.name, "addField: #{JSON.stringify(res)}").toBe input.name

    for row in [
      { nom: 'Alpha', date_debut: '2026-01-01T00:00:00Z' }
      { nom: 'Beta', date_debut: '2026-02-02T00:00:00Z' }
    ]
      res = await gql p,
        'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }',
        { sid: spaceId, data: row }
      expect(res?.data?.insertRecord?.id, "insertRecord: #{JSON.stringify(res)}").toBeTruthy()

    # Deux définitions : accès full (écrit) et read (mutation refusée).
    res = await gql p,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: fullName, description: 'calendrier (manifest)', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: fullScript, templateCode: '<div>init</div>',
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
    res = await gql p,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: readName, description: 'lecteur (read)', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: readScript, templateCode: '<div id="res">init</div>',
                 manifest: readManifest } }
    expect(res?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin (read): #{JSON.stringify(res)}").toBe readName
    readId = res.data.createWidgetPlugin.id

    # Page vide pour l'ajout par la fenêtre, et page du widget en lecture.
    res = await gql p,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }',
      { input: { name: windowPageName, yaml: "layout:\n  direction: vertical\n  children: []" } }
    expect(res?.data?.createCustomView?.id,
      "createCustomView (fenêtre): #{JSON.stringify(res)}").toBeTruthy()
    windowPageId = res.data.createCustomView.id

    readYaml = "layout:\n  direction: vertical\n  children:\n" +
      "    - widget:\n        id: reader\n        title: Lecteur\n" +
      "        space: #{spaceName}\n        type: '#{readName}'\n" +
      "        columns:\n          titre: nom\n"
    res = await gql p,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }',
      { input: { name: readPageName, yaml: readYaml } }
    expect(res?.data?.createCustomView?.id,
      "createCustomView (lecture): #{JSON.stringify(res)}").toBeTruthy()
    readPageId = res.data.createCustomView.id

    await ctx.close()

  test.afterAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    if windowPageId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: windowPageId }
    if readPageId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: readPageId }
    if fullId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: fullId }
    if readId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: readId }
    if spaceId
      await gql p, 'mutation($id: ID!) { deleteSpace(id: $id) }', { id: spaceId }
    await ctx.close()

  test 'ajouté par la fenêtre : mappage, lignes renommées, updateRecord', ({ page }) ->
    await performLogin page

    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    leaf = page.locator('#page-list .leaf-item', { hasText: windowPageName }).first()
    await expect(leaf).toBeVisible()
    await leaf.click()
    await expect(page.locator('#custom-view-container')).toBeVisible()

    # 1. Fenêtre « ＋ Widget » : choisir le widget personnalisé.
    await page.click '#yaml-add-widget-btn'
    modal = page.locator '#add-widget-modal'
    await expect(modal).toBeVisible()

    pluginOption = page.locator('#widget-type-plugin-list .widget-type-option',
      { hasText: fullName }).first()
    await expect(pluginOption).toBeVisible()
    await pluginOption.locator('label').click()
    await expect(pluginOption.locator('input[type="radio"]')).toBeChecked()

    await page.fill '#widget-title-input', 'Calendrier'
    await page.selectOption '#widget-space-select', { label: spaceName }

    # 2. Le formulaire du manifest remplace les paires clé/valeur.
    await expect(page.locator '#widget-params-pairs').toBeHidden()
    titreSelect = page.locator '#widget-manifest-form .manifest-column-select[data-declared="titre"]'
    debutSelect = page.locator '#widget-manifest-form .manifest-column-select[data-declared="debut"]'
    await expect(titreSelect).toBeVisible()
    await expect(debutSelect).toBeVisible()
    # Les champs de la source sont proposés, filtrés par type (Datetime seulement).
    await expect(titreSelect.locator('option[value="nom"]')).toHaveCount 1
    await expect(debutSelect.locator('option[value="date_debut"]')).toHaveCount 1
    await expect(debutSelect.locator('option[value="nom"]')).toHaveCount 0

    await titreSelect.selectOption 'nom'
    await debutSelect.selectOption 'date_debut'
    # Option color : la valeur par défaut du manifest est pré-remplie (le
    # navigateur normalise '#36c' en '#3366cc').
    await expect(page.locator '#widget-manifest-form input[data-option="couleur"]').toHaveValue '#3366cc'

    await page.click '#add-widget-confirm-btn'
    await expect(modal).toBeHidden()

    # 3. Le YAML de page porte le mappage et l'option, l'iframe les lignes renommées.
    saved = await gql page, 'query($id: ID!) { customView(id: $id) { yaml } }', { id: windowPageId }
    savedYaml = saved?.data?.customView?.yaml or ''
    expect(savedYaml, "YAML enregistré: #{savedYaml}").toContain 'columns:'
    expect(savedYaml, "YAML enregistré: #{savedYaml}").toContain 'titre: nom'
    expect(savedYaml, "YAML enregistré: #{savedYaml}").toContain 'debut: date_debut'
    expect(savedYaml, "YAML enregistré: #{savedYaml}").toContain "type: '#{fullName}'"

    widget = page.locator ".cv-widget[data-widget-type=\"#{fullName}\"]"
    await expect(widget).toBeVisible()
    frame = widget.locator('iframe').contentFrame()
    await expect(frame.locator('#param')).toHaveText '#3366cc', { timeout: 15000 }
    await expect(frame.locator('#status')).toHaveText 'UPDATED', { timeout: 15000 }
    await expect(frame.locator('#rows')).toContainText 'MODIFIÉ', { timeout: 15000 }
    await expect(frame.locator('#rows')).toContainText 'Beta'

    # 4. L'écriture est bien en base ; la seconde ligne est intacte.
    records = await gql page,
      'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }',
      { sid: spaceId, limit: 10 }
    items = records?.data?.records?.items or []
    names = for i in items
      if typeof i.data == 'string' then JSON.parse(i.data).nom else i.data.nom
    expect(names, "données en base: #{JSON.stringify(names)}").toContain 'MODIFIÉ'
    expect(names).toContain 'Beta'

  test 'access: read — mutation refusée, données inchangées', ({ page }) ->
    await performLogin page
    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    leaf = page.locator('#page-list .leaf-item', { hasText: readPageName }).first()
    await expect(leaf).toBeVisible()
    await leaf.click()
    await expect(page.locator('#custom-view-container')).toBeVisible()

    frame = page.frameLocator '[data-widget-id="reader"] iframe'
    await expect(frame.locator('#res')).toContainText 'DENIED', { timeout: 15000 }
    await expect(frame.locator('#res')).toContainText 'lectures'

    records = await gql page,
      'query($sid: ID!, $limit: Int) { records(spaceId: $sid, limit: $limit) { items { id data } } }',
      { sid: spaceId, limit: 10 }
    items = records?.data?.records?.items or []
    names = for i in items
      if typeof i.data == 'string' then JSON.parse(i.data).nom else i.data.nom
    expect(names, "aucune écriture HACK: #{JSON.stringify(names)}").not.toContain 'HACK'
