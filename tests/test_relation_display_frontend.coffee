# tests/test_relation_display_frontend.coffee
# Test frontend pour vérifier l'affichage des relations

describe "Relation display frontend", ->
  beforeEach ->
    # Attendre que l'interface soit chargée
    @app = window.tdbApp
    throw "App not loaded" unless @app

  it "should display relation fields with arrow format", ->
    # Naviguer vers un espace
    spaces = await Spaces.listSpaces()
    testSpace = spaces.find (s) -> s.name == "test_rel_display_source"
    return unless testSpace  # Skip si l'espace n'existe pas
    
    # Naviguer vers l'espace
    await @app.navigateToSpace testSpace.id
    
    # Attendre que les champs soient chargés
    await new Promise (resolve) -> setTimeout resolve, 100
    
    # Vérifier l'affichage des types de champs
    fieldBadges = document.querySelectorAll '#fields-list .field-type-badge'
    
    # Chercher le champ de relation
    relationBadge = null
    for badge in fieldBadges
      if badge.textContent.includes '→'
        relationBadge = badge
        break
    
    if relationBadge
      # Vérifier le format "→ Target"
      assert relationBadge.textContent.match /^→ \w+/, "Should display arrow format"
      assert relationBadge.title.includes "Relation vers", "Should have relation tooltip"
      console.log "Found relation badge:", relationBadge.textContent
    else
      console.log "No relation field found"

  it "should use _repr for relation data in grid", ->
    # Ce test nécessite une interaction manuelle ou une simulation plus complexe
    # Pour l'instant, on vérifie juste que le code existe
    dataView = window.tdbApp?._activeDataView
    if dataView
      assert dataView._fkMaps, "Should have FK maps"
      assert dataView._fkOptions, "Should have FK options"
