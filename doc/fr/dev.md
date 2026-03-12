# Developer Documentation — TGui

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-03-12 20:58:48 UTC

Compact architecture overview for TGui. Full reference is available in `doc/en/dev/*.md`.

## Architecture (summary)

- Runtime entrypoint: `backend/init.moon`
- HTTP edge: `backend/http_server.moon`
- GraphQL execution: `backend/graphql/executor.moon`
- Schema/resolver assembly: `backend/resolvers/init.moon`
- Metadata engine: `backend/core/spaces.moon`
- Frontend SPA shell: `frontend/src/app.coffee`

## Detailed references

- Global architecture: `doc/en/dev/architecture.md`
- Backend runtime: `doc/en/dev/runtime.md`
- GraphQL pipeline: `doc/en/dev/graphql.md`
- Frontend SPA: `doc/en/dev/frontend.md`
- Testing strategy: `doc/en/dev/tests.md`

## Commands

- Generate docs: `make doc-gen`
- Check docs: `make doc-check`
- Full CI: `make ci`
