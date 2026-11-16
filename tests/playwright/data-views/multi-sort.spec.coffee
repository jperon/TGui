# tests/playwright/data-views/multi-sort.spec.coffee
# Tri multicritère hiérarchisé (menu « Trier / Filtrer » et en-têtes).
#
# Le test crée son propre espace (deux colonnes, doublons sur la première) via
# l'API GraphQL puis vérifie l'ordre RÉEL des lignes de la grille :
#   - deux critères ajoutés par le menu : le premier décide, le second départage ;
#   - monter le second critère change l'ordre (priorité) ;
#   - un préréglage enregistré puis réappliqué restitue les deux critères ;
#   - Maj+clic et Ctrl+clic sur un en-tête ajoutent un critère sans effacer l'autre.

{ test, expect } = require '@playwright/test'
{ performLogin, generateUniqueName } = require '../config/parallel-helper'

gql = (page, query, variables = null) ->
  page.evaluate ({ query, variables }) ->
    token = localStorage.getItem 'tdb_token'
    fetch('/graphql', {
      method: 'POST'
      headers: { 'Content-Type': 'application/json', 'Authorization': "Bearer #{token}" }
      body: JSON.stringify({ query: query, variables: variables })
    }).then (r) -> r.json()
  , { query, variables }

# Ordre réel des lignes (sentinelle exclue), lu sur le DataView de la grille
# principale : c'est l'ordre trié que Toast UI Grid affiche.
gridPairs = (page) ->
  page.evaluate ->
    dv = window.App?._activeDataView
    rows = dv?._grid?.getData?() or []
    ([String(row.groupe ? ''), String(row.nom ? '')] for row in rows when not row.__isNew)

criterionColumns = (page) ->
  page.locator('.view-presets-sort-row .view-presets-sort-label').allTextContents()

openMenu = (page) ->
  await page.click '.view-presets-btn'
  await expect(page.locator('.view-presets-menu')).toBeVisible()

addCriterion = (page, column, direction = 'asc') ->
  await page.selectOption '.view-presets-add-column', { label: column }
  await page.selectOption '.view-presets-add-direction', direction
  await page.click '.view-presets-add-btn'
  await page.waitForTimeout 300

test.describe.serial 'Tri multicritère', ->
  spaceName = generateUniqueName 'TriMulti'
  spaceId = null

  test.beforeAll ({ browser }) ->
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    created = await gql p,
      'mutation($input: CreateSpaceInput!) { createSpace(input: $input) { id name } }',
      { input: { name: spaceName } }
    expect(created?.data?.createSpace?.id,
      "createSpace a échoué : #{JSON.stringify(created)}").toBeTruthy()
    spaceId = created.data.createSpace.id
    fields = await gql p,
      'mutation($spaceId: ID!, $inputs: [FieldInput!]!) { addFields(spaceId: $spaceId, inputs: $inputs) { id name } }',
      { spaceId: spaceId, inputs: [{ name: 'groupe', fieldType: 'String' }, { name: 'nom', fieldType: 'String' }] }
    expect(fields?.data?.addFields?.length, "addFields a échoué : #{JSON.stringify(fields)}").toBe 2
    rows = await gql p,
      'mutation($spaceId: ID!, $data: [JSON!]!) { insertRecords(spaceId: $spaceId, data: $data) { id } }',
      { spaceId: spaceId, data: [
        { groupe: 'B', nom: 'a' }
        { groupe: 'A', nom: 'b' }
        { groupe: 'B', nom: 'b' }
        { groupe: 'A', nom: 'a' }
      ] }
    expect(rows?.data?.insertRecords?.length, "insertRecords a échoué : #{JSON.stringify(rows)}").toBe 4
    await ctx.close()

  test.afterAll ({ browser }) ->
    return unless spaceId
    ctx = await browser.newContext()
    p = await ctx.newPage()
    await performLogin p
    await gql p, 'mutation($id: ID!) { deleteSpace(id: $id) }', { id: spaceId }
    await ctx.close()

  test.beforeEach ({ page }) ->
    await performLogin page
    spacesList = page.locator '#space-list'
    if await spacesList.isHidden()
      await page.click '#spaces-toggle-btn'
      await page.waitForTimeout 300
    await page.click "#space-list li[data-id=\"#{spaceId}\"]"
    await expect(page.locator('.view-presets-btn')).toBeVisible()
    await expect(page.locator('#grid-container .tui-grid-cell').first()).toBeVisible()
    await page.waitForTimeout 500

  test 'deux critères via le menu : égalités départagées par le second, puis priorité inversée', ({ page }) ->
    await openMenu page

    await addCriterion page, 'groupe', 'asc'
    await addCriterion page, 'nom', 'asc'
    expect(await criterionColumns(page)).toEqual ['groupe', 'nom']
    expect(await gridPairs(page)).toEqual [
      ['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']
    ]

    # Monter le second critère : il devient prioritaire et change l'ordre.
    await page.locator('.view-presets-sort-row').nth(1).locator('[data-action="up"]').click()
    await page.waitForTimeout 300
    expect(await criterionColumns(page)).toEqual ['nom', 'groupe']
    expect(await gridPairs(page)).toEqual [
      ['A', 'a'], ['B', 'a'], ['A', 'b'], ['B', 'b']
    ]

    # Bascule du sens du premier critère (nom décroissant, groupe départage).
    await page.locator('.view-presets-sort-row').nth(0).locator('[data-action="dir"]').click()
    await page.waitForTimeout 300
    expect(await gridPairs(page)).toEqual [
      ['A', 'b'], ['B', 'b'], ['A', 'a'], ['B', 'a']
    ]

  test 'préréglage : enregistrer puis réappliquer restitue les deux critères', ({ page }) ->
    presetName = "Deux critères #{Date.now()}"
    await openMenu page
    await addCriterion page, 'groupe', 'asc'
    await addCriterion page, 'nom', 'asc'
    expect(await gridPairs(page)).toEqual [
      ['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']
    ]

    page.once 'dialog', (dialog) -> dialog.accept presetName
    await page.click '.view-presets-save'
    await expect(page.locator('.view-presets-preset', { hasText: presetName })).toBeVisible()
    await expect(page.locator('.view-presets-btn')).toContainText presetName

    # Tri simple sur un en-tête : un seul critère, l'ordre change.
    await page.keyboard.press 'Escape'
    await page.locator('#grid-container th[data-column-name="nom"] .tui-grid-btn-sorting').click()
    await page.waitForTimeout 500
    await openMenu page
    expect(await criterionColumns(page)).toEqual ['nom']

    # Réapplique le préréglage : les deux critères reviennent, dans l'ordre.
    await page.locator('.view-presets-preset', { hasText: presetName }).click()
    await page.waitForTimeout 500
    expect(await gridPairs(page)).toEqual [
      ['A', 'a'], ['A', 'b'], ['B', 'a'], ['B', 'b']
    ]
    await openMenu page
    expect(await criterionColumns(page)).toEqual ['groupe', 'nom']
    await page.keyboard.press 'Escape'

  test 'Maj+clic et Ctrl+clic sur un en-tête ajoutent un critère sans effacer l’autre', ({ page }) ->
    # Clic simple : tri unique (comportement inchangé).
    await page.locator('#grid-container th[data-column-name="groupe"] .tui-grid-btn-sorting').click()
    await page.waitForTimeout 500
    await openMenu page
    expect(await criterionColumns(page)).toEqual ['groupe']
    await page.keyboard.press 'Escape'

    # Maj+clic ajoute le second critère en fin de liste.
    await page.locator('#grid-container th[data-column-name="nom"] .tui-grid-btn-sorting').click({ modifiers: ['Shift'] })
    await page.waitForTimeout 500
    await openMenu page
    expect(await criterionColumns(page)).toEqual ['groupe', 'nom']
    await page.keyboard.press 'Escape'

    # Ctrl+clic : multi-tri natif de Toast UI Grid, même résultat.
    await page.locator('#grid-container th[data-column-name="groupe"] .tui-grid-btn-sorting').click()
    await page.waitForTimeout 400
    await page.locator('#grid-container th[data-column-name="nom"] .tui-grid-btn-sorting').click({ modifiers: ['Control'] })
    await page.waitForTimeout 500
    await openMenu page
    expect(await criterionColumns(page)).toEqual ['groupe', 'nom']
