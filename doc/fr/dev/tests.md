# Tests — référence détaillée

> Fichier généré automatiquement. Ne pas modifier manuellement.
>
> Généré le: 2026-03-12 10:33:27 UTC

Panorama des tests backend/frontend et intention par fichier.

| Module | Résumé |
|---|---|
| `tests/run.moon` | Point d'entrée de la suite de tests TGui. |
| `tests/runner.moon` | Micro-framework de test autonome (aucune dépendance externe). |
| `tests/test_batch_ops.moon` | Tests d'intégration GraphQL pour insertRecords/updateRecords sur un espace temporaire. |
| `tests/test_custom_views.moon` | Tests des opérations CRUD sur les vues personnalisées (resolvers/custom_view_resolvers.moon). |
| `tests/test_data_filters.moon` | Tests des opérateurs de filtrage (matches_filter / apply_filter). |
| `tests/test_executor.moon` | Tests de l'executor GraphQL (graphql/executor.moon). |
| `tests/test_lexer.moon` | Tests du lexer GraphQL (graphql/lexer.moon). |
| `tests/test_nesting.moon` | Tests des requêtes imbriquées (nesting/sub-queries) |
| `tests/test_parser.moon` | Tests du parser GraphQL (graphql/parser.moon). |
| `tests/test_permissions.moon` | Tests de la couverture des permissions : require_auth, require_admin, |
| `tests/test_relation_display_backend.moon` | Test backend pour vérifier l'affichage des relations |
| `tests/test_relation_display_regression.moon` | Test de régression pour s'assurer que l'affichage des relations ne casse plus |
| `tests/test_relation_field.moon` | Test pour s'assurer que le type Relation n'existe pas et que l'UI utilise les bonnes mutations |
| `tests/test_relation_integration.moon` | Test d'intégration complet pour les relations |
| `tests/test_relation_repr.moon` | Test pour vérifier que les relations utilisent bien _repr |
| `tests/test_relation_type_regression.moon` | Régression: vérifie le mapping sécurisé fieldType=Relation -> Int et la création de relation associée. |
| `tests/test_relations.moon` | Tests des relations FK : create_relation, list_relations, update_relation |
| `tests/test_schema.moon` | Tests du système de types GraphQL (graphql/schema.moon). |
| `tests/test_snapshot.moon` | Tests des resolvers exportSnapshot / diffSnapshot / importSnapshot. |
| `tests/test_spaces.moon` | Tests des opérations CRUD sur les espaces (core/spaces.moon). |
| `tests/test_triggers.moon` | Tests des trigger formulas (core/triggers.moon). |
| `tests/js/dom_stub.coffee` | (pas de description en tête de fichier) |
| `tests/js/run.coffee` | (pas de description en tête de fichier) |
| `tests/js/runner.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_auth.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_custom_view.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_data_view.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_graphql_client.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_i18n.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_relation_display_frontend.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_relation_display_frontend_regression.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_spaces.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_undo_helpers.coffee` | (pas de description en tête de fichier) |
| `tests/js/test_yaml_builder.coffee` | (pas de description en tête de fichier) |
