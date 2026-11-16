# tests/js/test_view_presets_menu.coffee
# Menu « Trier / Filtrer » : sérialisation du tri, application d'un préréglage
# (filtre + tri), « Enregistrer sous », suppression, mise en évidence.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

queries       = []
mutationCalls = []
serverPresets = []
promptAnswers = []
confirmAnswers = []

global.window.prompt  = -> promptAnswers.shift() ? null
global.window.confirm = -> confirmAnswers.shift() ? false

global.window.GQL =
  query: (q, vars) ->
    queries.push { q, vars }
    Promise.resolve viewPresets: (Object.assign({}, p) for p in serverPresets)
  mutate: (m, vars) ->
    mutationCalls.push { m, vars }
    if /deleteViewPreset/.test m
      Promise.resolve deleteViewPreset: true
    else
      saved = Object.assign { id: 'saved-id', scope: vars.scope, spaceId: vars.spaceId,
        name: vars.name, filter: vars.filter, sort: vars.sort }, {}
      Promise.resolve saveViewPreset: saved

require '../../frontend/src/views/view_presets_menu'
VPM = global.window.ViewPresetsMenu

P_SORTED =
  id: 'p2'
  scope: 'widget:page1:w1'
  spaceId: 's1'
  name: 'Récents'
  filter: ''
  sort: '[{"column":"date","ascending":false}]'

P_FILTERED =
  id: 'p1'
  scope: 'widget:page1:w1'
  spaceId: 's1'
  name: 'Actifs'
  filter: 'self.actif'
  sort: '[]'

makeDv = (entries = [], fieldNames = ['date', 'titre', 'note', 'nom', 'age']) ->
  state =
    sort: (Object.assign({}, e) for e in entries)
    filters: []
    applied: []
  dv =
    _state: state
    space:
      id: 's1'
      name: 'test'
      fields: ({ name: n, fieldType: 'Str' } for n in fieldNames)
    _grid:
      getSortState: ->
        columns: [{ columnName: 'sortKey', ascending: true }].concat(
          { columnName: e.column, ascending: e.ascending } for e in state.sort
        )
      sort: -> null
      unsort: -> null
    getSortEntries: -> (Object.assign({}, e) for e in state.sort)
    applySortEntries: (entries) ->
      clean = VPM.normalizeEntries entries
      state.applied.push clean
      state.sort = (Object.assign({}, e) for e in clean)
      clean
    setFormulaFilter: (formula) -> state.filters.push formula
  dv

makeHarness = (scope = 'widget:page1:w1', spaceId = 's1', entries = []) ->
  wrap = global.document.createElement 'div'
  input = global.document.createElement 'input'
  wrap.appendChild input
  dv = makeDv entries
  api = VPM.attach wrap, {
    getDataView: -> dv
    scope: scope
    spaceId: spaceId
    filterInput: input
  }
  { wrap, input, dv, api }

# Bouton d'une ligne de critère (le rang et le libellé ne sont pas des boutons).
sortButton = (row, action) ->
  for btn in row.children
    return btn if btn.dataset.action == action
  null

sortRow = (api, index) -> api.elements.sortList.children[index]

describe 'ViewPresetsMenu — sérialisation du tri', ->
  it 'lit getSortState et ignore la colonne technique sortKey', ->
    dv = _grid: getSortState: -> {
      useClient: true
      columns: [
        { columnName: 'sortKey', ascending: true }
        { columnName: 'nom', ascending: false }
        { column: 'age', ascending: true }
      ]
    }
    deepEq VPM.sortEntriesFrom(dv), [
      { column: 'nom', ascending: false }
      { column: 'age', ascending: true }
    ]

  it 'sérialise au format texte JSON attendu par le backend', ->
    entries = [{ column: 'nom', ascending: true }]
    eq VPM.serializeSort(entries), '[{"column":"nom","ascending":true}]'

  it 'parse un tri stocké et tolère le JSON invalide', ->
    deepEq VPM.parseSort('[{"column":"date","ascending":false}]'), [
      { column: 'date', ascending: false }
    ]
    deepEq VPM.parseSort('pas du json'), []

describe 'ViewPresetsMenu — application d’un préréglage', ->
  it 'applique le filtre et le tri du préréglage', ->
    h = makeHarness()
    h.api.applyPreset P_SORTED
    eq h.input.value, ''
    eq h.input.classList.contains('active'), false
    deepEq h.dv._state.filters, ['']
    deepEq h.dv._state.applied, [[{ column: 'date', ascending: false }]]

  it 'remplit le champ filtre et le marque actif', ->
    h = makeHarness()
    h.api.applyPreset P_FILTERED
    eq h.input.value, 'self.actif'
    eq h.input.classList.contains('active'), true
    deepEq h.dv._state.filters, ['self.actif']

  it 'affiche le nom du préréglage actif sur le bouton', ->
    h = makeHarness()
    h.api.applyPreset P_FILTERED
    eq h.api.button.textContent, 'Trier / Filtrer · Actifs'

  it 'retire la mise en évidence à la moindre frappe dans le filtre', ->
    h = makeHarness()
    h.api.applyPreset P_FILTERED
    h.input._listeners.input[0] { target: h.input }
    eq h.api.button.textContent, 'Trier / Filtrer'

  it 'met en évidence le préréglage actif dans la liste', ->
    serverPresets = [P_FILTERED, P_SORTED]
    h = makeHarness()
    h.api.open().then ->
      h.api.applyPreset P_SORTED
      rows = h.api.elements.presetList.children
      eq rows.length, 2
      eq rows[0].classList.contains('active'), false
      eq rows[1].classList.contains('active'), true

  it 'retire la mise en évidence quand le tri change à la main', ->
    h = makeHarness()
    h.api.applyPreset P_SORTED
    eq h.api.button.textContent, 'Trier / Filtrer · Récents'
    h.dv._state.sort = [{ column: 'titre', ascending: true }]
    h.dv._onSortChanged()
    eq h.api.button.textContent, 'Trier / Filtrer'

  it 'permet de retirer un critère de tri', ->
    h = makeHarness 'widget:page1:w1', 's1', [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
    ]
    h.api.open()
    rows = h.api.elements.sortList.children
    eq rows.length, 2
    sortButton(rows[0], 'remove')._listeners.click[0]()
    deepEq h.dv._state.sort, [{ column: 'note', ascending: false }]
    eq h.api.elements.sortList.children.length, 1

describe 'ViewPresetsMenu — tri multicritère', ->
  it 'affiche le rang, la colonne, le sens et les boutons de priorité', ->
    h = makeHarness 'widget:page1:w1', 's1', [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
    ]
    h.api.open()
    row = sortRow h.api, 0
    eq row.dataset.rank, '1'
    eq sortRow(h.api, 1).dataset.rank, '2'
    eq row.children[0].textContent, '1.'
    eq row.children[1].textContent, 'titre'
    eq sortButton(row, 'dir').textContent, '↑'
    eq sortButton(sortRow(h.api, 1), 'dir').textContent, '↓'
    eq sortButton(row, 'up').disabled, true
    eq sortButton(sortRow(h.api, 1), 'down').disabled, true

  it 'rappelle l’astuce Maj/Ctrl+clic dans le texte vide', ->
    h = makeHarness()
    h.api.open()
    txt = h.api.elements.sortList.children[0].textContent
    assert /Maj\+clic/.test(txt), "astuce absente : #{txt}"

  it 'ajoute un critère non trié en fin de liste', ->
    h = makeHarness 'widget:page1:w1', 's1', [{ column: 'titre', ascending: true }]
    h.api.open()
    select = h.api.elements.addColumnSelect
    values = (opt.value for opt in select.children)
    assert values.indexOf('titre') == -1, "la colonne déjà triée ne doit pas être proposée : #{values}"
    assert values.indexOf('note') != -1, "la colonne note doit être proposée : #{values}"
    select.value = 'note'
    h.api.elements.addDirectionSelect.value = 'desc'
    h.api.elements.addBtn._listeners.click[0]()
    deepEq h.dv._state.applied[h.dv._state.applied.length - 1], [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
    ]
    eq h.api.elements.sortList.children.length, 2
    eq sortRow(h.api, 1).dataset.column, 'note'

  it 'réordonne les critères avec monter/descendre', ->
    h = makeHarness 'widget:page1:w1', 's1', [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
      { column: 'nom', ascending: true }
    ]
    h.api.open()
    sortButton(sortRow(h.api, 2), 'up')._listeners.click[0]()
    deepEq h.dv._state.sort, [
      { column: 'titre', ascending: true }
      { column: 'nom', ascending: true }
      { column: 'note', ascending: false }
    ]
    eq sortRow(h.api, 1).children[1].textContent, 'nom'
    sortButton(sortRow(h.api, 0), 'down')._listeners.click[0]()
    deepEq h.dv._state.sort, [
      { column: 'nom', ascending: true }
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
    ]

  it 'bascule le sens d’un critère sans changer sa priorité', ->
    h = makeHarness 'widget:page1:w1', 's1', [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
    ]
    h.api.open()
    sortButton(sortRow(h.api, 1), 'dir')._listeners.click[0]()
    deepEq h.dv._state.sort, [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: true }
    ]
    eq sortButton(sortRow(h.api, 1), 'dir').textContent, '↑'

  it 'sérialise les critères dans l’ordre de priorité', ->
    h = makeHarness 'space:s1', 's1', [
      { column: 'titre', ascending: true }
      { column: 'note', ascending: false }
    ]
    h.api.open()
    sortButton(sortRow(h.api, 1), 'up')._listeners.click[0]()
    promptAnswers.push 'Priorité'
    h.api.saveCurrent().then ->
      call = (c for c in mutationCalls when c.vars.name == 'Priorité')[0]
      assert call, 'mutation saveViewPreset attendue'
      eq call.vars.sort, '[{"column":"note","ascending":false},{"column":"titre","ascending":true}]'

  it 'retire la mise en évidence du préréglage actif quand le tri change', ->
    h = makeHarness()
    h.api.applyPreset P_SORTED
    eq h.api.button.textContent, 'Trier / Filtrer · Récents'
    h.api.open()
    h.api.elements.addColumnSelect.value = 'titre'
    h.api.elements.addBtn._listeners.click[0]()
    eq h.api.button.textContent, 'Trier / Filtrer'

describe 'ViewPresetsMenu — enregistrement et suppression', ->
  it '« Enregistrer sous… » envoie la portée du widget, le filtre et le tri', ->
    h = makeHarness 'widget:page1:w1', 's1', [{ column: 'nom', ascending: true }]
    h.input.value = 'self.actif'
    promptAnswers.push 'Mon préréglage'
    h.api.saveCurrent().then ->
      calls = (c for c in mutationCalls when c.vars.name == 'Mon préréglage')
      eq calls.length, 1
      call = calls[0]
      assert /saveViewPreset/.test(call.m), 'mutation saveViewPreset attendue'
      eq call.vars.scope, 'widget:page1:w1'
      eq call.vars.spaceId, 's1'
      eq call.vars.filter, 'self.actif'
      eq call.vars.sort, '[{"column":"nom","ascending":true}]'
      eq h.api.button.textContent, 'Trier / Filtrer · Mon préréglage'

  it '« Enregistrer sous… » utilise la portée de la grille principale', ->
    h = makeHarness 'space:s1', 's1'
    promptAnswers.push 'Espace'
    h.api.saveCurrent().then ->
      calls = (c for c in mutationCalls when c.vars.name == 'Espace')
      eq calls[0].vars.scope, 'space:s1'
      eq calls[0].vars.spaceId, 's1'

  it 'supprime le préréglage après confirmation', ->
    serverPresets = [P_FILTERED, P_SORTED]
    h = makeHarness()
    h.api.open().then ->
      confirmAnswers.push true
      h.api.deletePreset P_FILTERED
      .then ->
        calls = (c for c in mutationCalls when /deleteViewPreset/.test c.m)
        eq calls.length, 1
        eq calls[0].vars.id, 'p1'
        eq h.api.elements.presetList.children.length, 1

  it 'ne supprime rien sans confirmation', ->
    serverPresets = [P_FILTERED]
    h = makeHarness()
    h.api.open().then ->
      confirmAnswers.push false
      before = mutationCalls.length
      h.api.deletePreset P_FILTERED
      .then ->
        eq mutationCalls.length, before
        eq h.api.elements.presetList.children.length, 1

describe 'ViewPresetsMenu — cycle de vie', ->
  it 'retire son écouteur input à la destruction', ->
    wrap  = global.document.createElement 'div'
    input = global.document.createElement 'input'
    wrap.appendChild input
    dv = makeDv()
    api = VPM.attach wrap, { getDataView: (-> dv), scope: 'space:s1', spaceId: 's1', filterInput: input }
    eq (input._listeners.input or []).length, 1
    api.destroy()
    eq (input._listeners.input or []).length, 0

  it 'ne les accumule pas quand la grille réattache le menu au même input', ->
    wrap  = global.document.createElement 'div'
    input = global.document.createElement 'input'
    wrap.appendChild input
    dv = makeDv()
    opts = { getDataView: (-> dv), scope: 'space:s1', spaceId: 's1', filterInput: input }
    api1 = VPM.attach wrap, opts
    eq (input._listeners.input or []).length, 1
    # Changement d'espace : la grille principale réattache sur le même input.
    api2 = VPM.attach wrap, opts
    eq (input._listeners.input or []).length, 1
    api2.destroy()
    eq (input._listeners.input or []).length, 0

summary()
