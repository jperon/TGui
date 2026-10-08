# Application « Bibliothèque » — plan d'implémentation

> **Pour les exécutants :** une tâche à la fois, dans son propre worktree git, commits
> intermédiaires obligatoires, vérification par exécution réelle (compilation + tests),
> jamais par relecture. Les cases `- [ ]` suivent l'avancement.

**Objectif :** livrer le paquet `apps/bibliotheque/bibliotheque.tdbapp.yaml` (structure +
données fictives déterministes) et son outillage, installable par `applyAppUpdate`.

**Architecture :** la structure est rédigée en YAML compact (`backend/apps/bibliotheque/`).
Un constructeur (`backend/tools/app_builder.moon`) l'étend en items de paquet ; des
générateurs MoonScript à graine fixe produisent le seed ; un assembleur écrit le paquet
(YAML déterministe, clés triées). Un test installe le paquet dans l'instance de test.

**Stack :** MoonScript (Tarantool 3), YAML, micro-framework `tests/runner.moon`, Docker
(le générateur tourne dans le conteneur : Tarantool n'est pas sur l'hôte).

**Spec :** `docs/superpowers/specs/2026-10-08-bibliotheque-design.md`.

## Amendements au spec (décidés à la rédaction du plan)

1. **Risque 2 confirmé par mesure** (2026-10-08, instance de test) : seed `id` 1 et 2
   installé, puis `insertRecord` → l'enregistrement reçoit `id = 1` (doublon). D'où la
   tâche 1 (correctif de TGui).
2. `Annee.en_cours` est un **champ stocké** (Boolean, valeur du seed), pas une formule
   dépendant de la date du jour : sinon les tests deviendraient faux l'an prochain.
3. Retirés car dépendant de la date du jour ou de l'ordre des années, sans utilité pour
   les emprunts : `Personnes.age`, `Annee.precedente`, `Annee.anciennete`.
   `ClassesEleves.redoublement` devient un Boolean stocké (valeur du seed).
4. `Prefectures.nom` (String) remplace `T_Prefecture_Intitule`, table absente du fichier.
5. Volume « standard » réel : environ 760 lignes (le spec disait ~300).
6. Dates : chaînes ISO `YYYY-MM-DD` (le type `Datetime` accepte chaîne ou nombre,
   mesuré le même jour, sans validation). Une valeur absente est **omise** de la ligne,
   jamais `""`.

## Contraintes globales

- Ne jamais éditer `.lua`/`.js` : modifier le `.moon`/`.coffee` puis `make build`
  (ou `moonc <fichier>.moon`). Les artefacts compilés sont commités avec leur source.
- MoonScript : pas de `local`, pas de `end`, pas de `then`, appels de méthode par `\`,
  tableaux par `{}` (`[]` seulement pour les compréhensions), 4 niveaux d'indentation
  maximum (créer une fonction auxiliaire au-delà). Pas de classes.
- Commits en anglais (`feat:`, `fix:`, `test:`, `refactor:`, `docs:`), source +
  artefact ensemble, `git add` de fichiers nommés (jamais `-A`).
- Tests : `make test` (dans l'instance de test, `tests/test_*.moon` découverts
  automatiquement) ; l'instance de test se relance par `make test-down; make test-up`.
- Format d'un item de paquet (vérifié sur `exportApp`) :
  `{type, key, content}` ; clés `space:<N>`, `field:<N>.<champ>`, `relation:<N>.<champ>`,
  `seed:<N>|<valeur de clé>` avec `key_part` (`core/app_package.moon:382`) appliqué à
  chaque composant. Contenu d'un champ : `{fieldType, notNull, description, formula,
  triggerFields, language}`. Relation : `{fromSpace, fromField, toSpace, toField,
  cardinality}`. Seed : `{space, key, data}`, `seed_keys[<espace>] = <champ de clé>`.
- Clé étrangère = champ `Int` + item `relation` (`toField: id`) ; la valeur est le champ
  `id` (Sequence) de la ligne cible, pas l'UUID.
- Une formule est le corps de `(self, space) -> <formule>` ; `@x` = champ ou
  relation suivie ; `space('Nom')` renvoie toutes les lignes brutes (FK = entiers, champs
  calculés absents). Formule multi-ligne : le constructeur préfixe `\n` et indente de 2
  espaces. Valeur vide d'un champ lu par `@x` : `nil`.
- Aucune colonne ne contient de liste d'identifiants (principe du spec §2).

## Revue — cas qui ne sont dans aucune tâche « nominale »

Chacun a son test dans la tâche indiquée :

1. Insertion utilisateur après installation d'un seed : `id` jamais réutilisé (T1).
2. Genre racine sans parent : `niveau = 1`, `chemin` = son nom (T5).
3. Livre sans exemplaire / auteur sans livre : `n_exemplaires = 0`, `n_ouvrages = 0`,
   pas `nil` (T5).
4. Personne sans classe courante : `classe_actuelle` vide, `emprunts_en_cours = 0` (T4).
5. Textes accentués ou avec apostrophe/deux-points (`L'île`, `Éloïse`, `a: b`) :
   aller-retour de l'émetteur YAML sans perte (T2).
6. Emprunt rendu vs non rendu : `Exemplaires.emprunteur` vide / égal à l'emprunteur (T5).

---

## Vagues d'exécution (parallélisme)

Chaque tâche touche des fichiers disjoints ; les tâches d'une même vague se lancent en
parallèle, chacune dans son worktree, après vérification des ressources
(`~/.claude/tools/opencode-acp/can-launch.sh 700`, au plus le nombre de places annoncé),
sous surveillance de `watch-agents.sh`.

| Vague | Tâches | Prérequis |
|---|---|---|
| 1 | T1 correctif séquences · T2 constructeur + RNG | — |
| 2 | T3 structure école · T4 structure bibliothèque · T5 structure coordonnées · T6 seed école · T7 seed bibliothèque · T8 seed coordonnées | T2 fusionnée |
| 3 | T9 assemblage + test d'intégration + Makefile + doc | vagues 1 et 2 fusionnées |

Numérotation : T3 = école, T4 = bibliothèque, T5 = coordonnées (structures) ;
T6 = seed école, T7 = seed bibliothèque, T8 = seed coordonnées. (Les « cas de revue » ci-dessus
renvoient à ces numéros : cas 2, 3, 6 → T4 ; cas 4 → T3.)

---

## T1 — Les seeds font avancer les séquences (correctif TGui)

**Fichiers :** modifier `backend/core/app_apply.moon` (+ `.lua`) ;
créer `tests/test_app_seed_sequences.moon` (+ `.lua`).

**Constat :** `_seed_create`/`_seed_update` (`app_apply.moon:709-729`) insèrent la ligne
avec les `id` fournis sans avancer `_tdb_seq_<field_id>`.

- [ ] **Étape 1 — test qui échoue** `tests/test_app_seed_sequences.moon` :

```moonscript
-- tests/test_app_seed_sequences.moon
-- Un seed qui porte des `id` explicites doit faire avancer le compteur de la
-- séquence : une insertion utilisateur ultérieure ne réutilise jamais un id du seed.
R = require 'tests.runner'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
auth = require 'core.auth'
data_r = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999
SP = "seq_seed_#{SUFFIX}"
APP_ID = "org.test.seqseed_#{SUFFIX}"
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

clean_app_rows = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

field_item = (name, ftype, not_null) ->
  { type: 'field', key: "field:#{SP}.#{name}", content: {
      fieldType: ftype, notNull: not_null or false, description: '',
      formula: '', triggerFields: {}, language: 'lua' } }

seed_item = (id, nom) ->
  { type: 'seed', key: "seed:#{SP}|#{id}", content: {
      space: SP, key: tostring(id), data: { id: id, nom: nom } } }

PKG = {
  app: { id: APP_ID, version: '1.0.0' }
  items: {
    { type: 'space', key: "space:#{SP}", content: { description: '' } }
    field_item 'id', 'Sequence', true
    field_item 'nom', 'String'
    seed_item 1, 'a'
    seed_item 2, 'b'
    seed_item 7, 'g'
  }
  seed_keys: { [SP]: 'id' }
}

R.describe "app_apply — seeds advance sequences", ->

  R.it "installs the package", ->
    report = apply.apply_update PKG, {}, {}
    R.eq #(report.errors or {}), 0, 'errors'

  R.it "a user insert after the seed gets an id above every seed id", ->
    sp = spaces.get_space_by_name SP
    r = data_r.Mutation.insertRecord {}, { spaceId: sp.id, data: { nom: 'c' } }, CTX
    id = require('json').decode(r.data).id
    R.eq id, 8, 'id attribué'

  R.it "cleans up", ->
    clean_app_rows APP_ID
    sp = spaces.get_space_by_name SP
    spaces.delete_user_space sp.id if sp
    R.is_nil spaces.get_space_by_name SP
```

- [ ] **Étape 2 — le constater rouge :** `moonc tests/test_app_seed_sequences.moon && make test 2>&1 | grep -A3 "advance sequences"`.
  Attendu : `id attribué` en échec (obtenu 1).
- [ ] **Étape 3 — commit du test seul :** `test: seed rows must advance sequence counters`.
- [ ] **Étape 4 — correctif** dans `backend/core/app_apply.moon`. Ajouter avant
  `_do_seeds` (ligne ~741) :

```moonscript
-- Les lignes seed portent des `id` explicites : faire passer chaque séquence de
-- l'espace au-dessus du plus grand id stocké. `next!` consomme une valeur (écart
-- inoffensif, exécuté seulement pour les espaces dont un seed vient d'être écrit).
_bump_sequences = (space_name) ->
  meta = spaces_mod.get_space_by_name space_name
  data_sp = box.space["data_#{space_name}"]
  return unless meta and data_sp
  for f in *spaces_mod.list_fields meta.id
    continue unless f.fieldType == 'Sequence'
    seq = box.sequence["_tdb_seq_#{f.id}"]
    continue unless seq
    max_val = 0
    for t in *data_sp\select {}
      v = _decode(t[2])[f.name]
      max_val = v if type(v) == 'number' and v > max_val
    n = seq\next!
    seq\set max_val if n <= max_val
```

  Dans `_seed_create` et `_seed_update`, après l'insertion/remplacement, ajouter
  `ctx.seed_spaces or= {}` puis `ctx.seed_spaces[c.space] = true`. À la fin de
  `_do_seeds` (après sa dernière boucle) :

```moonscript
  for space_name, _ in pairs (ctx.seed_spaces or {})
    _bump_sequences space_name
```

- [ ] **Étape 5 — vert :** `moonc backend/core/app_apply.moon && make test` : tout passe,
  dont `advance sequences`.
- [ ] **Étape 6 — commit :** `fix: advance sequence counters after seeding explicit ids`
  (`app_apply.moon`, `app_apply.lua`, test `.moon` + `.lua`).

---

## T2 — Constructeur de paquet, émetteur YAML déterministe, RNG

**Fichiers :** créer `backend/tools/seed_rng.moon`, `backend/tools/app_builder.moon`
(+ `.lua`), `tests/test_app_builder.moon` (+ `.lua`).

**Interfaces produites :**
- `seed_rng.new(seed) -> rng` avec `rng.int(lo, hi)`, `rng.pick(list)`,
  `rng.chance(p)` (p entre 0 et 1), `rng.shuffle(list) -> list`. Déterministe.
- `app_builder.key_part(s)` — identique à `core.app_package.key_part`.
- `app_builder.expand(structure) -> {app, items, seed_keys}` où
  `structure = { app = {id, name, version, description}, spaces = { <espace>... } }` et
  chaque espace = `{ name, description, fields = { {name, type, notNull, description,
  formula, language, ref = 'Espace.champ'} } }`. Le champ `id` (Sequence, notNull) est
  ajouté en tête de chaque espace. `ref` produit un item `relation` (cardinalité `one`).
  Ordre des items : tous les `space`, puis tous les `field`, puis tous les `relation`.
  `seed_keys[<espace>] = 'id'` pour chaque espace.
- `app_builder.add_seed(pkg, space_name, rows)` — ajoute un item `seed` par ligne
  (clé = `tostring(row.id)`).
- `app_builder.emit(pkg) -> string` — YAML bloc, clés triées, sans `null`.
- `app_builder.load_structure(dir) -> structure` — lit `dir/app.yaml` (`app:`) et
  concatène la liste `spaces:` de chaque `dir/structure/*.yaml`, triés par nom de fichier.

- [ ] **Étape 1 — tests** `tests/test_app_builder.moon` (écrire d'abord ; ils échouent
  tant que les modules n'existent pas) :

```moonscript
R = require 'tests.runner'
yaml = require 'yaml'
B = require 'tools.app_builder'
RNG = require 'tools.seed_rng'
pkg_mod = require 'core.app_package'

R.describe "seed_rng", ->
  R.it "is deterministic for a given seed", ->
    a, b = RNG.new(42), RNG.new(42)
    for _ = 1, 20
      R.eq a.int(1, 1000), b.int(1, 1000)
  R.it "int stays in bounds", ->
    r = RNG.new(7)
    for _ = 1, 500
      v = r.int 3, 9
      R.ok v >= 3 and v <= 9
  R.it "differs between seeds", ->
    R.ne RNG.new(1).int(1, 1000000), RNG.new(2).int(1, 1000000)

R.describe "app_builder.key_part", ->
  R.it "matches core.app_package.key_part", ->
    for s in *{ 'Livres', 'a.b', 'x|y', 'k:v', '100%' }
      R.eq B.key_part(s), pkg_mod.key_part(s)

STRUCT = {
  app: { id: 'org.test.mini', name: 'Mini', version: '1.0.0', description: 'd' }
  spaces: {
    { name: 'Auteurs', description: 'auteurs', fields: {
        { name: 'nom', type: 'String', notNull: true } } }
    { name: 'Livres', description: 'livres', fields: {
        { name: 'titre', type: 'String' }
        { name: 'auteur', type: 'Int', ref: 'Auteurs.id' }
        { name: 'n', type: 'Int', formula: "1 + 1" }
        { name: 'multi', type: 'Int', formula: "a = 1\na + 1\n" } } }
  }
}

R.describe "app_builder.expand", ->
  pkg = B.expand STRUCT
  by_key = {}
  by_key[it.key] = it for it in *pkg.items

  R.it "emits space, field and relation items, id first", ->
    R.ok by_key['space:Auteurs']
    R.eq by_key['field:Auteurs.id'].content.fieldType, 'Sequence'
    R.eq by_key['field:Livres.titre'].content.fieldType, 'String'
    rel = by_key['relation:Livres.auteur']
    R.eq rel.content.toSpace, 'Auteurs'
    R.eq rel.content.toField, 'id'
    R.eq rel.content.cardinality, 'one'
  R.it "orders spaces, then fields, then relations", ->
    last = { space: 0, field: 0, relation: 0 }
    seen_field, seen_rel = false, false
    for it in *pkg.items
      seen_field = true if it.type == 'field'
      seen_rel = true if it.type == 'relation'
      R.ok not (it.type == 'space' and seen_field)
      R.ok not (it.type == 'field' and seen_rel)
  R.it "formula: single line kept, multi line prefixed by newline and indented", ->
    R.eq by_key['field:Livres.n'].content.formula, '1 + 1'
    R.eq by_key['field:Livres.n'].content.language, 'moonscript'
    R.eq by_key['field:Livres.multi'].content.formula, "\n  a = 1\n  a + 1"
  R.it "seed_keys point to id", ->
    R.eq pkg.seed_keys.Livres, 'id'

R.describe "app_builder.emit", ->
  R.it "round-trips accented and punctuated text through yaml.decode", ->
    pkg = B.expand STRUCT
    B.add_seed pkg, 'Auteurs', {
      { id: 1, nom: "L'île: Éloïse" }
      { id: 2, nom: "a: b # c" }
    }
    out = B.emit pkg
    back = yaml.decode out
    seeds = [it for it in *back.items when it.type == 'seed']
    R.eq #seeds, 2
    R.eq seeds[1].content.data.nom, "L'île: Éloïse"
    R.eq seeds[2].content.data.nom, "a: b # c"
  R.it "is byte-identical on two emissions", ->
    pkg = B.expand STRUCT
    R.eq B.emit(pkg), B.emit(B.expand(STRUCT))
  R.it "keys are sorted", ->
    out = B.emit B.expand STRUCT
    a = out\find 'description', 1, true
    f = out\find 'items', 1, true
    R.ok a and f and a < f
```

- [ ] **Étape 2 — RNG** `backend/tools/seed_rng.moon` (Park–Miller : le produit reste
  sous 2^53, donc exact en double) :

```moonscript
-- tools/seed_rng.moon — générateur pseudo-aléatoire déterministe (Park–Miller).
new = (seed) ->
  state = seed % 2147483647
  state = 1 if state <= 0
  step = ->
    state = (state * 48271) % 2147483647
    state
  rng = {}
  rng.int = (lo, hi) -> lo + step! % (hi - lo + 1)
  rng.pick = (list) -> list[rng.int 1, #list]
  rng.chance = (p) -> (step! % 1000) < p * 1000
  rng.shuffle = (list) ->
    out = [v for v in *list]
    for i = #out, 2, -1
      j = rng.int 1, i
      out[i], out[j] = out[j], out[i]
    out
  rng

{ :new }
```

- [ ] **Étape 3 — constructeur et émetteur** `backend/tools/app_builder.moon` :

```moonscript
-- tools/app_builder.moon — structure YAML compacte → paquet .tdbapp.yaml.
-- N'utilise aucun module qui exige box (exécutable par `tarantool -e` hors serveur).
json = require 'json'
yaml = require 'yaml'
fio  = require 'fio'

-- Copie de core.app_package.key_part (testé identique) : ce module ne doit pas
-- charger core.app_package, qui dépend de box.
key_part = (s) ->
  s = "#{s}"
  s = s\gsub '%%', '%%25'
  s = s\gsub '%.', '%%2E'
  s = s\gsub '%|', '%%7C'
  s = s\gsub ':', '%%3A'
  s

_formula = (f) ->
  return '' unless f and f != ''
  f = f\gsub '\n+$', ''
  return f unless f\find '\n', 1, true
  lines = [ '  ' .. l for l in f\gmatch '[^\n]*' ]
  "\n" .. table.concat lines, '\n'

_field_item = (space, f) ->
  language = f.language or (f.formula and 'moonscript' or 'lua')
  {
    type: 'field'
    key: "field:#{key_part space}.#{key_part f.name}"
    content: {
      fieldType: f.type, notNull: f.notNull == true
      description: f.description or '', formula: _formula f.formula
      triggerFields: {}, language: language
    }
  }

_relation_item = (space, f) ->
  to_space, to_field = f.ref\match '^([^.]+)%.(.+)$'
  {
    type: 'relation'
    key: "relation:#{key_part space}.#{key_part f.name}"
    content: {
      fromSpace: space, fromField: f.name, toSpace: to_space
      toField: to_field, cardinality: 'one'
    }
  }

_all_fields = (sp) ->
  fields = { { name: 'id', type: 'Sequence', notNull: true, description: 'Identifiant' } }
  table.insert fields, f for f in *(sp.fields or {})
  fields

expand = (structure) ->
  a = structure.app
  spaces, fields, rels, seed_keys = {}, {}, {}, {}
  for sp in *structure.spaces
    table.insert spaces, { type: 'space', key: "space:#{key_part sp.name}", content: { description: sp.description or '' } }
    seed_keys[sp.name] = 'id'
    for f in *_all_fields sp
      table.insert fields, _field_item sp.name, f
      table.insert rels, _relation_item sp.name, f if f.ref
  items = {}
  for group in *{ spaces, fields, rels }
    table.insert items, it for it in *group
  { app: { id: a.id, name: a.name, version: a.version, description: a.description or '' }, items: items, seed_keys: seed_keys }

add_seed = (pkg, space_name, rows) ->
  for row in *rows
    k = tostring row.id
    table.insert pkg.items, {
      type: 'seed', key: "seed:#{key_part space_name}|#{key_part k}"
      content: { space: space_name, key: k, data: row }
    }

-- ── Émetteur YAML (clés triées, scalaires JSON-quotés = YAML valide) ────────────
_scalar = (v) ->
  switch type v
    when 'string' then json.encode v
    when 'number', 'boolean' then tostring v
    else 'null'

_is_array = (t) -> #t > 0 or next(t) == nil

_key = (k) ->
  k = tostring k
  k\match('^[%w_]+$') and k or json.encode(k)

_lines = nil
_lines = (v, pad) ->
  out = {}
  if _is_array v
    for item in *v
      if type(item) == 'table' and next(item) != nil
        sub = _lines item, pad .. '  '
        sub[1] = pad .. '- ' .. sub[1]\sub(#pad + 3)
        table.insert out, l for l in *sub
      else
        table.insert out, pad .. '- ' .. (type(item) == 'table' and (_is_array(item) and '[]' or '{}') or _scalar item)
  else
    keys = [k for k, _ in pairs v]
    table.sort keys, (a, b) -> tostring(a) < tostring(b)
    for k in *keys
      val = v[k]
      if type(val) == 'table' and next(val) != nil
        table.insert out, pad .. _key(k) .. ':'
        table.insert out, l for l in *_lines val, pad .. '  '
      elseif type(val) == 'table'
        table.insert out, pad .. _key(k) .. ': ' .. (_is_array(val) and '[]' or '{}')
      else
        table.insert out, pad .. _key(k) .. ': ' .. _scalar val
  out

emit = (pkg) ->
  "---\n" .. table.concat(_lines(pkg, ''), '\n') .. '\n'

_read_yaml = (path) ->
  fh = fio.open path, { 'O_RDONLY' }
  error "cannot open #{path}" unless fh
  text = fh\read!
  fh\close!
  yaml.decode text

load_structure = (dir) ->
  structure = { app: (_read_yaml fio.pathjoin dir, 'app.yaml').app, spaces: {} }
  names = fio.glob fio.pathjoin dir, 'structure', '*.yaml'
  table.sort names
  for path in *names
    for sp in *(_read_yaml path).spaces
      table.insert structure.spaces, sp
  structure

{ :key_part, :expand, :add_seed, :emit, :load_structure }
```

  (Un `\n` dans une valeur est émis par `json.encode` en `\n` échappé : le texte
  multi-ligne des formules est donc sur une seule ligne YAML entre guillemets.)

- [ ] **Étape 4 — compiler et exécuter :** `moonc backend/tools/*.moon tests/test_app_builder.moon`
  puis `make test` : la suite `app_builder` / `seed_rng` passe. Corriger l'émetteur
  jusqu'au vert (le test d'aller-retour est le juge).
- [ ] **Étape 5 — commits :** `test: builder and rng` puis `feat: package builder, deterministic yaml emitter and seed rng`.

---

## Format des fichiers de structure (T3, T4, T5)

`backend/apps/bibliotheque/app.yaml` (créé en **T3**) :

```yaml
app:
  id: org.tgui.bibliotheque
  name: Bibliothèque
  version: 1.0.0
  description: Bibliothèque scolaire (démonstration et base de tests de TGui).
```

Chaque `structure/*.yaml` : `spaces:` = liste d'espaces `{name, description, fields: [...]}`,
champ = `{name, type, notNull?, description?, ref?, formula?}` (formule en bloc `|`).
Types utilisés : `String`, `Int`, `Boolean`, `Datetime`. Une formule est évaluée à la
lecture seulement si la valeur stockée est vide ; ne jamais stocker un champ calculé
dans le seed.

Chaque tâche de structure s'accompagne d'un test dans son propre fichier
`tests/test_app_structure_<nom>.moon` qui :
1. charge `tools.app_builder.load_structure('/app/backend/apps/bibliotheque')` (le répertoire
   doit exister — voir T3 pour `app.yaml`) ;
2. n'installe **que ses propres espaces** (filtrer `structure.spaces` par nom) sous un
   nom d'application de test unique, vérifie l'absence d'erreurs, insère quelques lignes
   via `data_r.Mutation.insertRecord`, lit les formules via la requête `records` du
   résolveur (`data_r.Query.records`) et nettoie (`spaces.delete_user_space`, lignes
   `_tdb_apps`/`_tdb_app_items`). Les relations vers des espaces absents de la sélection
   sont retirées par le test avant installation (`ref = nil`).

---

## T3 — Structure « école »

**Fichiers :** créer `backend/apps/bibliotheque/app.yaml`,
`backend/apps/bibliotheque/structure/ecole.yaml`, `tests/test_app_structure_ecole.moon`
(+ `.lua`). **Prérequis :** T2 fusionnée (`tools.app_builder`).

Contenu de `ecole.yaml` (espaces : `Titres`, `Personnes`, `Sections`, `Annee`, `Niveaux`,
`Prefectures`, `Classes`, `ClassesEleves`) :

```yaml
spaces:
- name: Titres
  description: Titres de civilité
  fields:
  - {name: titre, type: String, notNull: true}
  - {name: abrege, type: String}
  - {name: femme, type: Boolean}
- name: Sections
  description: Sections de l'école
  fields:
  - {name: section, type: String, notNull: true}
  - {name: abregee, type: String}
- name: Annee
  description: Années scolaires
  fields:
  - {name: debut, type: Datetime, notNull: true}
  - {name: fin, type: Datetime, notNull: true}
  - {name: en_cours, type: Boolean, description: Année courante (stockée, voir plan)}
  - {name: section, type: Int, ref: Sections.id}
  - name: n
    type: Int
    formula: "tonumber(@debut\\sub(1, 4))"
  - name: annee
    type: String
    formula: "@n .. ' - ' .. (@n + 1)"
- name: Niveaux
  description: Niveaux scolaires
  fields:
  - {name: niveau, type: Int, notNull: true}
  - {name: classe, type: String}
  - {name: abrege, type: String, notNull: true}
  - {name: generique, type: String}
  - {name: superieur, type: Int, ref: Niveaux.id}
  - name: descriptif
    type: String
    formula: "(\"%02d − %s\")\\format @niveau, @abrege"
- name: Personnes
  description: Élèves, enseignants et familles
  fields:
  - {name: nom, type: String, notNull: true}
  - {name: particule, type: String}
  - {name: prenom, type: String}
  - {name: titre, type: Int, ref: Titres.id}
  - {name: date_de_naissance, type: Datetime}
  - {name: lieu_de_naissance, type: String}
  - {name: precision, type: String}
  - {name: famille, type: Int, ref: Personnes.id}
  - {name: externe, type: Boolean}
  - name: descriptif
    type: String
    formula: "@nom\\upper! .. (@particule and (' (' .. @particule .. ')') or '') .. ' ' .. (@prenom or '') .. (@precision and (' ' .. @precision) or '')"
  - name: classe_actuelle
    type: Int
    description: Classe de l'année en cours (sans date de départ)
    formula: |
      [ce.classe for ce in *space('ClassesEleves') when ce.eleve == @id and (ce.depart or '') == '' and #[c for c in *space('Classes') when c.id == ce.classe and #[a for a in *space('Annee') when a.id == c.annee and a.en_cours] > 0] > 0][1]
  - name: emprunts_en_cours
    type: Int
    formula: "#[e for e in *space('Emprunts') when e.personne == @id and (e.retour or '') == '']"
- name: Prefectures
  description: Groupes de classes par année
  fields:
  - {name: nom, type: String, notNull: true}
  - {name: annee, type: Int, ref: Annee.id}
  - {name: prefet, type: Int, ref: Personnes.id}
  - {name: niveau_min, type: Int, ref: Niveaux.id}
  - {name: niveau_max, type: Int, ref: Niveaux.id}
  - name: descriptif
    type: String
    formula: "@nom .. ' ' .. (@annee and @annee.n or '?')"
  - name: effectif
    type: Int
    formula: "#[ce for ce in *space('ClassesEleves') when (ce.depart or '') == '' and #[c for c in *space('Classes') when c.id == ce.classe and c.prefecture == @id] > 0]"
- name: Classes
  description: Classes d'une année scolaire
  fields:
  - {name: niveau, type: Int, ref: Niveaux.id}
  - {name: annee, type: Int, ref: Annee.id}
  - {name: prefecture, type: Int, ref: Prefectures.id}
  - {name: professeur_principal, type: Int, ref: Personnes.id}
  - {name: precision, type: String}
  - name: descriptif
    type: String
    formula: "@niveau.abrege .. (@precision or '')"
  - name: descriptif_complet
    type: String
    formula: "@annee.n .. ' ' .. @descriptif"
  - name: effectif
    type: Int
    formula: "#[ce for ce in *space('ClassesEleves') when ce.classe == @id and (ce.depart or '') == '']"
  - name: naissance_theorique
    type: Int
    formula: "@annee.n - (@niveau.niveau + 2)"
- name: ClassesEleves
  description: Affectation des élèves aux classes (liaison N-N)
  fields:
  - {name: classe, type: Int, ref: Classes.id}
  - {name: eleve, type: Int, ref: Personnes.id}
  - {name: entree, type: Datetime}
  - {name: depart, type: Datetime}
  - {name: redoublement, type: Boolean}
  - name: annee
    type: Int
    formula: "@classe and @classe.annee and @classe.annee.id"
  - name: annee_en_cours
    type: Boolean
    formula: "not not (@classe and @classe.annee and @classe.annee.en_cours and not @depart)"
```

- [ ] **Étape 1 — test** `tests/test_app_structure_ecole.moon` : installe les 8 espaces,
  insère : 1 `Sections`, 2 `Annee` (n°1 `en_cours` faux 2025-09-01→2026-06-30, n°2
  `en_cours` vrai 2026-09-01→2027-06-30), 1 `Niveaux` (niveau 1, abrege `CP`), 1
  `Classes` par année (niveau 1), 2 `Personnes` (Dupont/Jeanne avec particule `de`, et
  Martin/Luc), `ClassesEleves` : Jeanne dans la classe n°2 sans départ, Luc dans la
  classe n°1 avec `depart` renseigné. Vérifie : `Annee.annee` = `2026 - 2027`,
  `Niveaux.descriptif` = `01 − CP`, `Personnes.descriptif` de Jeanne = `DUPONT (de) Jeanne`,
  `Jeanne.classe_actuelle` = id de la classe n°2, `Luc.classe_actuelle` vide (cas 4 de la
  revue), `Classes.effectif` de la classe n°2 = 1, `Classes.descriptif` = `CP`,
  `ClassesEleves.annee_en_cours` vrai pour Jeanne et faux pour Luc.
- [ ] **Étape 2 — rouge** (`make test`), **Étape 3** écrire `app.yaml` et `ecole.yaml`,
  **Étape 4 — vert.** Les formules ci-dessus sont la référence de sémantique ; si une
  forme MoonScript ne compile pas, la réécrire en conservant le résultat, et le dire
  dans le rapport.
- [ ] **Étape 5 — commits :** `test: school structure` puis `feat: school structure of the library app`.

---

## T4 — Structure « bibliothèque »

**Fichiers :** créer `backend/apps/bibliotheque/structure/bibliotheque.yaml`,
`tests/test_app_structure_bibliotheque.moon` (+ `.lua`). **Prérequis :** T2.

Espaces : `Genres`, `Auteurs`, `MotsCles`, `Livres`, `LivresMotsCles`, `Exemplaires`,
`Emprunts`. Les FK vers `Personnes` (`Emprunts.personne`) sont retirées par le test.

```yaml
spaces:
- name: Genres
  description: Genres littéraires (hiérarchie)
  fields:
  - {name: genre, type: String, notNull: true}
  - {name: parent, type: Int, ref: Genres.id}
  - name: niveau
    type: Int
    formula: |
      n = 1
      p = @parent
      while p
        n += 1
        p = p.parent
      n
  - name: chemin
    type: String
    formula: |
      parts = { @genre }
      p = @parent
      while p
        table.insert parts, 1, p.genre
        p = p.parent
      table.concat parts, ' › '
  - name: nombre_de_livres
    type: Int
    formula: "#[l for l in *space('Livres') when l.genre == @id]"
- name: Auteurs
  description: Auteurs
  fields:
  - {name: nom, type: String, notNull: true}
  - {name: particule, type: String}
  - {name: prenom, type: String}
  - {name: titre, type: String}
  - name: nom_complet
    type: String
    formula: |
      parts = {}
      table.insert parts, @prenom if @prenom
      table.insert parts, @particule if @particule
      table.insert parts, @nom
      table.concat parts, ' '
  - name: n_ouvrages
    type: Int
    formula: "#[l for l in *space('Livres') when l.auteur == @id]"
- name: MotsCles
  description: Mots-clés
  fields:
  - {name: mot, type: String, notNull: true}
  - name: occurrences
    type: Int
    formula: "#[x for x in *space('LivresMotsCles') when x.mot_cle == @id]"
- name: Livres
  description: Catalogue des livres
  fields:
  - {name: titre, type: String, notNull: true}
  - {name: auteur, type: Int, ref: Auteurs.id}
  - {name: genre, type: Int, ref: Genres.id}
  - {name: note, type: Int}
  - {name: age_min, type: Int}
  - {name: age_max, type: Int}
  - {name: commentaire, type: String}
  - name: descriptif
    type: String
    formula: "@titre .. ' (' .. (@auteur and @auteur.nom_complet or '?') .. ')'"
  - name: n_exemplaires
    type: Int
    formula: "#[e for e in *space('Exemplaires') when e.livre == @id and (e.suppression or '') == '']"
  - name: doublon
    type: Boolean
    formula: "#[l for l in *space('Livres') when l.titre == @titre and l.auteur == (@auteur and @auteur.id) and l.id ~= @id] > 0"
- name: LivresMotsCles
  description: Liaison N-N livres / mots-clés
  fields:
  - {name: livre, type: Int, ref: Livres.id}
  - {name: mot_cle, type: Int, ref: MotsCles.id}
- name: Exemplaires
  description: Exemplaires physiques
  fields:
  - {name: livre, type: Int, ref: Livres.id}
  - {name: cote, type: String}
  - {name: acquisition, type: Datetime}
  - {name: suppression, type: Datetime}
  - name: descriptif
    type: String
    formula: "(@livre and @livre.descriptif or '?') .. (@cote and (' − ' .. @cote) or '')"
  - name: emprunteur
    type: String
    description: Emprunteur du prêt non rendu (vide si disponible)
    formula: "([p.nom .. ' ' .. (p.prenom or '') for p in *space('Personnes') when p.id == ([e.personne for e in *space('Emprunts') when e.exemplaire == @id and (e.retour or '') == ''])[1]])[1]"
- name: Emprunts
  description: Emprunts
  fields:
  - {name: personne, type: Int, ref: Personnes.id}
  - {name: exemplaire, type: Int, ref: Exemplaires.id}
  - {name: emprunt, type: Datetime, notNull: true}
  - {name: retour, type: Datetime}
  - name: livre
    type: Int
    formula: "@exemplaire and @exemplaire.livre and @exemplaire.livre.id"
  - name: classe
    type: Int
    formula: "@personne and @personne.classe_actuelle"
  - name: annee
    type: Int
    formula: "([a.id for a in *space('Annee') when a.debut <= @emprunt and @emprunt <= a.fin])[1]"
  - name: annee_en_cours
    type: Boolean
    formula: "#[a for a in *space('Annee') when a.en_cours and a.debut <= @emprunt and @emprunt <= a.fin] > 0"
```

- [ ] **Étape 1 — test** (`test_app_structure_bibliotheque.moon`, sans les relations vers
  `Personnes`/`Annee`) : 3 genres (Fiction ← Roman ← Policier) ; vérifie
  `Policier.niveau = 3`, `Policier.chemin = "Fiction › Roman › Policier"`,
  `Fiction.niveau = 1` et `Fiction.chemin = "Fiction"` (cas 2) ; 1 auteur `La Fontaine`/
  `Jean`/particule `de` → `nom_complet = "Jean de La Fontaine"` ; un auteur sans livre
  → `n_ouvrages = 0` (cas 3) ; 1 livre → `n_exemplaires = 0` (cas 3), puis 2
  exemplaires (dont 1 avec `suppression`) → `n_exemplaires = 1` ; un second livre de
  même titre et auteur → `doublon` vrai pour les deux ; `Livres.descriptif` =
  `"<titre> (Jean de La Fontaine)"`. Emprunts (cas 6) : l'espace `Personnes` n'étant pas
  installé, le test crée un espace minimal `Personnes` (champs `nom`, `prenom`) pour
  l'occasion : exemplaire A prêté sans `retour` → `emprunteur` = `"Martin Luc"` ;
  exemplaire B prêté puis rendu → `emprunteur` vide.
- [ ] **Étapes 2-4 :** rouge, écrire `bibliotheque.yaml`, vert.
- [ ] **Étape 5 — commits :** `test: library core structure` puis `feat: library core structure`.

---

## T5 — Structure « coordonnées »

**Fichiers :** créer `backend/apps/bibliotheque/structure/coordonnees.yaml`,
`tests/test_app_structure_coordonnees.moon` (+ `.lua`). **Prérequis :** T2.

```yaml
spaces:
- name: TypesCoordonnees
  description: Types de coordonnées (tel, courriel, adresse)
  fields:
  - {name: type, type: String, notNull: true}
- name: Coordonnees
  description: Coordonnées (texte libre typé)
  fields:
  - {name: type_coordonnee, type: Int, ref: TypesCoordonnees.id}
  - {name: valeur, type: String, notNull: true}
- name: PersonnesCoordonnees
  description: Liaison N-N personnes / coordonnées
  fields:
  - {name: personne, type: Int, ref: Personnes.id}
  - {name: coordonnee, type: Int, ref: Coordonnees.id}
  - {name: libelle, type: String}
```

- [ ] **Étape 1 — test :** installe les trois espaces (+ espace minimal `Personnes` créé
  par le test), insère 3 types, 1 coordonnée, 2 personnes liées à cette même coordonnée
  (N-N) ; vérifie le nombre de liaisons et que `type_coordonnee` pointe un type existant ;
  `notNull` de `valeur` refusé si absent (`insertRecord` lève une erreur).
- [ ] **Étapes 2-4 :** rouge, écrire le YAML, vert.
- [ ] **Étape 5 — commits :** `test: contact structure` puis `feat: contact structure`.

---

## T6 — Données fictives : école

**Fichiers :** créer `backend/tools/bibliotheque_seed_ecole.moon` (+ `.lua`),
`tests/test_seed_ecole.moon` (+ `.lua`). **Prérequis :** T2 (`tools.seed_rng`).

**Interface produite :** `generate(rng, k) -> out` avec `k` = facteur d'échelle (entier ≥ 1).
`out.tables` = liste ordonnée `{ { space: 'Titres', rows: {...} }, ... }` dans l'ordre
`Titres, Sections, Annee, Niveaux, Personnes, Prefectures, Classes, ClassesEleves` ;
`out.eleves` = ids (`Personnes.id`) des élèves ; `out.adultes` = ids des adultes ;
`out.personnes` = tous les ids. Chaque ligne a un `id` entier explicite (1, 2, 3…),
les champs vides sont **omis**, les dates sont des chaînes `YYYY-MM-DD`, les FK sont des
`id` existants.

Volumes à `k = 1` (exacts) : Titres 4 (`M.`, `Mme`, `Frère`, `Sœur` ; `femme` vrai pour
`Mme` et `Sœur`), Sections 2, Annee 3 (2024-09-01→2025-06-30 ; 2025-09-01→2026-06-30 ;
2026-09-01→2027-06-30 avec `en_cours = true` pour la seule dernière), Niveaux 5
(`CP`, `CE1`, `CE2`, `CM1`, `CM2`, niveau 1 à 5, `superieur` = niveau suivant), Personnes
`72` (12 adultes : 5 professeurs principaux, 2 préfets, 5 parents, ids 1-12 ; puis
`60 k` élèves, 12 par niveau, `famille` = un parent tiré au hasard), Prefectures 3 (une
par année, `prefet` = un des 2 préfets), Classes 10 (années 2 et 3 : une par niveau ;
`prefecture` de l'année ; `professeur_principal` parmi les 5), ClassesEleves
`60 k + 48 k` : chaque élève dans la classe de son niveau en année 3 (sans `depart`, `entree`
2026-09-01), et chaque élève de niveau ≥ 2 dans la classe de niveau−1 en année 2
(`entree` 2025-09-01, `depart` 2026-06-30, `redoublement` faux).

- [ ] **Étape 1 — test** `tests/test_seed_ecole.moon` : (a) `generate(RNG.new(1001), 1)`
  deux fois donne la même table (comparer `require('json').encode`) ; (b) comptes exacts
  ci-dessus ; (c) intégrité : toute FK (`famille`, `titre`, `prefet`, `section`, `annee`,
  `niveau`, `prefecture`, `professeur_principal`, `classe`, `eleve`) désigne un `id` présent
  dans la table cible ; (d) chaque élève a exactement une ligne `ClassesEleves` sans
  `depart` ; (e) aucune valeur `""` ni `nil` explicite dans les lignes ; (f) `k = 2`
  double les élèves.
- [ ] **Étape 2 — rouge. Étape 3 — implémentation** : listes de prénoms/noms fictifs
  (au moins 16 de chaque) dans le module, tirés avec `rng.pick`, dates par chaînes fixes.
  Aucune donnée personnelle réelle. **Étape 4 — vert.**
- [ ] **Étape 5 — commits :** `test: school seed generator` puis `feat: school seed generator`.

---

## T7 — Données fictives : bibliothèque

**Fichiers :** créer `backend/tools/bibliotheque_seed_livres.moon` (+ `.lua`),
`tests/test_seed_livres.moon` (+ `.lua`). **Prérequis :** T2.

**Interface :** `generate(rng, k, ecole) -> out`, où `ecole = { eleves = {ids},
personnes = {ids} }` (le test fournit des ids factices 1…72 ; l'assembleur fournit ceux de T6).
`out.tables` dans l'ordre `Genres, Auteurs, MotsCles, Livres, LivresMotsCles, Exemplaires,
Emprunts`. Mêmes conventions que T6 (ids explicites, champs vides omis, dates ISO).

Volumes à `k = 1` : Genres 15 (arbre : 1 Fiction ; 2 Roman←1 ; 3 Policier←2 ; 4
Science-fiction←2 ; 5 Aventure←2 ; 6 Théâtre←1 ; 7 Poésie←1 ; 8 Documentaire ; 9
Histoire←8 ; 10 Sciences←8 ; 11 Biographie←8 ; 12 Bande dessinée ; 13 Jeunesse ; 14
Contes←13 ; 15 Albums←13), Auteurs `25 k`, MotsCles `40`, Livres `60 k` (un livre sur
quatre n'a **aucun exemplaire** ; au moins un auteur sans livre ; deux livres de même titre
et auteur pour exercer `doublon`), LivresMotsCles `2` par livre (couples distincts),
Exemplaires `100 k` (dont 5 avec `suppression`), Emprunts `120 k` : 30 non rendus (pas de
`retour`, `emprunt` entre 2026-09-10 et 2026-10-07, **un seul prêt non rendu par
exemplaire**, jamais sur un exemplaire supprimé) et le reste rendus (`emprunt` entre
2025-09-15 et 2026-06-15, `retour` 7 à 40 jours après). Emprunteurs = `ecole.eleves`.
Dates calculées avec `os.time`/`os.date` (arithmétique de jours).

- [ ] **Étape 1 — test** : déterminisme (deux appels identiques), comptes, intégrité des
  FK, au plus un prêt ouvert par exemplaire, aucun prêt ouvert sur exemplaire supprimé,
  au moins un livre sans exemplaire, au moins un auteur sans livre, présence du doublon,
  aucun `""`.
- [ ] **Étapes 2-4 :** rouge, implémentation (auteurs : prénoms et noms fictifs, dont
  quelques particules ; titres composés de fragments fictifs), vert.
- [ ] **Étape 5 — commits :** `test: library seed generator` puis `feat: library seed generator`.

---

## T8 — Données fictives : coordonnées

**Fichiers :** créer `backend/tools/bibliotheque_seed_coordonnees.moon` (+ `.lua`),
`tests/test_seed_coordonnees.moon` (+ `.lua`). **Prérequis :** T2.

**Interface :** `generate(rng, k, ecole) -> out`, `ecole.personnes` = ids (factices dans le
test). Tables dans l'ordre `TypesCoordonnees, Coordonnees, PersonnesCoordonnees`.
Volumes à `k = 1` : TypesCoordonnees 3 (`tel`, `courriel`, `adresse`) ; Coordonnees
`30 k` (réparties sur les 3 types, valeurs fictives : numéros `06 00 00 xx xx`, courriels
`@exemple.invalid`, adresses inventées) ; PersonnesCoordonnees `50 k` (au moins une
coordonnée partagée par 2 personnes ou plus ; couples distincts ; `libelle` parmi
`domicile`, `parents`, `travail`).

- [ ] **Étape 1 — test :** déterminisme, comptes, intégrité des FK, au moins une
  coordonnée partagée, aucune adresse réelle (domaines `.invalid` pour les courriels).
- [ ] **Étapes 2-5 :** rouge, implémentation, vert, commits `test:` puis `feat:`.

---

## T9 — Assemblage, paquet commité, test d'intégration, Makefile, documentation

**Fichiers :** créer `backend/tools/bibliotheque_app.moon` (+ `.lua`),
`tests/test_app_bibliotheque.moon` (+ `.lua`), `apps/bibliotheque/bibliotheque.tdbapp.yaml`,
`apps/bibliotheque/README.md` ; modifier `Makefile` (cibles `app-bibliotheque`,
`app-bibliotheque-check`, ajout à `.PHONY`). **Prérequis :** T1 à T8 fusionnées.

**Interface :** `bibliotheque_app.build(opts) -> pkg` (`opts.scale` entier, défaut 1 ;
répertoire de structure `opts.dir`, défaut `/app/backend/apps/bibliotheque`) :

```moonscript
-- tools/bibliotheque_app.moon
B     = require 'tools.app_builder'
RNG   = require 'tools.seed_rng'
ecole = require 'tools.bibliotheque_seed_ecole'
livres = require 'tools.bibliotheque_seed_livres'
coord = require 'tools.bibliotheque_seed_coordonnees'

DIR = '/app/backend/apps/bibliotheque'

_add = (pkg, out) ->
  B.add_seed pkg, t.space, t.rows for t in *out.tables

build = (opts) ->
  opts or= {}
  k = opts.scale or 1
  pkg = B.expand B.load_structure opts.dir or DIR
  e = ecole.generate RNG.new(1001), k
  _add pkg, e
  _add pkg, livres.generate RNG.new(2002), k, e
  _add pkg, coord.generate RNG.new(3003), k, e
  pkg

write = (path, opts) ->
  fio = require 'fio'
  fh = fio.open path, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, tonumber('644', 8)
  fh\write B.emit build opts
  fh\close!

{ :build, :write }
```

- [ ] **Étape 1 — Makefile** (calqué sur `sdl-gen`, `Makefile:225-227`) :

```make
app-bibliotheque: build
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) .
	docker run --rm -u $$(id -u):$$(id -g) -v ./:/app $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; require("tools.bibliotheque_app").write("/app/apps/bibliotheque/bibliotheque.tdbapp.yaml"); os.exit(0)'

app-bibliotheque-check: build
	@tmp=$$(mktemp); \
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . >/dev/null; \
	docker run --rm -v ./:/app $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; io.write(require("tools.app_builder").emit(require("tools.bibliotheque_app").build()))' > $$tmp; \
	diff -q $$tmp apps/bibliotheque/bibliotheque.tdbapp.yaml >/dev/null && echo "✅ paquet à jour" || { echo "❌ paquet périmé : make app-bibliotheque"; exit 1; }
```

  (Vérifier l'option `-u` : si l'utilisateur du conteneur ne peut pas écrire dans
  `./apps`, écrire sur stdout et rediriger comme `sdl-gen`.)

- [ ] **Étape 2 — test d'intégration** `tests/test_app_bibliotheque.moon` : construit le
  paquet avec `build()` (pas de lecture du fichier commité), l'installe par
  `apply.apply_update`, puis :
  1. **comptes exacts** par espace via `box.space["data_<Espace>"]:len()` :
     Titres 4, Sections 2, Annee 3, Niveaux 5, Personnes 72, Prefectures 3, Classes 10,
     ClassesEleves 108, Genres 15, Auteurs 25, MotsCles 40, Livres 60, LivresMotsCles 120,
     Exemplaires 100, Emprunts 120, TypesCoordonnees 3, Coordonnees 30,
     PersonnesCoordonnees 50 ;
  2. **intégrité** : pour chaque `relation` du paquet, chaque valeur non vide du champ
     source existe comme `id` dans l'espace cible ;
  3. **formules sur le seed** : `Classes.effectif` (classe d'année 3, niveau 1) = 12 ;
     la somme de `Personnes.emprunts_en_cours` sur tous les élèves = 30 ; pour chaque
     exemplaire avec prêt ouvert, `Exemplaires.emprunteur` non vide, et vide pour les
     autres ; `Genres.chemin` du genre 3 = `Fiction › Roman › Policier` ;
     `Auteurs.n_ouvrages` somme = 60 ; au moins un `Livres.doublon` vrai ;
  4. **idempotence** : `apply_update` du même paquet → `created`, `updated` vides ;
  5. **séquences** : `insertRecord` dans `Livres`, `Personnes` et `Emprunts` donne un `id`
     absent du seed ;
  6. **déterminisme** : `B.emit(build())` deux fois → chaînes égales ;
  7. nettoyage : suppression de tous les espaces installés et des lignes `_tdb_apps` /
     `_tdb_app_items` de `org.tgui.bibliotheque`.
- [ ] **Étape 3 — rouge → vert** ; corriger les générateurs ou structures défaillants en
  renvoyant le diagnostic à la tâche concernée (T3 à T8), sans contournement dans T9.
- [ ] **Étape 4 — générer et commiter le paquet :** `make app-bibliotheque`, vérifier
  `make app-bibliotheque-check`, et que `previewAppUpdate` du fichier généré, par
  GraphQL sur l'instance de test (`curl`), ne renvoie aucune erreur.
- [ ] **Étape 5 — `apps/bibliotheque/README.md`** : but, installation
  (`applyAppUpdate` / panneau Applications), régénération (`make app-bibliotheque`),
  structure (renvoi au spec), volumes et `--scale` (`build({scale: N})`), conventions
  (ids explicites, champs vides omis).
- [ ] **Étape 6 — `make test` complet vert, commits :** `test: library app integration`,
  `feat: library app package and make targets`, `docs: library app README`.
