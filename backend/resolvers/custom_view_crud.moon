-- resolvers/custom_view_crud.moon
-- CRUD, snapshot and layout export/import functions for custom YAML views.

uuid_mod = require 'uuid'

-- Convert a _tdb_custom_views tuple to the public page shape.
custom_view_from_tuple = (t) ->
  { id: t[1], name: t[2], description: t[3], yaml: t[4],
    createdAt: tostring(t[5]), updatedAt: tostring(t[6]) }

list_custom_views = ->
  result = {}
  for t in *box.space._tdb_custom_views\select {}
    table.insert result, custom_view_from_tuple t
  result

get_custom_view = (id) ->
  t = box.space._tdb_custom_views\get id
  return nil unless t
  custom_view_from_tuple t

create_custom_view = (name, description, yaml) ->
  id  = tostring uuid_mod.new!
  now = require('clock').time!
  box.space._tdb_custom_views\insert { id, name, description or '', yaml or '', now, now }
  { id: id, name: name, description: description or '', yaml: yaml or '',
    createdAt: tostring(now), updatedAt: tostring(now) }

delete_custom_view = (id) ->
  box.space._tdb_custom_views\delete id
  true

-- Create a layout snapshot
create_layout_snapshot = (page_id, yaml_content, description) ->
  id = tostring uuid_mod.new!
  now = require('clock').time!
  box.space._tdb_layout_snapshots\insert {
    id
    page_id
    yaml_content
    now
    description or ''
  }
  {
    id: id
    pageId: page_id
    yaml: yaml_content
    createdAt: now
    description: description or ''
  }

-- Create automatic snapshot before updating a custom view
create_auto_snapshot = (page_id) ->
  t = box.space._tdb_custom_views\get page_id
  return nil unless t
  -- Don't create snapshot if yaml is empty or hasn't changed
  return nil if not t[4] or t[4] == ''
  create_layout_snapshot page_id, t[4], "Auto-snapshot before update"

-- List all snapshots for a page
list_layout_snapshots = (page_id) ->
  result = {}
  for t in *box.space._tdb_layout_snapshots.index.by_page\select { page_id }
    table.insert result, {
      id: t[1]
      pageId: t[2]
      yaml: t[3]
      createdAt: t[4]
      description: t[5] or ''
    }
  -- Sort by created_at descending (newest first)
  table.sort result, (a, b) -> a.createdAt > b.createdAt
  result

-- Restore a layout snapshot
restore_layout_snapshot = (snapshot_id) ->
  snapshot = box.space._tdb_layout_snapshots\get snapshot_id
  error "Snapshot not found: #{snapshot_id}" unless snapshot
  page_id = snapshot[2]
  yaml_content = snapshot[3]
  -- Get the custom view
  t = box.space._tdb_custom_views\get page_id
  error "CustomView not found: #{page_id}" unless t
  -- Create a new snapshot for the current state before restoring
  create_auto_snapshot page_id
  -- Update the custom view with the snapshot's yaml
  now = require('clock').time!
  box.space._tdb_custom_views\replace { page_id, t[2], t[3], yaml_content, t[5], now }
  { id: page_id, name: t[2], description: t[3], yaml: yaml_content, createdAt: tostring(t[5]), updatedAt: tostring(now) }

-- Update a custom view with automatic snapshot
update_custom_view = (id, name, description, yaml) ->
  t = box.space._tdb_custom_views\get id
  error "CustomView not found: #{id}" unless t
  -- Create automatic snapshot if yaml is changing
  if yaml and yaml != t[4]
    create_auto_snapshot id
  now = require('clock').time!
  new_name = if name != nil then name else t[2]
  new_desc = if description != nil then description else t[3]
  new_yaml = if yaml != nil then yaml else t[4]
  box.space._tdb_custom_views\replace { id, new_name, new_desc, new_yaml, t[5], now }
  { id: id, name: new_name, description: new_desc, yaml: new_yaml, createdAt: tostring(t[5]), updatedAt: tostring(now) }

-- Export layout as YAML string
export_layout = (page_id) ->
  t = box.space._tdb_custom_views\get page_id
  error "CustomView not found: #{page_id}" unless t
  { id: t[1], name: t[2], yaml: t[4] }

-- Import layout YAML string
import_layout = (page_id, yaml) ->
  t = box.space._tdb_custom_views\get page_id
  error "CustomView not found: #{page_id}" unless t
  now = require('clock').time!
  box.space._tdb_custom_views\replace { page_id, t[2], t[3], yaml, t[5], now }
  { id: page_id, name: t[2], description: t[3], yaml: yaml, createdAt: tostring(t[5]), updatedAt: tostring(now) }

{
  :list_custom_views
  :get_custom_view
  :create_custom_view
  :delete_custom_view
  :create_layout_snapshot
  :list_layout_snapshots
  :restore_layout_snapshot
  :update_custom_view
  :export_layout
  :import_layout
}
