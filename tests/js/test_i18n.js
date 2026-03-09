(function() {
  // tests/js/test_i18n.coffee — tests du runtime i18n minimal
  var I18N, assert, describe, eq, it, localStorageStub, summary;

  ({localStorageStub} = require('./dom_stub'));

  ({describe, it, eq, assert, summary} = require('./runner'));

  localStorageStub.clear();

  global.navigator.language = 'en-US';

  global.window.dispatchEvent = function() {
    return null;
  };

  global.CustomEvent = function(name, opts = {}) {
    return {
      name,
      detail: opts.detail
    };
  };

  global.document.documentElement = {};

  require('../../frontend/src/i18n');

  I18N = global.window.I18N;

  describe('I18N.init', function() {
    return it('prend la locale stockée si disponible', function() {
      localStorageStub.clear();
      localStorageStub.setItem('tgui_locale', 'en');
      I18N.init();
      return eq(I18N.getLocale(), 'en');
    });
  });

  describe('I18N.t', function() {
    it('retourne une traduction dans la locale active', function() {
      I18N.setLocale('en');
      return eq(I18N.t('common.cancel'), 'Cancel');
    });
    it('retourne la traduction anglaise quand disponible', function() {
      I18N.setLocale('en');
      return eq(I18N.t('ui.snapshot.sectionSpacesDelete'), '⚠ Spaces to delete (data loss)');
    });
    return it('interpole les variables', function() {
      var msg;
      I18N.setLocale('fr');
      msg = I18N.t('ui.prompts.newPasswordFor', {
        username: 'alice'
      });
      return assert(msg.includes('alice'), 'interpolation manquante');
    });
  });

  describe('I18N.setLocale', function() {
    return it('persiste la locale dans localStorage', function() {
      I18N.setLocale('fr');
      return eq(localStorageStub.getItem('tgui_locale'), 'fr');
    });
  });

  summary();

}).call(this);
