local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local presets = require('core.view_presets')
local app_package = require('core.app_package')
local crud = require('resolvers.custom_view_crud')
local export_r = require('resolvers.export_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "ppc_space_" .. tostring(SUFFIX)
local PAGE_NAME = "ppc_page_" .. tostring(SUFFIX)
local sp_id = nil
local page = nil
local scope_w1 = nil
local ghost_page_id = "ghost-page-" .. tostring(SUFFIX)
local ghost_space_id = "ghost-space-" .. tostring(SUFFIX)
local portable_page_scope
portable_page_scope = function(name, widget_id)
  return "widget:" .. tostring(name) .. ":" .. tostring(widget_id)
end
return R.describe("Préréglages — cascade à la suppression d'une page", function()
  R.it("setup : espace, page et préréglages de deux widgets", function()
    local sp = spaces_mod.create_user_space(SP_NAME, 'preset page cascade fixture')
    sp_id = sp.id
    page = crud.create_custom_view(PAGE_NAME, 'page fixture', "title: " .. tostring(PAGE_NAME) .. "\n")
    R.ok(page.id)
    scope_w1 = "widget:" .. tostring(page.id) .. ":w1"
    local a = presets.save_preset(scope_w1, sp_id, 'Alpha', '', '[]')
    local b = presets.save_preset("widget:" .. tostring(page.id) .. ":w2", sp_id, 'Bêta', 'self.x > 0', '[]')
    R.ok(a.id)
    R.ok(b.id)
    return R.eq(#presets.list_presets(scope_w1), 1)
  end)
  R.it("deleteCustomView emporte les préréglages de ses widgets", function()
    R.ok(crud.delete_custom_view(page.id))
    R.is_nil(crud.get_custom_view(page.id))
    R.eq(#presets.list_presets(scope_w1), 0, 'plus aucun préréglage pour le widget w1')
    R.eq(#presets.list_presets("widget:" .. tostring(page.id) .. ":w2"), 0, 'plus aucun préréglage pour le widget w2')
    local leftover = { }
    local _list_0 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local prefix = "widget:" .. tostring(page.id) .. ":"
      if type(t[2]) == 'string' and t[2]:sub(1, #prefix) == prefix then
        table.insert(leftover, t[2])
      end
    end
    return R.eq(#leftover, 0, "préréglage(s) orphelin(s) restant(s) : " .. tostring(leftover[1]))
  end)
  R.it("build_package ignore un préréglage dont la page n'existe plus", function()
    local ghost_scope = portable_page_scope(ghost_page_id, 'w1')
    presets.save_preset(ghost_scope, sp_id, 'Fantôme', '', '[]')
    R.eq(#presets.list_presets(ghost_scope), 1, 'préréglage orphelin présent en base')
    local built = app_package.build_package({
      id = 'ppc',
      name = 'ppc',
      version = '1'
    }, { })
    local exported = { }
    local _list_0 = built.items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      if item.type == 'preset' and tostring(item.content.scope):find(ghost_page_id, 1, true) then
        table.insert(exported, item.key)
      end
    end
    R.eq(#exported, 0, "préréglage orphelin exporté : " .. tostring(exported[1]))
    return R.is_nil(app_package.describe_local('preset', "preset:" .. tostring(app_package.key_part(ghost_scope)) .. "|Fantôme"), 'le préréglage orphelin ne se décrit pas localement')
  end)
  R.it("build_snapshot ignore un préréglage orphelin (page ou espace disparu)", function()
    local ghost_page_scope = portable_page_scope(ghost_page_id, 'w1')
    local ghost_space_scope = "space:" .. tostring(ghost_space_id)
    local now = os.time()
    box.space._tdb_view_presets:insert({
      "ppc-ghost-space-" .. tostring(SUFFIX),
      ghost_space_scope,
      ghost_space_id,
      'Perdu',
      '',
      '[]',
      now,
      now
    })
    local snap = export_r.build_snapshot(false)
    local orphans = { }
    local _list_0 = snap.schema.view_presets
    for _index_0 = 1, #_list_0 do
      local entry = _list_0[_index_0]
      local scope = tostring(entry.scope)
      if scope:find(ghost_page_id, 1, true) or scope:find(ghost_space_id, 1, true) then
        table.insert(orphans, scope)
      end
    end
    R.eq(#orphans, 0, "préréglage(s) orphelin(s) exporté(s) : " .. tostring(orphans[1]))
    local built = app_package.build_package({
      id = 'ppc',
      name = 'ppc',
      version = '1'
    }, { })
    local _list_1 = built.items
    for _index_0 = 1, #_list_1 do
      local _continue_0 = false
      repeat
        local item = _list_1[_index_0]
        if not (item.type == 'preset') then
          _continue_0 = true
          break
        end
        local local_scope = app_package.preset_scope_local(item.content.scope)
        R.ok(local_scope, "scope non résoluble exporté : " .. tostring(item.content.scope))
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end)
  R.it("une page existante garde ses préréglages à l'export", function()
    local kept = crud.create_custom_view("ppc_keep_" .. tostring(SUFFIX), 'page conservée', "title: keep\n")
    local scope = "widget:" .. tostring(kept.id) .. ":w1"
    presets.save_preset(scope, sp_id, 'Gardé', '', '[]')
    local built = app_package.build_package({
      id = 'ppc',
      name = 'ppc',
      version = '1'
    }, { })
    local found = nil
    local _list_0 = built.items
    for _index_0 = 1, #_list_0 do
      local item = _list_0[_index_0]
      if item.type == 'preset' and item.content.name == 'Gardé' then
        found = item
      end
    end
    R.ok(found, 'le préréglage de la page existante doit être exporté')
    R.eq(found.content.scope, portable_page_scope("ppc_keep_" .. tostring(SUFFIX), 'w1'), 'le scope exporté porte le nom de la page')
    return crud.delete_custom_view(kept.id)
  end)
  return R.it("cleanup", function()
    local _list_0 = box.space._tdb_view_presets:select({ })
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      if t[3] == sp_id or t[3] == ghost_space_id then
        box.space._tdb_view_presets:delete(t[1])
      end
    end
    spaces_mod.delete_user_space(SP_NAME)
    return require('resolvers.init').reinit()
  end)
end)
