# app_snapshot_helpers.coffee — snapshot import/export helpers extracted from app.coffee

window.AppSnapshotHelpers =
  bindSnapshotPanel: (app) ->
    app._snapshotYaml = null

    doExport = (includeData) ->
      compress = app.el.snapshotCompressCheckbox().checked

      # Build URL for new /export endpoint
      params = new URLSearchParams({
        includeData: includeData,
        compress: compress
      })

      fetch("/export?#{params}", {
        method: 'GET',
        headers: {
          'Authorization': "Bearer #{localStorage.getItem('tdb_token') or ''}"
        }
      }).then (response) ->
        if not response.ok
          throw new Error("Export failed: #{response.statusText}")

        # Get filename from Content-Disposition header
        contentDisposition = response.headers.get('content-disposition')
        filename = 'export'
        if contentDisposition
          filenameMatch = contentDisposition.match(/filename="?([^"]+)"?/)
          filename = filenameMatch[1] if filenameMatch[1]

        # Create blob from response
        response.blob().then (blob) ->
          url = URL.createObjectURL blob
          a = document.createElement 'a'
          a.href = url
          a.download = filename
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

      # Check if file is compressed by extension
      isCompressed = file.name.endsWith('.zst')

      reader.onload = (ev) ->
        content = ev.target.result

        # If file is compressed, we need to decompress it in the browser
        # or send it as-is to the backend which handles decompression
        # For simplicity, we'll send the raw content and let backend handle it
        app._snapshotYaml = content

        GQL.query("""
          query($y: String!) { diffSnapshot(yaml: $y) {
            spacesToCreate spacesToDelete
            fieldsToCreate { space field oldType newType }
            fieldsToDelete { space field oldType newType }
            fieldsToChange { space field oldType newType }
            pagesToCreate pagesToUpdate
            widgetPluginsToCreate widgetPluginsToUpdate
          } }
        """, { y: app._snapshotYaml })
        .then (data) ->
          diff = data.diffSnapshot
          app._renderSnapshotDiff diff
          app.el.snapshotDiffBox().classList.remove 'hidden'
        .catch (err) ->
          app.el.snapshotImportError().textContent = app._err(err)
          app.el.snapshotImportError().classList.remove 'hidden'

      # Read file as text (backend will handle decompression if needed)
      reader.readAsText file

    app.el.snapshotImportConfirmBtn().addEventListener 'click', ->
      return unless app._snapshotYaml
      # Le mode *replace* destructif a été retiré de l'interface (spec §3) :
      # l'import de snapshot ne propose plus que « fusionner ».
      mode = 'merge'
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
        res.innerHTML = ''
        if r.ok
          res.className = 'snapshot-import-result snapshot-result-ok'
          res.textContent = app._t('ui.snapshot.importOk', { created: r.created, skipped: r.skipped })
        else
          res.className = 'snapshot-import-result snapshot-result-err'
          res.textContent = app._t('ui.snapshot.importErr', { created: r.created, skipped: r.skipped })
          for e in (r.errors or [])
            res.appendChild document.createElement 'br'
            codeEl = document.createElement 'code'
            codeEl.textContent = String(e ? '')
            res.appendChild codeEl
        app._loadAll() if r.ok or r.created > 0
      .catch (err) ->
        app.el.snapshotImportConfirmBtn().disabled = false
        app.el.snapshotImportError().textContent = app._err(err)
        app.el.snapshotImportError().classList.remove 'hidden'

  renderSnapshotDiff: (app, diff) ->
    c = app.el.snapshotDiffContent()
    c.innerHTML = ''
    esc = (s) -> window.TdbHtml.escape s
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
          safe = { space: esc(item.space), field: esc(item.field), oldType: esc(item.oldType), newType: esc(item.newType) }
          if item.oldType and item.newType
            li.innerHTML = "<code>#{safe.space}.#{safe.field}</code> : <em>#{safe.oldType}</em> → <strong>#{safe.newType}</strong>"
          else if item.newType
            li.innerHTML = app._t('ui.snapshot.fieldToCreate', safe)
          else
            li.innerHTML = app._t('ui.snapshot.fieldToDelete', safe)
        ul.appendChild li
      c.appendChild ul

    noop = diff.spacesToCreate.length == 0 and diff.spacesToDelete.length == 0 and
           diff.fieldsToCreate.length == 0 and diff.fieldsToDelete.length == 0 and
           diff.fieldsToChange.length == 0 and diff.pagesToCreate.length == 0 and
           diff.pagesToUpdate.length == 0 and
           diff.widgetPluginsToCreate.length == 0 and diff.widgetPluginsToUpdate.length == 0

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
      section app._t('ui.snapshot.sectionPagesCreate'), diff.pagesToCreate, 'diff-list diff-create'
      section app._t('ui.snapshot.sectionPagesUpdate'), diff.pagesToUpdate, 'diff-list diff-change'
      section app._t('ui.snapshot.sectionWidgetPluginsCreate'), diff.widgetPluginsToCreate, 'diff-list diff-create'
      section app._t('ui.snapshot.sectionWidgetPluginsUpdate'), diff.widgetPluginsToUpdate, 'diff-list diff-change'
