# tests/js/test_fields_helpers_computed_relation.coffee
# A relation may be declared on a COMPUTED field (read-time formula returning
# the target id). The fields panel must then:
#   - keep the formula section visible when the type is Relation;
#   - show the formula of an existing computed relation when editing it;
#   - transmit the typed formula when creating a Relation field (or when
#     changing a field's type to Relation).
#
# The runner starts every it() immediately (async tests overlap), so all tests
# share ONE Spaces stub recording into `calls`: each test uses unique ids and
# filters its own entries instead of relying on per-test stubs.

require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'
{ makeElement } = require './dom_stub'

require '../../frontend/src/app_fields_helpers'
H = global.window.AppFieldsHelpers

# --- element stubs ----------------------------------------------------------

formulaSectionEl = makeElement 'div'
formulaBodyEl    = makeElement 'div'
reprSectionEl    = makeElement 'div'
notNullLabelEl   = makeElement 'label'
# makeElement has no closest(): attach one so hiding the formula section would
# be observable (today it must not happen for a Relation).
formulaBodyEl.closest = (sel) -> if sel == '.formula-section' then formulaSectionEl else null

radio = (value) -> { value: value, checked: false }
radios =
  none:    radio 'none'
  formula: radio 'formula'
  trigger: radio 'trigger'

document.querySelector = (sel) ->
  if sel == 'input[name="formula-type"]:checked'
    for own k, r of radios
      return r if r.checked
    return radios.none
  m = sel.match /input\[name="formula-type"\]\[value="(\w+)"\]/
  return (radios[m[1]] ? null) if m
  null
document.getElementById = (id) ->
  return reprSectionEl if id == 'field-repr-section'
  null

selectRadio = (name) ->
  r.checked = false for own k, r of radios
  radios[name].checked = true

makeApp = (overrides = {}) ->
  els =
    fieldType:          makeElement 'select'
    relTargetRow:       makeElement 'div'
    relReprRow:         makeElement 'div'
    relToSpace:         makeElement 'select'
    relReprFormula:     makeElement 'input'
    fieldNotNull:       makeElement 'input'
    fieldName:          makeElement 'input'
    fieldFormula:       makeElement 'textarea'
    formulaLanguage:    makeElement 'select'
    formulaBody:        makeElement 'div'
    triggerFieldsRow:   makeElement 'div'
    fieldTriggerFields: makeElement 'input'
    fieldReprFormula:   makeElement 'input'
    fieldAddBtn:        makeElement 'button'
    fieldCancelBtn:     makeElement 'button'
  els.fieldName.focus = ->
  els.fieldFormula.value = ''
  els.formulaLanguage.value = 'lua'
  els.formulaBody = formulaBodyEl
  els.fieldNotNull.closest = (sel) -> if sel == 'label' then notNullLabelEl else null

  app =
    el: {}
    _allSpaces: [{ id: 'tgt1', name: 'classes' }]
    _t: (k) -> k
    _err: (e) -> String e
    _editingFieldId: null
    _editingRelation: null
    _currentSpace: { id: 'src1', name: 'pers', fields: [] }
    _onFieldTypeChange: -> H.onFieldTypeChange app
    updateFieldProperties: (fieldId, opts, formulaType) ->
      H.updateFieldProperties app, fieldId, opts, formulaType
    _resetFieldForm: ->
    _syncSpaceFields: ->
    renderFieldsList: ->
    _mountDataView: ->
  for own k, v of els
    app.el[k] = do (v = v) -> -> v
  for own k, v of overrides
    app[k] = v
  app

# --- Spaces stub ------------------------------------------------------------

calls = []
targetSpace = { id: 'tgt1', name: 'classes',
  fields: [{ id: 'idf', fieldType: 'Sequence' }] }

global.Spaces =
  getWithFields: (id) ->
    calls.push { kind: 'getWithFields', id }
    Promise.resolve targetSpace
  addField: (spaceId, name, type, notNull, desc, formula, triggerFields, language) ->
    calls.push { kind: 'addField', spaceId, name, fieldType: type, formula, triggerFields, language }
    Promise.resolve { id: "new_#{spaceId}" }
  createRelation: (name, fromSpaceId, fromFieldId, toSpaceId, toFieldId, reprFormula) ->
    calls.push { kind: 'createRelation', name, fromSpaceId, fromFieldId, toSpaceId, reprFormula }
    Promise.resolve { id: 'rel1' }
  changeFieldType: (fieldId, fieldType, conversionFormula, language) ->
    calls.push { kind: 'changeFieldType', fieldId, fieldType, conversionFormula, language }
    Promise.resolve { id: fieldId, fieldType }
  updateField: (fieldId, opts) ->
    calls.push { kind: 'updateField', fieldId, opts }
    Promise.resolve { id: fieldId }
  updateRelation: (id, reprFormula) ->
    calls.push { kind: 'updateRelation', id, reprFormula }
    Promise.resolve { id }

global.tdbAlert = ->

flush = -> new Promise (resolve) -> setImmediate resolve

# ---------------------------------------------------------------------------
describe 'onFieldTypeChange — Relation garde la section formule', ->
  it 'ne masque pas la section formule', ->
    app = makeApp()
    app.el.fieldType().value = 'Relation'
    formulaSectionEl.classList.remove 'hidden'
    H.onFieldTypeChange app
    assert !formulaSectionEl.classList.contains('hidden'), 'formula-section ne doit pas être masquée pour une Relation'
    # La représentation du CHAMP reste réservée aux non-relations (la
    # représentation d'une relation est relReprFormula).
    assert reprSectionEl.classList.contains('hidden'), 'la section repr du champ est masquée pour une Relation'

  it 'affiche la cible et masque le not_null', ->
    app = makeApp()
    app.el.fieldType().value = 'Relation'
    H.onFieldTypeChange app
    assert !app.el.relTargetRow().classList.contains('hidden'), 'cible visible'
    assert notNullLabelEl.classList.contains('hidden'), 'not_null masqué pour une relation'

# ---------------------------------------------------------------------------
describe 'startEditField — relation calculée', ->
  it 'affiche la formule du champ relation', ->
    app = makeApp()
    field =
      id: 'f1', name: 'classe_actuelle', fieldType: 'Int'
      formula: 'self.classe_id', language: 'moonscript', triggerFields: null
    H.startEditField app, field, { id: 'r1', toSpaceId: 'tgt1', reprFormula: '@nom' }
    eq app.el.fieldType().value, 'Relation'
    eq app.el.fieldFormula().value, 'self.classe_id'
    eq app.el.formulaLanguage().value, 'moonscript'
    eq app.el.relReprFormula().value, '@nom'
    assert radios.formula.checked, 'le radio « Colonne calculée » doit être sélectionné'
    assert !formulaBodyEl.classList.contains('hidden'), 'le corps de formule doit être visible'

  it 'relation sans formule : radio « Aucune formule »', ->
    app = makeApp()
    field = { id: 'f2', name: 'classe_fixe', fieldType: 'Int', formula: '', triggerFields: null }
    H.startEditField app, field, { id: 'r2', toSpaceId: 'tgt1', reprFormula: '@nom' }
    eq app.el.fieldFormula().value, ''
    assert radios.none.checked, 'aucune formule'
    assert formulaBodyEl.classList.contains('hidden'), 'corps de formule masqué'

  it 'relation avec trigger formula : affiche la liste des déclencheurs', ->
    app = makeApp()
    field =
      id: 'f3', name: 'cle', fieldType: 'Int'
      formula: 'self.classe_id', language: 'lua', triggerFields: ['classe_id']
    H.startEditField app, field, { id: 'r3', toSpaceId: 'tgt1', reprFormula: '@nom' }
    eq app.el.fieldFormula().value, 'self.classe_id'
    eq app.el.fieldTriggerFields().value, 'classe_id'
    assert radios.trigger.checked, 'trigger sélectionné'
    assert !app.el.triggerFieldsRow().classList.contains('hidden'), 'ligne déclencheurs visible'

# ---------------------------------------------------------------------------
describe 'handleFieldSubmit — nouveau champ Relation calculé', ->
  it 'transmet la formule au champ Int', ->
    app = makeApp { _currentSpace: { id: 'src_add_computed', name: 'pers', fields: [] } }
    app.el.fieldName().value = 'classe_actuelle'
    app.el.fieldType().value = 'Relation'
    app.el.relToSpace().value = 'tgt1'
    app.el.relReprFormula().value = '@nom'
    app.el.fieldFormula().value = ' self.classe_id '
    app.el.formulaLanguage().value = 'moonscript'
    selectRadio 'formula'

    H.handleFieldSubmit app
    await flush()

    added   = calls.find (c) -> c.kind == 'addField' and c.spaceId == 'src_add_computed'
    created = calls.find (c) -> c.kind == 'createRelation' and c.fromSpaceId == 'src_add_computed'
    assert added?, 'addField must be called'
    eq added.fieldType, 'Int'
    eq added.formula, 'self.classe_id'
    eq added.language, 'moonscript'
    eq added.triggerFields, null
    assert created?, 'createRelation must be called'
    eq created.reprFormula, '@nom'

  it 'sans formule : aucun champ calculé', ->
    app = makeApp { _currentSpace: { id: 'src_add_plain', name: 'pers', fields: [] } }
    app.el.fieldName().value = 'classe_fixe'
    app.el.fieldType().value = 'Relation'
    app.el.relToSpace().value = 'tgt1'
    app.el.relReprFormula().value = '@nom'
    selectRadio 'none'

    H.handleFieldSubmit app
    await flush()

    added = calls.find (c) -> c.kind == 'addField' and c.spaceId == 'src_add_plain'
    assert added?, 'addField must be called'
    eq added.formula, null

# ---------------------------------------------------------------------------
describe 'handleFieldSubmit — changement de type vers Relation', ->
  it 'enregistre la formule sur le champ sans la traiter comme conversion', ->
    app = makeApp {
      _currentSpace: {
        id: 'src_convert', name: 'pers'
        fields: [{ id: 'f_convert', name: 'classe_actuelle', fieldType: 'String' }]
      }
      _editingFieldId: 'f_convert'
    }
    app.el.fieldName().value = 'classe_actuelle'
    app.el.fieldType().value = 'Relation'
    app.el.relToSpace().value = 'tgt1'
    app.el.relReprFormula().value = '@nom'
    app.el.fieldFormula().value = 'self.classe_id'
    app.el.formulaLanguage().value = 'moonscript'
    app.el.fieldReprFormula().value = ''
    selectRadio 'formula'

    H.handleFieldSubmit app
    await flush()
    await flush()

    changed = calls.find (c) -> c.kind == 'changeFieldType' and c.fieldId == 'f_convert'
    created = calls.find (c) -> c.kind == 'createRelation' and c.fromFieldId == 'f_convert'
    updated = calls.find (c) -> c.kind == 'updateField' and c.fieldId == 'f_convert'
    assert changed?, 'changeFieldType must be called'
    eq changed.fieldType, 'Relation'
    eq changed.conversionFormula, null, 'la formule de lecture n est pas une conversion'
    assert created?, 'createRelation must be called'
    assert updated?, 'la formule doit être enregistrée sur le champ'
    eq updated.opts.formula, 'self.classe_id'
    eq updated.opts.language, 'moonscript'

# ---------------------------------------------------------------------------
describe 'source — onFieldTypeChange ne masque plus la formule', ->
  it 'aucun toggle hidden sur .formula-section', ->
    fs = require 'fs'
    path = require 'path'
    src = fs.readFileSync path.resolve(__dirname, '../../frontend/src/app_fields_helpers.coffee'), 'utf8'
    assert not /formulaSection\?\.classList\.toggle 'hidden', isRelation/.test(src), 'le masquage de la section formule doit avoir disparu'
    assert /applyFieldFormulaState app, field/.test(src), 'la formule doit être affichée pour une relation'

summary()
