local H = require('html')
local SCRIPT_SRCS = {
  '/vendor/tui-grid.bundle.js',
  '/vendor/jsyaml.bundle.js',
  '/vendor/codemirror.bundle.js',
  '/vendor/sortablejs.bundle.js',
  '/vendor/plugin-runtime.bundle.js',
  '/src/i18n.js',
  '/src/html_escape.js',
  '/src/modal.js',
  '/src/graphql_client.js',
  '/src/auth.js',
  '/src/spaces.js',
  '/src/data_views.js',
  '/src/widget_plugins.js',
  '/src/views/field_autocomplete.js',
  '/src/app_fields_helpers.js',
  '/src/app_sidebar_helpers.js',
  '/src/app_undo_helpers.js',
  '/src/drag_drop_manager.js',
  '/src/app_data_helpers.js',
  '/src/app_view_helpers.js',
  '/src/app_view_helpers_pages.js',
  '/src/app_view_helpers_yaml.js',
  '/src/app_view_helpers_widget_plugins.js',
  '/src/app_view_helpers_add_widget.js',
  '/src/app_view_helpers_zones.js',
  '/src/app_view_config_helpers.js',
  '/src/app_snapshot_helpers.js',
  '/src/app_apps_helpers.js',
  '/src/views/fk_search_editor.js',
  '/src/views/data_view.js',
  '/src/views/data_view_helpers.js',
  '/src/views/custom_view.js',
  '/src/views/custom_view_plugins.js',
  '/src/views/custom_view_aggregate.js',
  '/src/views/custom_view_resize.js',
  '/src/yaml_builder.js',
  '/src/app.js'
}
local make_scripts
make_scripts = function()
  local parts
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #SCRIPT_SRCS do
      local src = SCRIPT_SRCS[_index_0]
      _accum_0[_len_0] = H.script({
        src = src,
        ''
      })
      _len_0 = _len_0 + 1
    end
    parts = _accum_0
  end
  return table.concat(parts, '\n')
end
return {
  make_scripts = make_scripts
}
