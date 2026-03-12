(function() {
  // tests/js/test_spaces.coffee — tests for Spaces (spaces.js)
  // Strategy: stub GQL to capture calls and verify mutation shapes.
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

  // Load module under test
  require('../../frontend/src/spaces');

  S = global.window.Spaces;

  // --- helpers ----------------------------------------------------------------
  capture = function() {
    lastCall = null;
    return lastCall;
  };

  // ---------------------------------------------------------------------------
  describe('Spaces.list', function() {
    return it('emits a GQL query without variables', function() {
      S.list();
      assert(lastCall.type === 'query', 'must be a query');
      return assert(lastCall.q.includes('spaces'), 'query must mention spaces');
    });
  });

  describe('Spaces.create', function() {
    it('emits a mutation with name and description', function() {
      S.create('test_space', 'a description');
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.input.name, 'test_space');
      return eq(lastCall.vars.input.description, 'a description');
    });
    return it('empty default description', function() {
      S.create('sans_desc');
      return eq(lastCall.vars.input.description, '');
    });
  });

  describe('Spaces.update', function() {
    return it('emits a mutation with id and input', function() {
      S.update('42', 'new', 'desc');
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.id, '42');
      return eq(lastCall.vars.input.name, 'new');
    });
  });

  describe('Spaces.delete', function() {
    return it('emits a mutation with id', function() {
      S.delete('7');
      eq(lastCall.type, 'mutate');
      return eq(lastCall.vars.id, '7');
    });
  });

  describe('Spaces.addField', function() {
    return it('passes spaceId and input', function() {
      S.addField('3', 'age', 'Int', false);
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.spaceId, '3');
      eq(lastCall.vars.input.name, 'age');
      return eq(lastCall.vars.input.fieldType, 'Int');
    });
  });

  describe('Spaces.updateField', function() {
    return it('passes fieldId and input', function() {
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
    return it('passes all required fields', function() {
      S.createRelation('rel', '1', '2', '3', '4');
      eq(lastCall.type, 'mutate');
      eq(lastCall.vars.input.name, 'rel');
      eq(lastCall.vars.input.fromSpaceId, '1');
      return eq(lastCall.vars.input.toSpaceId, '3');
    });
  });

  describe('Spaces.deleteRelation', function() {
    return it('passes id', function() {
      S.deleteRelation('55');
      return eq(lastCall.vars.id, '55');
    });
  });

  summary();

}).call(this);
