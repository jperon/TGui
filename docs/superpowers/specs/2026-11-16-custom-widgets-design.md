# Widgets personnalisés — spécification de conception

Date : 2026-11-16. Inspiration : les *custom widgets* de Grist, sans leur
limite principale (un widget n'est pas réutilisable d'une page à l'autre).

## 0. Existant (à conserver : « plugins YAML » = pilier, cf. AGENTS.md)

Le projet a déjà des **widget plugins**, qui couvrent une grande partie du besoin :

| Élément | Où | État |
|---|---|---|
| Définition réutilisable (nom, description, script, gabarit) | `_tdb_widget_plugins`, `resolvers/widget_plugin_resolvers.moon`, SDL `WidgetPlugin` | ✅ globale, référencée par nom |
| Instance dans une page : `type: <nom du plugin>` + `params` | `views/custom_view.coffee` `_renderWidget`, `custom_view_plugins.coffee` | ✅ |
| Langages : script `coffeescript` / `javascript`, gabarit `pug` / `html` | `VALID_SCRIPT_LANGS`, `VALID_TEMPLATE_LANGS` | ✅ |
| Iframe `sandbox="allow-scripts"` (sans `allow-same-origin`) | `_mountPluginIframe` | ✅ |
| API dans l'iframe : `gql`, `emitSelection`, `onInputSelection`, `render`, `params` | `_buildPluginIframeDoc` | ✅ |
| Export / installation dans les paquets d'app (clé `plugin:<nom>`, empreinte, conflits) | `core/app_package.moon` `collect_plugins`, `core/app_apply.moon` | ✅ |
| Éditeur (CodeMirror, choix des langages) | `app_view_helpers_widget_plugins.coffee` | ✅ |

Ce spec **étend** ce système ; il ne crée pas de mécanisme parallèle. Le nom
« widget personnalisé » désigne dans l'interface ce qu'est un `WidgetPlugin`.

## 1. Décisions

1. **Définition / instance** : la définition (code) est unique ; une page n'en
   contient que des instances (référence par nom + paramètres). Corriger la
   définition corrige toutes les pages.
2. **Pas de version figée** par instance : une instance suit toujours la
   définition courante. Seule action d'indépendance : **« détacher »** (§4).
3. **Deux portées** : définition **globale** (bibliothèque de l'installation)
   ou **propre à une app**.
4. **Export autonome** : un paquet d'app embarque le code de toutes les
   définitions qu'il utilise, globales comprises (§5).
5. **Plusieurs langages de script**, dont Lua / MoonScript via wasmoon (§7).

## 2. Lacunes à combler

| # | Lacune | Section |
|---|---|---|
| L1 | Paramètres libres, sans déclaration ni mappage de colonnes | §3 |
| L2 | Pas de « détacher » | §4 |
| L3 | Pas de portée app/globale ; l'export collecte **tous** les plugins de l'installation, utilisés ou non | §5 |
| L4 | **Sécurité** : `gql_request` relaie n'importe quelle requête avec les droits de l'utilisateur, mutations et schéma compris ; un widget importé ouvert par un admin peut donc tout modifier | §6 |
| L5 | Pas d'API de données de haut niveau (lignes de la source, curseur) | §6 |
| L6 | Compilateurs (CoffeeScript, pug) chargés même sans widget | §7 |
| L7 | Pas de Lua / MoonScript | §7 |
| L8 | La fenêtre « ＋ Widget » (`backend/ui/widget_modal.moon:64`) ne propose que « Tableau simple » : un widget personnalisé ne s'ajoute qu'en écrivant son nom dans le YAML | §3 bis |

## 3 bis. Intégration à la fenêtre « ＋ Widget » (L8)

- Section « 2. Type de widget » : « Tableau simple », puis un groupe
  « Widgets personnalisés » listant les définitions (`widgetPlugins`) avec leur
  description ; portée affichée (app / bibliothèque) une fois §5 fait.
- Type personnalisé choisi → la section « 3. Paramètres » remplace les paires
  clé/valeur libres par un formulaire tiré du `manifest` : un sélecteur de
  colonne de la source par colonne déclarée (filtré par type), un champ par
  option (avec valeur par défaut). Sans `manifest` : paires clé/valeur
  actuelles.
- Validation avant création : colonnes obligatoires mappées. Le YAML produit
  est celui de §3 (`type`, `source`, `columns`, `params`).
- Lien « Nouveau widget personnalisé… » ouvrant l'éditeur de plugins existant.

## 3. Paramètres déclarés et mappage de colonnes (L1)

Nouveau champ de la définition, `manifest` (YAML, facultatif, rétrocompatible) :

```yaml
access: read            # none | read | full (défaut : read)
columns:                # colonnes attendues de la source
  - {name: titre, type: String}
  - {name: debut, type: Date}
  - {name: fin, type: Date, optional: true}
options:                # options typées de l'instance
  - {name: couleur, type: color, default: '#36c'}
```

Instance dans une page :

```yaml
- type: calendrier
  source: evenements          # espace ou data view
  columns: {titre: nom, debut: date_debut}
  params: {couleur: '#c33'}   # `params` existant = valeurs des options
```

- L'éditeur de page propose, pour chaque colonne déclarée, un sélecteur filtré
  par type ; une colonne obligatoire non mappée → message dans le widget, pas
  de chargement.
- Sans `manifest`, comportement actuel inchangé (params libres, `gql` brut).

## 4. Détacher (L2)

Action « Détacher » sur une instance : copie la définition sous un nouveau nom
(par défaut `<nom> (<page>)`, modifiable), de même portée que la page (app de
la page, sinon globale), puis réécrit **cette seule instance** vers la copie.
Aucune autre page n'est touchée. Mutation : `detachWidgetPlugin(pageId,
widgetId, newName)` → `require_admin` (crée une définition).

## 5. Portées et export (L3)

- `_tdb_widget_plugins` gagne `app_id` (nul = global). Unicité du nom par
  portée ; une instance résout d'abord la définition de son app, puis la
  globale.
- **Export d'une app** : on collecte les définitions **référencées** par ses
  pages (au lieu de toutes), globales comprises, marquées
  `origin: library` pour les globales. Empreinte = hash du `manifest`, du
  script, du gabarit et des langages.
- **Installation**, par définition embarquée (machinerie de conflits de
  `app_apply` réutilisée) :

| Cible | Action |
|---|---|
| Absente | Créée dans sa portée d'origine (app, ou bibliothèque si `origin: library`) |
| Présente, même empreinte | Réutilisée |
| Présente, empreinte différente | Conflit : *garder le local* / *remplacer* (liste les pages touchées) / *importer sous un autre nom* (défaut ; réécrit les références des pages importées) |

- Une définition globale utilisée ne peut pas être supprimée ; l'erreur liste
  les pages qui l'utilisent.
- Aperçu d'installation : définitions nouvelles ou modifiées et leur `access`
  affichés comme code tiers (spec de versionnage §4).

## 6. Accès et API de données (L4, L5)

Le parent filtre les messages selon `manifest.access` (défaut `read` pour les
définitions sans manifest **importées** ; les plugins existants créés
localement passent à `full` par migration, pour ne rien casser) :

| `access` | Autorisé |
|---|---|
| `none` | `params`, `render`, sélection ; aucune donnée |
| `read` | + API de lecture de la source mappée ; `gql` limité aux *queries* |
| `full` | + `updateRecord` / `insertRecord` / `deleteRecord` sur la source ; `gql` mutations de **données** seulement |

Jamais de mutation de schéma, d'utilisateurs ou d'apps depuis un widget, quel
que soit `access`. Le contrôle est fait **côté parent** (analyse de l'opération
avec le parser GraphQL existant, ou liste blanche des champs racine) **et** les
résolveurs gardent `core.permissions.can` : le widget n'obtient jamais plus que
l'utilisateur.

API ajoutée dans l'iframe (en plus de l'existante) :
`onRecords(cb)` (lignes de la source, colonnes renommées selon le mappage),
`onRecord(cb)` (ligne courante), `setCursor(id)`, et selon `access`
`updateRecord(id, values)`, `insertRecord(values)`, `deleteRecord(id)`.

## 7. Langages et chargement (L6, L7)

Un **registre de langages** côté iframe : `{id, load(), compile(code)}`.
Chaque runtime est chargé **à la demande** dans l'iframe (`<script src>` vers
`frontend/vendor/…`), seulement si la définition l'utilise.

| Langage | Exécution | Note |
|---|---|---|
| `javascript` | direct | |
| `coffeescript` | compilateur navigateur (vendor), à la demande | défaut recommandé |
| `lua` | wasmoon (Lua 5.4 en WebAssembly, vendor) | phase 2 |
| `moonscript` | compilé **côté serveur** par `moonscript.base.to_lua` (déjà utilisé pour les formules) à l'enregistrement, puis exécuté comme `lua` | phase 2 |

Lua / MoonScript :
- La définition stocke le source ; le Lua compilé est mis en cache (champ
  `compiled`, recalculé à chaque enregistrement ; erreur de compilation →
  refus d'enregistrer, message avec ligne).
- Le Lua n'est **pas** vérifié côté serveur : Tarantool tourne en LuaJIT
  (Lua 5.1), le widget sous wasmoon (Lua 5.4). `//`, `&`, `|`, `~`, `<<`, `>>`,
  `<const>`, `goto` sont valides en 5.4 et seraient refusés à tort par
  `loadstring`. Le source est donc stocké tel quel dans `compiled` et une erreur
  de syntaxe est signalée **dans le widget**, par wasmoon, avec sa ligne
  (`[string "..."]:N:`). Le Lua produit par moonc est valable en 5.1 comme en
  5.4 : MoonScript reste compilé et refusé côté serveur.
- L'API (§6) est exposée à Lua par l'interop wasmoon ; les rappels JS → Lua et
  les promesses (`gql`) sont adaptés par une petite couche (`await` wasmoon).
- Écart Lua 5.4 (navigateur) / LuaJIT 5.1 (Tarantool) : documenté ; le code
  MoonScript produit est compatible avec les deux dans les cas courants
  (`unpack` → `table.unpack` fourni en alias).
- Coût : le wasm wasmoon (quelques centaines de Ko) n'est chargé que par les
  widgets Lua/MoonScript.

## 8. Ordre de réalisation (une étape = un worktree, tests + navigateur)

1. **Accès** (§6, L4) : filtrage des messages selon `access`, migration
   `full` des plugins locaux, tests de refus. Priorité : c'est un trou de
   sécurité existant.
2. **Fenêtre « ＋ Widget »** (§3 bis) : liste des widgets personnalisés et
   paramètres clé/valeur (petite étape, utile tout de suite).
3. **Manifest + mappage** (§3), formulaire de paramètres tiré du manifest dans
   la fenêtre, et API `onRecords` / `onRecord` / `setCursor`.
4. **Chargement à la demande** des compilateurs (§7, L6).
5. **Portées + export des seules définitions référencées + conflits** (§5).
6. **Détacher** (§4).
7. **Lua / MoonScript via wasmoon** (§7, L7).

Chaque étape : tests backend (`tests/`), tests JS (`tests/js/`), une spec
Playwright, doc FR/EN (`doc/*/`), `make doc-check`, `make sdl-check`.

## 9. Hors périmètre

URL externe comme source de widget (à la Grist) : possible plus tard dans le
même cadre (`source: url` dans la définition, mêmes règles d'`access`).
