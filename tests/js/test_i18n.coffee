# tests/js/test_i18n.coffee — tests du runtime i18n minimal

{ localStorageStub } = require './dom_stub'
{ describe, it, eq, assert, summary } = require './runner'

localStorageStub.clear()
global.navigator.language = 'en-US'
global.window.dispatchEvent = -> null
global.CustomEvent = (name, opts = {}) -> { name, detail: opts.detail }
global.document.documentElement = {}

require '../../frontend/src/i18n'
I18N = global.window.I18N

describe 'I18N.init', ->
  it 'prend la locale stockée si disponible', ->
    localStorageStub.clear()
    localStorageStub.setItem 'tgui_locale', 'en'
    I18N.init()
    eq I18N.getLocale(), 'en'

describe 'I18N.t', ->
  it 'retourne une traduction dans la locale active', ->
    I18N.setLocale 'en'
    eq I18N.t('common.cancel'), 'Cancel'

  it 'retourne la traduction anglaise quand disponible', ->
    I18N.setLocale 'en'
    eq I18N.t('ui.snapshot.sectionSpacesDelete'), '⚠ Spaces to delete (data loss)'

  it 'interpole les variables', ->
    I18N.setLocale 'fr'
    msg = I18N.t 'ui.prompts.newPasswordFor', { username: 'alice' }
    assert msg.includes('alice'), 'interpolation manquante'

describe 'I18N.setLocale', ->
  it 'persiste la locale dans localStorage', ->
    I18N.setLocale 'fr'
    eq localStorageStub.getItem('tgui_locale'), 'fr'

summary()
