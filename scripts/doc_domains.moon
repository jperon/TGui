-- scripts/doc_domains.moon
-- Summary: Single source of truth mapping each GraphQL operation to a doc domain.
-- Inputs/outputs:
-- - Input : an operation name (Query/Mutation field).
-- - Output: a domain key used by generate_docs (sections) and doc_check (coverage).
-- Used by: scripts/generate_docs.moon, scripts/doc_check.moon.
-- Factorisé pour éviter la duplication entre le générateur et le vérificateur.

starts_with = (s, prefix) -> s\sub(1, #prefix) == prefix

domain_for_operation = (name) ->
  return 'snapshot' if name == 'exportSnapshot' or name == 'diffSnapshot' or name == 'importSnapshot'
  -- App versioning (export/import of app packages) is documented with the
  -- closest existing domain, Snapshots; a dedicated 'Applications' domain would
  -- need a matching label/order in scripts/generate_docs.moon (out of scope).
  return 'snapshot' if name == 'listApps' or name == 'appItems' or name == 'exportApp' or name == 'previewAppUpdate' or name == 'previewAppPurge' or name == 'applyAppUpdate' or name == 'purgeAppObsolete'
  return 'auth' if name == 'login' or name == 'logout' or name == 'me' or name == 'changePassword' or name == 'adminSetPassword'
  return 'users_groups' if starts_with(name, 'createUser') or starts_with(name, 'createGroup') or starts_with(name, 'deleteGroup') or starts_with(name, 'addMember') or starts_with(name, 'removeMember') or name == 'users' or name == 'user' or name == 'groups' or name == 'group' or name == 'grant' or name == 'revoke'
  return 'spaces_fields' if starts_with(name, 'space') or starts_with(name, 'createSpace') or starts_with(name, 'updateSpace') or starts_with(name, 'deleteSpace') or starts_with(name, 'addField') or starts_with(name, 'addFields') or starts_with(name, 'removeField') or starts_with(name, 'reorderFields') or starts_with(name, 'updateField') or starts_with(name, 'changeFieldType')
  return 'data_views' if starts_with(name, 'dataView') or starts_with(name, 'createDataView') or starts_with(name, 'updateDataView') or starts_with(name, 'deleteDataView') or starts_with(name, 'executeDataView') or starts_with(name, 'addDataViewToPage')
  return 'widget_plugins' if starts_with(name, 'widgetPlugin') or starts_with(name, 'createWidgetPlugin') or starts_with(name, 'updateWidgetPlugin') or starts_with(name, 'deleteWidgetPlugin')
  return 'layouts' if starts_with(name, 'layoutSnapshot') or starts_with(name, 'listLayoutSnapshots') or starts_with(name, 'createLayoutSnapshot') or starts_with(name, 'restoreLayoutSnapshot') or starts_with(name, 'exportLayout') or starts_with(name, 'importLayout') or starts_with(name, 'createZone') or starts_with(name, 'resizeZone') or starts_with(name, 'mergeZones') or starts_with(name, 'splitZone') or starts_with(name, 'addWidgetToView') or starts_with(name, 'reorderWidgets') or starts_with(name, 'updateWidgetInView') or starts_with(name, 'removeWidgetFromView')
  return 'views' if starts_with(name, 'view') or starts_with(name, 'views') or starts_with(name, 'createView') or starts_with(name, 'updateView') or starts_with(name, 'deleteView') or starts_with(name, 'customView') or starts_with(name, 'customViews') or starts_with(name, 'createCustomView') or starts_with(name, 'updateCustomView') or starts_with(name, 'deleteCustomView')
  return 'relations' if starts_with(name, 'relation') or starts_with(name, 'relations') or starts_with(name, 'createRelation') or starts_with(name, 'updateRelation') or starts_with(name, 'deleteRelation') or starts_with(name, 'gridColumnPrefs') or starts_with(name, 'saveGridColumnPrefs')
  return 'records' if starts_with(name, 'record') or starts_with(name, 'records') or starts_with(name, 'insertRecord') or starts_with(name, 'insertRecords') or starts_with(name, 'updateRecord') or starts_with(name, 'updateRecords') or starts_with(name, 'restoreRecords') or starts_with(name, 'deleteRecord') or starts_with(name, 'deleteRecords') or starts_with(name, 'aggregateSpace')
  'misc'

{ :starts_with, :domain_for_operation }
