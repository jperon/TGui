# API GraphQL de TGui

L'API est accessible via HTTP POST sur `/graphql`.  
Toutes les requêtes doivent inclure l'en-tête `Authorization: Bearer <token>` sauf `login`.

```
POST http://localhost:8080/graphql
Content-Type: application/json
Authorization: Bearer <token>

{"query": "...", "variables": {...}}
```

---

## Scalaires

| Scalaire | Description |
|----------|-------------|
| `ID`     | Chaîne opaque (UUID en pratique) |
| `String` | Chaîne UTF-8 |
| `Int`    | Entier 32 bits |
| `Float`  | Flottant 64 bits |
| `Boolean`| Booléen |
| `JSON`   | Valeur JSON quelconque (objet, tableau, scalaire) – sérialisée en chaîne dans les arguments |
| `Any`    | Valeur quelconque passée telle quelle (listes, objets, scalaires) – retournée sans coercition |

---

## Authentification

### `mutation login`
```graphql
mutation {
  login(username: "admin", password: "secret") {
    token
    user { id username email }
  }
}
```
Retourne un `AuthPayload` contenant le token de session à utiliser dans tous les appels suivants.

### `mutation logout`
```graphql
mutation {
  logout
}
```
Invalide la session courante. Retourne `true`.

### `mutation createUser`
```graphql
mutation {
  createUser(input: { username: "alice", email: "alice@example.com", password: "s3cr3t" }) {
    id username email
  }
}
```

### `query me`
```graphql
query {
  me { id username email groups { id name } }
}
```

---

## Espaces (tables)

Un **espace** est une table de données définie par l'utilisateur.

### `query spaces`
```graphql
query {
  spaces {
    id name description createdAt updatedAt
    fields { id name fieldType notNull position }
  }
}
```

### `query space`
```graphql
query {
  space(id: "uuid") {
    id name fields { id name fieldType }
  }
}
```

### `mutation createSpace`
```graphql
mutation {
  createSpace(input: { name: "personnes", description: "Liste des personnes" }) {
    id name
  }
}
```

### `mutation updateSpace`
```graphql
mutation {
  updateSpace(id: "uuid", input: { name: "membres", description: "..." }) {
    id name
  }
}
```

### `mutation deleteSpace`
```graphql
mutation {
  deleteSpace(id: "uuid")
}
```

---

## Champs

Les champs définissent la structure d'un espace. Leur ordre est géré via `position`.

### Types de champs (`FieldType`)

| Valeur | Description | Scalaire GraphQL |
|--------|-------------|-----------------|
| `String` | Texte | `String` |
| `Int` | Entier | `Int` |
| `Float` | Nombre décimal | `Float` |
| `Boolean` | Vrai/faux | `Boolean` |
| `ID` | Identifiant (chaîne) | `ID` |
| `UUID` | UUID v4 | `ID` |
| `Sequence` | Auto-incrément géré par Tarantool — non modifiable, non editable | `Int` |
| `Any` | Valeur quelconque (liste, objet, scalaire) — retournée sans coercition | `Any` |
| `Map` | Objet JSON (clés string → valeurs quelconques) | `Any` |
| `Array` | Tableau JSON | `Any` |

`Map`, `Array` et `Any` sont tous trois exposés via le scalaire GraphQL `Any` (passage direct,
sans coercition). Les valeurs correspondantes sont stockées dans le document JSON de
l'enregistrement et retournées telles quelles (tableau ou objet Lua → JSON natif dans la réponse).

### `mutation addField`
```graphql
mutation {
  addField(spaceId: "uuid", input: {
    name: "prenom"
    fieldType: String
    notNull: false
    description: "Prénom"
  }) {
    id name fieldType position formula
  }
}
```

Pour un champ calculé, ajouter `formula` (voir [Champs calculés](#champs-calculés--formula-columns)) :
```graphql
mutation {
  addField(spaceId: "uuid", input: {
    name:      "nom_complet"
    fieldType: String
    formula:   "self.prenom .. ' ' .. self.nom"
  }) {
    id name formula
  }
}
```

### `mutation removeField`
```graphql
mutation {
  removeField(fieldId: "uuid")
}
```

### `mutation reorderFields`
Réordonne les champs d'un espace. `fieldIds` doit contenir tous les IDs dans l'ordre souhaité.
```graphql
mutation {
  reorderFields(spaceId: "uuid", fieldIds: ["id1", "id2", "id3"]) {
    id name position
  }
}
```

---

## Enregistrements

Les données des espaces sont stockées sous forme de documents JSON.

### `query records`
```graphql
query {
  records(spaceId: "uuid", limit: 100, offset: 0) {
    total offset limit
    items { id data }
  }
}
```

Avec filtre :
```graphql
query {
  records(spaceId: "uuid", filter: { field: "nom", op: CONTAINS, value: "Martin" }) {
    items { id data }
  }
}
```

#### Opérateurs de filtre (`FilterOp`)
`EQ` · `NEQ` · `LT` · `GT` · `LTE` · `GTE` · `CONTAINS` · `STARTS_WITH`

#### Filtres composés (`and` / `or`)

`RecordFilter` est récursif : les champs `and` et `or` acceptent une liste de sous-filtres.

```graphql
# AND : annee = 2025 ET choeur = 1
filter: { and: [
  { field: "annee", op: EQ, value: "2025" },
  { field: "choeur", op: EQ, value: "1" }
]}

# OR : pupitre contient "T" OU pupitre contient "B"
filter: { or: [
  { field: "pupitre", op: CONTAINS, value: "T" },
  { field: "pupitre", op: CONTAINS, value: "B" }
]}

# Combinaison arbitraire (ici : nom = "Dupont" ET (annee = 2025 OU annee = 2026))
filter: {
  field: "nom", op: EQ, value: "Dupont"
  and: [{ or: [
    { field: "annee", op: EQ, value: "2025" },
    { field: "annee", op: EQ, value: "2026" }
  ]}]
}
```

`and` et `or` peuvent être imbriqués à profondeur arbitraire.
Un `RecordFilter` peut ne contenir que `and` ou `or` (sans condition primaire),
auquel cas il sert de pur combinateur logique.

### `query record`
```graphql
query {
  record(spaceId: "uuid", id: "record-uuid") {
    id data
  }
}
```

### `mutation insertRecord`
`data` est un objet JSON sérialisé en chaîne. Les champs `Sequence` sont ignorés (auto-générés).
```graphql
mutation {
  insertRecord(spaceId: "uuid", data: "{\"nom\":\"Dupont\",\"prenom\":\"Alice\"}") {
    id data
  }
}
```

### `mutation updateRecord`
Seuls les champs fournis dans `data` sont mis à jour (merge partiel). Les champs `Sequence` sont immuables.
```graphql
mutation {
  updateRecord(spaceId: "uuid", id: "record-uuid", data: "{\"nom\":\"Martin\"}") {
    id data
  }
}
```

### `mutation deleteRecord`
```graphql
mutation {
  deleteRecord(spaceId: "uuid", id: "record-uuid")
}
```

---

## Requêtes typées par espace

En plus de l'API générique `records(spaceId: ...)`, chaque espace dispose automatiquement
d'une **requête typée** portant son nom (en minuscules, caractères non alphanumériques
remplacés par `_`).  Ces requêtes sont générées dynamiquement au démarrage (et lors de
toute modification de schéma) à partir des métadonnées de l'espace.

### Structure

```graphql
query {
  <nomEspace>(limit: Int, offset: Int, filter: RecordFilter) {
    items { ... }
    total
    offset
    limit
  }
}
```

Chaque item est de type `<nomEspace>_record` et expose :

| Champ | Type | Description |
|-------|------|-------------|
| `_id` | `ID!` | Clé primaire interne Tarantool (UUID) |
| *champs scalaires* | `String` / `Int` / `Float` / `Boolean` / `ID` | Valeurs brutes selon le type de champ |
| *champs FK* | `<espaceTarget>_record` | Navigation directe vers l'enregistrement référencé |
| *rétro-références* | `<espaceSource>_page!` | Tous les enregistrements de l'espace source qui pointent vers cet enregistrement |

### Exemple — scalaires seuls

```graphql
{
  personnes {
    total
    items { nom particule prenom }
  }
}
```

### Exemple — rétro-référence (one-to-many)

`choriste` est le nom de la relation définie de `chorale → personnes`.  
Sur `personnes_record`, elle apparaît comme un champ retournant une page de choristes.

```graphql
{
  personnes {
    items {
      nom
      prenom
      choriste {
        items { annee pupitre choeur }
      }
    }
  }
}
```

### Exemple — navigation FK (many-to-one)

Sur `chorale_record`, le champ FK `choriste` renvoie directement l'enregistrement `personnes_record`.

```graphql
{
  chorale {
    items {
      annee
      pupitre
      choriste { nom prenom }
    }
  }
}
```

### Exemple — récupérer la valeur brute d'une FK

Pour obtenir la valeur brute (l'identifiant stocké), demandez `_id` dans le sous-objet :

```graphql
{
  chorale {
    items {
      choriste { _id }
    }
  }
}
```

### Pagination et filtre

Les arguments `limit`, `offset` et `filter` fonctionnent de la même façon que pour `records` :

```graphql
{
  personnes(limit: 20, offset: 0, filter: { field: "nom", op: CONTAINS, value: "Mar" }) {
    total
    items { nom prenom }
  }
}
```

### Mise à jour automatique du schéma

Toute mutation structurelle (`addField`, `removeField`, `createRelation`, `deleteRelation`,
`createSpace`, `deleteSpace`) déclenche automatiquement une régénération du schéma GraphQL.
Les nouvelles requêtes typées sont disponibles immédiatement sans redémarrage.

---

## Champs calculés — formula columns

Un champ calculé est un champ virtuel dont la valeur est **calculée à la lecture**
à partir d'une formule Lua. Il n'est jamais stocké en base.

Pour créer un champ calculé, passer `formula` dans `addField` :

```graphql
mutation {
  addField(spaceId: "uuid", input: {
    name:      "nom_complet"
    fieldType: String
    formula:   "self.prenom .. ' ' .. self.nom"
  }) {
    id name fieldType formula
  }
}
```

Le `fieldType` indique le type de retour attendu (pour la cohérence de l'API GraphQL).  
Si la valeur retournée par la formule peut être de n'importe quel type (liste, objet,
scalaire), utiliser `fieldType: Any`.

### Langue des formules

La formule est une **expression Lua** dont le résultat est retourné comme valeur du champ.

#### `self` — enregistrement courant

`self` est un proxy Lua sur l'enregistrement courant. Les champs scalaires sont accessibles
directement :

```lua
self.prenom .. " " .. self.nom         -- concaténation de chaînes
(self.montant or 0) * 1.2              -- arithmétique avec garde nil
math.floor(self.note)                  -- fonctions Lua standard
```

#### Navigation par clé étrangère

Si un champ est une **clé étrangère** vers un autre espace, `self.<champ>` renvoie
automatiquement l'enregistrement référencé (résolution lazy, mis en cache) :

```lua
-- choriste est un FK vers l'espace "personnes"
self.choriste.nom .. " " .. self.choriste.prenom

-- chaîner plusieurs niveaux
self.choriste.groupe.nom
```

L'enregistrement référencé est chargé à la première accès et mis en cache dans le proxy
(pas de chargement répété si on y accède plusieurs fois dans la même formule).

#### `space(name)` — accès à un autre espace

La fonction `space(name)` retourne la liste de **tous les enregistrements** de l'espace
nommé sous forme d'une table Lua :

```lua
-- Compter les enregistrements d'un autre espace
#space("commandes")

-- Agréger des valeurs
local total = 0
for _, item in ipairs(space("lignes")) do
  total = total + (item.montant or 0)
end
return total

-- Filtrer
local actifs = {}
for _, m in ipairs(space("membres")) do
  if m.actif then actifs[#actifs+1] = m end
end
return #actifs
```

> **Note** : `space()` retourne tous les enregistrements sans filtre ni pagination.
> Pour de grands espaces, préférer des calculs simples (comptage, agrégation scalaire).

#### Gardes nil

Les champs absents ou non renseignés valent `nil` en Lua. Toujours les garder :

```lua
(self.particule ~= nil and self.particule ~= "") and
  (self.prenom .. " " .. self.particule .. " " .. self.nom)
  or (self.prenom .. " " .. self.nom)
```

### Comportement

| Propriété | Valeur |
|-----------|--------|
| Stockage | Aucun — calculé à chaque lecture |
| Pré-compilation | La formule est compilée une fois au démarrage (ou après `addField`) |
| Erreur d'exécution | Retourne `null` (l'erreur est loguée côté serveur via `pcall`) |
| Editable | Non — la colonne est en lecture seule dans le frontend |
| Filtrable | Oui, via `filter` dans les requêtes typées (scan complet) |
| Indexable | Non |

### Exemples complets

```graphql
# Champ texte : nom complet
mutation { addField(spaceId: "uuid", input: {
  name: "nom_complet", fieldType: String
  formula: "self.prenom .. ' ' .. self.nom"
}) { id } }

# Champ entier : nombre total d'enregistrements dans un autre espace
mutation { addField(spaceId: "uuid", input: {
  name: "nb_choristes", fieldType: Int
  formula: "#space('chorale')"
}) { id } }

# Champ Any : liste des années de participation
mutation { addField(spaceId: "uuid", input: {
  name: "annees", fieldType: Any
  formula: """
    local result = {}
    for _, r in ipairs(space("chorale")) do
      if tostring(r.choriste_id) == tostring(self._id) then
        result[#result+1] = r.annee
      end
    end
    return result
  """
}) { id } }
```

---

## Relations (clés étrangères)

Une relation lie un champ d'un espace source à un champ d'un espace cible.

### `query relations`
```graphql
query {
  relations(spaceId: "uuid") {
    id name fromSpaceId fromFieldId toSpaceId toFieldId
  }
}
```

### `mutation createRelation`
```graphql
mutation {
  createRelation(input: {
    name:        "choriste_personne"
    fromSpaceId: "uuid-choristes"
    fromFieldId: "uuid-field-personne_id"
    toSpaceId:   "uuid-personnes"
    toFieldId:   "uuid-field-id"
  }) {
    id name
  }
}
```

### `mutation deleteRelation`
```graphql
mutation {
  deleteRelation(id: "uuid")
}
```

---

## Vues personnalisées (tableaux de bord YAML)

Les **vues personnalisées** sont des mises en page YAML stockées côté serveur (voir [`Views.md`](Views.md)).

### `query customViews`
```graphql
query {
  customViews { id name description yaml createdAt updatedAt }
}
```

### `query customView`
```graphql
query {
  customView(id: "uuid") { id name yaml }
}
```

### `mutation createCustomView`
```graphql
mutation {
  createCustomView(input: {
    name: "Tableau de bord"
    description: "Vue principale"
    yaml: "layout:\n  direction: vertical\n  children: []"
  }) {
    id name
  }
}
```

### `mutation updateCustomView`
```graphql
mutation {
  updateCustomView(id: "uuid", input: { yaml: "layout:\n  ..." }) {
    id name yaml
  }
}
```

### `mutation deleteCustomView`
```graphql
mutation {
  deleteCustomView(id: "uuid")
}
```

---

## Vues (par espace)

Les vues sont des métadonnées associées à un espace (non utilisées dans le frontend actuel).

### Types de vue (`ViewType`)
`grid` · `form` · `gallery`

### `query views`
```graphql
query {
  views(spaceId: "uuid") { id name viewType config }
}
```

### `mutation createView`
```graphql
mutation {
  createView(spaceId: "uuid", input: { name: "Grille", viewType: grid }) {
    id name viewType
  }
}
```

---

## Groupes et permissions

### `query groups` / `query group`
```graphql
query {
  groups {
    id name description
    members { id username }
    permissions { id resourceType resourceId level }
  }
}
```

### `mutation createGroup` / `mutation deleteGroup`
```graphql
mutation { createGroup(input: { name: "editeurs", description: "..." }) { id } }
mutation { deleteGroup(id: "uuid") }
```

### `mutation addMember` / `mutation removeMember`
```graphql
mutation { addMember(userId: "uuid", groupId: "uuid") }
mutation { removeMember(userId: "uuid", groupId: "uuid") }
```

### `mutation grant`
Niveaux : `read` · `write` · `admin`
```graphql
mutation {
  grant(groupId: "uuid", input: {
    resourceType: "space"
    resourceId:   "uuid-space"
    level:        write
  }) {
    id level
  }
}
```

### `mutation revoke`
```graphql
mutation { revoke(permissionId: "uuid") }
```

## Trigger formulas — champs calculés à l'écriture

Une **trigger formula** est une formule associée à un champ stocké, exécutée
**au moment de l'écriture** d'un enregistrement (INSERT ou UPDATE). Contrairement
aux formula columns (virtuelles, calculées à chaque lecture), la valeur calculée est
**stockée en base** et reste visible même si la formule est modifiée ultérieurement.

### Distinction formula column / trigger formula

| | Formula column | Trigger formula |
|---|---|---|
| `formula` | oui | oui |
| `triggerFields` | absent | présent (liste, éventuellement vide) |
| Exécution | Chaque lecture | À l'écriture |
| Valeur stockée | Non | Oui |
| Colonne éditable | Non | Oui (peut être overridée) |

### Créer une trigger formula

Passer **à la fois** `formula` et `triggerFields` dans `addField` :

```graphql
mutation {
  addField(spaceId: "uuid", input: {
    name:          "nom_complet"
    fieldType:     String
    formula:       "self.prenom .. ' ' .. self.nom"
    triggerFields: ["prenom", "nom"]
  }) {
    id name fieldType formula triggerFields
  }
}
```

### Sémantique de `triggerFields`

| Valeur | Comportement |
|---|---|
| `[]` | Exécuté uniquement à la **création** de l'enregistrement |
| `["*"]` | Exécuté à la création et à **tout changement** |
| `["nom", "prenom"]` | Exécuté à la création et quand `nom` ou `prenom` changent |

### Contexte d'exécution

Identique aux formula columns :
- `self` : proxy Lua sur le nouvel état entrant du tuple
- Navigation FK lazy : `self.choriste.pupitre`
- `space(name)` : liste des enregistrements d'un autre espace

```lua
-- Valeur calculée lors de la création et quand prenom/nom changent
self.prenom .. " " .. (self.particule and self.particule .. " " or "") .. self.nom

-- Exécuté à tout changement, fait référence à un champ FK
self.choriste.pupitre

-- Calculé à la création uniquement (snapshot initial)
os.date "%Y-%m-%d"   -- date d'inscription
```

### Persistance des triggers

Les triggers `before_replace` de Tarantool sont des hooks **en mémoire** : ils ne
survivent pas aux redémarrages. TGui les re-enregistre automatiquement au démarrage
depuis les métadonnées `_tdb_fields` (colonne `triggerFields`).

### Supprimer un champ trigger formula

```graphql
mutation { removeField(fieldId: "uuid") }
```

Le trigger `before_replace` est mis à jour (supprimé si c'était le seul champ calculé
de l'espace) automatiquement.
