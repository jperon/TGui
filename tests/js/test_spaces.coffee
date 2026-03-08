# tests/js/test_spaces.coffee — tests pour Spaces (spaces.js)
# Stratégie : stub GQL pour capturer les appels et vérifier la structure des mutations.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# --- stub GQL ---------------------------------------------------------------
lastCall = null
global.GQL =
  query:  (q, vars) -> lastCall = { type: 'query',  q, vars }; Promise.resolve {}
  mutate: (q, vars) -> lastCall = { type: 'mutate', q, vars }; Promise.resolve {}

# Chargement du module sous test
require '../../frontend/src/spaces'
S = global.window.Spaces

# --- helpers ----------------------------------------------------------------
capture = ->
  lastCall = null
  lastCall

# ---------------------------------------------------------------------------
describe 'Spaces.list', ->
  it 'émet une query GQL sans variables', ->
    S.list()
    assert lastCall.type is 'query', 'doit être une query'
    assert lastCall.q.includes('spaces'), 'query doit mentionner spaces'

describe 'Spaces.create', ->
  it 'émet une mutation avec name et description', ->
    S.create 'test_space', 'une description'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.input.name, 'test_space'
    eq lastCall.vars.input.description, 'une description'

  it 'description vide par défaut', ->
    S.create 'sans_desc'
    eq lastCall.vars.input.description, ''

describe 'Spaces.update', ->
  it 'émet une mutation avec id et input', ->
    S.update '42', 'nouveau', 'desc'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.id, '42'
    eq lastCall.vars.input.name, 'nouveau'

describe 'Spaces.delete', ->
  it 'émet une mutation avec id', ->
    S.delete '7'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.id, '7'

describe 'Spaces.addField', ->
  it 'passe spaceId et input', ->
    S.addField '3', 'age', 'Int', false
    eq lastCall.type, 'mutate'
    eq lastCall.vars.spaceId, '3'
    eq lastCall.vars.input.name, 'age'
    eq lastCall.vars.input.fieldType, 'Int'

describe 'Spaces.updateField', ->
  it 'passe fieldId et input', ->
    S.updateField '99', { formula: 'x + 1', language: 'moonscript' }
    eq lastCall.type, 'mutate'
    eq lastCall.vars.fieldId, '99'
    eq lastCall.vars.input.formula, 'x + 1'

describe 'Spaces.createRelation', ->
  it 'passe tous les champs requis', ->
    S.createRelation 'rel', '1', '2', '3', '4'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.input.name, 'rel'
    eq lastCall.vars.input.fromSpaceId, '1'
    eq lastCall.vars.input.toSpaceId, '3'

describe 'Spaces.deleteRelation', ->
  it 'passe l\'id', ->
    S.deleteRelation '55'
    eq lastCall.vars.id, '55'

summary()
