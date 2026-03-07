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
children:
  - ...                   # liste de zones ou de widgets
```

Les zones utilisent un layout flexbox : chaque enfant occupe une part égale de l'espace disponible.

---

## Widget

Un widget affiche les données d'un espace sous forme de grille.

```yaml
widget:
  title: Personnes          # libellé affiché en en-tête du widget (optionnel)
  space: personnes          # nom ou ID de l'espace à afficher (obligatoire)
  depends_on:               # filtre dynamique basé sur la sélection d'un autre widget (optionnel)
    widget: 0               # index (0-based) du widget source dans la liste de tous les widgets
    field: personne_id      # champ de filtrage dans l'espace de CE widget
    from_field: id          # champ de référence dans l'espace du widget source
```

### Champs du widget

| Clé | Obligatoire | Description |
|-----|-------------|-------------|
| `id` | si référencé | Identifiant unique du widget dans la vue, utilisé par `depends_on.widget` |
| `title` | non | Titre affiché en haut du widget |
| `space` | oui | Nom ou UUID de l'espace Tarantool à afficher |
| `depends_on` | non | Filtre ce widget en fonction de la ligne sélectionnée dans un autre widget |

### Champs de `depends_on`

| Clé | Description |
|-----|-------------|
| `widget` | `id` du widget source (chaîne définie dans le champ `id` de ce widget) |
| `field` | Champ de **cet** espace utilisé comme filtre (clé étrangère) |
| `from_field` | Champ de l'espace **source** dont la valeur sera comparée (généralement `id`) |

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
          from_field: id        # champ référencé dans "chorale"
```

### Mise en page complexe (zones imbriquées)

```yaml
layout:
  direction: vertical
  children:
    - direction: horizontal
      children:
        - widget:
            id: chorales
            title: Chorales
            space: chorale
        - widget:
            title: Choristes
            space: choristes
            depends_on:
              widget: chorales
              field: chorale_id
              from_field: id
    - direction: horizontal
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
              from_field: id
```

---

## Notes

- **Identifiants de widgets** : le champ `id` est libre (chaîne quelconque). Il n'est obligatoire que si un autre widget y fait référence via `depends_on.widget`.
- **Filtrage** : le mécanisme `depends_on` repose sur l'événement de clic de ligne dans le widget source. La valeur du champ `from_field` de la ligne cliquée est comparée au champ `field` de cet espace (`EQ`).
- **Espace introuvable** : si le nom ou l'UUID fourni dans `space` ne correspond à aucun espace existant, le widget affiche un message d'erreur sans bloquer le reste de la vue.
- **YAML invalide** : une erreur de syntaxe YAML est affichée à la place de la vue.
