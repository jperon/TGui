# AGENTS.md — Guide pour agents IA

Ce fichier décrit les conventions, l'architecture et les procédures de ce projet
à l'intention des agents IA qui interviennent dessus.

## Vue d'ensemble

`tdb` est un GUI web pour Tarantool 3.
Le backend est en **MoonScript compilé en Lua** et tourne dans Tarantool.
Le frontend est en **CoffeeScript compilé en JS**, servi statiquement par Tarantool.
Le dialogue frontend/backend passe par un moteur **GraphQL maison** (pas de dépendance externe).

## Objectif du projet

`TGui` (paquet `tdb`) vise à être une **alternative à Grist**, fondée sur
Tarantool, Lua et MoonScript. Grist est la source d'inspiration et l'idéal visé.

## Règles de conception

Renvois au spec `docs/superpowers/specs/2026-10-07-app-versioning-design.md` (§7, §8).

- **Permissions réellement appliquées dans chaque résolveur** : `core.permissions.can`
  doit être appelé par les résolveurs (lecture → `read`, écriture de données → `write`,
  schéma → `admin`). Voir le spec §7.
- **Validation à l'écriture** : `insertRecord`/`updateRecord` contrôlent les champs
  inconnus, `not_null` et le type déclaré, avec un message d'erreur par champ.
  Voir le spec §8.
- **API GraphQL et plugins YAML = piliers à conserver intacts** : l'API GraphQL et
  les plugins YAML ne doivent pas être réduits.
- **Versionnage des apps prévu** : conçu dans le spec ci-dessus — s'y référer avant
  toute modification liée aux apps, exports ou imports.

## Délégation

- Se référer au spec et aux plans de `docs/superpowers/` : toute tâche y est cadrée
  (périmètre, fichiers, vérifications). Exemple :
  `docs/superpowers/plans/2026-10-07-etapes-0-1-agents-et-securite.md`.
- **Une tâche à la fois, dans son propre worktree git. Commits intermédiaires
  obligatoires.** Vérifier par exécution réelle (compilation + tests), pas par
  relecture.

## Règles absolues

- **Ne jamais éditer les fichiers `.lua` ou `.js` directement.** Les sources sont les
  fichiers `.moon` et `.coffee` ; les fichiers compilés sont des artefacts. Modifier
  la source, puis compiler.
- **Ne jamais écrire `local x = y` en MoonScript.** Dans ce langage, `x = y` produit
  `local x = y` si `x` n'est pas déjà déclaré. `local x = y` est une erreur de syntaxe.
- Les fichiers `.lua` et `.js` sont **commités** en même temps que leur source (le dépôt
  contient à la fois les sources et les artefacts).

## Environnement de développement (Nix)

Un `flake.nix` fournit tous les outils (`moonc` du sous-module MoonScript,
`coffee`, navigateurs Playwright, `shot-scraper`, client `docker`, `jq`). Les
entrées `nixpkgs` et `flake-utils` sont **épinglées à une révision exacte**
(elle-même figée dans `flake.lock`) : l'environnement est reproductible. Le
`shellHook` **efface `LD_LIBRARY_PATH`/`LD_PRELOAD`/`LD_AUDIT`** héritées de
l'hôte pour rester hermétique (sinon les navigateurs Playwright échouent sur
une version de glibc).

**direnv** : le fichier `.envrc` à la racine (`use flake`) charge ce shell
automatiquement. Une seule fois par clone : `direnv allow .` ; ensuite
l'environnement s'active en entrant dans le répertoire (et se recharge quand
`flake.nix` ou `flake.lock` change). Hors de ce shell, `make build`/`make up`
échouent : `scripts/moonc.sh` s'arrête alors avec un message explicite.

**MoonScript est un sous-module git** (`backend/vendor/moonscript`), épinglé sur
le tag **v0.8.0** : c'est la même version qui compile les sources et qui tourne
dans Tarantool (`moonscript.base.to_lua` pour les formules). Après un clone (ou
un changement de branche) :

```bash
git submodule update --init  # récupère backend/vendor/moonscript
direnv allow                 # une fois : charge le shell Nix à chaque entrée
# (sans direnv : nix develop, pour un shell ponctuel)
make doctor                  # vérifie outils, sous-module, hermétisme, navigateur
# puis : make build, make test, npx playwright test ...
```

Le compilateur du sous-module tourne sur le Lua 5.1 de Nix avec `lpeg`,
`argparse` et `luafilesystem` (voir `scripts/moonc.sh`) ; son analyseur natif
(`moonscript/parse/native.c`) est compilé dans `build/`, ignoré par git.

**Mise à jour de MoonScript** : changer le commit du sous-module (checkout du
nouveau tag, `git add backend/vendor/moonscript`), puis `make build` et
committer les sources et les `.lua` recompilés. Ne jamais éditer le sous-module.

Mise à jour volontaire des dépendances Nix : `nix flake update
--override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable`, puis ré-épingler
dans `flake.nix` la nouvelle `rev` lue dans `flake.lock` et committer les deux
fichiers ensemble. La version de `@playwright/test` dans `package.json` doit
rester égale à `pkgs.playwright-driver.version` (`make doctor` le contrôle).

Hooks git versionnés dans `.githooks/` (pre-commit = `make test`) :

```bash
make install-hooks          # git config core.hooksPath .githooks (une fois)
```

> **Réseau Docker sur cet hôte** : le bridge ne fait pas de masquerade. Les
> builds passent par `--network=host` (variable `DOCKER_BUILD_NET` du Makefile
> et `build.network: host` des compose). À retirer si le NAT du bridge est réparé.

## Compilation

Les `.lua` sont produits par le `moonc` du sous-module (`scripts/moonc.sh`,
MoonScript 0.8.0), jamais par celui de nixpkgs : une seule version, celle qui
tourne à l'exécution.

```bash
# Un fichier MoonScript (ou `make build` pour tout)
scripts/moonc.sh backend/core/spaces.moon   # produit backend/core/spaces.lua

# Un fichier CoffeeScript
coffee --no-header -c frontend/src/app.coffee   # produit frontend/src/app.js

# Tout recompiler (analyseur natif + tous les .moon/.coffee)
make build
```

Après toute modification de `.moon` ou `.coffee`, toujours compiler avant de tester
ou de committer. Le sous-module doit être initialisé (`git submodule update
--init`) ; `make build` échoue avec un message explicite sinon.

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

Fichiers de test : la liste complète est dans le répertoire `tests/` (une trentaine
de fichiers) et dans la documentation des tests, `doc/fr/dev/tests.md` et
`doc/en/dev/tests.md`.

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
│   ├── data_views_executor.moon # Moteur d'exécution des Data Views (aggregations, filters)
│   └── introspection.moon   # __schema / __type / __typename
├── core/
│   ├── spaces.moon          # Bootstrap des espaces système, CRUD espaces/champs
│   ├── data_views.moon      # CRUD pour les Data Views
│   ├── triggers.moon        # Trigger formulas (Lua et MoonScript)
│   ├── auth.moon            # Sessions, PBKDF2-HMAC-SHA256 (100k itérations), tokens
│   ├── permissions.moon     # Groupes & droits read/write/admin
│   └── views.moon           # Vues personnalisées YAML
└── resolvers/
    ├── init.moon            # Agrège resolvers, construit le schéma, gère reinit
    ├── schema_resolvers.moon
    ├── data_resolvers.moon
    ├── data_view_resolvers.moon # Résolveurs pour les Data Views
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
| `_tdb_data_views` | Vues de données (id, name, description, source_space, config, …) |
| `_tdb_sessions` | Tokens d'authentification |
| `_tdb_users` | Utilisateurs (PBKDF2-HMAC-SHA256, 100k itérations) |
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
        ├── data_views_view.coffee # Éditeur et liste des Data Views
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

### Références documentation & SDL

- Référence API FR: `doc/fr/api.md`
- Référence API EN: `doc/en/api.md`
- Référence dev compacte FR: `doc/fr/dev.md`
- Référence dev compacte EN: `doc/en/dev.md`
- Références dev détaillées: `doc/fr/dev/*.md` et `doc/en/dev/*.md`
- SDL statique (source de vérité): `schema/tdb.graphql`
- SDL généré (snapshot runtime): `schema/tdb.generated.graphql`
- Commandes associées: `make doc-gen`, `make doc-check`, `make sdl-gen`, `make sdl-check`

## Vérification dans le navigateur (shot-scraper)

Utiliser pour cela l’instance de tests, sur le port 8081. Ne jamais toucher à l’instance de production sur le port 8080. Après tout changement dans le backend, relancer l’instance de test avec `make test-down; make test-up`.

L’outil `shot-scraper` (utilisé via `uvx`) permet d’automatiser les captures et les interactions dans un navigateur sans quitter l’agent.

### Commandes fréquentes

```bash
# Prendre une capture d'écran (avec délai pour rendu)
uvx shot-scraper http://localhost:8081 -o debug.png --wait 2000

# Exécuter du JavaScript et récupérer un résultat JSON
uvx shot-scraper javascript http://localhost:8081 "
  (() => {
    return {
      title: document.title,
      isHidden: document.getElementById('login-overlay').classList.contains('hidden')
    };
  })()
"
```

Identifiants par défaut : `admin` / `adminadmin`.

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
docker exec -it tdb-tarantool-test tt connect localhost:3301

# Appeler du code Lua directement
echo "return require('core.spaces').list_spaces()" | \
  docker exec -i tdb-tarantool-test tt connect localhost:3301 -x lua -f -

# Tester l'API GraphQL
curl -s -X POST http://localhost:8081/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ spaces { id name } }"}'
```

## Conventions de commit

- Messages en anglais, préfixe conventionnel : `feat:`, `fix:`, `test:`, `refactor:`, `docs:`
- Toujours committer les sources **et** les artefacts compilés ensemble
- **Committer après chaque tâche ou groupe de tâches cohérent**, avant de passer
  à la suivante. Ne pas laisser des changements non commités s'accumuler entre
  les sessions
- Découper les tâches en petites étapes logiques, bien définies ; committer après chaque étape, en utilisant si besoin des commits de fixup.

## Points de vigilance

- **Rendu des custom views (pages)** : afficher une page passe par
  `AppViewHelpers.renderCustomViewPreview`, qui doit (1) appeler `cv.mount()`
  sur l'instance `CustomView` et (2) retirer la classe `hidden` de
  `#custom-view-container`. Oublier l'un des deux donne une page **vide sans
  erreur**. Couvert par `tests/js/test_view_helpers.coffee` et
  `tests/playwright/pages/page-rendering.spec.coffee`.
- **Data view `sourceSpace`** : le frontend stocke l'**id** de l'espace (UUID),
  pas son nom. `data_views_executor.execute_view` résout par id puis par nom.
- **Vendor frontend** : tout bundle utilisé doit être inclus dans `backend/index.moon`
  (ex. `sortablejs.bundle.js` pour `new Sortable`). Un bundle oublié casse la
  fonctionnalité silencieusement à l'exécution.
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
- **Syntaxe MoonScript** : erreurs fréquentes à éviter :
  - Arrays : utiliser `{}` pour les arrays/tableaux, `[]` uniquement pour les array comprehensions
  - Indentation : ne jamais dépasser 4 niveaux d'indentation, créer des fonctions auxiliaires
  - Structure HTML : avec la lib `html.lua`, chaque `H.div{}` doit contenir ses enfants et se terminer par `}` (valable pour tout élément conteneur)

## Considérations spécifiques pour éviter les erreurs courantes

### 🏗️ Structure du code et indentation

- **Maximum 4 niveaux d'indentation** : Si l'on dépasse 4 niveaux, créer une fonction auxiliaire.
  - **Raison** : Maintient la lisibilité et évite les erreurs de structure MoonScript
  - **Application** : Particulièrement important avec `backend/html.lua` où les structures HTML peuvent devenir profondes
  - **Exemple** :
    ```moonscript
    -- ✅ Correct : fonction auxiliaire
    _widgetConfigRow = (labelText, inputElement) ->
      H.div {class: 'config-row',
        H.label {labelText}
        inputElement
      }

    -- ❌ Éviter : trop de niveaux d'indentation
    H.div {class: 'widget-section',
      H.div {class: 'data-source-config',
        H.div {class: 'config-row',
          H.div {class: 'nested-too-deep',  -- 4+ niveaux = risque de problèmes de maintenance
            ...
    ```

### 📚 Arrays et tableaux MoonScript

- **Arrays/Tableaux** : Utiliser `{}` pour définir les arrays/tableaux
  - ✅ `myArray = {1, 2, 3}` ou `myArray = {item1, item2}`
  - ✅ `options = {'String', 'Int', 'Float'}`
- **Array comprehensions** : Utiliser `[]` uniquement pour les compréhensions
  - ✅ `[item * 2 for item in *myArray]`
  - ✅ `[H.li{class: 'section-item', item} for item in *items]`
- **Erreur fréquente** : Confondre syntaxe JavaScript `[]` avec MoonScript `{}`
  - ❌ `items = [item1, item2]`  # Syntaxe JavaScript
  - ✅ `items = {item1, item2}`  # Syntaxe MoonScript

### 🌐 Structure HTML avec backend/html.lua

- **Parenthésage correct** : Chaque `H.div{}` doit contenir ses enfants et se terminer par `}`
  - ✅ `H.div {class: 'container', contenu...}`
  - ❌ `H.div {class: 'container'}, contenu...`
- **Imbrication** : Les éléments enfants sont indentés sous le parent
  - ✅ Structure hiérarchique claire avec indentation
  - ❌ Éléments frères au même niveau que leur parent

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

## Checklist MoonScript - Points critiques à vérifier

### 🔍 Syntaxe Arrays vs Comprehensions
- [ ] Les arrays/tableaux utilisent `{}` : `items = {item1, item2}`
- [ ] Les array comprehensions utilisent `[]` : `[item * 2 for item in *array]`
- [ ] Pas de confusion syntaxe JavaScript `[]` avec MoonScript `{}`

### 📐 Indentation et structure
- [ ] Maximum 4 niveaux d'indentation respecté
- [ ] Fonctions auxiliaires créées si dépassement de 4 niveaux
- [ ] Structure HTML claire avec `backend/html.lua`

### 🌐 Structure HTML (backend/html.lua)
- [ ] Chaque `H.div{}` se termine par `}` (pas par `,`)
- [ ] Éléments enfants correctement indentés sous le parent
- [ ] Pas d'éléments frères au mauvais niveau d'indentation

### ⚠️ Pièges courants
- [ ] Pas de `local x = y` (utiliser `x = y`)
- [ ] Pas de `obj:methode()` (utiliser `obj\methode()`)
- [ ] Pas de `if condition then` (utiliser `if condition`)
- [ ] Pas de `function...end` (utiliser `->` ou `=>`)

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
