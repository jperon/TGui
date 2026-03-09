local R = require('tests.runner')
local spaces_mod = require('core.spaces')
local auth = require('core.auth')
local execute
execute = require('graphql.executor').execute
local json = require('json')
local SUFFIX = tostring(math.random(100000, 999999))
local SP_NAME = "test_batch_" .. tostring(SUFFIX)
local space_id, context
return R.describe("Batch Operations", function()
  R.it("setup: create space and fields", function()
    local admin = auth.get_user_by_username('admin')
    context = {
      user_id = admin.id
    }
    local sp = spaces_mod.create_user_space(SP_NAME, "Batch test")
    space_id = sp.id
    spaces_mod.add_field(space_id, 'name', 'String')
    spaces_mod.add_field(space_id, 'val', 'Int')
    spaces_mod.add_field(space_id, 'seq', 'Sequence')
    return require('resolvers.init').reinit()
  end)
  R.it("insertRecords creates multiple records", function()
    local q = [[      mutation($spaceId: ID!, $data: [JSON!]!) {
        insertRecords(spaceId: $spaceId, data: $data) {
          id
          data
        }
      }
    ]]
    local vars = {
      spaceId = space_id,
      data = {
        json.encode({
          name = "A",
          val = 1
        }),
        json.encode({
          name = "B",
          val = 2
        })
      }
    }
    local res = execute({
      query = q,
      variables = vars,
      context = context
    })
    if res.errors then
      error(json.encode(res.errors))
    end
    R.ok(res.data)
    R.ok(res.data.insertRecords)
    R.eq(#res.data.insertRecords, 2)
    R.ok(res.data.insertRecords[1].id)
    R.ok(res.data.insertRecords[2].id)
    local sp = box.space["data_" .. tostring(SP_NAME)]
    return R.eq(sp:count(), 2)
  end)
  R.it("updateRecords updates multiple records", function()
    local sp = box.space["data_" .. tostring(SP_NAME)]
    local tuples = sp:select({ })
    local id1 = tuples[1][1]
    local id2 = tuples[2][1]
    local q = [[      mutation($spaceId: ID!, $records: [RecordUpdateInput!]!) {
        updateRecords(spaceId: $spaceId, records: $records) {
          id
          data
        }
      }
    ]]
    local vars = {
      spaceId = space_id,
      records = {
        {
          id = id1,
          data = json.encode({
            val = 10
          })
        },
        {
          id = id2,
          data = json.encode({
            val = 20
          })
        }
      }
    }
    local res = execute({
      query = q,
      variables = vars,
      context = context
    })
    if res.errors then
      error(json.encode(res.errors))
    end
    R.ok(res.data)
    R.ok(res.data.updateRecords)
    R.eq(#res.data.updateRecords, 2)
    local t1 = sp:get(id1)
    local t2 = sp:get(id2)
    local d1 = json.decode(t1[2])
    local d2 = json.decode(t2[2])
    R.eq(d1.val, 10)
    R.eq(d2.val, 20)
    local found_A = false
    local _list_0 = sp:select()
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      local d = json.decode(t[2])
      if d.name == "A" then
        found_A = true
        R.ok(d.val == 10 or d.val == 20)
      end
    end
    return R.ok(found_A)
  end)
  return R.it("cleanup", function()
    return spaces_mod.delete_user_space(SP_NAME)
  end)
end)
