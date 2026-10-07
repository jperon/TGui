local starts_with
starts_with = function(s, prefix)
  return s:sub(1, #prefix) == prefix
end
local domain_for_operation
domain_for_operation = function(name)
  if name == 'exportSnapshot' or name == 'diffSnapshot' or name == 'importSnapshot' then
    return 'snapshot'
  end
  if name == 'listApps' or name == 'appItems' or name == 'exportApp' or name == 'previewAppUpdate' or name == 'previewAppPurge' or name == 'applyAppUpdate' or name == 'purgeAppObsolete' then
    return 'snapshot'
  end
  if name == 'login' or name == 'logout' or name == 'me' or name == 'changePassword' or name == 'adminSetPassword' then
    return 'auth'
  end
  if starts_with(name, 'createUser') or starts_with(name, 'createGroup') or starts_with(name, 'deleteGroup') or starts_with(name, 'addMember') or starts_with(name, 'removeMember') or name == 'users' or name == 'user' or name == 'groups' or name == 'group' or name == 'grant' or name == 'revoke' then
    return 'users_groups'
  end
  if starts_with(name, 'space') or starts_with(name, 'createSpace') or starts_with(name, 'updateSpace') or starts_with(name, 'deleteSpace') or starts_with(name, 'addField') or starts_with(name, 'addFields') or starts_with(name, 'removeField') or starts_with(name, 'reorderFields') or starts_with(name, 'updateField') or starts_with(name, 'changeFieldType') then
    return 'spaces_fields'
  end
  if starts_with(name, 'dataView') or starts_with(name, 'createDataView') or starts_with(name, 'updateDataView') or starts_with(name, 'deleteDataView') or starts_with(name, 'executeDataView') or starts_with(name, 'addDataViewToPage') then
    return 'data_views'
  end
  if starts_with(name, 'widgetPlugin') or starts_with(name, 'createWidgetPlugin') or starts_with(name, 'updateWidgetPlugin') or starts_with(name, 'deleteWidgetPlugin') then
    return 'widget_plugins'
  end
  if starts_with(name, 'layoutSnapshot') or starts_with(name, 'listLayoutSnapshots') or starts_with(name, 'createLayoutSnapshot') or starts_with(name, 'restoreLayoutSnapshot') or starts_with(name, 'exportLayout') or starts_with(name, 'importLayout') or starts_with(name, 'createZone') or starts_with(name, 'resizeZone') or starts_with(name, 'mergeZones') or starts_with(name, 'splitZone') or starts_with(name, 'addWidgetToView') or starts_with(name, 'reorderWidgets') or starts_with(name, 'updateWidgetInView') or starts_with(name, 'removeWidgetFromView') then
    return 'layouts'
  end
  if starts_with(name, 'view') or starts_with(name, 'views') or starts_with(name, 'createView') or starts_with(name, 'updateView') or starts_with(name, 'deleteView') or starts_with(name, 'customView') or starts_with(name, 'customViews') or starts_with(name, 'createCustomView') or starts_with(name, 'updateCustomView') or starts_with(name, 'deleteCustomView') then
    return 'views'
  end
  if starts_with(name, 'relation') or starts_with(name, 'relations') or starts_with(name, 'createRelation') or starts_with(name, 'updateRelation') or starts_with(name, 'deleteRelation') or starts_with(name, 'gridColumnPrefs') or starts_with(name, 'saveGridColumnPrefs') then
    return 'relations'
  end
  if starts_with(name, 'record') or starts_with(name, 'records') or starts_with(name, 'insertRecord') or starts_with(name, 'insertRecords') or starts_with(name, 'updateRecord') or starts_with(name, 'updateRecords') or starts_with(name, 'restoreRecords') or starts_with(name, 'deleteRecord') or starts_with(name, 'deleteRecords') or starts_with(name, 'aggregateSpace') then
    return 'records'
  end
  return 'misc'
end
return {
  starts_with = starts_with,
  domain_for_operation = domain_for_operation
}
