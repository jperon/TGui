# GraphQL API — TGui

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-03-12 10:33:27 UTC
>
> Source: `schema/tdb.graphql`

## Overview

- Endpoint: `/graphql`
- Transport: HTTP POST JSON
- Auth: Bearer token in `Authorization` header
- Signature source of truth: `schema/tdb.graphql`
- Runtime SDL snapshot: `schema/tdb.generated.graphql`

## Queries

### Spaces & Fields

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `spaces` | `-` | `[Space!]!` | Read operation on space/field metadata. |
| `space` | `id: ID!` | `Space` | Read operation on space/field metadata. |

### Views

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `views` | `spaceId: ID!` | `[View!]!` | Manage standard and custom views. |
| `view` | `id: ID!` | `View` | Manage standard and custom views. |
| `customViews` | `-` | `[CustomView!]!` | Manage standard and custom views. |
| `customView` | `id: ID!` | `CustomView` | Manage standard and custom views. |

### Relations

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `relations` | `spaceId: ID!` | `[Relation!]!` | Manage inter-space relations and column display preferences. |
| `gridColumnPrefs` | `spaceId: ID!` | `JSON!` | Manage inter-space relations and column display preferences. |

### Data (records)

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `records` | `spaceId: ID!, filter: RecordFilter, limit: Int, offset: Int, reprFormula: String, reprLanguage: String` | `RecordPage!` | Read/write user records. |
| `record` | `spaceId: ID!, id: ID!` | `Record` | Read/write user records. |
| `aggregateSpace` | `spaceName: String! groupBy: [String!]! aggregate: [AggregateInput!]!` | `[JSON]` | Read/write user records. |

### Authentication

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `me` | `-` | `User` | Authentication, sessions and password lifecycle. |

### Users & Groups

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `users` | `-` | `[User!]!` | Administration for users, groups and permissions. |
| `user` | `id: ID!` | `User` | Administration for users, groups and permissions. |
| `groups` | `-` | `[Group!]!` | Administration for users, groups and permissions. |
| `group` | `id: ID!` | `Group` | Administration for users, groups and permissions. |

### Snapshots

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `exportSnapshot` | `includeData: Boolean!` | `String!` | Export, diff and import configuration snapshots. |
| `diffSnapshot` | `yaml: String!` | `SnapshotDiff!` | Export, diff and import configuration snapshots. |

## Mutations

### Spaces & Fields

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createSpace` | `input: CreateSpaceInput!` | `Space!` | Mutation operation on space/field metadata. |
| `updateSpace` | `id: ID!, input: UpdateSpaceInput!` | `Space!` | Mutation operation on space/field metadata. |
| `deleteSpace` | `id: ID!` | `Boolean!` | Mutation operation on space/field metadata. |
| `addField` | `spaceId: ID!, input: FieldInput!` | `Field!` | Mutation operation on space/field metadata. |
| `addFields` | `spaceId: ID!, inputs: [FieldInput!]!` | `[Field!]!` | Mutation operation on space/field metadata. |
| `removeField` | `fieldId: ID!` | `Boolean!` | Mutation operation on space/field metadata. |
| `reorderFields` | `spaceId: ID!, fieldIds: [ID!]!` | `[Field!]!` | Mutation operation on space/field metadata. |
| `updateField` | `fieldId: ID!, input: UpdateFieldInput!` | `Field!` | Mutation operation on space/field metadata. |
| `changeFieldType` | `fieldId: ID!, input: ChangeFieldTypeInput!` | `Field!` | Mutation operation on space/field metadata. |

### Views

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createView` | `spaceId: ID!, input: CreateViewInput!` | `View!` | Manage standard and custom views. |
| `updateView` | `id: ID!, input: UpdateViewInput!` | `View!` | Manage standard and custom views. |
| `deleteView` | `id: ID!` | `Boolean!` | Manage standard and custom views. |
| `createCustomView` | `input: CreateCustomViewInput!` | `CustomView!` | Manage standard and custom views. |
| `updateCustomView` | `id: ID!, input: UpdateCustomViewInput!` | `CustomView!` | Manage standard and custom views. |
| `deleteCustomView` | `id: ID!` | `Boolean!` | Manage standard and custom views. |

### Relations

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createRelation` | `input: CreateRelationInput!` | `Relation!` | Manage inter-space relations and column display preferences. |
| `deleteRelation` | `id: ID!` | `Boolean!` | Manage inter-space relations and column display preferences. |
| `updateRelation` | `id: ID!, input: UpdateRelationInput!` | `Relation!` | Manage inter-space relations and column display preferences. |
| `saveGridColumnPrefs` | `spaceId: ID!, prefs: JSON!, asDefault: Boolean` | `Boolean!` | Manage inter-space relations and column display preferences. |

### Data (records)

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `insertRecord` | `spaceId: ID!, data: JSON!` | `Record!` | Read/write user records. |
| `updateRecord` | `spaceId: ID!, id: ID!, data: JSON!` | `Record!` | Read/write user records. |
| `deleteRecord` | `spaceId: ID!, id: ID!` | `Boolean!` | Read/write user records. |
| `deleteRecords` | `spaceId: ID!, ids: [ID!]!` | `[Boolean!]!` | Read/write user records. |
| `insertRecords` | `spaceId: ID!, data: [JSON!]!` | `[Record!]!` | Read/write user records. |
| `updateRecords` | `spaceId: ID!, records: [RecordUpdateInput!]!` | `[Record!]!` | Read/write user records. |
| `restoreRecords` | `spaceId: ID!, records: [RecordUpdateInput!]!` | `[Record!]!` | Read/write user records. |

### Authentication

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `login` | `username: String!, password: String!` | `AuthPayload!` | Authentication, sessions and password lifecycle. |
| `logout` | `-` | `Boolean!` | Authentication, sessions and password lifecycle. |
| `changePassword` | `currentPassword: String!, newPassword: String!` | `Boolean!` | Authentication, sessions and password lifecycle. |
| `adminSetPassword` | `userId: ID!, newPassword: String!` | `Boolean!` | Authentication, sessions and password lifecycle. |

### Users & Groups

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createUser` | `input: CreateUserInput!` | `User!` | Administration for users, groups and permissions. |
| `createGroup` | `input: CreateGroupInput!` | `Group!` | Administration for users, groups and permissions. |
| `deleteGroup` | `id: ID!` | `Boolean!` | Administration for users, groups and permissions. |
| `addMember` | `userId: ID!, groupId: ID!` | `Boolean!` | Administration for users, groups and permissions. |
| `removeMember` | `userId: ID!, groupId: ID!` | `Boolean!` | Administration for users, groups and permissions. |
| `grant` | `groupId: ID!, input: PermissionInput!` | `Permission!` | Administration for users, groups and permissions. |
| `revoke` | `permissionId: ID!` | `Boolean!` | Administration for users, groups and permissions. |

### Snapshots

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `importSnapshot` | `yaml: String!, mode: ImportMode!` | `ImportResult!` | Export, diff and import configuration snapshots. |

## Usage Examples

### 1) Authenticate then query spaces

```graphql
mutation Login($u: String!, $p: String!) {
  login(username: $u, password: $p) { token user { id username } }
}
```

```graphql
query { spaces { id name description } }
```

### 2) Paginated records query

```graphql
query Records($spaceId: ID!, $limit: Int!, $offset: Int!) {
  records(spaceId: $spaceId, limit: $limit, offset: $offset) {
    total
    items { id data }
  }
}
```

### 3) Structural mutation: create space and field

```graphql
mutation CreateSpace($input: CreateSpaceInput!) {
  createSpace(input: $input) { id name }
}
```

```graphql
mutation AddField($spaceId: ID!, $input: FieldInput!) {
  addField(spaceId: $spaceId, input: $input) { id name fieldType }
}
```

## Input Types

- `RecordUpdateInput`
- `RecordFilter`
- `UpdateFieldInput`
- `CreateSpaceInput`
- `UpdateSpaceInput`
- `FieldInput`
- `ChangeFieldTypeInput`
- `CreateViewInput`
- `UpdateViewInput`
- `CreateRelationInput`
- `UpdateRelationInput`
- `CreateCustomViewInput`
- `UpdateCustomViewInput`
- `CreateUserInput`
- `CreateGroupInput`
- `PermissionInput`
- `AggregateInput`

## Enums

- `FieldType`
- `ViewType`
- `FilterOp`
- `PermissionLevel`
- `ImportMode`

## Notes

- Dynamic user-space types are rebuilt by backend schema reinitialization.
- To refresh SDL runtime snapshot: `make sdl-gen`.
