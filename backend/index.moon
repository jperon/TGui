#!/usr/bin/env moon
-- backend/index.moon
-- Dynamically generates the main TGui HTML page.
-- Uses backend/html.lua to build the HTML tree without manual string concatenation.

H = require 'html'

-- Constantes
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

-- Fonctions utilitaires
buildFieldTypeSelect = (selectedValue = 'String', fieldId) ->
  H.select {id: fieldId, name: fieldId, class: 'field-type-select'},
    for option in FIELD_TYPE_OPTIONS
      isSelected = option[1] == selectedValue
      H.option {value: option[1], selected: isSelected}, option[1]

-- Fonctions auxiliaires pour les éléments de l'interface
_navbar = ->
  H.nav {class: 'sidebar',
    H.div {class: 'sidebar-header',
      H.div {class: 'app-title', H.img {src: ICON, class: 'app-icon'}, H.span {'TGui'}}
      H.button {class: 'sidebar-toggle', '≡'}
    }
    H.div {class: 'sidebar-content',
      _sidebarSection 'Vues', 'add-view-btn'
      _sidebarSection 'Données', 'add-space-btn', {
        H.a {href: '#/data/Auteurs', 'Auteurs'}
        H.a {href: '#/data/Categories', 'Categories'}
        H.a {href: '#/data/Emprunts', 'Emprunts'}
        H.a {href: '#/data/Livres', 'Livres'}
      }
      _sidebarSection 'Plugins widgets', 'add-plugin-btn', {
        H.a {href: '#/plugins', 'Gestion des plugins'}
      }
      _sidebarSection 'Administration', null, {
        H.a {href: '#/users', 'Utilisateurs'}
        H.a {href: '#/groups', 'Groupes'}
        H.a {href: '#/export', 'Export / Import'}
      }
    }
    H.button {class: 'user-menu', 'admin'}
  }

_sidebarSection = (title, buttonId, items = {}) ->
  H.div {class: 'sidebar-section',
    H.div {class: 'section-header',
      H.span {class: 'section-title', title}
      buttonId and H.button{id: buttonId, class: 'section-add-btn', '＋'} or ""
    }
    (items and #items > 0 and H.ul{class: 'section-list', [H.li{class: 'section-item', item} for item in *items]} or "")
  }

_mainContent = ->
  H.main {id: 'main', class: 'sidebar-collapsed',
    _passwordWarning!
    _welcomeMessage!
    _changePasswordDialog!
    _createUserDialog!
    _createGroupDialog!
    _snapshotImportDialog!
    _yamlModal!
    _widgetPluginModal!
    _formulaModal!
    _addWidgetModal!
    _antiFlickerScript!
  }

_passwordWarning = ->
  H.div {class: 'password-warning',
    H.p {'⚠ Vous utilisez le mot de passe par défaut.'}
    H.button {'Changer maintenant'}
  }

_welcomeMessage = ->
  H.div {id: 'welcome', class: 'welcome',
    H.p {'Sélectionnez un espace ou une vue dans la barre latérale.'}
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
      H.input {id: 'cu-username', type: 'text', placeholder: "Nom d'utilisateur"}
      H.input {id: 'cu-email', type: 'email', placeholder: 'Email (optionnel)'}
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
      H.input {id: 'cg-name', type: 'text', placeholder: 'Nom du groupe'}
      H.input {id: 'cg-description', type: 'text', placeholder: 'Description (optionnel)'}
      H.p {id: 'cg-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cg-submit-btn', 'Créer'}
        H.button {id: 'cg-cancel-btn', 'Annuler'}
      }
    }
  }

_snapshotImportDialog = ->
  H.div {id: 'snapshot-import-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Importer une vue'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'snapshot-import-confirm-btn', class: 'toolbar-btn', '⬆ Importer'}
        }
      }
      H.div {class: 'yaml-modal-body',
        H.div {class: 'yaml-editor-pane',
          H.div {id: 'snapshot-import-cm-editor'}
        }
        H.div {id: 'snapshot-import-schema-browser', class: 'schema-browser'}
      }
      H.div {class: 'snapshot-import-options',
        H.div {class: 'import-mode',
          H.p {'Mode d\'importation :'}
          H.label {},
            H.input {id: 'snapshot-mode-merge', type: 'radio', name: 'snapshot-mode', value: 'merge', checked: true}
            H.span {' Fusion (recommandé) — crée ce qui manque, ignore l\'existant'}
          H.label {},
            H.input {id: 'snapshot-mode-replace', type: 'radio', name: 'snapshot-mode', value: 'replace'}
            H.span {' Remplacement — '}
            H.strong {'efface toutes les données existantes'}
            H.span {' puis recrée'}
        }
        H.p {id: 'snapshot-import-error', class: 'error hidden', ''}
      }
      H.div {id: 'snapshot-import-result', class: 'hidden snapshot-import-result', ''}
    }
  }

_yamlModal = ->
  H.div {id: 'yaml-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', id: 'yaml-modal-title'}
        H.div {class: 'modal-editor-actions',
          H.button {class: 'toolbar-btn', id: 'yaml-modal-preview-btn', '▶ Aperçu'}
          H.button {class: 'btn-primary', id: 'yaml-modal-save-btn', '💾 Enregistrer'}
          H.button {class: 'toolbar-btn', id: 'yaml-modal-close-btn', '✕'}
        }
      }
      H.div {class: 'yaml-modal-body',
        H.div {class: 'yaml-editor-pane',
          H.div {id: 'yaml-cm-editor'}
          H.div {class: 'yaml-validation-msg hidden', id: 'yaml-validation-msg'}
        }
        H.div {class: 'schema-browser', id: 'schema-browser'}
      }
    }
  }

_widgetPluginModal = ->
  H.div {id: 'widget-plugin-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Plugins widgets'}
        H.div {class: 'modal-editor-actions',
          H.button {class: 'toolbar-btn', id: 'widget-plugin-new-btn', '＋ Nouveau'}
          H.button {class: 'toolbar-btn toolbar-btn--danger', id: 'widget-plugin-delete-btn', '🗑 Supprimer'}
          H.button {class: 'btn-primary', id: 'widget-plugin-save-btn', '💾 Enregistrer'}
          H.button {class: 'toolbar-btn', id: 'widget-plugin-modal-close-btn', '✕'}
        }
      }
      H.div {class: 'yaml-modal-body widget-plugin-modal-body',
        H.div {class: 'widget-plugin-meta-row',
          H.div {class: 'widget-plugin-meta-col',
            H.label {['for']: 'widget-plugin-select', class: 'formula-hint', 'Plugins existants'}
            H.select {id: 'widget-plugin-select'}
          }
          H.div {class: 'widget-plugin-meta-col',
            H.label {['for']: 'widget-plugin-name', class: 'formula-hint', 'Nom'}
            H.input {id: 'widget-plugin-name', type: 'text', placeholder: 'my_widget_plugin'}
          }
          H.div {class: 'widget-plugin-meta-col',
            H.label {['for']: 'widget-plugin-description', class: 'formula-hint', 'Description'}
            H.input {id: 'widget-plugin-description', type: 'text', placeholder: 'Description'}
          }
        }
        H.div {class: 'widget-plugin-editors-row',
          H.div {class: 'widget-plugin-editor-col',
            H.label {['for']: 'widget-plugin-template-language', class: 'formula-hint', 'Template language'}
            H.select {id: 'widget-plugin-template-language',
              H.option {value: 'pug', 'Pug'}
              H.option {value: 'html', 'HTML'}
            }
            H.label {class: 'formula-hint', 'Template'}
            H.div {style: 'border: 1px solid #2a2a2a;', id: 'widget-plugin-template-editor'}
          }
          H.div {class: 'widget-plugin-editor-col',
            H.label {['for']: 'widget-plugin-script-language', class: 'formula-hint', 'Script language'}
            H.select {id: 'widget-plugin-script-language',
              H.option {value: 'coffeescript', 'CoffeeScript'}
              H.option {value: 'javascript', 'JavaScript'}
            }
            H.label {class: 'formula-hint', 'Script'}
            H.div {style: 'border: 1px solid #2a2a2a;', id: 'widget-plugin-script-editor'}
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
          H.button {class: 'btn-primary', id: 'formula-modal-apply-btn', 'Appliquer'}
          H.button {class: 'toolbar-btn', id: 'formula-modal-close-btn', '✕'}
        }
      }
      H.div {id: 'formula-cm-editor'}
    }
  }

_antiFlickerScript = ->
  H.script {[[
    if (localStorage.getItem('tdb_token')) {
      document.getElementById('login-overlay').classList.add('hidden');
      document.getElementById('main').classList.remove('hidden');
      if (localStorage.getItem('tdb_menu_state') === 'collapsed') {
        document.getElementById('main').classList.add('sidebar-collapsed');
      }
    }
  ]]}

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
    -- Note: Les espaces seront chargés dynamiquement via JavaScript
    -- car ils nécessitent un appel à la base de données Tarantool
  }

_widgetFieldsContainer = ->
  H.div {id: 'widget-fields-container', class: 'fields-container',
    H.div {class: 'fields-header',
      H.div {class: 'field-group', 'Disponibles:'}
      H.div {class: 'field-group', 'Sélectionnées:'}
    }
    H.div {class: 'fields-lists',
      H.div {id: 'available-fields', class: 'fields-list',
        -- Note: Les champs seront chargés dynamiquement via JavaScript
        -- après sélection d'un espace
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

-- Sections principales de la modale
_widgetDataSourceSection = ->
  H.div {class: 'widget-section',
    H.h3 {'1. Source de données'}
    H.div {class: 'data-source-config',
      _widgetConfigRow('Titre du widget:', _widgetTitleInput!)
      _widgetConfigRow('Espace:', _widgetSpaceSelect!)
      _widgetConfigRow('Colonnes à afficher:', _widgetFieldsContainer!)
      _widgetConfigRow('Groupement (GROUP BY):', _widgetGroupBySelect!)
    }
  }

_widgetTypeSection = ->
  H.div {class: 'widget-section',
    H.h3 {'2. Type de widget'}
    H.div {class: 'widget-type-config',
      H.div {class: 'widget-type-options',
        _widgetTypeOption('table', 'Tableau simple', true)
      }
      H.div {class: 'widget-type-note',
        H.p {'Pour l\'instant, seul le type "Tableau simple" est implémenté.'}
        H.p {'Les autres types (Graphique, Compteur, etc.) seront ajoutés plus tard.'}
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

-- Builds the field-type <select>.
field_type_select = ->
  opts = {id: 'field-type'}
  for {val, label} in *FIELD_TYPE_OPTIONS
    table.insert opts, H.option({value: val}, label)
  H.select opts


-- <head> section
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

-- Login overlay
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

-- Sidebar
make_sidebar = ->
  H.nav {id: 'sidebar',
    H.div {class: 'sidebar-header',
      H.span {class: 'logo', 'TGui'}
      H.button {id: 'sidebar-toggle', class: 'sidebar-toggle-btn', title: 'Replier le menu', '≡'}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.span {'Vues'}
        H.button {id: 'new-view-btn', title: 'Nouvelle vue', '＋'}
      }
      H.ul {id: 'custom-view-list', ''}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.button {id: 'spaces-toggle-btn', class: 'section-toggle-btn', '▾'}
        H.span {'Données'}
        H.button {id: 'new-space-btn', title: 'Nouvel espace', '＋'}
      }
      H.ul {id: 'space-list', ''}
    }
    H.div {id: 'plugins-sidebar-section', class: 'sidebar-section hidden',
      H.div {class: 'sidebar-section-title',
        H.span {'Plugins widgets'}
      }
      H.ul {class: 'plugins-nav-list',
        H.li {id: 'plugins-nav-manage', 'Gestion des plugins'}
      }
    }
    H.div {id: 'admin-sidebar-section', class: 'sidebar-section hidden',
      H.div {class: 'sidebar-section-title',
        H.span {'Administration'}
      }
      H.ul {class: 'admin-nav-list',
        H.li {id: 'admin-nav-users', 'Utilisateurs'}
        H.li {id: 'admin-nav-groups', 'Groupes'}
        H.li {id: 'admin-nav-snapshot', 'Export / Import'}
      }
    }
    H.div {class: 'sidebar-footer',
      H.button {id: 'current-user-btn', class: 'current-user-btn', ''}
      H.div {id: 'user-menu', class: 'user-menu hidden',
        H.button {id: 'change-password-btn', ['data-i18n']: 'ui.menu.changePassword', 'Changer le mot de passe'}
        H.button {id: 'logout-btn', ['data-i18n']: 'ui.menu.logout', 'Déconnexion'}
        H.div {class: 'menu-lang-row',
          H.button {id: 'lang-fr-btn', class: 'toolbar-btn', ['data-i18n']: 'ui.menu.langFr', 'FR'}
          H.button {id: 'lang-en-btn', class: 'toolbar-btn', ['data-i18n']: 'ui.menu.langEn', 'EN'}
        }
      }
    }
  }

-- Side panel for field management
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
      H.div {id: 'field-repr-section',
        H.label {class: 'formula-hint', ['for']: 'field-repr-formula', 'Représentation (affichage) :'}
        H.textarea {id: 'field-repr-formula', rows: '2',
          placeholder: "Ex: os.date('%d/%m/%Y', self.date) ou string.format('%.2f', self.montant)", ''}
        H.span {class: 'formula-hint', 'Formule MoonScript/Lua de rendu visuel (ne modifie pas la donnée brute).'}
      }
      H.div {class: 'fields-form-actions',
        H.button {id: 'field-add-btn', 'Ajouter'}
        H.button {id: 'field-cancel-btn', class: 'hidden', 'Annuler'}
      }
    }
  }

-- Main content area
make_content = ->
  H.main {id: 'content',
    -- Default-password warning banner
    H.div {id: 'default-password-warning', class: 'warning-banner hidden',
      '⚠ Vous utilisez le mot de passe par défaut. '
      H.button {id: 'warning-change-password-btn', 'Changer maintenant'}
    }
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
    H.div {id: 'yaml-editor-panel', class: 'hidden',
      H.div {class: 'yaml-editor-toolbar',
        H.span {id: 'yaml-view-name', class: 'content-title', ''}
        H.button {id: 'yaml-edit-btn', class: 'toolbar-btn', '✎ Éditer'}
        H.button {id: 'yaml-add-widget-btn', class: 'toolbar-btn', '＋ Widget'}
        H.button {id: 'yaml-delete-btn', class: 'toolbar-btn toolbar-btn--danger', title: 'Supprimer la vue', '🗑'}
      }
    }
    H.div {id: 'content-row',
      H.div {id: 'grid-container', ''}
      H.div {id: 'custom-view-container', class: 'hidden', ''}
      make_fields_panel!
    }
    -- Admin panel (users + groups)
    H.div {id: 'admin-panel', class: 'hidden admin-panel',
      H.div {id: 'admin-users-section',
        H.div {class: 'admin-section-header',
          H.h2 {'Utilisateurs'}
          H.button {id: 'admin-create-user-btn', class: 'toolbar-btn', '＋ Créer'}
        }
        H.ul {id: 'admin-users-list', ''}
      }
      H.div {id: 'admin-groups-section', class: 'hidden',
        H.div {class: 'admin-section-header',
          H.h2 {'Groupes'}
          H.button {id: 'admin-create-group-btn', class: 'toolbar-btn', '＋ Créer'}
        }
        H.ul {id: 'admin-groups-list', ''}
      }
      H.div {id: 'admin-snapshot-section', class: 'hidden',
        H.div {class: 'admin-section-header',
          H.h2 {'Export / Import'}
        }
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
        H.div {class: 'snapshot-import-box',
          H.h3 {'Importer'}
          H.p {'Importez un fichier .tdb.yaml exporté depuis TGui. Les fichiers compressés (.zst) sont automatiquement détectés.'}
          H.div {class: 'snapshot-import-file-row',
            H.label {for: 'snapshot-file-input', class: 'toolbar-btn', '📂 Choisir un fichier'}
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
                H.span {' Remplacement — '}
                H.strong {'efface toutes les données existantes'}
                H.span {' puis recrée'}
              }
            }
            H.p {id: 'snapshot-import-error', class: 'error hidden', ''}
            H.div {class: 'modal-actions',
              H.button {id: 'snapshot-import-confirm-btn', class: 'toolbar-btn', '⬆ Importer'}
            }
          }
          H.div {id: 'snapshot-import-result', class: 'hidden snapshot-import-result', ''}
        }
      }
    }
    H.div {id: 'welcome', class: 'welcome',
      H.p {'Sélectionnez un espace ou une vue dans la barre latérale.'}
    }
    -- Dialog: change password
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
    -- Dialog: create user (admin)
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
    -- Dialog: create group (admin)
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
    -- Modal: YAML editor (CodeMirror)
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
    -- Modal: widget plugins editor (CodeMirror)
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
                H.div {id: 'widget-plugin-template-editor', style: 'border: 1px solid #2a2a2a;'}
              }
              H.div {class: 'widget-plugin-editor-col',
                H.label {class: 'formula-hint', ['for']: 'widget-plugin-script-language', 'Script language'}
                H.select {id: 'widget-plugin-script-language',
                  H.option {value: 'coffeescript', 'CoffeeScript'}
                  H.option {value: 'javascript', 'JavaScript'}
                }
                H.label {class: 'formula-hint', 'Script'}
                H.div {id: 'widget-plugin-script-editor', style: 'border: 1px solid #2a2a2a;'}
              }
            }
          }
        }
      }
    }
    -- Modal: formula editor (CodeMirror)
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
    -- Modal: Add widget to view (moved to make_body)
  }

-- Full <body> with scripts
make_body = ->
  H.body {
    H.div {id: 'app',
      make_login_overlay!
      H.div {id: 'main', class: 'hidden',
        make_sidebar!
        make_content!
      }
    }
    -- Modal: Add widget to view (outside app structure)
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
    -- Anti-flicker script: immediately show the app shell if a token exists in localStorage
    H.script { [[
      if (localStorage.getItem('tdb_token')) {
        document.getElementById('login-overlay').classList.add('hidden');
        document.getElementById('main').classList.remove('hidden');
        if (localStorage.getItem('tdb_menu_state') === 'collapsed') {
          document.getElementById('main').classList.add('sidebar-collapsed');
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
    H.script {src: '/src/widget_plugins.js', ''}
    H.script {src: '/src/app_fields_helpers.js', ''}
    H.script {src: '/src/app_sidebar_helpers.js', ''}
    H.script {src: '/src/app_undo_helpers.js', ''}
    H.script {src: '/src/app_data_helpers.js', ''}
    H.script {src: '/src/app_view_helpers.js', ''}
    H.script {src: '/src/app_snapshot_helpers.js', ''}
    H.script {src: '/src/views/data_view.js', ''}
    H.script {src: '/src/views/custom_view.js', ''}
    H.script {src: '/src/yaml_builder.js', ''}
    H.script {src: '/src/app.js', ''}
  }

_html = nil

-- Generates (and caches) the complete HTML page.
render = ->
  return _html if _html
  doc = H.html {lang: 'fr',
    make_head!
    make_body!
  }
  _html = "<!DOCTYPE html>\n" .. doc
  _html

if arg[1] == "--test"
  print render!

{ :render }
