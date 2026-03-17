#!/usr/bin/env moon
-- backend/index.moon
-- Dynamically generates the main TGui HTML page.
-- Uses backend/html.lua to build the HTML tree.

H = require 'html'

-- Constants
ICON = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%2389b4fa'/><text x='50%' y='54%' dominant-baseline='middle' text-anchor='middle' font-family='system-ui,sans-serif' font-weight='700' font-size='18' fill='%231e1e2e'>db</text></svg>"

FIELD_TYPE_OPTIONS = {
  {'String',   'String'}
  {'Int',      'Int'}
  {'Float',    'Float'}
  {'Boolean',  'Boolean'}
  {'UUID',     'UUID'}
  {'Any',      'Any (type libre)'}
  {'Map',      'Map (objet JSON)'}
  {'Array',    'Array (tableau JSON)'}
  {'Sequence', 'Séquence (auto-incrément)'}
  {'Datetime', 'Datetime'}
  {'Relation', 'Relation'}
}

-- Helpers
field_type_select = ->
  opts = {id: 'field-type'}
  for {val, label} in *FIELD_TYPE_OPTIONS
    table.insert opts, H.option({value: val}, label)
  H.select opts

-- Main components
make_head = ->
  H.head {
    H.meta {charset: 'UTF-8'}
    H.meta {name: 'viewport', content: 'width=device-width, initial-scale=1.0'}
    H.title {'TGui'}
    H.link {rel: 'icon', href: ICON}
    H.link {rel: 'stylesheet', href: '/vendor/tui-grid.bundle.css'}
    H.link {rel: 'stylesheet', href: '/vendor/codemirror.bundle.css'}
    H.link {rel: 'stylesheet', href: '/css/app.css'}
  }

make_login_overlay = ->
  H.div {id: 'login-overlay', class: 'overlay',
    H.div {class: 'login-box',
      H.h1 {['data-i18n']: 'ui.login.title', 'TGui'}
      H.input {id: 'login-username', type: 'text',     placeholder: "Nom d'utilisateur"}
      H.input {id: 'login-password', type: 'password', placeholder: 'Mot de passe'}
      H.button {id: 'login-btn', ['data-i18n']: 'ui.login.button', 'Connexion'}
      H.p {id: 'login-error', class: 'error', ''}
    }
  }

_userMenu = ->
  H.div {id: 'user-menu', class: 'user-menu hidden',
    H.button {id: 'change-password-btn', ['data-i18n']: 'ui.menu.changePassword', 'Changer le mot de passe'}
    H.button {id: 'logout-btn', ['data-i18n']: 'ui.menu.logout', 'Déconnexion'}
    H.div {class: 'menu-lang-row',
      H.button {id: 'lang-fr-btn', class: 'toolbar-btn', ['data-i18n']: 'ui.menu.langFr', 'FR'}
      H.button {id: 'lang-en-btn', class: 'toolbar-btn', ['data-i18n']: 'ui.menu.langEn', 'EN'}
    }
  }

_sidebarFooter = ->
  H.div {class: 'sidebar-footer',
    H.button {id: 'current-user-btn', class: 'current-user-btn', ''}
    _userMenu!
  }

make_sidebar = ->
  H.nav {id: 'sidebar',
    H.div {class: 'sidebar-header',
      H.span {class: 'logo', 'TGui'}
      H.button {id: 'sidebar-toggle', class: 'sidebar-toggle-btn', title: 'Replier le menu', '≡'}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.span {'Pages'}
        H.button {id: 'new-page-btn', title: 'Nouvelle page', '＋'}
      }
      H.ul {id: 'page-list', ''}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.button {id: 'spaces-toggle-btn', class: 'section-toggle-btn', '▾'}
        H.span {'Données'}
        H.button {id: 'new-space-btn', title: 'Nouvel espace', '＋'}
      }
      H.ul {id: 'space-list', ''}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.button {id: 'data-views-toggle-btn', class: 'section-toggle-btn', '▾'}
        H.span {'Vues'}
        H.button {id: 'new-data-view-btn', title: 'Nouvelle vue', '＋'}
      }
      H.ul {id: 'data-view-list', ''}
    }
    H.div {id: 'plugins-sidebar-section', class: 'sidebar-section hidden',
      H.div {class: 'sidebar-section-title',
        H.span {'Outils'}
      }
      H.ul {class: 'plugins-nav-list',
        H.li {id: 'plugins-nav-manage', 'Gestion des plugins'}
      }
    }
    H.div {id: 'admin-sidebar-section', class: 'sidebar-section hidden collapsed',
      H.div {class: 'sidebar-section-title',
        H.button {id: 'admin-toggle-btn', class: 'section-toggle-btn', '▸'}
        H.span {'Administration'}
      }
      H.ul {class: 'admin-nav-list',
        H.li {id: 'admin-nav-users', 'Utilisateurs'}
        H.li {id: 'admin-nav-groups', 'Groupes'}
        H.li {id: 'admin-nav-snapshot', 'Export / Import'}
      }
    }
    _sidebarFooter!
  }

_fieldFormulaSection = ->
  H.div {class: 'formula-section',
    H.div {class: 'formula-type-row',
      H.label {class: 'formula-radio',
        H.input {type: 'radio', name: 'formula-type', value: 'none', checked: 'checked'}
        ' Aucune formule'
      }
      H.label {class: 'formula-radio',
        H.input {type: 'radio', name: 'formula-type', value: 'formula'}
        ' Colonne calculée'
      }
      H.label {class: 'formula-radio',
        H.input {type: 'radio', name: 'formula-type', value: 'trigger'}
        ' Trigger formula'
      }
    }
    H.div {id: 'formula-body', class: 'hidden',
      H.div {class: 'formula-lang-row',
        H.label {class: 'formula-hint', ['for']: 'formula-language', 'Langage :'}
        H.select {id: 'formula-language',
          H.option {value: 'lua',        'Lua'}
          H.option {value: 'moonscript', 'MoonScript'}
        }
      }
      H.textarea {id: 'field-formula', rows: '3',
        placeholder: "Expression (Lua : self.prenom .. ' ' .. self.nom)", ''}
      H.button {id: 'formula-expand-btn', class: 'formula-expand-btn',
        title: 'Ouvrir dans l\'éditeur', '⤢ Agrandir'}
      H.div {id: 'trigger-fields-row', class: 'hidden',
        H.label {class: 'formula-hint', ['for']: 'field-trigger-fields',
          'Déclencher quand :'}
        H.input {id: 'field-trigger-fields', type: 'text',
          placeholder: '* | nom, prenom | (vide = création seule)'}
        H.span {class: 'formula-hint',
          'Vide = création seule · '
          H.code {'*'}
          ' = tout changement · liste de champs'
        }
      }
    }
  }

_fieldReprSection = ->
  H.div {id: 'field-repr-section',
    H.label {class: 'formula-hint', ['for']: 'field-repr-formula', 'Représentation (affichage) :'}
    H.textarea {id: 'field-repr-formula', rows: '2',
      placeholder: "Ex: os.date('%d/%m/%Y', self.date) ou string.format('%.2f', self.montant)", ''}
    H.span {class: 'formula-hint', 'Formule MoonScript/Lua de rendu visuel (ne modifie pas la donnée brute).'}
  }

make_fields_panel = ->
  H.aside {id: 'fields-panel', class: 'hidden',
    H.div {class: 'fields-panel-header',
      H.span {'Champs'}
      H.button {id: 'fields-panel-close', '✕'}
    }
    H.ul {id: 'fields-list', ''}
    H.div {class: 'fields-add-form',
      H.input {id: 'field-name', type: 'text', placeholder: 'Nom du champ'}
      field_type_select!
      H.div {id: 'rel-target-row', class: 'hidden',
        H.label {class: 'formula-hint', 'Cible :'}
        H.select {id: 'rel-to-space',
          H.option {value: '', 'Cible…'}
        }
      }
      H.div {id: 'rel-repr-row', class: 'hidden',
        H.label {class: 'formula-hint', 'Représentation :'}
        H.textarea {id: 'rel-repr-formula', rows: '2',
          placeholder: "self.nom .. ' ' .. self.prenom", ''}
      }
      H.label {
        H.input {id: 'field-notnull', type: 'checkbox'}
        ' Requis'
      }
      _fieldFormulaSection!
      _fieldReprSection!
      H.div {class: 'fields-form-actions',
        H.button {id: 'field-add-btn', 'Ajouter'}
        H.button {id: 'field-cancel-btn', class: 'hidden', 'Annuler'}
      }
    }
  }

make_toolbar = ->
  H.div {id: 'data-toolbar', class: 'hidden',
    H.span {id: 'data-title', class: 'content-title', ''}
    H.button {id: 'undo-btn', class: 'toolbar-btn toolbar-btn--icon', title: 'Annuler (Ctrl/Cmd+Z)', '↶'}
    H.button {id: 'redo-btn', class: 'toolbar-btn toolbar-btn--icon', title: 'Rétablir (Ctrl/Cmd+Shift+Z)', '↷'}
    H.button {id: 'rename-space-btn', class: 'toolbar-btn toolbar-btn--icon', title: 'Renommer', '✎'}
    H.button {id: 'delete-space-btn', class: 'toolbar-btn toolbar-btn--icon toolbar-btn--danger', title: "Supprimer l'espace", '🗑'}
    H.div {class: 'toolbar-filter',
      H.span {class: 'toolbar-filter-label', '⚗'}
      H.input {id: 'formula-filter-input', type: 'text',
        class: 'toolbar-filter-input',
        placeholder: 'Filtre (ex: self.disponible)'}
    }
    H.button {id: 'delete-rows-btn', class: 'toolbar-btn toolbar-btn--icon toolbar-btn--danger', title: 'Supprimer les lignes sélectionnées', '🗑'}
    H.button {id: 'fields-btn', class: 'fields-btn', '⊞ Champs'}
  }

make_yaml_toolbar = ->
  H.div {id: 'yaml-editor-panel', class: 'hidden',
    H.div {class: 'yaml-editor-toolbar',
      H.span {id: 'yaml-page-name', class: 'content-title', ''}
      H.button {id: 'yaml-edit-btn', class: 'toolbar-btn', '✎ Éditer'}
      H.button {id: 'yaml-add-widget-btn', class: 'toolbar-btn', '＋ Widget'}
      H.button {id: 'yaml-delete-btn', class: 'toolbar-btn toolbar-btn--danger', title: 'Supprimer la page', '🗑'}
    }
  }

make_welcome_screen = ->
  H.div {id: 'welcome', class: 'welcome',
    H.p {'Sélectionnez un espace ou une vue dans la barre latérale.'}
  }

_adminUsersSection = ->
  H.div {id: 'admin-users-section',
    H.div {class: 'admin-section-header',
      H.h2 {'Utilisateurs'}
      H.button {id: 'admin-create-user-btn', class: 'toolbar-btn', '＋ Créer'}
    }
    H.ul {id: 'admin-users-list', ''}
  }

_adminGroupsSection = ->
  H.div {id: 'admin-groups-section', class: 'hidden',
    H.div {class: 'admin-section-header',
      H.h2 {'Groupes'}
      H.button {id: 'admin-create-group-btn', class: 'toolbar-btn', '＋ Créer'}
    }
    H.ul {id: 'admin-groups-list', ''}
  }

_snapshotExportBox = ->
  H.div {class: 'snapshot-export-box',
    H.h3 {'Exporter'}
    H.p {'Téléchargez la définition complète de l\'application sous forme de fichier YAML.'}
    H.div {class: 'snapshot-export-options',
      H.label {
        H.input {id: 'snapshot-compress-checkbox', type: 'checkbox', value: 'compress'}
        H.span {' Compresser (zstd) - recommandé pour les exports avec données'}
      }
    }
    H.div {class: 'snapshot-export-btns',
      H.button {id: 'snapshot-export-schema-btn', class: 'toolbar-btn', '⬇ Structure seule'}
      H.button {id: 'snapshot-export-full-btn',   class: 'toolbar-btn', '⬇ Structure + données'}
    }
  }

_snapshotImportBox = ->
  H.div {class: 'snapshot-import-box',
    H.h3 {'Importer'}
    H.p {'Importez un fichier .tdb.yaml exporté depuis TGui.'}
    H.div {class: 'snapshot-import-file-row',
      H.label {['for']: 'snapshot-file-input', class: 'toolbar-btn', '📂 Choisir un fichier'}
      H.input {id: 'snapshot-file-input', type: 'file', accept: '.yaml,.yml,.tdb.yaml,.zst,.tdb.yaml.zst', class: 'hidden'}
      H.span {id: 'snapshot-file-name', class: 'snapshot-file-name', ''}
    }
    H.div {id: 'snapshot-diff-box', class: 'hidden snapshot-diff-box',
      H.h4 {'Modifications détectées'}
      H.div {id: 'snapshot-diff-content', ''}
      H.div {class: 'snapshot-import-mode',
        H.label {
          H.input {id: 'snapshot-mode-merge', type: 'radio', name: 'snapshot-mode', value: 'merge', checked: true}
          H.span {' Fusion (recommandé) — crée ce qui manque, ignore l\'existant'}
        }
        H.label {
          H.input {id: 'snapshot-mode-replace', type: 'radio', name: 'snapshot-mode', value: 'replace'}
          H.span {' Remplacement — efface tout puis recrée'}
        }
      }
      H.p {id: 'snapshot-import-error', class: 'error hidden', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'snapshot-import-confirm-btn', class: 'toolbar-btn', '⬆ Importer'}
      }
    }
    H.div {id: 'snapshot-import-result', class: 'hidden snapshot-import-result', ''}
  }

_adminSnapshotSection = ->
  H.div {id: 'admin-snapshot-section', class: 'hidden',
    H.div {class: 'admin-section-header',
      H.h2 {'Export / Import'}
    }
    _snapshotExportBox!
    _snapshotImportBox!
  }

make_admin_panel = ->
  H.div {id: 'admin-panel', class: 'hidden admin-panel',
    _adminUsersSection!
    _adminGroupsSection!
    _adminSnapshotSection!
  }

make_content = ->
  H.main {id: 'content',
    H.div {id: 'default-password-warning', class: 'warning-banner hidden',
      '⚠ Vous utilisez le mot de passe par défaut. '
      H.button {id: 'warning-change-password-btn', 'Changer maintenant'}
    }
    make_toolbar!
    make_yaml_toolbar!
    H.div {id: 'content-row',
      H.div {id: 'grid-container', ''}
      H.div {id: 'custom-view-container', class: 'hidden', ''}
      make_fields_panel!
    }
    make_admin_panel!
    make_welcome_screen!
  }
_changePasswordDialog = ->
  H.div {id: 'change-password-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box',
      H.h2 {'Changer le mot de passe'}
      H.input {id: 'cp-current', type: 'password', placeholder: 'Mot de passe actuel'}
      H.input {id: 'cp-new', type: 'password', placeholder: 'Nouveau mot de passe'}
      H.input {id: 'cp-confirm', type: 'password', placeholder: 'Confirmer le nouveau'}
      H.p {id: 'cp-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cp-submit-btn', 'Enregistrer'}
        H.button {id: 'cp-cancel-btn', 'Annuler'}
      }
    }
  }

_createUserDialog = ->
  H.div {id: 'create-user-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box',
      H.h2 {'Créer un utilisateur'}
      H.input {id: 'cu-username', type: 'text',     placeholder: "Nom d'utilisateur"}
      H.input {id: 'cu-email',    type: 'email',    placeholder: 'Email (optionnel)'}
      H.input {id: 'cu-password', type: 'password', placeholder: 'Mot de passe'}
      H.p {id: 'cu-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cu-submit-btn', 'Créer'}
        H.button {id: 'cu-cancel-btn', 'Annuler'}
      }
    }
  }

_createGroupDialog = ->
  H.div {id: 'create-group-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box',
      H.h2 {'Créer un groupe'}
      H.input {id: 'cg-name',        type: 'text', placeholder: 'Nom du groupe'}
      H.input {id: 'cg-description', type: 'text', placeholder: 'Description (optionnel)'}
      H.p {id: 'cg-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cg-submit-btn', 'Créer'}
        H.button {id: 'cg-cancel-btn', 'Annuler'}
      }
    }
  }

_yamlModal = ->
  H.div {id: 'yaml-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {id: 'yaml-modal-title', class: 'modal-title', ''}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'yaml-modal-preview-btn', class: 'toolbar-btn', '▶ Aperçu'}
          H.button {id: 'yaml-modal-save-btn', class: 'btn-primary', '💾 Enregistrer'}
          H.button {id: 'yaml-modal-close-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {class: 'yaml-modal-body',
        H.div {class: 'yaml-editor-pane',
          H.div {id: 'yaml-cm-editor', ''}
          H.div {id: 'yaml-validation-msg', class: 'yaml-validation-msg hidden', ''}
        }
        H.div {id: 'schema-browser', class: 'schema-browser', ''}
      }
    }
  }

_widgetPluginModal = ->
  H.div {id: 'widget-plugin-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Plugins widgets'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'widget-plugin-new-btn', class: 'toolbar-btn', '＋ Nouveau'}
          H.button {id: 'widget-plugin-delete-btn', class: 'toolbar-btn toolbar-btn--danger', '🗑 Supprimer'}
          H.button {id: 'widget-plugin-save-btn', class: 'btn-primary', '💾 Enregistrer'}
          H.button {id: 'widget-plugin-modal-close-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {class: 'yaml-modal-body widget-plugin-modal-body',
        H.div {class: 'yaml-editor-pane',
          H.div {class: 'widget-plugin-meta-row',
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-select', 'Plugins existants'}
              H.select {id: 'widget-plugin-select', ''}
            }
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-name', 'Nom'}
              H.input {id: 'widget-plugin-name', type: 'text', placeholder: 'my_widget_plugin'}
            }
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-description', 'Description'}
              H.input {id: 'widget-plugin-description', type: 'text', placeholder: 'Description'}
            }
          }
          H.div {class: 'widget-plugin-editors-row',
            H.div {class: 'widget-plugin-editor-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-template-language', 'Template language'}
              H.select {id: 'widget-plugin-template-language',
                H.option {value: 'pug', 'Pug'}
                H.option {value: 'html', 'HTML'}
              }
              H.label {class: 'formula-hint', 'Template'}
              H.div {id: 'widget-plugin-template-editor', style: 'border: 1px solid #2a2a2a;', ''}
            }
            H.div {class: 'widget-plugin-editor-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-script-language', 'Script language'}
              H.select {id: 'widget-plugin-script-language',
                H.option {value: 'coffeescript', 'CoffeeScript'}
                H.option {value: 'javascript', 'JavaScript'}
              }
              H.label {class: 'formula-hint', 'Script'}
              H.div {id: 'widget-plugin-script-editor', style: 'border: 1px solid #2a2a2a;', ''}
            }
          }
        }
      }
    }
  }

_formulaModal = ->
  H.div {id: 'formula-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Éditeur de formule'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'formula-modal-apply-btn', class: 'btn-primary', 'Appliquer'}
          H.button {id: 'formula-modal-close-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {id: 'formula-cm-editor', ''}
    }
  }

make_modals = ->
  H.div {
    _changePasswordDialog!
    _createUserDialog!
    _createGroupDialog!
    _yamlModal!
    _widgetPluginModal!
    _formulaModal!
  }

_dataViewTabFields = ->
  H.div {id: 'dv-tab-fields', class: 'dv-tab-content',
    H.div {class: 'dv-fields-layout',
      H.div {class: 'dv-fields-left',
        H.h4 {'Sélectionnez les champs et jointures'}
        H.div {id: 'dv-joins-graph-container', class: 'joins-graph-container',
          H.div {class: 'joins-placeholder', 'Sélectionnez un espace source pour voir les relations...'}
        }
      }
      H.div {class: 'dv-fields-right',
        H.h4 {'Champs sélectionnés'}
        H.div {id: 'dv-selected-fields', class: 'selected-fields-list',
          H.div {class: 'field-placeholder', 'Aucun champ sélectionné'}
        }
        H.div {class: 'dv-fields-info',
          H.small {'Cliquez sur les champs dans le graphe pour les ajouter à la vue'}
        }
      }
    }
  }

_dataViewTabFilter = ->
  H.div {id: 'dv-tab-filter', class: 'dv-tab-content hidden'},
    H.div {class: 'config-row',
      H.label {'Filtre MoonScript:'},
      H.textarea {id: 'dv-filter-formula', rows: '6', placeholder: '@age > 18 and @status == "active"', ''}
    }

_dataViewTabGroup = ->
  H.div {id: 'dv-tab-group', class: 'dv-tab-content hidden',
    H.div {class: 'config-row',
      H.label {'Groupement par:'},
      H.div {id: 'dv-groupby-fields', class: 'fields-container',
        H.div {class: 'field-group',
          H.h5 {'Champs disponibles'},
          H.div {id: 'dv-groupby-available', class: 'fields-list',
            H.div {class: 'field-placeholder', 'Sélectionnez un espace...'}
          }
        }
        H.div {class: 'field-group',
          H.h5 {'Groupement'},
          H.div {id: 'dv-groupby-selected', class: 'fields-list selected',
            H.div {class: 'field-placeholder', 'Aucun groupement'}
          }
        }
      }
    }
    H.div {class: 'config-row',
      H.label {'Agrégats:'},
      H.div {id: 'dv-aggregates-list', class: 'dv-list', ''},
      H.button {id: 'dv-add-agg-btn', class: 'toolbar-btn', '＋ Ajouter agrégat'}
    }
  }

_dataViewModalHeader = ->
  H.div {class: 'modal-editor-header',
    H.span {class: 'modal-title', id: 'data-view-modal-title', 'Configuration de la vue'},
    H.div {class: 'modal-editor-actions',
      H.button {class: 'btn-primary', id: 'data-view-save-btn', '💾 Enregistrer'},
      H.button {class: 'toolbar-btn', id: 'data-view-modal-close-btn', '✕'}
    }
  }

_dataViewModalMainConfig = ->
  H.div {class: 'dv-main-config',
    H.div {class: 'config-row',
      H.label {['for']: 'dv-name', 'Nom :'},
      H.input {id: 'dv-name', type: 'text', placeholder: 'Ma vue'}
    }
    H.div {class: 'config-row',
      H.label {['for']: 'dv-source', 'Source :'},
      H.select {id: 'dv-source', ''}
    }
  }

_dataViewModalYamlEditor = ->
  H.div {class: 'dv-yaml-editor',
    H.h4 {'Requête YAML'},
    H.div {id: 'dv-yaml-editor-container', class: 'yaml-editor-container',
      H.textarea {id: 'dv-yaml-content', class: 'yaml-editor', placeholder: '# Définissez votre vue ici', ''}
    }
    H.div {class: 'yaml-editor-actions',
      H.button {id: 'dv-format-yaml-btn', class: 'toolbar-btn', '🎨 Formater'},
      H.button {id: 'dv-apply-yaml-btn', class: 'btn-primary', '✓ Appliquer YAML'}
    }
  }

_dataViewModalVisualEditor = ->
  H.div {class: 'dv-visual-editor',
    H.div {class: 'dv-config-tabs',
      H.button {class: 'tab-btn active', ['data-tab']: 'fields', 'Champs'},
      H.button {class: 'tab-btn', ['data-tab']: 'filter', 'Filtre'},
      H.button {class: 'tab-btn', ['data-tab']: 'group', 'Groupement'}
    }
    H.div {class: 'dv-tabs-content',
      _dataViewTabFields!
      _dataViewTabFilter!
      _dataViewTabGroup!
    }
  }

_dataViewModalSplitLayout = ->
  H.div {class: 'dv-split-layout',
    _dataViewModalYamlEditor!
    _dataViewModalVisualEditor!
  }

_dataViewModal = ->
  H.div {id: 'data-view-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor modal-box--large',
      _dataViewModalHeader!
      H.div {class: 'data-view-modal-body',
        _dataViewModalMainConfig!
        _dataViewModalSplitLayout!
      }
    }
  }

_widgetConfigRow = (labelText, inputElement) ->
  H.div {class: 'config-row',
    H.label {labelText}
    inputElement
  }

_widgetTitleInput = ->
  H.input {type: 'text', id: 'widget-title-input', placeholder: 'Mon widget', class: 'widget-input'}

_widgetSpaceSelect = ->
  H.select {id: 'widget-space-select', class: 'widget-select',
    H.option {value: '', 'Sélectionner un espace...'}
  }

_widgetFieldsContainer = ->
  H.div {id: 'widget-fields-container', class: 'fields-container',
    H.div {class: 'fields-header',
      H.div {class: 'field-group', 'Disponibles:'}
      H.div {class: 'field-group', 'Sélectionnées:'}
    }
    H.div {class: 'fields-lists',
      H.div {id: 'available-fields', class: 'fields-list',
        H.div {class: 'field-placeholder', 'Sélectionnez un espace...'}
      }
      H.div {id: 'selected-fields', class: 'fields-list selected',
        H.div {class: 'field-placeholder', 'Aucun champ sélectionné'}
      }
    }
  }

_widgetGroupBySelect = ->
  H.select {id: 'widget-groupby-select', class: 'widget-select',
    H.option {value: '', 'Aucun groupement'}
  }

_widgetTypeOption = (value, label, checked = false) ->
  H.div {class: 'widget-type-option',
    H.input {type: 'radio', name: 'widget-type', value: value, id: "widget-type-#{value}", checked: checked}
    H.label {['for']: "widget-type-#{value}", label}
  }

_widgetParamRow = ->
  H.div {class: 'param-row',
    H.input {type: 'text', placeholder: 'Clé', class: 'param-key'}
    H.input {type: 'text', placeholder: 'Valeur', class: 'param-value'}
    H.button {type: 'button', class: 'param-remove-btn', '✕'}
  }

_widgetDataSourceSection = ->
  H.div {class: 'widget-section',
    H.h3 {'1. Source de données'}
    H.div {class: 'data-source-config',
      _widgetConfigRow('Titre du widget:', _widgetTitleInput!)
      _widgetConfigRow('Espace:', _widgetSpaceSelect!)
      _widgetConfigRow('Colonnes à afficher:', _widgetFieldsContainer!)
    }
  }

_widgetTypeSection = ->
  H.div {class: 'widget-section',
    H.h3 {'2. Type de widget'}
    H.div {class: 'widget-type-config',
      H.div {class: 'widget-type-options',
        _widgetTypeOption('table', 'Tableau simple', true)
      }
    }
  }

_widgetParamsSection = ->
  H.div {class: 'widget-section',
    H.h3 {'3. Paramètres du widget'}
    H.div {class: 'widget-params-config',
      H.div {id: 'widget-params-list', class: 'params-list',
        _widgetParamRow!
      }
      H.button {id: 'add-param-btn', class: 'btn-secondary', '+ Ajouter un paramètre'}
    }
  }

_addWidgetModal = ->
  H.div {id: 'add-widget-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Ajouter un widget'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'add-widget-confirm-btn', class: 'btn-primary', 'Ajouter'}
          H.button {id: 'add-widget-cancel-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {class: 'add-widget-modal-body',
        _widgetDataSourceSection!
        _widgetTypeSection!
        _widgetParamsSection!
      }
    }
  }

make_body = ->
  H.body {
    H.div {id: 'app',
      make_login_overlay!
      H.div {id: 'main', class: 'hidden',
        make_sidebar!
        make_content!
      }
    }
    make_modals!
    _addWidgetModal!
    _dataViewModal!
    H.script { [[
      if (localStorage.getItem('tdb_token')) {
        const overlay = document.getElementById('login-overlay');
        const main = document.getElementById('main');
        if (overlay) overlay.classList.add('hidden');
        if (main) {
          main.classList.remove('hidden');
          if (localStorage.getItem('tdb_menu_state') === 'collapsed') {
            main.classList.add('sidebar-collapsed');
          }
        }
      }
    ]] }
    H.script {src: '/vendor/tui-grid.bundle.js', ''}
    H.script {src: '/vendor/jsyaml.bundle.js', ''}
    H.script {src: '/vendor/codemirror.bundle.js', ''}
    H.script {src: '/vendor/plugin-runtime.bundle.js', ''}
    H.script {src: '/src/i18n.js', ''}
    H.script {src: '/src/modal.js', ''}
    H.script {src: '/src/graphql_client.js', ''}
    H.script {src: '/src/auth.js', ''}
    H.script {src: '/src/spaces.js', ''}
    H.script {src: '/src/data_views.js', ''}
    H.script {src: '/src/widget_plugins.js', ''}
    H.script {src: '/src/app_fields_helpers.js', ''}
    H.script {src: '/src/app_sidebar_helpers.js', ''}
    H.script {src: '/src/app_undo_helpers.js', ''}
    H.script {src: '/src/drag_drop_manager.js', ''}
    H.script {src: '/src/app_data_helpers.js', ''}
    H.script {src: '/src/app_view_helpers.js', ''}
    H.script {src: '/src/app_view_config_helpers.js', ''}
    H.script {src: '/src/app_snapshot_helpers.js', ''}
    H.script {src: '/src/views/data_view.js', ''}
    H.script {src: '/src/views/custom_view.js', ''}
    H.script {src: '/src/yaml_builder.js', ''}
    H.script {src: '/src/app.js', ''}
  }

_html = nil

render = ->
  return _html if _html
  doc = H.html {lang: 'fr',
    make_head!
    make_body!
  }
  _html = "<!DOCTYPE html>\n" .. doc
  _html

-- Test code (only executed when run directly)
if arg and arg[1] == "--test"
  print render!

return render
