# Versionnage des applications TGui — spécification de conception

Date : 2026-10-07 — Statut : à relire

## Objectif

Permettre à l'auteur d'une application construite sur TGui de la publier sous forme de
paquet, à d'autres utilisateurs de l'installer, puis de recevoir les améliorations de
l'auteur **sans repartir de zéro** : données et personnalisations locales conservées.

Décisions de cadrage (validées) :

- Les éléments livrés par l'app et les éléments créés localement sont **séparés** :
  les premiers sont mis à jour, les seconds ne sont jamais touchés.
- Approche A : manifeste déclaratif avec clés stables (pas de fusion à trois voies,
  pas de scripts de migration pour cette première version).
- Une mise à jour **ne supprime jamais de données** ; une option de purge des éléments
  obsolètes existe, avec mise en évidence des pertes et confirmation explicite.
- Les lignes d'amorçage (`seed`) font partie du paquet.
- Les groupes et leurs droits par défaut sont livrés ; les membres et droits modifiés
  localement ne sont jamais écrasés.
- Hors périmètre : réduire l'API GraphQL ou les plugins YAML (à conserver intacts).

## 1. Modèle

### Paquet (`.tdbapp.yaml`)

- En-tête : `app: {id, name, version, description}` ; `id` stable et global
  (ex. `org.exemple.biblio`), `version` semver.
- Contenu : espaces (champs, relations), vues de données, pages, plugins YAML, groupes
  avec droits par défaut, lignes `seed` pour les espaces marqués `seed: true`.
- Chaque élément est identifié par une **clé stable** (nom dans son périmètre), jamais
  par un UUID local. `renamed_from: ancien_nom` déclare un renommage.
- Lignes `seed` : une clé naturelle par ligne (champ désigné par `seed_key`).

### Installation (espaces système)

- `_tdb_apps` : `app_id`, version installée, date, source.
- `_tdb_app_items` : `app_id`, type, clé, UUID local, **empreinte du contenu livré**,
  état (`actif` | `obsolète`).
- Tout élément absent de `_tdb_app_items` est « local ».

## 2. Algorithme de mise à jour

Pour chaque élément du nouveau paquet : comparer empreinte livrée (installée),
empreinte nouvelle et état local courant.

| Situation | Action |
|---|---|
| Nouvel élément | Créé |
| Inchangé localement, modifié par l'auteur | Mis à jour |
| Modifié localement et par l'auteur | Conflit : « garder le local » ou « prendre le nouveau » |
| Modifié localement seulement | Conservé (surcharge locale) |
| Absent du nouveau paquet | Marqué obsolète, jamais supprimé |
| `renamed_from` correspondant | Renommé en place, données conservées |

Lignes `seed` : ajout des nouvelles, mise à jour de celles non modifiées localement,
aucune suppression. Groupes : créés si absents ; membres et droits locaux préservés.

## 3. API et interface

- GraphQL : `exportApp(appId)`, `previewAppUpdate(package)`,
  `applyAppUpdate(package, decisions)`, `listApps`, `purgeObsolete(appId, items)`.
- **Aperçu obligatoire** avant application (créations, mises à jour, conflits, obsolètes).
- **Purge des obsolètes** : aperçu des pertes (enregistrements par champ ou espace,
  relations touchées), éléments en rouge, confirmation en saisissant le nom de l'élément.
- Interface : section « Applications » à côté d'Export/Import. Le mode *replace*
  destructif de l'import snapshot disparaît ; l'import devient « installer un paquet ».
  Le diff de `export_resolvers.moon` (`diff_snapshot`, `do_import`) est réutilisé
  autant que possible.

## 4. Erreurs et sécurité

- Application **atomique** (tout ou rien) ; échec → état précédent restauré.
- Version inférieure à l'installée refusée sans option explicite ; `app.id` inconnu →
  installation, pas mise à jour.
- Opérations réservées à `require_admin`.
- Plugins et formules livrés = code tiers : l'aperçu affiche ceux qui changent.
  Les plugins restent exécutés dans l'iframe sandboxée existante.

## 5. Tests

- Unitaires : empreintes, diff à trois états, `renamed_from`, marquage obsolète, seed.
- Intégration : installer → modifier localement → mettre à jour avec conflit → vérifier
  qu'aucun enregistrement n'est perdu → purger.
- Playwright : aperçu, résolution de conflit, purge avec confirmation.

## 6. Ordre de réalisation

Les droits par défaut n'ont de sens que si les permissions sont appliquées. Ordre :

1. Sécurité (§7).
2. Intégrité des données (§8).
3. Versionnage des apps (§1 à §5).
4. Documentation, tests et maintenabilité (§9 à §11).

Chaque étape est un cycle plan → exécution indépendant, commité par petites étapes.

## 7. Corrections — sécurité (étape 1)

Problèmes relevés à la revue générale du 2026-10-07 (lecture du code).

- **Permissions non appliquées.** `core.permissions.can` n'est appelée par aucun
  résolveur : tout utilisateur authentifié peut lire, écrire, supprimer espaces et
  enregistrements, ou modifier le schéma. Correction : un contrôle `can(user, type, id,
  niveau)` dans chaque résolveur (lecture → `read`, écriture de données → `write`,
  schéma → `admin`), factorisé dans `resolvers/utils.moon` (ex. `require_perm`).
  Le groupe `admin` garde tous les droits. Mettre à jour la phrase correspondante du
  README. Tests : un utilisateur sans groupe, `read` seul, `write` seul, `admin`,
  pour chaque famille de résolveurs (schéma, données, vues, data views, pages, plugins,
  export).
- **Sandbox des formules** (`core/triggers.moon`, `FORMULA_ENV`).
  - `string`, `table`, `math` sont les vraies tables globales : une formule peut les
    modifier (`string.format = nil`) et corrompre tout le serveur. Correction : copies
    profondes (ou proxies en lecture seule) par environnement.
  - Boucle infinie possible (`(function() while true do end end)()`) : limiter
    l'exécution (hook `debug.sethook` par instructions, ou délai) à l'appel de la formule.
  - Déni de service mémoire (`("x"):rep(1e9)`) : borner la taille des chaînes produites
    (ex. wrapper de `string.rep`) ou la mémoire par appel.
  - Tests : chaque cas ci-dessus doit échouer proprement avec une erreur de formule
    sans affecter les autres appels.
- **Fichiers statiques** : vérifier et corriger le traversal de chemin
  (`FRONTEND_DIR .. req.path`) — refuser `..`, chemins absolus, octets nuls.
  Test dédié sur l'instance de test.
- **Export** (`http_server.moon`, `handle_export`) : réécrire proprement (parsing de la
  requête, suppression des logs et commentaires d'hésitation) et utiliser
  `require_admin` (appartenance au groupe) au lieu du test sur le nom `admin`.
- **Points ouverts de `AUDIT.md`** : rate-limiting persistant au-delà de la mémoire
  (1.2), changement forcé du mot de passe admin par défaut côté serveur (1.4),
  échappement des `innerHTML` (1.9). Le token en `localStorage` (1.5) est documenté
  comme risque connu.

## 8. Corrections — intégrité des données (étape 2)

- **Validation à l'écriture.** `insertRecord`/`updateRecord` doivent contrôler les
  champs inconnus, `not_null` et le type déclaré (`String`, `Int`, `Float`, `Boolean`,
  `UUID`, `Datetime`, etc.), avec un message d'erreur par champ. Les `Sequence` restent
  immuables. Tests pour chaque type et pour `not_null`.
- **Filtres.** `tonumber(v) < tonumber(flt.value)` plante sur une valeur non numérique :
  comparer selon le type du champ (numérique, texte, date), exclure l'enregistrement si
  la valeur est invalide, sans erreur. Tests avec valeurs vides, non numériques, dates.
- **Relations.** Supprimer l'heuristique `is_multiple_relation` (le schéma GraphQL ne
  doit pas dépendre du contenu des données). La cardinalité est **déclarée** sur la
  relation (`one`/`many`) et incluse dans le paquet d'app ; migration des relations
  existantes avec une valeur par défaut et un message clair.
- **Performance** (non bloquant, noté) : les enregistrements sont un blob JSON lu par
  `select {}` complet. Hors périmètre de ce spec ; à traiter si la volumétrie l'exige.

## 9. Corrections — documentation (étape 4)

- **README** réécrit : objectif du projet, fonctionnalités réelles (espaces, champs,
  relations, formules, API GraphQL, Data Views, pages et plugins YAML, permissions,
  versionnage des apps), installation, structure à jour (suppression des références à
  Univer, `init.lua`, `index.html`). **Aucun positionnement face à Grist.**
- **AGENTS.md** : mention de Grist comme source d'inspiration et idéal visé.
- **doc/** : supprimer la phrase anglaise sur Grist des versions FR (`get-started.md`,
  `reference.md`) ; documenter le versionnage des apps et les permissions réellement
  appliquées ; régénérer avec `make doc-gen`, vérifier avec `make doc-check`.
- **Racine** : `AUDIT.md`, `GraphQL.md`, `Views.md`, `ROADMAP_drag_drop_widgets.md`
  déplacés dans `doc/` (ou fusionnés), `AUDIT.md` mis à jour avec l'état réel.

## 10. Corrections — tests (étapes 1 à 4)

- Ajouter les tests listés en §7 et §8, plus ceux du versionnage (§5).
- Nettoyer : fusionner les variantes (`test_multiple_relations*`,
  `test_graphql_builder_*`), déplacer ou supprimer les `.coffee` isolés de `tests/`,
  supprimer `test_error_format.lua` (fichier sans source à la racine), remplacer la
  découverte par `io.popen 'ls …'` par `fio.glob`.
- Vérifier que `tests/run.moon` restaure bien le schéma de production en fin de run.

## 11. Corrections — maintenabilité / KISS (étape 4)

Contraintes : **l'API GraphQL et les plugins YAML sont conservés intacts**.

- Découper les fichiers monolithiques : `frontend/src/app_view_helpers.coffee`
  (1 875 lignes), `backend/resolvers/custom_view_resolvers.moon` (921),
  `frontend/src/views/data_view.coffee`, `views/custom_view.coffee` et
  `backend/index.moon` (750 à 890 lignes chacun), `backend/core/triggers.moon` (634 :
  séparer sandbox, proxy FK et enregistrement des triggers).
- Éliminer les duplications : requêtes GraphQL dupliquées (`LIST_WIDGET_PLUGINS`),
  formatters d'erreur de formule (`data_view.coffee`), conversions tuple → table,
  constructions de maps FK dans `triggers.moon`.
- Pas de changement fonctionnel : chaque découpage est vérifié par la suite de tests
  existante, qui doit rester verte.
