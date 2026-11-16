-- backend/ui/scripts.moon
-- Ordered list of frontend <script src> tags for the SPA.
-- Extracted from backend/index.moon. The ORDER is significant: a module loaded
-- too early silently breaks the interface. Keep SCRIPT_SRCS in the exact same
-- order as the original tag sequence.
--
-- LAZY_SCRIPT_SRCS lists vendor bundles the page does NOT load: they are
-- fetched on demand by frontend/src/views/plugin_runtimes.js, only when a
-- custom widget definition uses the language they provide (spec
-- 2026-11-16-custom-widgets-design.md §7). They are listed here so the
-- "vendor bundle must be git-tracked" guard (tests/js/test_vendor_bundles_tracked.coffee)
-- sees them, and so both script lists live in one place.

H = require 'html'

-- Widget compilers (CoffeeScript, pug) and the Lua runtime (wasmoon) : chargés
-- à la demande, jamais par la SPA.
LAZY_SCRIPT_SRCS = {
  '/vendor/plugin-runtime.bundle.js'
  '/vendor/wasmoon.bundle.js'
}

SCRIPT_SRCS = {
  '/vendor/tui-grid.bundle.js'
  '/vendor/jsyaml.bundle.js'
  '/vendor/codemirror.bundle.js'
  '/vendor/sortablejs.bundle.js'
  '/src/i18n.js'
  '/src/html_escape.js'
  '/src/modal.js'
  '/src/graphql_client.js'
  '/src/auth.js'
  '/src/spaces.js'
  '/src/data_views.js'
  '/src/widget_plugins.js'
  '/src/views/field_autocomplete.js'
  '/src/views/view_presets_menu.js'
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
  '/src/views/plugin_runtimes.js'
  '/src/views/custom_view.js'
  '/src/views/custom_view_plugins.js'
  '/src/views/custom_view_aggregate.js'
  '/src/views/custom_view_resize.js'
  '/src/yaml_builder.js'
  '/src/app.js'
}

make_scripts = ->
  parts = [H.script {src: src, ''} for src in *SCRIPT_SRCS]
  table.concat parts, '\n'

{
  make_scripts: make_scripts
  LAZY_SCRIPT_SRCS: LAZY_SCRIPT_SRCS
  SCRIPT_SRCS: SCRIPT_SRCS
}
