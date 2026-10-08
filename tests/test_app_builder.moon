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
