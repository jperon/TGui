# tests/playwright/pages/add-widget-custom-widget.spec.coffee
# Fenêtre « ＋ Widget » : les widgets personnalisés (WidgetPlugin) sont proposés
# dans « 2. Type de widget », et un widget ainsi créé est écrit dans le YAML de
# la page puis rendu comme plugin (iframe) avec ses `params`.
# Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §3 bis (étape 2).
# Le test crée son plugin et sa page via l'API, et les supprime à la fin.

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

test.describe.serial 'Fenêtre ＋ Widget — widgets personnalisés', ->
  stamp = Date.now()
  pluginName = "wadd_plugin_#{stamp}"
  pageName = generateUniqueName 'AddWidgetPlugin'
  pageId = null
  pluginId = null

  scriptCode = """
  module.exports = function (api) {
    var titre = (api.params && api.params.titre) || 'sans-titre';
    api.render('<div id="res">PLUGIN ' + titre + '</div>');
  };
  """

  templateCode = '<div id="res">init</div>'

  test.afterAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    if pageId
      await gql p, 'mutation($id: ID!) { deleteCustomView(id: $id) }', { id: pageId }
    if pluginId
      await gql p, 'mutation($id: ID!) { deleteWidgetPlugin(id: $id) }', { id: pluginId }
    await ctx.close()

  test 'un widget personnalisé se choisit et se rend depuis cette fenêtre', ({ page }) ->
    await performLogin page

    # 1. Une définition de widget personnalisé, créée par l'API (admin)
    created = await gql page,
      'mutation($input: CreateWidgetPluginInput!) { createWidgetPlugin(input: $input) { id name } }',
      { input: { name: pluginName, description: 'Widget de test (fenêtre ＋ Widget)',
                 scriptLanguage: 'javascript', templateLanguage: 'html',
                 scriptCode: scriptCode, templateCode: templateCode } }
    expect(created?.data?.createWidgetPlugin?.name,
      "createWidgetPlugin a échoué: #{JSON.stringify(created)}").toBe pluginName
    pluginId = created.data.createWidgetPlugin.id

    # 2. Une page vide
    emptyYaml = "layout:\n  direction: vertical\n  children: []"
    pageRes = await gql page,
      'mutation($input: CreateCustomViewInput!) { createCustomView(input: $input) { id name } }',
      { input: { name: pageName, yaml: emptyYaml } }
    expect(pageRes?.data?.createCustomView?.id,
      "createCustomView a échoué: #{JSON.stringify(pageRes)}").toBeTruthy()
    pageId = pageRes.data.createCustomView.id

    # 3. Ouvrir la page
    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    leaf = page.locator('#page-list .leaf-item', { hasText: pageName }).first()
    await expect(leaf).toBeVisible()
    await leaf.click()
    await expect(page.locator('#custom-view-container')).toBeVisible()

    # 4. « ＋ Widget » : le plugin est proposé dans le groupe des widgets personnalisés
    await page.click '#yaml-add-widget-btn'
    modal = page.locator '#add-widget-modal'
    await expect(modal).toBeVisible()

    pluginOption = page.locator('#widget-type-plugin-list .widget-type-option',
      { hasText: pluginName }).first()
    await expect(pluginOption).toBeVisible()
    await expect(pluginOption).toHaveAttribute 'title', 'Widget de test (fenêtre ＋ Widget)'
    await expect(page.locator '#widget-type-plugin-list .widget-type-hint').toHaveCount 0

    # Lien vers l'éditeur de plugins (admin)
    newPluginLink = page.locator '#widget-type-new-plugin'
    await expect(newPluginLink).toBeVisible()

    # 5. Choisir le widget personnalisé, puis valider sans colonne
    await pluginOption.locator('label').click()
    await expect(pluginOption.locator('input[type="radio"]')).toBeChecked()

    await page.fill '#widget-title-input', 'Mon widget personnalisé'
    await page.selectOption '#widget-space-select', { label: 'Livres' }

    await page.fill '#widget-params-list .param-row:first-child .param-key', 'titre'
    await page.fill '#widget-params-list .param-row:first-child .param-value', 'Custom'

    await page.click '#add-widget-confirm-btn'
    await expect(modal).toBeHidden()

    # 6. Le widget apparaît et son iframe rend son contenu (donc les params arrivent)
    widget = page.locator ".cv-widget[data-widget-type=\"#{pluginName}\"]"
    await expect(widget).toBeVisible()

    frame = page.frameLocator(".cv-widget[data-widget-type=\"#{pluginName}\"] iframe")
    await expect(frame.locator('#res')).toContainText 'PLUGIN Custom', { timeout: 15000 }

    # 7. Le YAML de la page contient bien le nœud plugin (type, params, space, id)
    saved = await gql page,
      'query($id: ID!) { customView(id: $id) { yaml } }', { id: pageId }
    yaml = saved?.data?.customView?.yaml or ''
    expect(yaml, "YAML enregistré: #{yaml}").toContain "type: '#{pluginName}'"
    expect(yaml, "YAML enregistré: #{yaml}").toContain 'params:'
    expect(yaml, "YAML enregistré: #{yaml}").toContain "'titre': 'Custom'"
    expect(yaml, "YAML enregistré: #{yaml}").toContain 'space: Livres'
    expect(yaml, "YAML enregistré: #{yaml}").toMatch /id: \S+/
