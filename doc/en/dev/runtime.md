# Backend runtime — detailed reference

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-11-16 18:23:47 UTC

Tarantool startup, HTTP lifecycle and subsystem initialization details.

| Module | Summary |
|---|---|
| `backend/core/app_apply.moon` | Application atomique d'un paquet d'app (spec §4, plan « Étape 4 », ligne V3). |
| `backend/core/app_package.moon` | App versioning foundation (task V1): stable item identity, canonical JSON |
| `backend/core/app_plan.moon` | Moteur pur de calcul du plan de mise a jour d'une application (spec §2). |
| `backend/core/auth.moon` | Authentication: hashing, sessions, user management. |
| `backend/core/config.moon` | Centralized configuration for TGui. |
| `backend/core/data_views.moon` | CRUD for Data Views (stored YAML/JSON configs over a source space). |
| `backend/core/data_views_executor.moon` | Execution engine for Data Views queries. |
| `backend/core/formula_proxy.moon` | Formula plumbing for reads: error formatting, the compiled-formula cache, |
| `backend/core/formula_sandbox.moon` | Sandbox used to compile and run user formulas. |
| `backend/core/graphql_flattener.moon` | GraphQL Flattener with intelligent list handling |
| `backend/core/permissions.moon` | Unix-style group permissions management. |
| `backend/core/plugin_compile.moon` | Server-side compilation of a custom widget definition's script (spec §7). |
| `backend/core/relation_maps.moon` | Builds FK / relation definition maps for a space from the _tdb_relations, |
| `backend/core/spaces.moon` | Bootstrap and manage tdb system spaces (metadata) in Tarantool. |
| `backend/core/triggers.moon` | Manages Tarantool before_replace triggers for trigger formula fields. |
| `backend/core/validation.moon` | Validate record payloads against the declared space fields on insert/update. |
| `backend/core/view_presets.moon` | CRUD for named view presets (a MoonScript filter plus a sort order) |
| `backend/core/views.moon` | Manage view definitions: named projections over a data space. |
| `backend/core/widget_ids.moon` | guarantees that every widget of a custom-view (page) YAML document |
| `backend/core/widget_scopes.moon` | Portées des définitions de widgets personnalisés (spec |
| `backend/fixtures.moon` | Fixtures du conteneur de test : sur une base vide, installe l'application |
| `backend/generate_sdl.moon` | CLI entrypoint to generate passive SDL artifact. |
| `backend/graphql/dynamic.moon` | Generates GraphQL SDL and resolvers dynamically from space metadata. |
| `backend/graphql/executor.moon` | Executes a parsed GraphQL operation against a schema and resolvers. |
| `backend/graphql/introspection.moon` | Implements GraphQL introspection: __schema, __type, __typename. |
| `backend/graphql/lexer.moon` | Tokenizes a GraphQL document (query or SDL) into a token stream. |
| `backend/graphql/parser.moon` | Parses a GraphQL document (query or SDL) into an AST. |
| `backend/graphql/schema.moon` | Type system: builds an executable schema from a parsed SDL document. |
| `backend/graphql/sdl_generator.moon` | Generates a passive SDL artifact from MoonScript registry metadata. |
| `backend/graphql/sdl_registry.moon` | Passive MoonScript source of truth for static root GraphQL fields. |
| `backend/http_server.moon` | HTTP edge for TGui (index/static assets + GraphQL POST endpoint). |
| `backend/index.moon` | Dynamically generates the main TGui HTML page. |
| `backend/init.moon` | Tarantool bootstrap entrypoint for TGui backend runtime. |
| `backend/resolvers/aggregate_resolvers.moon` | Aggregation query: GROUP BY via Lua iteration over tuples. |
| `backend/resolvers/app_resolvers.moon` | GraphQL resolvers for application versioning (list, export, preview, apply, purge). |
| `backend/resolvers/auth_resolvers.moon` | Resolvers for authentication, user management, groups, and permissions. |
| `backend/resolvers/custom_view_crud.moon` | CRUD, snapshot and layout export/import functions for custom YAML views. |
| `backend/resolvers/custom_view_resolvers.moon` | Entry point: assembles Query and Mutation for custom YAML views (dashboard layouts). |
| `backend/resolvers/custom_view_widgets.moon` | Widget and layout-editing functions for custom YAML views. |
| `backend/resolvers/custom_view_zones.moon` | Zone layout functions for custom YAML views. |
| `backend/resolvers/data_resolvers.moon` | Resolvers for CRUD operations on user-defined data spaces. |
| `backend/resolvers/data_view_resolvers.moon` | CRUD resolvers for data views (persisted queries). |
| `backend/resolvers/export_resolvers.moon` | Snapshot export, diff and import resolvers. |
| `backend/resolvers/graphql_view_resolvers.moon` | GraphQL resolvers for data views with list support |
| `backend/resolvers/init.moon` | Compose and initialize the executable GraphQL schema/resolver graph. |
| `backend/resolvers/schema_resolvers.moon` | Resolvers for space, field, view, and relation metadata. |
| `backend/resolvers/utils.moon` | Shared helpers for all resolvers. |
| `backend/resolvers/view_preset_resolvers.moon` | GraphQL resolvers for named view presets (filter + sort per widget |
| `backend/resolvers/widget_plugin_resolvers.moon` | CRUD resolvers for custom widget plugins used by custom views. |
| `backend/test_runner.moon` | Entrypoint to run tests in a Docker container. |
| `backend/tools/app_builder.moon` | tools/app_builder.moon — structure YAML compacte → paquet .tdbapp.yaml. |
| `backend/tools/bibliotheque_app.moon` | Assembleur de l'application « Bibliothèque » : structure YAML + seeds. |
| `backend/tools/bibliotheque_seed_coordonnees.moon` | tools/bibliotheque_seed_coordonnees.moon — données fictives : coordonnées. |
| `backend/tools/bibliotheque_seed_ecole.moon` | T6 — Données fictives « école » du paquet Bibliothèque. |
| `backend/tools/bibliotheque_seed_livres.moon` | tools/bibliotheque_seed_livres.moon — données fictives « bibliothèque » (T7). |
| `backend/tools/seed_rng.moon` | tools/seed_rng.moon — générateur pseudo-aléatoire déterministe (Park–Miller). |
| `backend/ui/admin_panels.moon` | Administration panels of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/content.moon` | Main content area and toolbars of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/data_view_modal.moon` | Data view configuration modal of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/fields_panel.moon` | Fields panel of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/login.moon` | Login overlay of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/modals.moon` | Common modals of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/scripts.moon` | Ordered list of frontend <script src> tags for the SPA. |
| `backend/ui/sidebar.moon` | Sidebar of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/ui/widget_modal.moon` | "Add widget" modal of the SPA (extracted from backend/index.moon, no functional change). |
| `backend/zstd_wrapper.moon` | ZSTD-FFI Wrapper |
| `backend/init.lua` | (pas de description en tête de fichier) |
| `backend/html.lua` | SPDX-License-Identifier: MIT |
