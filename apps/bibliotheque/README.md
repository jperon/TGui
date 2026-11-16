# Application « Bibliothèque »

## But

Paquet TGui `org.tgui.bibliotheque` : l'école (personnes, années, niveaux, classes),
le catalogue de la bibliothèque (genres, auteurs, livres, exemplaires, emprunts) et
les coordonnées de contact, avec des données fictives déterministes.
Renvois : spec `docs/superpowers/specs/2026-10-08-bibliotheque-design.md` et plan
`docs/superpowers/plans/2026-10-08-bibliotheque.md` (tâche T9).

## Structure du dossier

- `bibliotheque.tdbapp.yaml` — le paquet (structure + seed) ; **artefact** produit par
  `make app-bibliotheque`, jamais édité à la main.
- `backend/apps/bibliotheque/app.yaml` et `backend/apps/bibliotheque/structure/*.yaml` —
  source de vérité de la structure (espaces, champs, relations, formules), écrite à la main.
- `backend/tools/bibliotheque_app.moon` — assembleur (`build(opts)`, `write(path, opts)`,
  `seed_tables(opts)`).
- `backend/tools/bibliotheque_seed_{ecole,livres,coordonnees}.moon` — générateurs de
  données fictives, à graine fixe (1001 / 2002 / 3003).

## Installation

1. Générer le paquet : `make app-bibliotheque`.
2. Dans l'IHM : **Administration > Applications** → encadré **Installer ou mettre à
   jour** → **📂 Choisir un fichier** → **Aperçu des changements** → **Appliquer**.
3. Par GraphQL : `previewAppUpdate(yaml:)` pour l'aperçu, puis `applyAppUpdate(yaml:)`
   pour l'installation (mutation admin).

## Régénération

- `make app-bibliotheque` — reconstruit le paquet depuis la structure et les seeds.
- `make app-bibliotheque-check` — vérifie que le paquet commité est identique à une
  régénération ; échoue avec « paquet périmé » s'il y a une dérive.

## Volumes et scale

À l'échelle 1 (paquet commité) : 72 personnes, 10 classes, 108 affectations,
60 livres, 100 exemplaires, 120 emprunts, 30 coordonnées, ~760 lignes au total.
`build({scale: N})` multiplie les volumes (facteur `N`) : utile pour des tests de
charge, mais cette variante n'est **pas** commitée.

## Vues de données et pages

L'application livre 8 vues de données prêtes à l'emploi, définies dans
`backend/apps/bibliotheque/structure/vues.yaml` :

- **Emprunts en cours**, **Exemplaires disponibles**, **Exemplaires prêtés**,
  **Livres sans exemplaire** — listes filtrées pour le guichet.

- **Livres les plus empruntés**, **Emprunts par année**, **Livres par genre**,
  **Effectifs par classe** — synthèses agrégées (regroupement + comptage).

Elle livre aussi 4 pages définies dans `backend/apps/bibliotheque/structure/pages.yaml` :
**Prêts et retours**, **Catalogue**, **Lecteurs et classes** (sélections en cascade) et
**Tableau de bord** (grille de synthèses).

## Conventions du seed

- ids entiers explicites (`1, 2, 3…`) ; toute clé étrangère vaut un `id` existant.
- Champs vides **omis** de la ligne, jamais `""`.
- Dates sous forme de chaînes ISO `YYYY-MM-DD`.
- Graine fixe : deux exécutions donnent exactement la même sortie.

## Références

- Spec : `docs/superpowers/specs/2026-10-08-bibliotheque-design.md`
- Plan : `docs/superpowers/plans/2026-10-08-bibliotheque.md` (T9)
- Paquets d'applications : `doc/fr/get-started.md` (« Applications »)
