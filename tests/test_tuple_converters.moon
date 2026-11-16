-- tests/test_tuple_converters.moon
-- Tuple→table converters: exact keys and values for each public reader.
-- Entities are created via existing public functions; expectations are built
-- independently of the converters under test (raw tuple columns / known values).

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
perms_mod  = require 'core.permissions'
auth_mod   = require 'core.auth'
views_mod  = require 'core.views'
data_views = require 'core.data_views'
cvcr       = require 'resolvers.custom_view_crud'
wpr        = require 'resolvers.widget_plugin_resolvers'
schema_r   = require 'resolvers.schema_resolvers'
auth_r     = require 'resolvers.auth_resolvers'
{ :trusted_ctx } = require 'resolvers.utils'

SUFFIX = tostring math.random 100000, 999999
SP_NAME = "tuple_sp_#{SUFFIX}"
VIEW_NAME = "tuple_view_#{SUFFIX}"
CV_NAME = "tuple_cv_#{SUFFIX}"
DV_NAME = "tuple_dv_#{SUFFIX}"
PLUGIN_NAME = "tuple_plugin_#{SUFFIX}"
GROUP_NAME = "tuple_grp_#{SUFFIX}"
USER_NAME = "tuple_user_#{SUFFIX}"
REL_NAME = "tuple_rel_#{SUFFIX}"
REL_SRC = "tuple_rel_src_#{SUFFIX}"
REL_TGT = "tuple_rel_tgt_#{SUFFIX}"

SCRIPT_CS = "module.exports = ({ render }) -> render '<div>ok</div>'"
TEMPLATE_PUG = "div ok"
YAML_SIMPLE = "layout:\n  direction: vertical\n  children: []\n"
DV_CONFIG = '{"columns":["name"]}'
VIEW_CONFIG = { layout: { direction: 'vertical', children: {} } }

CTX = trusted_ctx 'test-user'
admin = auth_mod.get_user_by_username 'admin'
ADMIN_CTX = { user_id: admin and admin.id }

FIX = {
  space_id: nil
  group_id: nil
  user_id: nil
  view_id: nil
  cv_id: nil
  dv_id: nil
  plugin_id: nil
  rel_id: nil
  rel_src_id: nil
  rel_tgt_id: nil
  rel_fk_id: nil
  rel_seq_id: nil
}

SPACE_KEYS = {"createdAt", "description", "id", "name", "updatedAt"}
GROUP_KEYS = {"createdAt", "description", "id", "name"}
USER_KEYS  = {"createdAt", "email", "id", "must_change_password", "username"}
VIEW_KEYS  = {"config", "createdAt", "id", "name", "spaceId", "updatedAt", "viewType"}
CV_KEYS    = {"createdAt", "description", "id", "name", "updatedAt", "yaml"}
DV_KEYS    = {"config", "createdAt", "description", "id", "name", "sourceSpace", "updatedAt"}
-- `appId` est facultatif (absent/nil = bibliothèque) : vérifié à part.
PLUGIN_KEYS = {
  "createdAt", "description", "id", "manifest", "name"
  "scriptCode", "scriptLanguage", "templateCode", "templateLanguage", "updatedAt"
}
REL_KEYS = {
  "cardinality", "fromFieldId", "fromSpaceId", "id", "name"
  "reprFormula", "toFieldId", "toSpaceId"
}

sorted_keys = (t) ->
  keys = {}
  for k in pairs t
    table.insert keys, tostring k
  table.sort keys
  keys

-- R.eq uses Lua ==, which is reference equality for tables: compare key lists
-- as a single string instead.
assert_keys = (actual, expected, label) ->
  R.ok type(actual) == 'table', "#{label}: expected a table"
  R.eq table.concat(sorted_keys(actual), ','), table.concat(expected, ','), "#{label}: exact keys"

assert_eq_all = (actual, expected, label) ->
  for k, v in pairs expected
    R.eq actual[k], v, "#{label}: #{k}"

find_by_id = (list, id) ->
  for item in *list
    return item if item.id == id
  nil

-- ── Fixture setup ─────────────────────────────────────────────────────────────

R.describe "tuple converters — fixture", ->
  R.it "creates spaces, group, user, views and relation endpoints", ->
    sp = spaces_mod.create_user_space SP_NAME, 'tuple converter fixture'
    R.ok sp
    FIX.space_id = sp.id

    g = perms_mod.create_group GROUP_NAME, 'tuple group fixture'
    R.ok g
    FIX.group_id = g.id

    u = auth_mod.create_user USER_NAME, "#{USER_NAME}@test.local", "pass_#{SUFFIX}_ok"
    R.ok u
    FIX.user_id = u.id

    v = views_mod.create_view FIX.space_id, VIEW_NAME, 'grid', VIEW_CONFIG
    R.ok v
    FIX.view_id = v.id

    cv = cvcr.create_custom_view CV_NAME, 'tuple page fixture', YAML_SIMPLE
    R.ok cv
    FIX.cv_id = cv.id

    dv = data_views.create_view DV_NAME, 'tuple dv fixture', SP_NAME, DV_CONFIG
    R.ok dv
    FIX.dv_id = dv.id

    res = wpr.Mutation.createWidgetPlugin {}, {
      input: {
        name: PLUGIN_NAME
        description: 'tuple plugin fixture'
        scriptLanguage: 'coffeescript'
        templateLanguage: 'pug'
        scriptCode: SCRIPT_CS
        templateCode: TEMPLATE_PUG
      }
    }, ADMIN_CTX
    R.ok res
    FIX.plugin_id = res.id

    src = spaces_mod.create_user_space REL_SRC, 'relation source'
    tgt = spaces_mod.create_user_space REL_TGT, 'relation target'
    R.ok src
    R.ok tgt
    FIX.rel_src_id = src.id
    FIX.rel_tgt_id = tgt.id
    seq = spaces_mod.add_field tgt.id, 'seq_id', 'Sequence'
    fk  = spaces_mod.add_field src.id, 'cible_id', 'Int'
    R.ok seq
    R.ok fk
    FIX.rel_seq_id = seq.id
    FIX.rel_fk_id = fk.id
    rel = schema_r.Mutation.createRelation {}, {
      input: {
        name: REL_NAME
        fromSpaceId: src.id
        fromFieldId: fk.id
        toSpaceId: tgt.id
        toFieldId: seq.id
        reprFormula: '@nom'
      }
    }, CTX
    R.ok rel
    R.ok rel.id
    FIX.rel_id = rel.id

-- ── Spaces ────────────────────────────────────────────────────────────────────

R.describe "tuple converters — space", ->
  R.it "get_space returns the public space keys", ->
    sp = spaces_mod.get_space FIX.space_id
    R.ok sp
    assert_keys sp, SPACE_KEYS, "get_space"
    assert_eq_all sp, {
      id: FIX.space_id
      name: SP_NAME
      description: 'tuple converter fixture'
    }, "get_space values"

  R.it "list_spaces includes the same shape", ->
    found = find_by_id spaces_mod.list_spaces!, FIX.space_id
    R.ok found, "space present in list_spaces"
    assert_keys found, SPACE_KEYS, "list_spaces"
    R.eq found.name, SP_NAME

  R.it "get_space_by_name matches get_space keys", ->
    sp = spaces_mod.get_space_by_name SP_NAME
    R.ok sp
    assert_keys sp, SPACE_KEYS, "get_space_by_name"
    R.eq sp.id, FIX.space_id

-- ── Groups ────────────────────────────────────────────────────────────────────

R.describe "tuple converters — group", ->
  R.it "get_group returns the public group keys", ->
    g = perms_mod.get_group FIX.group_id
    R.ok g
    assert_keys g, GROUP_KEYS, "get_group"
    assert_eq_all g, {
      id: FIX.group_id
      name: GROUP_NAME
      description: 'tuple group fixture'
    }, "get_group values"

  R.it "list_groups includes the same shape", ->
    found = find_by_id perms_mod.list_groups!, FIX.group_id
    R.ok found, "group present in list_groups"
    assert_keys found, GROUP_KEYS, "list_groups"

-- ── Users ─────────────────────────────────────────────────────────────────────

R.describe "tuple converters — user", ->
  R.it "get_user_by_id returns the public user keys", ->
    u = auth_mod.get_user_by_id FIX.user_id
    R.ok u
    assert_keys u, USER_KEYS, "get_user_by_id"
    assert_eq_all u, {
      id: FIX.user_id
      username: USER_NAME
      email: "#{USER_NAME}@test.local"
    }, "get_user_by_id values"

  R.it "auth_resolvers users query matches get_user_by_id shape", ->
    R.ok admin, "admin fixture user exists"
    rows = auth_r.Query.users nil, nil, ADMIN_CTX
    R.ok rows
    found = find_by_id rows, FIX.user_id
    R.ok found, "user present in Query.users"
    assert_keys found, USER_KEYS, "Query.users"
    R.eq found.username, USER_NAME
    R.eq found.email, "#{USER_NAME}@test.local"

-- ── Views ─────────────────────────────────────────────────────────────────────

R.describe "tuple converters — view", ->
  R.it "get_view returns the public view keys", ->
    v = views_mod.get_view FIX.view_id
    R.ok v
    assert_keys v, VIEW_KEYS, "get_view"
    assert_eq_all v, {
      id: FIX.view_id
      spaceId: FIX.space_id
      name: VIEW_NAME
      viewType: 'grid'
    }, "get_view values"

  R.it "list_views includes the same shape", ->
    found = find_by_id views_mod.list_views(FIX.space_id), FIX.view_id
    R.ok found, "view present in list_views"
    assert_keys found, VIEW_KEYS, "list_views"
    R.eq found.viewType, 'grid'

-- ── Custom views (pages) ──────────────────────────────────────────────────────

R.describe "tuple converters — custom view", ->
  R.it "get_custom_view returns the public page keys", ->
    cv = cvcr.get_custom_view FIX.cv_id
    R.ok cv
    assert_keys cv, CV_KEYS, "get_custom_view"
    assert_eq_all cv, {
      id: FIX.cv_id
      name: CV_NAME
      description: 'tuple page fixture'
      yaml: YAML_SIMPLE
    }, "get_custom_view values"

  R.it "list_custom_views includes the same shape", ->
    found = find_by_id cvcr.list_custom_views!, FIX.cv_id
    R.ok found, "page present in list_custom_views"
    assert_keys found, CV_KEYS, "list_custom_views"
    R.eq found.yaml, YAML_SIMPLE

-- ── Data views ────────────────────────────────────────────────────────────────

R.describe "tuple converters — data view", ->
  R.it "get_view returns the public data-view keys", ->
    dv = data_views.get_view FIX.dv_id
    R.ok dv
    assert_keys dv, DV_KEYS, "data_views.get_view"
    assert_eq_all dv, {
      id: FIX.dv_id
      name: DV_NAME
      description: 'tuple dv fixture'
      sourceSpace: SP_NAME
      config: DV_CONFIG
    }, "data_views.get_view values"

-- ── Widget plugins ────────────────────────────────────────────────────────────

R.describe "tuple converters — widget plugin", ->
  R.it "widgetPlugin returns the public plugin keys", ->
    p = wpr.Query.widgetPlugin nil, { id: FIX.plugin_id }, ADMIN_CTX
    R.ok p
    R.is_nil p.appId, 'définition de bibliothèque sans appId'

    assert_keys p, PLUGIN_KEYS, "widgetPlugin"
    assert_eq_all p, {
      id: FIX.plugin_id
      name: PLUGIN_NAME
      description: 'tuple plugin fixture'
      scriptLanguage: 'coffeescript'
      templateLanguage: 'pug'
      manifest: ''
    }, "widgetPlugin values"

-- ── Relations ─────────────────────────────────────────────────────────────────

R.describe "tuple converters — relation", ->
  R.it "Query.relations returns the public relation keys", ->
    rels = schema_r.Query.relations nil, { spaceId: FIX.rel_src_id }, CTX
    R.ok rels
    found = find_by_id rels, FIX.rel_id
    R.ok found, "relation present in Query.relations"
    assert_keys found, REL_KEYS, "Query.relations"
    assert_eq_all found, {
      id: FIX.rel_id
      name: REL_NAME
      fromSpaceId: FIX.rel_src_id
      fromFieldId: FIX.rel_fk_id
      toSpaceId: FIX.rel_tgt_id
      toFieldId: FIX.rel_seq_id
      reprFormula: '@nom'
      cardinality: 'one'
    }, "Query.relations values"

  R.it "updateRelation returns the same keys", ->
    upd = schema_r.Mutation.updateRelation nil, {
      id: FIX.rel_id
      input: { reprFormula: '@title', cardinality: 'many' }
    }, CTX
    R.ok upd
    assert_keys upd, REL_KEYS, "updateRelation"
    assert_eq_all upd, {
      id: FIX.rel_id
      name: REL_NAME
      fromSpaceId: FIX.rel_src_id
      fromFieldId: FIX.rel_fk_id
      toSpaceId: FIX.rel_tgt_id
      toFieldId: FIX.rel_seq_id
      reprFormula: '@title'
      cardinality: 'many'
    }, "updateRelation values"

-- ── Cleanup ───────────────────────────────────────────────────────────────────

R.describe "tuple converters — cleanup", ->
  R.it "removes fixtures", ->
    if FIX.rel_id
      schema_r.Mutation.deleteRelation nil, { id: FIX.rel_id }, CTX
    if FIX.plugin_id
      wpr.Mutation.deleteWidgetPlugin nil, { id: FIX.plugin_id }, ADMIN_CTX
    if FIX.dv_id
      data_views.delete_view FIX.dv_id
    if FIX.cv_id
      cvcr.delete_custom_view FIX.cv_id
    if FIX.view_id
      views_mod.delete_view FIX.view_id
    if FIX.user_id
      box.space._tdb_users\delete FIX.user_id
    if FIX.group_id
      perms_mod.delete_group FIX.group_id
    if FIX.rel_src_id
      sp = spaces_mod.get_space FIX.rel_src_id
      spaces_mod.delete_user_space sp.name if sp
    if FIX.rel_tgt_id
      sp = spaces_mod.get_space FIX.rel_tgt_id
      spaces_mod.delete_user_space sp.name if sp
    if FIX.space_id
      spaces_mod.delete_user_space SP_NAME
    R.ok true, "cleanup done"
