# app_apps_helpers.coffee
# Interface « Applications » (versionnage des apps).
#
# Logique pure testable (isSemver, buildDecisions, confirmationTarget,
# summarizePlan, hasCodeChanges) séparée du DOM. Tout contenu provenant d'un
# paquet ou de la base est inséré par textContent / createElement, jamais par
# innerHTML ni par concaténation de HTML (sécurité, spec §4).

window.AppAppsHelpers =
  # ── Fonctions pures ────────────────────────────────────────────────────────

  # x.y.z entièrement numérique (pas de préfixe « v », pas de suffixe).
  isSemver: (v) ->
    typeof v == 'string' and /^\d+\.\d+\.\d+$/.test v

  # conflicts: [{key, ...}] — choices: { key: 'local' | 'delivered' }
  # Retourne [{key, choice}] dans l'ordre des conflits, défaut « local ».
  buildDecisions: (conflicts, choices) ->
    result = []
    for c in (conflicts or [])
      choice = (choices or {})[c.key] or 'local'
      result.push { key: c.key, choice: choice }
    result

  # Un seul élément sélectionné → partie de la clé après le dernier ':' ;
  # plusieurs → identifiant de l'application.
  confirmationTarget: (keys, appId) ->
    ks = keys or []
    if ks.length == 1
      k = String ks[0]
      idx = k.lastIndexOf ':'
      if idx >= 0 then k.slice(idx + 1) else k
    else
      appId

  # Compteurs du plan.
  summarizePlan: (plan) ->
    {
      create:    (plan.create    or []).length
      update:    (plan.update    or []).length
      conflict:  (plan.conflict  or []).length
      keepLocal: (plan.keepLocal or []).length
      obsolete:  (plan.obsolete  or []).length
      rename:    (plan.rename    or []).length
      unchanged: (plan.unchanged or []).length
      errors:    (plan.errors    or []).length
    }

  # Vrai si un élément créé/mis à jour/en conflit porte du code tiers.
  hasCodeChanges: (plan) ->
    groups = [(plan.create or []), (plan.update or []), (plan.conflict or [])]
    for group in groups
      for item in group
        return true if item.isCode == true
        t = item.type
        return true if t == 'plugin' or t == 'page' or t == 'dataview'
    false

  # ── Aides DOM (jamais d'innerHTML) ─────────────────────────────────────────

  _makeEl: (tag, className, text) ->
    el = document.createElement tag
    el.className = className if className
    el.textContent = text if text? and text != null
    el

  _clear: (node) ->
    return unless node
    node.textContent = ''
    if node._children then node._children.length = 0
    if node.children then node.children.length = 0

  # ── Liste des applications installées ──────────────────────────────────────

  loadApps: (app) ->
    GQL.query """
      { listApps { appId name version installedAt source activeCount obsoleteCount } }
    """
    .then (data) ->
      window.AppAppsHelpers.renderAppsList app, data.listApps
    .catch (err) -> tdbAlert app._err(err), 'error'

  renderAppsList: (app, apps) ->
    app._appList = apps or []
    list = app.el.appsList()
    window.AppAppsHelpers._clear list
    for info in app._appList
      row = window.AppAppsHelpers._makeEl 'div', 'apps-list-item'
      row.appendChild window.AppAppsHelpers._makeEl 'div', 'apps-item-name', String info.name
      meta = window.AppAppsHelpers._makeEl 'div', 'apps-item-meta'
      meta.appendChild window.AppAppsHelpers._makeEl 'span', null, app._t('ui.apps.version', { version: info.version })
      meta.appendChild window.AppAppsHelpers._makeEl 'span', null, ' · '
      meta.appendChild window.AppAppsHelpers._makeEl 'span', null, app._t('ui.apps.activeCount', { count: info.activeCount })
      meta.appendChild window.AppAppsHelpers._makeEl 'span', null, ' · '
      meta.appendChild window.AppAppsHelpers._makeEl 'span', null, app._t('ui.apps.obsoleteCount', { count: info.obsoleteCount })
      row.appendChild meta
      list.appendChild row
    hasObsolete = app._appList.some (a) -> (a.obsoleteCount or 0) > 0
    app.el.appsPurgeOpenBtn().disabled = not hasObsolete

  # ── Liaison des évènements ─────────────────────────────────────────────────

  bindAppsPanel: (app) ->
    app._appList = []
