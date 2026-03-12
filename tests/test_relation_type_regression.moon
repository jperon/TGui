-- tests/test_relation_type_regression.moon
-- Régression: vérifie le mapping sécurisé fieldType=Relation -> Int et la création de relation associée.
R = require 'tests.runner'
auth = require 'core.auth'
spaces_mod = require 'core.spaces'
schema_r = require 'resolvers.schema_resolvers'

SUFFIX = tostring math.random 100000, 999999
CTX = do
  admin = auth.get_user_by_username 'admin'
  { user_id: admin.id }

R.describe "Regression: Relation type mapping", ->
  R.it "addField avec fieldType=Relation est mappé vers Int", ->
    sp_name = "test_relation_regression_#{SUFFIX}"
    sp = schema_r.Mutation.createSpace nil, { input: { name: sp_name, description: 'Type mapping test' } }, CTX
    f = schema_r.Mutation.addField nil, {
      spaceId: sp.id
      input: {
        name: 'bad_field'
        fieldType: 'Relation'
        description: 'Should map to Int'
      }
    }, CTX
    R.ok f
    R.eq f.fieldType, 'Int'
    spaces_mod.delete_user_space sp_name

  R.it "createRelation fonctionne avec un champ Int source", ->
    source_name = "test_source_#{SUFFIX}"
    target_name = "test_target_#{SUFFIX}"

    source = schema_r.Mutation.createSpace nil, { input: { name: source_name, description: 'Source' } }, CTX
    target = schema_r.Mutation.createSpace nil, { input: { name: target_name, description: 'Target' } }, CTX

    int_field = schema_r.Mutation.addField nil, {
      spaceId: source.id
      input: {
        name: 'relation_field'
        fieldType: 'Int'
        description: 'Relation field'
      }
    }, CTX

    target_fields = spaces_mod.list_fields target.id
    target_id_field = nil
    for f in *target_fields
      if f.name == 'id'
        target_id_field = f.id
        break
    R.ok target_id_field

    relation = schema_r.Mutation.createRelation nil, {
      input: {
        name: 'test_relation'
        fromSpaceId: source.id
        fromFieldId: int_field.id
        toSpaceId: target.id
        toFieldId: target_id_field
        reprFormula: '@id'
      }
    }, CTX

    R.ok relation
    R.eq relation.name, 'test_relation'

    spaces_mod.delete_user_space source_name
    spaces_mod.delete_user_space target_name
