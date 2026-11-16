# Plan — réduire le coût des formules en lecture (option 4)

Contexte : `fiber.set_max_slice` global relevé à 20 s (`5415f12`) pour qu'une
grille à colonnes calculées ne soit pas interrompue. Les options 2 (tranche par
requête GraphQL) et 3 (`fiber.yield` toutes les N lignes) traitent le blocage ;
ce plan traite la cause : le volume de calcul par lecture.

## État des lieux (2026-11-16)

- `DataView.load` (`frontend/src/views/data_view.coffee` ~l.431-450) charge
  jusqu'à **2000 lignes** (5000 ailleurs, l.76) en une requête ; toutes leurs
  colonnes calculées sont évaluées côté serveur, ligne par ligne.
- Le **filtre** (champ λ) est évalué côté serveur (`apply_filter`,
  `data_resolvers.moon` ~l.76) ; le **tri** est fait par Toast UI Grid côté
  client, sur les lignes chargées.
- Les « trigger formulas » (`core/triggers.moon`) stockent déjà une valeur à
  l'écriture, mais seulement à partir de l'enregistrement lui-même : aucune
  invalidation quand une autre table dont la formule dépend change.
- Aucune mesure du temps par formule : `formula_metrics` ne compte que les
  erreurs.

## Étape 0 — Mesurer (prérequis, petite tâche)

Ajouter à `safe_formula_call` un cumul par `space.field` : nombre d'appels et
temps total (`clock.monotonic`), exposé par une requête admin
(`formulaMetrics`) et remis à zéro à la demande. Mesurer sur le jeu
« Bibliothèque » (cf. mémoire projet) les grilles les plus lentes.
**Décision attendue de cette étape** : quelles formules coûtent, et si le
coût vient du nombre de lignes (→ étape 1) ou de formules qui parcourent
d'autres espaces (→ étape 2).

## Étape 1 — Ne calculer que ce qui est affiché

1a. **Colonnes calculées à la demande** : la requête de la grille ne
demande que les colonnes visibles (déjà le cas par le SDL dynamique ?
à vérifier : `fieldList` l.431) ; les colonnes masquées ne doivent pas être
évaluées.

1b. **Pagination côté serveur** (le gros morceau) : `records` accepte déjà
`limit`/`offset`. Il faut :
- un argument `sort: [{column, ascending}]` sur `records` (même format que
  `validate_sort` des préréglages), le tri passant du client au serveur ;
- trier sur une colonne calculée impose de la calculer pour toutes les lignes
  filtrées : ne trier côté serveur que si la colonne est stockée ou si le
  coût est acceptable (mesure de l'étape 0) ;
- **limite majeure : le filtre λ** peut lire n'importe quel champ, y compris
  calculé ou traversant des relations. Paginer ne dispense donc pas d'évaluer
  le λ (et ce dont il dépend) sur **toutes** les lignes ; seule l'évaluation
  des colonnes affichées sur les lignes hors page est économisée. Avec un λ
  coûteux, la pagination n'aide presque pas : c'est l'étape 2 (valeurs
  stockées, lues sans calcul par le λ et le tri) qui règle ce cas ;
- Toast UI Grid en mode `dataSource` (pagination/défilement infini) :
  vérifier l'API dans `frontend/vendor/tui-grid.bundle.js` ;
- impacts à recenser : sentinelle de nouvelle ligne (`_pinSentinelLast`),
  sélection, undo/redo, préréglages de tri, widgets de page, export.

## Étape 2 — Stocker les valeurs coûteuses (à la Grist)

Option « colonne calculée stockée » : la valeur est écrite dans le tuple et
recalculée quand une dépendance change.
- Dépendances : relever, à l'évaluation, les espaces/champs lus via le proxy
  (`formula_proxy.moon` voit déjà chaque accès `self.x` et `space(...)`).
- Invalidation : trigger `on_replace` sur les espaces sources → recalcul des
  lignes dépendantes, **hors transaction de l'écriture d'origine** (fibre
  différée) pour ne pas allonger les écritures ni dépasser la tranche.
- Bascule par champ (`stored: true` dans `_tdb_fields`), migration et export
  d'app (spec de versionnage §7-8 à respecter).

## Ordre proposé

0 → 1a → (décision selon mesures) 1b ou 2. Chaque étape : un worktree, tests
`make test` + mesure avant/après sur l'instance de test (8081).
