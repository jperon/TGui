(function() {
  // tests/js/test_spaces.coffee — tests pour Spaces (spaces.js)
  // Stratégie : stub GQL pour capturer les appels et vérifier la structure des mutations.
  var S, assert, capture, deepEq, describe, eq, it, lastCall, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  // --- stub GQL ---------------------------------------------------------------
  lastCall = null;

  global.GQL = {
    query: function(q, vars) {
      lastCall = {
        type: 'query',
        q,
        vars
      };
      return Promise.resolve({});
    },
    mutate: function(q, vars) {
      lastCall = {
        type: 'mutate',
        q,
        vars
      };
      return Promise.resolve({});
    }
  };

  // Chargement du module sous test
  require('../../frontend/src/spaces');

  S = global.window.Spaces;

  // --- helpers ----------------------------------------------------------------
  capture = function() {
    lastCall = null;
    return lastCall;
  };

  // ---------------------------------------------------------------------------
  describe('Spaces.list', function() {
    return it('émet une query GQL sans variables', function() {
      S.list();
      assert(lastCall.type === 'query', 'doit être une query');
      return assert(lastCall.q.includes('spaces'), 'query doit mentionner spaces');
    });
  });

  describe('Spaces.create', function() {
    it('émet une mutation avec name et description', function() {
      S.create('test_space', 'une description');
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.input.name, 'test_space');
      return eq(lastCall.vars.input.description, 'une description');
    });
    return it('description vide par défaut', function() {
      S.create('sans_desc');
      return eq(lastCall.vars.input.description, '');
    });
  });

  describe('Spaces.update', function() {
    return it('émet une mutation avec id et input', function() {
      S.update('42', 'nouveau', 'desc');
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.id, '42');
      return eq(lastCall.vars.input.name, 'nouveau');
    });
  });

  describe('Spaces.delete', function() {
    return it('émet une mutation avec id', function() {
      S.delete('7');
      eq(lastCall.type, 'mutate');
      return eq(lastCall.vars.id, '7');
    });
  });

  describe('Spaces.addField', function() {
    return it('passe spaceId et input', function() {
      S.addField('3', 'age', 'Int', false);
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.spaceId, '3');
      eq(lastCall.vars.input.name, 'age');
      return eq(lastCall.vars.input.fieldType, 'Int');
    });
  });

  describe('Spaces.updateField', function() {
    return it('passe fieldId et input', function() {
      S.updateField('99', {
        formula: 'x + 1',
        language: 'moonscript'
      });
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.fieldId, '99');
      return eq(lastCall.vars.input.formula, 'x + 1');
    });
  });

  describe('Spaces.createRelation', function() {
    return it('passe tous les champs requis', function() {
      S.createRelation('rel', '1', '2', '3', '4');
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.input.name, 'rel');
      eq(lastCall.vars.input.fromSpaceId, '1');
      return eq(lastCall.vars.input.toSpaceId, '3');
    });
  });

  describe('Spaces.deleteRelation', function() {
    return it('passe l\'id', function() {
      S.deleteRelation('55');
      return eq(lastCall.vars.id, '55');
    });
  });

  summary();

}).call(this);
