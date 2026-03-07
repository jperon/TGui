-- core/permissions.moon
-- Unix-style group permissions management.
-- Each permission record: (group, resource_type, resource_id, level)
-- level: 'read' | 'write' | 'admin'
-- resource_type: 'space' | 'view' | '*'
-- resource_id: UUID of the resource, or a sentinel UUID for wildcard '*'

uuid_mod = require 'uuid'

-- Sentinel UUID used for wildcard permissions (resource_id = '*')
WILDCARD_ID = '00000000-0000-0000-0000-000000000000'

LEVELS = { read: 1, write: 2, admin: 3 }
level_value = (l) -> LEVELS[l] or 0

-- ────────────────────────────────────────────────────────────────────────────
-- Group management
-- ────────────────────────────────────────────────────────────────────────────

create_group = (name, description) ->
  gid = tostring uuid_mod.new!
  box.space._tdb_groups\insert { gid, name, description or '', os.time! }
  { id: gid, name: name, description: description }

delete_group = (group_id) ->
  box.space._tdb_groups\delete group_id
  -- cascade delete memberships and permissions
  mems = {}
  for t in *box.space._tdb_memberships.index.by_group\select { group_id }
    table.insert mems, t
  for t in *mems
    box.space._tdb_memberships\delete { t[1], t[2] }
  perms = {}
  for t in *box.space._tdb_permissions.index.by_group\select { group_id }
    table.insert perms, t
  for t in *perms
    box.space._tdb_permissions\delete t[1]

list_groups = ->
  result = {}
  for t in *box.space._tdb_groups\select {}
    table.insert result, { id: t[1], name: t[2], description: t[3], createdAt: t[4] }
  result

get_group = (id) ->
  t = box.space._tdb_groups\get id
  return nil unless t
  { id: t[1], name: t[2], description: t[3], createdAt: t[4] }

-- ────────────────────────────────────────────────────────────────────────────
-- Membership
-- ────────────────────────────────────────────────────────────────────────────

add_member = (user_id, group_id) ->
  box.space._tdb_memberships\insert { user_id, group_id }

remove_member = (user_id, group_id) ->
  box.space._tdb_memberships\delete { user_id, group_id }

user_groups = (user_id) ->
  result = {}
  for t in *box.space._tdb_memberships.index.by_user\select { user_id }
    g = box.space._tdb_groups\get t[2]
    if g then table.insert result, { id: g[1], name: g[2] }
  result

group_members = (group_id) ->
  result = {}
  for t in *box.space._tdb_memberships.index.by_group\select { group_id }
    u = box.space._tdb_users\get t[1]
    if u then table.insert result, { id: u[1], username: u[2] }
  result

-- ────────────────────────────────────────────────────────────────────────────
-- Permission CRUD
-- ────────────────────────────────────────────────────────────────────────────

grant = (group_id, resource_type, resource_id, level) ->
  pid = tostring uuid_mod.new!
  rid = resource_id or WILDCARD_ID
  box.space._tdb_permissions\insert { pid, group_id, resource_type, rid, level }
  { id: pid, groupId: group_id, resourceType: resource_type, resourceId: rid, level: level }

revoke = (permission_id) ->
  box.space._tdb_permissions\delete permission_id

list_permissions = (group_id) ->
  result = {}
  for t in *box.space._tdb_permissions.index.by_group\select { group_id }
    table.insert result, {
      id:           t[1]
      groupId:      t[2]
      resourceType: t[3]
      resourceId:   t[4]
      level:        t[5]
    }
  result

-- ────────────────────────────────────────────────────────────────────────────
-- Authorization check
-- ────────────────────────────────────────────────────────────────────────────

-- Returns true if user has at least `required_level` on the given resource.
can = (user_id, resource_type, resource_id, required_level) ->
  groups = user_groups user_id
  required_val = level_value required_level

  for g in *groups
    -- check specific resource permission
    for t in *box.space._tdb_permissions.index.by_resource\select { resource_type, resource_id }
      if t[2] == g.id and level_value(t[5]) >= required_val
        return true
    -- check wildcard permission for this resource_type
    for t in *box.space._tdb_permissions.index.by_resource\select { resource_type, WILDCARD_ID }
      if t[2] == g.id and level_value(t[5]) >= required_val
        return true
    -- check global wildcard '*'
    for t in *box.space._tdb_permissions.index.by_resource\select { '*', WILDCARD_ID }
      if t[2] == g.id and level_value(t[5]) >= required_val
        return true

  false

{ :create_group, :delete_group, :list_groups, :get_group,
  :add_member, :remove_member, :user_groups, :group_members,
  :grant, :revoke, :list_permissions,
  :can, :WILDCARD_ID }
