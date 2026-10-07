> **Document historique** : fonctionnalité implémentée. Le glisser-déposer des
> widgets et des zones est en place dans `frontend/src/drag_drop_manager.coffee`
> et `frontend/src/yaml_builder.coffee`, avec les mutations `reorderWidgets`,
> `createZone`, `resizeZone`, `mergeZones` et `splitZone` de `schema/tdb.graphql`
> implémentées côté serveur dans `backend/resolvers/custom_view_widgets.moon` et
> `backend/resolvers/custom_view_zones.moon`. Couverture : `tests/test_reorder_widgets.moon`,
> `tests/test_change_parent.moon`, `tests/test_resize_zone.moon`,
> `tests/test_zone_merge_split.moon`, `tests/test_drag_drop_e2e.moon` et les specs
> Playwright `tests/playwright/pages/drag-drop-widgets.spec.coffee`,
> `drag-drop-final-parallel.spec.coffee`, `zone-management-parallel.spec.coffee`
> et `presentation-export-mobile.spec.coffee`. Ce plan est conservé pour mémoire.

# Roadmap : Implémentation du Drag & Drop pour Widgets

## 📋 Contexte actuel

Depuis les dernières évolutions, le système dispose de :
- **Pages** : Layouts YAML avec widgets (anciennement CustomViews)
- **Data Views** : Requêtes SQL-like avec configuration avancée
- **Widgets** : Composants affichant les données des espaces
- **Système de factors** : Proportions flexbox déjà implémentées

## 🎯 Objectif

Permettre aux utilisateurs de réorganiser visuellement les widgets et zones dans les Pages via drag & drop, avec mise à jour automatique du YAML.

## 📅 Phases d'implémentation

### Phase 1 : Infrastructure Drag & Drop (Semaine 1)
**Backend**
- [x] Ajouter champ `position` dans les widgets du YAML (via PositionInput)
- [x] Créer mutation `reorderWidgets(pageId: ID!, widgetPositions: [WidgetPosition!]!)`
- [x] Mettre à jour `custom_view_resolvers.moon` pour gérer le réordonnancement

**Frontend**
- [x] Intégrer bibliothèque drag & drop (SortableJS)
- [x] Créer `DragDropManager` dans `frontend/src/drag_drop_manager.coffee`
- [x] Ajouter zones de drop visibles sur les widgets existants

**Tests**
- [x] Tests unitaires pour la mutation `reorderWidgets`
- [x] Tests d'intégration drag & drop basiques

### Phase 2 : Réordonnancement simple (Semaine 2)
**Fonctionnalités**
- [x] Drag & drop entre widgets de même niveau
- [x] Mise à jour temps réel du YAML
- [x] Animation visuelle du déplacement
- [x] Validation des positions (empêcher les déplacements invalides)

**Backend**
- [x] Parser YAML existant avec positions
- [x] Reconstruire YAML avec nouvel ordre
- [x] Gestion des conflits de positions

**Frontend**
- [x] Handlers drag start/drag end
- [x] Zones de drop highlightées
- [x] Feedback visuel (curseurs, ombres)

### Phase 3 : Changement de conteneur (Semaine 3)
**Fonctionnalités**
- [x] Déplacer un widget vers une zone parent différente
- [x] Créer de nouvelles zones par drag & drop
- [x] Fusionner/séparer des zones

**Backend**
- [x] Gérer les changements de hiérarchie
- [x] Recalculer les factors automatiquement
- [x] Validation des structures YAML

**Frontend**
- [x] Indicateurs visuels pour les zones cibles
- [x] Mode "création de zone" par drag entre widgets
- [x] Panel latéral pour les actions avancées
- [x] Support multi-conteneurs dans DragDropManager
- [x] Tests E2E pour la gestion des zones (4/7 tests)
- [x] Interface de création de zones (modale)
- [x] Poignées de redimensionnement interactives

### Phase 4 : Redimensionnement interactif (Semaine 4)
**Fonctionnalités**
- [x] Poignées de redimensionnement sur les zones
- [x] Ajustement interactif des factors
- [x] Snap à des proportions prédéfinies (1/3, 1/2, 2/3)

**Backend**
- [x] Mutation `resizeZone(pageId: ID!, zoneId: ID!, factor: Float!)`
- [x] Validation des factors (min/max)
- [x] Recalcul automatique des factors voisins

**Frontend**
- [x] Composant `ResizeHandle`
- [x] Grid visuelle pour l'alignement
- [x] Tooltip affichant la proportion actuelle

### Phase 5 : Data Views Integration (Semaine 5)
**Fonctionnalités**
- [x] Drag & drop des Data Views dans les Pages
- [x] Conversion automatique Data View → Widget
- [x] Synchronisation des configurations

**Backend**
- [x] Mutation `addDataViewToPage(pageId: ID!, dataViewId: ID!)`
- [x] Mapping des configurations Data View vers Widget
- [x] Préservation des filtres et agrégations

**Frontend**
- [x] Panel Data Views glissant
- [x] Preview du widget avant insertion
- [x] Configuration rapide post-insertion

### Phase 6 : UX Avancée (Semaine 6)
**Fonctionnalités**
- [x] Undo/Redo pour les opérations drag & drop
- [ ] Mode "présentation" sans drag & drop
- [x] Raccourcis clavier pour les actions courantes
- [ ] Export/import des mises en page

**Backend**
- [x] Historique des modifications
- [ ] Snapshots automatiques
- [x] Validation des permissions

**Frontend**
- [x] Système de commandes (Command Pattern)
- [x] Animations et transitions fluides
- [ ] Mode responsive pour mobile

## 🏗️ Architecture technique

### Backend

```moon
-- backend/resolvers/page_resolvers.moon
reorder_widgets: (page_id, widget_positions) ->
  page = get_page page_id
  config = yaml.decode page.yaml

  -- Mettre à jour les positions
  for pos in widget_positions
    update_widget_position config, pos.widget_id, pos.index, pos.parent_id

  updated_yaml = yaml.encode config
  update_page page_id, yaml: updated_yaml

-- Structures
WidgetPosition = {
  widget_id: String
  index: Int
  parent_id: String?  -- null pour racine
}
```

### Frontend

```coffee
# frontend/src/drag_drop_manager.coffee
class DragDropManager
  constructor: (@pageContainer, @onReorder) ->
    @sortable = new Sortable @pageContainer,
      animation: 150
      ghostClass: 'widget-ghost'
      onEnd: @handleDrop

  handleDrop: (evt) =>
    positions = @extractPositions evt
    @onReorder positions

  extractPositions: (evt) ->
    # Extraire les nouvelles positions depuis le DOM
```

## 🧪 Tests

### Tests Backend
- [x] `test_reorder_widgets.moon` : Réordonnancement simple
- [x] `test_change_parent.moon` : Changement de conteneur
- [x] `test_resize_zone.moon` : Redimensionnement
- [x] `test_add_data_view_to_page.moon` : Integration Data Views

### Tests Frontend
- [x] Tests E2E avec Playwright pour les scénarios drag & drop
- [ ] Tests unitaires pour `DragDropManager`
- [ ] Tests d'accessibilité (navigation clavier)

### Tests Integration
- [ ] Synchronisation YAML ↔ DOM
- [ ] Performance avec 50+ widgets
- [ ] Compatibilité navigateurs

## 📊 Métriques de succès

- **Performance** : < 200ms pour la mise à jour après drag & drop
- **UX** : Taux d'erreur < 1% pour les opérations drag & drop
- **Adoption** : > 80% des utilisateurs utilisent le drag & drop vs édition YAML
- **Stabilité** : 0 régression dans les fonctionnalités existantes

## 🚨 Risques et mitigations

| Risque | Impact | Mitigation |
|--------|--------|------------|
| Performance avec grand nombre de widgets | Élevé | Virtualisation, lazy loading |
| Conflits de mise à jour simultanées | Moyen | Optimistic locking, validation |
| Complexité du YAML généré | Moyen | Tests automatiques, format normalisé |
| Accessibilité | Moyen | Raccourcis clavier, ARIA labels |

## 🔄 Dépendances

- [x] **SortableJS** : Bibliothèque drag & drop
- [x] **MutationObserver** : Surveillance des changements DOM
- [x] **Debounce** : Optimisation des mises à jour
- [x] **Tests E2E** : Playwright (déjà utilisé)

## 📝 Notes importantes

1. **Compatibilité ascendante** : Les Pages existantes sans positions doivent rester fonctionnelles
2. **YAML comme source de vérité** : Le drag & drop ne fait que modifier le YAML
3. **Data Views** : Système parallèle, les widgets restent basés sur les espaces
4. **Mobile** : Prévoir adaptation pour les écrans tactiles petits

---

*Cette roadmap est évolutionniste et peut être ajustée selon les retours utilisateurs et les contraintes techniques.*
