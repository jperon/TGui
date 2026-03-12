# Backend runtime — detailed reference

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-03-12 20:58:48 UTC

Tarantool startup, HTTP lifecycle and subsystem initialization details.

| Module | Summary |
|---|---|
| `backend/core/auth.moon` | Authentication: hashing, sessions, user management. |
| `backend/core/config.moon` | Centralized configuration for TGui. |
| `backend/core/fk_proxy.moon` | Foreign-key proxy resolution module to simplify triggers.moon. |
| `backend/core/permissions.moon` | Unix-style group permissions management. |
| `backend/core/spaces.moon` | Bootstrap and manage tdb system spaces (metadata) in Tarantool. |
| `backend/core/triggers.moon` | Manages Tarantool before_replace triggers for trigger formula fields. |
| `backend/core/views.moon` | Manage view definitions: named projections over a data space. |
| `backend/fixtures.moon` | Seed dataset for the TGui test container. |
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
| `backend/resolvers/auth_resolvers.moon` | Resolvers for authentication, user management, groups, and permissions. |
| `backend/resolvers/custom_view_resolvers.moon` | CRUD resolvers for custom YAML views (dashboard layouts). |
| `backend/resolvers/data_resolvers.moon` | Resolvers for CRUD operations on user-defined data spaces. |
| `backend/resolvers/export_resolvers.moon` | Snapshot export, diff and import resolvers. |
| `backend/resolvers/init.moon` | Compose and initialize the executable GraphQL schema/resolver graph. |
| `backend/resolvers/schema_resolvers.moon` | Resolvers for space, field, view, and relation metadata. |
| `backend/resolvers/utils.moon` | Shared helpers for all resolvers. |
| `backend/test_runner.moon` | Entrypoint to run tests in a Docker container. |
| `backend/init.lua` | (pas de description en tête de fichier) |
| `backend/html.lua` | SPDX-License-Identifier: MIT |
