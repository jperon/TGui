-- tests/test_index_modules.moon
-- Garde-fou du découpage de backend/index.moon : chaque module de backend/ui/
-- doit se charger (require) et exposer ses fonctions d'assemblage, et le HTML
-- rendu doit contenir les identifiants des sections clés. On ne fige PAS
-- l'empreinte complète : l'interface évolue légitimement.
R = require 'tests.runner'

R.describe "index — modules ui/", ->
  modules = {
    {'ui.login',           {'make_login_overlay'}}
    {'ui.sidebar',         {'make_sidebar'}}
    {'ui.fields_panel',    {'make_fields_panel'}}
    {'ui.content',         {'make_content'}}
    {'ui.admin_panels',    {'make_admin_panel'}}
    {'ui.modals',          {'make_modals'}}
    {'ui.data_view_modal', {'make_data_view_modal'}}
    {'ui.widget_modal',    {'make_add_widget_modal'}}
    {'ui.scripts',         {'make_scripts'}}
  }

  for {mod_name, fns} in *modules
    R.it "charge et exporte #{mod_name}", ->
      m = require mod_name
      R.eq type(m), 'table', mod_name
      for fn in *fns
        R.eq type(m[fn]), 'function', "#{mod_name}.#{fn}"

R.describe "index — sections clés", ->
  render = require 'index'
  html = render!

  section_ids = {
    'login-overlay'
    'sidebar'
    'fields-panel'
    'admin-panel'
    'admin-users-section'
    'admin-groups-section'
    'admin-snapshot-section'
    'admin-apps-section'
    'data-view-modal'
    'add-widget-modal'
  }

  for id in *section_ids
    R.it "contient ##{id}", ->
      R.ok html\find("id=\"#{id}\"", 1, true) != nil, "identifiant manquant : #{id}"
