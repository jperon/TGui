# Tests — detailed reference

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-03-12 20:58:48 UTC

Backend/frontend test panorama and per-file intent.

| Module | Summary |
|---|---|
| `tests/run.moon` | Entrypoint for the TGui test suite. |
| `tests/runner.moon` | Standalone test micro-framework (no external dependencies). |
| `tests/test_batch_ops.moon` | GraphQL integration tests for insertRecords/updateRecords on a temporary space. |
| `tests/test_custom_views.moon` | Tests CRUD operations on custom views (resolvers/custom_view_resolvers.moon). |
| `tests/test_data_filters.moon` | Tests filter operators (matches_filter / apply_filter). |
| `tests/test_executor.moon` | Tests GraphQL executor behavior (graphql/executor.moon). |
| `tests/test_lexer.moon` | Tests for GraphQL lexer (graphql/lexer.moon). |
| `tests/test_nesting.moon` | Tests nested GraphQL queries (nesting/sub-queries). |
| `tests/test_parser.moon` | Tests for GraphQL parser (graphql/parser.moon). |
| `tests/test_permissions.moon` | Tests permission coverage: require_auth, require_admin, |
| `tests/test_relation_display_backend.moon` | Backend test to verify relation display behavior. |
| `tests/test_relation_display_regression.moon` | Regression test to ensure relation rendering no longer breaks. |
| `tests/test_relation_field.moon` | Ensures Relation type is not used directly and UI follows the correct mutation flow. |
| `tests/test_relation_integration.moon` | Full integration test for relations. |
| `tests/test_relation_repr.moon` | Test to verify that relations correctly use _repr. |
| `tests/test_relation_type_regression.moon` | Regression: verifies safe fieldType=Relation -> Int mapping and relation creation. |
| `tests/test_relations.moon` | Tests FK relation behavior: create_relation, list_relations, update_relation |
| `tests/test_schema.moon` | Tests for GraphQL type system (graphql/schema.moon). |
| `tests/test_snapshot.moon` | Tests exportSnapshot / diffSnapshot / importSnapshot resolvers. |
| `tests/test_spaces.moon` | Tests CRUD operations on spaces (core/spaces.moon). |
| `tests/test_triggers.moon` | Tests trigger formulas (core/triggers.moon). |
| `tests/js/dom_stub.coffee` | tests/js/dom_stub.coffee — minimal DOM stub for Node.js |
| `tests/js/run.coffee` | tests/js/run.coffee — runs all test_*.coffee files sequentially |
| `tests/js/runner.coffee` | tests/js/runner.coffee — minimal test runner (no dependencies) |
| `tests/js/test_auth.coffee` | tests/js/test_auth.coffee — tests pour Auth (auth.js) |
| `tests/js/test_custom_view.coffee` | tests/js/test_custom_view.coffee — tests for CustomView (custom_view.js) |
| `tests/js/test_data_view.coffee` | tests/js/test_data_view.coffee — tests for DataView (data_view.js) |
| `tests/js/test_graphql_client.coffee` | tests/js/test_graphql_client.coffee — tests pour GQL (graphql_client.js) |
| `tests/js/test_i18n.coffee` | tests/js/test_i18n.coffee — tests du runtime i18n minimal |
| `tests/js/test_relation_display_frontend.coffee` | Static frontend tests (Node) for relation display. |
| `tests/js/test_relation_display_frontend_regression.coffee` | Targeted regressions for frontend relation rendering. |
| `tests/js/test_spaces.coffee` | tests/js/test_spaces.coffee — tests for Spaces (spaces.js) |
| `tests/js/test_undo_helpers.coffee` | tests/js/test_undo_helpers.coffee — tests for global AppUndoHelpers service. |
| `tests/js/test_yaml_builder.coffee` | tests/js/test_yaml_builder.coffee — tests for YamlBuilder (yaml_builder.js) |
