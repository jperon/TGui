# Tests — detailed reference

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-06-13 10:32:02 UTC

Backend/frontend test panorama and per-file intent.

| Module | Summary |
|---|---|
| `tests/run.moon` | Entrypoint for the TGui test suite. |
| `tests/runner.moon` | Standalone test micro-framework (no external dependencies). |
| `tests/test_add_data_view_to_page.moon` | Tests the addDataViewToPage mutation. |
| `tests/test_batch_ops.moon` | GraphQL integration tests for insertRecords/updateRecords on a temporary space. |
| `tests/test_change_parent.moon` | Tests for changing widget parent via reorderWidgets mutation |
| `tests/test_custom_views.moon` | Tests CRUD operations on custom views (resolvers/custom_view_resolvers.moon). |
| `tests/test_data_filters.moon` | Tests filter operators (matches_filter / apply_filter). |
| `tests/test_data_views.moon` | (pas de description en tête de fichier) |
| `tests/test_drag_drop_e2e.moon` | E2E tests for drag & drop functionality |
| `tests/test_executor.moon` | Tests GraphQL executor behavior (graphql/executor.moon). |
| `tests/test_extended_proxy.moon` | Tests for extended proxy with list support |
| `tests/test_graphql_builder_simple.moon` | Simple tests for GraphQL Builder functionality (backend only) |
| `tests/test_graphql_flattener.moon` | Tests for GraphQL Flattener with list support |
| `tests/test_graphql_integration_working.moon` | Working integration tests for GraphQL Builder system |
| `tests/test_index_html.moon` | Garde-fou : le HTML de la SPA doit inclure tous les bundles vendor requis. |
| `tests/test_lexer.moon` | Tests for GraphQL lexer (graphql/lexer.moon). |
| `tests/test_multiple_relations.moon` | Tests for multiple relations detection functionality |
| `tests/test_multiple_relations_simple.moon` | Simple tests for multiple relations detection functionality |
| `tests/test_nesting.moon` | Tests nested GraphQL queries (nesting/sub-queries). |
| `tests/test_parser.moon` | Tests for GraphQL parser (graphql/parser.moon). |
| `tests/test_permissions.moon` | Tests permission coverage: require_auth, require_admin, |
| `tests/test_relation_type_regression.moon` | Regression: verifies safe fieldType=Relation -> Int mapping and relation creation. |
| `tests/test_relations.moon` | Tests FK relation behavior: create_relation, list_relations, update_relation |
| `tests/test_reorder_widgets.moon` | Tests for the reorderWidgets mutation |
| `tests/test_resize_zone.moon` | Tests for the resizeZone mutation |
| `tests/test_schema.moon` | Tests for GraphQL type system (graphql/schema.moon). |
| `tests/test_snapshot.moon` | Tests exportSnapshot / diffSnapshot / importSnapshot resolvers. |
| `tests/test_spaces.moon` | Tests CRUD operations on spaces (core/spaces.moon). |
| `tests/test_triggers.moon` | Tests trigger formulas (core/triggers.moon). |
| `tests/test_widget_plugins.moon` | Tests CRUD operations on widget plugins (resolvers/widget_plugin_resolvers.moon). |
| `tests/js/dom_stub.coffee` | tests/js/dom_stub.coffee — minimal DOM stub for Node.js |
| `tests/js/run.coffee` | tests/js/run.coffee — runs all test_*.coffee files sequentially |
| `tests/js/runner.coffee` | tests/js/runner.coffee — minimal test runner (no dependencies) |
| `tests/js/test_auth.coffee` | tests/js/test_auth.coffee — tests pour Auth (auth.js) |
| `tests/js/test_custom_view.coffee` | tests/js/test_custom_view.coffee — tests for CustomView (custom_view.js) |
| `tests/js/test_data_view.coffee` | tests/js/test_data_view.coffee — tests for DataView (data_view.js) |
| `tests/js/test_data_view_opts.coffee` | tests/js/test_data_view_opts.coffee — tests for DataView options (readOnly) |
| `tests/js/test_drag_drop_manager.coffee` | tests/js/test_drag_drop_manager.coffee - tests for DragDropManager |
| `tests/js/test_graphql_client.coffee` | tests/js/test_graphql_client.coffee — tests pour GQL (graphql_client.js) |
| `tests/js/test_i18n.coffee` | tests/js/test_i18n.coffee — tests du runtime i18n minimal |
| `tests/js/test_relation_display_frontend.coffee` | Static frontend tests (Node) for relation display. |
| `tests/js/test_relation_display_frontend_regression.coffee` | Targeted regressions for frontend relation rendering. |
| `tests/js/test_spaces.coffee` | tests/js/test_spaces.coffee — tests for Spaces (spaces.js) |
| `tests/js/test_undo_helpers.coffee` | tests/js/test_undo_helpers.coffee — tests for global AppUndoHelpers service. |
| `tests/js/test_view_helpers.coffee` | Régression pour AppViewHelpers.renderCustomViewPreview. |
| `tests/js/test_yaml_builder.coffee` | tests/js/test_yaml_builder.coffee — tests for YamlBuilder (yaml_builder.js) |
