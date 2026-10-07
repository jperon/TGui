-- tests/test_app_plan.moon
-- Tests purs pour core/app_plan.moon (moteur de plan de mise a jour, spec §2).
-- Aucun acces a box ni a la base : les tables sont construites a la main.

R = require 'tests.runner'
{ :plan_update } = require 'core.app_plan'

APP = { id: 'org.test.app', name: 'Test', version: '1.0.0', description: 'demo' }

-- Construit un item de paquet.
item = (type_, key, fingerprint, renamed_from) ->
  result = { type: type_, key: key, content: {}, fingerprint: fingerprint }
  result.renamed_from = renamed_from if renamed_from
  result

mk_pkg = (items, app) -> { app: app or APP, items: items }

-- installed = { [key] = {type, fingerprint, state} }
mk_installed = (rows) ->
  result = {}
  for r in *rows
    result[r.key] = { type: r.type, fingerprint: r.fp, state: r.state or 'actif' }
  result

-- local_states = { [key] = {fingerprint, content} }
mk_local = (rows) ->
  result = {}
  for r in *rows
    result[r.key] = { fingerprint: r.fp, content: r.content or {} }
  result

keys_of = (list) -> [e.key for e in *list]
conflict_keys = (plan) -> [c[1].key for c in *plan.conflict]

-- Compare deux listes element par element (les tables Lua se comparent par reference).
eq_list = (actual, expected, label) ->
  R.eq #actual, #expected, "#{label and label .. ' ' or ''}length"
  for i = 1, #expected
    R.eq actual[i], expected[i], "#{label and label .. ' ' or ''}[#{i}]"

empty_plan = (plan) ->
  R.eq #plan.create, 0, 'create'
  R.eq #plan.update, 0, 'update'
  R.eq #plan.conflict, 0, 'conflict'
  R.eq #plan.keep_local, 0, 'keep_local'
  R.eq #plan.obsolete, 0, 'obsolete'
  R.eq #plan.rename, 0, 'rename'
  R.eq #plan.unchanged, 0, 'unchanged'
  R.eq #plan.errors, 0, 'errors'

R.describe "app_plan — règle 1 : élément absent de l'installation", ->
  R.it "règle 1 : absent installé et absent localement → create", ->
    plan = plan_update {}, mk_pkg({ item 'space', 'space:a', 'fpa' }), {}, {}
    eq_list keys_of(plan.create), {'space:a'}, 'create'
    R.eq plan.create[1].fingerprint, 'fpa'
    R.eq #plan.update, 0
    R.eq #plan.conflict, 0
    R.eq #plan.keep_local, 0
    R.eq #plan.unchanged, 0

  R.it "règle 1 : absent installé mais présent localement, même empreinte → unchanged", ->
    plan = plan_update {}, mk_pkg({ item 'space', 'space:a', 'fpa' }),
      mk_local({ {key: 'space:a', fp: 'fpa'} }), {}
    R.eq #plan.create, 0
    eq_list plan.unchanged, {'space:a'}, 'unchanged'
    R.eq #plan.conflict, 0

  R.it "règle 1 : absent installé mais présent localement, empreinte différente → conflict", ->
    plan = plan_update {}, mk_pkg({ item 'space', 'space:a', 'fpa' }),
      mk_local({ {key: 'space:a', fp: 'local'} }), {}
    R.eq #plan.create, 0
    R.eq #plan.unchanged, 0
    eq_list conflict_keys(plan), {'space:a'}, 'conflict'
    R.eq plan.conflict[1][2].fingerprint, 'local'
    R.eq plan.conflict[1][3], 'fpa'

R.describe "app_plan — règle 2 : élément installé et dans le paquet", ->
  R.it "règle 2 : inchangé localement + modifié par l'auteur → update", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'N' }),
      mk_local({ {key: 'space:a', fp: 'L'} }), {}
    eq_list keys_of(plan.update), {'space:a'}, 'update'
    R.eq #plan.unchanged, 0

  R.it "règle 2 : inchangé localement et paquet inchangé → unchanged", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'L' }),
      mk_local({ {key: 'space:a', fp: 'L'} }), {}
    eq_list plan.unchanged, {'space:a'}, 'unchanged'
    R.eq #plan.update, 0

  R.it "règle 2 : modifié localement seulement → keep_local", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'L' }),
      mk_local({ {key: 'space:a', fp: 'C'} }), {}
    eq_list keys_of(plan.keep_local), {'space:a'}, 'keep_local'
    R.eq #plan.conflict, 0

  R.it "règle 2 : modifié localement et par l'auteur → conflict", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'N' }),
      mk_local({ {key: 'space:a', fp: 'C'} }), {}
    eq_list conflict_keys(plan), {'space:a'}, 'conflict'
    R.eq plan.conflict[1][2].fingerprint, 'C'
    R.eq plan.conflict[1][3], 'N'
    R.eq #plan.update, 0
    R.eq #plan.keep_local, 0

  R.it "règle 2 : convergence (local == paquet, auteur a changé) → unchanged", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'N' }),
      mk_local({ {key: 'space:a', fp: 'N'} }), {}
    eq_list plan.unchanged, {'space:a'}, 'unchanged'
    R.eq #plan.update, 0
    R.eq #plan.conflict, 0

  R.it "règle 2 : supprimé localement et paquet inchangé → keep_local", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'L' }), {}, {}
    eq_list keys_of(plan.keep_local), {'space:a'}, 'keep_local'
    R.eq #plan.conflict, 0

  R.it "règle 2 : supprimé localement et paquet modifié → conflict", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:a', 'N' }), {}, {}
    eq_list conflict_keys(plan), {'space:a'}, 'conflict'
    R.eq plan.conflict[1][2], nil
    R.eq plan.conflict[1][3], 'N'
