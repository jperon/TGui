local H = require('html')
local ICON = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%2389b4fa'/><text x='50%' y='54%' dominant-baseline='middle' text-anchor='middle' font-family='system-ui,sans-serif' font-weight='700' font-size='18' fill='%231e1e2e'>db</text></svg>"
local FIELD_TYPE_OPTIONS = {
  {
    'String',
    'String'
  },
  {
    'Int',
    'Int'
  },
  {
    'Float',
    'Float'
  },
  {
    'Boolean',
    'Boolean'
  },
  {
    'UUID',
    'UUID'
  },
  {
    'Any',
    'Any (type libre)'
  },
  {
    'Map',
    'Map (objet JSON)'
  },
  {
    'Array',
    'Array (tableau JSON)'
  },
  {
    'Sequence',
    'Séquence (auto-incrément)'
  },
  {
    'Relation',
    'Relation'
  }
}
local field_type_select
field_type_select = function()
  local opts = {
    id = 'field-type'
  }
  for _index_0 = 1, #FIELD_TYPE_OPTIONS do
    local _des_0 = FIELD_TYPE_OPTIONS[_index_0]
    local val, label
    val, label = _des_0[1], _des_0[2]
    table.insert(opts, H.option({
      value = val
    }, label))
  end
  return H.select(opts)
end
local make_head
make_head = function()
  return H.head({
    H.meta({
      charset = 'UTF-8'
    }),
    H.meta({
      name = 'viewport',
      content = 'width=device-width, initial-scale=1.0'
    }),
    H.title({
      'tdb'
    }),
    H.link({
      rel = 'icon',
      href = ICON
    }),
    H.link({
      rel = 'stylesheet',
      href = '/vendor/tui-grid.bundle.css'
    }),
    H.link({
      rel = 'stylesheet',
      href = '/vendor/codemirror.bundle.css'
    }),
    H.link({
      rel = 'stylesheet',
      href = '/css/app.css'
    })
  })
end
local make_login_overlay
make_login_overlay = function()
  return H.div({
    id = 'login-overlay',
    class = 'overlay',
    H.div({
      class = 'login-box',
      H.h1({
        'tdb'
      }),
      H.input({
        id = 'login-username',
        type = 'text',
        placeholder = "Nom d'utilisateur"
      }),
      H.input({
        id = 'login-password',
        type = 'password',
        placeholder = 'Mot de passe'
      }),
      H.button({
        id = 'login-btn',
        'Connexion'
      }),
      H.p({
        id = 'login-error',
        class = 'error',
        ''
      })
    })
  })
end
local make_sidebar
make_sidebar = function()
  return H.nav({
    id = 'sidebar',
    H.div({
      class = 'sidebar-header',
      H.span({
        class = 'logo',
        'tdb'
      })
    }),
    H.div({
      class = 'sidebar-section',
      H.div({
        class = 'sidebar-section-title',
        H.span({
          'Vues'
        }),
        H.button({
          id = 'new-view-btn',
          title = 'Nouvelle vue',
          '＋'
        })
      }),
      H.ul({
        id = 'custom-view-list',
        ''
      })
    }),
    H.div({
      class = 'sidebar-section',
      H.div({
        class = 'sidebar-section-title',
        H.span({
          'Données'
        }),
        H.button({
          id = 'new-space-btn',
          title = 'Nouvel espace',
          '＋'
        })
      }),
      H.ul({
        id = 'space-list',
        ''
      })
    }),
    H.div({
      id = 'admin-sidebar-section',
      class = 'sidebar-section hidden',
      H.div({
        class = 'sidebar-section-title',
        H.span({
          'Administration'
        })
      }),
      H.ul({
        class = 'admin-nav-list',
        H.li({
          id = 'admin-nav-users',
          'Utilisateurs'
        }),
        H.li({
          id = 'admin-nav-groups',
          'Groupes'
        }),
        H.li({
          id = 'admin-nav-snapshot',
          'Export / Import'
        })
      })
    }),
    H.div({
      class = 'sidebar-footer',
      H.button({
        id = 'current-user-btn',
        class = 'current-user-btn',
        ''
      }),
      H.div({
        id = 'user-menu',
        class = 'user-menu hidden',
        H.button({
          id = 'change-password-btn',
          'Changer le mot de passe'
        }),
        H.button({
          id = 'logout-btn',
          'Déconnexion'
        })
      })
    })
  })
end
local make_fields_panel
make_fields_panel = function()
  return H.aside({
    id = 'fields-panel',
    class = 'hidden',
    H.div({
      class = 'fields-panel-header',
      H.span({
        'Champs'
      }),
      H.button({
        id = 'fields-panel-close',
        '✕'
      })
    }),
    H.ul({
      id = 'fields-list',
      ''
    }),
    H.div({
      class = 'fields-add-form',
      H.input({
        id = 'field-name',
        type = 'text',
        placeholder = 'Nom du champ'
      }),
      field_type_select(),
      H.div({
        id = 'rel-target-row',
        class = 'hidden',
        H.label({
          class = 'formula-hint',
          'Cible :'
        }),
        H.select({
          id = 'rel-to-space',
          H.option({
            value = '',
            'Cible…'
          })
        })
      }),
      H.label({
        H.input({
          id = 'field-notnull',
          type = 'checkbox'
        }),
        ' Requis'
      }),
      H.div({
        class = 'formula-section',
        H.div({
          class = 'formula-type-row',
          H.label({
            class = 'formula-radio',
            H.input({
              type = 'radio',
              name = 'formula-type',
              value = 'none',
              checked = 'checked'
            }),
            ' Aucune formule'
          }),
          H.label({
            class = 'formula-radio',
            H.input({
              type = 'radio',
              name = 'formula-type',
              value = 'formula'
            }),
            ' Colonne calculée'
          }),
          H.label({
            class = 'formula-radio',
            H.input({
              type = 'radio',
              name = 'formula-type',
              value = 'trigger'
            }),
            ' Trigger formula'
          })
        }),
        H.div({
          id = 'formula-body',
          class = 'hidden',
          H.div({
            class = 'formula-lang-row',
            H.label({
              class = 'formula-hint',
              ['for'] = 'formula-language',
              'Langage :'
            }),
            H.select({
              id = 'formula-language',
              H.option({
                value = 'lua',
                'Lua'
              }),
              H.option({
                value = 'moonscript',
                'MoonScript'
              })
            })
          }),
          H.textarea({
            id = 'field-formula',
            rows = '3',
            placeholder = "Expression (Lua : self.prenom .. ' ' .. self.nom)",
            ''
          }),
          H.button({
            id = 'formula-expand-btn',
            class = 'formula-expand-btn',
            title = 'Ouvrir dans l\'éditeur',
            '⤢ Agrandir'
          }),
          H.div({
            id = 'trigger-fields-row',
            class = 'hidden',
            H.label({
              class = 'formula-hint',
              ['for'] = 'field-trigger-fields',
              'Déclencher quand :'
            }),
            H.input({
              id = 'field-trigger-fields',
              type = 'text',
              placeholder = '* | nom, prenom | (vide = création seule)'
            }),
            H.span({
              class = 'formula-hint',
              'Vide = création seule · ',
              H.code({
                '*'
              }),
              ' = tout changement · liste de champs'
            })
          })
        })
      }),
      H.div({
        class = 'fields-form-actions',
        H.button({
          id = 'field-add-btn',
          'Ajouter'
        }),
        H.button({
          id = 'field-cancel-btn',
          class = 'hidden',
          'Annuler'
        })
      })
    })
  })
end
local make_content
make_content = function()
  return H.main({
    id = 'content',
    H.div({
      id = 'default-password-warning',
      class = 'warning-banner hidden',
      '⚠ Vous utilisez le mot de passe par défaut. ',
      H.button({
        id = 'warning-change-password-btn',
        'Changer maintenant'
      })
    }),
    H.div({
      id = 'data-toolbar',
      class = 'hidden',
      H.span({
        id = 'data-title',
        class = 'content-title',
        ''
      }),
      H.button({
        id = 'rename-space-btn',
        class = 'toolbar-btn toolbar-btn--icon',
        title = 'Renommer',
        '✎'
      }),
      H.button({
        id = 'delete-space-btn',
        class = 'toolbar-btn toolbar-btn--icon toolbar-btn--danger',
        title = "Supprimer l'espace",
        '🗑'
      }),
      H.div({
        class = 'toolbar-spacer',
        ''
      }),
      H.button({
        id = 'delete-rows-btn',
        class = 'toolbar-btn toolbar-btn--icon toolbar-btn--danger',
        title = 'Supprimer les lignes sélectionnées',
        '🗑'
      }),
      H.button({
        id = 'fields-btn',
        class = 'fields-btn',
        '⊞ Champs'
      })
    }),
    H.div({
      id = 'yaml-editor-panel',
      class = 'hidden',
      H.div({
        class = 'yaml-editor-toolbar',
        H.span({
          id = 'yaml-view-name',
          class = 'content-title',
          ''
        }),
        H.button({
          id = 'yaml-edit-btn',
          class = 'toolbar-btn',
          '✎ Éditer'
        }),
        H.button({
          id = 'yaml-delete-btn',
          class = 'toolbar-btn toolbar-btn--danger',
          title = 'Supprimer la vue',
          '🗑'
        })
      })
    }),
    H.div({
      id = 'content-row',
      H.div({
        id = 'grid-container',
        ''
      }),
      H.div({
        id = 'custom-view-container',
        class = 'hidden',
        ''
      }),
      make_fields_panel()
    }),
    H.div({
      id = 'admin-panel',
      class = 'hidden admin-panel',
      H.div({
        id = 'admin-users-section',
        H.div({
          class = 'admin-section-header',
          H.h2({
            'Utilisateurs'
          }),
          H.button({
            id = 'admin-create-user-btn',
            class = 'toolbar-btn',
            '＋ Créer'
          })
        }),
        H.ul({
          id = 'admin-users-list',
          ''
        })
      }),
      H.div({
        id = 'admin-groups-section',
        class = 'hidden',
        H.div({
          class = 'admin-section-header',
          H.h2({
            'Groupes'
          }),
          H.button({
            id = 'admin-create-group-btn',
            class = 'toolbar-btn',
            '＋ Créer'
          })
        }),
        H.ul({
          id = 'admin-groups-list',
          ''
        })
      }),
      H.div({
        id = 'admin-snapshot-section',
        class = 'hidden',
        H.div({
          class = 'admin-section-header',
          H.h2({
            'Export / Import'
          })
        }),
        H.div({
          class = 'snapshot-export-box',
          H.h3({
            'Exporter'
          }),
          H.p({
            'Téléchargez la définition complète de l\'application sous forme de fichier YAML.'
          }),
          H.div({
            class = 'snapshot-export-btns',
            H.button({
              id = 'snapshot-export-schema-btn',
              class = 'toolbar-btn',
              '⬇ Structure seule'
            }),
            H.button({
              id = 'snapshot-export-full-btn',
              class = 'toolbar-btn',
              '⬇ Structure + données'
            })
          })
        }),
        H.div({
          class = 'snapshot-import-box',
          H.h3({
            'Importer'
          }),
          H.p({
            'Importez un fichier .tdb.yaml exporté depuis tdb.'
          }),
          H.div({
            class = 'snapshot-import-file-row',
            H.label({
              ["for"] = 'snapshot-file-input',
              class = 'toolbar-btn',
              '📂 Choisir un fichier'
            }),
            H.input({
              id = 'snapshot-file-input',
              type = 'file',
              accept = '.yaml,.yml,.tdb.yaml',
              class = 'hidden'
            }),
            H.span({
              id = 'snapshot-file-name',
              class = 'snapshot-file-name',
              ''
            })
          }),
          H.div({
            id = 'snapshot-diff-box',
            class = 'hidden snapshot-diff-box',
            H.h4({
              'Modifications détectées'
            }),
            H.div({
              id = 'snapshot-diff-content',
              ''
            }),
            H.div({
              class = 'snapshot-import-mode',
              H.label({
                H.input({
                  id = 'snapshot-mode-merge',
                  type = 'radio',
                  name = 'snapshot-mode',
                  value = 'merge',
                  checked = true
                }),
                H.span({
                  ' Fusion (recommandé) — crée ce qui manque, ignore l\'existant'
                })
              }),
              H.label({
                H.input({
                  id = 'snapshot-mode-replace',
                  type = 'radio',
                  name = 'snapshot-mode',
                  value = 'replace'
                }),
                H.span({
                  ' Remplacement — '
                }),
                H.strong({
                  'efface toutes les données existantes'
                }),
                H.span({
                  ' puis recrée'
                })
              })
            }),
            H.p({
              id = 'snapshot-import-error',
              class = 'error hidden',
              ''
            }),
            H.div({
              class = 'modal-actions',
              H.button({
                id = 'snapshot-import-confirm-btn',
                class = 'toolbar-btn',
                '⬆ Importer'
              })
            })
          }),
          H.div({
            id = 'snapshot-import-result',
            class = 'hidden snapshot-import-result',
            ''
          })
        })
      })
    }),
    H.div({
      id = 'welcome',
      class = 'welcome',
      H.p({
        'Sélectionnez un espace ou une vue dans la barre latérale.'
      })
    }),
    H.div({
      id = 'change-password-dialog',
      class = 'modal-overlay hidden',
      H.div({
        class = 'modal-box',
        H.h2({
          'Changer le mot de passe'
        }),
        H.input({
          id = 'cp-current',
          type = 'password',
          placeholder = 'Mot de passe actuel'
        }),
        H.input({
          id = 'cp-new',
          type = 'password',
          placeholder = 'Nouveau mot de passe'
        }),
        H.input({
          id = 'cp-confirm',
          type = 'password',
          placeholder = 'Confirmer le nouveau'
        }),
        H.p({
          id = 'cp-error',
          class = 'error',
          ''
        }),
        H.div({
          class = 'modal-actions',
          H.button({
            id = 'cp-submit-btn',
            'Enregistrer'
          }),
          H.button({
            id = 'cp-cancel-btn',
            'Annuler'
          })
        })
      })
    }),
    H.div({
      id = 'create-user-dialog',
      class = 'modal-overlay hidden',
      H.div({
        class = 'modal-box',
        H.h2({
          'Créer un utilisateur'
        }),
        H.input({
          id = 'cu-username',
          type = 'text',
          placeholder = "Nom d'utilisateur"
        }),
        H.input({
          id = 'cu-email',
          type = 'email',
          placeholder = 'Email (optionnel)'
        }),
        H.input({
          id = 'cu-password',
          type = 'password',
          placeholder = 'Mot de passe'
        }),
        H.p({
          id = 'cu-error',
          class = 'error',
          ''
        }),
        H.div({
          class = 'modal-actions',
          H.button({
            id = 'cu-submit-btn',
            'Créer'
          }),
          H.button({
            id = 'cu-cancel-btn',
            'Annuler'
          })
        })
      })
    }),
    H.div({
      id = 'create-group-dialog',
      class = 'modal-overlay hidden',
      H.div({
        class = 'modal-box',
        H.h2({
          'Créer un groupe'
        }),
        H.input({
          id = 'cg-name',
          type = 'text',
          placeholder = 'Nom du groupe'
        }),
        H.input({
          id = 'cg-description',
          type = 'text',
          placeholder = 'Description (optionnel)'
        }),
        H.p({
          id = 'cg-error',
          class = 'error',
          ''
        }),
        H.div({
          class = 'modal-actions',
          H.button({
            id = 'cg-submit-btn',
            'Créer'
          }),
          H.button({
            id = 'cg-cancel-btn',
            'Annuler'
          })
        })
      })
    }),
    H.div({
      id = 'yaml-modal',
      class = 'modal-overlay hidden',
      H.div({
        class = 'modal-box modal-box--editor',
        H.div({
          class = 'modal-editor-header',
          H.span({
            id = 'yaml-modal-title',
            class = 'modal-title',
            ''
          }),
          H.div({
            class = 'modal-editor-actions',
            H.button({
              id = 'yaml-modal-preview-btn',
              class = 'toolbar-btn',
              '▶ Aperçu'
            }),
            H.button({
              id = 'yaml-modal-save-btn',
              class = 'btn-primary',
              '💾 Enregistrer'
            }),
            H.button({
              id = 'yaml-modal-close-btn',
              class = 'toolbar-btn',
              '✕'
            })
          })
        }),
        H.div({
          class = 'yaml-modal-body',
          H.div({
            id = 'yaml-validation-msg',
            class = 'yaml-validation-msg hidden',
            ''
          }),
          H.div({
            id = 'yaml-cm-editor',
            ''
          }),
          H.div({
            id = 'schema-browser',
            class = 'schema-browser',
            ''
          })
        })
      })
    }),
    H.div({
      id = 'formula-modal',
      class = 'modal-overlay hidden',
      H.div({
        class = 'modal-box modal-box--editor',
        H.div({
          class = 'modal-editor-header',
          H.span({
            class = 'modal-title',
            'Éditeur de formule'
          }),
          H.div({
            class = 'modal-editor-actions',
            H.button({
              id = 'formula-modal-apply-btn',
              class = 'btn-primary',
              'Appliquer'
            }),
            H.button({
              id = 'formula-modal-close-btn',
              class = 'toolbar-btn',
              '✕'
            })
          })
        }),
        H.div({
          id = 'formula-cm-editor',
          ''
        })
      })
    })
  })
end
local make_body
make_body = function()
  return H.body({
    H.div({
      id = 'app',
      make_login_overlay(),
      H.div({
        id = 'main',
        class = 'hidden',
        make_sidebar(),
        make_content()
      })
    }),
    H.script({
      src = '/vendor/tui-grid.bundle.js',
      ''
    }),
    H.script({
      src = '/vendor/jsyaml.bundle.js',
      ''
    }),
    H.script({
      src = '/vendor/codemirror.bundle.js',
      ''
    }),
    H.script({
      src = '/src/modal.js',
      ''
    }),
    H.script({
      src = '/src/graphql_client.js',
      ''
    }),
    H.script({
      src = '/src/auth.js',
      ''
    }),
    H.script({
      src = '/src/spaces.js',
      ''
    }),
    H.script({
      src = '/src/views/data_view.js',
      ''
    }),
    H.script({
      src = '/src/views/custom_view.js',
      ''
    }),
    H.script({
      src = '/src/yaml_builder.js',
      ''
    }),
    H.script({
      src = '/src/app.js',
      ''
    })
  })
end
local _html = nil
local render
render = function()
  if _html then
    return _html
  end
  local doc = H.html({
    lang = 'fr',
    make_head(),
    make_body()
  })
  _html = "<!DOCTYPE html>\n" .. doc
  return _html
end
return {
  render = render
}
