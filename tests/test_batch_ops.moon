-- tests/test_batch_ops.moon
-- GraphQL integration tests for insertRecords/updateRecords on a temporary space.
R = require 'tests.runner'
spaces_mod = require 'core.spaces'
auth = require 'core.auth'
{ :execute } = require 'graphql.executor'
json = require 'json'

SUFFIX = tostring(math.random 100000, 999999)
SP_NAME = "test_batch_#{SUFFIX}"

local space_id, context

R.describe "Batch Operations", ->
  R.it "setup: create space and fields", ->
    admin = auth.get_user_by_username 'admin'
    context = { user_id: admin.id }

    sp = spaces_mod.create_user_space SP_NAME, "Batch test"
    space_id = sp.id
    spaces_mod.add_field space_id, 'name', 'String'
    spaces_mod.add_field space_id, 'val', 'Int'
    spaces_mod.add_field space_id, 'seq', 'Sequence'
    -- Re-init schema to include the new space in GraphQL
    require('resolvers.init').reinit!

  R.it "insertRecords creates multiple records", ->
    q = [[
      mutation($spaceId: ID!, $data: [JSON!]!) {
        insertRecords(spaceId: $spaceId, data: $data) {
          id
          data
        }
      }
    ]]
    vars = {
      spaceId: space_id
      data: {
        json.encode({ name: "A", val: 1 }),
        json.encode({ name: "B", val: 2 })
      }
    }
    res = execute { query: q, variables: vars, context: context }
    if res.errors
      error json.encode res.errors
    R.ok res.data
    R.ok res.data.insertRecords
    R.eq #res.data.insertRecords, 2
    R.ok res.data.insertRecords[1].id
    R.ok res.data.insertRecords[2].id

    -- Verify in space
    sp = box.space["data_#{SP_NAME}"]
    R.eq sp\count!, 2

  R.it "updateRecords updates multiple records", ->
    -- First get the IDs
    sp = box.space["data_#{SP_NAME}"]
    tuples = sp\select {}
    id1 = tuples[1][1]
    id2 = tuples[2][1]

    q = [[
      mutation($spaceId: ID!, $records: [RecordUpdateInput!]!) {
        updateRecords(spaceId: $spaceId, records: $records) {
          id
          data
        }
      }
    ]]
    vars = {
      spaceId: space_id
      records: {
        { id: id1, data: json.encode({ val: 10 }) },
        { id: id2, data: json.encode({ val: 20 }) }
      }
    }
    res = execute { query: q, variables: vars, context: context }
    if res.errors
       error json.encode res.errors
    R.ok res.data
    R.ok res.data.updateRecords
    R.eq #res.data.updateRecords, 2

    -- Verify values
    t1 = sp\get id1
    t2 = sp\get id2
    d1 = json.decode t1[2]
    d2 = json.decode t2[2]
    R.eq d1.val, 10
    R.eq d2.val, 20

    found_A = false
    for t in *sp\select!
      d = json.decode t[2]
      if d.name == "A"
        found_A = true
        R.ok d.val == 10 or d.val == 20
    R.ok found_A

  R.it "cleanup", ->
    spaces_mod.delete_user_space SP_NAME
