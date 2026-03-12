local R = require('tests.runner')
local spaces = require('core.spaces')
local executor = require('graphql.executor')
local auth = require('core.auth')
local json = require('json')
local user_id, GQL
GQL = {
  query = function(q, v)
    local res = executor.execute({
      query = q,
      variables = v,
      context = {
        user_id = user_id
      }
    })
    if res.errors then
      error(json.encode(res.errors))
    end
    return res.data
  end,
  mutate = function(q, v)
    return GQL.query(q, v)
  end
}
return R.describe("GraphQL — Nested queries (Nesting)", function()
  local user_sp, task_sp
  local user_fid, task_user_fid
  R.before_all(function()
    local admin = auth.get_user_by_username('admin')
    user_id = admin.id
    user_sp = spaces.create_user_space("users_" .. tostring(math.random(100000, 999999)))
    user_fid = spaces.add_field(user_sp.id, "id", "Sequence", true).id
    spaces.add_field(user_sp.id, "name", "String", true)
    task_sp = spaces.create_user_space("tasks_" .. tostring(math.random(100000, 999999)))
    spaces.add_field(task_sp.id, "id", "Sequence", true)
    spaces.add_field(task_sp.id, "title", "String", true)
    task_user_fid = spaces.add_field(task_sp.id, "user_id", "Int", true).id
    local rid = tostring(require('uuid').new())
    box.space._tdb_relations:insert({
      rid,
      task_sp.id,
      task_user_fid,
      user_sp.id,
      user_fid,
      "owner"
    })
    executor.reinit_schema()
    GQL.mutate("mutation { insertRecord(spaceId: \"" .. tostring(user_sp.id) .. "\", data: \"{\\\"name\\\":\\\"Alice\\\"}\") { id } }")
    GQL.mutate("mutation { insertRecord(spaceId: \"" .. tostring(user_sp.id) .. "\", data: \"{\\\"name\\\":\\\"Bob\\\"}\") { id } }")
    GQL.mutate("mutation { insertRecord(spaceId: \"" .. tostring(task_sp.id) .. "\", data: \"{\\\"title\\\":\\\"Task 1\\\",\\\"user_id\\\":1}\") { id } }")
    GQL.mutate("mutation { insertRecord(spaceId: \"" .. tostring(task_sp.id) .. "\", data: \"{\\\"title\\\":\\\"Task 2\\\",\\\"user_id\\\":2}\") { id } }")
    return GQL.mutate("mutation { insertRecord(spaceId: \"" .. tostring(task_sp.id) .. "\", data: \"{\\\"title\\\":\\\"Task 3\\\",\\\"user_id\\\":1}\") { id } }")
  end)
  R.after_all(function()
    if user_sp then
      spaces.delete_user_space(user_sp.name)
    end
    if task_sp then
      return spaces.delete_user_space(task_sp.name)
    end
  end)
  R.it("can query a linked record (FK resolution)", function()
    local tname = require('graphql.dynamic').gql_name(task_sp.name)
    local uname = require('graphql.dynamic').gql_name(user_sp.name)
    local q = "{ " .. tostring(tname) .. " { items { title user_id { name } } } }"
    local res = GQL.query(q)
    R.ok(res[tname], "doit avoir le champ " .. tostring(tname))
    local items = res[tname].items
    R.eq(#items, 3)
    table.sort(items, function(a, b)
      return a.title < b.title
    end)
    R.eq(items[1].title, "Task 1")
    R.eq(items[1].user_id.name, "Alice")
    R.eq(items[2].title, "Task 2")
    R.eq(items[2].user_id.name, "Bob")
    R.eq(items[3].title, "Task 3")
    return R.eq(items[3].user_id.name, "Alice")
  end)
  R.it("can query back-references with pagination/filtering", function()
    local tname = require('graphql.dynamic').gql_name(task_sp.name)
    local uname = require('graphql.dynamic').gql_name(user_sp.name)
    local q = "{ " .. tostring(uname) .. "(filter: { field: \"name\", op: EQ, value: \"Alice\" }) { items { name owner(limit: 1) { items { title } total } } } }"
    local res = GQL.query(q)
    R.ok(res[uname])
    local alice = res[uname].items[1]
    R.eq(alice.name, "Alice")
    R.eq(alice.owner.total, 2, "Alice should have 2 tasks")
    return R.eq(#alice.owner.items, 1, "limit should be respected")
  end)
  return R.it("can query records from Space (nested records)", function()
    local q = "{ space(id: \"" .. tostring(task_sp.id) .. "\") { name records(limit: 2) { items { id } total } } }"
    local res = GQL.query(q)
    R.ok(res.space)
    R.eq(res.space.name, task_sp.name)
    R.eq(#res.space.records.items, 2)
    return R.eq(res.space.records.total, 3)
  end)
end)
