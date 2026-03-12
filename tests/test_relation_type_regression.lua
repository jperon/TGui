local R = require('tests.runner')
local auth = require('core.auth')
local spaces_mod = require('core.spaces')
local schema_r = require('resolvers.schema_resolvers')
local SUFFIX = tostring(math.random(100000, 999999))
local CTX
do
  local admin = auth.get_user_by_username('admin')
  CTX = {
    user_id = admin.id
  }
end
return R.describe("Regression: Relation type mapping", function()
  R.it("addField with fieldType=Relation maps to Int", function()
    local sp_name = "test_relation_regression_" .. tostring(SUFFIX)
    local sp = schema_r.Mutation.createSpace(nil, {
      input = {
        name = sp_name,
        description = 'Type mapping test'
      }
    }, CTX)
    local f = schema_r.Mutation.addField(nil, {
      spaceId = sp.id,
      input = {
        name = 'bad_field',
        fieldType = 'Relation',
        description = 'Should map to Int'
      }
    }, CTX)
    R.ok(f)
    R.eq(f.fieldType, 'Int')
    return spaces_mod.delete_user_space(sp_name)
  end)
  return R.it("createRelation works with an Int source field", function()
    local source_name = "test_source_" .. tostring(SUFFIX)
    local target_name = "test_target_" .. tostring(SUFFIX)
    local source = schema_r.Mutation.createSpace(nil, {
      input = {
        name = source_name,
        description = 'Source'
      }
    }, CTX)
    local target = schema_r.Mutation.createSpace(nil, {
      input = {
        name = target_name,
        description = 'Target'
      }
    }, CTX)
    local int_field = schema_r.Mutation.addField(nil, {
      spaceId = source.id,
      input = {
        name = 'relation_field',
        fieldType = 'Int',
        description = 'Relation field'
      }
    }, CTX)
    local target_fields = spaces_mod.list_fields(target.id)
    local target_id_field = nil
    for _index_0 = 1, #target_fields do
      local f = target_fields[_index_0]
      if f.name == 'id' then
        target_id_field = f.id
        break
      end
    end
    R.ok(target_id_field)
    local relation = schema_r.Mutation.createRelation(nil, {
      input = {
        name = 'test_relation',
        fromSpaceId = source.id,
        fromFieldId = int_field.id,
        toSpaceId = target.id,
        toFieldId = target_id_field,
        reprFormula = '@id'
      }
    }, CTX)
    R.ok(relation)
    R.eq(relation.name, 'test_relation')
    spaces_mod.delete_user_space(source_name)
    return spaces_mod.delete_user_space(target_name)
  end)
end)
