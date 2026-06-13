-- tests/test_data_views.moon
R = require 'tests.runner'
log = require 'log'
json = require 'json'
resolvers    = require 'resolvers.data_view_resolvers'
data_r       = require 'resolvers.data_resolvers'
spaces_mod   = require 'core.spaces'
executor     = require 'core.data_views_executor'

-- Setup test spaces
sp1_id = nil

R.describe "DataViews — system storage", ->
  R.it "setup test space", ->
    s1 = spaces_mod.create_user_space 'dv_test_users'
    sp1_id = s1.id
    spaces_mod.add_field s1.id, 'name', 'String'
    spaces_mod.add_field s1.id, 'age', 'Int'
    spaces_mod.add_field s1.id, 'role', 'String'

    -- Insert records
    data_r.Mutation.insertRecords nil, {
      spaceId: sp1_id,
      data: {
        { name: "Alice", age: 30, role: "Admin" }
        { name: "Bob",   age: 25, role: "User" }
        { name: "Charlie", age: 35, role: "User" }
      }
    }, { user_id: 'admin' }

  R.it "create view returns metadata", ->
    config = {
      columns: {"name", {field: "age", as: "user_age"}}
      filter: {
        field: "role"
        op: "EQ"
        value: "User"
      }
      orderBy: { {field: "age", desc: true} }
    }
    
    ctx = { user_id: 'admin' }
    args = {
      input: {
        name: "test_view_1"
        sourceSpace: "dv_test_users"
        config: json.encode(config)
      }
    }
    
    res = resolvers.Mutation.createDataView nil, args, ctx
    R.eq res.name, "test_view_1"
    R.eq res.config, json.encode(config)

  R.it "execute view returns filtered/sorted data", ->
    ctx = { user_id: 'admin' }
    -- Fetch the view
    views = resolvers.Query.dataViews nil, nil, ctx
    dv_id = views[#views].id
    
    -- Execute
    res = resolvers.Query.executeDataView nil, { id: dv_id }, ctx
    
    -- Should filter out Admin, return Charlie(35) then Bob(25) due to order desc
    R.eq #res, 2
    R.eq res[1].name, "Charlie"
    R.eq res[1].user_age, 35
    R.eq res[2].name, "Bob"

  R.it "aggregates (GROUP BY)", ->
    config = {
      groupBy: {"role"}
      aggregates: {
        { field: "age", fn: "sum", as: "total_age" }
        { field: "age", fn: "avg", as: "avg_age" }
        { fn: "count", as: "user_count" }
      }
    }
    
    ctx = { user_id: 'admin' }
    args = {
      input: {
        name: "test_view_agg"
        sourceSpace: "dv_test_users"
        config: json.encode(config)
      }
    }
    res = resolvers.Mutation.createDataView nil, args, ctx
    
    exec_res = resolvers.Query.executeDataView nil, { id: res.id }, ctx
    R.eq #exec_res, 2
    
    for row in *exec_res
      if row.role == "Admin"
        R.eq row.user_count, 1
        R.eq row.total_age, 30
      elseif row.role == "User"
        R.eq row.user_count, 2
        R.eq row.total_age, 60
        R.eq row.avg_age, 30

  -- Régression : le frontend stocke sourceSpace = id de l'espace (UUID),
  -- pas son nom. L'exécuteur doit résoudre l'espace par id comme par nom.
  R.it "execute view works when sourceSpace is the space id (frontend behaviour)", ->
    ctx = { user_id: 'admin' }
    args = {
      input: {
        name: "test_view_by_id"
        sourceSpace: sp1_id      -- id (UUID), comme envoyé par le frontend
        config: json.encode { columns: {"name", "age"} }
      }
    }
    res = resolvers.Mutation.createDataView nil, args, ctx
    R.eq res.sourceSpace, sp1_id

    exec_res = resolvers.Query.executeDataView nil, { id: res.id }, ctx
    R.eq #exec_res, 3   -- les 3 enregistrements, sans erreur "Source space not found"

  R.it "execute_view resolves a space passed by name too", ->
    res = executor.execute_view 'dv_test_users', json.encode({ columns: {"name"} }), {}
    R.eq #res, 3

  R.it "cleanup", ->
    ctx = { user_id: 'admin' }
    views = resolvers.Query.dataViews nil, nil, ctx
    for v in *views
      resolvers.Mutation.deleteDataView nil, { id: v.id }, ctx
    spaces_mod.delete_user_space sp1_id
