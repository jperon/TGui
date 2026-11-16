# tests/playwright/pages/widget-lua.spec.coffee
# Widgets personnalisés en Lua / MoonScript (spec
# docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7) :
#   - un widget MoonScript s'exécute via wasmoon dans son iframe, reçoit les
#     lignes de la source par onRecords et les affiche ;
#   - un widget Lua appelle gql (promesse attendue par :await()) ;
#   - une page sans widget Lua ne charge jamais wasmoon (ni le .js, ni le .wasm).
# Le test crée son espace, ses plugins et ses pages, et les supprime à la fin.

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

WASMOON_JS = '/vendor/wasmoon.bundle.js'
WASMOON_WASM = '/vendor/wasmoon.bundle.wasm'

gql = (page, query, variables) ->
  page.evaluate ({ query, variables }) ->
    token = localStorage.getItem 'tdb_token'
    fetch('/graphql', {
      method: 'POST'
      headers: { 'Content-Type': 'application/json', 'Authorization': "Bearer #{token}" }
      body: JSON.stringify({ query: query, variables: variables })
    }).then (r) -> r.json()
  , { query: query, variables: variables }

# Compte les requêtes réseau vers wasmoon (JS et binaire).
watchWasmoon = (page) ->
  hits = []
  page.on 'request', (req) ->
    url = req.url()
    hits.push url if url.includes(WASMOON_JS) or url.includes(WASMOON_WASM)
  hits

openPage = (page, name) ->
  await page.goto '/'
  await page.waitForSelector '#main', { state: 'visible' }
  leaf = page.locator('#page-list .leaf-item', { hasText: name }).first()
  await expect(leaf).toBeVisible()
  await leaf.click()
  await expect(page.locator('#custom-view-container')).toBeVisible()

createPage = (page, name, yaml) ->
  res = await gql page,
    'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id } }',
    { input: { name: name, yaml: yaml } }
  expect(res?.data?.createCustomView?.id,
    "createCustomView #{name}: #{JSON.stringify(res)}").toBeTruthy()
  res.data.createCustomView.id

test.describe.serial 'Widgets Lua / MoonScript (wasmoon)', ->
  stamp = Date.now()
  spaceName = "wlua_space_#{stamp}"
  moonPluginName = "wlua_moon_#{stamp}"
  luaPluginName = "wlua_lua_#{stamp}"
  plainPageName = generateUniqueName 'LuaPlain'
  moonPageName = generateUniqueName 'LuaMoon'
  luaPageName = generateUniqueName 'LuaGql'
  spaceId = null
  moonPluginId = null
  luaPluginId = null
  pageIds = []

  moonScript = """
  widget.render "<div id='moon-loading'>chargement…</div>"
  widget.onRecords (rows) ->
    items = for row in *rows
      "<li class='moon-row'>" .. tostring(row.nom) .. "</li>"
    widget.render "<ul id='moon-list'>" .. table.concat(items) .. "</ul>"
  """

  luaScript = """
  local data = widget.gql('query { spaces { id name } }'):await()
  widget.render('<div id="lua-gql">' .. tostring(#data.spaces) .. ' espaces</div>')
  """

  htmlTemplate = """<div class="plugin-root"></div>"""

  test.beforeAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p

    created = await gql p,
      'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }',
      { input: { name: spaceName, description: 'Widgets Lua e2e' } }
    expect(created?.data?.createSpace?.id,
      "createSpace a échoué: #{JSON.stringify(created)}").toBeTruthy()
    spaceId = created.data.createSpace.id

    res = await gql p,
      'mutation($sid: ID!, $input: FieldInput!) { addField(spaceId: $sid, input: $input) { id name } }',
      { sid: spaceId, input: { name: 'nom', fieldType: 'String', notNull: false, description: '' } }
    expect(res?.data?.addField?.name, "addField: #{JSON.stringify(res)}").toBe 'nom'

    for nom in ['Alpha', 'Beta']
      res = await gql p,
        'mutation($sid: ID!, $data: JSON!) { insertRecord(spaceId: $sid, data: $data) { id } }',
        { sid: spaceId, data: { nom: nom } }
      expect(res?.data?.insertRecord?.id, "insertRecord #{nom}: #{JSON.stringify(res)}").toBeTruthy()

    res = await gql p,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name compiled } }',
      { input: { name: moonPluginName, description: 'widget MoonScript (e2e)',
                 scriptLanguage: 'moonscript', templateLanguage: 'html',
                 scriptCode: moonScript, templateCode: htmlTemplate } }
    expect(res?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin moonscript: #{JSON.stringify(res)}").toBe moonPluginName
    expect(res.data.createWidgetPlugin.compiled,
      'compiled doit contenir le Lua compilé').toContain('widget.render')
    moonPluginId = res.data.createWidgetPlugin.id

    res = await gql p,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: luaPluginName, description: 'widget Lua (e2e)',
                 scriptLanguage: 'lua', templateLanguage: 'html',
                 scriptCode: luaScript, templateCode: htmlTemplate } }
    expect(res?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin lua: #{JSON.stringify(res)}").toBe luaPluginName
    luaPluginId = res.data.createWidgetPlugin.id

    plainYaml = """
    layout:
      direction: vertical
      children:
        - widget:
            id: w1
            title: 'Données'
            space: '#{spaceName}'
    """
    pageIds.push await createPage p, plainPageName, plainYaml

    moonYaml = """
    layout:
      direction: vertical
      children:
        - widget:
            id: w1
            title: 'MoonScript'
            type: '#{moonPluginName}'
            space: '#{spaceName}'
    """
    pageIds.push await createPage p, moonPageName, moonYaml

    luaYaml = """
    layout:
      direction: vertical
      children:
        - widget:
            id: w1
            title: 'Lua gql'
            type: '#{luaPluginName}'
    """
    pageIds.push await createPage p, luaPageName, luaYaml
    await ctx.close()

  test.afterAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    for id in pageIds
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: id }
    if moonPluginId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: moonPluginId }
    if luaPluginId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: luaPluginId }
    if spaceId
      await gql p, 'mutation($id: ID!) { deleteSpace(id: $id) }', { id: spaceId }
    await ctx.close()

  test 'une page sans widget Lua ne charge pas wasmoon', ({ page }) ->
    hits = watchWasmoon page
    await performLogin page
    await openPage page, plainPageName

    await expect(page.locator('.cv-widget').first()).toBeVisible()
    await expect(page.locator('.cv-widget iframe')).toHaveCount 0
    expect(hits, "requêtes wasmoon inattendues : #{hits.join ', '}").toHaveLength 0

  test 'un widget MoonScript rend les lignes de onRecords', ({ page }) ->
    hits = watchWasmoon page
    await performLogin page
    await openPage page, moonPageName

    frame = page.locator('.cv-widget iframe').first()
    await expect(frame).toHaveCount 1
    list = frame.contentFrame().locator('#moon-list')
    await expect(list).toBeVisible { timeout: 20000 }
    await expect(list.locator('.moon-row')).toHaveCount 2
    await expect(list).toContainText 'Alpha'
    await expect(list).toContainText 'Beta'

    # wasmoon (glue JS + binaire) n'a été demandé que pour ce widget.
    expect(hits.some((u) -> u.includes(WASMOON_JS)),
      "wasmoon.bundle.js attendu, vu : #{hits.join ', '}").toBe true
    expect(hits.some((u) -> u.includes(WASMOON_WASM)),
      "wasmoon.bundle.wasm attendu, vu : #{hits.join ', '}").toBe true

  test 'un widget Lua lit les données par gql', ({ page }) ->
    await performLogin page
    await openPage page, luaPageName

    frame = page.locator('.cv-widget iframe').first()
    await expect(frame).toHaveCount 1
    out = frame.contentFrame().locator('#lua-gql')
    await expect(out).toBeVisible { timeout: 20000 }
    await expect(out).toContainText 'espaces'
    # Au moins l'espace de ce test est visible pour l'admin.
    await expect(out).toHaveText /[1-9][0-9]* espaces/
