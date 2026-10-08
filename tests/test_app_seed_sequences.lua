local R = require('tests.runner')
local apply = require('core.app_apply')
local spaces = require('core.spaces')
local auth = require('core.auth')
local data_r = require('resolvers.data_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local SP = "seq_seed_" .. tostring(SUFFIX)
local APP_ID = "org.test.seqseed_" .. tostring(SUFFIX)
local admin = auth.get_user_by_username('admin')
local CTX = {
  user_id = admin and admin.id
}
local clean_app_rows
clean_app_rows = function(app_id)
  local _list_0 = box.space._tdb_app_items.index.by_app:select({
    app_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    box.space._tdb_app_items:delete({
      t[1],
      t[2]
    })
  end
  return box.space._tdb_apps:delete(app_id)
end
local field_item
field_item = function(name, ftype, not_null)
  return {
    type = 'field',
    key = "field:" .. tostring(SP) .. "." .. tostring(name),
    content = {
      fieldType = ftype,
      notNull = not_null or false,
      description = '',
      formula = '',
      triggerFields = { },
      language = 'lua'
    }
  }
end
local seed_item
seed_item = function(id, nom)
  return {
    type = 'seed',
    key = "seed:" .. tostring(SP) .. "|" .. tostring(id),
    content = {
      space = SP,
      key = tostring(id),
      data = {
        id = id,
        nom = nom
      }
    }
  }
end
local PKG = {
  app = {
    id = APP_ID,
    version = '1.0.0'
  },
  items = {
    {
      type = 'space',
      key = "space:" .. tostring(SP),
      content = {
        description = ''
      }
    },
    field_item('id', 'Sequence', true),
    field_item('nom', 'String'),
    seed_item(1, 'a'),
    seed_item(2, 'b'),
    seed_item(7, 'g')
  },
  seed_keys = {
    [SP] = 'id'
  }
}
return R.describe("app_apply — seeds advance sequences", function()
  R.it("installs the package", function()
    local report = apply.apply_update(PKG, { }, { })
    return R.eq(#(report.errors or { }), 0, 'errors')
  end)
  R.it("a user insert after the seed gets an id above every seed id", function()
    local sp = spaces.get_space_by_name(SP)
    local r = data_r.Mutation.insertRecord({ }, {
      spaceId = sp.id,
      data = {
        nom = 'c'
      }
    }, CTX)
    local id = require('json').decode(r.data).id
    return R.eq(id, 8, 'id attribué')
  end)
  return R.it("cleans up", function()
    clean_app_rows(APP_ID)
    local sp = spaces.get_space_by_name(SP)
    if sp then
      spaces.delete_user_space(SP)
    end
    return R.is_nil(spaces.get_space_by_name(SP))
  end)
end)
