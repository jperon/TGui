local H = require('html')
local make_fields_panel
make_fields_panel = require('ui.fields_panel').make_fields_panel
local make_admin_panel
make_admin_panel = require('ui.admin_panels').make_admin_panel
local make_toolbar
make_toolbar = function()
  return H.div({
    id = 'data-toolbar',
    class = 'hidden',
    H.span({
      id = 'data-title',
      class = 'content-title',
      ''
    }),
    H.button({
      id = 'undo-btn',
      class = 'toolbar-btn toolbar-btn--icon',
      title = 'Annuler (Ctrl/Cmd+Z)',
      '↶'
    }),
    H.button({
      id = 'redo-btn',
      class = 'toolbar-btn toolbar-btn--icon',
      title = 'Rétablir (Ctrl/Cmd+Shift+Z)',
      '↷'
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
      class = 'toolbar-filter',
      H.span({
        class = 'toolbar-filter-label',
        '⚗'
      }),
      H.input({
        id = 'formula-filter-input',
        type = 'text',
        class = 'toolbar-filter-input',
        placeholder = 'Filtre (ex: self.disponible)'
      })
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
  })
end
local make_yaml_toolbar
make_yaml_toolbar = function()
  return H.div({
    id = 'yaml-editor-panel',
    class = 'hidden',
    H.div({
      class = 'yaml-editor-toolbar',
      H.span({
        id = 'yaml-page-name',
        class = 'content-title',
        ''
      }),
      H.button({
        id = 'yaml-edit-btn',
        class = 'toolbar-btn',
        '✎ Éditer'
      }),
      H.button({
        id = 'yaml-add-widget-btn',
        class = 'toolbar-btn',
        '＋ Widget'
      }),
      H.button({
        id = 'yaml-delete-btn',
        class = 'toolbar-btn toolbar-btn--danger',
        title = 'Supprimer la page',
        '🗑'
      })
    })
  })
end
local make_welcome_screen
make_welcome_screen = function()
  return H.div({
    id = 'welcome',
    class = 'welcome',
    H.p({
      'Sélectionnez un espace ou une vue dans la barre latérale.'
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
    make_toolbar(),
    make_yaml_toolbar(),
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
    make_admin_panel(),
    make_welcome_screen()
  })
end
return {
  make_content = make_content
}
