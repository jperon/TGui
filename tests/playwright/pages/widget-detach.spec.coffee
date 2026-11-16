# tests/playwright/pages/widget-detach.spec.coffee
# « Détacher » une instance de widget personnalisé depuis l'interface (spec
# docs/superpowers/specs/2026-11-16-custom-widgets-design.md §4) :
#   - le bouton apparaît sur chaque instance, en édition de page, pour un admin ;
#   - le clic demande un nom (pré-rempli), détache l'instance choisie et la page
#     continue d'afficher son widget ;
#   - la copie prend le nom demandé, l'autre instance et l'autre page gardent la
#     définition d'origine ; modifier la copie ne change que l'instance détachée.
# Le test crée son plugin et ses pages, et les supprime à la fin.

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

typeCount = (text, name) ->
  escaped = name.replace /[.*+?^${}()|[\]\\]/g, '\\$&'
  matches = text.match new RegExp "type:\\s*'?#{escaped}'?", 'g'
  (matches or []).length

test.describe.serial 'Widget personnalisé — détacher une instance', ->
  stamp = Date.now()
  pluginName = "wdetach_src_#{stamp}"
  copyName = "wdetach_copy_#{stamp}"
  pageOneName = generateUniqueName 'WidgetDetach'
  pageTwoName = generateUniqueName 'WidgetDetachOther'
  pageOneId = null
  pageTwoId = null
  pluginId = null
  copyId = null

  originalScript = "module.exports = function (api) { " +
    "api.render('<div id=\"mark\">' + (api.params && api.params.label ? api.params.label : 'ORIGINAL') + '</div>'); };"
  copyScript = "module.exports = function (api) { " +
    "api.render('<div id=\"mark\">COPY:' + (api.params && api.params.label ? api.params.label : '') + '</div>'); };"

  yamlWith = (ids) ->
    children = for id, i in ids
      "    - widget:\n" +
      "        id: #{id}\n" +
      "        title: Widget #{i + 1}\n" +
      "        type: '#{pluginName}'\n" +
      "        params:\n" +
      "          label: '#{if i == 0 then 'Alpha' else 'Beta'}'\n"
    "layout:\n  direction: vertical\n  children:\n" + children.join('')

  test.beforeAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p

    res = await gql p,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: pluginName, description: 'détacher (source)', scriptLanguage: 'javascript',
                 templateLanguage: 'html', scriptCode: originalScript, templateCode: '<div>init</div>' } }
    expect(res?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin a échoué: #{JSON.stringify(res)}").toBe pluginName
    pluginId = res.data.createWidgetPlugin.id

    # Page 1 : DEUX instances du même plugin (celle de gauche reste l'originale).
    res = await gql p,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }',
      { input: { name: pageOneName, yaml: yamlWith(['w_detach_a', 'w_detach_b']) } }
    expect(res?.data?.createCustomView?.id,
      "createCustomView (page 1): #{JSON.stringify(res)}").toBeTruthy()
    pageOneId = res.data.createCustomView.id

    # Page 2 : une autre page qui utilise la même définition.
    res = await gql p,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }',
      { input: { name: pageTwoName, yaml: yamlWith(['w_detach_c']) } }
    expect(res?.data?.createCustomView?.id,
      "createCustomView (page 2): #{JSON.stringify(res)}").toBeTruthy()
    pageTwoId = res.data.createCustomView.id

    await ctx.close()

  test.afterAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    if pageOneId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: pageOneId }
    if pageTwoId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: pageTwoId }
    for id in [copyId, pluginId] when id
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: id }
    await ctx.close()

  openPage = (page, name) ->
    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    leaf = page.locator('#page-list .leaf-item', { hasText: name }).first()
    await expect(leaf).toBeVisible()
    await leaf.click()
    await expect(page.locator('#custom-view-container')).toBeVisible()

  test 'détache la seconde instance depuis l’interface, sans toucher l’autre', ({ page }) ->
    await performLogin page
    await openPage page, pageOneName

    # Deux instances du plugin, chacune avec son bouton « Détacher ».
    widgetA = page.locator '.cv-widget[data-widget-id="w_detach_a"]'
    widgetB = page.locator '.cv-widget[data-widget-id="w_detach_b"]'
    await expect(widgetA).toBeVisible()
    await expect(widgetB).toBeVisible()
    await expect(page.locator '.cv-widget-detach-btn').toHaveCount 2
    await expect(widgetA.locator('.cv-widget-detach-btn')).toBeVisible()

    # Les deux widgets affichent leur contenu avant le détachement.
    frameA = widgetA.locator('iframe').contentFrame()
    frameB = widgetB.locator('iframe').contentFrame()
    await expect(frameA.locator('#mark')).toHaveText 'Alpha', { timeout: 15000 }
    await expect(frameB.locator('#mark')).toHaveText 'Beta', { timeout: 15000 }

    # Action « Détacher » sur la seconde instance : nom pré-rempli puis modifié.
    await widgetB.locator('.cv-widget-detach-btn').click()
    modal = page.locator '#tdb-modal-overlay'
    await expect(modal).toBeVisible()
    nameInput = modal.locator '.tdb-modal-input'
    await expect(nameInput).toHaveValue new RegExp(pluginName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    await expect(nameInput).toHaveValue new RegExp(pageOneName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    await nameInput.fill copyName
    await modal.locator('.tdb-modal-actions .btn-primary').click()

    # L'éditeur de définitions s'ouvre sur la copie.
    pluginModal = page.locator '#widget-plugin-modal'
    await expect(pluginModal).toBeVisible()
    await expect(page.locator '#widget-plugin-name').toHaveValue copyName
    await page.click '#widget-plugin-modal-close-btn'
    await expect(pluginModal).toBeHidden()

    # La page affiche toujours ses deux widgets.
    await expect(page.locator '.cv-widget[data-widget-type]').toHaveCount 2
    await expect(page.locator '.cv-widget[data-widget-id="w_detach_a"] iframe').toBeVisible()
    await expect(page.locator '.cv-widget[data-widget-id="w_detach_b"] iframe').toBeVisible()

    # Une seule instance réécrite (params conservés), l'autre page est intacte.
    saved = await gql page, 'query($id: ID!) { customView(id: $id) { yaml } }', { id: pageOneId }
    yamlText = saved?.data?.customView?.yaml or ''
    expect(typeCount(yamlText, pluginName), "une seule instance sur l'original: #{yamlText}").toBe 1
    expect(typeCount(yamlText, copyName), "une seule instance détachée: #{yamlText}").toBe 1
    expect(yamlText, 'params de l’instance détachée conservés').toContain "label: 'Beta'"

    other = await gql page, 'query($id: ID!) { customView(id: $id) { yaml } }', { id: pageTwoId }
    otherYaml = other?.data?.customView?.yaml or ''
    expect(typeCount(otherYaml, pluginName), "l'autre page garde l'original: #{otherYaml}").toBe 1
    expect(typeCount(otherYaml, copyName)).toBe 0

    # La copie est une définition distincte, dans la portée de la page (ici la
    # bibliothèque : la page n'appartient à aucune app).
    plugins = await gql page,
      'query($pageId: ID!) { widgetPlugins(pageId: $pageId) { id name appId scriptCode } }',
      { pageId: pageOneId }
    definitions = plugins?.data?.widgetPlugins or []
    copy = definitions.find (def) -> def.name == copyName
    expect(copy, "la copie doit exister: #{JSON.stringify(definitions)}").toBeTruthy()
    copyId = copy.id
    expect(copy.appId).toBeNull()
    original = definitions.find (def) -> def.name == pluginName
    expect(original.scriptCode).toBe originalScript

    # Modifier la copie ne change que l'instance détachée.
    res = await gql page,
      'mutation($id: ID!, $input: UpdateWidgetPluginInput!) { updateWidgetPlugin(id: $id, input: $input) { id } }',
      { id: copyId, input: { scriptCode: copyScript } }
    expect(res?.errors, "updateWidgetPlugin: #{JSON.stringify(res)}").toBeFalsy()

    await openPage page, pageOneName
    frameA = page.locator('.cv-widget[data-widget-id="w_detach_a"] iframe').contentFrame()
    frameB = page.locator('.cv-widget[data-widget-id="w_detach_b"] iframe').contentFrame()
    await expect(frameA.locator('#mark')).toHaveText 'Alpha', { timeout: 15000 }
    await expect(frameB.locator('#mark')).toHaveText 'COPY:Beta', { timeout: 15000 }

    # L'autre page n'est pas affectée non plus.
    await openPage page, pageTwoName
    frameC = page.locator('.cv-widget[data-widget-id="w_detach_c"] iframe').contentFrame()
    await expect(frameC.locator('#mark')).toHaveText 'Alpha', { timeout: 15000 }
