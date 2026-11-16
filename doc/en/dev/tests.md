# Tests — detailed reference

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-11-16 18:23:47 UTC

Backend/frontend test panorama and per-file intent.

| Module | Summary |
|---|---|
| `tests/run.moon` | Entrypoint for the TGui test suite. |
| `tests/runner.moon` | Standalone test micro-framework (no external dependencies). |
| `tests/test_add_data_view_to_page.moon` | Tests the addDataViewToPage mutation. |
| `tests/test_app_apply.moon` | Tests d'intégration pour backend/core/app_apply.moon (tâche V3a, plan |
| `tests/test_app_bibliotheque_install.moon` | T9b — l'application « Bibliothèque » est déjà INSTALLÉE au démarrage du |
| `tests/test_app_builder.moon` | (pas de description en tête de fichier) |
| `tests/test_app_lifecycle.moon` | V6a : test d'intégration de bout en bout du cycle de vie d'une application, |
| `tests/test_app_lifecycle_parts.moon` | Tests d'intégration V3b du cycle de vie d'une app (spec §1-§4, plan « Étape 4 ») : |
| `tests/test_app_package.moon` | Tests for backend/core/app_package.moon (task V1, plan « Étape 4 » : |
| `tests/test_app_plan.moon` | Tests purs pour core/app_plan.moon (moteur de plan de mise a jour, spec §2). |
| `tests/test_app_resolvers.moon` | Tests des résolveurs GraphQL du versionnage des apps (tâche V4, spec §3/§4, |
| `tests/test_app_seed_sequences.moon` | Un seed qui porte des `id` explicites doit faire avancer le compteur de la |
| `tests/test_app_trigger_fields.moon` | Correctif T3b : une colonne calculée à la lecture (formule SANS triggerFields) |
| `tests/test_auth_ratelimit.moon` | Persistent login rate-limiting (spec §7 / audit 1.2): |
| `tests/test_batch_ops.moon` | GraphQL integration tests for insertRecords/updateRecords on a temporary space. |
| `tests/test_bibliotheque_app.moon` | T9a : tests de tools.bibliotheque_app.seed_tables (aucune dépendance |
| `tests/test_bibliotheque_vues_pages.moon` | T16b — vues de données et pages de l'application Bibliothèque. |
| `tests/test_change_parent.moon` | Tests for changing widget parent via reorderWidgets mutation |
| `tests/test_computed_relation.moon` | Relation dont le champ source est CALCULÉ (formule de lecture, pas de valeur |
| `tests/test_custom_view_resolvers_api.moon` | Guards the public surface of resolvers/custom_view_resolvers.moon: |
| `tests/test_custom_views.moon` | Tests CRUD operations on custom views (resolvers/custom_view_resolvers.moon). |
| `tests/test_data_filters.moon` | Tests filter operators (matches_filter / apply_filter). |
| `tests/test_data_views.moon` | (pas de description en tête de fichier) |
| `tests/test_data_views_relation_group.moon` | Data Views — groupBy sur un champ Relation : l'étiquette de groupe doit être |
| `tests/test_drag_drop_e2e.moon` | E2E tests for drag & drop functionality |
| `tests/test_executor.moon` | Tests GraphQL executor behavior (graphql/executor.moon). |
| `tests/test_extended_proxy.moon` | Tests for extended proxy with list support |
| `tests/test_fiber_slice.moon` | La tranche de fibre n'est plus relevée pour TOUTE l'instance (init.moon) : une |
| `tests/test_fiber_yield.moon` | Cession coopérative des boucles de lecture (core.config.yield_every). |
| `tests/test_formula_guard.moon` | Every formula call site must run through core.config.safe_formula_call |
| `tests/test_formula_read_path.moon` | T12 — chemin de lecture réel des colonnes calculées qui lisent d'autres |
| `tests/test_formula_read_perms.moon` | Formula columns and FK traversal must not read a space the requesting user |
| `tests/test_formula_space_cost.moon` | T10 — coût des formules qui lisent d'autres espaces. |
| `tests/test_formula_space_readonly.moon` | Le cache par requête de space() est partagé entre toutes les évaluations |
| `tests/test_graphql_flattener.moon` | Tests for GraphQL Flattener with list support |
| `tests/test_graphql_integration_working.moon` | Working integration tests for GraphQL Builder system |
| `tests/test_html.moon` | Tests backend/html.lua and the convention used by its callers. |
| `tests/test_http_static.moon` | Task 3 — fichiers statiques : garde-fous anti-traversal de chemin. |
| `tests/test_import_snapshot_format.moon` | importSnapshot must refuse documents that are not snapshots BEFORE do_import |
| `tests/test_index_html.moon` | Garde-fou : le HTML de la SPA doit inclure tous les bundles vendor requis. |
| `tests/test_index_modules.moon` | Garde-fou du découpage de backend/index.moon : chaque module de backend/ui/ |
| `tests/test_lexer.moon` | Tests for GraphQL lexer (graphql/lexer.moon). |
| `tests/test_multiple_relations.moon` | Tests for multiple relations detection functionality |
| `tests/test_nesting.moon` | Tests nested GraphQL queries (nesting/sub-queries). |
| `tests/test_parser.moon` | Tests for GraphQL parser (graphql/parser.moon). |
| `tests/test_password_policy.moon` | Forced change of the default admin password (spec §7 / audit 1.4). |
| `tests/test_permissions.moon` | Tests permission coverage: require_auth, require_admin, |
| `tests/test_preset_page_cascade.moon` | Préréglages de widgets attachés à une page ('widget:<pageId>:<widgetId>') : |
| `tests/test_relation_cardinality.moon` | Declared relation cardinality ('one' \| 'many'): storage, GraphQL API and |
| `tests/test_relation_type_regression.moon` | Regression: verifies safe fieldType=Relation -> Int mapping and relation creation. |
| `tests/test_relations.moon` | Tests FK relation behavior: create_relation, list_relations, update_relation |
| `tests/test_reorder_widgets.moon` | Tests for the reorderWidgets mutation |
| `tests/test_resize_zone.moon` | Tests for the resizeZone mutation |
| `tests/test_schema.moon` | Tests for GraphQL type system (graphql/schema.moon). |
| `tests/test_seed_coordonnees.moon` | T8 — données fictives : coordonnées. Déterminisme, volumes exacts, intégrité |
| `tests/test_seed_ecole.moon` | T6 — Données fictives « école » : interface generate(rng, k) de |
| `tests/test_seed_livres.moon` | T7 — données fictives « bibliothèque » : volumes exacts, intégrité des clés |
| `tests/test_snapshot.moon` | Tests exportSnapshot / diffSnapshot / importSnapshot resolvers. |
| `tests/test_spaces.moon` | Tests CRUD operations on spaces (core/spaces.moon). |
| `tests/test_triggers.moon` | Tests trigger formulas (core/triggers.moon). |
| `tests/test_triggers_exports.moon` | Freezes the exact public API of core.triggers so the T14 split into |
| `tests/test_tuple_converters.moon` | Tuple→table converters: exact keys and values for each public reader. |
| `tests/test_typed_query_permissions.moon` | Typed space queries generated by graphql/dynamic.moon must enforce the read |
| `tests/test_validation.moon` | Write-time record validation (core.validation), through validate_record and |
| `tests/test_view_presets.moon` | Named view presets: scope isolation, overwrite by (scope, name), validation, |
| `tests/test_views_core.moon` | Non-regression tests for the two bugs of core/views.moon (task T5). |
| `tests/test_widget_detach.moon` | « Détacher » une instance de widget personnalisé (spec |
| `tests/test_widget_gql_policy.moon` | Requêtes relayées depuis une iframe de widget (en-tête `X-TDB-Widget: 1` |
| `tests/test_widget_ids.moon` | Tests core/widget_ids: every widget of a page YAML text carries a stable id, |
| `tests/test_widget_plugin_lua.moon` | Définitions Lua / MoonScript des widgets personnalisés (spec |
| `tests/test_widget_plugin_manifest.moon` | Manifest des widgets personnalisés (spec |
| `tests/test_widget_plugin_permissions.moon` | Écriture du code d'un widget plugin = exécution de code dans le navigateur |
| `tests/test_widget_plugins.moon` | Tests CRUD operations on widget plugins (resolvers/widget_plugin_resolvers.moon). |
| `tests/test_widget_scopes.moon` | Portées des définitions de widgets personnalisés (spec |
| `tests/test_zone_merge_split.moon` | Tests for the mergeZones and splitZone mutations. |
| `tests/js/dom_stub.coffee` | tests/js/dom_stub.coffee — minimal DOM stub for Node.js |
| `tests/js/run.coffee` | tests/js/run.coffee — runs all test_*.coffee files sequentially |
| `tests/js/runner.coffee` | tests/js/runner.coffee — minimal test runner (no dependencies) |
| `tests/js/test_add_widget_manifest_form.coffee` | Fenêtre « ＋ Widget » : quand le widget personnalisé choisi déclare un |
| `tests/js/test_add_widget_plugins_options.coffee` | Fenêtre « ＋ Widget » : le groupe « Widgets personnalisés » est rempli depuis |
| `tests/js/test_apps_helpers.coffee` | tests/js/test_apps_helpers.coffee — tests de AppAppsHelpers (app_apps_helpers.js) |
| `tests/js/test_apps_reload_menu.coffee` | tests/js/test_apps_reload_menu.coffee — T14 |
| `tests/js/test_auth.coffee` | tests/js/test_auth.coffee — tests pour Auth (auth.js) |
| `tests/js/test_custom_view.coffee` | tests/js/test_custom_view.coffee — tests for CustomView (custom_view.js) |
| `tests/js/test_custom_view_cascade.coffee` | tests/js/test_custom_view_cascade.coffee — cascade selection of dependent widgets. |
| `tests/js/test_custom_view_dataview_widget.coffee` | tests/js/test_custom_view_dataview_widget.coffee — T18 regression tests. |
| `tests/js/test_custom_view_link_fields.coffee` | tests/js/test_custom_view_link_fields.coffee — T21 |
| `tests/js/test_custom_view_sorted_first_row.coffee` | `_firstRow` sert à la cascade depends_on initiale (widget racine → premier |
| `tests/js/test_custom_view_splitter.coffee` | Séparateur (splitter) entre deux enfants d'une zone : |
| `tests/js/test_custom_view_tiles.coffee` | tests/js/test_custom_view_tiles.coffee — page "tile" mode (T19). |
| `tests/js/test_custom_view_widget_menu.coffee` | Menu « Trier / Filtrer » d'un widget de page : il ne doit PAS être attaché |
| `tests/js/test_data_view.coffee` | tests/js/test_data_view.coffee — tests for DataView (data_view.js) |
| `tests/js/test_data_view_filter_focus.coffee` | tests/js/test_data_view_filter_focus.coffee — DataView.load focus handling. |
| `tests/js/test_data_view_opts.coffee` | tests/js/test_data_view_opts.coffee — tests for DataView options (readOnly) |
| `tests/js/test_data_view_sentinel_sort.coffee` | La ligne sentinelle `__isNew` (saisie d'un nouvel enregistrement) doit rester |
| `tests/js/test_drag_drop_manager.coffee` | tests/js/test_drag_drop_manager.coffee - tests for DragDropManager |
| `tests/js/test_field_autocomplete.coffee` | Autocomplete des noms de champs dans le filtre MoonScript ("λ") : |
| `tests/js/test_field_autocomplete_cache.coffee` | Cache du module d'autocomplétion (filtre « λ ») : |
| `tests/js/test_fields_helpers_computed_relation.coffee` | A relation may be declared on a COMPUTED field (read-time formula returning |
| `tests/js/test_graphql_client.coffee` | tests/js/test_graphql_client.coffee — tests pour GQL (graphql_client.js) |
| `tests/js/test_html_escape.coffee` | TdbHtml.escape + tests d'injection pour les sites corrigés en S3 (échappement innerHTML). |
| `tests/js/test_i18n.coffee` | tests/js/test_i18n.coffee — tests du runtime i18n minimal |
| `tests/js/test_modal_keydown.coffee` | tests/js/test_modal_keydown.coffee — retrait du handler keydown des modales. |
| `tests/js/test_page_widget_filter_focus.coffee` | tests/js/test_page_widget_filter_focus.coffee — focus du champ λ d'un widget de page. |
| `tests/js/test_password_policy.coffee` | Forced default-password change, frontend side (spec §7 / audit 1.4): |
| `tests/js/test_plugin_runtimes.coffee` | tests/js/test_plugin_runtimes.coffee — on-demand widget compiler loading |
| `tests/js/test_relation_display_frontend.coffee` | Static frontend tests (Node) for relation display. |
| `tests/js/test_relation_display_frontend_regression.coffee` | Targeted regressions for frontend relation rendering. |
| `tests/js/test_sidebar_helpers.coffee` | Handler « nouvel espace » de la barre latérale (AppSidebarHelpers.bindSidebar) : |
| `tests/js/test_spaces.coffee` | tests/js/test_spaces.coffee — tests for Spaces (spaces.js) |
| `tests/js/test_undo_helpers.coffee` | tests/js/test_undo_helpers.coffee — tests for global AppUndoHelpers service. |
| `tests/js/test_vendor_bundles_tracked.coffee` | tests/js/test_vendor_bundles_tracked.coffee — guard against 404 vendor bundles |
| `tests/js/test_view_helpers.coffee` | Régression pour AppViewHelpers.renderCustomViewPreview. |
| `tests/js/test_view_helpers_dedup.coffee` | T11 refactor guard: AppViewHelpers must not define any key twice, and every |
| `tests/js/test_view_presets_menu.coffee` | Menu « Trier / Filtrer » : sérialisation du tri, application d'un préréglage |
| `tests/js/test_widget_detach.coffee` | Action « Détacher » d'une instance de widget personnalisé (spec |
| `tests/js/test_widget_lua_runtime.coffee` | Widgets Lua / MoonScript (spec docs/superpowers/specs/2026-11-16-custom-widgets-design.md §7) : |
| `tests/js/test_widget_manifest_access.coffee` | Manifest des widgets personnalisés : accès effectif (none/read/full), |
| `tests/js/test_widget_plugins_dedup.coffee` | T13 guard: LIST_WIDGET_PLUGINS must be defined in exactly one frontend source |
| `tests/js/test_widget_relay_header.coffee` | Le relais des requêtes d'un widget (custom_view_plugins.coffee) doit passer |
| `tests/js/test_widget_scope_label.coffee` | Portées des widgets personnalisés côté frontend (spec |
| `tests/js/test_yaml_builder.coffee` | tests/js/test_yaml_builder.coffee — tests for YamlBuilder (yaml_builder.js) |
