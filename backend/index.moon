-- backend/index.moon
-- Génère dynamiquement la page HTML principale de tdb.
-- Utilise backend/html.lua pour construire l'arbre HTML sans concaténation manuelle.

H = require 'html'

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
}

-- Construit le <select> des types de champs.
field_type_select = ->
  opts = {id: 'field-type'}
  for {val, label} in *FIELD_TYPE_OPTIONS
    table.insert opts, H.option({value: val}, label)
  H.select opts

-- Section <head>
make_head = ->
  H.head {
    H.meta {charset: 'UTF-8'}
    H.meta {name: 'viewport', content: 'width=device-width, initial-scale=1.0'}
    H.title {'tdb'}
    H.link {rel: 'icon', href: ICON}
    H.link {rel: 'stylesheet', href: '/vendor/tui-grid.bundle.css'}
    H.link {rel: 'stylesheet', href: '/css/app.css'}
  }

-- Overlay de connexion
make_login_overlay = ->
  H.div {id: 'login-overlay', class: 'overlay',
    H.div {class: 'login-box',
      H.h1 {'tdb'}
      H.input {id: 'login-username', type: 'text',     placeholder: "Nom d'utilisateur"}
      H.input {id: 'login-password', type: 'password', placeholder: 'Mot de passe'}
      H.button {id: 'login-btn', 'Connexion'}
      H.p {id: 'login-error', class: 'error', ''}
    }
  }

-- Barre latérale
make_sidebar = ->
  H.nav {id: 'sidebar',
    H.div {class: 'sidebar-header',
      H.span {class: 'logo', 'tdb'}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.span {'Données'}
        H.button {id: 'new-space-btn', title: 'Nouvel espace', '＋'}
      }
      H.ul {id: 'space-list', ''}
    }
    H.div {class: 'sidebar-section',
      H.div {class: 'sidebar-section-title',
        H.span {'Vues'}
        H.button {id: 'new-view-btn', title: 'Nouvelle vue', '＋'}
      }
      H.ul {id: 'custom-view-list', ''}
    }
    H.div {class: 'sidebar-footer',
      H.span {id: 'current-user', ''}
      H.button {id: 'logout-btn', 'Déconnexion'}
    }
  }

-- Panneau latéral de gestion des champs et relations
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
      H.button {id: 'field-add-btn', 'Ajouter'}
    }
    H.div {class: 'relations-section-header',
      H.span {'Relations'}
    }
    H.ul {id: 'relations-list', ''}
    H.div {class: 'relations-add-form',
      H.input {id: 'rel-name', type: 'text', placeholder: 'Nom de la relation'}
      H.select {id: 'rel-from-field',
        H.option {value: '', 'Champ source…'}
      }
      H.select {id: 'rel-to-space',
        H.option {value: '', 'Espace cible…'}
      }
      H.select {id: 'rel-to-field',
        H.option {value: '', 'Champ cible…'}
      }
      H.button {id: 'rel-add-btn', 'Lier'}
    }
  }

-- Zone de contenu principale
make_content = ->
  H.main {id: 'content',
    H.div {id: 'data-toolbar', class: 'hidden',
      H.span {id: 'data-title', class: 'content-title', ''}
      H.button {id: 'delete-rows-btn', class: 'toolbar-btn toolbar-btn--danger', '🗑 Supprimer'}
      H.button {id: 'fields-btn', class: 'fields-btn', '⊞ Champs'}
    }
    H.div {id: 'yaml-editor-panel', class: 'hidden',
      H.div {class: 'yaml-editor-toolbar',
        H.span {id: 'yaml-view-name', class: 'content-title', ''}
        H.button {id: 'yaml-edit-btn', class: 'toolbar-btn', '✎ Éditer la vue'}
        H.button {id: 'yaml-save-btn', '💾 Enregistrer'}
        H.button {id: 'yaml-preview-btn', '▶ Aperçu'}
        H.button {id: 'yaml-close-editor-btn', class: 'toolbar-btn', "✕ Fermer l'éditeur"}
        H.button {id: 'yaml-delete-btn', '🗑 Supprimer la vue'}
      }
      H.textarea {id: 'yaml-editor', spellcheck: 'false', ''}
    }
    H.div {id: 'content-row',
      H.div {id: 'grid-container', ''}
      H.div {id: 'custom-view-container', class: 'hidden', ''}
      make_fields_panel!
    }
    H.div {id: 'welcome', class: 'welcome',
      H.p {'Sélectionnez un espace ou une vue dans la barre latérale.'}
    }
  }

-- <body> complet avec scripts
make_body = ->
  H.body {
    H.div {id: 'app',
      make_login_overlay!
      H.div {id: 'main', class: 'hidden',
        make_sidebar!
        make_content!
      }
    }
    H.script {src: '/vendor/tui-grid.bundle.js', ''}
    H.script {src: '/vendor/jsyaml.bundle.js', ''}
    H.script {src: '/src/graphql_client.js', ''}
    H.script {src: '/src/auth.js', ''}
    H.script {src: '/src/spaces.js', ''}
    H.script {src: '/src/views/data_view.js', ''}
    H.script {src: '/src/views/custom_view.js', ''}
    H.script {src: '/src/app.js', ''}
  }

_html = nil

-- Génère (et met en cache) la page HTML complète.
render = ->
  return _html if _html
  doc = H.html {lang: 'fr',
    make_head!
    make_body!
  }
  _html = "<!DOCTYPE html>\n" .. doc
  _html

{ :render }
