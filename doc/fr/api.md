# GraphQL API — TGui

> Auto-generated file. Do not edit manually.
>
> Generated at: 2026-06-13 10:32:02 UTC
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

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `spaces` | `-` | `[Space!]!` | Read operation on space/field metadata. |
| `space` | `id: ID!` | `Space` | Read operation on space/field metadata. |

### Views

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `views` | `spaceId: ID!` | `[View!]!` | Manage standard and custom views. |
| `view` | `id: ID!` | `View` | Manage standard and custom views. |
| `customViews` | `-` | `[CustomView!]!` | Manage standard and custom views. |
| `customView` | `id: ID!` | `CustomView` | Manage standard and custom views. |

### Data Views

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `dataViews` | `-` | `[DataView!]!` | Create, update and execute Data Views (server-side filters, joins and aggregations). |
| `dataView` | `id: ID!` | `DataView` | Create, update and execute Data Views (server-side filters, joins and aggregations). |
| `executeDataView` | `id: ID!, limit: Int, offset: Int` | `[JSON!]!` | Create, update and execute Data Views (server-side filters, joins and aggregations). |

### Widget Plugins

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `widgetPlugins` | `-` | `[WidgetPlugin!]!` | Manage custom widget plugins (script + template) usable in views. |
| `widgetPlugin` | `id: ID, name: String` | `WidgetPlugin` | Manage custom widget plugins (script + template) usable in views. |

### Layouts & Zones

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `exportLayout` | `pageId: ID!` | `String!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `listLayoutSnapshots` | `pageId: ID!` | `[LayoutSnapshot!]!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |

### Relations

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `relations` | `spaceId: ID!` | `[Relation!]!` | Manage inter-space relations and column display preferences. |
| `gridColumnPrefs` | `spaceId: ID!` | `JSON!` | Manage inter-space relations and column display preferences. |

### Data (records)

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `records` | `spaceId: ID!, filter: RecordFilter, limit: Int, offset: Int, reprFormula: String, reprLanguage: String` | `RecordPage!` | Read/write user records. |
| `record` | `spaceId: ID!, id: ID!` | `Record` | Read/write user records. |
| `aggregateSpace` | `spaceName: String! groupBy: [String!]! aggregate: [AggregateInput!]!` | `[JSON]` | Read/write user records. |

### Authentication

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `me` | `-` | `User` | Authentication, sessions and password lifecycle. |

### Users & Groups

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `users` | `-` | `[User!]!` | Administration for users, groups and permissions. |
| `user` | `id: ID!` | `User` | Administration for users, groups and permissions. |
| `groups` | `-` | `[Group!]!` | Administration for users, groups and permissions. |
| `group` | `id: ID!` | `Group` | Administration for users, groups and permissions. |

### Snapshots

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `exportSnapshot` | `includeData: Boolean!, compress: Boolean` | `String!` | Export, diff and import configuration snapshots. |
| `diffSnapshot` | `yaml: String!` | `SnapshotDiff!` | Export, diff and import configuration snapshots. |

## Mutations

### Spaces & Fields

| Operation | Arguments | Return | Description |
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

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `createView` | `spaceId: ID!, input: CreateViewInput!` | `View!` | Manage standard and custom views. |
| `updateView` | `id: ID!, input: UpdateViewInput!` | `View!` | Manage standard and custom views. |
| `deleteView` | `id: ID!` | `Boolean!` | Manage standard and custom views. |
| `createCustomView` | `input: CreateCustomViewInput!` | `CustomView!` | Manage standard and custom views. |
| `updateCustomView` | `id: ID!, input: UpdateCustomViewInput!` | `CustomView!` | Manage standard and custom views. |
| `deleteCustomView` | `id: ID!` | `Boolean!` | Manage standard and custom views. |

### Data Views

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `createDataView` | `input: DataViewInput!` | `DataView!` | Create, update and execute Data Views (server-side filters, joins and aggregations). |
| `updateDataView` | `id: ID!, input: DataViewInput!` | `DataView!` | Create, update and execute Data Views (server-side filters, joins and aggregations). |
| `deleteDataView` | `id: ID!` | `Boolean!` | Create, update and execute Data Views (server-side filters, joins and aggregations). |
| `addDataViewToPage` | `pageId: ID!, dataViewId: ID!` | `CustomView!` | Create, update and execute Data Views (server-side filters, joins and aggregations). |

### Widget Plugins

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `createWidgetPlugin` | `input: CreateWidgetPluginInput!` | `WidgetPlugin!` | Manage custom widget plugins (script + template) usable in views. |
| `updateWidgetPlugin` | `id: ID!, input: UpdateWidgetPluginInput!` | `WidgetPlugin!` | Manage custom widget plugins (script + template) usable in views. |
| `deleteWidgetPlugin` | `id: ID!` | `Boolean!` | Manage custom widget plugins (script + template) usable in views. |

### Layouts & Zones

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `addWidgetToView` | `viewId: ID!, widget: WidgetInput!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `reorderWidgets` | `pageId: ID!, widgetPositions: [WidgetPosition!]!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `updateWidgetInView` | `viewId: ID!, widgetId: String!, widget: WidgetInput!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `removeWidgetFromView` | `viewId: ID!, widgetId: String!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `importLayout` | `pageId: ID!, yaml: String!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `createLayoutSnapshot` | `pageId: ID!, yaml: String!, description: String` | `LayoutSnapshot!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `restoreLayoutSnapshot` | `snapshotId: ID!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `createZone` | `pageId: ID!, zoneData: ZoneInput!` | `Zone!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `resizeZone` | `pageId: ID!, zoneId: ID!, factor: Float!` | `Zone!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `mergeZones` | `pageId: ID!, zoneId1: ID!, zoneId2: ID!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |
| `splitZone` | `pageId: ID!, zoneId: ID!, direction: String!` | `CustomView!` | Manage page layout snapshots and zone composition (create/resize/merge/split). |

### Relations

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `createRelation` | `input: CreateRelationInput!` | `Relation!` | Manage inter-space relations and column display preferences. |
| `deleteRelation` | `id: ID!` | `Boolean!` | Manage inter-space relations and column display preferences. |
| `updateRelation` | `id: ID!, input: UpdateRelationInput!` | `Relation!` | Manage inter-space relations and column display preferences. |
| `saveGridColumnPrefs` | `spaceId: ID!, prefs: JSON!, asDefault: Boolean` | `Boolean!` | Manage inter-space relations and column display preferences. |

### Data (records)

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `insertRecord` | `spaceId: ID!, data: JSON!` | `Record!` | Read/write user records. |
| `updateRecord` | `spaceId: ID!, id: ID!, data: JSON!` | `Record!` | Read/write user records. |
| `deleteRecord` | `spaceId: ID!, id: ID!` | `Boolean!` | Read/write user records. |
| `deleteRecords` | `spaceId: ID!, ids: [ID!]!` | `[Boolean!]!` | Read/write user records. |
| `insertRecords` | `spaceId: ID!, data: [JSON!]!` | `[Record!]!` | Read/write user records. |
| `updateRecords` | `spaceId: ID!, records: [RecordUpdateInput!]!` | `[Record!]!` | Read/write user records. |
| `restoreRecords` | `spaceId: ID!, records: [RecordUpdateInput!]!` | `[Record!]!` | Read/write user records. |

### Authentication

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `login` | `username: String!, password: String!` | `AuthPayload!` | Authentication, sessions and password lifecycle. |
| `logout` | `-` | `Boolean!` | Authentication, sessions and password lifecycle. |
| `changePassword` | `currentPassword: String!, newPassword: String!` | `Boolean!` | Authentication, sessions and password lifecycle. |
| `adminSetPassword` | `userId: ID!, newPassword: String!` | `Boolean!` | Authentication, sessions and password lifecycle. |

### Users & Groups

| Operation | Arguments | Return | Description |
|---|---|---|---|
| `createUser` | `input: CreateUserInput!` | `User!` | Administration for users, groups and permissions. |
| `createGroup` | `input: CreateGroupInput!` | `Group!` | Administration for users, groups and permissions. |
| `deleteGroup` | `id: ID!` | `Boolean!` | Administration for users, groups and permissions. |
| `addMember` | `userId: ID!, groupId: ID!` | `Boolean!` | Administration for users, groups and permissions. |
| `removeMember` | `userId: ID!, groupId: ID!` | `Boolean!` | Administration for users, groups and permissions. |
| `grant` | `groupId: ID!, input: PermissionInput!` | `Permission!` | Administration for users, groups and permissions. |
| `revoke` | `permissionId: ID!` | `Boolean!` | Administration for users, groups and permissions. |

### Snapshots

| Operation | Arguments | Return | Description |
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

- `WidgetInput`
- `PositionInput`
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
- `DataViewInput`
- `CreateWidgetPluginInput`
- `UpdateWidgetPluginInput`
- `CreateUserInput`
- `CreateGroupInput`
- `PermissionInput`
- `AggregateInput`
- `WidgetPosition`
- `ZoneInput`

## Enums

- `FieldType`
- `ViewType`
- `FilterOp`
- `PermissionLevel`
- `ImportMode`

## Notes

- Dynamic user-space types are rebuilt by backend schema reinitialization.
- To refresh SDL runtime snapshot: `make sdl-gen`.
