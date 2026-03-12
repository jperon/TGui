# Chaîne GraphQL — référence détaillée

> Fichier généré automatiquement. Ne pas modifier manuellement.
>
> Généré le: 2026-03-12 10:33:27 UTC

Flux SDL/parser/executor/résolveurs (statique + dynamique).

| Module | Résumé |
|---|---|
| `backend/graphql/lexer.moon` | Tokenizes a GraphQL document (query or SDL) into a token stream. |
| `backend/graphql/parser.moon` | Parses a GraphQL document (query or SDL) into an AST. |
| `backend/graphql/schema.moon` | Type system: builds an executable schema from a parsed SDL document. |
| `backend/graphql/executor.moon` | Executes a parsed GraphQL operation against a schema and resolvers. |
| `backend/graphql/dynamic.moon` | Generates GraphQL SDL and resolvers dynamically from space metadata. |
| `backend/graphql/introspection.moon` | Implements GraphQL introspection: __schema, __type, __typename. |
| `backend/resolvers/schema_resolvers.moon` | Resolvers for space, field, view, and relation metadata. |
| `backend/resolvers/data_resolvers.moon` | Resolvers for CRUD operations on user-defined data spaces. |
| `backend/resolvers/auth_resolvers.moon` | Resolvers for authentication, user management, groups, and permissions. |
