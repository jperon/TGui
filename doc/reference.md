# Référence des fonctionnalités — tdb

**tdb** est inspiré de [Grist](https://www.getgrist.com) — pour tout usage sérieux ou en
production, l'utilisateur est invité à se tourner vers ce dernier en priorité.

tdb expose toutes ses fonctionnalités via une **API GraphQL** accessible sur
`http://localhost:8080/graphql`. L'interface web est un client de cette même API ;
tout ce qui est faisable dans l'UI l'est aussi directement via des requêtes GraphQL.

---

## Table des matières

1. [Espaces (tables)](#1-espaces-tables)
2. [Champs](#2-champs)
3. [Relations](#3-relations)
4. [Données (enregistrements)](#4-données-enregistrements)
5. [Vues classiques](#5-vues-classiques)
6. [Vues personnalisées (YAML)](#6-vues-personnalisées-yaml)
7. [Authentification](#7-authentification)
8. [Utilisateurs et groupes](#8-utilisateurs-et-groupes)
9. [Droits (permissions)](#9-droits-permissions)
10. [Export et import de snapshots](#10-export-et-import-de-snapshots)
11. [API GraphQL complète](#11-api-graphql-complète)

---

## 1. Espaces (tables)

Un **espace** est une table de données définie par l'utilisateur. Il contient des **champs**
(colonnes) et des **enregistrements** (lignes).

### Opérations UI

| Action | Comment |
|--------|---------|
| Créer | Clic sur **+** dans la section Données |
| Renommer | Bouton **(crayon)** dans la barre d'outils de l'espace |
| Supprimer | Bouton **[suppr]** (poubelle à côté du titre) |
| Naviguer | Clic sur le nom dans la barre latérale |

### API GraphQL

```graphql
# Lister tous les espaces
query {
  spaces { id name description fields { id name fieldType } }
}

# Détail d'un espace
query {
  space(id: "...") {
    id name fields { id name fieldType formula }
  }
}

# Créer
mutation {
  createSpace(input: { name: "clients", description: "..." }) { id }
}

# Renommer
mutation {
  updateSpace(id: "...", input: { name: "nouveau_nom" }) { id name }
}

# Supprimer
mutation { deleteSpace(id: "...") }
```

---

## 2. Champs

Un **champ** est une colonne d'un espace. Chaque champ a un type, un nom, et peut porter
une formule.

### Types disponibles

| Type | Description |
|------|-------------|
| `String` | Chaîne de caractères |
| `Int` | Entier |
| `Float` | Nombre décimal |
| `Boolean` | Booléen (`true` / `false`) |
| `UUID` | UUID généré automatiquement |
| `Sequence` | Entier auto-incrémenté (clé primaire naturelle) |
| `Any` | Type libre (JSON) |
| `Map` | Objet JSON |
| `Array` | Tableau JSON |
| `Relation` | Référence vers un enregistrement d'un autre espace |

### Champ calculé (colonne calculée)

Un champ calculé évalue une **expression MoonScript** à chaque lecture. La valeur n'est
**pas stockée**.

La formule est le corps d'une fonction `(self, space) -> <formule>`. En MoonScript,
`@champ` est un raccourci pour `self.champ` :

```moonscript
"#{@prenom} #{@nom}"
```

### Trigger formula

Une trigger formula est évaluée et son résultat **stocké** lors de chaque création ou
modification de l'enregistrement (ou uniquement lors du changement de champs listés dans
`triggerFields`).

```moonscript
-- Déclenché sur tout changement :
@quantite * @prix_unitaire

-- Déclenché uniquement si `titre` change :
-- (configurer triggerFields: ["titre"])
@titre\lower!\gsub "[^%w]+", "-"
```

### Langages de formule

| Valeur | Description |
|--------|-------------|
| `moonscript` | MoonScript (compilé → Lua à la volée) |
| `lua` | Lua natif |

### Helper `space` — accès aux autres espaces

Les formules et triggers reçoivent un deuxième paramètre `space` qui permet d'accéder à
tous les enregistrements d'un autre espace (full scan) :

```moonscript
-- Compter les commandes d'un client
#space("commandes")

-- Sommer une colonne filtrée
sum = 0
for r in *space("lignes")
  sum += r.montant if r.commande_id == @id
sum

-- Récupérer un libellé depuis une table de référence
next(t for t in *space("categories") when t._id == @categorie_id)?.libelle
```

`space("nom")` retourne une liste Lua de tous les enregistrements de l'espace `nom`,
chaque enregistrement étant un objet avec `_id` (identifiant), plus tous les champs de
données. Retourne `{}` si l'espace n'existe pas.

> **Attention :** le full scan est adapté aux espaces de petite taille (quelques milliers
> d'enregistrements). Pour des volumes importants, préférer les relations et les
> widgets agrégats.

### Réordonnancement

Les champs peuvent être réordonnés par glisser-déposer (::) dans le panel Champs.

### API GraphQL

```graphql
# Ajouter un champ simple
mutation {
  addField(spaceId: "...", input: {
    name: "age", fieldType: Int, notNull: false
  }) { id name }
}

# Ajouter une colonne calculée
mutation {
  addField(spaceId: "...", input: {
    name: "nom_complet", fieldType: String,
    formula: "\"#{@prenom} #{@nom}\"",
    language: "moonscript"
  }) { id }
}

# Ajouter une trigger formula
# (se déclenche sur changement de "prix" ou "qte")
mutation {
  addField(spaceId: "...", input: {
    name: "total", fieldType: Float,
    formula: "@prix * @qte",
    triggerFields: ["prix", "qte"],
    language: "moonscript"
  }) { id }
}

# Modifier un champ existant
mutation {
  updateField(fieldId: "...", input: {
    formula: "self.prenom .. \" \" .. self.nom",
    language: "lua"
  }) { id name formula }
}

# Supprimer
mutation { removeField(fieldId: "...") }

# Réordonner
mutation {
  reorderFields(
    spaceId: "...",
    fieldIds: ["id1", "id2", "id3"]
  ) { id position }
}
```

---

## 3. Relations

Une **relation** lie un champ d'un espace (champ de type `Relation`) à un autre espace.
Elle permet d'activer le filtrage dépendant dans les vues personnalisées.

Les relations **récursives** (vers l'espace lui-même) sont supportées, pour modéliser des
structures arborescentes (ex. catégories, généalogies).

### API GraphQL

```graphql
# Lister les relations d'un espace
query {
  relations(spaceId: "...") {
    id name fromFieldId toSpaceId toFieldId
  }
}

# Créer une relation
mutation {
  createRelation(input: {
    name: "appartient_à_client",
    fromSpaceId: "commandes-id",
    fromFieldId: "client_id-field-id",
    toSpaceId:   "clients-id",
    toFieldId:   "id-field-id"
  }) { id }
}

# Supprimer
mutation { deleteRelation(id: "...") }
```

---

## 4. Données (enregistrements)

### Édition dans la grille

- Clic sur une cellule pour entrer en mode édition.
- **Entrée** ou **Tab** pour valider et passer à la suivante.
- Ligne vide en bas : saisir pour créer un nouvel enregistrement.
- Cocher une ou plusieurs lignes puis cliquer **[suppr]** pour supprimer.

### Filtrage

L'API supporte un filtrage composable :

```graphql
query {
  records(
    spaceId: "..."
    filter: {
      or: [
        { field: "nom", op: STARTS_WITH, value: "Du" }
        { field: "age", op: GTE, value: "18" }
      ]
    }
    limit: 50
    offset: 0
  ) {
    items { id data }
    total
  }
}
```

### Opérateurs de filtre

| Opérateur | Signification |
|-----------|---------------|
| `EQ` | Égal à |
| `NEQ` | Différent de |
| `LT` / `GT` | Inférieur / supérieur (strict) |
| `LTE` / `GTE` | Inférieur / supérieur ou égal |
| `CONTAINS` | Contient la sous-chaîne |
| `STARTS_WITH` | Commence par |

### API GraphQL

```graphql
# Lire les enregistrements
query {
  records(spaceId: "...", limit: 100) {
    items { id data } total
  }
}

# Lire un seul enregistrement
query { record(spaceId: "...", id: "42") { id data } }

# Insérer
mutation {
  insertRecord(
    spaceId: "...",
    data: { nom: "Dupont", prenom: "Jean" }
  ) { id data }
}

# Modifier
mutation {
  updateRecord(spaceId: "...", id: "42", data: { nom: "Martin" }) {
    id data
  }
}

# Supprimer
mutation { deleteRecord(spaceId: "...", id: "42") }
```

---

## 5. Vues classiques

Les **vues classiques** sont des configurations nommées d'affichage d'un espace (type
grille, formulaire ou galerie). Actuellement le type `grid` est pleinement pris en charge.

### API GraphQL

```graphql
# Créer une vue grille
mutation {
  createView(
    spaceId: "...",
    input: { name: "Liste", viewType: grid }
  ) { id }
}

# Modifier
mutation {
  updateView(id: "...", input: { name: "Nouveau nom" }) { id name }
}

# Supprimer
mutation { deleteView(id: "...") }
```

---

## 6. Vues personnalisées (YAML)

Les **vues personnalisées** sont des tableaux de bord multi-espaces déclarés en YAML.

### Éditeur

Cliquer **« Éditer »** sur une vue ouvre un modal plein écran composé de :

- Un éditeur **CodeMirror** (YAML, thème monokai) pour saisir directement le YAML.
- Un **diagramme ERD interactif** à droite : cliquer sur un champ génère automatiquement
  le YAML correspondant dans l'éditeur (widget, colonnes, `depends_on` si FK détectée).

Chaque boîte ERD dispose d'un pseudo-champ **`*`** (première rangée) qui ajoute l'espace
sans restriction de colonnes (pas de clé `columns` dans le YAML).
Les champs sont classés **par ordre alphabétique**. Les auto-relations (ex. `parent_id → id`)
sont représentées par une boucle sur le côté droit de la boîte.

### Structure de base

```yaml
layout:
  direction: vertical    # ou horizontal
  children:
    - widget: ...        # widget feuille (grille de données)
    - layout: ...        # zone imbriquée (récursif)
```

### Widget

```yaml
widget:
  id: identifiant_unique   # requis, unique dans la vue
  title: "Titre affiché"   # optionnel
  space: nom_espace        # nom de l'espace Tarantool
  columns: [champ1, champ2]  # colonnes affichées (défaut : toutes)
  factor: 2                  # poids dans la zone parente (défaut : 1)
  depends_on:                # filtrage dépendant (optionnel)
    widget: id_widget_parent
    field: champ_jointure    # champ dans CET espace
    from_field: id           # champ dans le widget parent (défaut : id)
```

### Dépendances (filtrage inter-widgets)

Quand `depends_on` est défini, le widget n'affiche que les enregistrements dont le champ
`field` correspond à la valeur du champ `from_field` de la ligne sélectionnée dans le
widget parent.

### Facteurs de proportion

Le `factor` indique la place relative prise par un enfant dans sa zone. Exemple : si un
widget A a `factor: 2` et un widget B `factor: 1`, A occupe 2/3 de l'espace.

### Colonnes personnalisées

```yaml
columns: [prenom, nom, email]   # seuls ces champs, dans cet ordre
```

Si omis, tous les champs de l'espace sont affichés.

### Exemple complet

```yaml
layout:
  direction: vertical
  children:
    - widget:
        id: personnes
        title: Personnes
        space: personnes
        columns: [prenom, nom, email]
    - layout:
        direction: horizontal
        children:
          - widget:
              id: commandes
              title: Commandes
              space: commandes
              depends_on:
                widget: personnes
                field: client_id
                from_field: id
              factor: 2
          - widget:
              id: notes
              title: Notes
              space: notes
              depends_on:
                widget: personnes
                field: personne_id
              factor: 1
```

### Widget agrégat

Un widget de type `aggregate` affiche un tableau de synthèse en lecture seule, calculé
côté serveur par itération sur l'espace. Il est équivalent à un `GROUP BY` SQL.

```yaml
widget:
  type: aggregate
  title: "Par pupitre"      # optionnel
  space: chorale            # espace source
  groupBy: [pupitre]        # un ou plusieurs champs de groupement
  aggregate:
    - fn: count             # COUNT(*) — pas besoin de field
      as: nb
    - field: annee          # champ à agréger
      fn: avg               # sum | count | avg | min | max
      as: annee_moy         # alias colonne (défaut : fn_field)
```

L'alias `as` est optionnel : s'il est absent, le nom de colonne généré est `fn_field`
(ex. `avg_annee`) ou `count` pour `COUNT(*)`.

#### Colonnes calculées

Il est possible d'ajouter des colonnes calculées côté client via la clé `computed`.
Chaque entrée fournit un alias (`as`) et une expression JavaScript (`expr`) évaluée
sur chaque ligne agrégée. L'objet `row` contient tous les champs `groupBy` et les
alias `aggregate`.

```yaml
widget:
  type: aggregate
  space: chorale
  groupBy: [pupitre]
  aggregate:
    - fn: count
      as: nb
    - field: annee
      fn: avg
      as: annee_moy
  computed:
    - as: label
      expr: "row.pupitre + ' (' + row.nb + ')'"
    - as: statut
      expr: "row.nb > 1 ? 'Complet' : 'Insuffisant'"
```

> **Note :** les expressions `computed` sont du JavaScript pur (pas du MoonScript) ;
> elles s'exécutent dans le navigateur, après réception des données agrégées.

![Widget agrégat](img/aggregate-widget.png)

### API GraphQL

```graphql
# Lister
query { customViews { id name yaml } }

# Créer
mutation {
  createCustomView(input: {
    name: "Tableau de bord",
    yaml: "layout:\n  direction: vertical\n  children: []\n"
  }) { id }
}

# Modifier
mutation {
  updateCustomView(id: "...", input: { yaml: "..." }) { id yaml }
}

# Supprimer
mutation { deleteCustomView(id: "...") }

# Requête d'agrégation directe
query {
  aggregateSpace(
    spaceName: "chorale",
    groupBy: ["pupitre"],
    aggregate: [
      { fn: "count", as: "nb" },
      { field: "annee", fn: "avg", as: "annee_moy" }
    ]
  )
}
```

---

## 7. Authentification

tdb utilise des **tokens Bearer** (SHA-256 + sel, stockés en session Tarantool).
Le token est persisté dans `localStorage` et envoyé automatiquement par le client.

### Flux de connexion

```graphql
mutation {
  login(username: "alice", password: "secret") {
    token
    user { id username email groups { id name } }
  }
}
```

Le token est ensuite envoyé dans l'en-tête HTTP :

```
Authorization: Bearer <token>
```

### Déconnexion

```graphql
mutation { logout }
```

### Utilisateur courant

```graphql
query { me { id username email groups { id name } } }
```

### Changer son propre mot de passe

```graphql
mutation {
  changePassword(currentPassword: "ancien", newPassword: "nouveau")
}
```

---

## 8. Utilisateurs et groupes

Ces opérations nécessitent d'être **membre du groupe `admin`**.

### Utilisateurs

```graphql
# Lister
query { users { id username email groups { id name } } }

# Créer (admin uniquement)
mutation {
  createUser(input: {
    username: "bob",
    email: "bob@ex.com",
    password: "secret"
  }) { id }
}

# Forcer un changement de mot de passe (admin uniquement)
mutation {
  adminSetPassword(userId: "...", newPassword: "nouveau")
}
```

### Groupes

```graphql
# Lister (avec membres et permissions)
query {
  groups {
    id name description
    members { id username }
    permissions { id resourceType resourceId level }
  }
}

# Créer
mutation {
  createGroup(input: { name: "editeurs", description: "..." }) { id }
}

# Supprimer
mutation { deleteGroup(id: "...") }

# Ajouter un membre
mutation { addMember(userId: "...", groupId: "...") }

# Retirer un membre
mutation { removeMember(userId: "...", groupId: "...") }
```

---

## 9. Droits (permissions)

Les permissions s'accordent à un **groupe** sur une ressource.

| Niveau | Description |
|--------|-------------|
| `read` | Lecture seule |
| `write` | Lecture + écriture |
| `admin` | Contrôle total de la ressource |

```graphql
# Accorder un droit
mutation {
  grant(groupId: "...", input: {
    resourceType: "space",
    resourceId: "...",
    level: write
  }) { id }
}

# Révoquer
mutation { revoke(permissionId: "...") }
```

---

## 10. Export et import de snapshots

La section **Export / Import** du panneau Administration permet de sauvegarder l'intégralité
d'une application tdb (schéma, vues personnalisées, groupes, permissions, et optionnellement
les données) dans un fichier `.tdb.yaml`, puis de le restaurer sur une autre instance.

### Export

Deux modes d'export sont disponibles :

- **Structure seule** (`exportSnapshot(includeData: false)`) : exporte le schéma complet
  (espaces, champs, relations, vues personnalisées, groupes, permissions) sans les données.
  Utile pour partager un modèle d'application.
- **Structure + données** (`exportSnapshot(includeData: true)`) : exporte également toutes
  les lignes de chaque espace. Utile pour une sauvegarde complète ou une migration.

Le fichier produit est du YAML lisible :

```yaml
version: "1"
exported_at: "2026-03-08T12:00:00"
schema:
  spaces:
    - name: personnes
      fields:
        - name: nom
          fieldType: String
          notNull: false
        - name: nom_complet
          fieldType: String
          formula: "=> \"#{@prenom} #{@nom}\""
          language: moonscript
      views:
        - name: Grille
          viewType: Grid
  relations:
    - fromSpace: chorale
      fromField: choriste
      toSpace: personnes
      toField: id
  custom_views:
    - name: Chorale
      yaml: |
        layout: …
  groups:
    - name: admin
      members: [admin]
      permissions:
        - resourceType: space
          level: admin
data:                    # absent si export structure seulement
  personnes:
    - {nom: Dupont, prenom: Jean}
```

Les identifiants internes sont exclus ; la correspondance lors de l'import se fait par **nom**.

### Import

1. Cliquer sur **Choisir un fichier** et sélectionner un fichier `.tdb.yaml`.
2. tdb calcule automatiquement un **diff** entre le schéma du fichier et le schéma courant,
   et l'affiche avec un code couleur :
   - vert **Créer** : l'élément sera ajouté.
   - rouge **Supprimer** : l'élément sera retiré (mode Remplacement uniquement).
   - orange **Modifier** : le type d'un champ a changé.
3. Choisir le **mode** d'import et confirmer.

### Modes d'import

| Mode | Comportement |
|------|-------------|
| **Fusion** (`merge`) | Crée les espaces, champs, relations, vues et groupes manquants. Les éléments déjà présents (même nom) sont laissés intacts. |
| **Remplacement** (`replace`) | Supprime d'abord tous les espaces et groupes existants, puis recrée tout depuis le snapshot. Attention : toutes les données existantes sont perdues. |

Le résultat de l'opération indique le nombre d'éléments créés, ignorés et les erreurs
éventuelles.

### API GraphQL correspondante

```graphql
# Export
query {
  exportSnapshot(includeData: Boolean!): String!
}

# Prévisualisation du diff
query {
  diffSnapshot(yaml: String!): SnapshotDiff!
}

# Import
mutation {
  importSnapshot(yaml: String!, mode: merge|replace): ImportResult!
}
```

---

## 11. API GraphQL complète

### Queries

| Query | Description |
|-------|-------------|
| `spaces` | Liste tous les espaces |
| `space(id)` | Détail d'un espace |
| `views(spaceId)` | Vues classiques d'un espace |
| `view(id)` | Détail d'une vue classique |
| `customViews` | Toutes les vues personnalisées |
| `customView(id)` | Détail d'une vue personnalisée |
| `records(spaceId, filter, limit, offset)` | Enregistrements paginés et filtrés |
| `record(spaceId, id)` | Un enregistrement |
| `relations(spaceId)` | Relations d'un espace |
| `me` | Utilisateur connecté |
| `users` | Tous les utilisateurs (admin) |
| `user(id)` | Détail d'un utilisateur (admin) |
| `groups` | Tous les groupes (admin) |
| `group(id)` | Détail d'un groupe (admin) |
| `exportSnapshot(includeData)` | Export YAML de l'application (admin) |
| `diffSnapshot(yaml)` | Prévisualisation du diff avant import (admin) |
| `aggregateSpace(spaceName, groupBy, aggregate)` | Requête d'agrégation sur un espace |

### Mutations

| Mutation | Description |
|----------|-------------|
| `createSpace` / `updateSpace` / `deleteSpace` | CRUD espaces |
| `addField` / `updateField` / `removeField` / `reorderFields` | CRUD champs |
| `createView` / `updateView` / `deleteView` | CRUD vues classiques |
| `createRelation` / `deleteRelation` | CRUD relations |
| `createCustomView` / `updateCustomView` / `deleteCustomView` | CRUD vues YAML |
| `insertRecord` / `updateRecord` / `deleteRecord` | CRUD enregistrements |
| `login` / `logout` | Authentification |
| `createUser` | Créer un utilisateur (admin) |
| `changePassword` | Changer son propre mot de passe |
| `adminSetPassword` | Forcer le mot de passe d'un utilisateur (admin) |
| `createGroup` / `deleteGroup` | CRUD groupes (admin) |
| `addMember` / `removeMember` | Gestion des membres (admin) |
| `grant` / `revoke` | Gestion des permissions (admin) |
| `importSnapshot(yaml, mode)` | Import d'un snapshot YAML (admin) |

---

## Architecture technique

```
┌──────────────────────────────────────────────────────┐
│  Navigateur                                          │
│  CoffeeScript → JS  (app, auth, spaces, data_view,  │
│                       custom_view, graphql_client)   │
│  tui-grid (grille)  │  jsyaml (parsing YAML)         │
└─────────────────────┬────────────────────────────────┘
                      │ HTTP + GraphQL (JSON)
┌─────────────────────▼────────────────────────────────┐
│  Tarantool 3.x                                       │
│  MoonScript → Lua                                    │
│  ├── http_server (tarantool/http)                    │
│  ├── graphql engine (maison, pur Lua)                │
│  ├── resolvers/  (schema, data, auth, custom_view)   │
│  ├── core/       (auth, permissions, formula)        │
│  └── _tdb_*      (spaces internes Tarantool)         │
└──────────────────────────────────────────────────────┘
```

| Composant | Technologie |
|-----------|-------------|
| Backend | MoonScript compilé en Lua, exécuté par Tarantool |
| Frontend | CoffeeScript compilé en JS, servi statiquement |
| Base de données | Tarantool (espaces internes `_tdb_*`) |
| API | GraphQL maison (pas de dépendance npm/lua tierce) |
| Authentification | Bearer token, SHA-256 + sel, sessions en mémoire Tarantool |
| Tests | Runner CoffeeScript maison (pas de Jest/Mocha) |
