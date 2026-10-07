# Format YAML des vues personnalisées

Les vues personnalisées (section **Vues** dans la barre latérale) sont des tableaux de bord composés de zones imbriquées et de widgets. Leur mise en page est décrite en YAML et stockée côté serveur via l'API GraphQL.

---

## Structure générale

```yaml
layout:
  direction: vertical   # ou horizontal
  children:
    - ...               # zones ou widgets
```

Le document YAML doit contenir une clé racine `layout`. Un nœud est soit une **zone** (contient `direction` + `children`), soit un **widget** (contient `widget`).

---

## Zone

Une zone organise ses enfants horizontalement ou verticalement. Les zones peuvent s'imbriquer librement.

```yaml
direction: vertical       # "vertical" ou "horizontal"
factor: 2                 # proportion de l'espace occupée (optionnel, défaut : 1)
children:
  - ...                   # liste de zones ou de widgets
```

Chaque enfant d'une zone peut porter un champ `factor` (entier ou décimal) qui détermine sa part de l'espace disponible selon la règle des proportions flexbox. Par exemple, un enfant avec `factor: 2` et un voisin avec `factor: 1` occupent respectivement 2/3 et 1/3 de l'espace. Sans `factor`, tous les enfants se partagent l'espace à parts égales (`factor: 1` implicite).

---

## Widget

Un widget affiche les données d'un espace sous forme de grille.

```yaml
widget:
  title: Personnes          # libellé affiché en en-tête du widget (optionnel)
  space: personnes          # nom ou ID de l'espace à afficher (obligatoire)
  columns: [nom, prenom]    # colonnes à afficher dans l'ordre (optionnel, défaut : toutes)
  depends_on:               # filtre dynamique basé sur la sélection d'un autre widget (optionnel)
    widget: source-id       # id du widget source
    field: personne_id      # champ de filtrage dans l'espace de CE widget
    from_field: id          # champ de référence dans l'espace du widget source (défaut : id)
```

### Champs du widget

| Clé | Obligatoire | Description |
|-----|-------------|-------------|
| `id` | si référencé | Identifiant unique du widget dans la vue, utilisé par `depends_on.widget` |
| `title` | non | Titre affiché en haut du widget |
| `space` | oui | Nom ou UUID de l'espace Tarantool à afficher |
| `columns` | non | Liste ordonnée des champs à afficher ; si omis, tous les champs sont affichés |
| `depends_on` | non | Filtre ce widget en fonction de la ligne sélectionnée dans un autre widget |

### Champs de `depends_on`

| Clé | Description |
|-----|-------------|
| `widget` | `id` du widget source (chaîne définie dans le champ `id` de ce widget) |
| `field` | Champ de **cet** espace utilisé comme filtre (clé étrangère) |
| `from_field` | Champ de l'espace **source** dont la valeur sera comparée (défaut : `id`) |

---

## Exemples

### Vue simple : un seul espace

```yaml
layout:
  direction: vertical
  children:
    - widget:
        title: Personnes
        space: personnes
```

### Deux espaces côte à côte

```yaml
layout:
  direction: horizontal
  children:
    - widget:
        title: Chorales
        space: chorale
    - widget:
        title: Personnes
        space: personnes
```

### Proportions inégales (factor)

Le widget Chorales occupe 2/3 de la largeur, Personnes 1/3 :

```yaml
layout:
  direction: horizontal
  children:
    - factor: 2
      widget:
        title: Chorales
        space: chorale
    - factor: 1
      widget:
        title: Personnes
        space: personnes
```

### Colonnes sélectionnées

```yaml
layout:
  direction: vertical
  children:
    - widget:
        title: Personnes
        space: personnes
        columns: [prenom, nom]   # affiche uniquement prenom et nom, dans cet ordre
```

### Relation maître/détail

Sélectionner une chorale dans le widget `chorales` filtre automatiquement les choristes dans le widget `choristes` :

```yaml
layout:
  direction: horizontal
  children:
    - widget:
        id: chorales            # identifiant du widget source
        title: Chorales
        space: chorale
    - widget:
        title: Choristes
        space: choristes
        depends_on:
          widget: chorales      # id du widget source
          field: chorale_id     # champ FK dans l'espace "choristes"
          from_field: id        # champ référencé dans "chorale" (défaut : id)
```

### Mise en page complexe (zones imbriquées + proportions)

```yaml
layout:
  direction: vertical
  children:
    - factor: 2
      direction: horizontal
      children:
        - widget:
            id: chorales
            title: Chorales
            space: chorale
            columns: [annee, pupitre]
        - widget:
            title: Choristes
            space: choristes
            depends_on:
              widget: chorales
              field: chorale_id
    - factor: 1
      direction: horizontal
      children:
        - widget:
            title: Personnes
            space: personnes
        - widget:
            title: Partitions
            space: partitions
            depends_on:
              widget: chorales
              field: chorale_id
```

---

## Notes

- **Identifiants de widgets** : le champ `id` est libre (chaîne quelconque). Il n'est obligatoire que si un autre widget y fait référence via `depends_on.widget`.
- **Factor** : s'applique à n'importe quel enfant d'une zone (zone ou widget). La valeur peut être entière ou décimale. Les enfants sans `factor` valent `1`.
- **Colonnes** : l'ordre de la liste `columns` détermine l'ordre d'affichage dans la grille. Les noms non reconnus sont silencieusement ignorés.
- **from_field** : si omis dans `depends_on`, la valeur du champ `id` de la ligne source est utilisée.
- **Filtrage** : le mécanisme `depends_on` repose sur l'événement de clic de ligne dans le widget source.
- **Espace introuvable** : si le nom ou l'UUID fourni dans `space` ne correspond à aucun espace existant, le widget affiche un message d'erreur sans bloquer le reste de la vue.
- **YAML invalide** : une erreur de syntaxe YAML est affichée à la place de la vue.
