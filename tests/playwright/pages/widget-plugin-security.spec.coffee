# tests/playwright/pages/widget-plugin-security.spec.coffee
# Sécurité des requêtes relayées depuis une iframe de widget :
#   - un widget qui tente `createUser` reçoit une erreur GraphQL
#     (« not allowed from a widget ») et aucun utilisateur n'est créé ;
#   - un widget qui lit des données fonctionne encore.
# Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §6.
# Le test crée ses plugins et sa page, et les supprime à la fin.

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

test.describe.serial 'Widget plugin — requêtes relayées', ->
  stamp = Date.now()
  evilName = "wsec_evil_#{stamp}"
  readName = "wsec_read_#{stamp}"
  pageName = generateUniqueName 'WidgetSecu'
  evilUser = "wsec_evil_user_#{stamp}"
  pageId = null

  evilScript = """
  module.exports = function (api) {
    api.gql('mutation { createUser(input: {username: "wsec_evil_user_#{stamp}", email: "wsec@test.local", password: "pass1234"}) { id } }')
      .then(function () { api.render('<div id="res">ALLOWED</div>'); })
      .catch(function (e) { api.render('<div id="res">DENIED ' + e.message + '</div>'); });
  };
  """

  readScript = """
  module.exports = function (api) {
    api.gql('{ spaces { id name } }')
      .then(function (d) { api.render('<div id="res">SPACES ' + ((d.spaces || []).length) + '</div>'); })
      .catch(function (e) { api.render('<div id="res">ERR ' + e.message + '</div>'); });
  };
  """

  test.afterAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    if pageId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: pageId }
    plugins = await gql p, '{ widgetPlugins { id name } }'
    for plugin in (plugins?.data?.widgetPlugins or [])
      if plugin.name is evilName or plugin.name is readName
        await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: plugin.id }
    await ctx.close()

  test 'createUser refusé dans l’iframe, lecture toujours possible', ({ page }) ->
    await performLogin page

    created = await gql page,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: evilName, description: 'security test', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: evilScript,
                 templateCode: '<div id="res">init</div>' } }
    expect(created?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin a échoué: #{JSON.stringify(created)}").toBe evilName

    reader = await gql page,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: readName, description: 'security test (read)', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: readScript,
                 templateCode: '<div id="res">init</div>' } }
    expect(reader?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin (lecture) a échoué: #{JSON.stringify(reader)}").toBe readName

    # Vraies fins de ligne : la valeur passe par les variables (JSON), pas par
    # un littéral GraphQL où il faudrait un échappement supplémentaire.
    yaml = "layout:\n  direction: vertical\n  children:\n" +
      "    - widget:\n        id: evil\n        title: Evil\n        type: #{evilName}\n" +
      "    - widget:\n        id: reader\n        title: Reader\n        type: #{readName}"
    pageRes = await gql page,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }',
      { input: { name: pageName, yaml: yaml } }
    expect(pageRes?.data?.createCustomView?.id,
      "createCustomView a échoué: #{JSON.stringify(pageRes)}").toBeTruthy()
    pageId = pageRes.data.createCustomView.id

    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    leaf = page.locator('#page-list .leaf-item', { hasText: pageName }).first()
    await expect(leaf).toBeVisible()
    await leaf.click()

    # Le widget fautif reçoit une erreur explicite dans son iframe.
    evilFrame = page.frameLocator '[data-widget-id="evil"] iframe'
    await expect(evilFrame.locator('#res')).toContainText 'DENIED', { timeout: 15000 }
    await expect(evilFrame.locator('#res')).toContainText 'not allowed from a widget'

    # Le widget de lecture fonctionne encore (lecture autorisée).
    readFrame = page.frameLocator '[data-widget-id="reader"] iframe'
    await expect(readFrame.locator('#res')).toContainText 'SPACES', { timeout: 15000 }
    await expect(readFrame.locator('#res')).not.toContainText 'ERR'

    # Aucun utilisateur n'a été créé côté serveur.
    users = await gql page, '{ users { username } }'
    names = (u.username for u in (users?.data?.users or []))
    expect(names).not.toContain evilUser
