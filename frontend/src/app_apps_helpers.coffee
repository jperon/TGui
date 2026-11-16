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

  # conflicts: [{key, type, ...}] — choices: { key: 'local' | 'delivered' | 'rename' }
  # newNames: { key: nom } (choix « importer sous un autre nom »).
  # Retourne [{key, choice, newName}] dans l'ordre des conflits. Défaut :
  # « rename » pour une définition de widget personnalisé (spec §5 : c'est le
  # choix qui ne perd rien), « local » sinon.
  buildDecisions: (conflicts, choices, newNames) ->
    result = []
    for c in (conflicts or [])
      fallback = if c.type == 'plugin' then 'rename' else 'local'
      choice = (choices or {})[c.key] or fallback
      entry = { key: c.key, choice: choice }
      name = (newNames or {})[c.key]
      entry.newName = name if choice == 'rename' and name
      result.push entry
    result

  # Accès effectif d'une définition livrée, pour l'aperçu : valeur du manifest,
  # « complet » sans manifest (rétrocompatibilité) et « lecture » si le YAML est
  # illisible (le parent traite alors la définition comme `read`).
  pluginAccessOf: (content) ->
    text = content?.manifest
    return 'full' unless text and String(text).trim() != ''
    parser = window.jsyaml
    return 'read' unless parser and typeof parser.load == 'function'
    try
      parsed = parser.load String(text)
    catch e
      return 'read'
    # Commentaires seuls : aucun manifest, donc le comportement historique.
    return 'full' unless parsed and typeof parsed == 'object'
    access = String(parsed.access or 'read').toLowerCase()
    return access if access in ['none', 'read', 'full']
    'read'

  # Défaut proposé pour « importer sous un autre nom » : <nom>_imported.
  defaultImportName: (key) ->
    text = String key or ''
    idx = text.lastIndexOf ':'
    base = if idx >= 0 then text.slice(idx + 1) else text
    "#{base}_imported"

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
  # La liste des types reprend celle du résolveur (CODE_TYPES,
  # backend/resolvers/app_resolvers.moon) : `preset` porte une formule de filtre.
  hasCodeChanges: (plan) ->
    groups = [(plan.create or []), (plan.update or []), (plan.conflict or [])]
    for group in groups
      for item in group
        return true if item.isCode == true
        t = item.type
        return true if t == 'plugin' or t == 'page' or t == 'dataview' or t == 'preset'
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

  # ── Aperçu d'un paquet (installer / mettre à jour) ─────────────────────────

  previewPackage: (app, yamlText) ->
    app.el.appsApplyBtn().disabled = true
    app.el.appsApplyReport().classList.add 'hidden'
    GQL.query """
      query($y: String!, $d: Boolean) {
        previewAppUpdate(yaml: $y, allowDowngrade: $d) {
          create { key type content fingerprint isCode }
          update { key type content fingerprint isCode }
          conflict { key type local delivered pages }
          keepLocal { key type content fingerprint isCode }
          obsolete
          rename { from to }
          unchanged
          errors
        }
      }
    """, { y: yamlText, d: app.el.appsAllowDowngrade().checked }
    .then (data) ->
      plan = data.previewAppUpdate
      app._appPlan = plan
      window.AppAppsHelpers.renderPlan app, plan
    .catch (err) ->
      errEl = app.el.appsPlanErrors()
      window.AppAppsHelpers._clear errEl
      errEl.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-plan-error', app._err(err)
      errEl.classList.remove 'hidden'
      app.el.appsPlanBox().classList.add 'hidden'

  renderPlan: (app, plan) ->
    box = app.el.appsPlanBox()
    window.AppAppsHelpers._clear box
    box.classList.remove 'hidden'
    errors = plan.errors or []
    if errors.length > 0
      errEl = app.el.appsPlanErrors()
      window.AppAppsHelpers._clear errEl
      for e in errors
        errEl.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-plan-error', String e
      errEl.classList.remove 'hidden'
      app.el.appsApplyBtn().disabled = true
      return
    app.el.appsPlanErrors().classList.add 'hidden'
    app.el.appsApplyBtn().disabled = false

    summary = window.AppAppsHelpers.summarizePlan plan
    box.appendChild window.AppAppsHelpers._makeEl 'h4', null, app._t('ui.apps.previewTitle')
    box.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-plan-counts',
      app._t 'ui.apps.counts', summary
    if window.AppAppsHelpers.hasCodeChanges plan
      box.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-code-warning',
        app._t 'ui.apps.codeWarning'

    window.AppAppsHelpers._renderItemSection app, box, 'ui.apps.created', plan.create, 'diff-create'
    window.AppAppsHelpers._renderItemSection app, box, 'ui.apps.updated', plan.update, 'diff-change'
    window.AppAppsHelpers._renderItemSection app, box, 'ui.apps.kept', plan.keepLocal, 'apps-kept'
    window.AppAppsHelpers._renderRenames app, box, plan.rename
    window.AppAppsHelpers._renderObsolete app, box, plan.obsolete
    window.AppAppsHelpers._renderConflicts app, box, plan.conflict
    if summary.unchanged > 0
      box.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-plan-unchanged',
        app._t 'ui.apps.unchanged', { count: summary.unchanged }

  _isCodeItem: (item) ->
    item.isCode == true or item.type == 'plugin' or item.type == 'page' or
      item.type == 'dataview' or item.type == 'preset'

  _accessText: (app, item) ->
    access = window.AppAppsHelpers.pluginAccessOf item.content
    text = switch access
      when 'full' then app._t 'ui.apps.accessFull'
      else access
    app._t 'ui.apps.accessLabel', { access: text }

  _appendItemLabel: (app, li, item) ->
    li.appendChild window.AppAppsHelpers._makeEl 'code', null, String item.key
    li.appendChild window.AppAppsHelpers._makeEl 'span', 'apps-item-type', " (#{item.type or ''})"
    if item.type == 'plugin'
      li.appendChild window.AppAppsHelpers._makeEl 'span', 'apps-plugin-access',
        window.AppAppsHelpers._accessText app, item
    return unless window.AppAppsHelpers._isCodeItem item
    li.appendChild window.AppAppsHelpers._makeEl 'span', 'apps-code-badge', app._t('ui.apps.codeBadge')
    li.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-code-warning', app._t('ui.apps.codeWarning')
    details = document.createElement 'details'
    details.appendChild window.AppAppsHelpers._makeEl 'summary', null, app._t('ui.apps.codeDetails')
    details.appendChild window.AppAppsHelpers._makeEl 'pre', 'apps-code-content',
      JSON.stringify item.content, null, 2
    li.appendChild details

  _renderItemSection: (app, box, titleKey, items, cls) ->
    items or= []
    return if items.length == 0
    box.appendChild window.AppAppsHelpers._makeEl 'h5', null, app._t(titleKey)
    ul = window.AppAppsHelpers._makeEl 'ul', "diff-list #{cls}"
    for item in items
      li = window.AppAppsHelpers._makeEl 'li'
      window.AppAppsHelpers._appendItemLabel app, li, item
      ul.appendChild li
    box.appendChild ul

  _renderRenames: (app, box, renames) ->
    renames or= []
    return if renames.length == 0
    box.appendChild window.AppAppsHelpers._makeEl 'h5', null, app._t('ui.apps.renamed')
    ul = window.AppAppsHelpers._makeEl 'ul', 'diff-list diff-change'
    for r in renames
      li = window.AppAppsHelpers._makeEl 'li'
      li.appendChild window.AppAppsHelpers._makeEl 'code', null, String r.from
      li.appendChild window.AppAppsHelpers._makeEl 'span', null, ' → '
      li.appendChild window.AppAppsHelpers._makeEl 'code', null, String r.to
      ul.appendChild li
    box.appendChild ul

  _renderObsolete: (app, box, obsolete) ->
    obsolete or= []
    return if obsolete.length == 0
    box.appendChild window.AppAppsHelpers._makeEl 'h5', null, app._t('ui.apps.obsolete')
    ul = window.AppAppsHelpers._makeEl 'ul', 'diff-list diff-delete'
    for key in obsolete
      ul.appendChild window.AppAppsHelpers._makeEl 'li', null, String key
    box.appendChild ul

  _radio: (app, parent, name, value, labelText, checked, key) ->
    label = window.AppAppsHelpers._makeEl 'label', 'apps-conflict-radio'
    input = document.createElement 'input'
    input.type = 'radio'
    input.name = name
    input.value = value
    input.checked = checked
    input.addEventListener 'change', ->
      app._appChoices ?= {}
      app._appChoices[key] = value
    label.appendChild input
    label.appendChild window.AppAppsHelpers._makeEl 'span', null, " #{labelText}"
    parent.appendChild label

  _renderConflicts: (app, box, conflicts) ->
    conflicts or= []
    return if conflicts.length == 0
    box.appendChild window.AppAppsHelpers._makeEl 'h5', null, app._t('ui.apps.conflicts')
    app._appChoices ?= {}
    for c, i in conflicts
      container = window.AppAppsHelpers._makeEl 'div', 'apps-conflict'
      container.appendChild window.AppAppsHelpers._makeEl 'div', 'apps-conflict-key', String c.key
      if c.type == 'plugin'
        container.appendChild window.AppAppsHelpers._makeEl 'span', 'apps-plugin-access',
          window.AppAppsHelpers._accessText app, { type: 'plugin', content: c.delivered }
      if window.AppAppsHelpers._isCodeItem { type: c.type }
        container.appendChild window.AppAppsHelpers._makeEl 'span', 'apps-code-badge', app._t('ui.apps.codeBadge')
        container.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-code-warning', app._t('ui.apps.codeWarning')
      row = window.AppAppsHelpers._makeEl 'div', 'apps-conflict-versions'
      localSide = window.AppAppsHelpers._makeEl 'div', 'apps-conflict-side'
      localSide.appendChild window.AppAppsHelpers._makeEl 'div', 'apps-conflict-side-title', app._t('ui.apps.localVersion')
      localSide.appendChild window.AppAppsHelpers._makeEl 'pre', 'apps-conflict-json', JSON.stringify c['local'], null, 2
      deliveredSide = window.AppAppsHelpers._makeEl 'div', 'apps-conflict-side'
      deliveredSide.appendChild window.AppAppsHelpers._makeEl 'div', 'apps-conflict-side-title', app._t('ui.apps.deliveredVersion')
      deliveredSide.appendChild window.AppAppsHelpers._makeEl 'pre', 'apps-conflict-json', JSON.stringify c.delivered, null, 2
      row.appendChild localSide
      row.appendChild deliveredSide
      container.appendChild row
      pages = c.pages or []
      if c.type == 'plugin' and pages.length > 0
        container.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-conflict-pages',
          app._t 'ui.apps.conflictPages', { pages: pages.join ', ' }
      choices = window.AppAppsHelpers._makeEl 'div', 'apps-conflict-choices'
      name = "app-conflict-#{i}"
      fallback = if c.type == 'plugin' then 'rename' else 'local'
      choice = app._appChoices[c.key] or fallback
      window.AppAppsHelpers._radio app, choices, name, 'local', app._t('ui.apps.keepMine'), choice == 'local', c.key
      window.AppAppsHelpers._radio app, choices, name, 'delivered', app._t('ui.apps.takeDelivered'), choice == 'delivered', c.key
      if c.type == 'plugin'
        window.AppAppsHelpers._radio app, choices, name, 'rename', app._t('ui.apps.renameImport'), choice == 'rename', c.key
      container.appendChild choices
      if c.type == 'plugin'
        app._appNewNames ?= {}
        nameRow = window.AppAppsHelpers._makeEl 'div', 'apps-conflict-newname'
        nameRow.appendChild window.AppAppsHelpers._makeEl 'label', null, app._t('ui.apps.renameNewName')
        input = document.createElement 'input'
        input.type = 'text'
        input.className = 'apps-conflict-newname-input'
        input.value = app._appNewNames[c.key] or window.AppAppsHelpers.defaultImportName c.key
        input.addEventListener 'input', ->
          app._appNewNames[c.key] = input.value
        nameRow.appendChild input
        container.appendChild nameRow
      box.appendChild container

  renderApplyReport: (app, r) ->
    box = app.el.appsApplyReport()
    window.AppAppsHelpers._clear box
    box.classList.remove 'hidden'
    box.className = if r.ok then 'snapshot-import-result snapshot-result-ok' else 'snapshot-import-result snapshot-result-err'
    parts = [
      app._t('ui.apps.reportCreated', { count: (r.created or []).length })
      app._t('ui.apps.reportUpdated', { count: (r.updated or []).length })
      app._t('ui.apps.reportKept', { count: (r.kept or []).length })
      app._t('ui.apps.reportObsolete', { count: (r.obsolete or []).length })
    ]
    box.appendChild window.AppAppsHelpers._makeEl 'div', null, parts.join ' · '
    if r.error
      box.appendChild window.AppAppsHelpers._makeEl 'div', 'apps-apply-error', String r.error

  _reloadAppsAndMenu: (app) ->
    app._loadApps?()
    app._loadAll?()

  applyPackage: (app) ->
    return unless app._appPlan and app._appPackageYaml
    decisions = window.AppAppsHelpers.buildDecisions app._appPlan.conflict, (app._appChoices or {}), (app._appNewNames or {})
    tdbConfirm(app._t('ui.confirms.appApply')).then (ok) ->
      return unless ok
      app.el.appsApplyBtn().disabled = true
      GQL.mutate """
        mutation($y: String!, $dec: [AppDecisionInput!], $d: Boolean) {
          applyAppUpdate(yaml: $y, decisions: $dec, allowDowngrade: $d) {
            ok created updated kept unchanged obsolete skipped error
          }
        }
      """, { y: app._appPackageYaml, dec: decisions, d: app.el.appsAllowDowngrade().checked }
      .then (data) ->
        r = data.applyAppUpdate
        window.AppAppsHelpers.renderApplyReport app, r
        changed = r.ok or (r.created or []).length > 0 or (r.updated or []).length > 0
        window.AppAppsHelpers._reloadAppsAndMenu app if changed
      .catch (err) ->
        app.el.appsApplyBtn().disabled = false
        tdbAlert app._err(err), 'error'

  # ── Export d'une application (côté auteur) ─────────────────────────────────

  _download: (filename, content) ->
    blob = new Blob [content], { type: 'text/yaml' }
    url = URL.createObjectURL blob
    a = document.createElement 'a'
    a.href = url
    a.download = filename
    a.click()
    URL.revokeObjectURL url

  exportApp: (app) ->
    id = app.el.appsExportId().value.trim()
    name = app.el.appsExportName().value.trim()
    version = app.el.appsExportVersion().value.trim()
    description = app.el.appsExportDescription().value.trim()
    errEl = app.el.appsExportError()
    errEl.classList.add 'hidden'
    unless id and version
      errEl.textContent = app._t('ui.apps.exportRequired')
      errEl.classList.remove 'hidden'
      return
    unless window.AppAppsHelpers.isSemver version
      errEl.textContent = app._t('ui.apps.invalidVersion')
      errEl.classList.remove 'hidden'
      return
    seed = []
    for line in app.el.appsExportSeed().value.split('\n')
      line = line.trim()
      continue unless line
      parts = line.split(':')
      continue unless parts.length >= 2
      seed.push { space: parts[0].trim(), keyField: parts[1].trim() }
    GQL.query """
      query($meta: AppMetaInput!, $seed: [AppSeedInput!]) {
        exportApp(meta: $meta, seed: $seed)
      }
    """, { meta: { id, name, version, description }, seed }
    .then (data) ->
      window.AppAppsHelpers._download "#{id}-#{version}.tdbapp.yaml", data.exportApp
    .catch (err) ->
      errEl.textContent = app._err(err)
      errEl.classList.remove 'hidden'

  # ── Purge des éléments obsolètes ───────────────────────────────────────────

  openPurge: (app) ->
    target = ((app._appList or []).filter (a) -> (a.obsoleteCount or 0) > 0)[0]
    return unless target
    app._appPurgeAppId = target.appId
    app._appPurgeSelected = []
    app._appPurgePreview = null
    app._appPurgeCheckboxes = []
    app.el.appsPurgeBox().classList.remove 'hidden'
    app.el.appsPurgeReport().classList.add 'hidden'
    app.el.appsPurgeAppName().textContent = target.name or target.appId
    window.AppAppsHelpers._resetPurgeConfirm app
    GQL.query """
      query($id: String!) { appItems(appId: $id) { key type state version } }
    """, { id: target.appId }
    .then (data) ->
      window.AppAppsHelpers.renderPurgeItems app, data.appItems
    .catch (err) -> tdbAlert app._err(err), 'error'

  renderPurgeItems: (app, items) ->
    box = app.el.appsPurgeItems()
    window.AppAppsHelpers._clear box
    app._appPurgeSelected = []
    app._appPurgeCheckboxes = []
    for item in (items or [])
      continue unless item.state == 'obsolète' or item.state == 'obsolete'
      label = window.AppAppsHelpers._makeEl 'label', 'apps-purge-item'
      cb = document.createElement 'input'
      cb.type = 'checkbox'
      cb.value = item.key
      cb.addEventListener 'change', ->
        window.AppAppsHelpers._syncPurgeSelection app
      app._appPurgeCheckboxes.push { input: cb, key: item.key }
      label.appendChild cb
      label.appendChild window.AppAppsHelpers._makeEl 'span', null, " #{item.key} (#{item.type})"
      box.appendChild label
    window.AppAppsHelpers._invalidatePurgePreview app

  _syncPurgeSelection: (app) ->
    app._appPurgeSelected = (e.key for e in (app._appPurgeCheckboxes or []) when e.input.checked)
    window.AppAppsHelpers._invalidatePurgePreview app

  _invalidatePurgePreview: (app) ->
    app._appPurgePreview = null
    app.el.appsPurgePreview().classList.add 'hidden'
    window.AppAppsHelpers._resetPurgeConfirm app

  _resetPurgeConfirm: (app) ->
    app.el.appsPurgeConfirmInput().value = ''
    app.el.appsPurgeConfirmBtn().disabled = true
    app.el.appsPurgeConfirmHint().textContent = ''

  refreshPurgeConfirm: (app) ->
    input = app.el.appsPurgeConfirmInput()
    ok = app._appPurgePreview? and input.value == app._appPurgeTarget
    app.el.appsPurgeConfirmBtn().disabled = not ok

  previewPurge: (app) ->
    keys = app._appPurgeSelected or []
    unless keys.length > 0
      tdbAlert app._t('ui.apps.selectItems'), 'warn'
      return
    GQL.query """
      query($id: String!, $keys: [String!]!) {
        previewAppPurge(appId: $id, keys: $keys) {
          losses { key type records fields relations views }
          totalRecords
        }
      }
    """, { id: app._appPurgeAppId, keys: keys }
    .then (data) ->
      app._appPurgePreview = { preview: data.previewAppPurge, keys: keys }
      window.AppAppsHelpers.renderPurgePreview app, data.previewAppPurge
    .catch (err) -> tdbAlert app._err(err), 'error'

  renderPurgePreview: (app, preview) ->
    box = app.el.appsPurgePreview()
    window.AppAppsHelpers._clear box
    box.classList.remove 'hidden'
    box.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-purge-warning', app._t('ui.apps.purgeWarning')
    table = document.createElement 'table'
    table.className = 'apps-purge-loss'
    thead = document.createElement 'thead'
    hrow = document.createElement 'tr'
    cols = ['ui.apps.colKey', 'ui.apps.colType', 'ui.apps.colRecords',
            'ui.apps.colFields', 'ui.apps.colRelations', 'ui.apps.colViews']
    for colKey in cols
      hrow.appendChild window.AppAppsHelpers._makeEl 'th', null, app._t(colKey)
    thead.appendChild hrow
    table.appendChild thead
    tbody = document.createElement 'tbody'
    for loss in (preview.losses or [])
      tr = document.createElement 'tr'
      vals = [loss.key, loss.type, loss.records, loss.fields, loss.relations, loss.views]
      for v in vals
        tr.appendChild window.AppAppsHelpers._makeEl 'td', null, String v
      tbody.appendChild tr
    table.appendChild tbody
    box.appendChild table
    box.appendChild window.AppAppsHelpers._makeEl 'p', 'apps-purge-total',
      app._t 'ui.apps.purgeTotal', { count: preview.totalRecords }
    app._appPurgeTarget = window.AppAppsHelpers.confirmationTarget(
      (app._appPurgePreview or {}).keys or [], app._appPurgeAppId)
    app.el.appsPurgeConfirmHint().textContent =
      app._t 'ui.apps.confirmHint', { target: app._appPurgeTarget }
    window.AppAppsHelpers.refreshPurgeConfirm app

  confirmPurge: (app) ->
    return unless app._appPurgePreview
    input = app.el.appsPurgeConfirmInput()
    return unless input.value == app._appPurgeTarget
    keys = app._appPurgePreview.keys or []
    tdbConfirm(app._t('ui.apps.confirmPurge', { target: app._appPurgeTarget })).then (ok) ->
      return unless ok
      GQL.mutate """
        mutation($id: String!, $keys: [String!]!, $c: Boolean!) {
          purgeAppObsolete(appId: $id, keys: $keys, confirmed: $c) {
            ok purged error
          }
        }
      """, { id: app._appPurgeAppId, keys: keys, c: true }
      .then (data) ->
        r = data.purgeAppObsolete
        report = app.el.appsPurgeReport()
        window.AppAppsHelpers._clear report
        report.classList.remove 'hidden'
        report.className = if r.ok then 'snapshot-import-result snapshot-result-ok' else 'snapshot-import-result snapshot-result-err'
        report.textContent = if r.ok
          app._t 'ui.apps.purgeOk', { count: (r.purged or []).length }
        else
          app._t 'ui.apps.purgeErr', { error: r.error or '' }
        if r.ok
          app.el.appsPurgeBox().classList.add 'hidden'
          window.AppAppsHelpers._reloadAppsAndMenu app
      .catch (err) -> tdbAlert app._err(err), 'error'

  # ── Liaison des évènements ─────────────────────────────────────────────────

  bindAppsPanel: (app) ->
    app._appList = []
    app._appPackageYaml = null
    app._appPlan = null
    app._appChoices = {}
    app._appPurgeAppId = null
    app._appPurgeSelected = []
    app._appPurgePreview = null
    app._appPurgeCheckboxes = []
    app._appPurgeTarget = ''

    app.el.appsPackageInput().addEventListener 'change', (e) ->
      file = e.target.files[0]
      return unless file
      app.el.appsPackageName().textContent = file.name
      app.el.appsPlanBox().classList.add 'hidden'
      app.el.appsPlanErrors().classList.add 'hidden'
      app.el.appsApplyReport().classList.add 'hidden'
      reader = new FileReader()
      reader.onload = (ev) ->
        app._appPackageYaml = ev.target.result
        app._appChoices = {}
        window.AppAppsHelpers.previewPackage app, app._appPackageYaml
      reader.readAsText file

    app.el.appsAllowDowngrade().addEventListener 'change', ->
      return unless app._appPackageYaml
      window.AppAppsHelpers.previewPackage app, app._appPackageYaml

    app.el.appsApplyBtn().addEventListener 'click', ->
      window.AppAppsHelpers.applyPackage app

    app.el.appsExportBtn().addEventListener 'click', ->
      window.AppAppsHelpers.exportApp app

    app.el.appsPurgeOpenBtn().addEventListener 'click', ->
      window.AppAppsHelpers.openPurge app
    app.el.appsPurgePreviewBtn().addEventListener 'click', ->
      window.AppAppsHelpers.previewPurge app
    app.el.appsPurgeConfirmInput().addEventListener 'input', ->
      window.AppAppsHelpers.refreshPurgeConfirm app
    app.el.appsPurgeConfirmBtn().addEventListener 'click', ->
      window.AppAppsHelpers.confirmPurge app

