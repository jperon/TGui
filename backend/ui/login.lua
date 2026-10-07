local H = require('html')
local make_login_overlay
make_login_overlay = function()
  return H.div({
    id = 'login-overlay',
    class = 'overlay',
    H.div({
      class = 'login-box',
      H.h1({
        ['data-i18n'] = 'ui.login.title',
        'TGui'
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
        ['data-i18n'] = 'ui.login.button',
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
return {
  make_login_overlay = make_login_overlay
}
