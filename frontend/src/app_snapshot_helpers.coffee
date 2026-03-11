# app_snapshot_helpers.coffee — snapshot import/export helpers extracted from app.coffee

window.AppSnapshotHelpers =
  bindSnapshotPanel: (app) ->
    app._snapshotYaml = null

    doExport = (includeData) ->
      GQL.query("""
        query($d: Boolean!) { exportSnapshot(includeData: $d) }
      """, { d: includeData }).then (data) ->
        yaml   = data.exportSnapshot
        fname  = if includeData then 'backup.tdb.yaml' else 'schema.tdb.yaml'
        blob   = new Blob [yaml], { type: 'text/yaml' }
        url    = URL.createObjectURL blob
        a      = document.createElement 'a'
        a.href = url
        a.download = fname
        a.click()
        URL.revokeObjectURL url
      .catch (err) -> tdbAlert app._err(err), 'error'

    app.el.snapshotExportSchemaBtn().addEventListener 'click', -> doExport false
    app.el.snapshotExportFullBtn().addEventListener 'click', -> doExport true

    app.el.snapshotFileInput().addEventListener 'change', (e) ->
      file = e.target.files[0]
      return unless file
      app.el.snapshotFileName().textContent = file.name
      app.el.snapshotDiffBox().classList.add 'hidden'
      app.el.snapshotImportResult().classList.add 'hidden'
      app.el.snapshotImportError().classList.add 'hidden'
      reader = new FileReader()
      reader.onload = (ev) ->
        app._snapshotYaml = ev.target.result
        GQL.query("""
          query($y: String!) { diffSnapshot(yaml: $y) {
            spacesToCreate spacesToDelete
            fieldsToCreate { space field oldType newType }
            fieldsToDelete { space field oldType newType }
            fieldsToChange { space field oldType newType }
            customViewsToCreate customViewsToUpdate
          } }
        """, { y: app._snapshotYaml })
        .then (data) ->
          diff = data.diffSnapshot
          app._renderSnapshotDiff diff
          app.el.snapshotDiffBox().classList.remove 'hidden'
        .catch (err) ->
          app.el.snapshotImportError().textContent = app._err(err)
          app.el.snapshotImportError().classList.remove 'hidden'
      reader.readAsText file

    app.el.snapshotImportConfirmBtn().addEventListener 'click', ->
      return unless app._snapshotYaml
      mode = document.querySelector('input[name="snapshot-mode"]:checked')?.value or 'merge'
      if mode == 'replace'
        unless await tdbConfirm app._t('ui.confirms.replaceImport')
          return
      app.el.snapshotImportConfirmBtn().disabled = true
      GQL.mutate("""
        mutation($y: String!, $m: ImportMode!) {
          importSnapshot(yaml: $y, mode: $m) { ok created skipped errors }
        }
      """, { y: app._snapshotYaml, m: mode })
      .then (data) ->
        r = data.importSnapshot
        app.el.snapshotImportConfirmBtn().disabled = false
        app.el.snapshotDiffBox().classList.add 'hidden'
        res = app.el.snapshotImportResult()
        res.classList.remove 'hidden'
        if r.ok
          res.className = 'snapshot-import-result snapshot-result-ok'
          res.innerHTML = app._t('ui.snapshot.importOk', { created: r.created, skipped: r.skipped })
        else
          res.className = 'snapshot-import-result snapshot-result-err'
          res.innerHTML = app._t('ui.snapshot.importErr', { created: r.created, skipped: r.skipped }) + '<br>' +
            r.errors.map((e) -> "<code>#{e}</code>").join('<br>')
        app._loadAll() if r.ok or r.created > 0
      .catch (err) ->
        app.el.snapshotImportConfirmBtn().disabled = false
        app.el.snapshotImportError().textContent = app._err(err)
        app.el.snapshotImportError().classList.remove 'hidden'

  renderSnapshotDiff: (app, diff) ->
    c = app.el.snapshotDiffContent()
    c.innerHTML = ''
    section = (title, items, cls) ->
      return unless items and items.length > 0
      h = document.createElement 'h5'
      h.textContent = title
      c.appendChild h
      ul = document.createElement 'ul'
      ul.className = cls
      for item in items
        li = document.createElement 'li'
        if typeof item == 'string'
          li.textContent = item
        else
          if item.oldType and item.newType
            li.innerHTML = "<code>#{item.space}.#{item.field}</code> : <em>#{item.oldType}</em> → <strong>#{item.newType}</strong>"
          else if item.newType
            li.innerHTML = app._t('ui.snapshot.fieldToCreate', item)
          else
            li.innerHTML = app._t('ui.snapshot.fieldToDelete', item)
        ul.appendChild li
      c.appendChild ul

    noop = diff.spacesToCreate.length == 0 and diff.spacesToDelete.length == 0 and
           diff.fieldsToCreate.length == 0 and diff.fieldsToDelete.length == 0 and
           diff.fieldsToChange.length == 0 and diff.customViewsToCreate.length == 0 and
           diff.customViewsToUpdate.length == 0

    if noop
      p = document.createElement 'p'
      p.className = 'snapshot-diff-noop'
      p.textContent = app._t('ui.snapshot.noop')
      c.appendChild p
    else
      section app._t('ui.snapshot.sectionSpacesDelete'), diff.spacesToDelete, 'diff-list diff-delete'
      section app._t('ui.snapshot.sectionSpacesCreate'), diff.spacesToCreate, 'diff-list diff-create'
      section app._t('ui.snapshot.sectionFieldsDelete'), diff.fieldsToDelete, 'diff-list diff-delete'
      section app._t('ui.snapshot.sectionFieldsChange'), diff.fieldsToChange, 'diff-list diff-change'
      section app._t('ui.snapshot.sectionFieldsCreate'), diff.fieldsToCreate, 'diff-list diff-create'
      section app._t('ui.snapshot.sectionCustomViewsCreate'), diff.customViewsToCreate, 'diff-list diff-create'
      section app._t('ui.snapshot.sectionCustomViewsUpdate'), diff.customViewsToUpdate, 'diff-list diff-change'
