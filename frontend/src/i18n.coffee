# i18n.coffee — Localisation légère sans dépendance externe.

I18N_KEY = 'tgui_locale'

CATALOGS =
  fr:
    common:
      ok: 'OK'
      cancel: 'Annuler'
      error: 'Erreur'
      success: 'Succès'
    ui:
      appName: 'TGui'
      login:
        title: 'TGui'
        button: 'Connexion'
      menu:
        changePassword: 'Changer le mot de passe'
        logout: 'Déconnexion'
        langFr: 'FR'
        langEn: 'EN'
      prompts:
        newSpace: 'Nom du nouvel espace :'
        newView: 'Nom de la nouvelle vue :'
        newPasswordFor: 'Nouveau mot de passe pour {username} :'
        renameSpace: "Nouveau nom de l'espace :"
      confirms:
        deleteGroup: 'Supprimer le groupe « {name} » ?'
        deleteView: 'Supprimer la vue « {name} » ?'
        deleteSpace: "Supprimer l'espace « {name} » et toutes ses données ?"
        deleteField: 'Supprimer le champ « {name} » ?'
        replaceImport: '⚠ Mode Remplacement : toutes les données existantes seront effacées. Continuer ?'
      alerts:
        passwordChanged: 'Mot de passe changé.'
        passwordChangedSuccess: 'Mot de passe changé avec succès.'
        targetNoSequence: "L'espace cible n'a pas de champ Séquence."
      admin:
        pwdBtnTitle: 'Changer le mot de passe'
        deleteGroupTitle: 'Supprimer le groupe'
      validation:
        requiredAllFields: 'Veuillez remplir tous les champs.'
        newPasswordsMismatch: 'Les nouveaux mots de passe ne correspondent pas.'
        currentPasswordIncorrect: 'Erreur : mot de passe actuel incorrect.'
        usernamePasswordRequired: "Nom d'utilisateur et mot de passe requis."
        groupNameRequired: 'Le nom est requis.'
      fields:
        add: 'Ajouter'
        update: 'Mettre à jour'
        noneDefined: 'Aucun champ défini.'
        namePlaceholder: 'Nom du champ'
        dragToReorder: 'Glisser pour réordonner'
        triggerCreation: 'création'
        triggerAnyChange: 'tout changement'
        computedColumn: 'Colonne calculée'
      snapshot:
        importOk: '✓ Import réussi — {created} créé(s), {skipped} ignoré(s).'
        importErr: '⚠ Import terminé avec erreurs — {created} créé(s), {skipped} ignoré(s).'
        fieldToCreate: '<code>{space}.{field}</code> ({newType}) — à créer'
        fieldToDelete: '<code>{space}.{field}</code> ({oldType}) — sera supprimé'
        noop: '✓ Le schéma importé correspond exactement au schéma actuel.'
        sectionSpacesDelete: '⚠ Espaces à supprimer (données perdues)'
        sectionSpacesCreate: '+ Espaces à créer'
        sectionFieldsDelete: '⚠ Champs à supprimer'
        sectionFieldsChange: '~ Champs à modifier (type)'
        sectionFieldsCreate: '+ Champs à créer'
        sectionCustomViewsCreate: '+ Vues personnalisées à créer'
        sectionCustomViewsUpdate: '~ Vues personnalisées à mettre à jour'
  en:
    common:
      ok: 'OK'
      cancel: 'Cancel'
      error: 'Error'
      success: 'Success'
    ui:
      appName: 'TGui'
      login:
        title: 'TGui'
        button: 'Sign in'
      menu:
        changePassword: 'Change password'
        logout: 'Sign out'
        langFr: 'FR'
        langEn: 'EN'
      prompts:
        newSpace: 'Name of the new space:'
        newView: 'Name of the new view:'
        newPasswordFor: 'New password for {username}:'
        renameSpace: 'New space name:'
      confirms:
        deleteGroup: 'Delete group “{name}”?'
        deleteView: 'Delete view “{name}”?'
        deleteSpace: 'Delete space “{name}” and all its data?'
        deleteField: 'Delete field “{name}”?'
        replaceImport: '⚠ Replace mode: all existing data will be erased. Continue?'
      alerts:
        passwordChanged: 'Password changed.'
        passwordChangedSuccess: 'Password changed successfully.'
        targetNoSequence: 'The target space has no Sequence field.'
      admin:
        pwdBtnTitle: 'Change password'
        deleteGroupTitle: 'Delete group'
      validation:
        requiredAllFields: 'Please fill in all fields.'
        newPasswordsMismatch: 'New passwords do not match.'
        currentPasswordIncorrect: 'Error: current password is incorrect.'
        usernamePasswordRequired: 'Username and password are required.'
        groupNameRequired: 'Group name is required.'
      fields:
        add: 'Add'
        update: 'Update'
        noneDefined: 'No field defined.'
        namePlaceholder: 'Field name'
        dragToReorder: 'Drag to reorder'
        triggerCreation: 'creation'
        triggerAnyChange: 'any change'
        computedColumn: 'Computed column'
      snapshot:
        importOk: '✓ Import successful — {created} created, {skipped} skipped.'
        importErr: '⚠ Import completed with errors — {created} created, {skipped} skipped.'
        fieldToCreate: '<code>{space}.{field}</code> ({newType}) — to create'
        fieldToDelete: '<code>{space}.{field}</code> ({oldType}) — will be deleted'
        noop: '✓ Imported schema exactly matches current schema.'
        sectionSpacesDelete: '⚠ Spaces to delete (data loss)'
        sectionSpacesCreate: '+ Spaces to create'
        sectionFieldsDelete: '⚠ Fields to delete'
        sectionFieldsChange: '~ Fields to modify (type)'
        sectionFieldsCreate: '+ Fields to create'
        sectionCustomViewsCreate: '+ Custom views to create'
        sectionCustomViewsUpdate: '~ Custom views to update'

_locale = 'fr'

pick_locale = (raw) ->
  return 'fr' unless raw
  l = String(raw).toLowerCase()
  return 'en' if l.indexOf('en') == 0
  'fr'

lookup = (obj, path) ->
  cur = obj
  for part in path.split('.')
    return null unless cur? and Object::hasOwnProperty.call(cur, part)
    cur = cur[part]
  cur

interpolate = (template, vars = {}) ->
  return template unless typeof template == 'string'
  template.replace /\{([a-zA-Z0-9_]+)\}/g, (_, key) ->
    return '' unless vars?
    if Object::hasOwnProperty.call(vars, key) then String(vars[key]) else ''

t = (key, vars = {}, locale = _locale) ->
  primary = lookup(CATALOGS[locale], key)
  fallback = lookup(CATALOGS.fr, key)
  msg = primary or fallback or key
  interpolate msg, vars

apply_to_dom = (root = document) ->
  root.querySelectorAll('[data-i18n]').forEach (el) ->
    key = el.getAttribute('data-i18n')
    el.textContent = t key if key
  root.querySelectorAll('[data-i18n-placeholder]').forEach (el) ->
    key = el.getAttribute('data-i18n-placeholder')
    el.setAttribute 'placeholder', t(key) if key
  root.querySelectorAll('[data-i18n-title]').forEach (el) ->
    key = el.getAttribute('data-i18n-title')
    el.setAttribute 'title', t(key) if key
  document.documentElement.lang = _locale

window.I18N =
  getLocale: -> _locale
  t: (key, vars = {}, locale = _locale) -> t key, vars, locale
  setLocale: (locale) ->
    _locale = pick_locale locale
    localStorage.setItem I18N_KEY, _locale
    apply_to_dom document
    window.dispatchEvent new CustomEvent('i18n:locale-changed', { detail: { locale: _locale } })
    _locale
  init: ->
    stored = localStorage.getItem I18N_KEY
    browser = navigator.language or navigator.userLanguage
    _locale = pick_locale(stored or browser)
    apply_to_dom document
    _locale
  apply: (root = document) -> apply_to_dom root
