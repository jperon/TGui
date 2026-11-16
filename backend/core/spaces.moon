-- core/spaces.moon
-- Bootstrap and manage tdb system spaces (metadata) in Tarantool.
-- User-data spaces are created dynamically at runtime.

log = require 'log'
{ :validate_input, :safe_formula_call } = require 'core.config'
widget_ids = require 'core.widget_ids'

-- Field type constants (mirrors GraphQL scalar names)
FIELD_TYPES = { 'String', 'Int', 'Float', 'Boolean', 'ID', 'UUID', 'Sequence', 'Any', 'Map', 'Array', 'Datetime', 'Relation' }
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

  -- UI preferences (owner_key = user_id or 'default', payload JSON per space)
  _tdb_ui_prefs:
    format: {
      { name: 'owner_key', type: 'string' }
      { name: 'space_id',  type: 'string' }
      { name: 'prefs',     type: 'string' }
      { name: 'updated_at',type: 'number' }
    }
    indexes:
      primary:  { parts: {'owner_key','space_id'}, unique: true,  type: 'TREE' }
      by_space: { parts: {'space_id'},             unique: false, type: 'TREE' }

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

  -- Layout snapshots for custom views (automatic versioning)
  _tdb_layout_snapshots:
    format: {
      { name: 'id',          type: 'string' }
      { name: 'page_id',     type: 'string' }
      { name: 'yaml',        type: 'string' }
      { name: 'created_at',  type: 'number' }
      { name: 'description', type: 'string' }
    }
    indexes:
      primary:   { parts: {'id'},        unique: true,  type: 'HASH' }
      by_page:   { parts: {'page_id'},   unique: false, type: 'TREE' }
      by_page_time: { parts: {'page_id','created_at'}, unique: false, type: 'TREE' }

  -- Data Views: persisted queries with joins, groupBy, aggregates, computed fields
  _tdb_data_views:
    format: {
      { name: 'id',           type: 'string' }
      { name: 'name',         type: 'string' }
      { name: 'description',  type: 'string' }
      { name: 'source_space', type: 'string' }
      { name: 'config',       type: 'string' }
      { name: 'created_at',   type: 'number' }
      { name: 'updated_at',   type: 'number' }
    }
    indexes:
      primary: { parts: {'id'},   unique: true,  type: 'HASH' }
      by_name: { parts: {'name'}, unique: true,  type: 'TREE' }

  -- Named view presets: one filter formula + sort order per widget (or per
  -- main grid of a space). scope is an opaque key: 'widget:<pageId>:<widgetId>'
  -- or 'space:<spaceId>'. space_id identifies the displayed space (permissions).
  _tdb_view_presets:
    format: {
      { name: 'id',          type: 'string' }
      { name: 'scope',       type: 'string' }
      { name: 'space_id',    type: 'string' }
      { name: 'name',        type: 'string' }
      { name: 'filter',      type: 'string' }
      { name: 'sort',        type: 'string' }
      { name: 'created_at',  type: 'number' }
      { name: 'updated_at',  type: 'number' }
    }
    indexes:
      primary:       { parts: {'id'},              unique: true,  type: 'HASH' }
      by_scope_name: { parts: {'scope','name'},    unique: true,  type: 'TREE' }
      by_space:      { parts: {'space_id'},        unique: false, type: 'TREE' }

  -- Custom widget plugins (script/template code used by custom views)
  _tdb_widget_plugins:
    format: {
      { name: 'id',                type: 'string' }
      { name: 'name',              type: 'string' }
      { name: 'description',       type: 'string' }
      { name: 'script_language',   type: 'string' }
      { name: 'template_language', type: 'string' }
      { name: 'script_code',       type: 'string' }
      { name: 'template_code',     type: 'string' }
      { name: 'created_at',        type: 'number' }
      { name: 'updated_at',        type: 'number' }
      { name: 'manifest',          type: 'string', is_nullable: true }
      { name: 'app_id',            type: 'string', is_nullable: true }
      -- Code compilé/caché côté serveur (spec widgets personnalisés §7) :
      -- Lua compilé pour moonscript, source pour lua, '' pour les langages
      -- compilés par le navigateur. Recalculé à chaque enregistrement.
      { name: 'compiled',          type: 'string', is_nullable: true }
    }
    indexes:
      primary: { parts: {'id'},   unique: true,  type: 'HASH' }
      -- Unicité du nom PAR PORTÉE (spec widgets personnalisés §5) : app_id
      -- vide = bibliothèque. by_name reste non unique pour les recherches par
      -- nom seul (app_package.describe_local, compatibilité).
      by_scope_name: { parts: {'app_id','name'}, unique: true,  type: 'TREE' }
      by_name: { parts: {'name'}, unique: false, type: 'TREE' }

  -- Foreign-key relations between fields in different spaces
  _tdb_relations:
    format: {
      { name: 'id',             type: 'string'   }
      { name: 'from_space_id',  type: 'string'   }
      { name: 'from_field_id',  type: 'string'   }
      { name: 'to_space_id',    type: 'string'   }
      { name: 'to_field_id',    type: 'string'   }
      { name: 'name',           type: 'string' }
      { name: 'repr_formula',   type: 'string', is_nullable: true }
      { name: 'cardinality',    type: 'string', is_nullable: true }
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
      { name: 'must_change_password', type: 'boolean', is_nullable: true }
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

  -- Login rate-limiting (key = 'user:<lower>' or 'ip:<addr>'), persisted in
  -- memtx so it survives a server restart (spec §7 / audit 1.2).
  _tdb_login_attempts:
    format: {
      { name: 'key',             type: 'string' }
      { name: 'failures',        type: 'number' }
      { name: 'last_failure_at', type: 'number' }
      { name: 'locked_until',    type: 'number' }
      { name: 'lock_count',      type: 'number' }
    }
    indexes:
      primary: { parts: {'key'}, unique: true, type: 'HASH' }

  -- Installed applications (app packages, versioning)
  _tdb_apps:
    format: {
      { name: 'app_id',       type: 'string' }
      { name: 'name',         type: 'string' }
      { name: 'version',      type: 'string' }
      { name: 'installed_at', type: 'number' }
      { name: 'source',       type: 'string' }
    }
    indexes:
      primary: { parts: {'app_id'}, unique: true, type: 'HASH' }

  -- Items delivered by an installed application
  _tdb_app_items:
    format: {
      { name: 'app_id',      type: 'string' }
      { name: 'key',         type: 'string' }
      { name: 'type',        type: 'string' }
      { name: 'local_id',    type: 'string' }
      { name: 'fingerprint', type: 'string' }
      { name: 'state',       type: 'string' }
      { name: 'version',     type: 'string' }
    }
    indexes:
      primary: { parts: {'app_id', 'key'}, unique: true, type: 'HASH' }
      by_app:  { parts: {'app_id'},        unique: false, type: 'TREE' }

-- ────────────────────────────────────────────────────────────────────────────
-- Bootstrap
-- ────────────────────────────────────────────────────────────────────────────

-- Migration tdb_v4 (spec §7 / audit 1.4): extend the _tdb_users format with the
-- nullable must_change_password boolean and flag every existing user whose
-- current password is still the public default. Existing rows read as nil
-- (== false) until flagged. Returns the number of accounts flagged. Exposed so
-- the test suite can exercise the migration directly.
migrate_must_change_password = ->
  sp = box.space._tdb_users
  return 0 unless sp
  sp\format {
    { name: 'id',          type: 'string'   }
    { name: 'username',    type: 'string' }
    { name: 'email',       type: 'string' }
    { name: 'password_hash',type: 'string'}
    { name: 'salt',        type: 'string' }
    { name: 'created_at',  type: 'number' }
    { name: 'updated_at',  type: 'number' }
    { name: 'must_change_password', type: 'boolean', is_nullable: true }
  }
  auth_mod = require 'core.auth'
  { :DEFAULT_ADMIN_PASSWORD } = require 'core.config'
  flagged = 0
  for t in *sp\select {}
    if t[8] != true and auth_mod.verify_password DEFAULT_ADMIN_PASSWORD, t[5], t[4]
      sp\replace { t[1], t[2], t[3], t[4], t[5], t[6], t[7], true }
      flagged += 1
  flagged

-- Migration tdb_v5 (spec widgets personnalisés §3): extend
-- _tdb_widget_plugins with the optional YAML `manifest`, at the end of the
-- format and nullable so pre-existing tuples stay valid and read as
-- "no manifest" (= full access, the behaviour before manifests). Existing rows
-- are rewritten with an empty manifest so their arity matches the format.
-- Le format inclut `app_id` (migration tdb_v6) : cette migration reste
-- idempotente quand elle est rejouée après, sans perdre la portée.
-- Returns the number of rows normalized. Exposed for the test suite.
migrate_widget_plugin_manifest = ->
  sp = box.space._tdb_widget_plugins
  return 0 unless sp
  sp\format {
    { name: 'id',                type: 'string' }
    { name: 'name',              type: 'string' }
    { name: 'description',       type: 'string' }
    { name: 'script_language',   type: 'string' }
    { name: 'template_language', type: 'string' }
    { name: 'script_code',       type: 'string' }
    { name: 'template_code',     type: 'string' }
    { name: 'created_at',        type: 'number' }
    { name: 'updated_at',        type: 'number' }
    { name: 'manifest',          type: 'string', is_nullable: true }
    { name: 'app_id',            type: 'string', is_nullable: true }
    { name: 'compiled',          type: 'string', is_nullable: true }
  }
  normalized = 0
  for t in *sp\select {}
    if t[10] == nil
      sp\replace { t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], '', t[11] or '', t[12] or '' }
      normalized += 1
  normalized

-- Migration tdb_v6 (spec widgets personnalisés §5) : portée des définitions.
-- Ajoute `app_id` (nullable, en fin de format) et rend le nom unique PAR
-- PORTÉE : app_id vide = bibliothèque. Les définitions existantes deviennent
-- globales (`app_id` = '') — c'est ce qu'elles étaient avant les portées.
-- L'index by_name devient non unique (deux apps peuvent livrer le même nom) ;
-- la recherche par (portée, nom) passe par by_scope_name.
-- Returns the number of rows normalized. Exposed for the test suite.
migrate_widget_plugin_app_id = ->
  sp = box.space._tdb_widget_plugins
  return 0 unless sp
  -- Index d'abord : changer le format d'un espace non vide est refusé tant
  -- qu'un index unique porte sur un champ dont la définition change.
  if sp.index.by_name and sp.index.by_name.unique
    sp\drop_index 'by_name'
  sp\format {
    { name: 'id',                type: 'string' }
    { name: 'name',              type: 'string' }
    { name: 'description',       type: 'string' }
    { name: 'script_language',   type: 'string' }
    { name: 'template_language', type: 'string' }
    { name: 'script_code',       type: 'string' }
    { name: 'template_code',     type: 'string' }
    { name: 'created_at',        type: 'number' }
    { name: 'updated_at',        type: 'number' }
    { name: 'manifest',          type: 'string', is_nullable: true }
    { name: 'app_id',            type: 'string', is_nullable: true }
    { name: 'compiled',          type: 'string', is_nullable: true }
  }
  normalized = 0
  for t in *sp\select {}
    if t[11] == nil
      sp\replace { t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10] or '', '', t[12] or '' }
      normalized += 1
  sp\create_index 'by_scope_name', {
    parts: {'app_id', 'name'}, unique: true, type: 'TREE', if_not_exists: true
  }
  sp\create_index 'by_name', {
    parts: {'name'}, unique: false, type: 'TREE', if_not_exists: true
  }
  normalized

-- Migration tdb_v7 (spec widgets personnalisés §7) : champ `compiled` en fin de
-- format. Le code Lua compilé (moonscript) ou vérifié (lua) est recalculé à
-- chaque enregistrement ; les lignes existantes reçoivent '' (aucune
-- définition lua/moonscript ne peut exister avant cette étape : le langage
-- était refusé). Idempotente, exposée pour la suite de tests.
-- Returns the number of rows normalized.
migrate_widget_plugin_compiled = ->
  sp = box.space._tdb_widget_plugins
  return 0 unless sp
  sp\format {
    { name: 'id',                type: 'string' }
    { name: 'name',              type: 'string' }
    { name: 'description',       type: 'string' }
    { name: 'script_language',   type: 'string' }
    { name: 'template_language', type: 'string' }
    { name: 'script_code',       type: 'string' }
    { name: 'template_code',     type: 'string' }
    { name: 'created_at',        type: 'number' }
    { name: 'updated_at',        type: 'number' }
    { name: 'manifest',          type: 'string', is_nullable: true }
    { name: 'app_id',            type: 'string', is_nullable: true }
    { name: 'compiled',          type: 'string', is_nullable: true }
  }
  normalized = 0
  for t in *sp\select {}
    if t[12] == nil
      sp\replace { t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10] or '', t[11] or '', '' }
      normalized += 1
  normalized

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
    admin_pass = os.getenv('TDB_ADMIN_PASSWORD') or 'adminadmin'
    u = auth_mod.create_user admin_user, '', admin_pass
    -- Add admin user to admin group
    box.space._tdb_memberships\insert { u.id, tostring(admin_gid) }
    log.info "tdb bootstrap complete. Default admin: #{admin_user}"

  box.once 'tdb_v2', ->
    sp = box.space._tdb_relations
    if sp
      new_fmt = {
        { name: 'id',           type: 'string' }
        { name: 'from_space_id',type: 'string' }
        { name: 'from_field_id',type: 'string' }
        { name: 'to_space_id',  type: 'string' }
        { name: 'to_field_id',  type: 'string' }
        { name: 'name',         type: 'string' }
        { name: 'repr_formula', type: 'string', is_nullable: true }
      }
      sp\format new_fmt
      log.info 'tdb_v2: added repr_formula to _tdb_relations'

  box.once 'tdb_v3', ->
    sp = box.space._tdb_relations
    if sp
      new_fmt = {
        { name: 'id',           type: 'string' }
        { name: 'from_space_id',type: 'string' }
        { name: 'from_field_id',type: 'string' }
        { name: 'to_space_id',  type: 'string' }
        { name: 'to_field_id',  type: 'string' }
        { name: 'name',         type: 'string' }
        { name: 'repr_formula', type: 'string', is_nullable: true }
        { name: 'cardinality',  type: 'string', is_nullable: true }
      }
      sp\format new_fmt
      log.info "tdb_v3: added cardinality to _tdb_relations — relations existantes : cardinalité 'one' par défaut"

  -- Forced default-password change (spec §7 / audit 1.4). Extends the users
  -- format with a nullable boolean; existing rows get nil (== false). For an
  -- existing instance, any user whose current password is still the public
  -- default is flagged once, at startup (a single verify_password per user).
  box.once 'tdb_v4', ->
    flagged = migrate_must_change_password!
    log.info 'tdb_v4: added must_change_password to _tdb_users'
    if flagged > 0
      log.warn "tdb_v4: #{flagged} user(s) still use the default password — change required"

  -- Custom widget manifests (spec widgets personnalisés §3). Existing plugins
  -- keep working unchanged: an empty manifest means full access.
  box.once 'tdb_v5', ->
    normalized = migrate_widget_plugin_manifest!
    log.info "tdb_v5: added manifest to _tdb_widget_plugins (#{normalized} row(s) normalized)"

  -- Widget definition scopes (spec widgets personnalisés §5). Existing
  -- definitions become library (global), as they were; the name is now unique
  -- per scope.
  box.once 'tdb_v6', ->
    normalized = migrate_widget_plugin_app_id!
    log.info "tdb_v6: added app_id to _tdb_widget_plugins (#{normalized} row(s) normalized)"

  -- Lua / MoonScript widget definitions (spec widgets personnalisés §7).
  -- Existing definitions read as "no compiled code"; they keep working.
  box.once 'tdb_v7', ->
    normalized = migrate_widget_plugin_compiled!
    log.info "tdb_v7: added compiled to _tdb_widget_plugins (#{normalized} row(s) normalized)"

  -- Widget ids: every widget of a page carries a stable id, which is the key of
  -- the widget-scoped records (named view presets: 'widget:<pageId>:<widgetId>').
  -- Tarantool does not persist before_replace triggers, so it is registered on
  -- every start; pages written before this module are normalized once here.
  widget_ids.install_trigger!
  normalized = widget_ids.migrate_stored_pages!
  log.info "tdb widget ids: #{normalized} page(s) normalized" if normalized > 0

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
-- Get maximum value for a field in a space (for sequence initialization)
get_max_field_value = (space_id, field_name) ->
  space_meta = box.space._tdb_spaces\get space_id
  return 0 unless space_meta

  data_sp = box.space["data_#{space_meta[2]}"]
  return 0 unless data_sp

  max_val = 0
  for t in *data_sp\select {}
    d = if type(t[2]) == 'string' then require('json').decode(t[2]) else t[2]
    val = d[field_name]
    if type(val) == 'number' and val > max_val
      max_val = val

  max_val

add_field = (space_id, field_name, field_type, not_null, description, formula, trigger_fields, language, repr_formula) ->
  uuid = require 'uuid'
  json = require 'json'

  -- Transform Relation alias to Int (frontend handles the actual relation creation)
  if field_type == 'Relation'
    field_type = 'Int'
    log.info "Relation field type transformed to Int (relation will be created by frontend)"

  error "Type de champ invalide : #{field_type}" unless FIELD_TYPES_SET[field_type]

  -- Validate inputs
  unless validate_input 'field_name', field_name, "add_field"
    error "Field name too long: #{#field_name} chars"

  if formula and not validate_input 'formula', formula, "add_field"
    error "Formula too long: #{#formula} chars"

  if repr_formula and not validate_input 'formula', repr_formula, "add_field"
    error "Representation formula too long: #{#repr_formula} chars"

  -- compute next position
  pos = 1
  for _ in *box.space._tdb_fields.index.by_space\select { space_id }
    pos += 1
  fid = tostring uuid.new!
  tuple = { fid, space_id, field_name, field_type, not_null or false, pos, description or '' }
  if formula and formula != ''
    -- Index 8: formula; index 9: trigger_fields (JSON, "null" when absent);
    -- index 10: language. Keeping all three ensures stable tuple positions.
    table.insert tuple, formula
    table.insert tuple, json.encode(trigger_fields)  -- "null" si trigger_fields est nil
    table.insert tuple, language or 'lua'
    table.insert tuple, repr_formula or ''
  elseif repr_formula and repr_formula != ''
    -- No formula but a reprFormula: still fill t[8..10] to preserve positions.
    table.insert tuple, ''          -- empty formula
    table.insert tuple, json.encode(nil)  -- trigger_fields null
    table.insert tuple, 'lua'        -- default language
    table.insert tuple, repr_formula
  box.space._tdb_fields\insert tuple
  -- Create a Tarantool sequence for auto-increment fields and backfill existing records
  if field_type == 'Sequence'
    -- Get max existing value to preserve existing IDs
    max_val = get_max_field_value(space_id, field_name)
    start_val = max_val + 1

    box.schema.sequence.create "_tdb_seq_#{fid}", { start: start_val, min: 1, step: 1, if_not_exists: true }
    seq = box.sequence["_tdb_seq_#{fid}"]
    space_meta = box.space._tdb_spaces\get space_id
    if space_meta and seq
      data_sp = box.space["data_#{space_meta[2]}"]
      if data_sp
        for t in *data_sp\select {}
          d = if type(t[2]) == 'string' then require('json').decode(t[2]) else t[2]
          -- Only backfill if the field is nil or not a number
          if d[field_name] == nil or type(d[field_name]) != 'number'
            d[field_name] = seq\next!
          data_sp\replace { t[1], require('json').encode(d) }
  {
    id: fid, spaceId: space_id, name: field_name, fieldType: field_type,
    notNull: not_null or false, position: pos, description: description or '',
    formula: formula or '', triggerFields: trigger_fields, language: language or 'lua',
    reprFormula: repr_formula or ''
  }

remove_field = (field_id) ->
  t = box.space._tdb_fields\get field_id
  if t and t[4] == 'Sequence'
    seq = box.sequence["_tdb_seq_#{field_id}"]
    seq\drop! if seq
  box.space._tdb_fields\delete field_id
  true

-- Convert a _tdb_spaces tuple to the public space shape.
space_from_tuple = (t) ->
  { id: t[1], name: t[2], description: t[3], createdAt: t[4], updatedAt: t[5] }

-- List all user spaces
list_spaces = ->
  result = {}
  for t in *box.space._tdb_spaces\select {}
    table.insert result, space_from_tuple t
  result

-- Get a single space by id
get_space = (id) ->
  t = box.space._tdb_spaces\get id
  return nil unless t
  space_from_tuple t

-- Get a single space by name
get_space_by_name = (name) ->
  t = box.space._tdb_spaces.index.by_name\get name
  return nil unless t
  space_from_tuple t

-- List fields for a space, sorted by position.
list_fields = (space_id) ->
  result = {}
  json = require 'json'
  for t in *box.space._tdb_fields.index.by_space_pos\select { space_id }
    -- Index 9 may be: nil (legacy tuple without formula), "null" (formula without trigger),
    -- or a JSON array (trigger formula). Index 10 stores language (newer tuples).
    -- Index 11 stores reprFormula (latest tuple format).
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
      reprFormula:   t[11] or ''
    }
  result

-- Update a field definition (name, notNull, description, formula, triggerFields, language, reprFormula).
-- fieldType cannot be changed here (use change_field_type for that).
update_field = (field_id, opts) ->
  json = require 'json'
  t = box.space._tdb_fields\get field_id
  error "Field not found: #{field_id}" unless t

  -- Validate inputs
  if opts.name and not validate_input 'field_name', opts.name, "update_field"
    error "Field name too long: #{#opts.name} chars"

  if opts.formula and not validate_input 'formula', opts.formula, "update_field"
    error "Formula too long: #{#opts.formula} chars"

  if opts.reprFormula and not validate_input 'formula', opts.reprFormula, "update_field"
    error "Representation formula too long: #{#opts.reprFormula} chars"
  name     = opts.name     or t[3]
  not_null = if opts.notNull != nil then opts.notNull else t[5]
  desc     = opts.description or t[7]
  language = opts.language or t[10] or 'lua'
  -- Preserve the columns the caller does not mention: an absent formula keeps
  -- the existing formula and triggers, `formula = ''` clears them explicitly,
  -- an absent reprFormula keeps the existing representation formula.
  formula = if opts.formula != nil then opts.formula else (t[8] or '')
  repr_formula = if opts.reprFormula != nil then opts.reprFormula else (t[11] or '')
  triggers_enc = if opts.formula != nil
    json.encode opts.triggerFields
  else
    t[9] or json.encode(nil)
  -- Preserve immutable columns: id, spaceId, fieldType, position
  tuple = { t[1], t[2], name, t[4], not_null, t[6], desc }
  -- Rewrite columns 8..11 only when the field already carries them or the
  -- update touches the formula/representation; a plain field stays 7 columns.
  if t[8] != nil or formula != '' or repr_formula != ''
    table.insert tuple, formula
    table.insert tuple, triggers_enc
    table.insert tuple, language
    table.insert tuple, repr_formula
  box.space._tdb_fields\replace tuple
  -- Return updated field
  trigger_raw = if #tuple >= 9 then tuple[9] else nil
  tf = if trigger_raw and trigger_raw != 'null' then json.decode(trigger_raw) else nil
  {
    id: t[1], spaceId: t[2], name: name, fieldType: t[4],
    notNull: not_null, position: t[6], description: desc,
    formula: (if #tuple >= 8 then tuple[8] else '') or '', triggerFields: tf, language: language,
    reprFormula: repr_formula
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

-- Change the type of a field, optionally converting existing data with a formula.
-- conversion_formula: MoonScript/Lua formula receiving self (the record data table),
--   must return the new value for the field.
-- language: 'lua' or 'moonscript'
change_field_type = (field_id, new_type, conversion_formula, language) ->
  json    = require 'json'
  t = box.space._tdb_fields\get field_id
  error "Field not found: #{field_id}" unless t
  error "Type de champ invalide : #{new_type}" unless FIELD_TYPES_SET[new_type]
  field_name = t[3]
  space_id   = t[2]
  space_meta = box.space._tdb_spaces\get space_id
  error "Space not found" unless space_meta
  space_name = space_meta[2]

  -- Migrate existing data if a conversion formula is provided
  if conversion_formula and conversion_formula != ''
    -- Direct compilation for conversion formulas (avoid triggers.compile_formula issues)
    lang = language or 'lua'
    lua_chunk = if lang == 'moonscript'
      ok_ms, moon = pcall require, 'moonscript.base'
      unless ok_ms
        error "MoonScript non disponible: #{moon}"
      moon_src = "return (self, space) -> " .. conversion_formula
      ok_c, lua_or_err, compile_err = pcall moon.to_lua, moon_src
      unless ok_c
        error "MoonScript parse error: #{lua_or_err}"
      -- to_lua returns nil, message on a parse/compile error (it does not raise)
      unless lua_or_err
        error "MoonScript parse error: #{compile_err}"
      lua_or_err
    else
      "return function(self, space) return " .. conversion_formula .. " end"

    chunk_fn, load_err = load lua_chunk
    unless chunk_fn
      error "Parse error: #{load_err}"

    ok2, conv_fn = pcall chunk_fn
    unless ok2 and type(conv_fn) == 'function'
      error "Compilation error: #{conv_fn}"

    data_sp = box.space["data_#{space_name}"]
    if data_sp
      for raw_t in *data_sp\select {}
        d = if type(raw_t[2]) == 'string' then json.decode(raw_t[2]) else raw_t[2]
        new_val, conv_err = safe_formula_call conv_fn, "conversion #{space_name}.#{field_name}", nil, raw_t[1], { d, nil }
        d[field_name] = new_val unless conv_err
        data_sp\replace { raw_t[1], json.encode(d) }

  -- Special handling for Sequence type conversion
  if new_type == 'Sequence'
    -- Get max existing value to preserve existing IDs
    max_val = get_max_field_value(space_id, field_name)
    start_val = max_val + 1

    -- Create the sequence with proper start value
    seq_name = "_tdb_seq_#{field_id}"
    box.schema.sequence.create seq_name, { start: start_val, min: 1, step: 1, if_not_exists: true }
    seq = box.sequence[seq_name]

    -- Backfill only records without valid numeric values
    if seq
      data_sp = box.space["data_#{space_name}"]
      if data_sp
        for raw_t in *data_sp\select {}
          d = if type(raw_t[2]) == 'string' then json.decode(raw_t[2]) else raw_t[2]
          -- Only backfill if the field is nil or not a number
          if d[field_name] == nil or type(d[field_name]) != 'number'
            d[field_name] = seq\next!
          data_sp\replace { raw_t[1], json.encode(d) }

  -- Update field type in metadata (preserve all other columns)
  -- Build updated tuple: replace t[4] (field_type) with new_type
  new_tuple = { t[1], t[2], t[3], new_type, t[5], t[6], t[7] }
  if t[8] != nil
    table.insert new_tuple, t[8]   -- formula
    table.insert new_tuple, t[9]   -- trigger_fields
    table.insert new_tuple, t[10]  -- language
    table.insert new_tuple, t[11]  -- repr_formula
  box.space._tdb_fields\replace new_tuple

  -- Return updated field
  trigger_raw = t[9]
  tf = if trigger_raw and trigger_raw != 'null' then json.decode(trigger_raw) else nil
  {
    id: t[1], spaceId: t[2], name: t[3], fieldType: new_type,
    notNull: t[5], position: t[6], description: t[7],
    formula: t[8] or '', triggerFields: tf, language: t[10] or 'lua',
    reprFormula: t[11] or ''
  }

-- ────────────────────────────────────────────────────────────────────────────
-- Migrations (run on every startup, idempotent)
-- ────────────────────────────────────────────────────────────────────────────

migrate = ->
  -- Ensure all system spaces added after initial bootstrap exist
  for name, desc in pairs SYSTEM_SPACES
    create_space name, desc

  -- A system space (re)created above has no trigger yet; before_replace
  -- replaces the previous trigger, so the bootstrap call is not duplicated.
  widget_ids.install_trigger!

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
  -- Deregister trigger before dropping (via package.loaded to avoid circular dep)
  trg_mod = package.loaded['core.triggers']
  if trg_mod and trg_mod.deregister_space_trigger
    pcall trg_mod.deregister_space_trigger, name
  -- Remove all fields (and their sequences)
  for t in *box.space._tdb_fields.index.by_space\select { sid }
    if t[4] == 'Sequence'
      seq = box.sequence["_tdb_seq_#{t[1]}"]
      seq\drop! if seq
    box.space._tdb_fields\delete t[1]
  -- Drop the underlying box.space
  sp = box.space["data_#{name}"]
  sp\drop! if sp
  -- Cascade: remove the view presets attached to this space
  -- (core/view_presets.moon, index by_space).
  if box.space._tdb_view_presets
    for t in *box.space._tdb_view_presets.index.by_space\select { sid }
      box.space._tdb_view_presets\delete t[1]
  -- Remove metadata
  box.space._tdb_spaces\delete sid

{ :bootstrap, :migrate, :migrate_must_change_password, :migrate_widget_plugin_manifest, :migrate_widget_plugin_app_id, :migrate_widget_plugin_compiled, :create_user_space, :delete_user_space, :add_field, :remove_field, :update_field, :reorder_fields, :change_field_type, :list_spaces, :list_fields, :get_space, :get_space_by_name, :FIELD_TYPES }
