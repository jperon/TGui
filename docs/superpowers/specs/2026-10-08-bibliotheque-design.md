# Application « Bibliothèque » — spécification de conception

Date : 2026-10-08. Statut : à relire par l'utilisateur avant tout plan.

## 1. Objectif

Fournir une application de gestion de bibliothèque scolaire, livrée comme **paquet
d'application TGui** (`.tdbapp.yaml`, voir
`docs/superpowers/specs/2026-10-07-app-versioning-design.md`), avec des **données
fictives déterministes**. Elle sert de :

- démonstration réaliste de TGui (relations, formules, hiérarchie, calculs sur le prêt
  en cours) — dans l'esprit « alternative à Grist » du projet ;
- base de tests : installation/mise à jour d'une vraie application, volumes réalistes.

Source d'inspiration : `~/Téléchargements/Bibliothèque.grist` (structure seule, aucune
donnée). Cette base est elle-même issue d'une base de gestion d'école ; on conserve la
partie qui sert aux emprunts et on retire le reste.

## 2. Principes

- **Pas de RefList.** Une colonne ne contient jamais une liste d'identifiants
  (dénormalisation). Toute relation N-N passe par un **espace de liaison** ; toute
  « liste de liés » (élèves d'une classe, exemplaires d'un livre, enfants d'une famille)
  s'obtient par **jointure** sur la relation 1-N, jamais par une colonne stockée.
- **Formules réécrites**, pas copiées : celles de Grist sont en Python
  (`lookupRecords`, `SortedList`, `CONTAINS`). Ici : Lua/MoonScript, proxys de relations
  et `space()` (`backend/core/formula_proxy.moon`).
- Conventions de nommage de l'existant : espaces au pluriel capitalisé (`Auteurs`),
  champs en `snake_case`, `id` de type `Sequence`, champ `_repr` pour la
  représentation affichée.
- Types TGui : `String`, `Int`, `Float`, `Boolean`, `Datetime`, `Sequence`,
  `Relation` (clé étrangère). Pas d'énumération : un référentiel = un petit espace.

## 3. Modèle de données

Légende : `→ X` = relation (clé étrangère) vers l'espace X. `(calc)` = formule.

### 3.1 Bibliothèque

| Espace | Champs | Calculés |
|---|---|---|
| `Genres` | `genre`, `parent → Genres` | `niveau` (profondeur), `chemin` (« Roman › Policier »), `nombre_de_livres` |
| `Auteurs` | `nom`, `particule`, `prenom`, `titre` | `nom_complet`, `n_ouvrages` |
| `MotsCles` | `mot` | `occurrences` |
| `Livres` | `titre`, `auteur → Auteurs`, `genre → Genres`, `note`, `age_min`, `age_max`, `commentaire` | `descriptif`, `n_exemplaires`, `doublon` (même titre + auteur) |
| `LivresMotsCles` | `livre → Livres`, `mot_cle → MotsCles` | — |
| `Exemplaires` | `livre → Livres`, `cote`, `acquisition`, `suppression` | `descriptif`, `emprunteur` (personne du prêt non rendu, sinon vide) |
| `Emprunts` | `personne → Personnes`, `exemplaire → Exemplaires`, `emprunt`, `retour` | `livre`, `classe` (classe de l'emprunteur), `annee` (année scolaire contenant `emprunt`), `annee_en_cours` |

Écarts assumés par rapport à Grist :

- `Livres.Etiquettes` pointe vers `T_Bibliotheque_livres_etiquettes`, **table absente**
  du fichier (référence orpheline) : abandonnée. Seuls les mots-clés sont conservés.
- `Genres.Genres` (ancêtres), `Genres.Livres`, `Genres.Especes`, `Livres.Genres`,
  `Livres.Exemplaires` et `Emprunts.Genres` étaient des RefList calculées : supprimées.
  Les « livres d'un genre, sous-genres compris » sont une requête/jointure, pas une
  colonne (voir §8, question ouverte 2).
- `Valide` (existence des références) est remplacé par l'intégrité référentielle que
  TGui applique à l'écriture (spec versionnage §8).

### 3.2 École (emprunteurs)

| Espace | Champs | Calculés |
|---|---|---|
| `Titres` | `titre`, `abrege`, `femme` | — |
| `Personnes` | `nom`, `particule`, `prenom`, `titre → Titres`, `date_de_naissance`, `lieu_de_naissance`, `precision`, `famille → Personnes`, `externe` | `descriptif`, `age`, `classe_actuelle`, `emprunts_en_cours` |
| `Sections` | `section`, `abregee` | — |
| `Annee` | `debut`, `fin`, `section → Sections` | `n`, `annee` (« 2025 - 2026 »), `en_cours`, `precedente`, `anciennete` |
| `Niveaux` | `niveau`, `classe`, `abrege`, `generique`, `superieur → Niveaux` | `descriptif` |
| `Prefectures` | `annee → Annee`, `prefet → Personnes`, `niveau_min → Niveaux`, `niveau_max → Niveaux` | `descriptif`, `effectif` |
| `Classes` | `niveau → Niveaux`, `annee → Annee`, `prefecture → Prefectures`, `professeur_principal → Personnes`, `precision` | `descriptif`, `descriptif_complet`, `effectif`, `naissance_theorique` |
| `ClassesEleves` | `classe → Classes`, `eleve → Personnes`, `entree`, `depart`, `redoublement` | `annee`, `annee_en_cours` (année en cours et pas de départ), `doublon` |

`ClassesEleves` est la liaison N-N élève ↔ classe (un élève change de classe chaque
année). `Personnes.classe_actuelle` et `Classes.effectif` en sont des jointures.

Retirés (sans rapport avec la bibliothèque) : notes, évaluations, périodes, trimestres,
compositions, appréciations, cours, notices, listes, communes et géocodage, vCard,
classements, ainsi que les colonnes de `R_Classes_Eleves` liées aux notes
(`Periode`, `Defaillant`, `Classement_periode`, `Objectif`, `Recapitulatif_periode`…).

### 3.3 Coordonnées

| Espace | Champs |
|---|---|
| `TypesCoordonnees` | `type` ∈ {`tel`, `courriel`, `adresse`} (3 lignes de seed) |
| `Coordonnees` | `type → TypesCoordonnees`, `valeur` (texte libre) |
| `PersonnesCoordonnees` | `personne → Personnes`, `coordonnee → Coordonnees`, `libelle` (« domicile », « parents »…) |

Relation N-N : une coordonnée (ex. le téléphone familial) peut concerner plusieurs
personnes ; une personne en a plusieurs. Pas de géocodage ni de commune.

## 4. Livraison

```
apps/bibliotheque/
├── structure.yaml        # espaces, champs, relations, formules (source de vérité, écrit à la main)
├── gen_seed.moon         # générateur de données fictives (graine fixe)
└── bibliotheque.tdbapp.yaml   # paquet produit = structure + seed (commité)
tests/test_app_bibliotheque.moon
```

- `bibliotheque.tdbapp.yaml` est un artefact commité, comme les `.lua`/`.js` : régénéré
  par une cible Makefile (`make app-bibliotheque`), jamais édité à la main.
- Le paquet utilise le format défini par `core/app_package.moon` : items `space`,
  `field`, `relation`, `seed`, clés stables (`space:Livres`, `field:Livres.titre`,
  `relation:Livres.auteur`, `seed:Livres|<clé naturelle>`), `app.id` =
  `org.tgui.bibliotheque`, `version` semver.
- `backend/fixtures.moon` n'est **pas** modifié dans cette étape : des tests existants
  dépendent de ses espaces (`Auteurs`, `Livres`, `Emprunts`, `Categories`). La
  bibliothèque s'installe **en plus** (cas à traiter : conflit de noms d'espaces, voir
  question ouverte 3). La bascule des tests vers la bibliothèque sera un chantier
  distinct.

## 5. Données fictives

Générateur MoonScript, graine fixe : même sortie à chaque exécution.

Volume « standard » (commité, environ 300 lignes) : 3 années (dont une en cours),
5 niveaux, 8 classes, 60 élèves, 12 familles/adultes, 15 genres sur 3 niveaux, 25 auteurs,
60 livres, 100 exemplaires, 120 emprunts (dont une trentaine non rendus), 40 mots-clés,
30 coordonnées. Option `--scale N` multiplie les volumes pour des tests de charge (non
commitée).

Contraintes de cohérence que le générateur doit garantir :

- clés étrangères du seed = `id` explicites du seed (voir §6) ;
- un exemplaire a au plus un emprunt non rendu ;
- un élève n'a qu'une classe sans `depart` dans l'année en cours ;
- noms/titres plausibles mais fictifs, aucune donnée personnelle réelle.

## 6. Risques et points à vérifier d'abord

Constatés dans `backend/core/app_apply.moon` (lignes 693-728) :

1. **Les lignes seed sont insérées en brut** (`sp:insert { uuid, json.encode data }`),
   avec les `id` portés par `data`. Les clés étrangères du seed sont donc des entiers :
   le générateur doit attribuer des `id` explicites et cohérents.
2. **Compteur de séquence.** Rien n'indique que la séquence associée au champ `id`
   (`_tdb_seq_<field_id>`) soit avancée après un seed. Une insertion utilisateur
   ultérieure pourrait alors **réutiliser un `id` du seed**. À mesurer par un test
   avant tout reste ; si confirmé, c'est un défaut de TGui à corriger dans une tâche
   séparée (correction de l'installation, pas contournement dans le seed).
3. Les validations d'écriture (champs inconnus, `not_null`, types) ne s'exécutent pas
   sur le seed : le générateur doit les respecter lui-même, et le test d'installation
   relit les données via GraphQL pour le vérifier.
4. Format des dates dans le seed (type `Datetime`) : valeur attendue à confirmer
   (chaîne ISO ou nombre) avant d'écrire le générateur.

## 7. Tests

`tests/test_app_bibliotheque.moon`, dans l'instance de test :

- installation du paquet : tous les espaces, champs et relations existent ; nombre de
  lignes par espace conforme au générateur ;
- réinstallation du même paquet : aucun changement (idempotence, empreintes) ;
- intégrité : chaque clé étrangère du seed pointe sur un enregistrement existant ;
- formules : `Exemplaires.emprunteur`, `Livres.n_exemplaires`, `Auteurs.n_ouvrages`,
  `Personnes.classe_actuelle`, `Classes.effectif`, `Genres.chemin` donnent les valeurs
  attendues sur des cas du seed connus d'avance ;
- séquences : après installation, `insertRecord` sur chaque espace produit un `id`
  absent du seed (risque 2) ;
- déterminisme : deux exécutions du générateur donnent un paquet identique octet pour
  octet.

Vérification par exécution réelle (installation + `make test`), pas par relecture.

## 8. Questions ouvertes (à trancher en début de plan)

1. Les formules de `Personnes`, `Classes` et `Emprunts` traversent 2 à 3 relations :
   confirmer que les proxys de relations et `space()` le permettent, sinon passer ces
   colonnes en trigger (écrites à l'écriture).
2. « Livres d'un genre, sous-genres compris » : jointure récursive impossible en
   formule simple ; options (a) vue de données avec filtre sur `chemin`, (b) espace de
   fermeture transitive `GenresAncetres(genre, ancetre)` maintenu par le seed et un
   trigger. Par défaut : (a), (b) seulement si (a) est insuffisant.
3. Conflit de noms avec `fixtures.moon` (`Auteurs`, `Livres`, `Emprunts` existent déjà
   dans l'instance de test) : installer la bibliothèque dans une base vide dédiée, ou
   renommer l'un des deux jeux ?
4. Groupes/droits livrés par le paquet (lecteur, bibliothécaire) : hors périmètre de
   cette étape sauf demande contraire.

## 9. Hors périmètre

Notes, cours et évaluations de l'école ; géocodage ; import de l'ancien fichier Grist ;
migration des tests existants vers cette application ; interface dédiée (pages YAML)
— à envisager dans une étape ultérieure.
