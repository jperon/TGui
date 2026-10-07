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
      var c, choice, i, len, ref, result;
      result = [];
      ref = conflicts || [];
      for (i = 0, len = ref.length; i < len; i++) {
        c = ref[i];
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
    hasCodeChanges: function(plan) {
      var group, groups, i, item, j, len, len1, t;
      groups = [plan.create || [], plan.update || [], plan.conflict || []];
      for (i = 0, len = groups.length; i < len; i++) {
        group = groups[i];
        for (j = 0, len1 = group.length; j < len1; j++) {
          item = group[j];
          if (item.isCode === true) {
            return true;
          }
          t = item.type;
          if (t === 'plugin' || t === 'page' || t === 'dataview') {
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
      var hasObsolete, i, info, len, list, meta, ref, row;
      app._appList = apps || [];
      list = app.el.appsList();
      window.AppAppsHelpers._clear(list);
      ref = app._appList;
      for (i = 0, len = ref.length; i < len; i++) {
        info = ref[i];
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
    // ── Liaison des évènements ─────────────────────────────────────────────────
    bindAppsPanel: function(app) {
      return app._appList = [];
    }
  };

}).call(this);
