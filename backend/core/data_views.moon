-- core/data_views.moon
uuid = require 'uuid'
json = require 'json'
log  = require 'log'
{ :make_self_proxy, :build_fk_def_map, :compile_formula } = require 'core.triggers'

get_view = (id) ->
  t = box.space._tdb_data_views\get { id }
  return nil unless t
  {
    id: t[1]
    name: t[2]
    description: t[3]
    sourceSpace: t[4]
    config: t[5]
    createdAt: t[6]
    updatedAt: t[7]
  }

create_view = (name, description, source_space, config_json) ->
  error "Name cannot be empty" if not name or name == ''
  error "Source space cannot be empty" if not source_space or source_space == ''
  
  -- check duplicate name
  existing = box.space._tdb_data_views.index.by_name\get { name }
  error "A view with name '#{name}' already exists" if existing

  -- validate config is json
  if config_json and config_json != ''
    ok, err = pcall json.decode, config_json
    error "Invalid config JSON: #{err}" unless ok

  view_id = uuid.str!
  now = os.time!
  box.space._tdb_data_views\insert { view_id, name, description or '', source_space, config_json or '{}', now, now }
  get_view view_id

get_view_by_name = (name) ->
  t = box.space._tdb_data_views.index.by_name\get { name }
  return nil unless t
  get_view t[1]

list_views = ->
  [get_view(t[1]) for t in *box.space._tdb_data_views\select {}]

update_view = (id, params) ->
  t = box.space._tdb_data_views\get { id }
  error "View not found" unless t
  
  name = params.name
  if name and name != t[2]
    existing = box.space._tdb_data_views.index.by_name\get { name }
    error "A view with name '#{name}' already exists" if existing

  if params.config
    ok, err = pcall json.decode, params.config
    error "Invalid config JSON: #{err}" unless ok

  box.space._tdb_data_views\update id, {
    { '=', 2, params.name or t[2] }
    { '=', 3, params.description or t[3] }
    { '=', 4, params.sourceSpace or params.source_space or t[4] }
    { '=', 5, params.config or t[5] }
    { '=', 7, os.time! }
  }
  get_view id

delete_view = (id) ->
  t = box.space._tdb_data_views\get { id }
  return false unless t
  box.space._tdb_data_views\delete { id }
  true

{ :create_view, :get_view, :get_view_by_name, :list_views, :update_view, :delete_view }
