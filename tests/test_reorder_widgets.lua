local R = require('tests.runner')
local cvr = require('resolvers.custom_view_resolvers')
local auth = require('core.auth')
local spaces = require('core.spaces')
local yaml = require('yaml')
local SUFFIX = tostring(math.random(100000, 999999))
local CV_NAME = "test_reorder_cv_" .. tostring(SUFFIX)
local SPACE_NAME = "test_reorder_space_" .. tostring(SUFFIX)
local cv_id, space_id, plugin_cv_id
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
R.describe("ReorderWidgets — setup test space", function()
  return R.it("create test space for reorder tests", function()
    local space = spaces.create_user_space(SPACE_NAME, 'Test space for reorder', CTX.user_id)
    R.ok(space)
    R.ok(space.id)
    R.eq(space.name, SPACE_NAME)
    space_id = space.id
    spaces.add_field(space_id, 'id', 'Sequence')
    return spaces.add_field(space_id, 'name', 'String', false, '')
  end)
end)
R.describe("ReorderWidgets — creation", function()
  return R.it("createCustomView with multiple widgets", function()
    local yaml_content = [[layout:
  direction: vertical
  children:
    - widget:
        id: widget1
        title: First Widget
        space: #{SPACE_NAME}
        position: 1
    - widget:
        id: widget2
        title: Second Widget
        space: #{SPACE_NAME}
        position: 2
    - widget:
        id: widget3
        title: Third Widget
        space: #{SPACE_NAME}
        position: 3
]]
    local res = cvr.Mutation.createCustomView({ }, {
      name = CV_NAME,
      description = 'test',
      yaml = yaml_content
    }, CTX)
    R.ok(res)
    R.ok(res.id)
    cv_id = res.id
  end)
end)
R.describe("ReorderWidgets — basic reordering", function()
  R.it("reorderWidgets changes widget order", function()
    local widget_positions = {
      {
        widgetId = 'widget2',
        index = 1
      },
      {
        widgetId = 'widget1',
        index = 2
      },
      {
        widgetId = 'widget3',
        index = 3
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res)
    R.ok(res.id, cv_id)
    R.ok(res.yaml)
    R.ok(res.yaml:find("id: widget2"), "widget2 should be first")
    R.ok(res.yaml:find("id: widget1"), "widget1 should be second")
    R.ok(res.yaml:find("id: widget3"), "widget3 should be third")
    R.ok(res.yaml:find("position: 1"), "first widget should have position 1")
    R.ok(res.yaml:find("position: 2"), "second widget should have position 2")
    return R.ok(res.yaml:find("position: 3"), "third widget should have position 3")
  end)
  return R.it("reorderWidgets with same order keeps same YAML", function()
    local widget_positions = {
      {
        widgetId = 'widget2',
        index = 1
      },
      {
        widgetId = 'widget1',
        index = 2
      },
      {
        widgetId = 'widget3',
        index = 3
      }
    }
    local original_view = cvr.Query.customView({ }, {
      id = cv_id
    }, CTX)
    local original_yaml = original_view.yaml
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res)
    return R.eq(res.yaml, original_yaml)
  end)
end)
R.describe("ReorderWidgets — widget personnalisé (plugin)", function()
  return R.it("reorderWidgets keeps type and params of plugin widgets", function()
    local yaml_content = "layout:\n" .. "  direction: vertical\n" .. "  children:\n" .. "    - widget:\n" .. "        id: plugin_w\n" .. "        title: Calendrier\n" .. ("        space: " .. tostring(SPACE_NAME) .. "\n") .. "        position: 1\n" .. "        type: mon_plugin\n" .. "        params:\n" .. "          couleur: '#c33'\n" .. "    - zone:\n" .. "        id: zone_a\n" .. "        title: Zone A\n" .. "        direction: vertical\n" .. "        children:\n" .. "          - widget:\n" .. "              id: plugin_in_zone\n" .. "              title: Dans une zone\n" .. ("              space: " .. tostring(SPACE_NAME) .. "\n") .. "              position: 1\n" .. "              type: mon_plugin\n" .. "              params:\n" .. "                titre: Zone\n"
    local created = cvr.Mutation.createCustomView({ }, {
      name = tostring(CV_NAME) .. "_plugin",
      yaml = yaml_content
    }, CTX)
    R.ok(created)
    plugin_cv_id = created.id
    local widget_positions = {
      {
        widgetId = 'plugin_w',
        index = 2
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = plugin_cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res.yaml)
    local parsed = yaml.decode(res.yaml)
    local widgets = { }
    local collect
    collect = function(node)
      if not (type(node) == 'table') then
        return 
      end
      if node.widget then
        table.insert(widgets, node.widget)
      end
      for key, value in pairs(node) do
        if key ~= 'widget' then
          collect(value)
        end
      end
    end
    collect(parsed.layout)
    local by_id = { }
    for _index_0 = 1, #widgets do
      local w = widgets[_index_0]
      by_id[w.id] = w
    end
    R.ok(by_id.plugin_w, "le widget racine doit survivre au réordonnancement")
    R.eq(by_id.plugin_w.type, 'mon_plugin')
    R.eq(by_id.plugin_w.params.couleur, '#c33')
    R.ok(by_id.plugin_in_zone, "le widget de la zone doit survivre au réordonnancement")
    R.eq(by_id.plugin_in_zone.type, 'mon_plugin')
    return R.eq(by_id.plugin_in_zone.params.titre, 'Zone')
  end)
end)
R.describe("ReorderWidgets — error handling", function()
  R.it("reorderWidgets on unknown page -> error", function()
    local widget_positions = {
      {
        widgetId = 'widget1',
        index = 1
      }
    }
    return R.raises((function()
      return cvr.Mutation.reorderWidgets({ }, {
        pageId = 'no-such-id',
        widgetPositions = widget_positions
      }, CTX)
    end), 'not found')
  end)
  R.it("reorderWidgets with invalid widget ID -> error", function()
    local widget_positions = {
      {
        widgetId = 'invalid-widget',
        index = 1
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    return R.ok(res)
  end)
  return R.it("reorderWidgets with empty positions -> no change", function()
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = { }
    }, CTX)
    R.ok(res)
    return R.ok(res.yaml)
  end)
end)
R.describe("ReorderWidgets — edge cases", function()
  R.it("reorderWidgets reverse order", function()
    local widget_positions = {
      {
        widgetId = 'widget3',
        index = 1
      },
      {
        widgetId = 'widget1',
        index = 2
      },
      {
        widgetId = 'widget2',
        index = 3
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res)
    local lines = res.yaml:split('\n')
    local widget1_pos = nil
    local widget2_pos = nil
    local widget3_pos = nil
    for i, line in ipairs(lines) do
      if line:match("id: widget1") then
        widget1_pos = i
      end
      if line:match("id: widget2") then
        widget2_pos = i
      end
      if line:match("id: widget3") then
        widget3_pos = i
      end
    end
    R.ok(widget3_pos < widget1_pos, "widget3 should come before widget1")
    return R.ok(widget1_pos < widget2_pos, "widget1 should come before widget2")
  end)
  return R.it("reorderWidgets with partial positions", function()
    local widget_positions = {
      {
        widgetId = 'widget1',
        index = 1
      },
      {
        widgetId = 'widget3',
        index = 2
      }
    }
    local res = cvr.Mutation.reorderWidgets({ }, {
      pageId = cv_id,
      widgetPositions = widget_positions
    }, CTX)
    R.ok(res)
    return R.ok(res.yaml)
  end)
end)
return R.describe("ReorderWidgets — cleanup", function()
  return R.it("cleanup test space and page", function()
    if plugin_cv_id then
      cvr.Mutation.deleteCustomView({ }, {
        id = plugin_cv_id
      }, CTX)
    end
    if cv_id then
      cvr.Mutation.deleteCustomView({ }, {
        id = cv_id
      }, CTX)
    end
    if space_id then
      return spaces.delete_user_space(space_id)
    end
  end)
end)
