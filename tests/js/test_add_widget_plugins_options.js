(function() {
  // tests/js/test_add_widget_plugins_options.coffee
  // Fenêtre « ＋ Widget » : le groupe « Widgets personnalisés » est rempli depuis
  // WidgetPlugins.list(), et un widget personnalisé (plugin) se valide sans
  // sélection de colonnes (spec 2026-11-16-custom-widgets-design.md §3 bis).
  var AVH, assert, describe, document, eq, it, makeList, setForm, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  // Le module sous test étend window.AppViewHelpers (défini par un autre fichier
  // en production) : le stub suffit ici.
  global.window.AppViewHelpers = {};

  global.window.Auth = null;

  require('../../frontend/src/app_view_helpers_add_widget');

  AVH = global.window.AppViewHelpers;

  document = global.document;

  // Conteneur du groupe « Widgets personnalisés », comme dans widget_modal.moon
  makeList = function() {
    var list;
    list = document.createElement('div');
    list.id = 'widget-type-plugin-list';
    document._setById('widget-type-plugin-list', list);
    return list;
  };

  // Formulaire minimal : titre + espace remplis, type donné, aucun champ.
  setForm = function(type) {
    var space, title;
    title = document.createElement('input');
    title.value = 'Mon widget';
    document._setById('widget-title-input', title);
    space = document.createElement('select');
    space.value = 'space-uuid';
    document._setById('widget-space-select', space);
    document.querySelector = function(sel) {
      if (sel === 'input[name="widget-type"]:checked') {
        return {
          value: type
        };
      } else {
        return null;
      }
    };
    document.querySelectorAll = function() {
      return [];
    };
  };

  describe('Widgets personnalisés — options de type', function() {
    it('rend une option par plugin, valeur radio = nom du plugin', function() {
      var first, input, label, list, second;
      list = makeList();
      AVH._renderWidgetTypePlugins([
        {
          name: 'calendrier',
          description: 'Vue calendrier'
        },
        {
          name: 'carte'
        }
      ]);
      eq(list._children.length, 2);
      first = list._children[0];
      assert(first.classList.contains('widget-type-option'), 'classe widget-type-option');
      assert(first.classList.contains('widget-type-option--plugin'), 'variante plugin');
      eq(first.title, 'Vue calendrier');
      input = first._children[0];
      eq(input.type, 'radio');
      eq(input.name, 'widget-type');
      eq(input.value, 'calendrier');
      label = first._children[1];
      eq(label.textContent, 'calendrier');
      eq(label.getAttribute('for'), input.id);
      eq(label._children[0].textContent, 'Vue calendrier');
      // Sans description : pas de sous-titre
      second = list._children[1];
      eq(second._children[0].value, 'carte');
      return eq(second._children[1]._children.length, 0);
    });
    it('affiche « Aucun widget personnalisé » quand la liste est vide', function() {
      var list;
      list = makeList();
      AVH._renderWidgetTypePlugins([]);
      eq(list._children.length, 1);
      return eq(list._children[0].textContent, 'Aucun widget personnalisé');
    });
    it('affiche un message d’erreur visible (jamais avalé)', function() {
      var list, message;
      list = makeList();
      AVH._renderWidgetTypePluginsError(new Error('réseau KO'));
      eq(list._children.length, 1);
      message = list._children[0];
      assert(message.classList.contains('widget-type-hint--error'), 'classe d’erreur');
      assert(message.textContent.indexOf('réseau KO') > -1, 'le message doit être visible');
      return assert(message.textContent.indexOf('widgets personnalisés') > -1, 'contexte lisible');
    });
    return it('remplace la liste précédente au lieu de l’accumuler', function() {
      var list;
      list = makeList();
      AVH._renderWidgetTypePlugins([
        {
          name: 'a'
        }
      ]);
      AVH._renderWidgetTypePlugins([
        {
          name: 'b'
        }
      ]);
      eq(list._children.length, 1);
      return eq(list._children[0]._children[0].value, 'b');
    });
  });

  describe('Widgets personnalisés — sélection du type', function() {
    return it('marque une seule option et coche son radio', function() {
      var optionA, optionB, radioA, radioB, scope;
      scope = document.createElement('div');
      document._setById('widget-type-options', scope);
      radioA = document.createElement('input');
      radioA.checked = false;
      optionA = document.createElement('div');
      optionA.className = 'widget-type-option';
      optionA.appendChild(radioA);
      radioB = document.createElement('input');
      radioB.checked = false;
      optionB = document.createElement('div');
      optionB.className = 'widget-type-option';
      optionB.appendChild(radioB);
      optionA.querySelector = function(sel) {
        if (sel === 'input[type="radio"]') {
          return radioA;
        }
      };
      optionB.querySelector = function(sel) {
        if (sel === 'input[type="radio"]') {
          return radioB;
        }
      };
      scope.querySelectorAll = function() {
        return [optionA, optionB];
      };
      AVH._selectWidgetType(optionB);
      assert(optionB.classList.contains('selected'), 'option choisie marquée');
      assert(!optionA.classList.contains('selected'), 'ancienne option démarquée');
      eq(radioB.checked, true);
      return eq(radioA.checked, false);
    });
  });

  describe('Widgets personnalisés — validation du formulaire', function() {
    it('refuse un « Tableau simple » sans colonne', function() {
      var errors;
      setForm('table');
      errors = AVH._validateWidgetForm();
      eq(errors.length, 1);
      return assert(errors[0].indexOf('champ') > -1, 'message sur les champs attendu');
    });
    return it('accepte un widget personnalisé sans colonne', function() {
      var errors;
      setForm('mon_plugin');
      errors = AVH._validateWidgetForm();
      return eq(errors.join(' / '), '');
    });
  });

  describe('Widgets personnalisés — données envoyées', function() {
    it('renvoie type = nom du plugin, params et la source', function() {
      var data;
      setForm('mon_plugin');
      document.querySelectorAll = function(sel) {
        if (sel !== '#widget-params-list .param-row') {
          return [];
        }
        return [
          {
            querySelector: function(s) {
              if (s === '.param-key') {
                return {
                  value: 'couleur'
                };
              } else {
                return {
                  value: '#c33'
                };
              }
            }
          },
          {
            querySelector: function(s) {
              if (s === '.param-key') {
                return {
                  value: 'titre'
                };
              } else {
                return {
                  value: "L'été"
                };
              }
            }
          },
          {
            querySelector: function(s) {
              if (s === '.param-key') {
                return {
                  value: '  '
                };
              } else {
                return {
                  value: 'ignoré'
                };
              }
            }
          }
        ];
      };
      data = AVH._collectWidgetData();
      eq(data.type, 'mon_plugin');
      eq(data.title, 'Mon widget');
      eq(data.spaceId, 'space-uuid');
      eq(data.fields.length, 0);
      eq(data.params.couleur, '#c33');
      eq(data.params.titre, "L'été");
      return eq(Object.keys(data.params).length, 2);
    });
    return it('garde « table » par défaut quand aucun radio n’est coché', function() {
      var data;
      setForm('table');
      document.querySelector = function() {
        return null;
      };
      data = AVH._collectWidgetData();
      return eq(data.type, 'table');
    });
  });

  describe('Widgets personnalisés — lien éditeur', function() {
    it('est visible pour un admin', function() {
      global.window.Auth = {
        isAdmin: function() {
          return true;
        }
      };
      return eq(AVH._canEditWidgetPlugins(), true);
    });
    it('est masqué pour un non-admin', function() {
      global.window.Auth = {
        isAdmin: function() {
          return false;
        }
      };
      return eq(AVH._canEditWidgetPlugins(), false);
    });
    return it('reste visible si l’info n’est pas disponible (serveur juge)', function() {
      global.window.Auth = null;
      return eq(AVH._canEditWidgetPlugins(), true);
    });
  });

  describe('Widgets personnalisés — page courante', function() {
    return it('résout l’id depuis la vue courante puis depuis le hash', function() {
      var app;
      app = {
        _currentCustomView: {
          id: 'cv-1'
        }
      };
      eq(AVH._resolveAddWidgetViewId(app, '#page/abc'), 'cv-1');
      eq(AVH._resolveAddWidgetViewId({}, '#page/abc-def'), 'abc-def');
      eq(AVH._resolveAddWidgetViewId({}, '#view/dv-42'), 'dv-42');
      eq(AVH._resolveAddWidgetViewId({}, '#space/deadbeef'), null);
      return eq(AVH._resolveAddWidgetViewId(null, ''), null);
    });
  });

  summary();

}).call(this);
