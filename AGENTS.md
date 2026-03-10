# AGENTS.md — Guide pour agents IA

Ce fichier décrit les conventions, l'architecture et les procédures de ce projet
à l'intention des agents IA qui interviennent dessus.

## Vue d'ensemble

`tdb` est un GUI web pour Tarantool 3.
Le backend est en **MoonScript compilé en Lua** et tourne dans Tarantool.
Le frontend est en **CoffeeScript compilé en JS**, servi statiquement par Tarantool.
Le dialogue frontend/backend passe par un moteur **GraphQL maison** (pas de dépendance externe).

## Règles absolues

- **Ne jamais éditer les fichiers `.lua` ou `.js` directement.** Les sources sont les
  fichiers `.moon` et `.coffee` ; les fichiers compilés sont des artefacts. Modifier
  la source, puis compiler.
- **Ne jamais écrire `local x = y` en MoonScript.** Dans ce langage, `x = y` produit
  `local x = y` si `x` n'est pas déjà déclaré. `local x = y` est une erreur de syntaxe.
- Les fichiers `.lua` et `.js` sont **commités** en même temps que leur source (le dépôt
  contient à la fois les sources et les artefacts).

## Compilation

```bash
# Un fichier MoonScript
moonc backend/core/spaces.moon          # produit backend/core/spaces.lua

# Un fichier CoffeeScript
coffee --no-header -c frontend/src/app.coffee   # produit frontend/src/app.js

# Tout recompiler
make build
```

Après toute modification de `.moon` ou `.coffee`, toujours compiler avant de tester
ou de committer.

## Tests

```bash
# Lancer l'environnement de test (fortement recommandé pour éviter de supprimer les données de production)
make test-up

# Lancer les tests
make test
```

Les tests tournent dans l'instance Tarantool dédiée `tgui-tarantool-test`.
L'instance de production (`tgui-tarantool-1`) ne doit être utilisée que pour une visualisation manuelle et ne doit pas subir de tests invasifs.
Ils sont écrits en MoonScript dans `tests/` avec un micro-framework maison (`tests/runner.moon`).
**Aucune dépendance externe** de test.

Fichiers de test :

| Fichier | Ce qu'il teste |
|---|---|
| `test_lexer.moon` | Tokenizer GraphQL |
| `test_parser.moon` | Parser GraphQL (AST) |
| `test_schema.moon` | Système de types GraphQL |
| `test_executor.moon` | Executor GraphQL (schéma minimal mocké, sans Tarantool) |
| `test_spaces.moon` | CRUD espaces et champs (`core/spaces`) |
| `test_triggers.moon` | Triggers et formules Lua/MoonScript (`core/triggers`) |

`test_executor.moon` remplace temporairement le schéma de production par un schéma
de test. `tests/run.moon` restaure le schéma de production à la fin via
`require('resolvers.init').reinit!`.

Les tests créent des espaces Tarantool avec un suffixe aléatoire (`test_space_XXXXXX`,
`test_triggers_XXXXXX`, `trig_moon_XXXXXX`) et les suppriment à la fin via
`spaces.delete_user_space`.

## Architecture backend

```
backend/
├── init.lua                 # Point d'entrée Tarantool (non compilé — Lua pur)
├── http_server.moon         # Serveur HTTP + routing (GET / → index, POST /graphql)
├── index.moon               # Génération HTML de la SPA (page unique)
├── html.lua                 # Lib de construction HTML (Lua pur)
├── graphql/
│   ├── lexer.moon           # Tokenizer SDL/query
│   ├── parser.moon          # Parser → AST
│   ├── schema.moon          # Système de types (build_schema)
│   ├── executor.moon        # Résolution queries/mutations/subscriptions
│   ├── dynamic.moon         # SDL + resolvers générés par espace (champs calculés)
│   └── introspection.moon   # __schema / __type / __typename
├── core/
│   ├── spaces.moon          # Bootstrap des espaces système, CRUD espaces/champs
│   ├── triggers.moon        # Trigger formulas (Lua et MoonScript)
│   ├── auth.moon            # Sessions, bcrypt, tokens
│   ├── permissions.moon     # Groupes & droits read/write/admin
│   └── views.moon           # Vues personnalisées YAML
└── resolvers/
    ├── init.moon            # Agrège resolvers, construit le schéma, gère reinit
    ├── schema_resolvers.moon
    ├── data_resolvers.moon
    ├── auth_resolvers.moon
    └── custom_view_resolvers.moon
```

### Reinitialisation du schéma

Chaque fois que la structure change (ajout/suppression de champ, etc.),
`executor.reinit_schema!` est appelé. Cela exécute `resolvers.init.reinit()`
qui reconstruit le SDL et les resolvers depuis les métadonnées.

**Ne jamais appeler `executor.init(schema)` dans du code qui tourne en production**
sans appeler `reinit!` ensuite — cela remplacerait le schéma de production.

### Stockage des métadonnées

Tarantool stocke les métadonnées dans des espaces système préfixés `_tdb_` :

| Espace | Contenu |
|---|---|
| `_tdb_spaces` | Espaces utilisateur (id, name, description, …) |
| `_tdb_fields` | Champs (id, space_id, name, type, not_null, pos, desc, formula?, trigger_json?, language?) |
| `_tdb_sessions` | Tokens d'authentification |
| `_tdb_users` | Utilisateurs (bcrypt) |
| `_tdb_groups` | Groupes |
| `_tdb_permissions` | Droits par groupe/ressource |
| `_tdb_relations` | Clés étrangères entre espaces |
| `_tdb_views` | Vues personnalisées YAML |

Les données utilisateur sont dans des espaces `data_<nom_espace>`.

### Champs calculés et triggers

- **Formula column** : évaluée à la lecture, via le resolver de type dynamique.
  La fonction reçoit `self` = enregistrement courant.
- **Trigger formula** : évaluée à l'écriture (insert/update) via un trigger Tarantool.
  Le champ `trigger_fields` liste les champs déclencheurs.
- **Langages** : `lua` (défaut) ou `moonscript`. Pour MoonScript, le code est transpilé
  via `moonscript.base.to_lua` au moment de la compilation de la formule.

## Architecture frontend

```
frontend/
├── css/app.css
├── vendor/
│   ├── tui-grid.bundle.js    # Toast UI Grid (commité)
│   └── jsyaml.bundle.js      # js-yaml (commité)
└── src/
    ├── graphql_client.coffee  # fetch + gestion des erreurs GraphQL
    ├── app.coffee             # Shell SPA (navigation, login, panel Champs)
    ├── auth.coffee            # Login/logout
    ├── spaces.coffee          # Requêtes GraphQL espaces/champs
    └── views/
        ├── data_view.coffee   # Grille de données (Toast UI Grid)
        └── custom_view.coffee # Vues YAML personnalisées
```

Le frontend est une **SPA sans bundler** : chaque `.coffee` est compilé en `.js`
et chargé directement via `<script>`. Pas de module system (les variables globales
sont partagées entre scripts).

## Schéma GraphQL

Le fichier source de vérité est `schema/tdb.graphql` (SDL statique).
Les types dynamiques (un par espace utilisateur) sont générés par `graphql/dynamic.moon`.

Pour ajouter un champ au schéma :
1. Modifier `schema/tdb.graphql`
2. Mettre à jour les resolvers correspondants dans `backend/resolvers/`
3. Mettre à jour les requêtes frontend dans `frontend/src/spaces.coffee` si besoin

## Vérification dans le navigateur

L'outil `chrome-devtools` permet d'inspecter l'application dans Chrome sans quitter
l'agent. Utiliser systématiquement pour valider les changements frontend :

```
# Prendre un snapshot de la page courante (arbre d'accessibilité)
→ chrome-devtools-take_snapshot

# Naviguer vers l'application
→ chrome-devtools-navigate_page  url: "http://localhost:8080"

# Vérifier les erreurs console après un changement
→ chrome-devtools-list_console_messages  types: ["error", "warn"]

# Inspecter les requêtes réseau (GraphQL)
→ chrome-devtools-list_network_requests  resourceTypes: ["fetch", "xhr"]
```

L'application tourne sur **http://localhost:8080**.
Identifiants par défaut : `admin` / `admin`.

## Commandes utiles

```bash
make build          # Compile tout
make test           # Lance les tests (container doit tourner)
make up             # Build + lance le container Docker
make down           # Arrête le container
make logs           # Suit les logs Tarantool (production)
make test-up        # Build + lance le container de test
make test-down      # Arrête le container de test
make vendor         # Régénère le bundle Univer (rare)

# Inspecter la base en live
docker exec -it tdb-tarantool-1 tt connect localhost:3301

# Appeler du code Lua directement
echo "return require('core.spaces').list_spaces()" | \
  docker exec -i tdb-tarantool-1 tt connect localhost:3301 -x lua -f -

# Tester l'API GraphQL
curl -s -X POST http://localhost:8080/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ spaces { id name } }"}'
```

## Conventions de commit

- Messages en anglais, préfixe conventionnel : `feat:`, `fix:`, `test:`, `refactor:`, `docs:`
- Toujours committer les sources **et** les artefacts compilés ensemble
- **Committer après chaque tâche ou groupe de tâches cohérent**, avant de passer
  à la suivante. Ne pas laisser des changements non commités s'accumuler entre
  les sessions.

## Points de vigilance

- **Cache de modules Lua** : Tarantool met les modules en cache dans `package.loaded`.
  Une modification de `.lua` n'est prise en compte qu'après redémarrage du container
  (`make down && make up`), sauf si le module est rechargé explicitement.
- **Schéma GraphQL** : après chaque `reinit_schema!`, le schéma est reconstruit depuis
  la base. En cas d'erreur dans un resolver dynamique (ex. formule invalide),
  `reinit` est wrappé dans un `pcall` et logue l'erreur sans crasher.
- **Séquences** : les champs de type `Sequence` ont une séquence Tarantool associée
  (`_tdb_seq_<field_id>`). `delete_user_space` et `remove_field` les suppriment.
- **MoonScript dans `tt connect`** : le REPL de `tt connect` exécute du Lua, pas du
  MoonScript. Compiler les sources avant de les déployer.

Tu es un expert MoonScript. MoonScript n'est PAS du Lua.
Tu ne dois JAMAIS écrire de syntaxe Lua quand l'utilisateur demande du MoonScript.

## Règles CRITIQUES du MoonScript — les violations sont interdites :

### Variables
- N'utilise JAMAIS `local`. Les variables sont implicitement locales par défaut.
  ✗ local x = 5
  ✓ x = 5
- Utilise `export` uniquement pour rendre quelque chose explicitement global.

### Appels de méthodes
- N'utilise JAMAIS `:` pour appeler des méthodes. Utilise `\` à la place.
  ✗ obj:methode(arg)
  ✓ obj\methode(arg)
- `:` est UNIQUEMENT utilisé dans les littéraux de table pour les paires clé-valeur.

### Blocs et indentation
- N'utilise JAMAIS `end` pour fermer un bloc. MoonScript est basé sur l'indentation.
  ✗ if x > 0 then\n  foo()\nend
  ✓ if x > 0\n  foo()
- N'ajoute JAMAIS `then` après une condition `if` ou `elseif`.
  ✗ if x > 0 then
  ✓ if x > 0

### Fonctions
- Utilise `->` pour les fonctions normales, `=>` pour les méthodes (lie `self`).
  ✓ add = (a, b) -> a + b
  ✓ greet = => "Bonjour, #{@name}"
- N'utilise JAMAIS `function...end`.

### Classes
- Utilise le mot-clé `class` avec un corps indenté.
  ✓ class Animal
      new: (name) =>
        @name = name
      speak: => print @name
- N'utilise JAMAIS les métatables ou `__index` manuellement sauf demande explicite.

### Interpolation de chaînes
- Utilise `"#{expression}"` pour l'interpolation dans les chaînes entre guillemets doubles.

### Tables
- Les constructeurs de tables utilisent l'indentation ou `{}` (facultatif quand il n’y a pas ambiguïté :
  ✓ t = {cle: valeur}
  ✓ t = cle: valeur
  ✓ t =\n  cle: valeur

### Self / instance
- Utilise `@` comme raccourci pour `self.` et `@@` pour la classe. Mais dans ce projet, n’utilise pas de classes, utilise les métatables standards de Lua.
  ✓ @nom  →  self.nom
  ✓ @@instances  →  self.__class.instances

## Avant de produire du code, vérifie mentalement :
1. Aucun mot-clé `local` nulle part
2. Aucun mot-clé `end` nulle part
3. Aucun mot-clé `then` nulle part
4. Tous les appels de méthodes utilisent `\`, jamais `:`
5. Les fonctions utilisent `->` ou `=>`, jamais `function`
6. Les tables clé / valeur utilisent la syntaxe `cle: valeur`, jamais `cle = valeur`
7. Les arrays sont la même chose que les tables en Lua comme en MoonScript : `[]` est utilisé seulement pour les compréhensions, un array se définit avec `{}`.

Si tu n'es pas sûr d'une fonctionnalité MoonScript, dis-le explicitement

## Principes directeurs du projet

### 🌙 MoonScript-first
- **Privilégier** : Solutions MoonScript natives vs dépendances externes
- **Éviter** : Libs Lua externes quand MoonScript suffit
- **Maintenir** : Compatibilité avec MoonScript existant

### 📦 Faible dépendances
- **Refuser** : Nouvelles dépendances sauf nécessité absolue
- **Préférer** : Solutions built-in Tarantool/Lua
- **Auditer** : Uniquement dépendances existantes critiques

### 🎯 KISS (Keep It Simple, Stupid)
- **Simplifier** : Avant de complexifier
- **Factoriser** : Uniquement si bénéfice évident
- **Maintenir** : Lisibilité du code MoonScript
plutôt que de revenir à la syntaxe Lua.
