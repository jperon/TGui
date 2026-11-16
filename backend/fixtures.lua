local log = require('log')
local spaces = require('core.spaces')
local setup_demo_data
setup_demo_data = function()
  local all_spaces = spaces.list_spaces()
  local user_spaces
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if not space.name:match('^_tdb_') then
        _accum_0[_len_0] = space
        _len_0 = _len_0 + 1
      end
    end
    user_spaces = _accum_0
  end
  if #user_spaces > 0 then
    return 
  end
  log.info("fixtures: installation de l'application Bibliothèque...")
  local pkg = require('tools.bibliotheque_app').build()
  local apply = require('core.app_apply')
  local report = apply.apply_update(pkg, { }, { })
  if not (report.ok) then
    error("fixtures: apply_update de l'application Bibliothèque a échoué: " .. tostring(report.error or 'erreur inconnue'))
  end
  if report.reinit_error then
    error("fixtures: reinitialisation du schema GraphQL echouee: " .. tostring(report.reinit_error))
  end
  log.info("fixtures: Bibliothèque installée (" .. tostring(#report.created) .. " éléments créés, " .. tostring(#report.updated) .. " mis à jour).")
  return nil
end
return {
  setup_demo_data = setup_demo_data
}
