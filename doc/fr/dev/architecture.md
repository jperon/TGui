# Architecture — detailed reference

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-03-12 20:58:48 UTC

Architecture-level view of backend/frontend modules and relationships.

| Module | Summary |
|---|---|
| `backend/init.moon` | Tarantool bootstrap entrypoint for TGui backend runtime. |
| `backend/http_server.moon` | HTTP edge for TGui (index/static assets + GraphQL POST endpoint). |
| `backend/core/spaces.moon` | Bootstrap and manage tdb system spaces (metadata) in Tarantool. |
| `backend/core/auth.moon` | Authentication: hashing, sessions, user management. |
| `backend/core/permissions.moon` | Unix-style group permissions management. |
| `backend/core/triggers.moon` | Manages Tarantool before_replace triggers for trigger formula fields. |
| `backend/core/views.moon` | Manage view definitions: named projections over a data space. |
| `backend/resolvers/init.moon` | Compose and initialize the executable GraphQL schema/resolver graph. |
