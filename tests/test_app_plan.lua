local R = require('tests.runner')
local plan_update
plan_update = require('core.app_plan').plan_update
local APP = {
  id = 'org.test.app',
  name = 'Test',
  version = '1.0.0',
  description = 'demo'
}
local item
item = function(type_, key, fingerprint, renamed_from)
  local result = {
    type = type_,
    key = key,
    content = { },
    fingerprint = fingerprint
  }
  if renamed_from then
    result.renamed_from = renamed_from
  end
  return result
end
local mk_pkg
mk_pkg = function(items, app)
  return {
    app = app or APP,
    items = items
  }
end
local mk_installed
mk_installed = function(rows)
  local result = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    result[r.key] = {
      type = r.type,
      fingerprint = r.fp,
      state = r.state or 'actif'
    }
  end
  return result
end
local mk_local
mk_local = function(rows)
  local result = { }
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    result[r.key] = {
      fingerprint = r.fp,
      content = r.content or { }
    }
  end
  return result
end
local keys_of
keys_of = function(list)
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #list do
    local e = list[_index_0]
    _accum_0[_len_0] = e.key
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
local conflict_keys
conflict_keys = function(plan)
  local _accum_0 = { }
  local _len_0 = 1
  local _list_0 = plan.conflict
  for _index_0 = 1, #_list_0 do
    local c = _list_0[_index_0]
    _accum_0[_len_0] = c[1].key
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
local eq_list
eq_list = function(actual, expected, label)
  R.eq(#actual, #expected, tostring(label and label .. ' ' or '') .. "length")
  for i = 1, #expected do
    R.eq(actual[i], expected[i], tostring(label and label .. ' ' or '') .. "[" .. tostring(i) .. "]")
  end
end
local empty_plan
empty_plan = function(plan)
  R.eq(#plan.create, 0, 'create')
  R.eq(#plan.update, 0, 'update')
  R.eq(#plan.conflict, 0, 'conflict')
  R.eq(#plan.keep_local, 0, 'keep_local')
  R.eq(#plan.obsolete, 0, 'obsolete')
  R.eq(#plan.rename, 0, 'rename')
  R.eq(#plan.unchanged, 0, 'unchanged')
  return R.eq(#plan.errors, 0, 'errors')
end
R.describe("app_plan — règle 1 : élément absent de l'installation", function()
  R.it("règle 1 : absent installé et absent localement → create", function()
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'fpa')
    }), { }, { })
    eq_list(keys_of(plan.create), {
      'space:a'
    }, 'create')
    R.eq(plan.create[1].fingerprint, 'fpa')
    R.eq(#plan.update, 0)
    R.eq(#plan.conflict, 0)
    R.eq(#plan.keep_local, 0)
    return R.eq(#plan.unchanged, 0)
  end)
  R.it("règle 1 : absent installé mais présent localement, même empreinte → unchanged", function()
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'fpa')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'fpa'
      }
    }), { })
    R.eq(#plan.create, 0)
    eq_list(plan.unchanged, {
      'space:a'
    }, 'unchanged')
    return R.eq(#plan.conflict, 0)
  end)
  return R.it("règle 1 : absent installé mais présent localement, empreinte différente → conflict", function()
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'fpa')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'local'
      }
    }), { })
    R.eq(#plan.create, 0)
    R.eq(#plan.unchanged, 0)
    eq_list(conflict_keys(plan), {
      'space:a'
    }, 'conflict')
    R.eq(plan.conflict[1][2].fingerprint, 'local')
    return R.eq(plan.conflict[1][3], 'fpa')
  end)
end)
R.describe("app_plan — règle 2 : élément installé et dans le paquet", function()
  R.it("règle 2 : inchangé localement + modifié par l'auteur → update", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'N')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'L'
      }
    }), { })
    eq_list(keys_of(plan.update), {
      'space:a'
    }, 'update')
    return R.eq(#plan.unchanged, 0)
  end)
  R.it("règle 2 : inchangé localement et paquet inchangé → unchanged", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'L')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'L'
      }
    }), { })
    eq_list(plan.unchanged, {
      'space:a'
    }, 'unchanged')
    return R.eq(#plan.update, 0)
  end)
  R.it("règle 2 : modifié localement seulement → keep_local", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'L')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'C'
      }
    }), { })
    eq_list(keys_of(plan.keep_local), {
      'space:a'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
  R.it("règle 2 : modifié localement et par l'auteur → conflict", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'N')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'C'
      }
    }), { })
    eq_list(conflict_keys(plan), {
      'space:a'
    }, 'conflict')
    R.eq(plan.conflict[1][2].fingerprint, 'C')
    R.eq(plan.conflict[1][3], 'N')
    R.eq(#plan.update, 0)
    return R.eq(#plan.keep_local, 0)
  end)
  R.it("règle 2 : convergence (local == paquet, auteur a changé) → unchanged", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'N')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'N'
      }
    }), { })
    eq_list(plan.unchanged, {
      'space:a'
    }, 'unchanged')
    R.eq(#plan.update, 0)
    return R.eq(#plan.conflict, 0)
  end)
  R.it("règle 2 : supprimé localement et paquet inchangé → keep_local", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'L')
    }), { }, { })
    eq_list(keys_of(plan.keep_local), {
      'space:a'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
  return R.it("règle 2 : supprimé localement et paquet modifié → conflict", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:a', 'N')
    }), { }, { })
    eq_list(conflict_keys(plan), {
      'space:a'
    }, 'conflict')
    R.eq(plan.conflict[1][2], nil)
    return R.eq(plan.conflict[1][3], 'N')
  end)
end)
R.describe("app_plan — règle 3 : éléments obsolètes", function()
  R.it("règle 3 : installé actif absent du paquet → obsolete", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({ }), { }, { })
    eq_list(plan.obsolete, {
      'space:a'
    }, 'obsolete')
    R.eq(#plan.create, 0)
    return R.eq(#plan.update, 0)
  end)
  R.it("règle 3 : déjà obsolète et toujours absent → pas répété", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L',
        state = 'obsolète'
      }
    }), mk_pkg({ }), { }, { })
    return R.eq(#plan.obsolete, 0)
  end)
  return R.it("règle 3 : élément obsolète qui réapparaît dans le paquet → traité comme règle 2", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L',
        state = 'obsolète'
      }
    }), mk_pkg({
      item('space', 'space:a', 'N')
    }), mk_local({
      {
        key = 'space:a',
        fp = 'L'
      }
    }), { })
    eq_list(keys_of(plan.update), {
      'space:a'
    }, 'update')
    return R.eq(#plan.obsolete, 0)
  end)
end)
R.describe("app_plan — règle 4 : renamed_from", function()
  R.it("règle 4 : ancienne clé installée → rename puis règle 2 sur l'ancienne clé", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:old',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:new', 'N', 'space:old')
    }), mk_local({
      {
        key = 'space:old',
        fp = 'L'
      }
    }), { })
    eq_list(plan.rename[1], {
      'space:old',
      'space:new'
    }, 'rename')
    eq_list(keys_of(plan.update), {
      'space:new'
    }, 'update')
    return R.eq(#plan.obsolete, 0)
  end)
  R.it("règle 4 : ancienne clé non installée → create simple sans rename", function()
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:new', 'N', 'space:old')
    }), mk_local({
      {
        key = 'space:new',
        fp = 'other'
      }
    }), { })
    R.eq(#plan.rename, 0)
    return eq_list(keys_of(plan.create), {
      'space:new'
    }, 'create')
  end)
  return R.it("règle 4 : comparaison faite sur l'état local de l'ancienne clé (conflit)", function()
    local plan = plan_update(mk_installed({
      {
        key = 'space:old',
        type = 'space',
        fp = 'L'
      }
    }), mk_pkg({
      item('space', 'space:new', 'N', 'space:old')
    }), mk_local({
      {
        key = 'space:old',
        fp = 'C'
      }
    }), { })
    eq_list(conflict_keys(plan), {
      'space:new'
    }, 'conflict')
    R.eq(plan.conflict[1][2].fingerprint, 'C')
    R.eq(plan.conflict[1][3], 'N')
    return R.eq(#plan.obsolete, 0)
  end)
end)
R.describe("app_plan — règle 5 : lignes seed", function()
  R.it("règle 5 : seed installé absent du paquet → jamais obsolete", function()
    local plan = plan_update(mk_installed({
      {
        key = 'seed:s|k',
        type = 'seed',
        fp = 'L'
      }
    }), mk_pkg({ }), { }, { })
    return R.eq(#plan.obsolete, 0)
  end)
  R.it("règle 5 : seed modifié localement et par l'auteur → keep_local (jamais conflict)", function()
    local plan = plan_update(mk_installed({
      {
        key = 'seed:s|k',
        type = 'seed',
        fp = 'L'
      }
    }), mk_pkg({
      item('seed', 'seed:s|k', 'N')
    }), mk_local({
      {
        key = 'seed:s|k',
        fp = 'C'
      }
    }), { })
    eq_list(keys_of(plan.keep_local), {
      'seed:s|k'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
  R.it("règle 5 : seed absent installé mais présent localement différent → keep_local", function()
    local plan = plan_update({ }, mk_pkg({
      item('seed', 'seed:s|k', 'N')
    }), mk_local({
      {
        key = 'seed:s|k',
        fp = 'C'
      }
    }), { })
    R.eq(#plan.conflict, 0)
    return eq_list(keys_of(plan.keep_local), {
      'seed:s|k'
    }, 'keep_local')
  end)
  R.it("règle 5 : seed inchangé localement, modifié par l'auteur → update", function()
    local plan = plan_update(mk_installed({
      {
        key = 'seed:s|k',
        type = 'seed',
        fp = 'L'
      }
    }), mk_pkg({
      item('seed', 'seed:s|k', 'N')
    }), mk_local({
      {
        key = 'seed:s|k',
        fp = 'L'
      }
    }), { })
    return eq_list(keys_of(plan.update), {
      'seed:s|k'
    }, 'update')
  end)
  return R.it("règle 5 : seed supprimé localement et auteur modifié → keep_local (pas de conflict)", function()
    local plan = plan_update(mk_installed({
      {
        key = 'seed:s|k',
        type = 'seed',
        fp = 'L'
      }
    }), mk_pkg({
      item('seed', 'seed:s|k', 'N')
    }), { }, { })
    eq_list(keys_of(plan.keep_local), {
      'seed:s|k'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
end)
R.describe("app_plan — règle 6 : groupes et droits", function()
  R.it("règle 6 : groupe modifié localement → keep_local (jamais conflict)", function()
    local plan = plan_update(mk_installed({
      {
        key = 'group:g',
        type = 'group',
        fp = 'L'
      }
    }), mk_pkg({
      item('group', 'group:g', 'N')
    }), mk_local({
      {
        key = 'group:g',
        fp = 'C'
      }
    }), { })
    eq_list(keys_of(plan.keep_local), {
      'group:g'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
  R.it("règle 6 : perm modifié localement → keep_local (jamais conflict)", function()
    local plan = plan_update(mk_installed({
      {
        key = 'perm:g|read|r|1',
        type = 'perm',
        fp = 'L'
      }
    }), mk_pkg({
      item('perm', 'perm:g|read|r|1', 'N')
    }), mk_local({
      {
        key = 'perm:g|read|r|1',
        fp = 'C'
      }
    }), { })
    eq_list(keys_of(plan.keep_local), {
      'perm:g|read|r|1'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
  R.it("règle 6 : perm absent du paquet → pas d'obsolete", function()
    local plan = plan_update(mk_installed({
      {
        key = 'perm:g|read|r|1',
        type = 'perm',
        fp = 'L'
      }
    }), mk_pkg({ }), { }, { })
    return R.eq(#plan.obsolete, 0)
  end)
  R.it("règle 6 : groupe absent du paquet → obsolete comme les autres", function()
    local plan = plan_update(mk_installed({
      {
        key = 'group:g',
        type = 'group',
        fp = 'L'
      }
    }), mk_pkg({ }), { }, { })
    return eq_list(plan.obsolete, {
      'group:g'
    }, 'obsolete')
  end)
  return R.it("règle 6 : perm absent installé mais présent localement différent → keep_local", function()
    local plan = plan_update({ }, mk_pkg({
      item('perm', 'perm:g|read|r|1', 'N')
    }), mk_local({
      {
        key = 'perm:g|read|r|1',
        fp = 'C'
      }
    }), { })
    eq_list(keys_of(plan.keep_local), {
      'perm:g|read|r|1'
    }, 'keep_local')
    return R.eq(#plan.conflict, 0)
  end)
end)
local all_lists_empty
all_lists_empty = function(plan)
  R.eq(#plan.create, 0, 'create')
  R.eq(#plan.update, 0, 'update')
  R.eq(#plan.conflict, 0, 'conflict')
  R.eq(#plan.keep_local, 0, 'keep_local')
  R.eq(#plan.obsolete, 0, 'obsolete')
  R.eq(#plan.rename, 0, 'rename')
  return R.eq(#plan.unchanged, 0, 'unchanged')
end
local deep_copy
deep_copy = function(v)
  if not (type(v) == 'table') then
    return v
  end
  local result = { }
  for k, val in pairs(v) do
    result[k] = deep_copy(val)
  end
  return result
end
local deep_eq
deep_eq = function(a, b)
  if not (type(a) == 'table' or type(b) == 'table') then
    return a == b
  end
  if not (type(a) == 'table' and type(b) == 'table') then
    return false
  end
  for k, v in pairs(a) do
    if not (deep_eq(v, b[k])) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end
R.describe("app_plan — règle 7 : version", function()
  R.it("règle 7 : version inférieure refusée → erreur, listes vides", function()
    local app = {
      id = 'org.test.app',
      name = 'T',
      version = '1.9.0',
      description = ''
    }
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'N')
    }, app), mk_local({
      {
        key = 'space:a',
        fp = 'C'
      }
    }), {
      installed_version = '1.10.0'
    })
    R.ok(#plan.errors > 0)
    return all_lists_empty(plan)
  end)
  R.it("règle 7 : comparaison semver numérique 1.10.0 > 1.9.0 (mise à jour autorisée)", function()
    local app = {
      id = 'org.test.app',
      name = 'T',
      version = '1.10.0',
      description = ''
    }
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'N')
    }, app), { }, {
      installed_version = '1.9.0'
    })
    R.eq(#plan.errors, 0)
    return eq_list(keys_of(plan.create), {
      'space:a'
    }, 'create')
  end)
  R.it("règle 7 : version égale autorisée", function()
    local plan = plan_update({ }, mk_pkg({ }), { }, {
      installed_version = '1.0.0'
    })
    return R.eq(#plan.errors, 0)
  end)
  R.it("règle 7 : downgrade autorisé si allow_downgrade", function()
    local app = {
      id = 'org.test.app',
      name = 'T',
      version = '1.9.0',
      description = ''
    }
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'N')
    }, app), { }, {
      installed_version = '1.10.0',
      allow_downgrade = true
    })
    R.eq(#plan.errors, 0)
    return eq_list(keys_of(plan.create), {
      'space:a'
    }, 'create')
  end)
  R.it("règle 7 : app.id absent → erreur, listes vides", function()
    local app = {
      name = 'T',
      version = '1.0.0',
      description = ''
    }
    local plan = plan_update({ }, mk_pkg({
      item('space', 'space:a', 'N')
    }, app), { }, { })
    R.ok(#plan.errors > 0)
    return all_lists_empty(plan)
  end)
  R.it("règle 7 : item sans type → erreur, listes vides", function()
    local plan = plan_update({ }, mk_pkg({
      {
        key = 'space:a',
        content = { },
        fingerprint = 'N'
      }
    }), { }, { })
    R.ok(#plan.errors > 0)
    return all_lists_empty(plan)
  end)
  R.it("règle 7 : item sans key → erreur, listes vides", function()
    local plan = plan_update({ }, mk_pkg({
      {
        type = 'space',
        content = { },
        fingerprint = 'N'
      }
    }), { }, { })
    R.ok(#plan.errors > 0)
    return all_lists_empty(plan)
  end)
  return R.it("règle 7 : item sans fingerprint → erreur, listes vides", function()
    local plan = plan_update({ }, mk_pkg({
      {
        type = 'space',
        key = 'space:a',
        content = { }
      }
    }), { }, { })
    R.ok(#plan.errors > 0)
    return all_lists_empty(plan)
  end)
end)
return R.describe("app_plan — règle 8 : déterminisme", function()
  R.it("règle 8 : les listes create/unchanged sont triées par clé", function()
    local pkg = mk_pkg({
      item('space', 'space:c', 'fc'),
      item('space', 'space:a', 'fa'),
      item('space', 'space:b', 'fb')
    })
    local plan = plan_update({ }, pkg, { }, { })
    return eq_list(keys_of(plan.create), {
      'space:a',
      'space:b',
      'space:c'
    }, 'create')
  end)
  R.it("règle 8 : la liste obsolete est triée par clé", function()
    local inst = mk_installed({
      {
        key = 'space:z',
        type = 'space',
        fp = 'L'
      },
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      },
      {
        key = 'space:m',
        type = 'space',
        fp = 'L'
      }
    })
    local plan = plan_update(inst, mk_pkg({ }), { }, { })
    return eq_list(plan.obsolete, {
      'space:a',
      'space:m',
      'space:z'
    }, 'obsolete')
  end)
  R.it("règle 8 : la liste rename est triée par ancienne clé", function()
    local inst = mk_installed({
      {
        key = 'space:z',
        type = 'space',
        fp = 'L'
      },
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    })
    local pkg = mk_pkg({
      item('space', 'space:new1', 'N', 'space:z'),
      item('space', 'space:new2', 'N', 'space:a')
    })
    local plan = plan_update(inst, pkg, mk_local({
      {
        key = 'space:z',
        fp = 'L'
      },
      {
        key = 'space:a',
        fp = 'L'
      }
    }), { })
    R.eq(#plan.rename, 2)
    R.eq(plan.rename[1][1], 'space:a')
    return R.eq(plan.rename[2][1], 'space:z')
  end)
  return R.it("règle 8 : la fonction ne modifie pas ses arguments", function()
    local inst = mk_installed({
      {
        key = 'space:a',
        type = 'space',
        fp = 'L'
      }
    })
    local pkg = mk_pkg({
      item('space', 'space:b', 'N'),
      item('space', 'space:a', 'N')
    })
    local loc = mk_local({
      {
        key = 'space:a',
        fp = 'C'
      }
    })
    local inst_before = deep_copy(inst)
    local pkg_before = deep_copy(pkg)
    local loc_before = deep_copy(loc)
    plan_update(inst, pkg, loc, { })
    R.ok(deep_eq(inst, inst_before), 'installed intact')
    R.ok(deep_eq(pkg, pkg_before), 'package intact')
    return R.ok(deep_eq(loc, loc_before), 'local_states intact')
  end)
end)
