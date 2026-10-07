# Étapes 0 et 1 — AGENTS.md et sécurité — plan d'implémentation

> **Pour les exécutants :** une tâche à la fois, dans son propre worktree git. Commits
> intermédiaires obligatoires. Vérifier par exécution réelle (compilation + tests), pas
> par relecture.

**Objectif :** cadrer les agents (AGENTS.md) puis corriger les failles de sécurité
relevées à la revue : permissions non appliquées, sandbox des formules, fichiers
statiques, export.

**Architecture :** aucun changement d'architecture. Un helper `require_perm` dans
`backend/resolvers/utils.moon` appelle `core.permissions.can` ; le sandbox est durci
dans `backend/core/triggers.moon` ; `backend/http_server.moon` est corrigé.

**Stack :** MoonScript (compilé en Lua via `moonc`), tests maison `tests/runner.moon`,
Tarantool 3 en Docker. Jamais de `.lua` édité à la main ; commiter source + artefact.

**Spec :** `docs/superpowers/specs/2026-10-07-app-versioning-design.md` (§7, §9).

## Contraintes globales

- MoonScript : jamais `local`, `end`, `then` ; méthodes avec `\` ; arrays en `{}` ;
  4 niveaux d'indentation maximum (fonctions auxiliaires au-delà).
- Compiler avec `moonc <fichier.moon>` (dans `nix develop`) et commiter `.moon` + `.lua`.
- Tests : `make test` (instance dédiée). Ne jamais toucher à l'instance de production
  (port 8080). Vérifications navigateur sur le port 8081 uniquement.
- Messages de commit en anglais, préfixe `fix:`/`feat:`/`test:`/`docs:`.
- L'API GraphQL et les plugins YAML ne doivent pas être réduits.
- Aucune règle inventée : toute modification cite un fichier et des lignes.

## Review Focus

- Utilisateur sans groupe : refusé partout (`Forbidden`), y compris en lecture.
- Utilisateur avec `read` seul : lecture OK, toute mutation refusée.
- Wildcard `*` et wildcard par type de ressource respectés ; groupe `admin` total.
- Formule modifiant `string`/`table`/`math` : aucun effet sur les autres appels.
- Formule en boucle infinie ou `("x"):rep(1e9)` : erreur de formule, serveur vivant.
- `GET /../../etc/passwd` et variantes encodées : 404 ou 400, jamais le contenu.

## Task 0 : AGENTS.md (indépendante, démarrable immédiatement)

**Fichier :** `AGENTS.md` uniquement.

- [ ] Ajouter une section « Objectif du projet » : TGui vise à être une alternative à
  Grist fondée sur Tarantool/Lua/MoonScript (Grist = source d'inspiration et idéal visé).
- [ ] Ajouter une section « Règles de conception » : permissions réellement appliquées
  dans chaque résolveur ; validation des types et `not_null` à l'écriture ; l'API GraphQL
  et les plugins YAML sont des piliers à conserver intacts ; versionnage des apps prévu
  (spec ci-dessus).
- [ ] Ajouter une section « Délégation » : renvoyer au spec et aux plans de
  `docs/superpowers/` ; chaque tâche = un worktree, commits intermédiaires.
- [ ] Corriger la liste des tests du tableau (elle ne mentionne que 6 fichiers sur ~30) :
  remplacer par une phrase renvoyant à `tests/` et à `doc/*/dev/tests.md`.
- [ ] Vérifier : `make doc-check` ne casse pas. Commit `docs: update AGENTS.md`.

## Task 1 : permissions appliquées (le plus gros ; fichiers : resolvers uniquement)

**Fichiers :** `backend/resolvers/utils.moon` (+ `.lua`), tous les
`backend/resolvers/*_resolvers.moon`, `tests/test_permissions.moon`.

**Produit :** `require_perm ctx, resource_type, resource_id, level` → retourne `uid` ou
lève `Forbidden`. Admin (groupe `admin`) passe toujours. Utilise `perms_mod.can`
(`backend/core/permissions.moon:~105`).

- [ ] Écrire les tests d'abord dans `tests/test_permissions.moon` : utilisateur sans
  groupe, `read`, `write`, `admin`, wildcard `*`, wildcard par type ; pour chaque
  famille : schéma (`schema_resolvers`), données (`data_resolvers`), vues, data views,
  pages (`custom_view_resolvers`), plugins, agrégats. Voir qu'ils échouent.
- [ ] Implémenter `require_perm` dans `utils.moon`.
- [ ] Appliquer : requêtes de lecture → `read` sur le `space`/`view` ; mutations de
  données → `write` ; mutations de schéma (`createSpace`, `addField`, `deleteSpace`,
  relations…) → `admin` (global `*`) ; vues/pages/plugins : `write` sur leur ressource,
  `admin` pour suppression. Les listes (`spaces`, `views`) filtrent selon `read`.
- [ ] `make test` vert ; commit par famille de résolveurs (petits commits).
- [ ] Mettre à jour la phrase du README sur `core.permissions.can()` seulement si fausse.

## Task 2 : sandbox des formules (fichiers : triggers uniquement)

**Fichiers :** `backend/core/triggers.moon` (+ `.lua`), `tests/test_triggers.moon`.

- [ ] Tests d'abord : (a) formule `string.format = nil` puis une autre formule utilisant
  `string.format` fonctionne ; (b) `(function() while true do end end)()` retourne une
  erreur de formule en un temps borné ; (c) `("x"):rep(1e9)` retourne une erreur ;
  voir les échecs.
- [ ] `FORMULA_ENV` : construire des **copies** de `string`, `table`, `math`, `os`
  (copie superficielle suffit pour des tables de fonctions).
- [ ] Limite d'exécution : `debug.sethook` par comptage d'instructions autour de l'appel
  de la formule (dans `config.safe_formula_call`, `backend/core/config.moon`), avec
  restauration du hook dans tous les cas (pcall).
- [ ] Limite mémoire : copie de `string` avec `rep` enveloppé refusant un résultat
  supérieur à un seuil nommé (constante en tête de fichier).
- [ ] `make test` vert ; commit `fix: harden formula sandbox`.

## Task 3 : fichiers statiques et export (fichiers : http_server uniquement)

**Fichiers :** `backend/http_server.moon` (+ `.lua`), nouveau
`tests/test_http_static.moon`.

- [ ] Test d'abord : une fonction pure `safe_static_path url_path` refuse `..`, `//`,
  octet nul, `%2e%2e`, chemin absolu ; accepte `/src/app.js`.
- [ ] Extraire `safe_static_path` et l'utiliser dans `serve_static`.
- [ ] Réécrire `handle_export` : analyse de la requête propre (une petite fonction),
  suppression des logs/commentaires d'hésitation, `require_admin` à la place du test sur
  le nom `admin` (adapter pour `auth_mod` si `ctx` n'est pas disponible : réutiliser la
  logique de `resolvers.utils.require_admin` sans la dupliquer).
- [ ] `make test` vert ; commit.

## Ordre et parallélisme

Les tâches 0, 1, 2 et 3 touchent des fichiers disjoints : elles peuvent s'exécuter en
parallèle, chacune dans son worktree, au rythme des places données par
`can-launch.sh`. Fusion dans `wip` après relecture du diff par l'orchestrateur.
Tâche 1 en premier si une seule place est disponible (plus forte valeur).
