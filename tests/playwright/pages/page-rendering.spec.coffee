# tests/playwright/pages/page-rendering.spec.coffee
# Régression navigateur : une page (custom view) doit AFFICHER ses widgets.
#
# Garde trois bugs corrigés ensemble :
#   - sortablejs.bundle.js absent de la page (drag & drop / pages cassés)
#   - renderCustomViewPreview n'appelait pas CustomView.mount()
#   - #custom-view-container restait masqué (classe 'hidden')
# Le test est autonome : il crée sa page via l'API et la supprime à la fin.

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

gql = (page, query) ->
  page.evaluate (q) ->
    token = localStorage.getItem 'tdb_token'
    fetch('/graphql', {
      method: 'POST'
      headers: { 'Content-Type': 'application/json', 'Authorization': "Bearer #{token}" }
      body: JSON.stringify({ query: q })
    }).then (r) -> r.json()
  , query

test.describe 'Page rendering', ->
  pageName = generateUniqueName 'RenderPage'
  createdId = null

  test.afterAll ({ browser }) ->
    return unless createdId
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    await gql p, "mutation { deleteCustomView(id: \"#{createdId}\") }"
    await ctx.close()

  test 'a page displays its widget grid with data', ({ page }) ->
    await performLogin page

    # SortableJS doit être chargé (sinon les pages avec zones cassent)
    sortableLoaded = await page.evaluate -> typeof Sortable isnt 'undefined'
    expect(sortableLoaded, 'SortableJS doit être chargé').toBe true

    # Crée une page avec un widget sur l'espace "Livres" (jeu d'exemple de la
    # bibliothèque installée par backend/fixtures.moon)
    yaml = "layout:\\n  direction: vertical\\n  children:\\n    - widget:\\n        id: w1\\n        title: Catalogue\\n        space: Livres\\n        columns: [titre, note]"
    res = await gql page, "mutation { createCustomView(input: { name: \"#{pageName}\", yaml: \"#{yaml}\" }) { id name } }"
    expect(res?.data?.createCustomView?.id, "createCustomView a échoué: #{JSON.stringify(res)}").toBeTruthy()
    createdId = res.data.createCustomView.id

    # Recharge complètement l'app (session déjà active) puis ouvre la page
    await page.goto '/'
    await page.waitForSelector '#main', { state: 'visible' }
    pageLeaf = page.locator('#page-list .leaf-item', { hasText: pageName }).first()
    await expect(pageLeaf).toBeVisible()
    await pageLeaf.click()

    # Le conteneur d'aperçu doit devenir visible et contenir une grille avec des lignes
    container = page.locator '#custom-view-container'
    await expect(container).toBeVisible()
    grid = container.locator '.tui-grid-container, [class*="tui-grid"]'
    await expect(grid.first()).toBeVisible()
    # Au moins une ligne de données (les livres de la bibliothèque)
    await expect(container.locator('.tui-grid-cell').first()).toBeVisible()
