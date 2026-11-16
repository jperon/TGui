(function() {
  // tests/js/test_add_widget_manifest_form.coffee
  // Fenêtre « ＋ Widget » : quand le widget personnalisé choisi déclare un
  // manifest, les paires clé/valeur sont remplacées par un formulaire (un
  // sélecteur de champ par colonne déclarée, un champ par option), et la
  // validation exige les colonnes obligatoires. Sans manifest : paires comme
  // avant. Spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §3 bis.
  var AVH, FIELDS, MANIFEST, assert, describe, document, eq, it, makeStub, setForm, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  global.window.AppViewHelpers = {};

  global.window.Auth = null;

  global.window.jsyaml = {
    load: function(text) {
      var trimmed;
      trimmed = String(text || '').trim();
      if (trimmed === '' || trimmed.indexOf('#') === 0) {
        return void 0;
      }
      return JSON.parse(trimmed);
    }
  };

  require('../../frontend/src/app_view_helpers_add_widget');

  AVH = global.window.AppViewHelpers;

  document = global.document;

  MANIFEST = {
    columns: [
      {
        name: 'titre',
        type: 'String'
      },
      {
        name: 'debut',
        type: 'Date'
      },
      {
        name: 'fin',
        type: 'Date',
        optional: true
      }
    ],
    options: [
      {
        name: 'couleur',
        type: 'color',
        default: '#36c'
      },
      {
        name: 'taille',
        type: 'number',
        default: 12
      },
      {
        name: 'compact',
        type: 'boolean',
        default: true
      },
      {
        name: 'libelle',
        type: 'text',
        default: 'Calendrier'
      }
    ]
  };

  FIELDS = [
    {
      name: 'nom',
      fieldType: 'String'
    },
    {
      name: 'date_debut',
      fieldType: 'Datetime'
    },
    {
      name: 'date_fin',
      fieldType: 'Datetime'
    },
    {
      name: 'compteur',
      fieldType: 'Int'
    },
    {
      name: 'uuid_ref',
      fieldType: 'UUID'
    },
    {
      name: 'booleen',
      fieldType: 'Boolean'
    }
  ];

  // Formulaire minimal rendu dans le DOM stub : les conteneurs et l'identifiant
  // de source que le code lit par getElementById.
  makeStub = function(tag, id, value = null) {
    var el;
    el = document.createElement(tag);
    if (value != null) {
      el.value = value;
    }
    document._setById(id, el);
    return el;
  };

  setForm = function(columns, options) {
    makeStub('input', 'widget-title-input', 'Mon widget');
    makeStub('select', 'widget-space-select', 'space-uuid');
    makeStub('div', 'widget-params-pairs');
    makeStub('div', 'widget-manifest-form');
    makeStub('div', 'widget-manifest-hint');
    document.querySelectorAll = function(sel) {
      if (sel === '#widget-manifest-form .manifest-column-select') {
        return columns || [];
      }
      if (sel === '#widget-manifest-form [data-option]') {
        return options || [];
      }
      if (sel === '#selected-fields .field-item') {
        return [];
      }
      return [];
    };
    document.querySelector = function(sel) {
      if (sel === 'input[name="widget-type"]:checked') {
        return {
          value: 'calendrier'
        };
      } else {
        return null;
      }
    };
  };

  global.window._currentSpacesData = [
    {
      id: 'space-uuid',
      name: 'evenements',
      fields: FIELDS
    }
  ];

  global.window._currentDataViewsData = [];

  describe('Fenêtre « ＋ Widget » — analyse du manifest', function() {
    it('sans manifest (ou commentaires seuls) : null', function() {
      eq(AVH._parseWidgetManifest(null), null);
      eq(AVH._parseWidgetManifest(''), null);
      return eq(AVH._parseWidgetManifest('# commentaire'), null);
    });
    it('retient columns et options, et access', function() {
      var parsed;
      parsed = AVH._parseWidgetManifest(JSON.stringify({
        access: 'read',
        columns: MANIFEST.columns,
        options: []
      }));
      eq(parsed.access, 'read');
      eq(parsed.columns.length, 3);
      return eq(parsed.options.length, 0);
    });
    return it('manifest illisible : null (paires clé/valeur, comme avant)', function() {
      return eq(AVH._parseWidgetManifest('{oops'), null);
    });
  });

  describe('Fenêtre « ＋ Widget » — compatibilité des types', function() {
    it('Date accepte Datetime, refuse String', function() {
      eq(AVH._manifestFieldCompatible('Date', {
        fieldType: 'Datetime'
      }), true);
      return eq(AVH._manifestFieldCompatible('Date', {
        fieldType: 'String'
      }), false);
    });
    it('nombre accepte Int et Float, String accepte ID/UUID', function() {
      eq(AVH._manifestFieldCompatible('Int', {
        fieldType: 'Float'
      }), true);
      eq(AVH._manifestFieldCompatible('String', {
        fieldType: 'UUID'
      }), true);
      return eq(AVH._manifestFieldCompatible('String', {
        fieldType: 'Int'
      }), false);
    });
    return it('Any (déclaré ou champ) accepte tout', function() {
      eq(AVH._manifestFieldCompatible('Any', {
        fieldType: 'Int'
      }), true);
      return eq(AVH._manifestFieldCompatible('Boolean', {
        fieldType: 'Any'
      }), true);
    });
  });

  describe('Fenêtre « ＋ Widget » — rendu du formulaire', function() {
    it('une ligne par colonne : sélecteur « — » + champs compatibles', function() {
      var label, o, row, select, values;
      row = AVH._makeManifestColumnRow(MANIFEST.columns[1], FIELDS);
      label = row._children[0];
      eq(label.textContent, 'debut (Date) *');
      select = row._children[1];
      eq(select.className, 'manifest-column-select');
      eq(select.dataset.declared, 'debut');
      eq(select.dataset.required, '1');
      values = (function() {
        var i, len, ref, results;
        ref = select._children;
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          o = ref[i];
          results.push(o.value);
        }
        return results;
      })();
      eq(values[0], '');
      eq(select._children[0].textContent, '—');
      return eq(values.slice(1).join(','), 'date_debut,date_fin');
    });
    it('une colonne optionnelle n’est pas marquée obligatoire', function() {
      var row;
      row = AVH._makeManifestColumnRow(MANIFEST.columns[2], FIELDS);
      eq(row._children[0].textContent, 'fin (Date)');
      return eq(row._children[1].dataset.required, '0');
    });
    it('chaque option typée reçoit le bon contrôle et sa valeur par défaut', function() {
      var color, flag, number, text;
      color = AVH._makeManifestOptionRow(MANIFEST.options[0]);
      eq(color._children[1].type, 'color');
      eq(color._children[1].value, '#36c');
      eq(color._children[1].dataset.option, 'couleur');
      number = AVH._makeManifestOptionRow(MANIFEST.options[1]);
      eq(number._children[1].type, 'number');
      eq(number._children[1].value, '12');
      flag = AVH._makeManifestOptionRow(MANIFEST.options[2]);
      eq(flag._children[1].type, 'checkbox');
      eq(flag._children[1].checked, true);
      text = AVH._makeManifestOptionRow(MANIFEST.options[3]);
      eq(text._children[1].type, 'text');
      return eq(text._children[1].value, 'Calendrier');
    });
    return it('le formulaire complet rend colonnes puis options', function() {
      var form;
      setForm();
      AVH._renderWidgetManifestForm(MANIFEST);
      form = document.getElementById('widget-manifest-form');
      return eq(form._children.length, 7);
    });
  });

  describe('Fenêtre « ＋ Widget » — choix du type', function() {
    it('plugin avec manifest : paires masquées, formulaire affiché', function() {
      setForm();
      AVH._widgetPluginsByName = {
        calendrier: {
          name: 'calendrier',
          manifest: JSON.stringify(MANIFEST)
        }
      };
      AVH._updateWidgetParamsForm('calendrier');
      assert(document.getElementById('widget-params-pairs').classList.contains('hidden'), 'paires masquées');
      assert(!document.getElementById('widget-manifest-form').classList.contains('hidden'), 'formulaire affiché');
      return eq(AVH._currentWidgetManifest.columns.length, 3);
    });
    it('plugin sans manifest : paires affichées, formulaire masqué', function() {
      setForm();
      AVH._widgetPluginsByName = {
        libre: {
          name: 'libre',
          manifest: ''
        }
      };
      AVH._updateWidgetParamsForm('libre');
      eq(AVH._currentWidgetManifest, null);
      assert(!document.getElementById('widget-params-pairs').classList.contains('hidden'));
      return assert(document.getElementById('widget-manifest-form').classList.contains('hidden'));
    });
    return it('table : paires comme avant', function() {
      setForm();
      AVH._updateWidgetParamsForm('table');
      return assert(!document.getElementById('widget-params-pairs').classList.contains('hidden'));
    });
  });

  describe('Fenêtre « ＋ Widget » — validation et collecte', function() {
    var makeSelect;
    makeSelect = function(declared, value, required) {
      var el;
      el = document.createElement('select');
      el.value = value;
      el.dataset.declared = declared;
      el.dataset.required = required ? '1' : '0';
      return el;
    };
    it('colonne obligatoire non mappée : erreur nommée', function() {
      var errors;
      setForm([makeSelect('titre', 'nom', true), makeSelect('debut', '', true)]);
      AVH._currentWidgetManifest = MANIFEST;
      errors = AVH._validateWidgetManifestForm();
      eq(errors.length, 1);
      return assert(errors[0].indexOf('debut') > -1);
    });
    it('colonne optionnelle non mappée : acceptée', function() {
      setForm([makeSelect('titre', 'nom', true), makeSelect('fin', '', false)]);
      AVH._currentWidgetManifest = MANIFEST;
      return eq(AVH._validateWidgetManifestForm().length, 0);
    });
    it('collecte le mappage et les options typées', function() {
      var colorInput, data, flagInput, numberInput;
      colorInput = document.createElement('input');
      colorInput.dataset.option = 'couleur';
      colorInput.dataset.optionType = 'color';
      colorInput.value = '#c33';
      numberInput = document.createElement('input');
      numberInput.dataset.option = 'taille';
      numberInput.dataset.optionType = 'number';
      numberInput.value = '20';
      flagInput = document.createElement('input');
      flagInput.dataset.option = 'compact';
      flagInput.dataset.optionType = 'boolean';
      flagInput.checked = false;
      setForm([makeSelect('titre', 'nom', true)], [colorInput, numberInput, flagInput]);
      data = AVH._collectWidgetManifestData();
      eq(data.columns.titre, 'nom');
      eq(data.params.couleur, '#c33');
      eq(data.params.taille, 20);
      return eq(data.params.compact, false);
    });
    return it('le formulaire remplace les paires dans les données envoyées', function() {
      var colorInput, data;
      colorInput = document.createElement('input');
      colorInput.dataset.option = 'couleur';
      colorInput.dataset.optionType = 'color';
      colorInput.value = '#c33';
      setForm([makeSelect('titre', 'nom', true), makeSelect('debut', 'date_debut', true)], [colorInput]);
      AVH._currentWidgetManifest = MANIFEST;
      // Une paire clé/valeur traînerait encore : elle doit être ignorée.
      document.querySelectorAll = (function() {
        var original;
        original = document.querySelectorAll;
        return function(sel) {
          if (sel === '#widget-params-list .param-row') {
            return [
              {
                querySelector: function() {
                  return {
                    value: 'ignoré'
                  };
                }
              }
            ];
          } else {
            return original(sel);
          }
        };
      })();
      data = AVH._collectWidgetData();
      eq(data.columns.titre, 'nom');
      eq(data.columns.debut, 'date_debut');
      eq(data.params.couleur, '#c33');
      eq(data.params.ignore, void 0);
      return eq(data.fields.length, 0);
    });
  });

  summary();

}).call(this);
