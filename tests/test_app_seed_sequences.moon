-- tests/test_app_seed_sequences.moon
-- Un seed qui porte des `id` explicites doit faire avancer le compteur de la
-- séquence : une insertion utilisateur ultérieure ne réutilise jamais un id du seed.
R = require 'tests.runner'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
auth = require 'core.auth'
data_r = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999
SP = "seq_seed_#{SUFFIX}"
APP_ID = "org.test.seqseed_#{SUFFIX}"
admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

clean_app_rows = (app_id) ->
  for t in *box.space._tdb_app_items.index.by_app\select { app_id }
    box.space._tdb_app_items\delete { t[1], t[2] }
  box.space._tdb_apps\delete app_id

field_item = (name, ftype, not_null) ->
  { type: 'field', key: "field:#{SP}.#{name}", content: {
      fieldType: ftype, notNull: not_null or false, description: '',
      formula: '', triggerFields: {}, language: 'lua' } }

seed_item = (id, nom) ->
  { type: 'seed', key: "seed:#{SP}|#{id}", content: {
      space: SP, key: tostring(id), data: { id: id, nom: nom } } }

PKG = {
  app: { id: APP_ID, version: '1.0.0' }
  items: {
    { type: 'space', key: "space:#{SP}", content: { description: '' } }
    field_item 'id', 'Sequence', true
    field_item 'nom', 'String'
    seed_item 1, 'a'
    seed_item 2, 'b'
    seed_item 7, 'g'
  }
  seed_keys: { [SP]: 'id' }
}

R.describe "app_apply — seeds advance sequences", ->

  R.it "installs the package", ->
    report = apply.apply_update PKG, {}, {}
    R.eq #(report.errors or {}), 0, 'errors'

  R.it "a user insert after the seed gets an id above every seed id", ->
    sp = spaces.get_space_by_name SP
    r = data_r.Mutation.insertRecord {}, { spaceId: sp.id, data: { nom: 'c' } }, CTX
    id = require('json').decode(r.data).id
    R.eq id, 8, 'id attribué'

  R.it "cleans up", ->
    clean_app_rows APP_ID
    sp = spaces.get_space_by_name SP
    spaces.delete_user_space SP if sp
    R.is_nil spaces.get_space_by_name SP
