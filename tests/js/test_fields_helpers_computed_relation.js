(function() {
  // tests/js/test_fields_helpers_computed_relation.coffee
  // A relation may be declared on a COMPUTED field (read-time formula returning
  // the target id). The fields panel must then:
  //   - keep the formula section visible when the type is Relation;
  //   - show the formula of an existing computed relation when editing it;
  //   - transmit the typed formula when creating a Relation field (or when
  //     changing a field's type to Relation).

  // The runner starts every it() immediately (async tests overlap), so all tests
  // share ONE Spaces stub recording into `calls`: each test uses unique ids and
  // filters its own entries instead of relying on per-test stubs.
  var H, assert, calls, describe, eq, flush, formulaBodyEl, formulaSectionEl, it, makeApp, makeElement, notNullLabelEl, radio, radios, reprSectionEl, selectRadio, summary, targetSpace,
    hasProp = {}.hasOwnProperty;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  ({makeElement} = require('./dom_stub'));

  require('../../frontend/src/app_fields_helpers');

  H = global.window.AppFieldsHelpers;

  // --- element stubs ----------------------------------------------------------
  formulaSectionEl = makeElement('div');

  formulaBodyEl = makeElement('div');

  reprSectionEl = makeElement('div');

  notNullLabelEl = makeElement('label');

  // makeElement has no closest(): attach one so hiding the formula section would
  // be observable (today it must not happen for a Relation).
  formulaBodyEl.closest = function(sel) {
    if (sel === '.formula-section') {
      return formulaSectionEl;
    } else {
      return null;
    }
  };

  radio = function(value) {
    return {
      value: value,
      checked: false
    };
  };

  radios = {
    none: radio('none'),
    formula: radio('formula'),
    trigger: radio('trigger')
  };

  document.querySelector = function(sel) {
    var k, m, r, ref;
    if (sel === 'input[name="formula-type"]:checked') {
      for (k in radios) {
        if (!hasProp.call(radios, k)) continue;
        r = radios[k];
        if (r.checked) {
          return r;
        }
      }
      return radios.none;
    }
    m = sel.match(/input\[name="formula-type"\]\[value="(\w+)"\]/);
    if (m) {
      return (ref = radios[m[1]]) != null ? ref : null;
    }
    return null;
  };

  document.getElementById = function(id) {
    if (id === 'field-repr-section') {
      return reprSectionEl;
    }
    return null;
  };

  selectRadio = function(name) {
    var k, r;
    for (k in radios) {
      if (!hasProp.call(radios, k)) continue;
      r = radios[k];
      r.checked = false;
    }
    return radios[name].checked = true;
  };

  makeApp = function(overrides = {}) {
    var app, els, k, v;
    els = {
      fieldType: makeElement('select'),
      relTargetRow: makeElement('div'),
      relReprRow: makeElement('div'),
      relToSpace: makeElement('select'),
      relReprFormula: makeElement('input'),
      fieldNotNull: makeElement('input'),
      fieldName: makeElement('input'),
      fieldFormula: makeElement('textarea'),
      formulaLanguage: makeElement('select'),
      formulaBody: makeElement('div'),
      triggerFieldsRow: makeElement('div'),
      fieldTriggerFields: makeElement('input'),
      fieldReprFormula: makeElement('input'),
      fieldAddBtn: makeElement('button'),
      fieldCancelBtn: makeElement('button')
    };
    els.fieldName.focus = function() {};
    els.fieldFormula.value = '';
    els.formulaLanguage.value = 'lua';
    els.formulaBody = formulaBodyEl;
    els.fieldNotNull.closest = function(sel) {
      if (sel === 'label') {
        return notNullLabelEl;
      } else {
        return null;
      }
    };
    app = {
      el: {},
      _allSpaces: [
        {
          id: 'tgt1',
          name: 'classes'
        }
      ],
      _t: function(k) {
        return k;
      },
      _err: function(e) {
        return String(e);
      },
      _editingFieldId: null,
      _editingRelation: null,
      _currentSpace: {
        id: 'src1',
        name: 'pers',
        fields: []
      },
      _onFieldTypeChange: function() {
        return H.onFieldTypeChange(app);
      },
      updateFieldProperties: function(fieldId, opts, formulaType) {
        return H.updateFieldProperties(app, fieldId, opts, formulaType);
      },
      _resetFieldForm: function() {},
      _syncSpaceFields: function() {},
      renderFieldsList: function() {},
      _mountDataView: function() {}
    };
    for (k in els) {
      if (!hasProp.call(els, k)) continue;
      v = els[k];
      app.el[k] = (function(v) {
        return function() {
          return v;
        };
      })(v);
    }
    for (k in overrides) {
      if (!hasProp.call(overrides, k)) continue;
      v = overrides[k];
      app[k] = v;
    }
    return app;
  };

  // --- Spaces stub ------------------------------------------------------------
  calls = [];

  targetSpace = {
    id: 'tgt1',
    name: 'classes',
    fields: [
      {
        id: 'idf',
        fieldType: 'Sequence'
      }
    ]
  };

  global.Spaces = {
    getWithFields: function(id) {
      calls.push({
        kind: 'getWithFields',
        id
      });
      return Promise.resolve(targetSpace);
    },
    addField: function(spaceId, name, type, notNull, desc, formula, triggerFields, language) {
      calls.push({
        kind: 'addField',
        spaceId,
        name,
        fieldType: type,
        formula,
        triggerFields,
        language
      });
      return Promise.resolve({
        id: `new_${spaceId}`
      });
    },
    createRelation: function(name, fromSpaceId, fromFieldId, toSpaceId, toFieldId, reprFormula) {
      calls.push({
        kind: 'createRelation',
        name,
        fromSpaceId,
        fromFieldId,
        toSpaceId,
        reprFormula
      });
      return Promise.resolve({
        id: 'rel1'
      });
    },
    changeFieldType: function(fieldId, fieldType, conversionFormula, language) {
      calls.push({
        kind: 'changeFieldType',
        fieldId,
        fieldType,
        conversionFormula,
        language
      });
      return Promise.resolve({
        id: fieldId,
        fieldType
      });
    },
    updateField: function(fieldId, opts) {
      calls.push({
        kind: 'updateField',
        fieldId,
        opts
      });
      return Promise.resolve({
        id: fieldId
      });
    },
    updateRelation: function(id, reprFormula) {
      calls.push({
        kind: 'updateRelation',
        id,
        reprFormula
      });
      return Promise.resolve({id});
    }
  };

  global.tdbAlert = function() {};

  flush = function() {
    return new Promise(function(resolve) {
      return setImmediate(resolve);
    });
  };

  // ---------------------------------------------------------------------------
  describe('onFieldTypeChange — Relation garde la section formule', function() {
    it('ne masque pas la section formule', function() {
      var app;
      app = makeApp();
      app.el.fieldType().value = 'Relation';
      formulaSectionEl.classList.remove('hidden');
      H.onFieldTypeChange(app);
      assert(!formulaSectionEl.classList.contains('hidden'), 'formula-section ne doit pas être masquée pour une Relation');
      // La représentation du CHAMP reste réservée aux non-relations (la
      // représentation d'une relation est relReprFormula).
      return assert(reprSectionEl.classList.contains('hidden'), 'la section repr du champ est masquée pour une Relation');
    });
    return it('affiche la cible et masque le not_null', function() {
      var app;
      app = makeApp();
      app.el.fieldType().value = 'Relation';
      H.onFieldTypeChange(app);
      assert(!app.el.relTargetRow().classList.contains('hidden'), 'cible visible');
      return assert(notNullLabelEl.classList.contains('hidden'), 'not_null masqué pour une relation');
    });
  });

  // ---------------------------------------------------------------------------
  describe('startEditField — relation calculée', function() {
    it('affiche la formule du champ relation', function() {
      var app, field;
      app = makeApp();
      field = {
        id: 'f1',
        name: 'classe_actuelle',
        fieldType: 'Int',
        formula: 'self.classe_id',
        language: 'moonscript',
        triggerFields: null
      };
      H.startEditField(app, field, {
        id: 'r1',
        toSpaceId: 'tgt1',
        reprFormula: '@nom'
      });
      eq(app.el.fieldType().value, 'Relation');
      eq(app.el.fieldFormula().value, 'self.classe_id');
      eq(app.el.formulaLanguage().value, 'moonscript');
      eq(app.el.relReprFormula().value, '@nom');
      assert(radios.formula.checked, 'le radio « Colonne calculée » doit être sélectionné');
      return assert(!formulaBodyEl.classList.contains('hidden'), 'le corps de formule doit être visible');
    });
    it('relation sans formule : radio « Aucune formule »', function() {
      var app, field;
      app = makeApp();
      field = {
        id: 'f2',
        name: 'classe_fixe',
        fieldType: 'Int',
        formula: '',
        triggerFields: null
      };
      H.startEditField(app, field, {
        id: 'r2',
        toSpaceId: 'tgt1',
        reprFormula: '@nom'
      });
      eq(app.el.fieldFormula().value, '');
      assert(radios.none.checked, 'aucune formule');
      return assert(formulaBodyEl.classList.contains('hidden'), 'corps de formule masqué');
    });
    return it('relation avec trigger formula : affiche la liste des déclencheurs', function() {
      var app, field;
      app = makeApp();
      field = {
        id: 'f3',
        name: 'cle',
        fieldType: 'Int',
        formula: 'self.classe_id',
        language: 'lua',
        triggerFields: ['classe_id']
      };
      H.startEditField(app, field, {
        id: 'r3',
        toSpaceId: 'tgt1',
        reprFormula: '@nom'
      });
      eq(app.el.fieldFormula().value, 'self.classe_id');
      eq(app.el.fieldTriggerFields().value, 'classe_id');
      assert(radios.trigger.checked, 'trigger sélectionné');
      return assert(!app.el.triggerFieldsRow().classList.contains('hidden'), 'ligne déclencheurs visible');
    });
  });

  // ---------------------------------------------------------------------------
  describe('handleFieldSubmit — nouveau champ Relation calculé', function() {
    it('transmet la formule au champ Int', async function() {
      var added, app, created;
      app = makeApp({
        _currentSpace: {
          id: 'src_add_computed',
          name: 'pers',
          fields: []
        }
      });
      app.el.fieldName().value = 'classe_actuelle';
      app.el.fieldType().value = 'Relation';
      app.el.relToSpace().value = 'tgt1';
      app.el.relReprFormula().value = '@nom';
      app.el.fieldFormula().value = ' self.classe_id ';
      app.el.formulaLanguage().value = 'moonscript';
      selectRadio('formula');
      H.handleFieldSubmit(app);
      await flush();
      added = calls.find(function(c) {
        return c.kind === 'addField' && c.spaceId === 'src_add_computed';
      });
      created = calls.find(function(c) {
        return c.kind === 'createRelation' && c.fromSpaceId === 'src_add_computed';
      });
      assert(added != null, 'addField must be called');
      eq(added.fieldType, 'Int');
      eq(added.formula, 'self.classe_id');
      eq(added.language, 'moonscript');
      eq(added.triggerFields, null);
      assert(created != null, 'createRelation must be called');
      return eq(created.reprFormula, '@nom');
    });
    return it('sans formule : aucun champ calculé', async function() {
      var added, app;
      app = makeApp({
        _currentSpace: {
          id: 'src_add_plain',
          name: 'pers',
          fields: []
        }
      });
      app.el.fieldName().value = 'classe_fixe';
      app.el.fieldType().value = 'Relation';
      app.el.relToSpace().value = 'tgt1';
      app.el.relReprFormula().value = '@nom';
      selectRadio('none');
      H.handleFieldSubmit(app);
      await flush();
      added = calls.find(function(c) {
        return c.kind === 'addField' && c.spaceId === 'src_add_plain';
      });
      assert(added != null, 'addField must be called');
      return eq(added.formula, null);
    });
  });

  // ---------------------------------------------------------------------------
  describe('handleFieldSubmit — changement de type vers Relation', function() {
    return it('enregistre la formule sur le champ sans la traiter comme conversion', async function() {
      var app, changed, created, updated;
      app = makeApp({
        _currentSpace: {
          id: 'src_convert',
          name: 'pers',
          fields: [
            {
              id: 'f_convert',
              name: 'classe_actuelle',
              fieldType: 'String'
            }
          ]
        },
        _editingFieldId: 'f_convert'
      });
      app.el.fieldName().value = 'classe_actuelle';
      app.el.fieldType().value = 'Relation';
      app.el.relToSpace().value = 'tgt1';
      app.el.relReprFormula().value = '@nom';
      app.el.fieldFormula().value = 'self.classe_id';
      app.el.formulaLanguage().value = 'moonscript';
      app.el.fieldReprFormula().value = '';
      selectRadio('formula');
      H.handleFieldSubmit(app);
      await flush();
      await flush();
      changed = calls.find(function(c) {
        return c.kind === 'changeFieldType' && c.fieldId === 'f_convert';
      });
      created = calls.find(function(c) {
        return c.kind === 'createRelation' && c.fromFieldId === 'f_convert';
      });
      updated = calls.find(function(c) {
        return c.kind === 'updateField' && c.fieldId === 'f_convert';
      });
      assert(changed != null, 'changeFieldType must be called');
      eq(changed.fieldType, 'Relation');
      eq(changed.conversionFormula, null, 'la formule de lecture n est pas une conversion');
      assert(created != null, 'createRelation must be called');
      assert(updated != null, 'la formule doit être enregistrée sur le champ');
      eq(updated.opts.formula, 'self.classe_id');
      return eq(updated.opts.language, 'moonscript');
    });
  });

  // ---------------------------------------------------------------------------
  describe('source — onFieldTypeChange ne masque plus la formule', function() {
    return it('aucun toggle hidden sur .formula-section', function() {
      var fs, path, src;
      fs = require('fs');
      path = require('path');
      src = fs.readFileSync(path.resolve(__dirname, '../../frontend/src/app_fields_helpers.coffee'), 'utf8');
      assert(!/formulaSection\?\.classList\.toggle 'hidden', isRelation/.test(src), 'le masquage de la section formule doit avoir disparu');
      return assert(/applyFieldFormulaState app, field/.test(src), 'la formule doit être affichée pour une relation');
    });
  });

  summary();

}).call(this);
