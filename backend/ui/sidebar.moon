-- backend/ui/sidebar.moon
-- Sidebar of the SPA (extracted from backend/index.moon, no functional change).

H = require 'html'

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
        H.li {id: 'admin-nav-apps', 'Applications'}
      }
    }
    _sidebarFooter!
  }

{
  make_sidebar: make_sidebar
}
