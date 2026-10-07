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

R.describe "app_plan — règle 3 : éléments obsolètes", ->
  R.it "règle 3 : installé actif absent du paquet → obsolete", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L'} }),
      mk_pkg({}), {}, {}
    eq_list plan.obsolete, {'space:a'}, 'obsolete'
    R.eq #plan.create, 0
    R.eq #plan.update, 0

  R.it "règle 3 : déjà obsolète et toujours absent → pas répété", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L', state: 'obsolète'} }),
      mk_pkg({}), {}, {}
    R.eq #plan.obsolete, 0

  R.it "règle 3 : élément obsolète qui réapparaît dans le paquet → traité comme règle 2", ->
    plan = plan_update mk_installed({ {key: 'space:a', type: 'space', fp: 'L', state: 'obsolète'} }),
      mk_pkg({ item 'space', 'space:a', 'N' }),
      mk_local({ {key: 'space:a', fp: 'L'} }), {}
    eq_list keys_of(plan.update), {'space:a'}, 'update'
    R.eq #plan.obsolete, 0

R.describe "app_plan — règle 4 : renamed_from", ->
  R.it "règle 4 : ancienne clé installée → rename puis règle 2 sur l'ancienne clé", ->
    plan = plan_update mk_installed({ {key: 'space:old', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:new', 'N', 'space:old' }),
      mk_local({ {key: 'space:old', fp: 'L'} }), {}
    eq_list plan.rename[1], {'space:old', 'space:new'}, 'rename'
    eq_list keys_of(plan.update), {'space:new'}, 'update'
    R.eq #plan.obsolete, 0

  R.it "règle 4 : ancienne clé non installée → create simple sans rename", ->
    plan = plan_update {}, mk_pkg({ item 'space', 'space:new', 'N', 'space:old' }),
      mk_local({ {key: 'space:new', fp: 'other'} }), {}
    R.eq #plan.rename, 0
    eq_list keys_of(plan.create), {'space:new'}, 'create'

  R.it "règle 4 : comparaison faite sur l'état local de l'ancienne clé (conflit)", ->
    plan = plan_update mk_installed({ {key: 'space:old', type: 'space', fp: 'L'} }),
      mk_pkg({ item 'space', 'space:new', 'N', 'space:old' }),
      mk_local({ {key: 'space:old', fp: 'C'} }), {}
    eq_list conflict_keys(plan), {'space:new'}, 'conflict'
    R.eq plan.conflict[1][2].fingerprint, 'C'
    R.eq plan.conflict[1][3], 'N'
    R.eq #plan.obsolete, 0

R.describe "app_plan — règle 5 : lignes seed", ->
  R.it "règle 5 : seed installé absent du paquet → jamais obsolete", ->
    plan = plan_update mk_installed({ {key: 'seed:s|k', type: 'seed', fp: 'L'} }),
      mk_pkg({}), {}, {}
    R.eq #plan.obsolete, 0

  R.it "règle 5 : seed modifié localement et par l'auteur → keep_local (jamais conflict)", ->
    plan = plan_update mk_installed({ {key: 'seed:s|k', type: 'seed', fp: 'L'} }),
      mk_pkg({ item 'seed', 'seed:s|k', 'N' }),
      mk_local({ {key: 'seed:s|k', fp: 'C'} }), {}
    eq_list keys_of(plan.keep_local), {'seed:s|k'}, 'keep_local'
    R.eq #plan.conflict, 0

  R.it "règle 5 : seed absent installé mais présent localement différent → keep_local", ->
    plan = plan_update {}, mk_pkg({ item 'seed', 'seed:s|k', 'N' }),
      mk_local({ {key: 'seed:s|k', fp: 'C'} }), {}
    R.eq #plan.conflict, 0
    eq_list keys_of(plan.keep_local), {'seed:s|k'}, 'keep_local'

  R.it "règle 5 : seed inchangé localement, modifié par l'auteur → update", ->
    plan = plan_update mk_installed({ {key: 'seed:s|k', type: 'seed', fp: 'L'} }),
      mk_pkg({ item 'seed', 'seed:s|k', 'N' }),
      mk_local({ {key: 'seed:s|k', fp: 'L'} }), {}
    eq_list keys_of(plan.update), {'seed:s|k'}, 'update'

  R.it "règle 5 : seed supprimé localement et auteur modifié → keep_local (pas de conflict)", ->
    plan = plan_update mk_installed({ {key: 'seed:s|k', type: 'seed', fp: 'L'} }),
      mk_pkg({ item 'seed', 'seed:s|k', 'N' }), {}, {}
    eq_list keys_of(plan.keep_local), {'seed:s|k'}, 'keep_local'
    R.eq #plan.conflict, 0

R.describe "app_plan — règle 6 : groupes et droits", ->
  R.it "règle 6 : groupe modifié localement → keep_local (jamais conflict)", ->
    plan = plan_update mk_installed({ {key: 'group:g', type: 'group', fp: 'L'} }),
      mk_pkg({ item 'group', 'group:g', 'N' }),
      mk_local({ {key: 'group:g', fp: 'C'} }), {}
    eq_list keys_of(plan.keep_local), {'group:g'}, 'keep_local'
    R.eq #plan.conflict, 0

  R.it "règle 6 : perm modifié localement → keep_local (jamais conflict)", ->
    plan = plan_update mk_installed({ {key: 'perm:g|read|r|1', type: 'perm', fp: 'L'} }),
      mk_pkg({ item 'perm', 'perm:g|read|r|1', 'N' }),
      mk_local({ {key: 'perm:g|read|r|1', fp: 'C'} }), {}
    eq_list keys_of(plan.keep_local), {'perm:g|read|r|1'}, 'keep_local'
    R.eq #plan.conflict, 0

  R.it "règle 6 : perm absent du paquet → pas d'obsolete", ->
    plan = plan_update mk_installed({ {key: 'perm:g|read|r|1', type: 'perm', fp: 'L'} }),
      mk_pkg({}), {}, {}
    R.eq #plan.obsolete, 0

  R.it "règle 6 : groupe absent du paquet → obsolete comme les autres", ->
    plan = plan_update mk_installed({ {key: 'group:g', type: 'group', fp: 'L'} }),
      mk_pkg({}), {}, {}
    eq_list plan.obsolete, {'group:g'}, 'obsolete'

  R.it "règle 6 : perm absent installé mais présent localement différent → keep_local", ->
    plan = plan_update {}, mk_pkg({ item 'perm', 'perm:g|read|r|1', 'N' }),
      mk_local({ {key: 'perm:g|read|r|1', fp: 'C'} }), {}
    eq_list keys_of(plan.keep_local), {'perm:g|read|r|1'}, 'keep_local'
    R.eq #plan.conflict, 0
