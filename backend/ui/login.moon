-- backend/ui/login.moon
-- Login overlay of the SPA (extracted from backend/index.moon, no functional change).

H = require 'html'

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

{
  make_login_overlay: make_login_overlay
}
