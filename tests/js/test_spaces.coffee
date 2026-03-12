# tests/js/test_spaces.coffee — tests for Spaces (spaces.js)
# Strategy: stub GQL to capture calls and verify mutation shapes.

require './dom_stub'
{ describe, it, eq, deepEq, assert, summary } = require './runner'

# --- stub GQL ---------------------------------------------------------------
lastCall = null
global.GQL =
  query:  (q, vars) -> lastCall = { type: 'query',  q, vars }; Promise.resolve {}
  mutate: (q, vars) -> lastCall = { type: 'mutate', q, vars }; Promise.resolve {}

# Load module under test
require '../../frontend/src/spaces'
S = global.window.Spaces

# --- helpers ----------------------------------------------------------------
capture = ->
  lastCall = null
  lastCall

# ---------------------------------------------------------------------------
describe 'Spaces.list', ->
  it 'emits a GQL query without variables', ->
    S.list()
    assert lastCall.type is 'query', 'must be a query'
    assert lastCall.q.includes('spaces'), 'query must mention spaces'

describe 'Spaces.create', ->
  it 'emits a mutation with name and description', ->
    S.create 'test_space', 'a description'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.input.name, 'test_space'
    eq lastCall.vars.input.description, 'a description'

  it 'empty default description', ->
    S.create 'sans_desc'
    eq lastCall.vars.input.description, ''

describe 'Spaces.update', ->
  it 'emits a mutation with id and input', ->
    S.update '42', 'new', 'desc'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.id, '42'
    eq lastCall.vars.input.name, 'new'

describe 'Spaces.delete', ->
  it 'emits a mutation with id', ->
    S.delete '7'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.id, '7'

describe 'Spaces.addField', ->
  it 'passes spaceId and input', ->
    S.addField '3', 'age', 'Int', false
    eq lastCall.type, 'mutate'
    eq lastCall.vars.spaceId, '3'
    eq lastCall.vars.input.name, 'age'
    eq lastCall.vars.input.fieldType, 'Int'

describe 'Spaces.updateField', ->
  it 'passes fieldId and input', ->
    S.updateField '99', { formula: 'x + 1', language: 'moonscript' }
    eq lastCall.type, 'mutate'
    eq lastCall.vars.fieldId, '99'
    eq lastCall.vars.input.formula, 'x + 1'

describe 'Spaces.createRelation', ->
  it 'passes all required fields', ->
    S.createRelation 'rel', '1', '2', '3', '4'
    eq lastCall.type, 'mutate'
    eq lastCall.vars.input.name, 'rel'
    eq lastCall.vars.input.fromSpaceId, '1'
    eq lastCall.vars.input.toSpaceId, '3'

describe 'Spaces.deleteRelation', ->
  it 'passes id', ->
    S.deleteRelation '55'
    eq lastCall.vars.id, '55'

summary()
