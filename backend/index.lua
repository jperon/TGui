local H = require('html')
local make_login_overlay
make_login_overlay = require('ui.login').make_login_overlay
local make_sidebar
make_sidebar = require('ui.sidebar').make_sidebar
local make_content
make_content = require('ui.content').make_content
local make_modals
make_modals = require('ui.modals').make_modals
local make_add_widget_modal
make_add_widget_modal = require('ui.widget_modal').make_add_widget_modal
local make_data_view_modal
make_data_view_modal = require('ui.data_view_modal').make_data_view_modal
local make_scripts
make_scripts = require('ui.scripts').make_scripts
local ICON = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%2389b4fa'/><text x='50%' y='54%' dominant-baseline='middle' text-anchor='middle' font-family='system-ui,sans-serif' font-weight='700' font-size='18' fill='%231e1e2e'>db</text></svg>"
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
      'TGui'
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
    make_modals(),
    make_add_widget_modal(),
    make_data_view_modal(),
    H.script({
      [[      if (localStorage.getItem('tdb_token')) {
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
    ]]
    }),
    make_scripts()
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
if arg and arg[1] == "--test" then
  print(render())
end
return render
