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
return R.describe("app_plan — règle 4 : renamed_from", function()
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
