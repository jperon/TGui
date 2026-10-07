# Étapes 3, 4, 5 (et restes de 2) — plan d'implémentation

> Même cadre que les plans précédents : TDD (phase rouge **locale**, test et correctif
> commités ensemble, suite verte, jamais `--no-verify`), un worktree par tâche,
> commits intermédiaires verts, vérification par exécution réelle, aucun fichier hors
> périmètre. Compléments : `2026-10-07-etape-2-integrite-donnees.md` (T6, T7, T8).

**Spec :** `docs/superpowers/specs/2026-10-07-app-versioning-design.md`.

## Contraintes globales (rappel)

MoonScript : jamais `local`/`end`/`then`, méthodes `\`, arrays `{}`, 4 niveaux
d'indentation max. Compiler avec `moonc`/`coffee` dans `nix develop`, commiter source +
artefact. Instance de production (8080) interdite. API GraphQL et plugins YAML à
conserver intacts (ajouts compatibles autorisés pour le versionnage).

## Restes des étapes 1 et 2

| Id | Tâche | Fichiers |
|---|---|---|
| T9 | garde d'instructions sur tous les sites de formules, limite à 20 M | `graphql/dynamic.moon`, `core/spaces.moon`, `core/config.moon` (en cours) |
| T7 | filtres robustes + formules de `data_resolvers.moon:251,262` via `safe_formula_call` | `resolvers/data_resolvers.moon`, `tests/test_data_filters.moon` (après T6) |
| T8 | cardinalité `one`/`many` déclarée, suppression de `is_multiple_relation`, contrôle de droit `read` dans le proxy FK des formules | `core/triggers.moon`, `core/fk_proxy.moon`, `core/spaces.moon`, `schema/tdb.graphql`, résolveurs de relations |
| T10 | remplacer l'exemption `is_perm_subject` (contextes de test sans token) par un drapeau explicite posé par les tests | `resolvers/utils.moon`, fixtures/tests concernés |

## Étape 3 : tests et maintenabilité (sans changement fonctionnel)

La suite de tests existante doit rester verte à chaque commit.

| Id | Tâche | Fichiers |
|---|---|---|
| T11 | découper `frontend/src/app_view_helpers.coffee` (1 875 lignes) par domaine (pages, éditeur YAML, plugins de widgets, modale d'ajout de widget, zones), supprimer les clés définies deux fois (`_getWidgetConfig`, `_closeWidgetModal`, `_renderCustomViewPreview`, `_bindAddWidgetModal`) en gardant la version effectivement active, retirer le `module.exports` du fichier navigateur ; mettre à jour les balises `<script>` de `backend/index.moon` | `frontend/src/app_view_helpers*.coffee` (+ .js), `backend/index.moon` (balises seulement) |
| T12 | découper `backend/resolvers/custom_view_resolvers.moon` (921 lignes) | `backend/resolvers/custom_view_resolvers*.moon` |
| T13 | dédupliquer le frontend : formatters d'erreur de formule (`views/data_view.coffee`), `LIST_WIDGET_PLUGINS` (`app.coffee` / `widget_plugins.coffee`) ; découper `views/custom_view.coffee` si lisible | `frontend/src/views/*.coffee`, `app.coffee`, `widget_plugins.coffee` |
| T14 | découper `core/triggers.moon` (sandbox → `core/formula_sandbox.moon`, relations, enregistrement des triggers) | `core/triggers*.moon` (après T8) |
| T15 | découper `backend/index.moon` (757 lignes) en fonctions de rendu par section | `backend/index*.moon` (après T11) |
| T16 | nettoyage des tests : fusionner `test_multiple_relations*`, `test_graphql_builder_*`, déplacer/supprimer les `.coffee` isolés de `tests/`, supprimer `test_error_format.lua`, remplacer la découverte `io.popen 'ls …'` de `tests/run.moon` par `fio.glob`, vérifier que le schéma de production est restauré en fin de run | `tests/**` (après T8) |

## Étape 4 : versionnage des apps

**Identité des éléments.** Clés stables, fondées sur les noms (le snapshot actuel
procède déjà ainsi) : `space:<nom>`, `field:<espace>.<champ>`, `relation:<espace>.<champ>`,
`view:<espace>.<nom>`, `page:<nom>`, `dataview:<nom>`, `plugin:<nom>`, `group:<nom>`,
`perm:<groupe>|<type>|<ressource>|<niveau>`, `seed:<espace>|<clé naturelle>`.

**Empreinte.** `fingerprint(item)` = SHA-256 hexadécimal (`digest.sha256_hex`) de la
sérialisation canonique JSON de l'élément (clés triées, sans identifiants locaux ni
dates).

**Interfaces (à respecter par toutes les tâches V\*) :**

```
-- core/app_package.moon
canonical = (value) -> string                    -- JSON à clés triées
fingerprint = (item) -> string                   -- sha256 hex de canonical item
describe_local = (item_type, key) -> table|nil   -- état local courant d'un élément (même forme que dans un paquet)
build_package = (meta, opts) -> package          -- meta: {id, name, version, description}
-- package = { app = {id,name,version,description}, items = { {type, key, content, renamed_from?}, ... }, seed_keys = {espace = champ_clé} }

-- core/app_plan.moon  (fonction pure, sans accès à box)
plan_update = (installed, package, local_states) -> plan
-- installed: { [key] = {type, fingerprint, state} }   (contenu de _tdb_app_items pour cette app)
-- local_states: { [key] = table|nil }                  (describe_local pour chaque clé concernée)
-- plan = { create = {item}, update = {item}, conflict = {{item, local, delivered}},
--          keep_local = {item}, obsolete = {key}, rename = {{from, to}}, unchanged = {key} }

-- core/app_apply.moon
install_or_update = (package, decisions, opts) -> report   -- atomique (box.begin/commit), applique plan_update ; decisions[key] = 'local'|'delivered'
purge_obsolete = (app_id, keys) -> report                  -- exige confirmation côté résolveur
preview_purge = (app_id, keys) -> { losses = { {key, records=n, relations=n} } }
```

Tables système (bootstrap dans `core/spaces.moon`, même mécanisme que les autres
`_tdb_*`) : `_tdb_apps` {app_id, name, version, installed_at, source} et
`_tdb_app_items` {app_id, key, type, local_id, fingerprint, state, version}.

| Id | Tâche | Fichiers | Dépend de |
|---|---|---|---|
| V0 | corriger l'export des données (`build_snapshot` lit `tuple[position+1]` alors que les enregistrements sont un blob JSON en `tuple[2]`) ; test d'aller-retour export/import avec données | `resolvers/export_resolvers.moon`, `tests/test_snapshot.moon` | — |
| V1 | `core/app_package.moon` : `canonical`, `fingerprint`, `describe_local`, `build_package` ; tables `_tdb_apps`/`_tdb_app_items` | `core/app_package.moon`, `core/spaces.moon` (bootstrap), `tests/test_app_package.moon` | V0 |
| V2 | `core/app_plan.moon` : `plan_update` pure, tous les cas du spec §2 (créé, mis à jour, conflit, surcharge locale, obsolète, renommage `renamed_from`, seed sans suppression, groupes sans écrasement) | `core/app_plan.moon`, `tests/test_app_plan.moon` | V1 (interfaces seulement) |
| V3 | `core/app_apply.moon` : installation, mise à jour atomique, marquage obsolète, `preview_purge`, `purge_obsolete` ; version inférieure refusée sans option | `core/app_apply.moon`, `tests/test_app_apply.moon` | V1, V2 |
| V4 | résolveurs GraphQL : `exportApp`, `previewAppUpdate`, `applyAppUpdate`, `listApps`, `previewPurge`, `purgeObsolete` (admin) ; SDL `schema/tdb.graphql` ; `make sdl-gen`, `make doc-gen` | `resolvers/app_resolvers.moon`, `resolvers/init.moon`, `schema/tdb.graphql`, `schema/tdb.generated.graphql`, `scripts/doc_domains.moon` | V3 |
| V5 | interface « Applications » : liste, aperçu (créations, mises à jour, conflits, obsolètes), choix par conflit, plugins/formules changés mis en évidence, purge avec pertes en rouge et confirmation par saisie du nom ; remplace le mode *replace* destructif de l'import | `frontend/src/apps.coffee`, `app_sidebar_helpers.coffee`, `backend/index.moon` (balise), `po/` | V4 |
| V6 | test d'intégration backend (installer → modifier localement → mettre à jour avec conflit → aucune perte d'enregistrement → purger) et specs Playwright (aperçu, conflit, purge) | `tests/test_app_lifecycle.moon`, `tests/playwright/apps/*.spec.coffee` | V5 |

## Étape 5 : documentation publique

| Id | Tâche | Fichiers |
|---|---|---|
| D1 | README réécrit (objectif, fonctionnalités réelles, installation, structure à jour, versionnage), **sans positionnement face à Grist** ; supprimer les références périmées (Univer, `init.lua`, `index.html`) | `README.md` |
| D2 | `doc/` : supprimer la phrase anglaise sur Grist des versions FR ; documenter permissions appliquées, validation, versionnage ; `make doc-gen`, `make doc-check` | `doc/**`, `po/**`, `scripts/*` si besoin |
| D3 | racine : déplacer `AUDIT.md`, `GraphQL.md`, `Views.md`, `ROADMAP_drag_drop_widgets.md` dans `doc/` (ou fusionner), `AUDIT.md` mis à jour avec l'état réel, `.gitignore` | racine, `doc/` |

## Review Focus

- Mise à jour d'une app : aucun enregistrement utilisateur supprimé, jamais (test avec
  comptage avant/après).
- Élément modifié localement ET par l'auteur : conflit signalé, jamais écrasé en silence.
- Paquet invalide ou version inférieure : refusé sans effet partiel (atomicité).
- Éléments locaux (créés par l'utilisateur) : intacts après toute mise à jour.
- Purge : impossible sans aperçu des pertes et confirmation explicite.
