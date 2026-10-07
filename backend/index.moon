#!/usr/bin/env moon
-- backend/index.moon
-- Dynamically generates the main TGui HTML page.
-- Uses backend/html.lua to build the HTML tree.
-- Section builders live in backend/ui/*.moon; this module only assembles them.

H = require 'html'

{ :make_login_overlay }   = require 'ui.login'
{ :make_sidebar }         = require 'ui.sidebar'
{ :make_content }         = require 'ui.content'
{ :make_modals }          = require 'ui.modals'
{ :make_add_widget_modal } = require 'ui.widget_modal'
{ :make_data_view_modal } = require 'ui.data_view_modal'
{ :make_scripts }         = require 'ui.scripts'

-- Constants
ICON = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%2389b4fa'/><text x='50%' y='54%' dominant-baseline='middle' text-anchor='middle' font-family='system-ui,sans-serif' font-weight='700' font-size='18' fill='%231e1e2e'>db</text></svg>"

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
    make_add_widget_modal!
    make_data_view_modal!
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
    make_scripts!
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
