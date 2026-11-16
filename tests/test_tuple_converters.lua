local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local perms_mod = require('core.permissions')
local auth_mod = require('core.auth')
local views_mod = require('core.views')
local data_views = require('core.data_views')
local cvcr = require('resolvers.custom_view_crud')
local wpr = require('resolvers.widget_plugin_resolvers')
local schema_r = require('resolvers.schema_resolvers')
local auth_r = require('resolvers.auth_resolvers')
local trusted_ctx
trusted_ctx = require('resolvers.utils').trusted_ctx
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "tuple_sp_" .. tostring(SUFFIX)
local VIEW_NAME = "tuple_view_" .. tostring(SUFFIX)
local CV_NAME = "tuple_cv_" .. tostring(SUFFIX)
local DV_NAME = "tuple_dv_" .. tostring(SUFFIX)
local PLUGIN_NAME = "tuple_plugin_" .. tostring(SUFFIX)
local GROUP_NAME = "tuple_grp_" .. tostring(SUFFIX)
local USER_NAME = "tuple_user_" .. tostring(SUFFIX)
local REL_NAME = "tuple_rel_" .. tostring(SUFFIX)
local REL_SRC = "tuple_rel_src_" .. tostring(SUFFIX)
local REL_TGT = "tuple_rel_tgt_" .. tostring(SUFFIX)
local SCRIPT_CS = "module.exports = ({ render }) -> render '<div>ok</div>'"
local TEMPLATE_PUG = "div ok"
local YAML_SIMPLE = "layout:\n  direction: vertical\n  children: []\n"
local DV_CONFIG = '{"columns":["name"]}'
local VIEW_CONFIG = {
  layout = {
    direction = 'vertical',
    children = { }
  }
}
local CTX = trusted_ctx('test-user')
local admin = auth_mod.get_user_by_username('admin')
local ADMIN_CTX = {
  user_id = admin and admin.id
}
local FIX = {
  space_id = nil,
  group_id = nil,
  user_id = nil,
  view_id = nil,
  cv_id = nil,
  dv_id = nil,
  plugin_id = nil,
  rel_id = nil,
  rel_src_id = nil,
  rel_tgt_id = nil,
  rel_fk_id = nil,
  rel_seq_id = nil
}
local SPACE_KEYS = {
  "createdAt",
  "description",
  "id",
  "name",
  "updatedAt"
}
local GROUP_KEYS = {
  "createdAt",
  "description",
  "id",
  "name"
}
local USER_KEYS = {
  "createdAt",
  "email",
  "id",
  "must_change_password",
  "username"
}
local VIEW_KEYS = {
  "config",
  "createdAt",
  "id",
  "name",
  "spaceId",
  "updatedAt",
  "viewType"
}
local CV_KEYS = {
  "createdAt",
  "description",
  "id",
  "name",
  "updatedAt",
  "yaml"
}
local DV_KEYS = {
  "config",
  "createdAt",
  "description",
  "id",
  "name",
  "sourceSpace",
  "updatedAt"
}
local PLUGIN_KEYS = {
  "compiled",
  "createdAt",
  "description",
  "id",
  "manifest",
  "name",
  "scriptCode",
  "scriptLanguage",
  "templateCode",
  "templateLanguage",
  "updatedAt"
}
local REL_KEYS = {
  "cardinality",
  "fromFieldId",
  "fromSpaceId",
  "id",
  "name",
  "reprFormula",
  "toFieldId",
  "toSpaceId"
}
local sorted_keys
sorted_keys = function(t)
  local keys = { }
  for k in pairs(t) do
    table.insert(keys, tostring(k))
  end
  table.sort(keys)
  return keys
end
local assert_keys
assert_keys = function(actual, expected, label)
  R.ok(type(actual) == 'table', tostring(label) .. ": expected a table")
  return R.eq(table.concat(sorted_keys(actual), ','), table.concat(expected, ','), tostring(label) .. ": exact keys")
end
local assert_eq_all
assert_eq_all = function(actual, expected, label)
  for k, v in pairs(expected) do
    R.eq(actual[k], v, tostring(label) .. ": " .. tostring(k))
  end
end
local find_by_id
find_by_id = function(list, id)
  for _index_0 = 1, #list do
    local item = list[_index_0]
    if item.id == id then
      return item
    end
  end
  return nil
end
R.describe("tuple converters — fixture", function()
  return R.it("creates spaces, group, user, views and relation endpoints", function()
    local sp = spaces_mod.create_user_space(SP_NAME, 'tuple converter fixture')
    R.ok(sp)
    FIX.space_id = sp.id
    local g = perms_mod.create_group(GROUP_NAME, 'tuple group fixture')
    R.ok(g)
    FIX.group_id = g.id
    local u = auth_mod.create_user(USER_NAME, tostring(USER_NAME) .. "@test.local", "pass_" .. tostring(SUFFIX) .. "_ok")
    R.ok(u)
    FIX.user_id = u.id
    local v = views_mod.create_view(FIX.space_id, VIEW_NAME, 'grid', VIEW_CONFIG)
    R.ok(v)
    FIX.view_id = v.id
    local cv = cvcr.create_custom_view(CV_NAME, 'tuple page fixture', YAML_SIMPLE)
    R.ok(cv)
    FIX.cv_id = cv.id
    local dv = data_views.create_view(DV_NAME, 'tuple dv fixture', SP_NAME, DV_CONFIG)
    R.ok(dv)
    FIX.dv_id = dv.id
    local res = wpr.Mutation.createWidgetPlugin({ }, {
      input = {
        name = PLUGIN_NAME,
        description = 'tuple plugin fixture',
        scriptLanguage = 'coffeescript',
        templateLanguage = 'pug',
        scriptCode = SCRIPT_CS,
        templateCode = TEMPLATE_PUG
      }
    }, ADMIN_CTX)
    R.ok(res)
    FIX.plugin_id = res.id
    local src = spaces_mod.create_user_space(REL_SRC, 'relation source')
    local tgt = spaces_mod.create_user_space(REL_TGT, 'relation target')
    R.ok(src)
    R.ok(tgt)
    FIX.rel_src_id = src.id
    FIX.rel_tgt_id = tgt.id
    local seq = spaces_mod.add_field(tgt.id, 'seq_id', 'Sequence')
    local fk = spaces_mod.add_field(src.id, 'cible_id', 'Int')
    R.ok(seq)
    R.ok(fk)
    FIX.rel_seq_id = seq.id
    FIX.rel_fk_id = fk.id
    local rel = schema_r.Mutation.createRelation({ }, {
      input = {
        name = REL_NAME,
        fromSpaceId = src.id,
        fromFieldId = fk.id,
        toSpaceId = tgt.id,
        toFieldId = seq.id,
        reprFormula = '@nom'
      }
    }, CTX)
    R.ok(rel)
    R.ok(rel.id)
    FIX.rel_id = rel.id
  end)
end)
R.describe("tuple converters — space", function()
  R.it("get_space returns the public space keys", function()
    local sp = spaces_mod.get_space(FIX.space_id)
    R.ok(sp)
    assert_keys(sp, SPACE_KEYS, "get_space")
    return assert_eq_all(sp, {
      id = FIX.space_id,
      name = SP_NAME,
      description = 'tuple converter fixture'
    }, "get_space values")
  end)
  R.it("list_spaces includes the same shape", function()
    local found = find_by_id(spaces_mod.list_spaces(), FIX.space_id)
    R.ok(found, "space present in list_spaces")
    assert_keys(found, SPACE_KEYS, "list_spaces")
    return R.eq(found.name, SP_NAME)
  end)
  return R.it("get_space_by_name matches get_space keys", function()
    local sp = spaces_mod.get_space_by_name(SP_NAME)
    R.ok(sp)
    assert_keys(sp, SPACE_KEYS, "get_space_by_name")
    return R.eq(sp.id, FIX.space_id)
  end)
end)
R.describe("tuple converters — group", function()
  R.it("get_group returns the public group keys", function()
    local g = perms_mod.get_group(FIX.group_id)
    R.ok(g)
    assert_keys(g, GROUP_KEYS, "get_group")
    return assert_eq_all(g, {
      id = FIX.group_id,
      name = GROUP_NAME,
      description = 'tuple group fixture'
    }, "get_group values")
  end)
  return R.it("list_groups includes the same shape", function()
    local found = find_by_id(perms_mod.list_groups(), FIX.group_id)
    R.ok(found, "group present in list_groups")
    return assert_keys(found, GROUP_KEYS, "list_groups")
  end)
end)
R.describe("tuple converters — user", function()
  R.it("get_user_by_id returns the public user keys", function()
    local u = auth_mod.get_user_by_id(FIX.user_id)
    R.ok(u)
    assert_keys(u, USER_KEYS, "get_user_by_id")
    return assert_eq_all(u, {
      id = FIX.user_id,
      username = USER_NAME,
      email = tostring(USER_NAME) .. "@test.local"
    }, "get_user_by_id values")
  end)
  return R.it("auth_resolvers users query matches get_user_by_id shape", function()
    R.ok(admin, "admin fixture user exists")
    local rows = auth_r.Query.users(nil, nil, ADMIN_CTX)
    R.ok(rows)
    local found = find_by_id(rows, FIX.user_id)
    R.ok(found, "user present in Query.users")
    assert_keys(found, USER_KEYS, "Query.users")
    R.eq(found.username, USER_NAME)
    return R.eq(found.email, tostring(USER_NAME) .. "@test.local")
  end)
end)
R.describe("tuple converters — view", function()
  R.it("get_view returns the public view keys", function()
    local v = views_mod.get_view(FIX.view_id)
    R.ok(v)
    assert_keys(v, VIEW_KEYS, "get_view")
    return assert_eq_all(v, {
      id = FIX.view_id,
      spaceId = FIX.space_id,
      name = VIEW_NAME,
      viewType = 'grid'
    }, "get_view values")
  end)
  return R.it("list_views includes the same shape", function()
    local found = find_by_id(views_mod.list_views(FIX.space_id), FIX.view_id)
    R.ok(found, "view present in list_views")
    assert_keys(found, VIEW_KEYS, "list_views")
    return R.eq(found.viewType, 'grid')
  end)
end)
R.describe("tuple converters — custom view", function()
  R.it("get_custom_view returns the public page keys", function()
    local cv = cvcr.get_custom_view(FIX.cv_id)
    R.ok(cv)
    assert_keys(cv, CV_KEYS, "get_custom_view")
    return assert_eq_all(cv, {
      id = FIX.cv_id,
      name = CV_NAME,
      description = 'tuple page fixture',
      yaml = YAML_SIMPLE
    }, "get_custom_view values")
  end)
  return R.it("list_custom_views includes the same shape", function()
    local found = find_by_id(cvcr.list_custom_views(), FIX.cv_id)
    R.ok(found, "page present in list_custom_views")
    assert_keys(found, CV_KEYS, "list_custom_views")
    return R.eq(found.yaml, YAML_SIMPLE)
  end)
end)
R.describe("tuple converters — data view", function()
  return R.it("get_view returns the public data-view keys", function()
    local dv = data_views.get_view(FIX.dv_id)
    R.ok(dv)
    assert_keys(dv, DV_KEYS, "data_views.get_view")
    return assert_eq_all(dv, {
      id = FIX.dv_id,
      name = DV_NAME,
      description = 'tuple dv fixture',
      sourceSpace = SP_NAME,
      config = DV_CONFIG
    }, "data_views.get_view values")
  end)
end)
R.describe("tuple converters — widget plugin", function()
  return R.it("widgetPlugin returns the public plugin keys", function()
    local p = wpr.Query.widgetPlugin(nil, {
      id = FIX.plugin_id
    }, ADMIN_CTX)
    R.ok(p)
    R.is_nil(p.appId, 'définition de bibliothèque sans appId')
    assert_keys(p, PLUGIN_KEYS, "widgetPlugin")
    return assert_eq_all(p, {
      id = FIX.plugin_id,
      name = PLUGIN_NAME,
      description = 'tuple plugin fixture',
      scriptLanguage = 'coffeescript',
      templateLanguage = 'pug',
      manifest = ''
    }, "widgetPlugin values")
  end)
end)
R.describe("tuple converters — relation", function()
  R.it("Query.relations returns the public relation keys", function()
    local rels = schema_r.Query.relations(nil, {
      spaceId = FIX.rel_src_id
    }, CTX)
    R.ok(rels)
    local found = find_by_id(rels, FIX.rel_id)
    R.ok(found, "relation present in Query.relations")
    assert_keys(found, REL_KEYS, "Query.relations")
    return assert_eq_all(found, {
      id = FIX.rel_id,
      name = REL_NAME,
      fromSpaceId = FIX.rel_src_id,
      fromFieldId = FIX.rel_fk_id,
      toSpaceId = FIX.rel_tgt_id,
      toFieldId = FIX.rel_seq_id,
      reprFormula = '@nom',
      cardinality = 'one'
    }, "Query.relations values")
  end)
  return R.it("updateRelation returns the same keys", function()
    local upd = schema_r.Mutation.updateRelation(nil, {
      id = FIX.rel_id,
      input = {
        reprFormula = '@title',
        cardinality = 'many'
      }
    }, CTX)
    R.ok(upd)
    assert_keys(upd, REL_KEYS, "updateRelation")
    return assert_eq_all(upd, {
      id = FIX.rel_id,
      name = REL_NAME,
      fromSpaceId = FIX.rel_src_id,
      fromFieldId = FIX.rel_fk_id,
      toSpaceId = FIX.rel_tgt_id,
      toFieldId = FIX.rel_seq_id,
      reprFormula = '@title',
      cardinality = 'many'
    }, "updateRelation values")
  end)
end)
return R.describe("tuple converters — cleanup", function()
  return R.it("removes fixtures", function()
    if FIX.rel_id then
      schema_r.Mutation.deleteRelation(nil, {
        id = FIX.rel_id
      }, CTX)
    end
    if FIX.plugin_id then
      wpr.Mutation.deleteWidgetPlugin(nil, {
        id = FIX.plugin_id
      }, ADMIN_CTX)
    end
    if FIX.dv_id then
      data_views.delete_view(FIX.dv_id)
    end
    if FIX.cv_id then
      cvcr.delete_custom_view(FIX.cv_id)
    end
    if FIX.view_id then
      views_mod.delete_view(FIX.view_id)
    end
    if FIX.user_id then
      box.space._tdb_users:delete(FIX.user_id)
    end
    if FIX.group_id then
      perms_mod.delete_group(FIX.group_id)
    end
    if FIX.rel_src_id then
      local sp = spaces_mod.get_space(FIX.rel_src_id)
      if sp then
        spaces_mod.delete_user_space(sp.name)
      end
    end
    if FIX.rel_tgt_id then
      local sp = spaces_mod.get_space(FIX.rel_tgt_id)
      if sp then
        spaces_mod.delete_user_space(sp.name)
      end
    end
    if FIX.space_id then
      spaces_mod.delete_user_space(SP_NAME)
    end
    return R.ok(true, "cleanup done")
  end)
end)
