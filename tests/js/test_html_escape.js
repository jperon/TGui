(function() {
  // tests/js/test_html_escape.coffee
  // TdbHtml.escape + tests d'injection pour les sites corrigés en S3 (échappement innerHTML).

  // ── AUDIT SITE PAR SITE des affectations innerHTML / insertAdjacentHTML / outerHTML / document.write ──
  // (grep -n "innerHTML\|insertAdjacentHTML\|outerHTML\|document\.write" frontend/src/*.coffee frontend/src/views/*.coffee)
  // Aucun insertAdjacentHTML / outerHTML / document.write n'existe dans le dépôt.
  // Légende origine : STAT=gabarit statique · USER=donnée utilisateur (nom d'espace/champ/utilisateur/groupe/page/plugin/vue)
  //   SERV=réponse serveur · I18N=traduction app._t(...) · YML=contenu YAML de page (choisi par l'utilisateur)
  // Légende état : OK=déjà sûr (textContent/createlement/statique/échappé) · CORRIGÉ=corrigé dans cette tâche

  // fichier:ligne | origine | déjà échappé ? | corrigé ?
  // ─────────────────────────────────────────────────────────────────────────────
  // app_data_helpers.coffee:39        | STAT (clear '' )                     | n/a            | OK
  // app_data_helpers.coffee:188       | STAT (clear '' )                     | n/a            | OK
  //   → noms d'espaces/vues via textContent (l.45, l.194) : déjà sûr
  // app_fields_helpers.coffee:114     | STAT (option placeholder)             | n/a            | OK
  // app_fields_helpers.coffee:225     | STAT (clear '' )                     | n/a            | OK
  //   → noms de champs/cibles via textContent (l.263-269) : déjà sûr (audit 1.9)
  // app_sidebar_helpers.coffee:197    | STAT (clear '' )                     | n/a            | OK
  // app_sidebar_helpers.coffee:229    | STAT (clear '' )                     | n/a            | OK
  //   → noms utilisateurs/groupes via textContent (l.204-239) : déjà sûr (audit 1.9)
  // app_snapshot_helpers.coffee:103   | STAT (clear '' )                     | n/a            | OK
  // app_snapshot_helpers.coffee:105   | I18N + SERV (counts r.created/skipped)| params numériques | CORRIGÉ → textContent
  // app_snapshot_helpers.coffee:108   | I18N + SERV (r.errors[] non échappés)| NON            | CORRIGÉ → textContent + createElement/code
  // app_snapshot_helpers.coffee:123   | STAT (clear '' )                     | n/a            | OK
  // app_snapshot_helpers.coffee:139   | USER (space/field/types) via `safe`  | oui (esc local) | CORRIGÉ → TdbHtml.escape (équiv. prouvé, sur-ensemble : ajoute ')
  // app_snapshot_helpers.coffee:141   | I18N (fieldToCreate, params=safe)    | oui (params échappés avant _t) | OK (inchangé)
  // app_snapshot_helpers.coffee:143   | I18N (fieldToDelete, params=safe)    | oui (params échappés avant _t) | OK (inchangé)
  //   → i18n.interpolate (i18n.coffee:228-232) NE fait PAS l'échappement : les
  //     chaînes HTML (fieldToCreate/Delete) reçoivent des params pré-échappés ;
  //     importOk/importErr n'ont aucun tag HTML et des params numériques.
  //     Les autres _t avec params (ui.confirms, ui.apps…) passent par
  //     tdbConfirm/tdbAlert/_makeEl → textContent : sûrs.
  // app_view_config_helpers.coffee:45  | STAT (option placeholder)            | n/a            | OK
  // app_view_config_helpers.coffee:55  | STAT (clear '' )                     | n/a            | OK
  // app_view_config_helpers.coffee:231 | STAT (placeholder)                   | n/a            | OK
  // app_view_config_helpers.coffee:250 | STAT (placeholder)                   | n/a            | OK
  // app_view_config_helpers.coffee:252 | STAT (placeholder)                   | n/a            | OK
  // app_view_config_helpers.coffee:299 | USER (fieldInfo.spaceName/name/type) | NON            | CORRIGÉ → createElement/textContent
  //   (définition morte de toggleFieldSelection, écrasée par la suivante — corrigée quand même)
  // app_view_config_helpers.coffee:363 | STAT (placeholder)                   | n/a            | OK
  // app_view_config_helpers.coffee:381 | STAT (placeholder)                   | n/a            | OK
  // app_view_config_helpers.coffee:384 | STAT (placeholder)                   | n/a            | OK
  // app_view_config_helpers.coffee:442 | USER (fieldData.name/spaceName/type) | NON            | CORRIGÉ → createElement/textContent
  //   (définition active de toggleFieldSelection)
  // app_view_config_helpers.coffee:658 | STAT (clear '' )                     | n/a            | OK
  // app_view_helpers_add_widget.coffee:28  | STAT (structure modal)           | n/a            | OK
  // app_view_helpers_add_widget.coffee:47  | STAT (option placeholder)        | n/a            | OK
  // app_view_helpers_add_widget.coffee:98  | STAT (option placeholder)        | n/a            | OK
  // app_view_helpers_add_widget.coffee:199 | STAT (clear '' )                 | n/a            | OK
  // app_view_helpers_add_widget.coffee:200 | STAT (clear '' )                 | n/a            | OK
  // app_view_helpers_add_widget.coffee:204 | STAT (message statique)          | n/a            | OK
  // app_view_helpers_add_widget.coffee:265 | STAT (template param-row)        | n/a            | OK
  // app_view_helpers.coffee:11        | STAT (clear '' )                     | n/a            | OK
  // app_view_helpers.coffee:22        | STAT (toolbar buttons)               | n/a            | OK
  // app_view_helpers.coffee:69        | YML/SERV (e.message depuis jsyaml)   | NON            | CORRIGÉ → createElement/textContent
  // app_view_helpers_pages.coffee:10  | STAT (clear '' )                     | n/a            | OK
  //   → noms de pages via textContent/createTextNode : déjà sûr
  // app_view_helpers_widget_plugins.coffee:158 | STAT (clear '' )            | n/a            | OK
  //   → noms de plugins via textContent (l.177) : déjà sûr
  // app_view_helpers_zones.coffee:47  | STAT (modale création zone)          | n/a            | OK
  // app_view_helpers_zones.coffee:286 | STAT (modale gestion zones)          | n/a            | OK
  // app_view_helpers_zones.coffee:323 | STAT (clear '' )                     | n/a            | OK
  // app_view_helpers_zones.coffee:311→309 | YML (zone.id/title/widgetCount) | NON           | CORRIGÉ → _renderZoneItem (createElement/textContent)
  // yaml_builder.coffee:311           | STAT (clear '' )                     | n/a            | OK
  //   → noms d'espaces/champs via textContent (SVG) : déjà sûr
  // app_apps_helpers.coffee           | (aucune affectation — commentaires)   | n/a            | OK
  // views/custom_view.coffee:140      | STAT (clear '' via _setMessage)       | n/a            | OK
  // views/custom_view.coffee:147      | STAT (clear '' )                     | n/a            | OK
  // views/custom_view.coffee:156→147  | YML/SERV (e.message jsyaml)          | NON            | CORRIGÉ → _setMessage (textContent)
  // views/custom_view.coffee:169      | STAT (`<code>layout</code>` fixe)    | n/a            | OK
  // views/custom_view.coffee:307→307  | YML (wNode.space)                    | NON            | CORRIGÉ → _setMessage (textContent)
  // views/custom_view.coffee:373      | STAT (`<code>space</code>` fixe)     | n/a            | OK
  // views/custom_view.coffee:377      | STAT (Chargement…)                   | n/a            | OK
  // views/custom_view.coffee:388      | STAT (clear '' )                     | n/a            | OK
  // views/custom_view.coffee:390      | STAT (Aucun résultat)                | n/a            | OK
  // views/custom_view.coffee:440      | SERV (err.message aggregateSpace)    | NON            | CORRIGÉ → _setMessage (textContent)
  // views/custom_view.coffee:516      | STAT (`<code>type</code>` fixe)      | n/a            | OK (conservé)
  // views/custom_view.coffee:510→516  | YML (pluginName = wNode.type)        | NON            | CORRIGÉ → _setMessage (textContent)
  // views/custom_view.coffee:513→516  | YML (pluginName)                     | NON            | CORRIGÉ → _setMessage (textContent)
  // views/custom_view.coffee:518      | SERV (err.message WidgetPlugins)     | NON            | CORRIGÉ → _setMessage (textContent)
  // views/custom_view.coffee:533      | STAT (clear '' )                     | n/a            | OK
  // views/custom_view.coffee:648      | iframe srcdoc (runtime plugin, escapeHtml(txt) déjà appliqué dans le code généré) | oui | OK (by design, hors page parente)
  // views/custom_view.coffee:660      | iframe render() API du plugin        | n/a            | OK (by design : le plugin rend du HTML volontairement)
  // views/custom_view.coffee:723      | STAT (clear '' )                     | n/a            | OK
  // views/custom_view.coffee:740      | STAT ('⋮' glyph)                     | n/a            | OK
  // views/data_view.coffee:204        | STAT (clear '' )                     | n/a            | OK
  // views/data_view.coffee:309        | STAT (clear '' )                     | n/a            | OK
  // views/data_view.coffee:882        | STAT (clear '' )                     | n/a            | OK
  //   → formateurs de grille : _escapeHtml (l.865) et _formatFormulaError
  //     délèguent désormais à TdbHtml.escape (équivalence prouvé : même 5
  //     caractères ; TdbHtml ajoute l'échappement de ' — sur-emploi sûr).
  //     Les formateurs retournent des chaînes HTML consommées par tui.Grid
  //     (innerHTML du libellé de cellule) : échappement requis et présent.
  // ─────────────────────────────────────────────────────────────────────────────
  // Sites NON testables avec le stub DOM (tests/js/dom_stub.coffee) :
  // - app_snapshot_helpers.coffee:108 (branche importSnapshot errors) : le code
  //   vit dans un callback d'addEventListener sur un bouton, dépendant de
  //   GQL.mutate et de app._loadAll — non isolable sans rejouer tout le flux
  //   d'import. La correction est structurellement sûre (textContent +
  //   createElement/code) : pas de parsing HTML.
  // - app_view_helpers_zones.coffee zone list : la population de la liste vit
  //   dans _openZoneManageModal, dépendante de GQL.query — le helper isolé
  //   _renderZoneItem est testé ici à la place.
  // - views/custom_view.coffee:440 (catch aggregateSpace) : nécessite
  //   Spaces.aggregateSpace + promesses ; testé indirectement via _setMessage
  //   et les autres chemins CustomView ci-dessous.
  // - i18n.interpolate : non testé ici (module i18n non chargé dans ce test) ;
  //   le comportement est documenté ci-dessus et les appelsants HTML échappent
  //   déjà leurs params (snapshot) ou passent par textContent (apps/confirms).
  var MALICIOUS, TdbHtml, assert, collectTags, deepEq, describe, eq, it, summary;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  require('../../frontend/src/html_escape');

  TdbHtml = global.window.TdbHtml;

  collectTags = function(node) {
    var tags, walk;
    tags = [];
    walk = function(n) {
      var c, j, len, ref, results;
      if (n && n.tagName) {
        tags.push(n.tagName);
      }
      if (n && n._children) {
        ref = n._children;
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          c = ref[j];
          results.push(walk(c));
        }
        return results;
      }
    };
    walk(node);
    return tags;
  };

  MALICIOUS = '<img src=x onerror=alert(1)>';

  // ---------------------------------------------------------------------------
  describe('TdbHtml.escape', function() {
    it('échappe les cinq caractères HTML', function() {
      return eq(TdbHtml.escape('&<>"\''), '&amp;&lt;&gt;&quot;&#39;');
    });
    it('tolère null, undefined et les nombres', function() {
      eq(TdbHtml.escape(null), '');
      eq(TdbHtml.escape(void 0), '');
      eq(TdbHtml.escape(42), '42');
      return eq(TdbHtml.escape(0), '0');
    });
    return it('laisse les chaînes normales intactes', function() {
      eq(TdbHtml.escape('espace_1'), 'espace_1');
      return eq(TdbHtml.escape(''), '');
    });
  });

  // ---------------------------------------------------------------------------
  describe('AppSnapshotHelpers.renderSnapshotDiff — sécurité', function() {
    var ASH, beforeModule, makeApp;
    ASH = null;
    beforeModule = function() {
      require('../../frontend/src/app_snapshot_helpers');
      return ASH = global.window.AppSnapshotHelpers;
    };
    makeApp = function() {
      var app, els, get;
      els = {};
      get = function(id) {
        return els[id] != null ? els[id] : els[id] = global.document.createElement('div');
      };
      app = {
        _t: function(key, vars = {}) {
          if (key === 'ui.snapshot.fieldToCreate') {
            return `<code>${vars.space}.${vars.field}</code> (${vars.newType}) — à créer`;
          } else if (key === 'ui.snapshot.fieldToDelete') {
            return `<code>${vars.space}.${vars.field}</code> (${vars.oldType}) — sera supprimé`;
          } else {
            return key;
          }
        },
        el: {
          snapshotDiffContent: function() {
            return get('snapshot-diff-content');
          }
        }
      };
      return app;
    };
    return it('n’injecte pas de HTML depuis un nom d’espace ou de champ', function() {
      var app, blob, diff, htmlBlobs, j, len, results, tags, walk;
      beforeModule();
      app = makeApp();
      diff = {
        spacesToCreate: [MALICIOUS],
        spacesToDelete: [MALICIOUS],
        fieldsToCreate: [
          {
            space: MALICIOUS,
            field: 'f',
            oldType: null,
            newType: 'String'
          }
        ],
        fieldsToDelete: [
          {
            space: 's',
            field: MALICIOUS,
            oldType: 'String',
            newType: null
          }
        ],
        fieldsToChange: [
          {
            space: 's',
            field: 'f',
            oldType: MALICIOUS,
            newType: 'String'
          }
        ],
        pagesToCreate: [],
        pagesToUpdate: [],
        widgetPluginsToCreate: [],
        widgetPluginsToUpdate: []
      };
      ASH.renderSnapshotDiff(app, diff);
      tags = collectTags(app.el.snapshotDiffContent());
      assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
      // Les items objet passent par innerHTML avec valeurs échappées (TdbHtml) :
      // le stub ne parse pas innerHTML, on vérifie donc la chaîne produite.
      walk = function(n, fn) {
        var c, j, len, ref, results;
        fn(n);
        ref = n._children || [];
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          c = ref[j];
          results.push(walk(c, fn));
        }
        return results;
      };
      htmlBlobs = [];
      walk(app.el.snapshotDiffContent(), function(n) {
        if (n.innerHTML && n.innerHTML !== '') {
          return htmlBlobs.push(n.innerHTML);
        }
      });
      results = [];
      for (j = 0, len = htmlBlobs.length; j < len; j++) {
        blob = htmlBlobs[j];
        assert(blob.indexOf('<img') < 0, `innerHTML non échappé : ${blob}`);
        if (blob.indexOf('img') >= 0) {
          results.push(assert(blob.indexOf('&lt;img') >= 0, `escape manquant dans : ${blob}`));
        } else {
          results.push(void 0);
        }
      }
      return results;
    });
  });

  // ---------------------------------------------------------------------------
  describe('AppViewConfigHelpers.toggleFieldSelection — sécurité', function() {
    it('n’injecte pas de HTML depuis un nom d’espace/champ (déf. active)', function() {
      var AVCH, app, container, fieldData, tags;
      require('../../frontend/src/app_view_config_helpers');
      AVCH = global.window.AppViewConfigHelpers;
      container = global.document.createElement('div');
      global.document._setById('dv-selected-fields', container);
      // Le stub querySelector renvoie un élément mémoïsimé (toujours truthy) :
      // on le neutralise pour simuler « champ pas encore sélectionné ».
      container.querySelector = function() {
        return null;
      };
      app = {};
      fieldData = {
        id: 'f1',
        name: MALICIOUS,
        spaceId: 'sp1',
        spaceName: MALICIOUS,
        type: 'String'
      };
      AVCH._yamlChanged = false;
      AVCH.toggleFieldSelection(app, fieldData);
      tags = collectTags(container);
      assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
      assert(tags.indexOf('STRONG') >= 0, 'le nom doit être rendu comme texte');
      return assert(tags.indexOf('BUTTON') >= 0, 'le bouton de retrait doit exister');
    });
    return it('n’injecte pas de HTML (définition morte, fieldInfo)', function() {
      var AVCH;
      require('../../frontend/src/app_view_config_helpers');
      AVCH = global.window.AppViewConfigHelpers;
      // La définition en tête de fichier (fieldInfo) est écrasée par la suivante
      // dans le littéral d'objet : on teste le comportement de la déf. active
      // avec la forme fieldData, et on vérifie que le module expose bien un seul
      // toggleFieldSelection opérationnel.
      assert(typeof AVCH.toggleFieldSelection === 'function');
      return assert(typeof AVCH.removeField === 'function');
    });
  });

  // ---------------------------------------------------------------------------
  describe('AppViewHelpers._renderZoneItem — sécurité', function() {
    return it('n’injecte pas de HTML depuis un titre de zone YAML', function() {
      var AVH, item, tags;
      require('../../frontend/src/app_view_helpers');
      require('../../frontend/src/app_view_helpers_zones');
      AVH = global.window.AppViewHelpers;
      item = AVH._renderZoneItem({
        id: MALICIOUS,
        title: MALICIOUS,
        widgetCount: 2
      });
      tags = collectTags(item);
      assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
      assert(tags.indexOf('SPAN') >= 0, 'le titre doit être rendu comme texte');
      return assert(tags.indexOf('INPUT') >= 0, 'la checkbox doit exister');
    });
  });

  // ---------------------------------------------------------------------------
  describe('AppViewHelpers.renderCustomViewPreview — sécurité (erreur YAML)', function() {
    return it('n’injecte pas de HTML depuis un message d’erreur de plugin YAML', function() {
      var AVH, app, container, errEls, tags;
      require('../../frontend/src/html_escape');
      require('../../frontend/src/views/custom_view');
      require('../../frontend/src/views/custom_view_plugins');
      // app_view_helpers.js référence CustomView en identifiant nu (window en
      // navigateur) : il faut aussi l'exposer sur global pour Node.
      global.CustomView = global.window.CustomView;
      global.jsyaml = {
        load: function() {
          return {
            layout: {
              widget: {
                id: 'w1',
                type: 'boom',
                space: 's'
              }
            }
          };
        }
      };
      global.WidgetPlugins = {
        getByName: function(name) {
          throw new Error(`boom ${MALICIOUS}`);
        }
      };
      require('../../frontend/src/app_view_helpers');
      AVH = global.window.AppViewHelpers;
      AVH._bindZoneEvents = function() {};
      container = global.document.createElement('div');
      app = {
        el: {
          customViewContainer: function() {
            return container;
          }
        },
        _allSpaces: [],
        _allDataViews: [],
        _currentCustomView: null,
        _activeCustomView: null
      };
      AVH.renderCustomViewPreview(app, 'layout-ok');
      tags = collectTags(container);
      assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
      errEls = container._children.filter(function(c) {
        return c.className === 'error-message';
      });
      assert(errEls.length >= 1, 'un div error-message doit être créé');
      return assert(errEls[errEls.length - 1].textContent.includes(MALICIOUS), 'le message d’erreur doit être du texte');
    });
  });

  // ---------------------------------------------------------------------------
  describe('CustomView._renderWidget — sécurité (nom d’espace YAML)', function() {
    return it('n’injecte pas de HTML depuis un nom d’espace introuvable', function() {
      var CV, body, container, cv, p, tags, wrapper;
      require('../../frontend/src/views/custom_view');
      CV = global.window.CustomView;
      container = global.document.createElement('div');
      cv = new CV(container, 'layout: {}', [], []);
      wrapper = cv._renderWidget({
        space: MALICIOUS
      });
      tags = collectTags(wrapper);
      assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
      assert(tags.indexOf('P') >= 0, 'le message doit être rendu comme élément p');
      body = wrapper._children[1];
      p = body._children[0];
      assert(p != null, 'élément p manquant');
      return assert(p.textContent.includes(MALICIOUS), 'le nom doit apparaître comme texte');
    });
  });

  // ---------------------------------------------------------------------------
  describe('AppSidebarHelpers — sécurité (noms utilisateurs/groupes)', function() {
    it('loadAdminUsers n’injecte pas de HTML depuis un nom d’utilisateur', function() {
      var ASH, app, btn, ul;
      require('../../frontend/src/app_sidebar_helpers');
      ASH = global.window.AppSidebarHelpers;
      global.Auth = {
        listUsers: function() {
          return Promise.resolve([
            {
              id: 'u1',
              username: MALICIOUS,
              groups: [
                {
                  name: 'admin'
                }
              ]
            }
          ]);
        }
      };
      ul = global.document.createElement('ul');
      btn = global.document.createElement('button');
      app = {
        _t: function(k, v = {}) {
          return k;
        },
        el: {
          adminUsersList: function() {
            return ul;
          },
          adminCreateUserBtn: function() {
            return btn;
          }
        }
      };
      ASH.loadAdminUsers(app);
      return new Promise(function(resolve, reject) {
        return setTimeout(function() {
          var e, tags;
          try {
            tags = collectTags(ul);
            assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
            assert(tags.indexOf('SPAN') >= 0, 'le nom doit être rendu comme texte');
            return resolve();
          } catch (error) {
            e = error;
            return reject(e);
          }
        }, 0);
      });
    });
    return it('loadAdminGroups n’injecte pas de HTML depuis un nom de groupe', function() {
      var ASH, app, btn, ul;
      require('../../frontend/src/app_sidebar_helpers');
      ASH = global.window.AppSidebarHelpers;
      global.Auth = {
        listGroups: function() {
          return Promise.resolve([
            {
              id: 'g1',
              name: MALICIOUS,
              members: [
                {
                  username: 'x'
                }
              ]
            }
          ]);
        }
      };
      ul = global.document.createElement('ul');
      btn = global.document.createElement('button');
      app = {
        _t: function(k, v = {}) {
          return k;
        },
        el: {
          adminGroupsList: function() {
            return ul;
          },
          adminCreateGroupBtn: function() {
            return btn;
          }
        }
      };
      ASH.loadAdminGroups(app);
      return new Promise(function(resolve, reject) {
        return setTimeout(function() {
          var e, tags;
          try {
            tags = collectTags(ul);
            assert(tags.indexOf('IMG') < 0, 'aucun élément img ne doit être créé');
            assert(tags.indexOf('SPAN') >= 0, 'le nom de groupe doit être rendu comme texte');
            return resolve();
          } catch (error) {
            e = error;
            return reject(e);
          }
        }, 0);
      });
    });
  });

  // ---------------------------------------------------------------------------
  describe('DataView._escapeHtml / _formatFormulaError — délégation TdbHtml', function() {
    it('_escapeHtml délègue à TdbHtml.escape', function() {
      var DV, dv;
      global.GQL = {
        query: function() {
          return Promise.resolve({}, {
            mutate: function() {
              return Promise.resolve({});
            }
          });
        }
      };
      global.tui = {
        Grid: class {
          constructor(opts = {}) {
            this._data = [];
            this._columns = opts.columns || [];
          }

          resetData(d) {
            return this._data = d;
          }

          getData() {
            return this._data;
          }

          getColumns() {
            return this._columns;
          }

          getRowAt(i) {
            return this._data[i] || null;
          }

          addRowClassName() {}

          on() {}

          destroy() {}

          getIndexOfRow() {
            return 0;
          }

          getRowCount() {
            return this._data.length;
          }

          getFocusedCell() {
            return null;
          }

          getCheckedRowKeys() {
            return [];
          }

        }
      };
      require('../../frontend/src/views/data_view');
      DV = global.window.DataView;
      dv = new DV(global.document.createElement('div'), {
        id: 's',
        name: 's',
        fields: []
      });
      eq(dv._escapeHtml('&<>"\''), '&amp;&lt;&gt;&quot;&#39;');
      return eq(dv._escapeHtml(MALICIOUS), '&lt;img src=x onerror=alert(1)&gt;');
    });
    return it('_formatFormulaError échappe le contenu de l’erreur', function() {
      var DV, dv, html;
      DV = global.window.DataView;
      dv = new DV(global.document.createElement('div'), {
        id: 's',
        name: 's',
        fields: []
      });
      html = dv._formatFormulaError(`[ERROR|${MALICIOUS}|<script>x</script>]`);
      assert(html.indexOf('<img') < 0, 'le HTML brut ne doit pas figurer');
      assert(html.indexOf('&lt;img') >= 0, 'le contenu doit être échappé');
      assert(html.indexOf('<script') < 0);
      return assert(html.indexOf('&lt;script') >= 0);
    });
  });

  summary();

}).call(this);
