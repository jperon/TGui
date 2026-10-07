(function() {
  // app_view_helpers_yaml.coffee — YAML editor helpers extracted from app_view_helpers.coffee
  Object.assign(window.AppViewHelpers, {
    bindYamlEditor: function(app) {
      app.el.yamlEditBtn().addEventListener('click', function() {
        return app._openYamlModal();
      });
      app.el.yamlAddWidgetBtn().addEventListener('click', function() {
        return window.AppViewHelpers._openAddWidgetModal(app);
      });
      app.el.yamlDeleteBtn().addEventListener('click', async function() {
        var cv;
        cv = app._currentCustomView;
        if (!cv) {
          return;
        }
        if (!(await tdbConfirm(app._t('ui.confirms.deletePage', {
          name: cv.name
        })))) {
          return;
        }
        return GQL.mutate(app._deleteCustomViewMutation, {
          id: cv.id
        }).then(function() {
          var ref;
          app._currentCustomView = null;
          if ((ref = app._activeCustomView) != null) {
            if (typeof ref.unmount === "function") {
              ref.unmount();
            }
          }
          app._activeCustomView = null;
          app.el.yamlEditorPanel().classList.add('hidden');
          app.el.customViewContainer().classList.add('hidden');
          app.el.welcome().classList.remove('hidden');
          return app.loadPages();
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      app.el.yamlModalSaveBtn().addEventListener('click', function() {
        var cv, yaml;
        cv = app._currentCustomView;
        if (!cv) {
          return;
        }
        yaml = app._cmYaml.getValue();
        return GQL.mutate(app._updateCustomViewMutation, {
          id: cv.id,
          input: {yaml}
        }).then(function(data) {
          app._currentCustomView = data.updateCustomView;
          app.el.yamlModal().classList.add('hidden');
          app._renderCustomViewPreview(yaml);
          return app.loadPages();
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      app.el.yamlModalCloseBtn().addEventListener('click', function() {
        return app.el.yamlModal().classList.add('hidden');
      });
      return app.el.yamlModalPreviewBtn().addEventListener('click', function() {
        if (!app._cmYaml) {
          return;
        }
        return app._renderCustomViewPreview(app._cmYaml.getValue());
      });
    },
    openYamlModal: function(app) {
      var cv, query;
      cv = app._currentCustomView;
      if (!cv) {
        return;
      }
      // Recharger la vue depuis la base pour avoir le YAML à jour
      query = `query GetView($viewId: ID!) {
  customView(id: $viewId) {
    id
    name
    yaml
  }
}`;
      return window.GQL.query(query, {
        viewId: cv.id
      }).then(function(data) {
        var applyValidationLayout, ref, yamlPane;
        if (data.customView) {
          // Mettre à jour la vue courante avec les données fraîches
          app._currentCustomView = data.customView;
          cv = data.customView;
          app.el.yamlModalTitle().textContent = cv.name;
          app.el.yamlModal().classList.remove('hidden');
          // Ajouter la palette d'insertion de layouts dans le header de la modale YAML
          window.AppViewHelpers.setupLayoutPalette(app);
          // Configurer le listener global d'insertion de layouts
          if ((ref = window.CustomView) != null) {
            if (typeof ref.setupLayoutInsertion === "function") {
              ref.setupLayoutInsertion();
            }
          }
          yamlPane = document.querySelector('.yaml-editor-pane');
          applyValidationLayout = function() {
            var hasError;
            if (!(yamlPane && app._yamlValidMsg)) {
              return;
            }
            hasError = !app._yamlValidMsg.classList.contains('hidden');
            return yamlPane.classList.toggle('has-validation-error', hasError);
          };
          if (!app._cmYaml) {
            app._cmYaml = CodeMirror(document.getElementById('yaml-cm-editor'), {
              mode: 'yaml',
              theme: 'monokai',
              lineNumbers: true,
              lineWrapping: true,
              tabSize: 2,
              indentWithTabs: false
            });
            app._cmYaml.on('change', function(cm, change) {
              var e, ref1, ref2, ref3;
              if (!app._yamlValidMsg) {
                app._yamlValidMsg = document.getElementById('yaml-validation-msg');
              }
              if (change.origin === 'setValue') {
                if ((ref1 = app._yamlValidMsg) != null) {
                  ref1.classList.add('hidden');
                }
                applyValidationLayout();
                return;
              }
              if ((ref2 = app._yamlBuilder) != null) {
                ref2.reloadFromYaml(cm.getValue());
              }
              try {
                jsyaml.load(cm.getValue());
                if ((ref3 = app._yamlValidMsg) != null) {
                  ref3.classList.add('hidden');
                }
                return applyValidationLayout();
              } catch (error1) {
                e = error1;
                if (app._yamlValidMsg) {
                  app._yamlValidMsg.textContent = `YAML invalide : ${e.message}`;
                  app._yamlValidMsg.classList.remove('hidden');
                  return applyValidationLayout();
                }
              }
            });
          } else {
            if (app._yamlValidMsg == null) {
              app._yamlValidMsg = document.getElementById('yaml-validation-msg');
            }
            applyValidationLayout();
          }
          // Recharger le YAML depuis la base pour avoir la version à jour
          window.GQL.query(`query GetView($viewId: ID!) {
  customView(id: $viewId) {
    id
    name
    yaml
  }
}`, {
            viewId: cv.id
          }).then(function(data) {
            var freshYaml;
            if (data.customView) {
              freshYaml = data.customView.yaml;
              app._currentCustomView.yaml = freshYaml;
              app._cmYaml.setValue(freshYaml || '');
              return setTimeout((function() {
                return app._cmYaml.refresh();
              }), 10);
            }
          }).catch(function(error) {
            console.error('Erreur lors du rechargement du YAML:', error);
            // Utiliser le YAML existant en cas d'erreur
            app._cmYaml.setValue(cv.yaml || '');
            return setTimeout((function() {
              return app._cmYaml.refresh();
            }), 10);
          });
          return app._loadAllRelations().then(function(relations) {
            app._yamlBuilder = new YamlBuilder({
              container: document.getElementById('schema-browser'),
              allSpaces: app._allSpaces,
              allRelations: relations,
              initialYaml: cv.yaml || '',
              onChange: function(yaml) {
                var ref1;
                return (ref1 = app._cmYaml) != null ? ref1.setValue(yaml) : void 0;
              }
            });
            return app._yamlBuilder.mount();
          });
        }
      }).catch(function(error) {
        return console.error('Erreur lors du chargement de la vue:', error);
      });
    },
    loadAllRelations: function(app) {
      if (app._allRelations) {
        return Promise.resolve(app._allRelations);
      }
      return Promise.all(app._allSpaces.map(function(sp) {
        return Spaces.listRelations(sp.id);
      })).then(function(results) {
        app._allRelations = results.reduce((function(a, b) {
          return a.concat(b);
        }), []);
        return app._allRelations;
      });
    },
    setupLayoutPalette: function(app) {
      var actionsContainer, btnHoriz, btnVert, existingPalette, palette;
      // Vérifier si la palette existe déjà pour éviter les doublons
      existingPalette = document.querySelector('.cv-layout-palette');
      if (existingPalette) {
        return;
      }
      // Créer la palette d'insertion de layouts
      palette = document.createElement('div');
      palette.className = 'cv-layout-palette';
      btnVert = document.createElement('button');
      btnVert.textContent = 'Ajouter layout vertical';
      btnVert.className = 'cv-layout-btn';
      btnVert.title = 'Insérer un layout vertical';
      btnHoriz = document.createElement('button');
      btnHoriz.textContent = 'Ajouter layout horizontal';
      btnHoriz.className = 'cv-layout-btn';
      btnHoriz.title = 'Insérer un layout horizontal';
      palette.appendChild(btnVert);
      palette.appendChild(btnHoriz);
      // Insérer la palette dans le header de la modale YAML
      actionsContainer = document.querySelector('.modal-editor-actions');
      if (actionsContainer) {
        actionsContainer.insertBefore(palette, actionsContainer.firstChild);
        // Gestion des clics sur la palette
        btnVert.addEventListener('click', function() {
          return window.dispatchEvent(new CustomEvent('cv-insert-layout', {
            detail: {
              direction: 'vertical'
            }
          }));
        });
        return btnHoriz.addEventListener('click', function() {
          return window.dispatchEvent(new CustomEvent('cv-insert-layout', {
            detail: {
              direction: 'horizontal'
            }
          }));
        });
      }
    }
  });

}).call(this);
