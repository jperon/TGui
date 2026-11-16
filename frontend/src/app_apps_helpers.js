(function() {
  // app_apps_helpers.coffee
  // Interface « Applications » (versionnage des apps).

  // Logique pure testable (isSemver, buildDecisions, confirmationTarget,
  // summarizePlan, hasCodeChanges) séparée du DOM. Tout contenu provenant d'un
  // paquet ou de la base est inséré par textContent / createElement, jamais par
  // innerHTML ni par concaténation de HTML (sécurité, spec §4).
  window.AppAppsHelpers = {
    // ── Fonctions pures ────────────────────────────────────────────────────────

    // x.y.z entièrement numérique (pas de préfixe « v », pas de suffixe).
    isSemver: function(v) {
      return typeof v === 'string' && /^\d+\.\d+\.\d+$/.test(v);
    },
    // conflicts: [{key, ...}] — choices: { key: 'local' | 'delivered' }
    // Retourne [{key, choice}] dans l'ordre des conflits, défaut « local ».
    buildDecisions: function(conflicts, choices) {
      var c, choice, j, len, ref, result;
      result = [];
      ref = conflicts || [];
      for (j = 0, len = ref.length; j < len; j++) {
        c = ref[j];
        choice = (choices || {})[c.key] || 'local';
        result.push({
          key: c.key,
          choice: choice
        });
      }
      return result;
    },
    // Un seul élément sélectionné → partie de la clé après le dernier ':' ;
    // plusieurs → identifiant de l'application.
    confirmationTarget: function(keys, appId) {
      var idx, k, ks;
      ks = keys || [];
      if (ks.length === 1) {
        k = String(ks[0]);
        idx = k.lastIndexOf(':');
        if (idx >= 0) {
          return k.slice(idx + 1);
        } else {
          return k;
        }
      } else {
        return appId;
      }
    },
    // Compteurs du plan.
    summarizePlan: function(plan) {
      return {
        create: (plan.create || []).length,
        update: (plan.update || []).length,
        conflict: (plan.conflict || []).length,
        keepLocal: (plan.keepLocal || []).length,
        obsolete: (plan.obsolete || []).length,
        rename: (plan.rename || []).length,
        unchanged: (plan.unchanged || []).length,
        errors: (plan.errors || []).length
      };
    },
    // Vrai si un élément créé/mis à jour/en conflit porte du code tiers.
    // La liste des types reprend celle du résolveur (CODE_TYPES,
    // backend/resolvers/app_resolvers.moon) : `preset` porte une formule de filtre.
    hasCodeChanges: function(plan) {
      var group, groups, item, j, l, len, len1, t;
      groups = [plan.create || [], plan.update || [], plan.conflict || []];
      for (j = 0, len = groups.length; j < len; j++) {
        group = groups[j];
        for (l = 0, len1 = group.length; l < len1; l++) {
          item = group[l];
          if (item.isCode === true) {
            return true;
          }
          t = item.type;
          if (t === 'plugin' || t === 'page' || t === 'dataview' || t === 'preset') {
            return true;
          }
        }
      }
      return false;
    },
    // ── Aides DOM (jamais d'innerHTML) ─────────────────────────────────────────
    _makeEl: function(tag, className, text) {
      var el;
      el = document.createElement(tag);
      if (className) {
        el.className = className;
      }
      if ((text != null) && text !== null) {
        el.textContent = text;
      }
      return el;
    },
    _clear: function(node) {
      if (!node) {
        return;
      }
      node.textContent = '';
      if (node._children) {
        node._children.length = 0;
      }
      if (node.children) {
        return node.children.length = 0;
      }
    },
    // ── Liste des applications installées ──────────────────────────────────────
    loadApps: function(app) {
      return GQL.query(`{ listApps { appId name version installedAt source activeCount obsoleteCount } }`).then(function(data) {
        return window.AppAppsHelpers.renderAppsList(app, data.listApps);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderAppsList: function(app, apps) {
      var hasObsolete, info, j, len, list, meta, ref, row;
      app._appList = apps || [];
      list = app.el.appsList();
      window.AppAppsHelpers._clear(list);
      ref = app._appList;
      for (j = 0, len = ref.length; j < len; j++) {
        info = ref[j];
        row = window.AppAppsHelpers._makeEl('div', 'apps-list-item');
        row.appendChild(window.AppAppsHelpers._makeEl('div', 'apps-item-name', String(info.name)));
        meta = window.AppAppsHelpers._makeEl('div', 'apps-item-meta');
        meta.appendChild(window.AppAppsHelpers._makeEl('span', null, app._t('ui.apps.version', {
          version: info.version
        })));
        meta.appendChild(window.AppAppsHelpers._makeEl('span', null, ' · '));
        meta.appendChild(window.AppAppsHelpers._makeEl('span', null, app._t('ui.apps.activeCount', {
          count: info.activeCount
        })));
        meta.appendChild(window.AppAppsHelpers._makeEl('span', null, ' · '));
        meta.appendChild(window.AppAppsHelpers._makeEl('span', null, app._t('ui.apps.obsoleteCount', {
          count: info.obsoleteCount
        })));
        row.appendChild(meta);
        list.appendChild(row);
      }
      hasObsolete = app._appList.some(function(a) {
        return (a.obsoleteCount || 0) > 0;
      });
      return app.el.appsPurgeOpenBtn().disabled = !hasObsolete;
    },
    // ── Aperçu d'un paquet (installer / mettre à jour) ─────────────────────────
    previewPackage: function(app, yamlText) {
      app.el.appsApplyBtn().disabled = true;
      app.el.appsApplyReport().classList.add('hidden');
      return GQL.query(`query($y: String!, $d: Boolean) {
  previewAppUpdate(yaml: $y, allowDowngrade: $d) {
    create { key type content fingerprint isCode }
    update { key type content fingerprint isCode }
    conflict { key type local delivered }
    keepLocal { key type content fingerprint isCode }
    obsolete
    rename { from to }
    unchanged
    errors
  }
}`, {
        y: yamlText,
        d: app.el.appsAllowDowngrade().checked
      }).then(function(data) {
        var plan;
        plan = data.previewAppUpdate;
        app._appPlan = plan;
        return window.AppAppsHelpers.renderPlan(app, plan);
      }).catch(function(err) {
        var errEl;
        errEl = app.el.appsPlanErrors();
        window.AppAppsHelpers._clear(errEl);
        errEl.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-plan-error', app._err(err)));
        errEl.classList.remove('hidden');
        return app.el.appsPlanBox().classList.add('hidden');
      });
    },
    renderPlan: function(app, plan) {
      var box, e, errEl, errors, j, len, summary;
      box = app.el.appsPlanBox();
      window.AppAppsHelpers._clear(box);
      box.classList.remove('hidden');
      errors = plan.errors || [];
      if (errors.length > 0) {
        errEl = app.el.appsPlanErrors();
        window.AppAppsHelpers._clear(errEl);
        for (j = 0, len = errors.length; j < len; j++) {
          e = errors[j];
          errEl.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-plan-error', String(e)));
        }
        errEl.classList.remove('hidden');
        app.el.appsApplyBtn().disabled = true;
        return;
      }
      app.el.appsPlanErrors().classList.add('hidden');
      app.el.appsApplyBtn().disabled = false;
      summary = window.AppAppsHelpers.summarizePlan(plan);
      box.appendChild(window.AppAppsHelpers._makeEl('h4', null, app._t('ui.apps.previewTitle')));
      box.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-plan-counts', app._t('ui.apps.counts', summary)));
      if (window.AppAppsHelpers.hasCodeChanges(plan)) {
        box.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-code-warning', app._t('ui.apps.codeWarning')));
      }
      window.AppAppsHelpers._renderItemSection(app, box, 'ui.apps.created', plan.create, 'diff-create');
      window.AppAppsHelpers._renderItemSection(app, box, 'ui.apps.updated', plan.update, 'diff-change');
      window.AppAppsHelpers._renderItemSection(app, box, 'ui.apps.kept', plan.keepLocal, 'apps-kept');
      window.AppAppsHelpers._renderRenames(app, box, plan.rename);
      window.AppAppsHelpers._renderObsolete(app, box, plan.obsolete);
      window.AppAppsHelpers._renderConflicts(app, box, plan.conflict);
      if (summary.unchanged > 0) {
        return box.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-plan-unchanged', app._t('ui.apps.unchanged', {
          count: summary.unchanged
        })));
      }
    },
    _isCodeItem: function(item) {
      return item.isCode === true || item.type === 'plugin' || item.type === 'page' || item.type === 'dataview' || item.type === 'preset';
    },
    _appendItemLabel: function(app, li, item) {
      var details;
      li.appendChild(window.AppAppsHelpers._makeEl('code', null, String(item.key)));
      li.appendChild(window.AppAppsHelpers._makeEl('span', 'apps-item-type', ` (${item.type || ''})`));
      if (!window.AppAppsHelpers._isCodeItem(item)) {
        return;
      }
      li.appendChild(window.AppAppsHelpers._makeEl('span', 'apps-code-badge', app._t('ui.apps.codeBadge')));
      li.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-code-warning', app._t('ui.apps.codeWarning')));
      details = document.createElement('details');
      details.appendChild(window.AppAppsHelpers._makeEl('summary', null, app._t('ui.apps.codeDetails')));
      details.appendChild(window.AppAppsHelpers._makeEl('pre', 'apps-code-content', JSON.stringify(item.content, null, 2)));
      return li.appendChild(details);
    },
    _renderItemSection: function(app, box, titleKey, items, cls) {
      var item, j, len, li, ul;
      items || (items = []);
      if (items.length === 0) {
        return;
      }
      box.appendChild(window.AppAppsHelpers._makeEl('h5', null, app._t(titleKey)));
      ul = window.AppAppsHelpers._makeEl('ul', `diff-list ${cls}`);
      for (j = 0, len = items.length; j < len; j++) {
        item = items[j];
        li = window.AppAppsHelpers._makeEl('li');
        window.AppAppsHelpers._appendItemLabel(app, li, item);
        ul.appendChild(li);
      }
      return box.appendChild(ul);
    },
    _renderRenames: function(app, box, renames) {
      var j, len, li, r, ul;
      renames || (renames = []);
      if (renames.length === 0) {
        return;
      }
      box.appendChild(window.AppAppsHelpers._makeEl('h5', null, app._t('ui.apps.renamed')));
      ul = window.AppAppsHelpers._makeEl('ul', 'diff-list diff-change');
      for (j = 0, len = renames.length; j < len; j++) {
        r = renames[j];
        li = window.AppAppsHelpers._makeEl('li');
        li.appendChild(window.AppAppsHelpers._makeEl('code', null, String(r.from)));
        li.appendChild(window.AppAppsHelpers._makeEl('span', null, ' → '));
        li.appendChild(window.AppAppsHelpers._makeEl('code', null, String(r.to)));
        ul.appendChild(li);
      }
      return box.appendChild(ul);
    },
    _renderObsolete: function(app, box, obsolete) {
      var j, key, len, ul;
      obsolete || (obsolete = []);
      if (obsolete.length === 0) {
        return;
      }
      box.appendChild(window.AppAppsHelpers._makeEl('h5', null, app._t('ui.apps.obsolete')));
      ul = window.AppAppsHelpers._makeEl('ul', 'diff-list diff-delete');
      for (j = 0, len = obsolete.length; j < len; j++) {
        key = obsolete[j];
        ul.appendChild(window.AppAppsHelpers._makeEl('li', null, String(key)));
      }
      return box.appendChild(ul);
    },
    _radio: function(app, parent, name, value, labelText, checked, key) {
      var input, label;
      label = window.AppAppsHelpers._makeEl('label', 'apps-conflict-radio');
      input = document.createElement('input');
      input.type = 'radio';
      input.name = name;
      input.value = value;
      input.checked = checked;
      input.addEventListener('change', function() {
        if (app._appChoices == null) {
          app._appChoices = {};
        }
        return app._appChoices[key] = value;
      });
      label.appendChild(input);
      label.appendChild(window.AppAppsHelpers._makeEl('span', null, ` ${labelText}`));
      return parent.appendChild(label);
    },
    _renderConflicts: function(app, box, conflicts) {
      var c, choice, choices, container, deliveredSide, i, j, len, localSide, name, results, row;
      conflicts || (conflicts = []);
      if (conflicts.length === 0) {
        return;
      }
      box.appendChild(window.AppAppsHelpers._makeEl('h5', null, app._t('ui.apps.conflicts')));
      if (app._appChoices == null) {
        app._appChoices = {};
      }
      results = [];
      for (i = j = 0, len = conflicts.length; j < len; i = ++j) {
        c = conflicts[i];
        container = window.AppAppsHelpers._makeEl('div', 'apps-conflict');
        container.appendChild(window.AppAppsHelpers._makeEl('div', 'apps-conflict-key', String(c.key)));
        if (window.AppAppsHelpers._isCodeItem({
          type: c.type
        })) {
          container.appendChild(window.AppAppsHelpers._makeEl('span', 'apps-code-badge', app._t('ui.apps.codeBadge')));
          container.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-code-warning', app._t('ui.apps.codeWarning')));
        }
        row = window.AppAppsHelpers._makeEl('div', 'apps-conflict-versions');
        localSide = window.AppAppsHelpers._makeEl('div', 'apps-conflict-side');
        localSide.appendChild(window.AppAppsHelpers._makeEl('div', 'apps-conflict-side-title', app._t('ui.apps.localVersion')));
        localSide.appendChild(window.AppAppsHelpers._makeEl('pre', 'apps-conflict-json', JSON.stringify(c['local'], null, 2)));
        deliveredSide = window.AppAppsHelpers._makeEl('div', 'apps-conflict-side');
        deliveredSide.appendChild(window.AppAppsHelpers._makeEl('div', 'apps-conflict-side-title', app._t('ui.apps.deliveredVersion')));
        deliveredSide.appendChild(window.AppAppsHelpers._makeEl('pre', 'apps-conflict-json', JSON.stringify(c.delivered, null, 2)));
        row.appendChild(localSide);
        row.appendChild(deliveredSide);
        container.appendChild(row);
        choices = window.AppAppsHelpers._makeEl('div', 'apps-conflict-choices');
        name = `app-conflict-${i}`;
        choice = app._appChoices[c.key] || 'local';
        window.AppAppsHelpers._radio(app, choices, name, 'local', app._t('ui.apps.keepMine'), choice === 'local', c.key);
        window.AppAppsHelpers._radio(app, choices, name, 'delivered', app._t('ui.apps.takeDelivered'), choice === 'delivered', c.key);
        container.appendChild(choices);
        results.push(box.appendChild(container));
      }
      return results;
    },
    renderApplyReport: function(app, r) {
      var box, parts;
      box = app.el.appsApplyReport();
      window.AppAppsHelpers._clear(box);
      box.classList.remove('hidden');
      box.className = r.ok ? 'snapshot-import-result snapshot-result-ok' : 'snapshot-import-result snapshot-result-err';
      parts = [
        app._t('ui.apps.reportCreated',
        {
          count: (r.created || []).length
        }),
        app._t('ui.apps.reportUpdated',
        {
          count: (r.updated || []).length
        }),
        app._t('ui.apps.reportKept',
        {
          count: (r.kept || []).length
        }),
        app._t('ui.apps.reportObsolete',
        {
          count: (r.obsolete || []).length
        })
      ];
      box.appendChild(window.AppAppsHelpers._makeEl('div', null, parts.join(' · ')));
      if (r.error) {
        return box.appendChild(window.AppAppsHelpers._makeEl('div', 'apps-apply-error', String(r.error)));
      }
    },
    _reloadAppsAndMenu: function(app) {
      if (typeof app._loadApps === "function") {
        app._loadApps();
      }
      return typeof app._loadAll === "function" ? app._loadAll() : void 0;
    },
    applyPackage: function(app) {
      var decisions;
      if (!(app._appPlan && app._appPackageYaml)) {
        return;
      }
      decisions = window.AppAppsHelpers.buildDecisions(app._appPlan.conflict, app._appChoices || {});
      return tdbConfirm(app._t('ui.confirms.appApply')).then(function(ok) {
        if (!ok) {
          return;
        }
        app.el.appsApplyBtn().disabled = true;
        return GQL.mutate(`mutation($y: String!, $dec: [AppDecisionInput!], $d: Boolean) {
  applyAppUpdate(yaml: $y, decisions: $dec, allowDowngrade: $d) {
    ok created updated kept unchanged obsolete skipped error
  }
}`, {
          y: app._appPackageYaml,
          dec: decisions,
          d: app.el.appsAllowDowngrade().checked
        }).then(function(data) {
          var changed, r;
          r = data.applyAppUpdate;
          window.AppAppsHelpers.renderApplyReport(app, r);
          changed = r.ok || (r.created || []).length > 0 || (r.updated || []).length > 0;
          if (changed) {
            return window.AppAppsHelpers._reloadAppsAndMenu(app);
          }
        }).catch(function(err) {
          app.el.appsApplyBtn().disabled = false;
          return tdbAlert(app._err(err), 'error');
        });
      });
    },
    // ── Export d'une application (côté auteur) ─────────────────────────────────
    _download: function(filename, content) {
      var a, blob, url;
      blob = new Blob([content], {
        type: 'text/yaml'
      });
      url = URL.createObjectURL(blob);
      a = document.createElement('a');
      a.href = url;
      a.download = filename;
      a.click();
      return URL.revokeObjectURL(url);
    },
    exportApp: function(app) {
      var description, errEl, id, j, len, line, name, parts, ref, seed, version;
      id = app.el.appsExportId().value.trim();
      name = app.el.appsExportName().value.trim();
      version = app.el.appsExportVersion().value.trim();
      description = app.el.appsExportDescription().value.trim();
      errEl = app.el.appsExportError();
      errEl.classList.add('hidden');
      if (!(id && version)) {
        errEl.textContent = app._t('ui.apps.exportRequired');
        errEl.classList.remove('hidden');
        return;
      }
      if (!window.AppAppsHelpers.isSemver(version)) {
        errEl.textContent = app._t('ui.apps.invalidVersion');
        errEl.classList.remove('hidden');
        return;
      }
      seed = [];
      ref = app.el.appsExportSeed().value.split('\n');
      for (j = 0, len = ref.length; j < len; j++) {
        line = ref[j];
        line = line.trim();
        if (!line) {
          continue;
        }
        parts = line.split(':');
        if (!(parts.length >= 2)) {
          continue;
        }
        seed.push({
          space: parts[0].trim(),
          keyField: parts[1].trim()
        });
      }
      return GQL.query(`query($meta: AppMetaInput!, $seed: [AppSeedInput!]) {
  exportApp(meta: $meta, seed: $seed)
}`, {
        meta: {id, name, version, description},
        seed
      }).then(function(data) {
        return window.AppAppsHelpers._download(`${id}-${version}.tdbapp.yaml`, data.exportApp);
      }).catch(function(err) {
        errEl.textContent = app._err(err);
        return errEl.classList.remove('hidden');
      });
    },
    // ── Purge des éléments obsolètes ───────────────────────────────────────────
    openPurge: function(app) {
      var target;
      target = ((app._appList || []).filter(function(a) {
        return (a.obsoleteCount || 0) > 0;
      }))[0];
      if (!target) {
        return;
      }
      app._appPurgeAppId = target.appId;
      app._appPurgeSelected = [];
      app._appPurgePreview = null;
      app._appPurgeCheckboxes = [];
      app.el.appsPurgeBox().classList.remove('hidden');
      app.el.appsPurgeReport().classList.add('hidden');
      app.el.appsPurgeAppName().textContent = target.name || target.appId;
      window.AppAppsHelpers._resetPurgeConfirm(app);
      return GQL.query(`query($id: String!) { appItems(appId: $id) { key type state version } }`, {
        id: target.appId
      }).then(function(data) {
        return window.AppAppsHelpers.renderPurgeItems(app, data.appItems);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderPurgeItems: function(app, items) {
      var box, cb, item, j, label, len, ref;
      box = app.el.appsPurgeItems();
      window.AppAppsHelpers._clear(box);
      app._appPurgeSelected = [];
      app._appPurgeCheckboxes = [];
      ref = items || [];
      for (j = 0, len = ref.length; j < len; j++) {
        item = ref[j];
        if (!(item.state === 'obsolète' || item.state === 'obsolete')) {
          continue;
        }
        label = window.AppAppsHelpers._makeEl('label', 'apps-purge-item');
        cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.value = item.key;
        cb.addEventListener('change', function() {
          return window.AppAppsHelpers._syncPurgeSelection(app);
        });
        app._appPurgeCheckboxes.push({
          input: cb,
          key: item.key
        });
        label.appendChild(cb);
        label.appendChild(window.AppAppsHelpers._makeEl('span', null, ` ${item.key} (${item.type})`));
        box.appendChild(label);
      }
      return window.AppAppsHelpers._invalidatePurgePreview(app);
    },
    _syncPurgeSelection: function(app) {
      var e;
      app._appPurgeSelected = (function() {
        var j, len, ref, results;
        ref = app._appPurgeCheckboxes || [];
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          e = ref[j];
          if (e.input.checked) {
            results.push(e.key);
          }
        }
        return results;
      })();
      return window.AppAppsHelpers._invalidatePurgePreview(app);
    },
    _invalidatePurgePreview: function(app) {
      app._appPurgePreview = null;
      app.el.appsPurgePreview().classList.add('hidden');
      return window.AppAppsHelpers._resetPurgeConfirm(app);
    },
    _resetPurgeConfirm: function(app) {
      app.el.appsPurgeConfirmInput().value = '';
      app.el.appsPurgeConfirmBtn().disabled = true;
      return app.el.appsPurgeConfirmHint().textContent = '';
    },
    refreshPurgeConfirm: function(app) {
      var input, ok;
      input = app.el.appsPurgeConfirmInput();
      ok = (app._appPurgePreview != null) && input.value === app._appPurgeTarget;
      return app.el.appsPurgeConfirmBtn().disabled = !ok;
    },
    previewPurge: function(app) {
      var keys;
      keys = app._appPurgeSelected || [];
      if (!(keys.length > 0)) {
        tdbAlert(app._t('ui.apps.selectItems'), 'warn');
        return;
      }
      return GQL.query(`query($id: String!, $keys: [String!]!) {
  previewAppPurge(appId: $id, keys: $keys) {
    losses { key type records fields relations views }
    totalRecords
  }
}`, {
        id: app._appPurgeAppId,
        keys: keys
      }).then(function(data) {
        app._appPurgePreview = {
          preview: data.previewAppPurge,
          keys: keys
        };
        return window.AppAppsHelpers.renderPurgePreview(app, data.previewAppPurge);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderPurgePreview: function(app, preview) {
      var box, colKey, cols, hrow, j, l, len, len1, len2, loss, m, ref, table, tbody, thead, tr, v, vals;
      box = app.el.appsPurgePreview();
      window.AppAppsHelpers._clear(box);
      box.classList.remove('hidden');
      box.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-purge-warning', app._t('ui.apps.purgeWarning')));
      table = document.createElement('table');
      table.className = 'apps-purge-loss';
      thead = document.createElement('thead');
      hrow = document.createElement('tr');
      cols = ['ui.apps.colKey', 'ui.apps.colType', 'ui.apps.colRecords', 'ui.apps.colFields', 'ui.apps.colRelations', 'ui.apps.colViews'];
      for (j = 0, len = cols.length; j < len; j++) {
        colKey = cols[j];
        hrow.appendChild(window.AppAppsHelpers._makeEl('th', null, app._t(colKey)));
      }
      thead.appendChild(hrow);
      table.appendChild(thead);
      tbody = document.createElement('tbody');
      ref = preview.losses || [];
      for (l = 0, len1 = ref.length; l < len1; l++) {
        loss = ref[l];
        tr = document.createElement('tr');
        vals = [loss.key, loss.type, loss.records, loss.fields, loss.relations, loss.views];
        for (m = 0, len2 = vals.length; m < len2; m++) {
          v = vals[m];
          tr.appendChild(window.AppAppsHelpers._makeEl('td', null, String(v)));
        }
        tbody.appendChild(tr);
      }
      table.appendChild(tbody);
      box.appendChild(table);
      box.appendChild(window.AppAppsHelpers._makeEl('p', 'apps-purge-total', app._t('ui.apps.purgeTotal', {
        count: preview.totalRecords
      })));
      app._appPurgeTarget = window.AppAppsHelpers.confirmationTarget((app._appPurgePreview || {}).keys || [], app._appPurgeAppId);
      app.el.appsPurgeConfirmHint().textContent = app._t('ui.apps.confirmHint', {
        target: app._appPurgeTarget
      });
      return window.AppAppsHelpers.refreshPurgeConfirm(app);
    },
    confirmPurge: function(app) {
      var input, keys;
      if (!app._appPurgePreview) {
        return;
      }
      input = app.el.appsPurgeConfirmInput();
      if (input.value !== app._appPurgeTarget) {
        return;
      }
      keys = app._appPurgePreview.keys || [];
      return tdbConfirm(app._t('ui.apps.confirmPurge', {
        target: app._appPurgeTarget
      })).then(function(ok) {
        if (!ok) {
          return;
        }
        return GQL.mutate(`mutation($id: String!, $keys: [String!]!, $c: Boolean!) {
  purgeAppObsolete(appId: $id, keys: $keys, confirmed: $c) {
    ok purged error
  }
}`, {
          id: app._appPurgeAppId,
          keys: keys,
          c: true
        }).then(function(data) {
          var r, report;
          r = data.purgeAppObsolete;
          report = app.el.appsPurgeReport();
          window.AppAppsHelpers._clear(report);
          report.classList.remove('hidden');
          report.className = r.ok ? 'snapshot-import-result snapshot-result-ok' : 'snapshot-import-result snapshot-result-err';
          report.textContent = r.ok ? app._t('ui.apps.purgeOk', {
            count: (r.purged || []).length
          }) : app._t('ui.apps.purgeErr', {
            error: r.error || ''
          });
          if (r.ok) {
            app.el.appsPurgeBox().classList.add('hidden');
            return window.AppAppsHelpers._reloadAppsAndMenu(app);
          }
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
    },
    // ── Liaison des évènements ─────────────────────────────────────────────────
    bindAppsPanel: function(app) {
      app._appList = [];
      app._appPackageYaml = null;
      app._appPlan = null;
      app._appChoices = {};
      app._appPurgeAppId = null;
      app._appPurgeSelected = [];
      app._appPurgePreview = null;
      app._appPurgeCheckboxes = [];
      app._appPurgeTarget = '';
      app.el.appsPackageInput().addEventListener('change', function(e) {
        var file, reader;
        file = e.target.files[0];
        if (!file) {
          return;
        }
        app.el.appsPackageName().textContent = file.name;
        app.el.appsPlanBox().classList.add('hidden');
        app.el.appsPlanErrors().classList.add('hidden');
        app.el.appsApplyReport().classList.add('hidden');
        reader = new FileReader();
        reader.onload = function(ev) {
          app._appPackageYaml = ev.target.result;
          app._appChoices = {};
          return window.AppAppsHelpers.previewPackage(app, app._appPackageYaml);
        };
        return reader.readAsText(file);
      });
      app.el.appsAllowDowngrade().addEventListener('change', function() {
        if (!app._appPackageYaml) {
          return;
        }
        return window.AppAppsHelpers.previewPackage(app, app._appPackageYaml);
      });
      app.el.appsApplyBtn().addEventListener('click', function() {
        return window.AppAppsHelpers.applyPackage(app);
      });
      app.el.appsExportBtn().addEventListener('click', function() {
        return window.AppAppsHelpers.exportApp(app);
      });
      app.el.appsPurgeOpenBtn().addEventListener('click', function() {
        return window.AppAppsHelpers.openPurge(app);
      });
      app.el.appsPurgePreviewBtn().addEventListener('click', function() {
        return window.AppAppsHelpers.previewPurge(app);
      });
      app.el.appsPurgeConfirmInput().addEventListener('input', function() {
        return window.AppAppsHelpers.refreshPurgeConfirm(app);
      });
      return app.el.appsPurgeConfirmBtn().addEventListener('click', function() {
        return window.AppAppsHelpers.confirmPurge(app);
      });
    }
  };

}).call(this);
