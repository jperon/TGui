-- core/spaces.moon
-- Bootstrap and manage tdb system spaces (metadata) in Tarantool.
-- User-data spaces are created dynamically at runtime.

log = require 'log'

-- Field type constants (mirrors GraphQL scalar names)
FIELD_TYPES = { 'String', 'Int', 'Float', 'Boolean', 'ID', 'UUID', 'Sequence', 'Any', 'Map', 'Array' }
FIELD_TYPES_SET = { v, true for v in *FIELD_TYPES }

-- ────────────────────────────────────────────────────────────────────────────
-- Space descriptors
-- ────────────────────────────────────────────────────────────────────────────

SYSTEM_SPACES =
  -- User-defined spaces (tables)
  _tdb_spaces:
    format: {
      { name: 'id',          type: 'string'    }
      { name: 'name',        type: 'string'  }
      { name: 'description', type: 'string'  }
      { name: 'created_at',  type: 'number'  }
      { name: 'updated_at',  type: 'number'  }
    }
    indexes:
      primary: { parts: {'id'},   unique: true, type: 'HASH' }
      by_name: { parts: {'name'}, unique: true, type: 'TREE' }

  -- Fields within each user-defined space
  _tdb_fields:
    format: {
      { name: 'id',          type: 'string'   }
      { name: 'space_id',    type: 'string'   }
      { name: 'name',        type: 'string' }
      { name: 'field_type',  type: 'string' }
      { name: 'not_null',    type: 'boolean'}
      { name: 'position',    type: 'number' }
      { name: 'description', type: 'string' }
    }
    indexes:
      primary:     { parts: {'id'},               unique: true,  type: 'HASH' }
      by_space:    { parts: {'space_id'},          unique: false, type: 'TREE' }
      by_space_pos:{ parts: {'space_id','position'}, unique: true, type: 'TREE' }

  -- Views: named projections over a space (with filters, ordering, hidden fields…)
  _tdb_views:
    format: {
      { name: 'id',          type: 'string'   }
      { name: 'space_id',    type: 'string'   }
      { name: 'name',        type: 'string' }
      { name: 'view_type',   type: 'string' }  -- 'grid','form','gallery'
      { name: 'config',      type: 'string' }  -- JSON blob
      { name: 'created_at',  type: 'number' }
      { name: 'updated_at',  type: 'number' }
    }
    indexes:
      primary:    { parts: {'id'},       unique: true,  type: 'HASH' }
      by_space:   { parts: {'space_id'}, unique: false, type: 'TREE' }
      by_name:    { parts: {'name'},     unique: true,  type: 'TREE' }

  -- Custom YAML views (dashboard layouts)
  _tdb_custom_views:
    format: {
      { name: 'id',          type: 'string' }
      { name: 'name',        type: 'string' }
      { name: 'description', type: 'string' }
      { name: 'yaml',        type: 'string' }
      { name: 'created_at',  type: 'number' }
      { name: 'updated_at',  type: 'number' }
    }
    indexes:
      primary: { parts: {'id'},   unique: true,  type: 'HASH' }
      by_name: { parts: {'name'}, unique: true,  type: 'TREE' }

  -- Foreign-key relations between fields in different spaces
  _tdb_relations:
    format: {
      { name: 'id',             type: 'string'   }
      { name: 'from_space_id',  type: 'string'   }
      { name: 'from_field_id',  type: 'string'   }
      { name: 'to_space_id',    type: 'string'   }
      { name: 'to_field_id',    type: 'string'   }
      { name: 'name',           type: 'string' }
    }
    indexes:
      primary:  { parts: {'id'},            unique: true,  type: 'HASH' }
      by_from:  { parts: {'from_space_id'}, unique: false, type: 'TREE' }
      by_to:    { parts: {'to_space_id'},   unique: false, type: 'TREE' }

  -- Users
  _tdb_users:
    format: {
      { name: 'id',          type: 'string'   }
      { name: 'username',    type: 'string' }
      { name: 'email',       type: 'string' }
      { name: 'password_hash',type: 'string'}
      { name: 'salt',        type: 'string' }
      { name: 'created_at',  type: 'number' }
      { name: 'updated_at',  type: 'number' }
    }
    indexes:
      primary:      { parts: {'id'},       unique: true, type: 'HASH' }
      by_username:  { parts: {'username'}, unique: true, type: 'TREE' }
      by_email:     { parts: {'email'},    unique: true, type: 'TREE' }

  -- Groups (Unix-style: users can belong to N groups)
  _tdb_groups:
    format: {
      { name: 'id',          type: 'string'   }
      { name: 'name',        type: 'string' }
      { name: 'description', type: 'string' }
      { name: 'created_at',  type: 'number' }
    }
    indexes:
      primary: { parts: {'id'},   unique: true, type: 'HASH' }
      by_name: { parts: {'name'}, unique: true, type: 'TREE' }

  -- Membership: user ↔ group
  _tdb_memberships:
    format: {
      { name: 'user_id',  type: 'string' }
      { name: 'group_id', type: 'string' }
    }
    indexes:
      primary:    { parts: {'user_id','group_id'}, unique: true,  type: 'HASH' }
      by_user:    { parts: {'user_id'},            unique: false, type: 'TREE' }
      by_group:   { parts: {'group_id'},           unique: false, type: 'TREE' }

  -- Permissions: (group_id, resource_type, resource_id, level)
  -- resource_type: 'space'|'view'|'field'|'*'
  -- level: bitmask or symbolic e.g. 'read'|'write'|'admin'
  _tdb_permissions:
    format: {
      { name: 'id',            type: 'string'   }
      { name: 'group_id',      type: 'string'   }
      { name: 'resource_type', type: 'string' }
      { name: 'resource_id',   type: 'string'   }  -- uuid() for wildcard '*'
      { name: 'level',         type: 'string' }
    }
    indexes:
      primary:    { parts: {'id'},                        unique: true,  type: 'HASH' }
      by_group:   { parts: {'group_id'},                  unique: false, type: 'TREE' }
      by_resource:{ parts: {'resource_type','resource_id'}, unique: false, type: 'TREE' }

  -- Sessions (short-lived auth tokens)
  _tdb_sessions:
    format: {
      { name: 'token',      type: 'string' }
      { name: 'user_id',    type: 'string'   }
      { name: 'created_at', type: 'number' }
      { name: 'expires_at', type: 'number' }
    }
    indexes:
      primary:  { parts: {'token'},   unique: true, type: 'HASH' }
      by_user:  { parts: {'user_id'}, unique: false, type: 'TREE' }

-- ────────────────────────────────────────────────────────────────────────────
-- Bootstrap
-- ────────────────────────────────────────────────────────────────────────────

create_space = (name, desc) ->
  if box.space[name] then return
  s = box.schema.space.create name, {
    format: desc.format
    if_not_exists: true
  }
  -- Primary index must be created first
  if desc.indexes.primary
    opts = {
      parts:         desc.indexes.primary.parts
      unique:        desc.indexes.primary.unique
      type:          desc.indexes.primary.type
      if_not_exists: true
    }
    s\create_index 'primary', opts
  for idx_name, idx_def in pairs desc.indexes
    continue if idx_name == 'primary'
    opts = {
      parts:         idx_def.parts
      unique:        idx_def.unique
      type:          idx_def.type
      if_not_exists: true
    }
    s\create_index idx_name, opts
  log.info "Created space: #{name}"

bootstrap = ->
  box.once 'tdb_v1', ->
    log.info 'Bootstrapping tdb system spaces…'
    for name, desc in pairs SYSTEM_SPACES
      create_space name, desc

    -- Create the built-in 'admin' group
    admin_gid = require('uuid').new!
    box.space._tdb_groups\insert {
      tostring(admin_gid)
      'admin'
      'Administrators with full access'
      os.time!
    }

    -- Create the default admin user
    auth_mod = require 'core.auth'
    admin_user = os.getenv('TDB_ADMIN_USER') or 'admin'
    admin_pass = os.getenv('TDB_ADMIN_PASSWORD') or 'admin'
    u = auth_mod.create_user admin_user, '', admin_pass
    -- Add admin user to admin group
    box.space._tdb_memberships\insert { u.id, tostring(admin_gid) }
    log.info "tdb bootstrap complete. Default admin: #{admin_user}"

-- ────────────────────────────────────────────────────────────────────────────
-- Runtime space management
-- ────────────────────────────────────────────────────────────────────────────

-- Create a new user-defined data space.
-- Returns the new space metadata tuple.
create_user_space = (name, description) ->
  uuid = require 'uuid'
  now  = os.time!
  sid  = tostring uuid.new!
  meta = { sid, name, description or '', now, now }
  box.space._tdb_spaces\insert meta
  box.schema.space.create "data_#{name}", { if_not_exists: true }
  box.space["data_#{name}"]\create_index 'primary', {
    parts: {1}, type: 'HASH', if_not_exists: true
  }
  { id: sid, name: name, description: description or '', createdAt: now, updatedAt: now }

-- Add a field definition to a space.
add_field = (space_id, field_name, field_type, not_null, description, formula, trigger_fields, language) ->
  uuid = require 'uuid'
  json = require 'json'
  error "Type de champ invalide : #{field_type}" unless FIELD_TYPES_SET[field_type]
  -- compute next position
  pos = 1
  for _ in *box.space._tdb_fields.index.by_space\select { space_id }
    pos += 1
  fid = tostring uuid.new!
  tuple = { fid, space_id, field_name, field_type, not_null or false, pos, description or '' }
  if formula and formula != ''
    -- Index 8 : formule ; index 9 : trigger_fields (JSON, "null" si absent) ;
    -- index 10 : langage. La présence systématique des trois garantit une position fixe.
    table.insert tuple, formula
    table.insert tuple, json.encode(trigger_fields)  -- "null" si trigger_fields est nil
    table.insert tuple, language or 'lua'
  box.space._tdb_fields\insert tuple
  -- Create a Tarantool sequence for auto-increment fields and backfill existing records
  if field_type == 'Sequence'
    box.schema.sequence.create "_tdb_seq_#{fid}", { start: 1, min: 1, step: 1, if_not_exists: true }
    seq = box.sequence["_tdb_seq_#{fid}"]
    space_meta = box.space._tdb_spaces\get space_id
    if space_meta and seq
      data_sp = box.space["data_#{space_meta[2]}"]
      if data_sp
        for t in *data_sp\select {}
          d = if type(t[2]) == 'string' then require('json').decode(t[2]) else t[2]
          d[field_name] = seq\next!
          data_sp\replace { t[1], require('json').encode(d) }
  {
    id: fid, spaceId: space_id, name: field_name, fieldType: field_type,
    notNull: not_null or false, position: pos, description: description or '',
    formula: formula or '', triggerFields: trigger_fields, language: language or 'lua'
  }

remove_field = (field_id) ->
  t = box.space._tdb_fields\get field_id
  if t and t[4] == 'Sequence'
    seq = box.sequence["_tdb_seq_#{field_id}"]
    seq\drop! if seq
  box.space._tdb_fields\delete field_id
  true

-- List all user spaces
list_spaces = ->
  result = {}
  for t in *box.space._tdb_spaces\select {}
    table.insert result, {
      id:          t[1]
      name:        t[2]
      description: t[3]
      createdAt:   t[4]
      updatedAt:   t[5]
    }
  result

-- Get a single space by id
get_space = (id) ->
  t = box.space._tdb_spaces\get id
  return nil unless t
  { id: t[1], name: t[2], description: t[3], createdAt: t[4], updatedAt: t[5] }

-- List fields for a space, sorted by position.
list_fields = (space_id) ->
  result = {}
  json = require 'json'
  for t in *box.space._tdb_fields.index.by_space_pos\select { space_id }
    -- Index 9 peut être : nil (ancien tuple sans formula), "null" (formula sans trigger),
    -- ou un JSON array (trigger formula). L'index 10 est le langage (nouveaux tuples).
    trigger_raw = t[9]
    trigger_fields = if trigger_raw and trigger_raw != 'null'
      json.decode trigger_raw
    else
      nil
    table.insert result, {
      id:            t[1]
      spaceId:       t[2]
      name:          t[3]
      fieldType:     t[4]
      notNull:       t[5]
      position:      t[6]
      description:   t[7]
      formula:       t[8] or ''
      triggerFields: trigger_fields
      language:      t[10] or 'lua'
    }
  result

-- Update a field definition (name, notNull, description, formula, triggerFields, language).
-- fieldType cannot be changed (would require data migration).
update_field = (field_id, opts) ->
  json = require 'json'
  t = box.space._tdb_fields\get field_id
  error "Field not found: #{field_id}" unless t
  name     = opts.name     or t[3]
  not_null = if opts.notNull != nil then opts.notNull else t[5]
  desc     = opts.description or t[7]
  formula  = opts.formula
  trigger_fields = opts.triggerFields
  language = opts.language or t[10] or 'lua'
  -- Preserve immutable columns: id, spaceId, fieldType, position
  tuple = { t[1], t[2], name, t[4], not_null, t[6], desc }
  if formula and formula != ''
    table.insert tuple, formula
    table.insert tuple, json.encode(trigger_fields)
    table.insert tuple, language
  box.space._tdb_fields\replace tuple
  -- Return updated field
  trigger_raw = if #tuple >= 9 then tuple[9] else nil
  tf = if trigger_raw and trigger_raw != 'null' then json.decode(trigger_raw) else nil
  {
    id: t[1], spaceId: t[2], name: name, fieldType: t[4],
    notNull: not_null, position: t[6], description: desc,
    formula: formula or '', triggerFields: tf, language: language
  }

-- Reorder fields by assigning new positions based on given id order.
reorder_fields = (space_id, field_ids) ->
  -- First pass: assign temporary large positions to avoid unique index conflicts
  for pos, fid in ipairs field_ids
    t = box.space._tdb_fields\get fid
    continue unless t and t[2] == space_id
    box.space._tdb_fields\update fid, { { '=', 6, 10000 + pos } }
  -- Second pass: assign final positions
  for pos, fid in ipairs field_ids
    t = box.space._tdb_fields\get fid
    continue unless t and t[2] == space_id
    box.space._tdb_fields\update fid, { { '=', 6, pos } }
  list_fields space_id

-- ────────────────────────────────────────────────────────────────────────────
-- Migrations (run on every startup, idempotent)
-- ────────────────────────────────────────────────────────────────────────────

migrate = ->
  -- Ensure all system spaces added after initial bootstrap exist
  for name, desc in pairs SYSTEM_SPACES
    create_space name, desc

  -- Ensure sequences exist for all Sequence-type fields
  for t in *box.space._tdb_fields\select {}
    if t[4] == 'Sequence'
      seq_name = "_tdb_seq_#{t[1]}"
      unless box.sequence[seq_name]
        box.schema.sequence.create seq_name, { start: 1, min: 1, step: 1 }
        log.info "Created missing sequence: #{seq_name}"

-- Delete a user space and all its associated data (fields, sequences, box.space).
-- Used by the test suite to clean up after itself.
delete_user_space = (name) ->
  return unless name
  meta = box.space._tdb_spaces.index.by_name\get name
  return unless meta
  sid = meta[1]
  -- Remove all fields (and their sequences)
  for t in *box.space._tdb_fields.index.by_space\select { sid }
    if t[4] == 'Sequence'
      seq = box.sequence["_tdb_seq_#{t[1]}"]
      seq\drop! if seq
    box.space._tdb_fields\delete t[1]
  -- Drop the underlying box.space
  sp = box.space["data_#{name}"]
  sp\drop! if sp
  -- Remove metadata
  box.space._tdb_spaces\delete sid

{ :bootstrap, :migrate, :create_user_space, :delete_user_space, :add_field, :remove_field, :update_field, :reorder_fields, :list_spaces, :list_fields, :get_space, :FIELD_TYPES }
