# Documentation développeur — TGui

> Fichier généré automatiquement. Ne pas modifier manuellement.
>
> Généré le: 2026-03-12 10:33:27 UTC

Synthèse compacte de l’architecture TGui. La référence complète est disponible dans `doc/fr/dev/*.md`.

## Architecture (résumé)

- Point d’entrée d’exécution: `backend/init.moon`
- Passerelle HTTP: `backend/http_server.moon`
- Exécution GraphQL: `backend/graphql/executor.moon`
- Assemblage schéma/résolveurs: `backend/resolvers/init.moon`
- Moteur métadonnées: `backend/core/spaces.moon`
- Interface SPA: `frontend/src/app.coffee`

## Références détaillées

- Architecture globale: `doc/fr/dev/architecture.md`
- Exécution backend: `doc/fr/dev/runtime.md`
- Chaîne GraphQL: `doc/fr/dev/graphql.md`
- Interface SPA: `doc/fr/dev/frontend.md`
- Stratégie de tests: `doc/fr/dev/tests.md`

## Commandes

- Génération docs: `make doc-gen`
- Vérification docs: `make doc-check`
- CI complète: `make ci`
