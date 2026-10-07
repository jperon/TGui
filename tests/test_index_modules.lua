local R = require('tests.runner')
R.describe("index — modules ui/", function()
  local modules = {
    {
      'ui.login',
      {
        'make_login_overlay'
      }
    },
    {
      'ui.sidebar',
      {
        'make_sidebar'
      }
    },
    {
      'ui.fields_panel',
      {
        'make_fields_panel'
      }
    },
    {
      'ui.content',
      {
        'make_content'
      }
    },
    {
      'ui.admin_panels',
      {
        'make_admin_panel'
      }
    },
    {
      'ui.modals',
      {
        'make_modals'
      }
    },
    {
      'ui.data_view_modal',
      {
        'make_data_view_modal'
      }
    },
    {
      'ui.widget_modal',
      {
        'make_add_widget_modal'
      }
    },
    {
      'ui.scripts',
      {
        'make_scripts'
      }
    }
  }
  for _index_0 = 1, #modules do
    local _des_0 = modules[_index_0]
    local mod_name, fns
    mod_name, fns = _des_0[1], _des_0[2]
    R.it("charge et exporte " .. tostring(mod_name), function()
      local m = require(mod_name)
      R.eq(type(m), 'table', mod_name)
      for _index_1 = 1, #fns do
        local fn = fns[_index_1]
        R.eq(type(m[fn]), 'function', tostring(mod_name) .. "." .. tostring(fn))
      end
    end)
  end
end)
return R.describe("index — sections clés", function()
  local render = require('index')
  local html = render()
  local section_ids = {
    'login-overlay',
    'sidebar',
    'fields-panel',
    'admin-panel',
    'admin-users-section',
    'admin-groups-section',
    'admin-snapshot-section',
    'admin-apps-section',
    'data-view-modal',
    'add-widget-modal'
  }
  for _index_0 = 1, #section_ids do
    local id = section_ids[_index_0]
    R.it("contient #" .. tostring(id), function()
      return R.ok(html:find("id=\"" .. tostring(id) .. "\"", 1, true) ~= nil, "identifiant manquant : " .. tostring(id))
    end)
  end
end)
