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

## 6. Prérequis et ordre de réalisation

Les droits par défaut n'ont de sens que si les permissions sont appliquées. Ordre :

1. Appliquer `permissions.can` dans les résolveurs ; durcir le sandbox des formules.
2. Valider types et `not_null` à l'écriture ; corriger les filtres ; supprimer
   l'heuristique `is_multiple_relation` (cardinalité déclarée dans le schéma).
3. Versionnage des apps (ce document).
4. README réécrit (sans positionnement face à Grist ; Grist cité comme idéal dans
   AGENTS.md) ; nettoyage de la racine ; découpage des plus gros fichiers, API GraphQL
   et plugins YAML conservés.

Chaque étape est un cycle spec → plan → exécution indépendant.
