-- graphql/sdl_registry.moon
-- Passive MoonScript source of truth for static root GraphQL fields.
-- This registry is intentionally additive and does not replace schema/tdb.graphql yet.

Query = {
  { name: 'spaces',       args: '',                           returns: '[Space!]!' }
  { name: 'space',        args: 'id: ID!',                    returns: 'Space' }
  { name: 'views',        args: 'spaceId: ID!',               returns: '[View!]!' }
  { name: 'view',         args: 'id: ID!',                    returns: 'View' }
  { name: 'customViews',  args: '',                           returns: '[CustomView!]!' }
  { name: 'customView',   args: 'id: ID!',                    returns: 'CustomView' }
  { name: 'records',      args: 'spaceId: ID!, filter: RecordFilter, limit: Int, offset: Int, reprFormula: String, reprLanguage: String', returns: 'RecordPage!' }
  { name: 'record',       args: 'spaceId: ID!, id: ID!',      returns: 'Record' }
  { name: 'relations',    args: 'spaceId: ID!',               returns: '[Relation!]!' }
  { name: 'me',           args: '',                           returns: 'User' }
  { name: 'users',        args: '',                           returns: '[User!]!' }
  { name: 'user',         args: 'id: ID!',                    returns: 'User' }
  { name: 'groups',       args: '',                           returns: '[Group!]!' }
  { name: 'group',        args: 'id: ID!',                    returns: 'Group' }
  { name: 'exportSnapshot', args: 'includeData: Boolean!',    returns: 'String!' }
  { name: 'diffSnapshot', args: 'yaml: String!',              returns: 'SnapshotDiff!' }
  { name: 'aggregateSpace', args: 'spaceName: String!, groupBy: [String!], aggregate: [AggregateSpec!]', returns: '[AggregateResult!]!' }
}

Mutation = {
  { name: 'createSpace',      args: 'input: CreateSpaceInput!',         returns: 'Space!' }
  { name: 'updateSpace',      args: 'id: ID!, input: UpdateSpaceInput!', returns: 'Space!' }
  { name: 'deleteSpace',      args: 'id: ID!',                           returns: 'Boolean!' }
  { name: 'addField',         args: 'spaceId: ID!, input: AddFieldInput!', returns: 'Field!' }
  { name: 'addFields',        args: 'spaceId: ID!, inputs: [AddFieldInput!]!', returns: '[Field!]!' }
  { name: 'reorderFields',    args: 'spaceId: ID!, fieldIds: [ID!]!',    returns: '[Field!]!' }
  { name: 'updateField',      args: 'fieldId: ID!, input: UpdateFieldInput!', returns: 'Field!' }
  { name: 'removeField',      args: 'fieldId: ID!',                      returns: 'Boolean!' }
  { name: 'createView',       args: 'spaceId: ID!, input: CreateViewInput!', returns: 'View!' }
  { name: 'updateView',       args: 'id: ID!, input: UpdateViewInput!',  returns: 'View!' }
  { name: 'deleteView',       args: 'id: ID!',                           returns: 'Boolean!' }
  { name: 'createRelation',   args: 'input: CreateRelationInput!',       returns: 'Relation!' }
  { name: 'updateRelation',   args: 'id: ID!, input: UpdateRelationInput!', returns: 'Relation' }
  { name: 'deleteRelation',   args: 'id: ID!',                           returns: 'Boolean!' }
  { name: 'createCustomView', args: 'input: CreateCustomViewInput!',     returns: 'CustomView!' }
  { name: 'updateCustomView', args: 'id: ID!, input: UpdateCustomViewInput!', returns: 'CustomView!' }
  { name: 'deleteCustomView', args: 'id: ID!',                           returns: 'Boolean!' }
  { name: 'insertRecord',     args: 'spaceId: ID!, data: JSON!',         returns: 'Record!' }
  { name: 'updateRecord',     args: 'spaceId: ID!, id: ID!, data: JSON!', returns: 'Record!' }
  { name: 'deleteRecord',     args: 'spaceId: ID!, id: ID!',             returns: 'Boolean!' }
  { name: 'deleteRecords',    args: 'spaceId: ID!, ids: [ID!]!',         returns: '[Boolean!]!' }
  { name: 'insertRecords',    args: 'spaceId: ID!, data: [JSON!]!',      returns: '[Record!]!' }
  { name: 'updateRecords',    args: 'spaceId: ID!, records: [RecordUpdateInput!]!', returns: '[Record!]!' }
  { name: 'login',            args: 'username: String!, password: String!', returns: 'AuthPayload!' }
  { name: 'logout',           args: '',                                   returns: 'Boolean!' }
  { name: 'createUser',       args: 'input: CreateUserInput!',            returns: 'User!' }
  { name: 'changePassword',   args: 'currentPassword: String!, newPassword: String!', returns: 'Boolean!' }
  { name: 'adminSetPassword', args: 'userId: ID!, newPassword: String!',  returns: 'Boolean!' }
  { name: 'createGroup',      args: 'input: CreateGroupInput!',           returns: 'Group!' }
  { name: 'deleteGroup',      args: 'id: ID!',                            returns: 'Boolean!' }
  { name: 'addMember',        args: 'groupId: ID!, userId: ID!',          returns: 'Boolean!' }
  { name: 'removeMember',     args: 'groupId: ID!, userId: ID!',          returns: 'Boolean!' }
  { name: 'grant',            args: 'groupId: ID!, input: GrantInput!',   returns: 'Permission!' }
  { name: 'revoke',           args: 'permissionId: ID!',                  returns: 'Boolean!' }
  { name: 'importSnapshot',   args: 'yaml: String!, mode: ImportMode!',   returns: 'ImportResult!' }
}

{ :Query, :Mutation }
