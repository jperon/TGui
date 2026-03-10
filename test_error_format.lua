local R = require('tests.runner')
R.describe("Test du formatage d'erreurs", function()
  R.it("montre les détails quand une assertion échoue", function()
    return R.eq(42, 24, "le calcul mathématique")
  end)
  R.it("montre les détails quand une valeur truthy est attendue", function()
    local valeur = nil
    return R.ok(valeur, "une valeur truthy")
  end)
  R.it("montre les détails pour un tableau", function()
    local attendu = {
      a = 1,
      b = 2
    }
    local obtenu = {
      a = 1,
      b = 3
    }
    return R.eq(obtenu, attendu, "les objets complexes")
  end)
  return R.it("montre les détails pour un tableau indexé", function()
    local attendu = {
      1,
      2,
      3
    }
    local obtenu = {
      1,
      2,
      4
    }
    return R.eq(obtenu, attendu, "les listes")
  end)
end)
return R.summary()
