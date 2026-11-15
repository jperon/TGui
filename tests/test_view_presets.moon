-- tests/test_view_presets.moon
-- Named view presets: scope isolation, overwrite by (scope, name), validation,
-- space-scoped read safety, delete and cascade on space removal.

R = require 'tests.runner'
spaces_mod = require 'core.spaces'
presets = require 'core.view_presets'

SUFFIX = tostring math.random 100000, 999999
SP_NAME = "vp_space_#{SUFFIX}"
OTHER_NAME = "vp_other_#{SUFFIX}"

SCOPE_W = "widget:page_#{SUFFIX}:w1"
SCOPE_W2 = "widget:page_#{SUFFIX}:w2"

sp_id = nil
other_id = nil
scope_other = nil
alpha_id = nil

R.describe "ViewPresets — storage and scopes", ->

  R.it "creates two test spaces", ->
    sp = spaces_mod.create_user_space SP_NAME, 'view presets fixture'
    sp_id = sp.id
    other = spaces_mod.create_user_space OTHER_NAME, 'view presets other fixture'
    other_id = other.id
    scope_other = "space:#{other_id}"
    R.ok sp_id
    R.ok other_id

  R.it "saves presets in one scope and in another scope of the same space", ->
    a = presets.save_preset SCOPE_W, sp_id, 'Alpha', '', nil
    b = presets.save_preset SCOPE_W, sp_id, 'Bêta', 'self.age > 3', '[{"column":"age","ascending":false}]'
    c = presets.save_preset SCOPE_W2, sp_id, 'Alpha', 'self.role == "admin"', '[]'
    alpha_id = a.id
    R.ok a.id
    R.ok b.id
    R.eq a.scope, SCOPE_W
    R.eq a.spaceId, sp_id
    R.eq a.filter, ''
    R.eq a.sort, '[]'
    R.eq b.filter, 'self.age > 3'
    R.eq b.sort, '[{"column":"age","ascending":false}]'
    R.eq c.scope, SCOPE_W2

  R.it "lists presets sorted by name and isolated per scope", ->
    w = presets.list_presets SCOPE_W
    R.eq #w, 2
    R.eq w[1].name, 'Alpha'
    R.eq w[2].name, 'Bêta'

    w2 = presets.list_presets SCOPE_W2
    R.eq #w2, 1
    R.eq w2[1].name, 'Alpha'

    R.eq #presets.list_presets(SCOPE_W), 2

  R.it "allows the same name in two different scopes", ->
    w = presets.list_presets SCOPE_W
    w2 = presets.list_presets SCOPE_W2
    R.ne w[1].id, w2[1].id

  R.it "overwrites the preset stored under the same (scope, name)", ->
    saved = presets.save_preset SCOPE_W, sp_id, 'Alpha', 'self.x == 1', '[{"column":"x","ascending":true}]'
    R.eq saved.id, alpha_id
    R.eq saved.filter, 'self.x == 1'
    R.eq saved.sort, '[{"column":"x","ascending":true}]'
    R.eq #presets.list_presets(SCOPE_W), 2

  R.it "rejects an invalid sort", ->
    R.raises (-> presets.save_preset SCOPE_W, sp_id, 'Bad1', '', 'not-json'), 'Invalid sort JSON'
    R.raises (-> presets.save_preset SCOPE_W, sp_id, 'Bad2', '', '{"column":"x"}'), 'Invalid sort'
    R.raises (-> presets.save_preset SCOPE_W, sp_id, 'Bad3', '', '[{"column":1,"ascending":true}]'), 'column'
    R.raises (-> presets.save_preset SCOPE_W, sp_id, 'Bad4', '', '[{"column":"x","ascending":"yes"}]'), 'ascending'
    for p in *presets.list_presets SCOPE_W
      R.nok p.name\match('^Bad'), 'no invalid preset stored'

  R.it "rejects an empty name and an unknown space", ->
    R.raises (-> presets.save_preset SCOPE_W, sp_id, '   ', '', '[]'), 'name'
    R.raises (-> presets.save_preset SCOPE_W, 'missing-space-id', 'Nom', '', '[]'), 'Space not found'

  R.it "deletes a preset by id", ->
    p = presets.save_preset SCOPE_W2, sp_id, 'ToDelete', '', '[]'
    R.ok presets.delete_preset p.id
    R.is_nil presets.get_preset p.id
    R.nok presets.delete_preset p.id

  R.it "cascades preset deletion when the space is deleted", ->
    other = presets.save_preset scope_other, other_id, 'Other', '', '[]'
    R.ok other.id
    R.eq #presets.list_presets(scope_other), 1
    spaces_mod.delete_user_space OTHER_NAME
    R.eq #presets.list_presets(scope_other), 0
    for t in *box.space._tdb_view_presets.index.by_space\select { other_id }
      R.ok false, 'no preset must remain for the deleted space'

  R.it "cleanup", ->
    for scope in *{ SCOPE_W, SCOPE_W2 }
      for p in *presets.list_presets scope
        presets.delete_preset p.id
    spaces_mod.delete_user_space SP_NAME
    R.eq #presets.list_presets(SCOPE_W), 0
    R.eq #presets.list_presets(SCOPE_W2), 0
