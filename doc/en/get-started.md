# Quick Start — TGui

**TGui** is inspired by [Grist](https://www.getgrist.com) — for any serious or production use, users are encouraged to consider Grist as a priority.

**TGui** is a graphical interface for [Tarantool](https://www.tarantool.io/) that lets you create and manage data spaces (tables), link them, define computed columns or triggers, and compose declarative custom views (YAML).

This guide walks you step by step from zero to a fully functional **school library management** application: book catalog, physical copies, borrowers, and loans.

---

## Prerequisites

- [Docker](https://www.docker.com/) (or Tarantool 3.x installed locally)
- `make`, `moonc` (MoonScript compiler), `coffee` (CoffeeScript) — only needed to modify sources

---

## Launch

```bash
git clone <repo>
cd tgui
docker compose up
```

The interface is available at **http://localhost:8080**.

---

## Login

![Login screen](../img/login-screen.png)

---

## Overview of the interface

![Main interface](../img/main.png)

The interface is divided into two areas:

| Area | Role |
|------|------|
| **Sidebar** (left) | Navigation between Views, Data and Administration |
| **Content** (right) | Data grid, view editor or administration panel |

---

## Create the spaces (tables)

The library is built on 12 tables. Create them in the following order to make relations easier to define: first the reference tables, then the main tables, then the join tables, and finally the transaction table.

### 1 — Reference tables

These tables have no dependency on other tables.

1. In the **Data** section of the sidebar, click **+**.
2. Enter the space name and confirm.
3. Repeat for each table.

| Space | Role |
|--------|------|
| `genres` | Literary genres (novel, comic, non-fiction, …) |
| `auteurs` | Book authors |
| `classes` | School classes |
| `motscles` | Thematic keywords |
| `etiquettes` | Classification labels (prize, favorites, …) |

![Data space with grid](../img/space-data.png)

### 2 — Main tables

| Space | Role |
|--------|------|
| `livres` | Catalog of titles (bibliographic references) |
| `personnes` | Students and staff who can borrow |
| `exemplaires` | Physical copies of each title |
| `coordonnees` | Contact details for people |

### 3 — Many-to-many join tables

| Space | Role |
|--------|------|
| `livres_motscles` | Book ↔ keyword association |
| `livres_etiquettes` | Book ↔ label association |

### 4 — Transaction table

| Space | Role |
|--------|------|
| `emprunts` | Records of loans (copy + borrower + dates) |

---

## Add and manage fields

Click **[#] Fields** in the toolbar to open the side panel.

![Fields panel](../img/fields-panel.png)

### Create a simple field

1. Enter the **name** of the field.
2. Choose the **type**: `String`, `Int`, `Float`, `Boolean`, `UUID`, `Sequence`, `Any`, `Map`, `Array`, or `Relation`.
3. Check **Required** if the value cannot be null.
4. Click **Add**.

### Example: fields of the `auteurs` space

| Field | Type | Required |
|-------|------|--------|
| `id` | Sequence | — |
| `particule` | String | no |
| `nom` | String | **yes** |
| `prenom` | String | no |

### Example: fields of the `livres` space

| Field | Type | Required | Note |
|-------|------|--------|----------|
| `id` | Sequence | — | |
| `titre` | String | **yes** | |
| `auteur_id` | Relation | no | → `auteurs` |
| `genre_id` | Relation | no | → `genres` |
| `cote` | String | no | Shelf mark |
| `isbn` | String | no | Nullable |
| `annee` | Int | no | Publication year, nullable |

### Computed column (λ)

Select **Computed column** and enter a MoonScript or Lua expression.
The formula is the body of a function `(self, space) -> <expression>`; in MoonScript `@field` accesses `self.field`. The value is recomputed on each read and is not stored.

**Example: `nom_complet` in `auteurs`** — combine first name, particle and last name while handling nulls:

```moonscript
parts = {}
table.insert(parts, @prenom) if @prenom and @prenom != ""
table.insert(parts, @particule) if @particule and @particule != ""
table.insert(parts, @nom) if @nom and @nom != ""
table.concat(parts, " ")
```

The `space` parameter gives access to records of another space (full scan):

```moonscript
-- Count available copies for this book
n = 0
for e in *space("exemplaires")
  n += 1 if e.livre_id == @id and e.disponible
n
```

### Trigger formula ((trigger))

Select **Trigger formula** and optionally list the trigger fields.
The formula is executed and the result **stored** on each creation or modification of the listed fields.

**Example: `cote_auto` in `livres`** — generate an automatic shelf mark from the first three letters of the title and the year (triggered on `titre` and `annee`):

```moonscript
-- triggerFields: ["titre", "annee"]
prefix = (@titre or "")\upper!\sub(1, 3)\gsub("[^%A]", "")
annee  = if @annee then tostring(@annee) else "????"
"#{prefix}-#{annee}"
```

### Edit an existing field

Click the **(pencil)** icon next to a field to edit its name, type, formula or trigger.

![Edit field](../img/field-edit.png)

---

## Entering and editing data

- Click a cell to edit it directly in the grid.
- Press **Enter** or Tab to move to the next cell.
- To **add a row**, click in the empty area below the last row.
- To **delete rows**, select them (checkboxes) then click the [del] “Delete selected rows” button.

Start by entering data in the reference tables (`genres`, `auteurs`, `classes`) before filling `livres`, `personnes` and `exemplaires`.

---

## Relations between spaces

In the **Fields** panel choose the **Relation** type for `_id` fields:

1. Select the **target** space from the dropdown.
2. The field will store the identifier of the linked record.

Here are the relations to create for the library:

| Source field (space) | Target space |
|-----------------------|-------------|
| `livres.auteur_id` | `auteurs` |
| `livres.genre_id` | `genres` |
| `exemplaires.livre_id` | `livres` |
| `emprunts.exemplaire_id` | `exemplaires` |
| `emprunts.personne_id` | `personnes` |
| `personnes.classe_id` | `classes` |
| `coordonnees.personne_id` | `personnes` |
| `livres_motscles.livre_id` | `livres` |
| `livres_motscles.motcle_id` | `motscles` |
| `livres_etiquettes.livre_id` | `livres` |
| `livres_etiquettes.etiquette_id` | `etiquettes` |

Relations can then be used to build custom views with automatic filtering (inter-widget dependencies).

### Representation formula (reprFormula)

By default, a Relation column displays the raw identifier of the linked record. You can define a **representation formula** in MoonScript to show a human-friendly label instead.

- The syntax `@field` accesses fields of the linked record.
- FK fields are resolved automatically: `@genre_id.libelle` follows the `genre_id` relation in the linked space and returns its `libelle`.
- Multi-level chaining is supported: `@livre_id.genre_id.libelle` (copy → book → genre).
- If no formula is defined, the column uses the `_repr` field of the target space (if present), otherwise the raw id.

**Examples:**

| Formula | Effect |
|---------|-------|
| `@nom` | Shows the `nom` field of the linked record |
| `@nom .. ' ' .. @prenom` | Concatenates last name and first name |
| `@genre_id.libelle` | Follows the FK `genre_id` and displays the genre label |
| `@livre_id.genre_id.libelle` | Chains two FKs (copy → book → genre) |

**Concrete example — loans:**

In the `emprunts` space, the `exemplaire_id` column can display the title of the corresponding book by chaining FKs:

```
reprFormula : @livre_id.titre
```

(To show the book title for this copy.)

To set the formula, click the **(pencil)** next to the Relation field in the Fields panel and enter the representation formula in the **Representation formula** field.

---

## Custom views (YAML)

Views let you compose multi-space dashboards.

![Custom view](../img/custom-view.png)

### Create a view

1. In the **Views** section click **+**.
2. Give the view a name (e.g. `Loans management`).
3. The YAML editor opens automatically.

### YAML editor with ERD schema

Clicking **Edit** opens a fullscreen modal with two panels:

- **Left**: CodeMirror editor (YAML syntax highlighting, monokai theme).
- **Right**: interactive ERD diagram showing all spaces and their relations.

![YAML editor modal and ERD diagram](../img/erd-modal-overview.png)

**Use the ERD diagram to build the YAML:**

Each box represents a space. For each field (row):

- Click **`*`** (first row, italic) to add the space **without column restrictions**. The box lights up with the `* ✓` badge.

![Select with pseudo-field *](../img/erd-star-field.png)

- Click a **named field** to add it to the widget's `columns` list. If the space is not yet in the YAML it is created. If that space has a foreign key to an already-present space in the YAML, a `depends_on` is generated automatically.

![Auto-detection of depends_on](../img/erd-depends-on.png)

- Clicking a selected field again removes it. Removing all fields deletes the widget.
- The **Clear** button resets the selection.
- **Arrows** indicate foreign keys; **self-relations** (e.g. `parent_id → id`) are drawn as a loop on the right side of the box.

**Bidirectional sync:** the ERD initializes from the existing YAML when opening the modal — spaces and fields already defined are highlighted. Editing the YAML manually in CodeMirror updates the diagram in real time. Fields not managed by the builder (like `title`, `aggregate`, `computed`) are **preserved** when editing via the diagram.

**Modal buttons:**

| Button | Action |
|--------|--------|
| **↓ Save** | Save the YAML |
| **▶ Preview** | Show the rendered view |
| **×** | Close the modal without saving |

### View “Loans management”

The main library view shows books, their copies and current loans, with a summary by genre.

```yaml
layout:
  direction: vertical
  children:
    - widget:
        id: livres
        title: Catalogue des livres
        space: livres
        columns: [titre, cote_auto, auteur_id, genre_id, isbn, annee]
    - layout:
        direction: horizontal
        children:
          - widget:
              id: exemplaires
              title: Exemplaires
              space: exemplaires
              depends_on:
                widget: livres
                field: livre_id
                from_field: id
              columns: [etat, disponible]
              factor: 2
          - widget:
              id: emprunts_en_cours
              title: Emprunts en cours
              space: emprunts
              depends_on:
                widget: exemplaires
                field: exemplaire_id
                from_field: id
              columns: [personne_id, date_emprunt, date_retour]
              factor: 3
```

### Aggregate widget — Loans by genre

An `aggregate` widget shows a read-only summary table — the equivalent of an SQL `GROUP BY`, computed in Lua on the server side.

```yaml
- widget:
    type: aggregate
    title: Emprunts par genre
    space: emprunts
    groupBy: [genre_id]
    aggregate:
      - fn: count
        as: nb_emprunts
    computed:
      - as: label
        expr: "row.genre_id + ' (' + row.nb_emprunts + ')'"
      - as: statut
        expr: "row.nb_emprunts > 10 ? 'Actif' : 'Peu emprunté'"
```

Available functions are `sum`, `count`, `avg`, `min`, `max`. The `as` alias is optional (default name: `fn_field`, e.g. `count`).

![Aggregate widget example](../img/aggregate-widget.png)

### Custom widget plugins

You can add custom widgets to a YAML view with a plugin (`CoffeeScript` or `JavaScript` for logic, `Pug` or `HTML` for template).

#### Create a plugin

1. Open a custom view.
2. Click **🧩 Plugins** in the view toolbar.
3. Click **+ New**.
4. Fill:
   - `name` (used as widget `type` in YAML)
   - `description` (optional)
   - script language + code
   - template language + code
5. Click **💾 Save**.
6. Close the modal (`✕`) to refresh views using modified plugins.

#### Plugin script contract

Your script must export a function:

```coffeescript
module.exports = ({ gql, emitSelection, onInputSelection, render, params }) ->
  render "<div>Ready</div>"
```

- `render(html)`: updates widget HTML inside the sandboxed iframe.
- `params`: widget params from YAML (`widget.params`).
- `gql(query, variables)`: runs GraphQL requests through the parent app.
- `emitSelection({ rows, byField })`: emits selection for dependent widgets.
- `onInputSelection(cb)`: receives selection from `depends_on` upstream widgets.

#### Use plugin in YAML

Set the widget `type` to the plugin name:

```yaml
- widget:
    id: books_plugin
    type: test
    title: Books plugin
    params:
      title: "Books"
```

`depends_on` works with plugin widgets the same way as for space widgets:

```yaml
- widget:
    id: books_plugin
    type: test
    depends_on:
      widget: livres
      field: livre_id
      from_field: id
```

#### Troubleshooting

- If script/template compilation fails, TGui shows a detailed message with plugin name, source (`script` or `template`), language, and line/column when available.
- If runtime execution fails inside the iframe, TGui shows `Plugin <name> — exécution JavaScript invalide ...` with the error details.
- Runtime availability errors (`runtime CoffeeScript indisponible`, `runtime Pug indisponible`) indicate a missing or broken frontend vendor bundle.

---

## User and rights management (admin)

The **Administration** section is visible only to members of the `admin` group.

### Users

![Users panel](../img/admin-users.png)

- **+ Create**: opens a form (username, optional email, password).
- **[key]** on each row: allows the admin to force a password change for a user without knowing their current password.

### Groups

![Groups panel](../img/admin-groups.png)

- **+ Create**: creates a new group.
- **[del]**: deletes the group (except the protected `admin` group).

> Rights (`grant` / `revoke`) are currently manageable via the GraphQL API.

### Export and import snapshots

The **Export / Import** section allows saving and restoring a TGui application.

**Export:**

- **Structure only**: downloads a `.tdb.yaml` file containing the full schema (spaces, fields, relations, views, groups, permissions) without data.
- **Structure + data**: includes all rows of each space.

**Import:**

1. Click **Choose file** and select a `.tdb.yaml` file.
2. A **diff** is shown (green = create, red = delete, orange = modify).
3. Choose mode:
   - **Merge**: create missing elements, leave existing ones untouched.
   - **Replace**: delete everything and recreate from the snapshot (warning: data loss).
4. Click **Confirm import**.

---

## User profile

Click your **username** (bottom left) to open the menu:

![Profile menu](../img/user-menu.png)

- **Change password**: enter the old and the new password.
- **Logout**: invalidates the session on the server and returns to the login screen.
- **FR / EN**: changes the interface language (preference is stored locally in the browser).

![Change password dialog](../img/change-password.png)

---

## Rename or delete a space

In the space toolbar:

- **(pencil)** (pencil icon): rename the space.
- **[del]** (trash icon next to the title): delete the space and all its data.

---

## Keyboard shortcuts

| Key | Action |
|--------|--------|
| **Enter** | Confirm cell edit |
| **Escape** | Cancel current edit |
| **Tab** | Move to the next cell |
| **Enter** on the login screen | Log in |

