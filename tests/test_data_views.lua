local R = require('tests.runner')
local log = require('log')
local json = require('json')
local resolvers = require('resolvers.data_view_resolvers')
local data_r = require('resolvers.data_resolvers')
local spaces_mod = require('core.spaces')
local executor = require('core.data_views_executor')
local sp1_id = nil
return R.describe("DataViews — system storage", function()
  R.it("setup test space", function()
    local s1 = spaces_mod.create_user_space('dv_test_users')
    sp1_id = s1.id
    spaces_mod.add_field(s1.id, 'name', 'String')
    spaces_mod.add_field(s1.id, 'age', 'Int')
    spaces_mod.add_field(s1.id, 'role', 'String')
    return data_r.Mutation.insertRecords(nil, {
      spaceId = sp1_id,
      data = {
        {
          name = "Alice",
          age = 30,
          role = "Admin"
        },
        {
          name = "Bob",
          age = 25,
          role = "User"
        },
        {
          name = "Charlie",
          age = 35,
          role = "User"
        }
      }
    }, {
      user_id = 'admin'
    })
  end)
  R.it("create view returns metadata", function()
    local config = {
      columns = {
        "name",
        {
          field = "age",
          as = "user_age"
        }
      },
      filter = {
        field = "role",
        op = "EQ",
        value = "User"
      },
      orderBy = {
        {
          field = "age",
          desc = true
        }
      }
    }
    local ctx = {
      user_id = 'admin'
    }
    local args = {
      input = {
        name = "test_view_1",
        sourceSpace = "dv_test_users",
        config = json.encode(config)
      }
    }
    local res = resolvers.Mutation.createDataView(nil, args, ctx)
    R.eq(res.name, "test_view_1")
    return R.eq(res.config, json.encode(config))
  end)
  R.it("execute view returns filtered/sorted data", function()
    local ctx = {
      user_id = 'admin'
    }
    local views = resolvers.Query.dataViews(nil, nil, ctx)
    local dv_id = views[#views].id
    local res = resolvers.Query.executeDataView(nil, {
      id = dv_id
    }, ctx)
    R.eq(#res, 2)
    R.eq(res[1].name, "Charlie")
    R.eq(res[1].user_age, 35)
    return R.eq(res[2].name, "Bob")
  end)
  R.it("aggregates (GROUP BY)", function()
    local config = {
      groupBy = {
        "role"
      },
      aggregates = {
        {
          field = "age",
          fn = "sum",
          as = "total_age"
        },
        {
          field = "age",
          fn = "avg",
          as = "avg_age"
        },
        {
          fn = "count",
          as = "user_count"
        }
      }
    }
    local ctx = {
      user_id = 'admin'
    }
    local args = {
      input = {
        name = "test_view_agg",
        sourceSpace = "dv_test_users",
        config = json.encode(config)
      }
    }
    local res = resolvers.Mutation.createDataView(nil, args, ctx)
    local exec_res = resolvers.Query.executeDataView(nil, {
      id = res.id
    }, ctx)
    R.eq(#exec_res, 2)
    for _index_0 = 1, #exec_res do
      local row = exec_res[_index_0]
      if row.role == "Admin" then
        R.eq(row.user_count, 1)
        R.eq(row.total_age, 30)
      elseif row.role == "User" then
        R.eq(row.user_count, 2)
        R.eq(row.total_age, 60)
        R.eq(row.avg_age, 30)
      end
    end
  end)
  R.it("execute view works when sourceSpace is the space id (frontend behaviour)", function()
    local ctx = {
      user_id = 'admin'
    }
    local args = {
      input = {
        name = "test_view_by_id",
        sourceSpace = sp1_id,
        config = json.encode({
          columns = {
            "name",
            "age"
          }
        })
      }
    }
    local res = resolvers.Mutation.createDataView(nil, args, ctx)
    R.eq(res.sourceSpace, sp1_id)
    local exec_res = resolvers.Query.executeDataView(nil, {
      id = res.id
    }, ctx)
    return R.eq(#exec_res, 3)
  end)
  R.it("execute_view resolves a space passed by name too", function()
    local res = executor.execute_view('dv_test_users', json.encode({
      columns = {
        "name"
      }
    }), { })
    return R.eq(#res, 3)
  end)
  return R.it("cleanup", function()
    local ctx = {
      user_id = 'admin'
    }
    local views = resolvers.Query.dataViews(nil, nil, ctx)
    for _index_0 = 1, #views do
      local v = views[_index_0]
      resolvers.Mutation.deleteDataView(nil, {
        id = v.id
      }, ctx)
    end
    return spaces_mod.delete_user_space(sp1_id)
  end)
end)
