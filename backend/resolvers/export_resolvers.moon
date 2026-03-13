-- resolvers/export_resolvers.moon
-- Snapshot export, diff and import resolvers.

spaces_mod  = require 'core.spaces'
views_mod   = require 'core.views'
perms_mod   = require 'core.permissions'
auth_mod    = require 'core.auth'
executor    = require 'graphql.executor'
uuid_mod    = require 'uuid'
yaml        = require 'yaml'
json        = require 'json'
clock       = require 'clock'
{ :require_auth, :require_admin } = require 'resolvers.utils'

-- Stored in schema_resolvers, reproduced here to avoid circular imports
list_relations_for_space = (space_id) ->
  result = {}
  for t in *box.space._tdb_relations.index.by_from\select { space_id }
    table.insert result, {
      fromSpaceId: t[2]
      fromFieldId: t[3]
      toSpaceId:   t[4]
      toFieldId:   t[5]
    }
  result

-- Resolve a space id → name
space_name_by_id = (sid) ->
  t = box.space._tdb_spaces\get sid
  t and t[2] or nil

-- Resolve a field id → name (within a space)
field_name_by_id = (fid) ->
  t = box.space._tdb_fields\get fid
  t and t[3] or nil

-- ────────────────────────────────────────────────────────────────────────────
-- Build snapshot table (Lua) from current database state
-- ────────────────────────────────────────────────────────────────────────────

build_snapshot = (include_data) ->
  snap = {
    version:     '1'
    exported_at: os.date '!%Y-%m-%dT%H:%M:%SZ'
    schema: {
      spaces: {}
      relations: {}
      custom_views: {}
      widget_plugins: {}
      groups: {}
    }
  }

  -- Spaces + fields + views
  for sp in *spaces_mod.list_spaces!
    fields = {}
    for f in *spaces_mod.list_fields sp.id
      entry = {
        name:      f.name
        fieldType: f.fieldType
        notNull:   f.notNull
        position:  f.position
      }
      entry.description   = f.description   if f.description and f.description != ''
      entry.formula       = f.formula       if f.formula and f.formula != ''
      entry.triggerFields = f.triggerFields if f.triggerFields
      entry.language      = f.language      if f.language and f.language != 'lua'
      table.insert fields, entry

    sp_views = {}
    for v in *views_mod.list_views sp.id
      table.insert sp_views, { name: v.name, viewType: v.viewType }

    sp_entry = { name: sp.name, fields: fields, views: sp_views }
    sp_entry.description = sp.description if sp.description and sp.description != ''
    table.insert snap.schema.spaces, sp_entry

  -- Relations (one pass over all spaces, deduplicate by collecting once)
  seen_rels = {}
  for sp in *spaces_mod.list_spaces!
    for rel in *list_relations_for_space sp.id
      from_sp   = space_name_by_id rel.fromSpaceId
      from_fld  = field_name_by_id rel.fromFieldId
      to_sp     = space_name_by_id rel.toSpaceId
      to_fld    = field_name_by_id rel.toFieldId
      continue unless from_sp and from_fld and to_sp and to_fld
      key = "#{rel.fromSpaceId}/#{rel.fromFieldId}/#{rel.toSpaceId}/#{rel.toFieldId}"
      continue if seen_rels[key]
      seen_rels[key] = true
      table.insert snap.schema.relations, {
        fromSpace: from_sp, fromField: from_fld
        toSpace: to_sp, toField: to_fld
      }

  -- Custom views
  for cv in *box.space._tdb_custom_views\select {}
    entry = { name: cv[2], yaml: cv[4] }
    entry.description = cv[3] if cv[3] and cv[3] != ''
    table.insert snap.schema.custom_views, entry

  -- Widget plugins
  for wp in *box.space._tdb_widget_plugins\select {}
    entry = {
      name: wp[2]
      scriptLanguage: wp[4] or 'coffeescript'
      templateLanguage: wp[5] or 'pug'
      scriptCode: wp[6] or ''
      templateCode: wp[7] or ''
    }
    entry.description = wp[3] if wp[3] and wp[3] != ''
    table.insert snap.schema.widget_plugins, entry

  -- Groups + members + permissions
  for g in *box.space._tdb_groups\select {}
    members = {}
    for m in *box.space._tdb_memberships.index.by_group\select { g[1] }
      u = box.space._tdb_users\get m[1]
      table.insert members, u[2] if u
    permissions = {}
    for p in *perms_mod.list_permissions g[1]
      perm_entry = { resourceType: p.resourceType, level: p.level }
      if p.resourceId and p.resourceId != perms_mod.WILDCARD_ID
        rname = space_name_by_id p.resourceId
        perm_entry.resourceId = rname or p.resourceId
      table.insert permissions, perm_entry
    g_entry = { name: g[2], members: members, permissions: permissions }
    g_entry.description = g[3] if g[3] and g[3] != ''
    table.insert snap.schema.groups, g_entry

  -- Data (optional)
  if include_data
    snap.data = {}
    for sp in *spaces_mod.list_spaces!
      user_sp = box.space["data_#{sp.name}"]
      continue unless user_sp
      rows = {}
      for tuple in *user_sp\select {}
        row = {}
        for f in *spaces_mod.list_fields sp.id
          row[f.name] = tuple[f.position + 1]  -- position 1-based, tuple[1] = box id
        table.insert rows, row
      snap.data[sp.name] = rows

  snap

-- ────────────────────────────────────────────────────────────────────────────
-- Diff: compare incoming snapshot schema vs current schema
-- ────────────────────────────────────────────────────────────────────────────

diff_snapshot = (snap) ->
  result = {
    spacesToCreate: {}, spacesToDelete: {}
    fieldsToCreate: {}, fieldsToDelete: {}, fieldsToChange: {}
    customViewsToCreate: {}, customViewsToUpdate: {}
    widgetPluginsToCreate: {}, widgetPluginsToUpdate: {}
  }

  -- Index current spaces by name
  current_spaces = {}
  for sp in *spaces_mod.list_spaces!
    current_spaces[sp.name] = sp

  -- Index current custom views by name
  current_cvs = {}
  for cv in *box.space._tdb_custom_views\select {}
    current_cvs[cv[2]] = cv[4]  -- name → yaml

  -- Index current widget plugins by name
  current_wps = {}
  for wp in *box.space._tdb_widget_plugins\select {}
    current_wps[wp[2]] = {
      description: wp[3] or ''
      scriptLanguage: wp[4] or 'coffeescript'
      templateLanguage: wp[5] or 'pug'
      scriptCode: wp[6] or ''
      templateCode: wp[7] or ''
    }

  incoming_spaces = snap.schema and snap.schema.spaces or {}
  incoming_cvs    = snap.schema and snap.schema.custom_views or {}
  incoming_wps    = snap.schema and snap.schema.widget_plugins or {}

  -- Spaces to create / check fields
  incoming_names = {}
  for isp in *incoming_spaces
    incoming_names[isp.name] = true
    if not current_spaces[isp.name]
      table.insert result.spacesToCreate, isp.name
    else
      -- Field-level diff for existing space
      cur_fields = {}
      for f in *spaces_mod.list_fields current_spaces[isp.name].id
        cur_fields[f.name] = f.fieldType
      inc_fields = {}
      for f in *(isp.fields or {})
        inc_fields[f.name] = f.fieldType
        if not cur_fields[f.name]
          table.insert result.fieldsToCreate, { space: isp.name, field: f.name, oldType: nil, newType: f.fieldType }
        elseif cur_fields[f.name] != f.fieldType
          table.insert result.fieldsToChange, { space: isp.name, field: f.name, oldType: cur_fields[f.name], newType: f.fieldType }
      for fname, ftype in pairs cur_fields
        unless inc_fields[fname]
          table.insert result.fieldsToDelete, { space: isp.name, field: fname, oldType: ftype, newType: nil }

  -- Spaces to delete (in current but not in incoming)
  for sname, _ in pairs current_spaces
    unless incoming_names[sname]
      table.insert result.spacesToDelete, sname

  -- Custom views diff
  for icv in *incoming_cvs
    if not current_cvs[icv.name]
      table.insert result.customViewsToCreate, icv.name
    elseif current_cvs[icv.name] != icv.yaml
      table.insert result.customViewsToUpdate, icv.name

  -- Widget plugins diff
  for iwp in *incoming_wps
    cur = current_wps[iwp.name]
    if not cur
      table.insert result.widgetPluginsToCreate, iwp.name
    else
      inc_desc = iwp.description or ''
      inc_script_lang = iwp.scriptLanguage or 'coffeescript'
      inc_tpl_lang = iwp.templateLanguage or 'pug'
      inc_script = iwp.scriptCode or ''
      inc_tpl = iwp.templateCode or ''
      if cur.description != inc_desc or
         cur.scriptLanguage != inc_script_lang or
         cur.templateLanguage != inc_tpl_lang or
         cur.scriptCode != inc_script or
         cur.templateCode != inc_tpl
        table.insert result.widgetPluginsToUpdate, iwp.name

  result

-- ────────────────────────────────────────────────────────────────────────────
-- Import: merge or replace
-- ────────────────────────────────────────────────────────────────────────────

do_import = (snap, mode) ->
  created = 0
  skipped = 0
  errors  = {}
  spaces_by_name = {}  -- name → id (for relations)

  -- In replace mode: delete all existing user spaces (data + meta)
  if mode == 'replace'
    for sp in *spaces_mod.list_spaces!
      ok, err = pcall -> spaces_mod.delete_user_space sp.name
      unless ok
        table.insert errors, "delete space #{sp.name}: #{err}"
    for cv in *box.space._tdb_custom_views\select {}
      box.space._tdb_custom_views\delete cv[1]
    for wp in *box.space._tdb_widget_plugins\select {}
      box.space._tdb_widget_plugins\delete wp[1]
    -- Delete groups except 'admin' (keep users, keep admin group for safety)
    for g in *box.space._tdb_groups\select {}
      perms_mod.delete_group g[1] unless g[2] == 'admin'

  -- Create spaces + fields
  for isp in *(snap.schema and snap.schema.spaces or {})
    existing = nil
    for sp in *spaces_mod.list_spaces!
      if sp.name == isp.name
        existing = sp
        break
    if existing
      spaces_by_name[isp.name] = existing.id
      skipped += 1
    else
      ok, sp_or_err = pcall -> spaces_mod.create_user_space isp.name, isp.description
      if ok
        sid = sp_or_err.id
        spaces_by_name[isp.name] = sid
        -- Add fields (skip 'id' Sequence which is auto-added)
        for f in *(isp.fields or {})
          continue if f.name == 'id' and f.fieldType == 'Sequence'
          ok2, ferr = pcall ->
            spaces_mod.add_field sid, f.name, f.fieldType, f.notNull or false,
              f.description, f.formula, f.triggerFields, f.language
          unless ok2
            table.insert errors, "add field #{isp.name}.#{f.name}: #{ferr}"
        -- Add views
        for v in *(isp.views or {})
          ok3, verr = pcall -> views_mod.create_view sid, v.name, v.viewType or 'Grid'
          unless ok3
            table.insert errors, "add view #{isp.name}/#{v.name}: #{verr}"
        created += 1
      else
        table.insert errors, "create space #{isp.name}: #{sp_or_err}"

  -- Relations
  for rel in *(snap.schema and snap.schema.relations or {})
    ok, err = pcall ->
      from_sid = spaces_by_name[rel.fromSpace]
      to_sid   = spaces_by_name[rel.toSpace]
      error "unknown space #{rel.fromSpace}" unless from_sid
      error "unknown space #{rel.toSpace}"   unless to_sid
      -- Resolve field ids by name
      from_fid, to_fid = nil, nil
      for f in *spaces_mod.list_fields from_sid
        from_fid = f.id if f.name == rel.fromField
      for f in *spaces_mod.list_fields to_sid
        to_fid = f.id if f.name == rel.toField
      error "field #{rel.fromSpace}.#{rel.fromField} not found" unless from_fid
      error "field #{rel.toSpace}.#{rel.toField} not found"     unless to_fid
      -- Check duplicate: return early without error if already exists
      is_dup = false
      for t in *box.space._tdb_relations.index.by_from\select { from_sid }
        if t[3] == from_fid and t[4] == to_sid and t[5] == to_fid
          is_dup = true
          break
      if is_dup
        skipped += 1
        return  -- early return from pcall lambda
      rid = tostring uuid_mod.new!
      box.space._tdb_relations\insert { rid, from_sid, from_fid, to_sid, to_fid, "#{rel.fromSpace}_#{rel.fromField}" }
      created += 1
    unless ok
      table.insert errors, "relation #{rel.fromSpace}.#{rel.fromField}→#{rel.toSpace}.#{rel.toField}: #{err}"

  -- Custom views
  for icv in *(snap.schema and snap.schema.custom_views or {})
    existing_cv = nil
    for cv in *box.space._tdb_custom_views\select {}
      if cv[2] == icv.name
        existing_cv = cv
        break
    if existing_cv
      skipped += 1
    else
      ok, err = pcall ->
        id  = tostring uuid_mod.new!
        now = clock.time!
        box.space._tdb_custom_views\insert { id, icv.name, icv.description or '', icv.yaml or '', now, now }
      if ok then created += 1 else table.insert errors, "custom_view #{icv.name}: #{err}"

  -- Widget plugins
  for iwp in *(snap.schema and snap.schema.widget_plugins or {})
    existing_wp = box.space._tdb_widget_plugins.index.by_name\get iwp.name
    if existing_wp
      skipped += 1
    else
      ok, err = pcall ->
        id  = tostring uuid_mod.new!
        now = clock.time!
        box.space._tdb_widget_plugins\insert {
          id
          iwp.name
          iwp.description or ''
          iwp.scriptLanguage or 'coffeescript'
          iwp.templateLanguage or 'pug'
          iwp.scriptCode or ''
          iwp.templateCode or ''
          now
          now
        }
      if ok then created += 1 else table.insert errors, "widget_plugin #{iwp.name}: #{err}"

  -- Groups + members + permissions
  for ig in *(snap.schema and snap.schema.groups or {})
    existing_g = nil
    for g in *box.space._tdb_groups\select {}
      if g[2] == ig.name
        existing_g = g
        break
    gid = nil
    if existing_g
      gid = existing_g[1]
      skipped += 1
    else
      ok, g_or_err = pcall -> perms_mod.create_group ig.name, ig.description
      if ok
        gid = g_or_err.id
        created += 1
      else
        table.insert errors, "group #{ig.name}: #{g_or_err}"
        continue
    -- Members
    for uname in *(ig.members or {})
      u = auth_mod.get_user_by_username uname
      if u
        ok2, err2 = pcall -> box.space._tdb_memberships\insert { u.id, gid }
        -- ignore duplicate key errors
      else
        table.insert errors, "member #{uname} not found (group #{ig.name})"
    -- Permissions
    for perm in *(ig.permissions or {})
      ok3, err3 = pcall ->
        rid = perms_mod.WILDCARD_ID
        if perm.resourceId
          for sp in *spaces_mod.list_spaces!
            rid = sp.id if sp.name == perm.resourceId
        -- Skip if identical permission already exists
        for ep in *perms_mod.list_permissions gid
          if ep.resourceType == (perm.resourceType or 'space') and ep.resourceId == rid and ep.level == perm.level
            return  -- already exists
        perms_mod.grant gid, perm.resourceType or 'space', rid, perm.level
      unless ok3
        table.insert errors, "permission #{ig.name}/#{perm.level}: #{err3}"

  -- Data
  if snap.data
    for sp_name, rows in pairs snap.data
      sp = nil
      for s in *spaces_mod.list_spaces!
        sp = s if s.name == sp_name
      continue unless sp
      user_sp = box.space["data_#{sp_name}"]
      continue unless user_sp
      fields = spaces_mod.list_fields sp.id
      for row in *rows
        ok4, err4 = pcall ->
          tuple = {}
          for f in *fields
            table.insert tuple, row[f.name]
          user_sp\insert tuple
        if ok4
          created += 1
        else
          table.insert errors, "data #{sp_name}: #{err4}"

  -- Reinit schema after import
  executor.reinit_schema!

  { ok: #errors == 0, created: created, skipped: skipped, errors: errors }

-- ────────────────────────────────────────────────────────────────────────────
-- Resolvers
-- ────────────────────────────────────────────────────────────────────────────

Query =
  exportSnapshot: (_, args, ctx) ->
    require_admin ctx
    snap = build_snapshot args.includeData
    yaml.encode snap

  diffSnapshot: (_, args, ctx) ->
    require_auth ctx
    ok, snap = pcall -> yaml.decode args.yaml
    error "Invalid YAML: #{snap}" unless ok and snap
    diff_snapshot snap

Mutation =
  importSnapshot: (_, args, ctx) ->
    require_admin ctx
    ok, snap = pcall -> yaml.decode args.yaml
    error "Invalid YAML: #{snap}" unless ok and snap
    error "Invalid YAML: expected a mapping" unless type(snap) == 'table'
    do_import snap, args.mode

{ :Query, :Mutation }
