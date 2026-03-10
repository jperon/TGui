# TGui — GUI pour Tarantool

GUI web pour [Tarantool 3](https://hub.docker.com/r/tarantool/tarantool/) :
création et modification d'espaces (tables), vues multiples sur les données (grille/formulaire/galerie),
relations inter-espaces via clés étrangères, champs calculés par formule Lua,
et gestion des permissions par groupes (style Unix).

## Fonctionnalités

- **Espaces** : création/suppression de tables, ajout/suppression/réordonnancement de champs
- **Types de champs** : `String`, `Int`, `Float`, `Boolean`, `ID`, `UUID`, `Sequence` (auto-incrément), `Any` / `Map` / `Array` (JSON quelconque, objet, tableau)
- **Champs calculés** : formules Lua avec accès à `self` (enregistrement courant), navigation FK lazy (`self.choriste.nom`), et helper `space(name)` pour requêter d'autres espaces
- **API GraphQL** : moteur maison (SDL + parser + executor + introspection), compatible Altair
- **Requêtes typées** : chaque espace expose une requête GraphQL dédiée avec navigation FK et rétro-références
- **Filtres** : `field/op/value` + combinateurs `and`/`or` récursifs arbitraires
- **Relations** : clés étrangères entre espaces, navigation bidirectionnelle via l'API typée
- **Vues personnalisées** : mises en page YAML stockées côté serveur
- **Auth** : sessions token, utilisateurs, groupes, permissions `read`/`write`/`admin` par ressource

## Stack technique

| Couche | Technologie |
|---|---|
| Conteneur | `tarantool/tarantool:3` (Docker) |
| Backend | MoonScript → Lua (`moonc`), HTTP via lib Tarantool 3 |
| API | GraphQL maison (SDL + parser + executor, écrit en MoonScript) |
| Frontend | CoffeeScript compilé avec `coffee -c` (pas de bundler) |
| UI | Toast UI Grid + paquets locaux (pré-empaquetés) |

## Prérequis

- Docker & Docker Compose
- `moonc` (`luarocks install moonscript`)
- `coffee` (`npm install -g coffeescript`)
- `node` + `npm` (pour la génération du vendor Univer, une seule fois)

## Démarrage rapide

```bash
# 1. Compiler les sources MoonScript et CoffeeScript
make build

# 2. Générer le bundle vendor Univer (une seule fois)
make vendor

# 3. Lancer le conteneur Tarantool
make up

# 4. Ouvrir dans le navigateur
open http://localhost:8080
```

## Commandes Makefile

| Commande | Description |
|---|---|
| `make build` | Compile `.moon` → `.lua` et `.coffee` → `.js` |
| `make vendor` | Génère `frontend/vendor/univer.bundle.js` |
| `make up` | Build + lance le conteneur Docker |
| `make down` | Arrête le conteneur |
| `make logs` | Suit les logs Tarantool |
| `make clean` | Supprime les fichiers compilés |

## Structure du projet

```
tgui/
├── Dockerfile                  # Image Tarantool 3 + rock http
├── docker-compose.yml
├── Makefile
├── schema/
│   └── tdb.graphql             # SDL GraphQL (source de vérité)
├── backend/
│   ├── init.lua                # Point d'entrée Tarantool
│   ├── http_server.moon        # Serveur HTTP + routing
│   ├── graphql/                # Moteur GraphQL from scratch
│   │   ├── lexer.moon          # Tokenizer
│   │   ├── parser.moon         # Parser AST
│   │   ├── schema.moon         # Type system
│   │   ├── executor.moon       # Résolution queries/mutations
│   │   ├── dynamic.moon        # SDL + resolvers générés dynamiquement par espace
│   │   └── introspection.moon  # __schema/__type
│   ├── core/
│   │   ├── spaces.moon         # Bootstrap espaces système + CRUD espaces/champs
│   │   ├── views.moon          # Gestion des vues
│   │   ├── auth.moon           # Authentification, sessions
│   │   └── permissions.moon    # Groupes & droits Unix-style
│   └── resolvers/
│       ├── init.moon           # Agrège les resolvers, initialise le schema
│       ├── schema_resolvers.moon
│       ├── data_resolvers.moon
│       └── auth_resolvers.moon
└── frontend/
    ├── index.html
    ├── css/app.css
    ├── vendor/                 # Toast UI Grid + dépendances (généré par `make vendor`)
    └── src/
        ├── graphql_client.coffee
        ├── app.coffee
        ├── auth.coffee
        ├── spaces.coffee
        └── views/
            ├── data_view.coffee    # Vue tableau principale (Toast UI Grid)
            └── custom_view.coffee  # Vues personnalisées YAML
```

## Architecture GraphQL

Le moteur GraphQL est intégralement écrit en MoonScript et compilé en Lua.
Il ne dépend d'aucune bibliothèque externe.

| Composant | Rôle |
|---|---|
| `lexer` | Tokenise les documents SDL et les queries |
| `parser` | Produit un AST complet (queries, mutations, fragments, variables) |
| `schema` | Construit le type system à partir du SDL |
| `executor` | Résout l'AST contre les resolvers avec gestion des erreurs |
| `dynamic` | Génère dynamiquement SDL + resolvers pour chaque espace utilisateur (y compris champs calculés) |
| `introspection` | Implémente `__schema`, `__type`, `__typename` (compatible Altair) |

## Permissions

Les permissions sont **génériques** : l'administrateur crée les groupes qu'il souhaite
(aucun rôle prédéfini), puis assigne des droits `read`/`write`/`admin` par ressource
(espace, vue, ou globalement via wildcard `*`).

Un utilisateur peut appartenir à plusieurs groupes (style Unix).
La vérification s'effectue dans chaque resolver via `core.permissions.can()`.
test final
