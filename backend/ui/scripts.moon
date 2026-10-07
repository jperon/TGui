-- backend/ui/scripts.moon
-- Ordered list of frontend <script src> tags for the SPA.
-- Extracted from backend/index.moon. The ORDER is significant: a module loaded
-- too early silently breaks the interface. Keep SCRIPT_SRCS in the exact same
-- order as the original tag sequence.

H = require 'html'

SCRIPT_SRCS = {
  '/vendor/tui-grid.bundle.js'
  '/vendor/jsyaml.bundle.js'
  '/vendor/codemirror.bundle.js'
  '/vendor/sortablejs.bundle.js'
  '/vendor/plugin-runtime.bundle.js'
  '/src/i18n.js'
  '/src/html_escape.js'
  '/src/modal.js'
  '/src/graphql_client.js'
  '/src/auth.js'
  '/src/spaces.js'
  '/src/data_views.js'
  '/src/widget_plugins.js'
  '/src/app_fields_helpers.js'
  '/src/app_sidebar_helpers.js'
  '/src/app_undo_helpers.js'
  '/src/drag_drop_manager.js'
  '/src/app_data_helpers.js'
  '/src/app_view_helpers.js'
  '/src/app_view_helpers_pages.js'
  '/src/app_view_helpers_yaml.js'
  '/src/app_view_helpers_widget_plugins.js'
  '/src/app_view_helpers_add_widget.js'
  '/src/app_view_helpers_zones.js'
  '/src/app_view_config_helpers.js'
  '/src/app_snapshot_helpers.js'
  '/src/app_apps_helpers.js'
  '/src/views/fk_search_editor.js'
  '/src/views/data_view.js'
  '/src/views/data_view_helpers.js'
  '/src/views/custom_view.js'
  '/src/yaml_builder.js'
  '/src/app.js'
}

make_scripts = ->
  parts = [H.script {src: src, ''} for src in *SCRIPT_SRCS]
  table.concat parts, '\n'

{
  make_scripts: make_scripts
}
