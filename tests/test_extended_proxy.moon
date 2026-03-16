-- tests/test_extended_proxy.moon
-- Tests for extended proxy with list support

R = require 'tests.runner'
triggers = require 'core.triggers'
spaces_mod = require 'core.spaces'

-- Setup test environment
json = require 'json'

R.describe "Extended Self Proxy with List Support", ->
  R.before_all ->
    -- Clean up any existing test data
    source_space = box.space._tdb_spaces.index.by_name\get { 'TestSource' }
    if source_space
      data_space = box.space["data_#{source_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { source_space[1] }

    target_space = box.space._tdb_spaces.index.by_name\get { 'TestTarget' }
    if target_space
      data_space = box.space["data_#{target_space[2]}"]
      if data_space
        data_space\truncate()
      box.space._tdb_spaces\delete { target_space[1] }

    -- Clean up relations
    for t in *box.space._tdb_relations\select {}
      if t[3] == 'TestSource' or t[3] == 'TestTarget'
        box.space._tdb_relations\delete { t[1] }

  R.after_all ->

  R.it "make_self_proxy_extended should create proxy with list functions", ->
    -- Create test space
    sp = spaces_mod.create_user_space 'TestSource'
    source_id = sp.id

    -- Add field
    field_id = spaces_mod.add_field source_id, 'name', 'String'

    -- Create record
    source_space = box.space["data_TestSource"]
    source_space\insert { '1', json.encode{name: 'Test Record'} }

    record = {name: 'Test Record', _id: '1'}
    single_map, multiple_map = triggers.build_single_and_multiple_maps source_id

    proxy = triggers.make_self_proxy_extended record, single_map, multiple_map, nil, 'TestSource'

    R.assert type(proxy) == 'table'
    R.assert type(proxy.list) == 'table'
    R.assert type(proxy.list.length) == 'function'
    R.assert type(proxy.list.first) == 'function'
    R.assert type(proxy.list.last) == 'function'
    R.assert type(proxy.list.map) == 'function'
    R.assert type(proxy.list.filter) == 'function'
    R.assert type(proxy.list.reduce) == 'function'

-- Cleanup: delete spaces created for these tests
spaces_mod.delete_user_space 'TestSource'
