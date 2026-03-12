(function() {
  // app_snapshot_helpers.coffee — snapshot import/export helpers extracted from app.coffee
  window.AppSnapshotHelpers = {
    bindSnapshotPanel: function(app) {
      var doExport;
      app._snapshotYaml = null;
      doExport = function(includeData) {
        return GQL.query(`query($d: Boolean!) { exportSnapshot(includeData: $d) }`, {
          d: includeData
        }).then(function(data) {
          var a, blob, fname, url, yaml;
          yaml = data.exportSnapshot;
          fname = includeData ? 'backup.tdb.yaml' : 'schema.tdb.yaml';
          blob = new Blob([yaml], {
            type: 'text/yaml'
          });
          url = URL.createObjectURL(blob);
          a = document.createElement('a');
          a.href = url;
          a.download = fname;
          a.click();
          return URL.revokeObjectURL(url);
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      };
      app.el.snapshotExportSchemaBtn().addEventListener('click', function() {
        return doExport(false);
      });
      app.el.snapshotExportFullBtn().addEventListener('click', function() {
        return doExport(true);
      });
      app.el.snapshotFileInput().addEventListener('change', function(e) {
        var file, reader;
        file = e.target.files[0];
        if (!file) {
          return;
        }
        app.el.snapshotFileName().textContent = file.name;
        app.el.snapshotDiffBox().classList.add('hidden');
        app.el.snapshotImportResult().classList.add('hidden');
        app.el.snapshotImportError().classList.add('hidden');
        reader = new FileReader();
        reader.onload = function(ev) {
          app._snapshotYaml = ev.target.result;
          return GQL.query(`query($y: String!) { diffSnapshot(yaml: $y) {
  spacesToCreate spacesToDelete
  fieldsToCreate { space field oldType newType }
  fieldsToDelete { space field oldType newType }
  fieldsToChange { space field oldType newType }
  customViewsToCreate customViewsToUpdate
} }`, {
            y: app._snapshotYaml
          }).then(function(data) {
            var diff;
            diff = data.diffSnapshot;
            app._renderSnapshotDiff(diff);
            return app.el.snapshotDiffBox().classList.remove('hidden');
          }).catch(function(err) {
            app.el.snapshotImportError().textContent = app._err(err);
            return app.el.snapshotImportError().classList.remove('hidden');
          });
        };
        return reader.readAsText(file);
      });
      return app.el.snapshotImportConfirmBtn().addEventListener('click', async function() {
        var mode, ref;
        if (!app._snapshotYaml) {
          return;
        }
        mode = ((ref = document.querySelector('input[name="snapshot-mode"]:checked')) != null ? ref.value : void 0) || 'merge';
        if (mode === 'replace') {
          if (!(await tdbConfirm(app._t('ui.confirms.replaceImport')))) {
            return;
          }
        }
        app.el.snapshotImportConfirmBtn().disabled = true;
        return GQL.mutate(`mutation($y: String!, $m: ImportMode!) {
  importSnapshot(yaml: $y, mode: $m) { ok created skipped errors }
}`, {
          y: app._snapshotYaml,
          m: mode
        }).then(function(data) {
          var r, res;
          r = data.importSnapshot;
          app.el.snapshotImportConfirmBtn().disabled = false;
          app.el.snapshotDiffBox().classList.add('hidden');
          res = app.el.snapshotImportResult();
          res.classList.remove('hidden');
          if (r.ok) {
            res.className = 'snapshot-import-result snapshot-result-ok';
            res.innerHTML = app._t('ui.snapshot.importOk', {
              created: r.created,
              skipped: r.skipped
            });
          } else {
            res.className = 'snapshot-import-result snapshot-result-err';
            res.innerHTML = app._t('ui.snapshot.importErr', {
              created: r.created,
              skipped: r.skipped
            }) + '<br>' + r.errors.map(function(e) {
              return `<code>${e}</code>`;
            }).join('<br>');
          }
          if (r.ok || r.created > 0) {
            return app._loadAll();
          }
        }).catch(function(err) {
          app.el.snapshotImportConfirmBtn().disabled = false;
          app.el.snapshotImportError().textContent = app._err(err);
          return app.el.snapshotImportError().classList.remove('hidden');
        });
      });
    },
    renderSnapshotDiff: function(app, diff) {
      var c, esc, noop, p, section;
      c = app.el.snapshotDiffContent();
      c.innerHTML = '';
      esc = function(s) {
        return String(s != null ? s : '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
      };
      section = function(title, items, cls) {
        var h, i, item, len, li, safe, ul;
        if (!(items && items.length > 0)) {
          return;
        }
        h = document.createElement('h5');
        h.textContent = title;
        c.appendChild(h);
        ul = document.createElement('ul');
        ul.className = cls;
        for (i = 0, len = items.length; i < len; i++) {
          item = items[i];
          li = document.createElement('li');
          if (typeof item === 'string') {
            li.textContent = item;
          } else {
            safe = {
              space: esc(item.space),
              field: esc(item.field),
              oldType: esc(item.oldType),
              newType: esc(item.newType)
            };
            if (item.oldType && item.newType) {
              li.innerHTML = `<code>${safe.space}.${safe.field}</code> : <em>${safe.oldType}</em> → <strong>${safe.newType}</strong>`;
            } else if (item.newType) {
              li.innerHTML = app._t('ui.snapshot.fieldToCreate', safe);
            } else {
              li.innerHTML = app._t('ui.snapshot.fieldToDelete', safe);
            }
          }
          ul.appendChild(li);
        }
        return c.appendChild(ul);
      };
      noop = diff.spacesToCreate.length === 0 && diff.spacesToDelete.length === 0 && diff.fieldsToCreate.length === 0 && diff.fieldsToDelete.length === 0 && diff.fieldsToChange.length === 0 && diff.customViewsToCreate.length === 0 && diff.customViewsToUpdate.length === 0;
      if (noop) {
        p = document.createElement('p');
        p.className = 'snapshot-diff-noop';
        p.textContent = app._t('ui.snapshot.noop');
        return c.appendChild(p);
      } else {
        section(app._t('ui.snapshot.sectionSpacesDelete'), diff.spacesToDelete, 'diff-list diff-delete');
        section(app._t('ui.snapshot.sectionSpacesCreate'), diff.spacesToCreate, 'diff-list diff-create');
        section(app._t('ui.snapshot.sectionFieldsDelete'), diff.fieldsToDelete, 'diff-list diff-delete');
        section(app._t('ui.snapshot.sectionFieldsChange'), diff.fieldsToChange, 'diff-list diff-change');
        section(app._t('ui.snapshot.sectionFieldsCreate'), diff.fieldsToCreate, 'diff-list diff-create');
        section(app._t('ui.snapshot.sectionCustomViewsCreate'), diff.customViewsToCreate, 'diff-list diff-create');
        return section(app._t('ui.snapshot.sectionCustomViewsUpdate'), diff.customViewsToUpdate, 'diff-list diff-change');
      }
    }
  };

}).call(this);
