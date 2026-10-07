# Audit complet — TGui

> Date : juillet 2025 / Mises à jour : mars 2026, juin 2026, octobre 2026
>
> Périmètre : backend (MoonScript), frontend (CoffeeScript), tests, documentation, schéma GraphQL.

---

## Mise à jour d'octobre 2026

Revue générale du 2026-10-07 (voir `docs/superpowers/specs/2026-10-07-app-versioning-design.md`
§7 et §8). Chaque affirmation ci-dessous a été revérifiée dans le code à cette date.

### Corrigé depuis

| Constat de l'audit d'origine | Preuve |
|---|---|
| 1.1 Hachage SHA-256 | `backend/core/auth.moon:10-22` : PBKDF2-HMAC-SHA256, 100 000 itérations |
| 1.3 Aucune longueur minimale de mot de passe | `backend/core/auth.moon:34` : `check_password_length` (8 caractères) |
| 1.6 Sandbox des formules | `backend/core/formula_sandbox.moon` (environnement par formule, `string.rep` borné) et `backend/core/config.moon:62` (`safe_formula_call`) |
| 2.1 Double création dans `renderSpaceList` | `frontend/src/app_data_helpers.coffee:36-46` : un seul `addEventListener` par élément |
| 2.2 Tests dupliqués dans `test_data_filters` | `tests/test_data_filters.moon` |
| 2.3 Rendu d'erreur de formule copié-collé | `frontend/src/views/data_view.coffee:852` : `_formatFormulaError` factorisée |
| 2.4 `LIST_WIDGET_PLUGINS` dupliqué | défini une seule fois, `frontend/src/widget_plugins.coffee:4` |
| 3.2 Cinq fichiers de test relation orphelins | `test_relation_display_backend`, `test_relation_display_regression`, `test_relation_field`, `test_relation_integration`, `test_relation_repr` : absents du dépôt |
| 3.3 Serveur HTTP non testé | `tests/test_http_static.moon`, `tests/test_index_html.moon` |
| 3.3 Sécurité du sandbox non testée | `tests/test_triggers.moon` (sections « sandbox »), `tests/test_formula_guard.moon` |
| 5.1 `AGENTS.md` mentionnait « bcrypt » | `AGENTS.md:135` : « PBKDF2-HMAC-SHA256 (100k itérations) » |
| 5.5 `doc/fr/dev.md` annonçait `init.moon` | `backend/init.moon` existe, la mention est correcte |

### Corrections de la revue d'octobre 2026

- **Permissions jamais appliquées** : `core.permissions.can` n'était appelée par aucun
  résolveur ; contrôles factorisés dans `require_perm` (`backend/resolvers/utils.moon:50`),
  utilisés par tous les résolveurs. Tests : `tests/test_permissions.moon`,
  `tests/test_typed_query_permissions.moon`, `tests/test_formula_read_perms.moon`.
- **Requêtes typées lisibles sans authentification** : `backend/graphql/dynamic.moon:151`
  appelle `require_perm ctx, 'space', sp_cap.id, 'read'` ; test
  `tests/test_typed_query_permissions.moon`.
- **Sandbox des formules** : copies d'environnement par formule
  (`backend/core/formula_sandbox.moon:55`), garde d'instructions de 20 millions
  (`backend/core/config.moon:41`), `string.rep` borné à 10 Mio
  (`backend/core/formula_sandbox.moon:13-29`). Tests : `tests/test_triggers.moon`
  (isolation des bibliothèques, limite d'instructions, `string.rep`),
  `tests/test_formula_guard.moon`.
- **Traversal de chemin sur les fichiers statiques** : `safe_static_path`
  (`backend/http_server.moon:52`) refuse `..`, `//`, octet nul, encodages `%2e%2e`
  et chemins absolus ; test `tests/test_http_static.moon`.
- **Export de snapshot** : `handle_export` (`backend/http_server.moon:138`) lit les données
  via `build_snapshot`, encode en YAML et contrôle l'appartenance au groupe admin ; test de
  round-trip `tests/test_snapshot.moon` (`export → import (includeData)`), et
  `tests/test_http_static.moon` pour l'authentification.
- **Mutations `mergeZones`/`splitZone` jamais enregistrées** : enregistrées dans
  `backend/resolvers/custom_view_resolvers.moon:103-109`, implémentées dans
  `backend/resolvers/custom_view_zones.moon` ; test `tests/test_zone_merge_split.moon`.
- **Bugs de `backend/core/views.moon`** : validation de la config à la création et écriture
  de `config_str` à la mise à jour ; test `tests/test_views_core.moon`.
- **Heuristique `is_multiple_relation` remplacée par une cardinalité déclarée** : plus aucune
  occurrence dans `backend/` ; la cardinalité est stockée et validée (`createRelation`,
  `schema/tdb.graphql`), valeur par défaut `one` pour les relations existantes. Tests :
  `tests/test_relation_cardinality.moon`, `tests/test_multiple_relations.moon`.
- **Validation des types et `not_null` à l'écriture** : `backend/core/validation.moon`,
  appelée par `insertRecord`/`updateRecord` (`backend/resolvers/data_resolvers.moon:106,122`) ;
  tests `tests/test_validation.moon`.
- **Filtres numériques** : `numeric_compare` (`backend/resolvers/data_resolvers.moon:31`)
  exclut un enregistrement dont la valeur n'est pas numérique au lieu de planter ; test
  `tests/test_data_filters.moon` (LT/GT/LTE/GTE sur données vides, textuelles ou absentes).
- **Exemption de test `is_perm_subject` remplacée par `trusted_ctx`** : plus aucune occurrence
  dans `backend/` ; `trusted_ctx` (`backend/resolvers/utils.moon:33`) ne peut pas être forgé
  par un client (le contexte HTTP est construit de zéro et ne recopie pas `trusted`) ; tests
  `tests/test_permissions.moon` (« trusted cannot be forged by a request »).

### Points encore ouverts

- **Limitation de débit du login uniquement en mémoire** : `backend/core/auth.moon:97-135`
  (`_login_attempts`), perdue au redémarrage du serveur.
- **Changement du mot de passe admin par défaut non forcé côté serveur** :
  `backend/core/spaces.moon:293` (`adminadmin`) ; seul un bandeau frontend s'appuie sur un
  drapeau `localStorage` (`frontend/src/app.coffee:305`).
- **Jeton stocké dans `localStorage`** : `frontend/src/graphql_client.coffee:3,12`, risque
  XSS connu.
- **`innerHTML` à auditer** : les trois fichiers cités par l'audit d'origine ont été revus —
  `frontend/src/app_sidebar_helpers.coffee` et `frontend/src/app_fields_helpers.coffee`
  utilisent désormais `textContent` ; `frontend/src/app_snapshot_helpers.coffee:135-139`
  conserve `innerHTML` mais avec des valeurs échappées par `esc`.
- **Budget d'instructions de 20 millions appliqué aussi aux lectures faites dans une
  formule** : `FORMULA_INSTRUCTION_LIMIT` (`backend/core/config.moon:41`) borne toute lecture
  déclenchée par une formule (`space(...)`, navigation FK) ; couvert par
  `tests/test_formula_read_perms.moon`.
- **`restoreRecords` non validé** : `backend/resolvers/data_resolvers.moon:197-209` insère les
  enregistrements sans passer par `validation_mod.validate_record`, contrairement à
  `insertRecord`/`updateRecord`.
- **`CONTAINS` / `STARTS_WITH` avec une valeur de filtre `nil`** : `v\find(flt.value, …)` et
  `v\sub(1, #flt.value)` (`backend/resolvers/data_resolvers.moon:58-59`, également
  `backend/graphql/dynamic.moon:48-49`) lèvent une erreur si `flt.value` est `nil`.
- **Formules citant un ancien nom en clair non réécrites au renommage d'app** :
  `_rename_field` (`backend/core/app_apply.moon:785`) renomme le champ mais ne réécrit ni
  `formula` ni `reprFormula`.
- **Code frontend mort** : `frontend/src/graphql_builder.coffee` n'est référencé nulle part ;
  ses trois tests `tests/test_graphql_builder_basic.coffee`, `_minimal.coffee` et
  `_simple.coffee` ne sont découverts ni par `tests/run.moon` (motif `test_*.moon`) ni par
  `tests/js/run.coffee`.
- **Références obsolètes au module supprimé `core/fk_proxy.moon`** : `doc/en/dev/runtime.md:18`
  et `doc/fr/dev/runtime.md:15` le listent alors que `backend/core/fk_proxy.moon` n'existe
  pas dans le dépôt.

## Mise à jour juin 2026 — bugs trouvés par tests d'usage réel

Session centrée sur le fonctionnement réel (Docker + parcours navigateur Playwright).

### Bugs applicatifs corrigés

1. **🔴 Pages custom totalement cassées (rendu vide)** — `renderCustomViewPreview`
   n'appelait jamais `CustomView.mount()` et ne dé-masquait pas
   `#custom-view-container`. Toute page s'ouvrait vide, sans erreur.
2. **🔴 Data views inexécutables** — le frontend stocke `sourceSpace` = id de
   l'espace (UUID) mais `execute_view` cherchait par nom → « Source space not
   found » à chaque ouverture. Résolu par id avec repli sur le nom.
3. **🟠 Drag & drop des widgets cassé** — `sortablejs.bundle.js` jamais inclus
   dans `index.moon` alors que `new Sortable` est utilisé.
4. **🟡 Logs de debug** verbeux laissés dans `data_views.moon`.

### Infrastructure / tests

- **`flake.nix`** ajouté (dev shell reproductible : moonc, coffee, navigateurs
  Playwright, shot-scraper, docker, jq).
- **Docker injouable sur l'hôte** : bridge sans masquerade NAT → build via
  `--network=host` (workaround ; vrai correctif = config firewall hôte).
- **Hook pre-commit non portable** (`#!/bin/bash`, `make` hors PATH) → versionné
  dans `.githooks/`, shebang `env bash`, repli `nix develop`.
- **Suite de tests JS était rouge** (stub DOM incomplet : `getAttribute`,
  `window.addEventListener` manquants) → réparée.
- **Aucune CI** : `.github/workflows/` est vide alors que `make ci` existe — d'où
  les régressions passées inaperçues. **Recommandation : ajouter un workflow CI**
  (sur runner standard le réseau Docker fonctionne).
- **7 specs Playwright en échec** étaient tous des bugs de **test** (pas de reload
  après création via API, sélecteurs `.page-item` inexistants, dialogue de confirm
  mal ciblé, `toHaveCount(1)` supposant une base vierge) → corrigés. Ajout de
  régressions ciblées (`test_view_helpers.coffee`, `page-rendering.spec.coffee`,
  régression backend id/nom dans `test_data_views.moon`).

### Fait dans cette session (suite)

- **CI** : workflow `.github/workflows/ci.yml` (job `ci` = `make sdl-check test
  test-js` ; job `e2e` = instance de test + Playwright/chromium).
- **Isolation Playwright** : `globalSetup` (qui n'était même pas branché dans la
  config) ramène la base à une baseline démo avant chaque run.

### Réparé (suite, juin 2026)

- **`make build` n'est plus un no-op** : vraie recette compilant les sources
  (hors `backend/moonscript/` vendu). Ça a immédiatement révélé un bug latent —
  `http_server.moon` appelait `index.render!` alors que `index` retourne la
  fonction de rendu (servir `/` aurait planté) ; le `.lua` périmé le masquait.
  Corrigé. Un job CI `artifacts` (devShell Nix `.#build`) échoue désormais sur
  tout artefact désynchronisé.
- **`make doc-check` repasse au vert** : domaines de doc ajoutés pour les
  opérations Data Views / Widget Plugins / Layouts & Zones, docs régénérées
  (`doc/en`, `doc/fr`, `po/tdb-docs.pot`), Summary ajouté à `data_views.moon`.
  `doc-check` est réintégré à `make ci`.
- **Duplication factorisée** : `domain_for_operation` (dupliqué à l'identique
  dans `generate_docs.moon` et `doc_check.moon`) est désormais dans un module
  partagé `scripts/doc_domains.moon`.

### Reste à faire (recommandations)

- Réparer le NAT du bridge Docker côté hôte (NixOS) puis retirer les `--network=host`.

---

## 1. Sécurité

### 1.1 Hachage des mots de passe — ✅ CORRIGÉ

**Fichier** : `backend/core/auth.moon` (lignes 16-17)

Le hachage utilise désormais **PBKDF2-HMAC-SHA256** avec 100 000 itérations (ligne 13). Une longueur minimale de 8 caractères est imposée (ligne 15). Le système supporte la migration depuis l'ancien SHA-256 via `hash_password_legacy`.

> Cette correction a été appliquée après l'audit initial.

### 1.2 Aucune limitation de débit sur le login — 🟡 MOYEN

`login()` dans `auth.moon` ne comporte aucun rate-limiting ni mécanisme de verrouillage après N tentatives échouées. Un attaquant peut tenter un nombre illimité de combinaisons.

**Recommandation** : ajouter un compteur d'échecs par IP ou par username avec un délai exponentiel ou un verrouillage temporaire.

### 1.3 Aucune exigence de complexité de mot de passe — ✅ CORRIGÉ

Le backend impose maintenant une longueur minimale de 8 caractères via `check_password_length` dans `auth.moon` (ligne 35).

### 1.4 Identifiants par défaut admin/admin — 🟡 MOYEN

Un bandeau d'avertissement existe côté frontend (`defaultPasswordWarning`), mais le changement n'est pas forcé. Le flag `localStorage.tdb_password_changed` est purement client-side et peut être contourné.

**Recommandation** : vérifier côté serveur si le mot de passe admin est toujours le défaut, et forcer le changement lors de la première connexion.

### 1.5 Token stocké dans localStorage — 🟡 MOYEN

`graphql_client.coffee` persiste le token dans `localStorage`, ce qui est vulnérable aux attaques XSS (tout script injecté peut lire le token).

**Recommandation** : acceptable pour une application interne/auto-hébergée, mais à documenter comme risque connu. Pour un déploiement sensible, utiliser des cookies `HttpOnly` + `SameSite`.

### 1.6 Sandbox des formules — ✅ CORRIGÉ

`triggers.moon` (lignes 20-43) définit un `FORMULA_ENV` bien contrôlé :
- ✅ Exclut explicitement `io`, `debug`, `box`, `load`, `require`, `loadfile`, `dofile`
- ✅ Limite `os` à `time`, `clock`, `date`
- ✅ `setfenv` appliqué pour isoler le chunk
- ✅ **CORRIGÉ** : si `setfenv` échoue, la formule est **refusée** (lignes 83-85), pas exécutée sans sandbox

> Cette correction a été appliquée après l'audit initial.

### 1.7 `new Function()` dans les vues agrégées — 🟡 MOYEN

`custom_view.coffee` (ligne 179) utilise `new Function('row', expr)` pour les colonnes calculées dans les widgets d'agrégation. L'expression provient du YAML de la vue, qui est éditable par tout utilisateur authentifié.

**Recommandation** : ce code s'exécute côté client donc le risque est limité à du self-XSS. Documenter que les expressions calculées s'exécutent dans le contexte du navigateur de l'utilisateur.

### 1.8 Plugin iframes et postMessage — 🟢 FAIBLE

Les widgets plugins sont isolés dans des iframes `sandbox='allow-scripts'` (bon). `postMessage` utilise `'*'` comme target origin, ce qui est acceptable car l'iframe est `srcdoc` (même origine nulle).

### 1.9 innerHTML et XSS potentiel — 🟡 MOYEN

Plusieurs endroits du frontend utilisent `.innerHTML` avec des données potentiellement contrôlées par l'utilisateur :

- `app_sidebar_helpers.coffee:124` — noms d'utilisateurs et groupes dans le panneau admin
- `app_snapshot_helpers.coffee:100` — noms d'espaces/champs dans le diff de snapshot
- `app_fields_helpers.coffee:263-264` — noms de cibles de relations

**Recommandation** : utiliser `textContent` ou échapper systématiquement avant injection dans `.innerHTML`. Les noms d'espaces et de champs proviennent de la base et sont partiellement validés, mais un utilisateur admin malveillant pourrait injecter du HTML.

### 1.10 Pas de protection CSRF — 🟢 FAIBLE

L'API utilise des Bearer tokens dans le header `Authorization`, ce qui protège naturellement contre le CSRF classique (les formulaires HTML ne peuvent pas ajouter ce header). Acceptable.

---

## 2. Qualité du code (DRY, KISS, clarté, cohérence)

### 2.1 BUG — Double création d'éléments dans renderSpaceList — ✅ CORRIGÉ

**Fichier** : `frontend/src/app_data_helpers.coffee` (lignes 37-49)

Le code a été nettoyé. La boucle `for` crée chaque élément une seule fois avec un seul `addEventListener`.

> Ce bug a été corrigé après l'audit initial.

### 2.2 Tests dupliqués dans test_data_filters — ✅ CORRIGÉ

**Fichier** : `tests/test_data_filters.moon`

Les tests dupliqués ont été supprimés. Le fichier contient maintenant une seule série de tests sans duplication.

> Ce problème a été corrigé après l'audit initial.

### 2.3 Répétition du pattern de rendu d'erreur de formule — 🟡 MOYEN

**Fichier** : `frontend/src/views/data_view.coffee`

Le pattern de détection et rendu des erreurs de formule `[ERROR|...|...]` est copié-collé 3 fois :
- Formatter FK (lignes 339-347)
- Formatter Boolean (lignes 367-373)
- Formatter Text (lignes 387-395)

**Recommandation** : extraire une méthode `_formatCellError(displayVal)` qui retourne soit le HTML d'erreur, soit `null` si pas d'erreur.

### 2.4 Requêtes GraphQL dupliquées entre fichiers — 🟢 FAIBLE

`LIST_WIDGET_PLUGINS` est défini dans `app.coffee` (lignes 33-46) ET dans `widget_plugins.coffee` (lignes 4-17). Les deux sont identiques.

**Recommandation** : centraliser les requêtes dans un seul endroit ou utiliser celles exposées par les modules existants.

### 2.5 Mapping tuple-vers-objet répété — 🟢 FAIBLE

Chaque resolver backend (custom_view_resolvers, widget_plugin_resolvers, views, etc.) définit sa propre logique de conversion tuple → table Lua. C'est acceptable car chaque espace a un schéma différent, mais un helper générique `tuple_to_map(tuple, field_names)` pourrait réduire le boilerplate.

### 2.6 Points positifs

- **Architecture claire** : séparation nette backend/frontend, resolvers bien découpés par domaine
- **Extraction des helpers frontend** : `AppDataHelpers`, `AppFieldsHelpers`, `AppSidebarHelpers`, `AppViewHelpers`, `AppSnapshotHelpers`, `AppUndoHelpers` — bonne factorisation
- **Conventions de nommage cohérentes** : snake_case en MoonScript, camelCase en CoffeeScript
- **GraphQL schema bien organisé** avec sections clairement délimitées
- **Undo/redo** : implémentation sophistiquée avec vérification optimiste des conflits (bien pensé)
- **FkSearchEditor** : recherche fuzzy bien implémentée, bon UX
- **Validation d'entrée** dans widget_plugin_resolvers (longueurs max, patterns de noms, langages autorisés)

---

## 3. Couverture de tests

### 3.1 Tests exécutés (15 suites dans `run.moon`)

| Suite | Domaine | Couverture |
|---|---|---|
| `test_lexer` | Tokenizer GraphQL | ✅ Bonne |
| `test_parser` | Parser AST | ✅ Bonne |
| `test_schema` | Système de types | ✅ Bonne |
| `test_executor` | Exécution GraphQL | ✅ Bonne |
| `test_spaces` | CRUD espaces/champs | ✅ Bonne |
| `test_batch_ops` | Opérations en lot | ✅ Bonne |
| `test_triggers` | Formules et triggers | ✅ Bonne |
| `test_custom_views` | Vues YAML | ✅ Bonne |
| `test_widget_plugins` | Plugins widget | ✅ Bonne |
| `test_relations` | Relations FK | ✅ Bonne |
| `test_relation_type_regression` | Régression types relation | ✅ Bonne |
| `test_snapshot` | Export/import/diff | ✅ Bonne |
| `test_permissions` | Auth, admin, sessions | ✅ Bonne |
| `test_data_filters` | Filtres, FK proxy | ✅ Très bonne |
| `test_nesting` | Requêtes imbriquées | ✅ Bonne |

### 3.2 Tests existants mais NON exécutés — 🔴 IMPORTANT

**5 fichiers de test** existent dans `tests/` mais ne sont **pas référencés** dans `tests/run.moon` :

| Fichier | Probablement teste |
|---|---|
| `test_relation_display_backend.moon` | Affichage des relations côté backend |
| `test_relation_display_regression.moon` | Régression affichage relations |
| `test_relation_field.moon` | Champs relation |
| `test_relation_integration.moon` | Intégration relations |
| `test_relation_repr.moon` | Formules de représentation relations |

Ces fichiers sont **incompatibles** avec le runner actuel : ils importent `execute_mutation`
et `execute_query` depuis `tests.runner` (qui ne les exporte pas), et utilisent `describe`/`it`/
`before_each`/`assert` en globales (au lieu de `R.describe`/`R.it`/`R.ok`). Les ajouter
à `run.moon` en l'état **ferait crasher la suite de tests**.

**Recommandation** : supprimer ces fichiers (code mort) ou les réécrire en utilisant le
micro-framework `R.*` actuel. Les scénarios qu'ils couvrent (relations, reprFormula)
sont déjà largement testés par `test_relations.moon`, `test_nesting.moon` et
`test_relation_type_regression.moon`.

### 3.3 Domaines NON couverts par les tests

| Domaine | Risque | Recommandation |
|---|---|---|
| **HTTP server** (`http_server.moon`) | 🟡 | Test d'intégration HTTP (token extraction, routing, content-type) |
| **Introspection** (`introspection.moon`) | 🟡 | Tester `__schema`, `__type` queries |
| **Hachage de mots de passe** | 🟡 | Tester `hash_password` / `verify_password` round-trip |
| **`safe_call` / `validate_input`** (`config.moon`) | 🟢 | Tests unitaires des utilitaires |
| **`core/views.moon`** CRUD | 🟢 | Couvert indirectement via resolvers |
| **Aggregate resolvers** edge cases | 🟢 | Fonctions inconnues, espaces vides |
| **Frontend JS** | 🟡 | Les tests `tests/js/` existent, évaluer leur couverture |
| **Sandbox formulas** sécurité | 🔴 | Tester qu'une formule ne peut pas accéder à `box`, `io`, `require` |

### 3.4 Points positifs

- **Micro-framework de test** maison (`runner.moon`) simple et efficace avec `describe`, `it`, `before_all`, `after_all`, assertions variées (`eq`, `ne`, `ok`, `nok`, `is_nil`, `matches`, `raises`)
- **Isolation des tests** via suffixes aléatoires et nettoyage systématique
- **CI complète** : `make ci` enchaîne SDL check, tests backend, tests JS, doc check
- **Restauration du schéma** après les tests (`reinit!` en fin de `run.moon`)
- **Bonne couverture des filtres** : tous les opérateurs, AND/OR, formules, FK proxy, chaînes imbriquées

---

## 4. Commentaires du code

### 4.1 Backend

- ✅ **En-têtes de fichiers** systématiques et descriptifs
- ✅ **Séparateurs visuels** (`-- ────`) pour structurer les sections
- ✅ **Code auto-documenté** : les noms de fonctions et variables sont clairs
- ✅ **Commentaire de sécurité** dans `triggers.moon` expliquant ce que le sandbox exclut
- 🟢 Quelques fonctions complexes (comme `make_self_proxy`, `build_fk_def_map`) pourraient bénéficier d'un commentaire décrivant l'algorithme

### 4.2 Frontend

- ✅ En-têtes clairs sur chaque fichier `.coffee`
- ✅ Les requêtes GraphQL sont nommées par des constantes explicites
- ✅ Sections de `app.coffee` bien délimitées par des commentaires
- 🟢 `FkSearchEditor` (data_view.coffee) et `AppUndoHelpers` (app_undo_helpers.coffee) mériteraient quelques commentaires supplémentaires sur la logique de vérification des conflits

### 4.3 Tests

- ✅ Chaque fichier de test commence par un commentaire décrivant ce qu'il teste
- ✅ Les `describe`/`it` sont descriptifs
- ✅ Runner bien documenté avec un exemple d'usage

### Verdict : les commentaires sont **adéquats**. Le code est généralement auto-documenté. Pas de sur-commentaire inutile.

---

## 5. Documentation (clarté et actualité)

### 5.1 AGENTS.md — ✅ CORRIGÉ

Le fichier `AGENTS.md` est un guide développeur **exemplaire** : architecture, conventions, commandes, points de vigilance, tout est là.

**CORRIGÉ** : la description de `core/auth.moon` mentionne maintenant correctement « PBKDF2-HMAC-SHA256 (100k itérations) » au lieu de « bcrypt ».

> Cette correction a été appliquée après l'audit initial.

### 5.2 Documentation API (`doc/fr/api.md`, `doc/en/api.md`) — ✅ Bonne

- Auto-générée depuis le schéma GraphQL
- Couvre toutes les queries et mutations
- Exemples d'utilisation inclus
- Pipeline CI de vérification (`make doc-check`)

**Manque** : les descriptions par opération sont génériques (« Read operation on space/field metadata. »). Des descriptions plus spécifiques amélioreraient la compréhension.

### 5.3 Documentation développeur (`doc/*/dev.md`, `doc/*/dev/*.md`) — ✅ Bonne

- Architecture globale documentée
- Références vers les fichiers sources
- Auto-générée et maintenue par CI

### 5.4 Points manquants dans la documentation

| Sujet | État | Recommandation |
|---|---|---|
| **Langage de formules** | Peu documenté | Documenter les fonctions disponibles dans le sandbox, la syntaxe `@champ`, les FK |
| **Widget plugins API** | Minimal | Documenter l'API `gql()`, `emitSelection()`, `onInputSelection()`, `render()`, `params` |
| **YAML des vues custom** | `doc/views-yaml.md` existe | Vérifier qu'il couvre `depends_on`, `filter`, `computed`, plugins |
| **Sécurité** | Non documenté | Ajouter une section sécurité (modèle d'authentification, permissions, sandbox) |
| **Déploiement** | Basique (Docker) | Documenter les variables d'environnement, configuration réseau, TLS |

### 5.5 `doc/fr/dev.md` — erreur mineure

Ligne 11 : « Runtime entrypoint: `backend/init.moon` ». Le fichier est `backend/init.lua` (Lua pur, non compilé depuis MoonScript). C'est cohérent avec `AGENTS.md` mais le `.md` auto-généré devrait refléter `.lua`.

---

## 6. Synthèse et recommandations

###Corrections appliquées

5 problèmes sur 18 ont été corrigés depuis l'audit initial :
- ✅ Hachage PBKDF2-HMAC-SHA256 (au lieu de SHA-256)
- ✅ Bug double addEventListener corrigé
- ✅ Tests dupliqués supprimés
- ✅ Sandbox formule refuse l'exécution si setfenv échoue
- ✅ AGENTS.md mentionne PBKDF2 au lieu de bcrypt

### Actions restantes

#### Priorité 🟡

1. Ajouter un rate-limiting sur le login
2. Remplacer les `innerHTML` par `textContent`
3. Ajouter un test de sécurité du sandbox
4. Gérer les 5 fichiers de test orphelins
5. Extraire le rendu d'erreur de formule

### Actions recommandées (🟡)

6. Ajouter un rate-limiting sur le login
7. Remplacer les `innerHTML` par `textContent` ou échappement dans le panneau admin/snapshot
8. Ajouter un test de sécurité du sandbox vérifiant que `box`, `io`, `require` sont inaccessibles
9. Gérer les 5 fichiers de test orphelins
10. Extraire le rendu d'erreur de formule dans une méthode partagée (`data_view.coffee`)

### Améliorations souhaitables (🟢)

11. Documenter le langage de formules (sandbox, syntaxe @, FK)
12. Documenter l'API des widget plugins
13. Ajouter des descriptions spécifiques dans la documentation API auto-générée
14. Centraliser les requêtes GraphQL dupliquées côté frontend
15. Ajouter un test d'intégration HTTP de base
16. Ajouter un test pour l'introspection GraphQL

### Bilan global

| Axe | Note | Commentaire |
|---|---|---|
| **Sécurité** | ✅ 8/10 | PBKDF2-HMAC-SHA256 corrigé, sandbox renforcé. Restent : rate-limiting login, XSS innerHTML |
| **Qualité code** | ✅ 9/10 | Bug de duplication corrigé. Architecture claire, bonne factorisation |
| **Tests** | ✅ 8/10 | Bonne couverture, framework maison efficace, CI complète. Quelques trous (HTTP, introspection, sandbox sécurité) et tests orphelins. |
| **Commentaires** | ✅ 8/10 | Adéquats, ni trop ni trop peu. Code auto-documenté. |
| **Documentation** | ✅ 8/10 | AGENTS.md corrigé. Très bonne base (API auto-générée, CI) |
