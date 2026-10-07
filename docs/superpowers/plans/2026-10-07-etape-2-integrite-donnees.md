# Étape 2 — Intégrité des données — plan d'implémentation

> Même cadre que `2026-10-07-etapes-0-1-agents-et-securite.md` (contraintes globales,
> TDD, un worktree par tâche, commits intermédiaires, vérification par exécution réelle).

**Objectif :** valider types et `not_null` à l'écriture, rendre les filtres robustes,
déclarer la cardinalité des relations, corriger deux bugs de `core/views.moon`.

**Spec :** `docs/superpowers/specs/2026-10-07-app-versioning-design.md` §8.

## Propriété des fichiers (pour paralléliser sans conflit)

| Tâche | Fichiers | Dépend de |
|---|---|---|
| T5 bugs `views.moon` | `backend/core/views.moon`, `tests/test_views_core.moon` | — |
| T6 validation à l'écriture | `backend/core/validation.moon` (nouveau), `backend/resolvers/data_resolvers.moon` (mutations seulement), `tests/test_validation.moon` | — |
| T7 filtres robustes | `backend/resolvers/data_resolvers.moon` (`matches_filter`), `tests/test_data_filters.moon` | T6 (même fichier) |
| T8 cardinalité des relations | `backend/core/triggers.moon`, `backend/core/spaces.moon`, `schema/tdb.graphql`, résolveurs de relations | t2 (sandbox, même `triggers.moon`) |

## Review Focus

- `insertRecord` avec champ inconnu, `not_null` absent, mauvais type : erreur par champ.
- Champs calculés (formule/trigger) et `Sequence` : jamais exigés ni acceptés en entrée.
- `updateRecord` partiel : ne revalide pas les champs absents ; refuse un `null` sur `not_null`.
- Filtre numérique sur valeur non numérique ou vide : enregistrement exclu, aucune erreur.

## T5 : bugs de `core/views.moon`

Faits mesurés (lecture du code) : (1) `create_view` (~ligne 10) appelle
`validate_view_yaml`, déclarée plus bas (~ligne 98) : à l'appel c'est une globale `nil` ;
(2) `update_view` (~lignes 42-47) : `config_str` est déclarée locale à chaque branche du
`if/else`, donc la valeur écrite dans `replace` est `nil` quand `patch.config` est fourni
ou non. Chaque bug : un test de non-régression d'abord (qui échoue), puis le correctif
minimal (déplacer la déclaration, déclarer `config_str` avant le `if`). Un commit par bug.

## T6 : validation à l'écriture

Nouveau module `core/validation.moon` : `validate_record space_id, data, mode` où mode est
`'insert'` ou `'update'`. Il retourne la table nettoyée ou lève une erreur listant, par
champ, la raison. Règles (à vérifier dans le code avant d'appliquer, ne rien deviner) :
champs inconnus refusés ; types `String`, `Int`, `Float`, `Boolean`, `UUID`, `Any`/`Map`/
`Array` ; `Datetime` et `Relation` : lire comment ils sont stockés (frontend, fixtures,
tests existants) avant de décider, sinon accepter et signaler ; `Sequence` et champs à
formule/trigger : ni exigés ni acceptés ; `not_null` exigé à l'insert, et interdit
(`null`) à l'update. Brancher dans `insertRecord`/`updateRecord` (et les mutations par
lot si elles écrivent des enregistrements). Les 903 assertions existantes doivent rester
vertes : si une fixture écrit des données invalides, le signaler, ne pas assouplir la règle.

## T7 (après T6) : filtres

`matches_filter` (`data_resolvers.moon` ~lignes 25-45) : `tonumber(v) < tonumber(flt.value)`
plante si l'un des deux est `nil`. Comparer selon le type : numérique si les deux se
convertissent, sinon exclure l'enregistrement sans erreur. Tests : valeur vide, texte, `nil`.

## T8 (après t2) : cardinalité déclarée

Supprimer `is_multiple_relation` (`triggers.moon`) ; ajouter un attribut de cardinalité
(`one` | `many`) à `_tdb_relations` avec migration (défaut documenté), exposé dans le SDL
statique. Plan détaillé à écrire quand t2 sera fusionné.
