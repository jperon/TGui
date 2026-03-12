# API GraphQL — TGui

> Fichier généré automatiquement. Ne pas modifier manuellement.
>
> Généré le: 2026-03-12 10:33:27 UTC
>
> Source: `schema/tdb.graphql`

## Vue d’ensemble

- Endpoint: `/graphql`
- Transport: HTTP POST JSON
- Auth: token Bearer dans l’en-tête `Authorization`
- Source de vérité des signatures: `schema/tdb.graphql`
- Capture d’exécution du SDL: `schema/tdb.generated.graphql`

## Queries

### Espaces & Champs

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `spaces` | `-` | `[Space!]!` | Opération de lecture sur les métadonnées d’espaces/champs. |
| `space` | `id: ID!` | `Space` | Opération de lecture sur les métadonnées d’espaces/champs. |

### Vues

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `views` | `spaceId: ID!` | `[View!]!` | Gestion des vues standard et personnalisées. |
| `view` | `id: ID!` | `View` | Gestion des vues standard et personnalisées. |
| `customViews` | `-` | `[CustomView!]!` | Gestion des vues standard et personnalisées. |
| `customView` | `id: ID!` | `CustomView` | Gestion des vues standard et personnalisées. |

### Relations

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `relations` | `spaceId: ID!` | `[Relation!]!` | Gestion des relations inter-espaces et préférences d’affichage. |
| `gridColumnPrefs` | `spaceId: ID!` | `JSON!` | Gestion des relations inter-espaces et préférences d’affichage. |

### Données (records)

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `records` | `spaceId: ID!, filter: RecordFilter, limit: Int, offset: Int, reprFormula: String, reprLanguage: String` | `RecordPage!` | Lecture/écriture des enregistrements utilisateurs. |
| `record` | `spaceId: ID!, id: ID!` | `Record` | Lecture/écriture des enregistrements utilisateurs. |
| `aggregateSpace` | `spaceName: String! groupBy: [String!]! aggregate: [AggregateInput!]!` | `[JSON]` | Lecture/écriture des enregistrements utilisateurs. |

### Authentification

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `me` | `-` | `User` | Authentification, session et gestion du mot de passe. |

### Utilisateurs & Groupes

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `users` | `-` | `[User!]!` | Administration des utilisateurs, groupes et permissions. |
| `user` | `id: ID!` | `User` | Administration des utilisateurs, groupes et permissions. |
| `groups` | `-` | `[Group!]!` | Administration des utilisateurs, groupes et permissions. |
| `group` | `id: ID!` | `Group` | Administration des utilisateurs, groupes et permissions. |

### Snapshots

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `exportSnapshot` | `includeData: Boolean!` | `String!` | Export, comparaison et import des snapshots de configuration. |
| `diffSnapshot` | `yaml: String!` | `SnapshotDiff!` | Export, comparaison et import des snapshots de configuration. |

## Mutations

### Espaces & Champs

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createSpace` | `input: CreateSpaceInput!` | `Space!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `updateSpace` | `id: ID!, input: UpdateSpaceInput!` | `Space!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `deleteSpace` | `id: ID!` | `Boolean!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `addField` | `spaceId: ID!, input: FieldInput!` | `Field!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `addFields` | `spaceId: ID!, inputs: [FieldInput!]!` | `[Field!]!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `removeField` | `fieldId: ID!` | `Boolean!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `reorderFields` | `spaceId: ID!, fieldIds: [ID!]!` | `[Field!]!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `updateField` | `fieldId: ID!, input: UpdateFieldInput!` | `Field!` | Opération de mutation sur les métadonnées d’espaces/champs. |
| `changeFieldType` | `fieldId: ID!, input: ChangeFieldTypeInput!` | `Field!` | Opération de mutation sur les métadonnées d’espaces/champs. |

### Vues

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createView` | `spaceId: ID!, input: CreateViewInput!` | `View!` | Gestion des vues standard et personnalisées. |
| `updateView` | `id: ID!, input: UpdateViewInput!` | `View!` | Gestion des vues standard et personnalisées. |
| `deleteView` | `id: ID!` | `Boolean!` | Gestion des vues standard et personnalisées. |
| `createCustomView` | `input: CreateCustomViewInput!` | `CustomView!` | Gestion des vues standard et personnalisées. |
| `updateCustomView` | `id: ID!, input: UpdateCustomViewInput!` | `CustomView!` | Gestion des vues standard et personnalisées. |
| `deleteCustomView` | `id: ID!` | `Boolean!` | Gestion des vues standard et personnalisées. |

### Relations

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createRelation` | `input: CreateRelationInput!` | `Relation!` | Gestion des relations inter-espaces et préférences d’affichage. |
| `deleteRelation` | `id: ID!` | `Boolean!` | Gestion des relations inter-espaces et préférences d’affichage. |
| `updateRelation` | `id: ID!, input: UpdateRelationInput!` | `Relation!` | Gestion des relations inter-espaces et préférences d’affichage. |
| `saveGridColumnPrefs` | `spaceId: ID!, prefs: JSON!, asDefault: Boolean` | `Boolean!` | Gestion des relations inter-espaces et préférences d’affichage. |

### Données (records)

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `insertRecord` | `spaceId: ID!, data: JSON!` | `Record!` | Lecture/écriture des enregistrements utilisateurs. |
| `updateRecord` | `spaceId: ID!, id: ID!, data: JSON!` | `Record!` | Lecture/écriture des enregistrements utilisateurs. |
| `deleteRecord` | `spaceId: ID!, id: ID!` | `Boolean!` | Lecture/écriture des enregistrements utilisateurs. |
| `deleteRecords` | `spaceId: ID!, ids: [ID!]!` | `[Boolean!]!` | Lecture/écriture des enregistrements utilisateurs. |
| `insertRecords` | `spaceId: ID!, data: [JSON!]!` | `[Record!]!` | Lecture/écriture des enregistrements utilisateurs. |
| `updateRecords` | `spaceId: ID!, records: [RecordUpdateInput!]!` | `[Record!]!` | Lecture/écriture des enregistrements utilisateurs. |
| `restoreRecords` | `spaceId: ID!, records: [RecordUpdateInput!]!` | `[Record!]!` | Lecture/écriture des enregistrements utilisateurs. |

### Authentification

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `login` | `username: String!, password: String!` | `AuthPayload!` | Authentification, session et gestion du mot de passe. |
| `logout` | `-` | `Boolean!` | Authentification, session et gestion du mot de passe. |
| `changePassword` | `currentPassword: String!, newPassword: String!` | `Boolean!` | Authentification, session et gestion du mot de passe. |
| `adminSetPassword` | `userId: ID!, newPassword: String!` | `Boolean!` | Authentification, session et gestion du mot de passe. |

### Utilisateurs & Groupes

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `createUser` | `input: CreateUserInput!` | `User!` | Administration des utilisateurs, groupes et permissions. |
| `createGroup` | `input: CreateGroupInput!` | `Group!` | Administration des utilisateurs, groupes et permissions. |
| `deleteGroup` | `id: ID!` | `Boolean!` | Administration des utilisateurs, groupes et permissions. |
| `addMember` | `userId: ID!, groupId: ID!` | `Boolean!` | Administration des utilisateurs, groupes et permissions. |
| `removeMember` | `userId: ID!, groupId: ID!` | `Boolean!` | Administration des utilisateurs, groupes et permissions. |
| `grant` | `groupId: ID!, input: PermissionInput!` | `Permission!` | Administration des utilisateurs, groupes et permissions. |
| `revoke` | `permissionId: ID!` | `Boolean!` | Administration des utilisateurs, groupes et permissions. |

### Snapshots

| Opération | Arguments | Retour | Description |
|---|---|---|---|
| `importSnapshot` | `yaml: String!, mode: ImportMode!` | `ImportResult!` | Export, comparaison et import des snapshots de configuration. |

## Exemples d’usage

### 1) Authentification puis lecture des espaces

```graphql
mutation Login($u: String!, $p: String!) {
  login(username: $u, password: $p) { token user { id username } }
}
```

```graphql
query { spaces { id name description } }
```

### 2) Lecture paginée de records avec filtre

```graphql
query Records($spaceId: ID!, $limit: Int!, $offset: Int!) {
  records(spaceId: $spaceId, limit: $limit, offset: $offset) {
    total
    items { id data }
  }
}
```

### 3) Mutation structurelle: créer un espace puis un champ

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

## Types d'entrée

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

- Les types dynamiques liés aux espaces utilisateur sont reconstruits côté backend.
- Pour régénérer une capture SDL d’exécution: `make sdl-gen`.
