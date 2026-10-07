local R = require('tests.runner')
local spaces = require('core.spaces')
local views = require('core.views')
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local SPACE_NAME = "test_views_core_" .. tostring(SUFFIX)
local VIEW_NAME = "tvc_" .. tostring(SUFFIX)
local VALID_CONFIG = {
  layout = {
    direction = 'vertical',
    children = { }
  }
}
local FIX = {
  sid = nil,
  created = { }
}
R.describe("core/views — fixture", function()
  return R.it("creates the test space", function()
    local sp = spaces.create_user_space(SPACE_NAME, 'fixture for core/views tests')
    R.ok(sp)
    R.ok(sp.id)
    FIX.sid = sp.id
  end)
end)
R.describe("core/views — create_view validates its config", function()
  R.it("create_view with a valid config inserts the row", function()
    local v = views.create_view(FIX.sid, VIEW_NAME, 'grid', VALID_CONFIG)
    R.ok(v, "create_view must return the created view")
    R.ok(v.id, "created view id")
    R.eq(v.name, VIEW_NAME)
    R.eq(v.viewType, 'grid')
    R.eq(v.spaceId, FIX.sid)
    local row = box.space._tdb_views:get(v.id)
    R.ok(row, "row present in _tdb_views")
    local decoded = json.decode(row[5])
    R.eq(decoded.layout.direction, 'vertical')
    return table.insert(FIX.created, v.id)
  end)
  return R.it("create_view with an invalid config raises the validation message", function()
    return R.raises((function()
      return views.create_view(FIX.sid, tostring(VIEW_NAME) .. "_bad", 'grid', { })
    end), 'layout')
  end)
end)
R.describe("core/views — update_view writes config_str", function()
  local upd = {
    id = nil,
    name = tostring(VIEW_NAME) .. "_upd"
  }
  R.it("creates the view used by the update tests", function()
    local v = views.create_view(FIX.sid, upd.name, 'grid', VALID_CONFIG)
    R.ok(v)
    upd.id = v.id
    return table.insert(FIX.created, v.id)
  end)
  R.it("update_view with a new config replaces the stored config", function()
    local new_config = {
      layout = {
        direction = 'horizontal',
        children = { }
      }
    }
    views.update_view(upd.id, {
      config = new_config
    })
    local row = box.space._tdb_views:get(upd.id)
    R.ok(row, "row still present after update")
    local decoded = json.decode(row[5])
    R.eq(decoded.layout.direction, 'horizontal')
    return R.eq(views.get_view(upd.id).config, row[5], "get_view returns the stored config")
  end)
  return R.it("update_view without config keeps the stored config and updates the name", function()
    local before_cfg = box.space._tdb_views:get(upd.id)[5]
    views.update_view(upd.id, {
      name = tostring(upd.name) .. "_v2"
    })
    local row = box.space._tdb_views:get(upd.id)
    R.eq(row[3], tostring(upd.name) .. "_v2", "name updated")
    return R.eq(row[5], before_cfg, "config preserved when patch.config is absent")
  end)
end)
return R.describe("core/views — cleanup", function()
  return R.it("removes the fixture view rows and the test space", function()
    local _list_0 = FIX.created
    for _index_0 = 1, #_list_0 do
      local id = _list_0[_index_0]
      box.space._tdb_views:delete(id)
    end
    return spaces.delete_user_space(SPACE_NAME)
  end)
end)
