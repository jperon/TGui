# Applications E2E tests — Administration > Applications panel.
#
# Stateful serial scenario: navigate, export (validations), install, update with
# local conflicts, purge obsolete items, and XSS display safety. Every run uses a
# unique app id and its own spaces (created through GraphQL, deleted afterwards),
# because the test DB keeps the app tracking tables (_tdb_apps/_tdb_app_items)
# across the Playwright baseline reset and there is no uninstall API.

fs = require 'fs'
{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

BASE = 'http://localhost:8081'

# ── GraphQL helpers (Node fetch) ────────────────────────────────────────────

gql = (query, variables, token) ->
  headers = { 'Content-Type': 'application/json' }
  headers.Authorization = "Bearer #{token}" if token
  res = await fetch "#{BASE}/graphql", {
    method: 'POST'
    headers: headers
    body: JSON.stringify { query, variables }
  }
  json = await res.json()
  throw new Error "GraphQL error: #{JSON.stringify json.errors}" if json.errors?.length
  json.data

adminToken = ->
  data = await gql 'mutation { login(username:"admin", password:"adminadmin") { token } }'
  data.login.token

readSpaces = (token) ->
  data = await gql '{ spaces { id name description fields { id name description } } }', {}, token
  data.spaces

recordTotal = (token, spaceId) ->
  data = await gql 'query($id: ID!){ space(id:$id){ records(limit:1){ total } } }', { id: spaceId }, token
  data.space.records.total

# ── UI helpers ──────────────────────────────────────────────────────────────

openAppsPanel = (page) ->
  await expect(page.locator('#admin-toggle-btn')).toBeVisible()
  await page.click '#admin-toggle-btn'
  await page.click '#admin-nav-apps'
  await expect(page.locator('#admin-apps-section')).toBeVisible()

confirmModal = (page) ->
  primary = page.locator '.tdb-modal-overlay:not(.hidden) .btn-primary'
  await expect(primary).toBeVisible()
  await primary.click()

uploadPackage = (page, content, filename) ->
  await page.setInputFiles '#apps-package-input', {
    name: filename
    mimeType: 'text/yaml'
    buffer: Buffer.from content
  }

# ── State shared by the serial tests ────────────────────────────────────────

XSS = '<img src=x onerror="window.__xss=1">'

exportedYaml = null
spaceName = null
spaceId = null
fieldIds = {}
appId = null
appName = null
pluginName = null
localConflitDesc = 'Conflit (modifié LOCALEMENT)'
localSpaceDesc = 'Espace (modifié LOCALEMENT)'
deliveredConflitDesc = 'Conflit (livré v1.1)'
deliveredAuteurDesc = 'Auteur (livré v1.1)'

test.describe.serial('Applications — Administration panel', ->

  test.beforeAll(->
    token = await adminToken()
    stamp = Date.now()
    spaceName = generateUniqueName 'E2EApps'
    appId = "org.test.e2e.#{stamp}"
    appName = "E2E App #{stamp}"
    pluginName = "e2e_plugin_#{stamp}"

    # The shared test DB keeps stray schema objects left by manual/exploratory
    # runs (the Playwright baseline reset only removes non-demo spaces). A field
    # name containing a dot breaks the package key round-trip
    # (`field:<space>.<name>` splits on the last dot), so an exported package
    # would carry an item that cannot be applied. Remove such corrupt
    # leftovers before exporting; this is not part of the tested scenario.
    existing = await readSpaces token
    for s in existing
      for f in s.fields when f.name.includes('.')
        await gql 'mutation($id: ID!){ removeField(fieldId:$id) }', { id: f.id }, token

    created = await gql 'mutation($input: CreateSpaceInput!){ createSpace(input:$input){ id name } }',
      { input: { name: spaceName, description: 'Espace e2e initial' } }, token
    spaceId = created.createSpace.id

    addField = (input) ->
      d = await gql 'mutation($sid: ID!, $input: FieldInput!){ addField(spaceId:$sid, input:$input){ id name } }',
        { sid: spaceId, input: input }, token
      d.addField

    # createSpace already creates the auto-increment `id` field.
    fieldIds.nom = (await addField { name: 'nom', fieldType: 'String', notNull: true, description: 'Nom' }).id
    fieldIds.conflit = (await addField { name: 'conflit', fieldType: 'String', notNull: false, description: 'Conflit initial' }).id
    fieldIds.auteur = (await addField { name: 'auteur', fieldType: 'String', notNull: false, description: 'Auteur initial' }).id
    fieldIds.supprime = (await addField { name: 'supprime', fieldType: 'String', notNull: false, description: 'Sera retirée' }).id

    rows = [
      { nom: 'Alpha', conflit: 'c1', supprime: 's1' }
      { nom: 'Beta', conflit: 'c2', supprime: 's2' }
      { nom: 'Gamma', conflit: 'c3', supprime: 's3' }
    ]
    for row in rows
      await gql 'mutation($sid: ID!, $data: JSON!){ insertRecord(spaceId:$sid, data:$data){ id } }',
        { sid: spaceId, data: row }, token
  )

  test.afterAll(->
    token = await adminToken()
    plugins = await gql '{ widgetPlugins { id name } }', {}, token
    for p in (plugins.widgetPlugins or []) when p.name == pluginName
      await gql 'mutation($id: ID!){ deleteWidgetPlugin(id:$id) }', { id: p.id }, token
    spaces = await readSpaces token
    for s in spaces when s.name == spaceName
      await gql 'mutation($id: ID!){ deleteSpace(id:$id) }', { id: s.id }, token
  )

  test('1. navigation and panel layout', ({ page }) ->
    await performLogin page
    await openAppsPanel page

    await expect(page.locator('.apps-installed-box')).toBeVisible()
    await expect(page.locator('.apps-install-box')).toBeVisible()
    await expect(page.locator('.apps-export-box')).toBeVisible()

    await expect(page.locator('#apps-apply-btn')).toBeDisabled()
    await expect(page.locator('#snapshot-mode-replace')).toHaveCount(0)
  )

  test('2. export validations and valid download', ({ page }) ->
    test.setTimeout 60000
    await performLogin page
    await openAppsPanel page

    # 2a — non-semver version: inline error, no download.
    await page.fill '#apps-export-id', appId
    await page.fill '#apps-export-name', appName
    await page.fill '#apps-export-version', '1.0'
    await page.fill '#apps-export-description', 'Application e2e'
    await page.click '#apps-export-btn'
    await expect(page.locator('#apps-export-error')).toBeVisible()
    await expect(page.locator('#apps-export-error')).toContainText(/invalide|invalid/i)
    noDownload = await page.waitForEvent('download', { timeout: 1500 }).catch(-> null)
    expect(noDownload).toBeNull()

    # 2b — seed on an unknown space: clear error naming that space, no download.
    unknownSpace = "#{generateUniqueName 'NoSuchSpace'}"
    await page.fill '#apps-export-version', '1.0.0'
    await page.fill '#apps-export-seed', "#{unknownSpace}:nom"
    await page.click '#apps-export-btn'
    await expect(page.locator('#apps-export-error')).toBeVisible()
    await expect(page.locator('#apps-export-error')).toContainText(unknownSpace)
    noDownload2 = await page.waitForEvent('download', { timeout: 1500 }).catch(-> null)
    expect(noDownload2).toBeNull()

    # 2c — valid configuration: downloadable package with id, version and keys.
    await page.fill '#apps-export-seed', "#{spaceName}:nom"
    [download] = await Promise.all [
      page.waitForEvent('download', { timeout: 15000 })
      page.click '#apps-export-btn'
    ]
    expect(download.suggestedFilename()).toBe("#{appId}-1.0.0.tdbapp.yaml")
    exportedYaml = fs.readFileSync await download.path(), 'utf8'
    expect(exportedYaml).toContain appId
    expect(exportedYaml).toContain '1.0.0'
    expect(exportedYaml).toContain "space:#{spaceName}"
    expect(exportedYaml).toContain "field:#{spaceName}.nom"
    expect(exportedYaml).toContain "field:#{spaceName}.conflit"
  )

  test('3. install the exported package (all unchanged)', ({ page }) ->
    test.setTimeout 90000
    expect(exportedYaml).not.toBeNull()

    await performLogin page
    await openAppsPanel page
    await uploadPackage page, exportedYaml, "#{appId}-1.0.0.tdbapp.yaml"

    await expect(page.locator('#apps-plan-box')).toBeVisible({ timeout: 20000 })
    await expect(page.locator('#apps-plan-box .apps-conflict')).toHaveCount(0)
    await expect(page.locator('#apps-plan-box .apps-plan-unchanged')).toBeVisible()
    await expect(page.locator('#apps-apply-btn')).toBeEnabled()

    await page.click '#apps-apply-btn'
    await confirmModal page

    await expect(page.locator('#apps-apply-report')).toBeVisible()
    await expect(page.locator('#apps-list')).toContainText(appName)
    await expect(page.locator('#apps-list')).toContainText('1.0.0')
  )

  test('4. update v1.1.0 with local conflicts', ({ page }) ->
    test.setTimeout 120000
    token = await adminToken()

    # Local modifications: a field description (will conflict) and a space
    # description (will be kept because the author does not touch it).
    await gql 'mutation($id: ID!, $input: UpdateFieldInput!){ updateField(fieldId:$id, input:$input){ id } }',
      { id: fieldIds.conflit, input: { description: localConflitDesc } }, token
    await gql 'mutation($id: ID!, $input: UpdateSpaceInput!){ updateSpace(id:$id, input:$input){ id } }',
      { id: spaceId, input: { description: localSpaceDesc } }, token

    recordsBefore = await recordTotal token, spaceId

    await performLogin page
    await openAppsPanel page

    v11 = await page.evaluate((opts) ->
      doc = jsyaml.load(opts.yamlText)
      # js-yaml turns blank scalars into null (the backend emits empty strings
      # for absent formulas/descriptions). Restore the empty-string/empty-array
      # representation so untouched items keep their fingerprints.
      normalize = (it) ->
        c = it.content
        return unless c?
        if it.type == 'field'
          c.description ?= ''
          c.formula ?= ''
          c.triggerFields ?= []
          c.language ?= 'lua'
        else if it.type == 'space'
          c.description ?= ''
        else if it.type == 'plugin'
          c.description ?= ''
          c.scriptCode ?= ''
          c.templateCode ?= ''
          c.scriptLanguage ?= 'coffeescript'
          c.templateLanguage ?= 'pug'
        return
      normalize it for it in doc.items
      doc.app.version = '1.1.0'
      findItem = (key) -> doc.items.find (it) -> it.key == key
      findItem("field:#{opts.space}.conflit").content.description = opts.conflitDelivered
      findItem("field:#{opts.space}.auteur").content.description = opts.auteurDelivered
      doc.items = doc.items.filter (it) -> it.key != "field:#{opts.space}.supprime"
      doc.items.push
        type: 'field'
        key: "field:#{opts.space}.ajoute"
        content: { fieldType: 'String', notNull: false, description: 'Champ ajouté v1.1', formula: '', triggerFields: [], language: 'lua' }
      doc.items.push
        type: 'plugin'
        key: "plugin:#{opts.plugin}"
        content: { name: opts.plugin, description: 'Plugin livré v1.1', scriptLanguage: 'coffeescript', templateLanguage: 'pug', scriptCode: "module.exports = -> console.log 'hello'", templateCode: 'div Hello' }
      jsyaml.dump doc
    , { yamlText: exportedYaml, space: spaceName, plugin: pluginName, conflitDelivered: deliveredConflitDesc, auteurDelivered: deliveredAuteurDesc })

    await uploadPackage page, v11, "#{appId}-1.1.0.tdbapp.yaml"

    await expect(page.locator('#apps-plan-box')).toBeVisible({ timeout: 20000 })
    await expect(page.locator('#apps-apply-btn')).toBeEnabled()

    # Sections with the right items.
    await expect(page.locator('#apps-plan-box .apps-kept')).toContainText("space:#{spaceName}")
    await expect(page.locator('#apps-plan-box .diff-change')).toContainText("field:#{spaceName}.auteur")
    await expect(page.locator('#apps-plan-box .diff-delete')).toContainText("field:#{spaceName}.supprime")
    await expect(page.locator('#apps-plan-box .diff-create')).toContainText("field:#{spaceName}.ajoute")
    await expect(page.locator('#apps-plan-box .diff-create')).toContainText("plugin:#{pluginName}")
    # Plugin third-party code warning.
    await expect(page.locator('#apps-plan-box .diff-create .apps-code-badge')).toHaveCount(1)
    await expect(page.locator('#apps-plan-box .diff-create .apps-code-warning')).toHaveCount(1)

    # Conflict shows both local and delivered versions.
    conflict = page.locator '#apps-plan-box .apps-conflict'
    await expect(conflict).toContainText("field:#{spaceName}.conflit")
    await expect(conflict).toContainText(localConflitDesc)
    await expect(conflict).toContainText(deliveredConflitDesc)

    # Apply with the default decision "keep mine".
    await page.click '#apps-apply-btn'
    await confirmModal page
    await expect(page.locator('#apps-apply-report')).toBeVisible()

    # Database verification.
    after = await readSpaces token
    sp = after.find (s) -> s.name == spaceName
    fieldByName = (name) -> sp.fields.find (f) -> f.name == name

    expect(fieldByName('conflit').description).toBe(localConflitDesc)
    expect(fieldByName('auteur').description).toBe(deliveredAuteurDesc)
    expect(fieldByName('supprime')).toBeTruthy()
    expect(fieldByName('ajoute')).toBeTruthy()
    recordsAfter = await recordTotal token, spaceId
    expect(recordsAfter).toBe(recordsBefore)
    expect(recordsAfter).toBe(3)

    plugins = await gql '{ widgetPlugins { id name } }', {}, token
    expect((plugins.widgetPlugins or []).some((p) -> p.name == pluginName)).toBe(true)
  )

  test('5. purge obsolete element', ({ page }) ->
    test.setTimeout 120000
    token = await adminToken()

    await performLogin page
    await openAppsPanel page

    await expect(page.locator('#apps-purge-open-btn')).toBeEnabled()
    await page.click '#apps-purge-open-btn'
    await expect(page.locator('#apps-purge-box')).toBeVisible()

    checkboxes = page.locator '#apps-purge-items input[type=checkbox]'
    await expect(checkboxes).toHaveCount(1)
    await checkboxes.first().check()
    await page.click '#apps-purge-preview-btn'
    await expect(page.locator('#apps-purge-preview')).toBeVisible()
    await expect(page.locator('#apps-purge-preview')).toContainText('3')

    hint = await page.locator('#apps-purge-confirm-hint').innerText()
    target = hint.split(':').pop().trim()
    expect(target).toBe("#{spaceName}.supprime")

    await expect(page.locator('#apps-purge-confirm-btn')).toBeDisabled()
    await page.fill '#apps-purge-confirm-input', 'definitely-wrong'
    await expect(page.locator('#apps-purge-confirm-btn')).toBeDisabled()
    await page.fill '#apps-purge-confirm-input', target
    await expect(page.locator('#apps-purge-confirm-btn')).toBeEnabled()

    # Changing the selection invalidates the preview.
    await checkboxes.first().uncheck()
    await expect(page.locator('#apps-purge-preview')).toBeHidden()
    await expect(page.locator('#apps-purge-confirm-btn')).toBeDisabled()

    # Re-select, re-preview and confirm the purge.
    await checkboxes.first().check()
    await page.click '#apps-purge-preview-btn'
    await expect(page.locator('#apps-purge-preview')).toBeVisible()
    await page.fill '#apps-purge-confirm-input', target
    await expect(page.locator('#apps-purge-confirm-btn')).toBeEnabled()
    await page.click '#apps-purge-confirm-btn'
    await confirmModal page
    # The report lives inside the purge box, which is hidden on success, so
    # check its text content rather than its visibility.
    await expect(page.locator('#apps-purge-report')).toContainText(/\d/, { timeout: 15000 })
    await expect(page.locator('#apps-purge-report')).toHaveClass(/snapshot-result-ok/)

    after = await readSpaces token
    sp = after.find (s) -> s.name == spaceName
    names = (f.name for f in sp.fields)
    expect(names).not.toContain('supprime')
    expect(names).toContain('nom')
    expect(names).toContain('conflit')
    expect(names).toContain('auteur')
    expect(names).toContain('ajoute')
    recordsAfter = await recordTotal token, spaceId
    expect(recordsAfter).toBe(3)
  )

  test('6. package name is never inserted as HTML', ({ page }) ->
    test.setTimeout 120000
    token = await adminToken()
    xssAppId = "org.test.e2e.xss.#{Date.now()}"
    fresh = await gql 'query($meta: AppMetaInput!){ exportApp(meta:$meta) }',
      { meta: { id: xssAppId, name: 'xss-pkg', version: '1.0.0', description: '' } }, token

    await performLogin page
    await openAppsPanel page

    xssYaml = await page.evaluate(({ yamlText, payload }) ->
      doc = jsyaml.load(yamlText)
      normalize = (it) ->
        c = it.content
        return unless c?
        if it.type == 'field'
          c.description ?= ''
          c.formula ?= ''
          c.triggerFields ?= []
          c.language ?= 'lua'
        else if it.type == 'space'
          c.description ?= ''
        else if it.type == 'plugin'
          c.description ?= ''
          c.scriptCode ?= ''
          c.templateCode ?= ''
          c.scriptLanguage ?= 'coffeescript'
          c.templateLanguage ?= 'pug'
        return
      normalize it for it in doc.items
      doc.app.name = payload
      jsyaml.dump doc
    , { yamlText: fresh.exportApp, payload: XSS })

    await uploadPackage page, xssYaml, "#{xssAppId}-1.0.0.tdbapp.yaml"
    await expect(page.locator('#apps-plan-box')).toBeVisible({ timeout: 20000 })
    await expect(page.locator('#apps-apply-btn')).toBeEnabled()
    await page.click '#apps-apply-btn'
    await confirmModal page
    await expect(page.locator('#apps-apply-report')).toBeVisible()
    await expect(page.locator('#apps-list')).toContainText(XSS)

    imgCount = await page.evaluate(-> document.getElementById('admin-apps-section').querySelectorAll('img').length)
    expect(imgCount).toBe(0)
    xssFlag = await page.evaluate(-> window.__xss)
    expect(xssFlag).toBeUndefined()
  )
)
