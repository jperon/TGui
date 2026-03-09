-- tests/test_nesting.moon
-- Tests des requêtes imbriquées (nesting/sub-queries)

R = require 'tests.runner'
spaces   = require 'core.spaces'
executor = require 'graphql.executor'
auth     = require 'core.auth'
json     = require 'json'

local user_id, GQL

GQL = {
  query: (q, v) ->
    res = executor.execute { query: q, variables: v, context: { :user_id } }
    if res.errors
      error json.encode res.errors
    res.data
  mutate: (q, v) -> GQL.query q, v
}

R.describe "GraphQL — Requêtes imbriquées (Nesting)", ->
  local user_sp, task_sp
  local user_fid, task_user_fid

  R.before_all ->
    admin = auth.get_user_by_username 'admin'
    user_id = admin.id

    -- 1. Créer espace Utilisateurs
    user_sp = spaces.create_user_space "users_#{math.random 100000, 999999}"
    user_fid = spaces.add_field(user_sp.id, "id", "Sequence", true).id
    spaces.add_field(user_sp.id, "name", "String", true)

    -- 2. Créer espace Tâches
    task_sp = spaces.create_user_space "tasks_#{math.random 100000, 999999}"
    spaces.add_field(task_sp.id, "id", "Sequence", true)
    spaces.add_field(task_sp.id, "title", "String", true)
    task_user_fid = spaces.add_field(task_sp.id, "user_id", "Int", true).id

    -- 3. Créer une relation (Task.user_id -> User.id)
    rid = tostring(require('uuid').new!)
    box.space._tdb_relations\insert { rid, task_sp.id, task_user_fid, user_sp.id, user_fid, "owner" }

    executor.reinit_schema!

    -- 4. Insérer des données
    -- Users: Alice (1), Bob (2)
    GQL.mutate "mutation { insertRecord(spaceId: \"#{user_sp.id}\", data: \"{\\\"name\\\":\\\"Alice\\\"}\") { id } }"
    GQL.mutate "mutation { insertRecord(spaceId: \"#{user_sp.id}\", data: \"{\\\"name\\\":\\\"Bob\\\"}\") { id } }"

    -- Tasks: Task 1 (Alice), Task 2 (Bob), Task 3 (Alice)
    GQL.mutate "mutation { insertRecord(spaceId: \"#{task_sp.id}\", data: \"{\\\"title\\\":\\\"Task 1\\\",\\\"user_id\\\":1}\") { id } }"
    GQL.mutate "mutation { insertRecord(spaceId: \"#{task_sp.id}\", data: \"{\\\"title\\\":\\\"Task 2\\\",\\\"user_id\\\":2}\") { id } }"
    GQL.mutate "mutation { insertRecord(spaceId: \"#{task_sp.id}\", data: \"{\\\"title\\\":\\\"Task 3\\\",\\\"user_id\\\":1}\") { id } }"

  R.after_all ->
    spaces.delete_user_space user_sp.name if user_sp
    spaces.delete_user_space task_sp.name if task_sp

  R.it "peut requêter un enregistrement lié (FK resolution)", ->
    tname = require('graphql.dynamic').gql_name task_sp.name
    uname = require('graphql.dynamic').gql_name user_sp.name
    q = "{ #{tname} { items { title user_id { name } } } }"
    res = GQL.query q
    R.ok res[tname], "doit avoir le champ #{tname}"
    items = res[tname].items
    R.eq #items, 3
    
    table.sort items, (a, b) -> a.title < b.title
    R.eq items[1].title, "Task 1"
    R.eq items[1].user_id.name, "Alice"
    R.eq items[2].title, "Task 2"
    R.eq items[2].user_id.name, "Bob"
    R.eq items[3].title, "Task 3"
    R.eq items[3].user_id.name, "Alice"

  R.it "peut requêter des back-references avec pagination/filtrage", ->
    tname = require('graphql.dynamic').gql_name task_sp.name
    uname = require('graphql.dynamic').gql_name user_sp.name
    -- Récupérer Alice et ses tâches (back-ref via relation "owner")
    q = "{ #{uname}(filter: { field: \"name\", op: EQ, value: \"Alice\" }) { items { name owner(limit: 1) { items { title } total } } } }"
    res = GQL.query q
    R.ok res[uname]
    alice = res[uname].items[1]
    R.eq alice.name, "Alice"
    R.eq alice.owner.total, 2, "Alice doit avoir 2 tâches"
    R.eq #alice.owner.items, 1, "Limit doit être respecté"

  R.it "peut requêter records depuis Space (nested records)", ->
    q = "{ space(id: \"#{task_sp.id}\") { name records(limit: 2) { items { id } total } } }"
    res = GQL.query q
    R.ok res.space
    R.eq res.space.name, task_sp.name
    R.eq #res.space.records.items, 2
    return R.eq(res.space.records.total, 3)
