-- backend/fixtures.moon
-- Fixtures du conteneur de test : sur une base vide, installe l'application
-- « Bibliothèque » (structure backend/apps/bibliotheque + seed déterministe
-- assemblés par tools/bibliotheque_app). Appelé par backend/init.moon
-- (TGUI_TEST_ENV=true) et backend/test_runner.moon, avant la découverte des
-- tests : tests/test_app_bibliotheque_install.moon contrôle cet état installé.
--
-- apply_update réinitialise lui-même le schéma GraphQL (_finalize appelle
-- executor.reinit_schema!) : rien d'autre à appeler ici, on se contente de
-- signaler une reinitialisation en échec.

log = require 'log'
spaces = require 'core.spaces'

-- Installe la bibliothèque uniquement quand la base est vide.
setup_demo_data = ->
  -- Un espace utilisateur existant signifie que la base n'est plus vide :
  -- on n'y touche pas (comportement historique des fixtures).
  all_spaces = spaces.list_spaces!
  user_spaces = [space for space in *all_spaces when not space.name\match '^_tdb_']
  return if #user_spaces > 0

  log.info "fixtures: installation de l'application Bibliothèque..."
  pkg = require('tools.bibliotheque_app').build!
  apply = require 'core.app_apply'
  report = apply.apply_update pkg, {}, {}

  unless report.ok
    error "fixtures: apply_update de l'application Bibliothèque a échoué: #{report.error or 'erreur inconnue'}"
  if report.reinit_error
    error "fixtures: reinitialisation du schema GraphQL echouee: #{report.reinit_error}"

  log.info "fixtures: Bibliothèque installée (#{#report.created} éléments créés, #{#report.updated} mis à jour)."
  nil

{ :setup_demo_data }
