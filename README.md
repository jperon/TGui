# TGui

TGui est une application web de gestion de bases de données relationnelles,
construite sur **Tarantool 3**, **Lua** et **MoonScript**. Elle permet de créer
des espaces (tables), de typer leurs champs, de les relier par des relations
et des formules, de les consulter à travers une API GraphQL et de les
présenter dans des vues et des pages.

## Fonctionnalités

- **Espaces et champs** : création/suppression de tables, ajout, suppression et
  réordonnancement de champs. Types disponibles : `String`, `Int`, `Float`,
  `Boolean`, `ID`, `UUID`, `Sequence` (auto-incrément), `Any`, `Map`, `Array`,
  `Datetime`, `Relation`.
- **Champs calculés** : formules Lua ou MoonScript évaluées à la lecture, avec
  accès à `self` (l'enregistrement courant) et navigation dans les relations.
- **Formules trigger** : code Lua ou MoonScript exécuté à l'écriture
  (insertion/mise à jour) par un trigger Tarantool, sur les champs déclencheurs
  désignés.
- **Relations** : clés étrangères entre espaces, avec une cardinalité déclarée
  `one` (défaut) ou `many` et une formule de représentation.
- **API GraphQL** : moteur écrit en MoonScript (lexer, parser, executor,
  introspection). Chaque espace expose une requête typée, avec filtres
  (`field`/`op`/`value` et combinateurs `and`/`or`) et introspection. L'API sert
  de base à des usages backend.
- **Data Views** : vues de données configurées (agrégations, filtres) au-dessus
  d'un espace source.
- **Pages et plugins de widgets** : pages personnalisées décrites en YAML,
  composées de widgets et de plugins (script + template) définis par
  l'utilisateur.
- **Permissions** : groupes et droits `read`/`write`/`admin` par ressource,
  appliqués dans chaque résolveur (`backend/resolvers/utils.moon`).
- **Export/import de snapshots** : export du schéma et des données vers un
  document YAML, diff avant import.
- **Versionnage des applications** : publication d'un paquet `.tdbapp.yaml`,
  installation et mise à jour qui préservent les données et les
  personnalisations locales. Conflits résolus par décision explicite, éléments
  absents marqués obsolètes (jamais supprimés automatiquement), purge des
  éléments obsolètes après confirmation.

## Stack technique

| Couche | Technologie |
|---|---|
| Conteneur | `tarantool/tarantool:3` (Docker) |
| Backend | MoonScript compilé en Lua (`moonc`), HTTP via la bibliothèque Tarantool 3 |
| API | GraphQL maison, sans dépendance externe |
| Frontend | CoffeeScript compilé en JS (`coffee -c`), sans bundler |
| UI | Toast UI Grid, CodeMirror, js-yaml (paquets locaux dans `frontend/vendor/`) |

## Prérequis

- **Docker** et **Docker Compose**.
- **Nix** (recommandé) : `nix develop` fournit le compilateur MoonScript du
  sous-module (Lua 5.1 + lpeg, même version qu'à l'exécution), `coffee`,
  `node`, les navigateurs Playwright, `shot-scraper` et le client Docker
  (voir `flake.nix`).
- **direnv** (facultatif, avec Nix) : le `.envrc` du dépôt charge ce shell
  automatiquement. Lancer `direnv allow` une fois à la racine ; ensuite
  l'environnement s'active en entrant dans le répertoire. Sans direnv,
  `nix develop` reste nécessaire pour `make build`, `make up` et `make test`.

Le compilateur MoonScript est le sous-module git `backend/vendor/moonscript`
(épinglé sur le tag v0.8.0) : après un clone, lancer
`git submodule update --init`. Sans Nix, Lua 5.1 avec `lpeg`, `argparse` et
`luafilesystem` est nécessaire (ou utiliser Docker pour les tests).

## Démarrage rapide

```bash
# 1. Entrer dans l'environnement de développement (recommandé)
#    Avec direnv : `direnv allow` une fois, puis l'environnement se charge
#    automatiquement en entrant dans le répertoire. Sinon : `nix develop`.
nix develop

# 2. Compiler les sources MoonScript et CoffeeScript
make build

# 3. Générer les paquets vendor du frontend
make vendor

# 4. Lancer le conteneur Tarantool
make up

# 5. Ouvrir la SPA
# http://localhost:8080
```

Identifiants par défaut : **`admin`** / **`adminadmin`**. Ils sont définis par
les variables d'environnement `TDB_ADMIN_USER` et `TDB_ADMIN_PASSWORD`
(`backend/core/spaces.moon`) ; **changez le mot de passe** avant tout usage
réel.

## Commandes Makefile

| Commande | Description |
|---|---|
| `make build` | Compile `.moon` → `.lua` (moonc du sous-module), `.coffee` → `.js` et l'analyseur natif MoonScript |
| `make test` | Construit l'image de test et lance la suite Tarantool |
| `make test-js` | Lance les tests JavaScript (`tests/js/run.coffee`) |
| `make test-up` | Démarre l'environnement de test (port 8081) |
| `make test-down` | Arrête l'environnement de test |
| `make doc-gen` | Génère `doc/en/` depuis les sources |
| `make doc-check` | Vérifie la documentation (en-têtes `Summary`, etc.) |
| `make sdl-gen` | Régénère `schema/tdb.generated.graphql` |
| `make sdl-check` | Vérifie l'absence de dérive du SDL généré |
| `make vendor` | (Re)construit les paquets du navigateur dans `frontend/vendor/` |
| `make ci` | `sdl-check`, `test`, `test-js` puis `doc-check` |

Autres cibles utiles : `make up`, `make down`, `make logs`, `make clean`,
`make install-hooks` (hooks git versionnés dans `.githooks/`).

## Structure du projet

```
tgui/
├── Dockerfile
├── docker-compose.yml          # Instance de production (port 8080)
├── docker-compose.test.yml     # Instance de test (port 8081)
├── flake.nix                   # Environnement de développement Nix
├── Makefile
├── schema/
│   └── tdb.graphql             # SDL GraphQL (source de vérité)
├── backend/
│   ├── init.moon               # Point d'entrée Tarantool
│   ├── http_server.moon        # Serveur HTTP + routing
│   ├── index.moon              # Génération de la SPA
│   ├── html.lua                # Librairie de construction HTML
│   ├── graphql/                # Moteur GraphQL maison
│   ├── core/                   # Espaces, vues, permissions, relations, auth,
│   │                           #   formules, triggers, versionnage des apps
│   ├── resolvers/              # Résolveurs par domaine
│   └── test_runner.moon
├── frontend/
│   ├── css/app.css
│   ├── vendor/                 # Paquets navigateur (générés par `make vendor`)
│   └── src/                    # CoffeeScript (SPA, grilles, pages, plugins)
│       └── views/
├── tests/                      # Suite MoonScript, tests JS et Playwright
├── doc/                        # Documentation FR/EN (voir ci-dessous)
└── scripts/                    # Outillage (build vendor, génération documentaire)
```

Les fichiers compilés `.lua` et `.js` sont **commités en même temps que leurs
sources** ; ce sont des artefacts, jamais édités directement.

## Documentation

- `doc/fr/` et `doc/en/` : `README`, `get-started`, `api` et `dev`, plus la
  documentation développeur détaillée dans `doc/<lang>/dev/`.
- `doc/graphql-guide.md` : guide de l'API GraphQL (requêtes, mutations, formules).
- `doc/views-yaml.md` : format YAML des vues personnalisées (pages et widgets).
- `doc/audit.md` : audit historique, corrections appliquées et points ouverts.
- `AGENTS.md` : conventions, architecture et procédures pour les
  contributeurs (et les agents IA).

## Licence

MIT — voir le fichier [`LICENSE`](LICENSE).
